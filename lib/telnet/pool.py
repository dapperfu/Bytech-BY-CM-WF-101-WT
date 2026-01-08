"""Connection pool for managing multiple device connections."""

import asyncio
import time
from typing import TYPE_CHECKING

from lib.telnet.async_client import AsyncTelnetClient
from lib.telnet.exceptions import ConnectionError, TelnetError

if TYPE_CHECKING:
    from lib.telnet.profiles.base import DeviceProfile


class ConnectionPool:
    """Connection pool for managing multiple device connections.

    Provides persistent connections with automatic reconnection and health checks.
    """

    def __init__(
        self,
        max_connections: int = 10,
        health_check_interval: float = 30.0,
        reconnect_delay: float = 2.0,
        health_check_timeout: float = 5.0,
    ) -> None:
        """Initialize connection pool.

        Parameters
        ----------
        max_connections : int, optional
            Maximum number of concurrent connections, by default 10
        health_check_interval : float, optional
            Interval between health checks in seconds, by default 30.0
        reconnect_delay : float, optional
            Delay before reconnecting in seconds, by default 2.0
        health_check_timeout : float, optional
            Timeout for health checks in seconds, by default 5.0
        """
        self.max_connections = max_connections
        self.health_check_interval = health_check_interval
        self.reconnect_delay = reconnect_delay
        self.health_check_timeout = health_check_timeout

        self._connections: dict[str, AsyncTelnetClient] = {}
        self._connection_info: dict[str, dict] = {}  # Metadata for each connection
        self._lock = asyncio.Lock()
        self._health_check_task: asyncio.Task | None = None
        self._running = False

    async def connect(
        self,
        host: str,
        port: int = 23,
        username: str = "root",
        password: str = "",
        timeout: float = 30.0,
        profile: "DeviceProfile | str | None" = None,
    ) -> AsyncTelnetClient:
        """Connect to a device and add to pool.

        Parameters
        ----------
        host : str
            Target host IP address
        port : int, optional
            Telnet port, by default 23
        username : str, optional
            Username for authentication, by default "root"
        password : str, optional
            Password for authentication, by default ""
        timeout : float, optional
            Connection timeout in seconds, by default 30.0
        profile : DeviceProfile | str | None, optional
            Device profile or profile name, by default None

        Returns
        -------
        AsyncTelnetClient
            Connected client

        Raises
        ------
        ConnectionError
            If pool is full or connection fails
        """
        async with self._lock:
            if len(self._connections) >= self.max_connections:
                raise ConnectionError(
                    f"Connection pool full (max {self.max_connections})",
                    device_ip=host,
                )

            if host in self._connections:
                # Return existing connection
                client = self._connections[host]
                # Check if still connected
                if await client.connected:
                    return client
                # Remove stale connection
                del self._connections[host]
                if host in self._connection_info:
                    del self._connection_info[host]

            # Create new connection
            client = AsyncTelnetClient(
                host=host,
                port=port,
                username=username,
                password=password,
                timeout=timeout,
                profile=profile,
            )

            try:
                await client.connect()
            except Exception as e:
                raise ConnectionError(
                    f"Failed to connect: {str(e)}",
                    device_ip=host,
                ) from e

            # Store connection
            self._connections[host] = client
            self._connection_info[host] = {
                "port": port,
                "username": username,
                "password": password,
                "timeout": timeout,
                "profile": profile,
                "connected_at": time.time(),
                "last_health_check": time.time(),
                "reconnect_count": 0,
            }

            # Start health check task if not running
            if not self._running:
                self._start_health_checks()

            return client

    async def get(self, host: str) -> AsyncTelnetClient | None:
        """Get connection from pool.

        Parameters
        ----------
        host : str
            Device host IP

        Returns
        -------
        AsyncTelnetClient | None
            Client if connected, None otherwise
        """
        async with self._lock:
            return self._connections.get(host)

    async def disconnect(self, host: str) -> None:
        """Disconnect device and remove from pool.

        Parameters
        ----------
        host : str
            Device host IP
        """
        async with self._lock:
            if host in self._connections:
                client = self._connections[host]
                try:
                    await client.disconnect()
                except Exception:
                    pass
                del self._connections[host]
            if host in self._connection_info:
                del self._connection_info[host]

    async def disconnect_all(self) -> None:
        """Disconnect all devices in pool."""
        async with self._lock:
            hosts = list(self._connections.keys())
            for host in hosts:
                await self.disconnect(host)

    async def reconnect(self, host: str) -> AsyncTelnetClient:
        """Reconnect a device in the pool.

        Parameters
        ----------
        host : str
            Device host IP

        Returns
        -------
        AsyncTelnetClient
            Reconnected client

        Raises
        ------
        ConnectionError
            If device not in pool or reconnection fails
        """
        async with self._lock:
            if host not in self._connection_info:
                raise ConnectionError(
                    f"Device {host} not in pool",
                    device_ip=host,
                )

            info = self._connection_info[host]
            await self.disconnect(host)

            # Wait before reconnecting
            await asyncio.sleep(self.reconnect_delay)

            # Reconnect with same parameters
            client = await self.connect(
                host=host,
                port=info["port"],
                username=info["username"],
                password=info["password"],
                timeout=info["timeout"],
                profile=info["profile"],
            )

            info["reconnect_count"] += 1
            return client

    async def health_check(self, host: str) -> bool:
        """Perform health check on a connection.

        Parameters
        ----------
        host : str
            Device host IP

        Returns
        -------
        bool
            True if connection is healthy
        """
        client = await self.get(host)
        if not client:
            return False

        try:
            # Try a simple command
            await asyncio.wait_for(
                client.execute("echo health_check", timeout=self.health_check_timeout),
                timeout=self.health_check_timeout + 1.0,
            )
            if host in self._connection_info:
                self._connection_info[host]["last_health_check"] = time.time()
            return True
        except Exception:
            return False

    async def _health_check_loop(self) -> None:
        """Background task for periodic health checks."""
        while self._running:
            try:
                await asyncio.sleep(self.health_check_interval)

                async with self._lock:
                    hosts = list(self._connections.keys())

                for host in hosts:
                    is_healthy = await self.health_check(host)
                    if not is_healthy:
                        # Try to reconnect
                        try:
                            await self.reconnect(host)
                        except Exception:
                            # Remove if reconnection fails
                            await self.disconnect(host)

            except asyncio.CancelledError:
                break
            except Exception:
                # Continue on error
                continue

    def _start_health_checks(self) -> None:
        """Start health check background task."""
        if self._running:
            return

        self._running = True
        self._health_check_task = asyncio.create_task(self._health_check_loop())

    async def stop_health_checks(self) -> None:
        """Stop health check background task."""
        self._running = False
        if self._health_check_task:
            self._health_check_task.cancel()
            try:
                await self._health_check_task
            except asyncio.CancelledError:
                pass

    async def get_status(self) -> dict:
        """Get pool status.

        Returns
        -------
        dict
            Pool status information
        """
        async with self._lock:
            return {
                "total_connections": len(self._connections),
                "max_connections": self.max_connections,
                "connections": {
                    host: {
                        "connected": await client.connected,
                        "info": self._connection_info.get(host, {}),
                    }
                    for host, client in self._connections.items()
                },
                "health_check_running": self._running,
            }

    async def __aenter__(self) -> "ConnectionPool":
        """Async context manager entry."""
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb) -> None:
        """Async context manager exit."""
        await self.stop_health_checks()
        await self.disconnect_all()

