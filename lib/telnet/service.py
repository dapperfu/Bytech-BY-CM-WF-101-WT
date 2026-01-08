"""Long-running telnet service with connection pool management."""

import asyncio
import signal
from typing import TYPE_CHECKING

from lib.telnet.config import TelnetConfig
from lib.telnet.logging import get_logger, log_error, log_info, log_success
from lib.telnet.pool import ConnectionPool

if TYPE_CHECKING:
    from lib.telnet.profiles.base import DeviceProfile


class TelnetService:
    """Long-running telnet service managing connection pool."""

    def __init__(self, config: TelnetConfig | None = None) -> None:
        """Initialize telnet service.

        Parameters
        ----------
        config : TelnetConfig | None, optional
            Service configuration, by default None (loads from config)
        """
        from lib.telnet.config import TelnetConfig, load_config

        self.config = config or load_config()
        self.pool = ConnectionPool(
            max_connections=self.config.service.max_connections,
            health_check_interval=self.config.service.health_check_interval,
            reconnect_delay=self.config.service.reconnect_delay,
            health_check_timeout=self.config.service.health_check_timeout,
        )
        self._running = False
        self._shutdown_event = asyncio.Event()
        self.logger = get_logger()

    async def start(self) -> None:
        """Start the service."""
        if self._running:
            return

        log_info("Starting telnet service...")
        self._running = True
        self._shutdown_event.clear()

        # Set up signal handlers
        loop = asyncio.get_event_loop()
        for sig in (signal.SIGTERM, signal.SIGINT):
            loop.add_signal_handler(sig, self._signal_handler)

        log_success("Telnet service started")

    async def stop(self) -> None:
        """Stop the service."""
        if not self._running:
            return

        log_info("Stopping telnet service...")
        self._running = False
        self._shutdown_event.set()

        # Stop health checks and disconnect all
        await self.pool.stop_health_checks()
        await self.pool.disconnect_all()

        log_success("Telnet service stopped")

    def _signal_handler(self) -> None:
        """Handle shutdown signals."""
        asyncio.create_task(self.stop())

    async def connect_device(
        self,
        host: str,
        port: int | None = None,
        username: str | None = None,
        password: str | None = None,
        timeout: float | None = None,
        profile: "DeviceProfile | str | None" = None,
    ) -> None:
        """Connect a device to the pool.

        Parameters
        ----------
        host : str
            Device host IP
        port : int | None, optional
            Telnet port, uses config default if None, by default None
        username : str | None, optional
            Username, uses config default if None, by default None
        password : str | None, optional
            Password, uses config default if None, by default None
        timeout : float | None, optional
            Timeout, uses config default if None, by default None
        profile : DeviceProfile | str | None, optional
            Device profile, by default None
        """
        device_config = self.config.get_device_config(host)

        await self.pool.connect(
            host=host,
            port=port or device_config.port,
            username=username or device_config.username,
            password=password or device_config.password,
            timeout=timeout or device_config.timeout,
            profile=profile or device_config.profile,
        )

    async def execute_command(
        self,
        host: str,
        command: str,
        timeout: float | None = None,
    ) -> str:
        """Execute command on device.

        Parameters
        ----------
        host : str
            Device host IP
        command : str
            Command to execute
        timeout : float | None, optional
            Command timeout, by default None

        Returns
        -------
        str
            Command output

        Raises
        ------
        ConnectionError
            If device not in pool
        """
        client = await self.pool.get(host)
        if not client:
            from lib.telnet.exceptions import ConnectionError

            raise ConnectionError(f"Device {host} not in pool", device_ip=host)

        return await client.execute(command, timeout=timeout)

    async def get_status(self) -> dict:
        """Get service status.

        Returns
        -------
        dict
            Service status
        """
        pool_status = await self.pool.get_status()
        return {
            "running": self._running,
            "pool": pool_status,
        }

    async def run(self) -> None:
        """Run the service (blocking)."""
        await self.start()
        try:
            await self._shutdown_event.wait()
        except KeyboardInterrupt:
            pass
        finally:
            await self.stop()

