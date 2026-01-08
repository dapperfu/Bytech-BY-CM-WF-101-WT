"""Asynchronous API wrapper for telnet client."""

import asyncio
from concurrent.futures import ThreadPoolExecutor
from typing import TYPE_CHECKING

from lib.telnet.client import TelnetClient
from lib.telnet.profiles.base import DeviceProfile

if TYPE_CHECKING:
    from lib.telnet.profiles.registry import ProfileRegistry


class AsyncTelnetClient:
    """Asynchronous telnet client wrapper.

    Non-blocking wrapper around TelnetClient using asyncio.
    """

    def __init__(
        self,
        host: str,
        port: int = 23,
        username: str = "root",
        password: str = "",
        timeout: float = 30.0,
        profile: "DeviceProfile | str | None" = None,
        executor: ThreadPoolExecutor | None = None,
    ) -> None:
        """Initialize asynchronous telnet client.

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
            Device profile or profile name, by default None (auto-detect)
        executor : ThreadPoolExecutor | None, optional
            Thread pool executor for running blocking operations, by default None
        """
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.timeout = timeout

        # Resolve profile
        if isinstance(profile, str):
            from lib.telnet.profiles.registry import ProfileRegistry

            self.profile = ProfileRegistry.get(profile)
        else:
            self.profile = profile

        self._client: TelnetClient | None = None
        self._executor = executor or ThreadPoolExecutor(max_workers=1)
        self._lock = asyncio.Lock()

    async def connect(self) -> None:
        """Connect to device (async, thread-safe)."""
        async with self._lock:
            if self._client is None:
                self._client = TelnetClient(
                    host=self.host,
                    port=self.port,
                    username=self.username,
                    password=self.password,
                    timeout=self.timeout,
                    profile=self.profile,
                )
            if not self._client.connected:
                loop = asyncio.get_event_loop()
                await loop.run_in_executor(self._executor, self._client.connect)
                # Auto-detect profile if not set
                if self.profile is None and self._client.connected:
                    from lib.telnet.profiles.auto_detect import detect_device_profile

                    self.profile = await loop.run_in_executor(
                        self._executor,
                        detect_device_profile,
                        self._client,
                    )
                    self._client.profile = self.profile

    async def execute(
        self,
        command: str,
        timeout: float | None = None,
        expect_prompt: bool = True,
    ) -> str:
        """Execute command (async, thread-safe).

        Parameters
        ----------
        command : str
            Command to execute
        timeout : float | None, optional
            Command timeout, uses default if None, by default None
        expect_prompt : bool, optional
            Whether to wait for prompt after command, by default True

        Returns
        -------
        str
            Command output

        Raises
        ------
        ConnectionError
            If not connected
        """
        async with self._lock:
            if self._client is None or not self._client.connected:
                from lib.telnet.exceptions import ConnectionError

                raise ConnectionError("Not connected", device_ip=self.host)

            loop = asyncio.get_event_loop()
            return await loop.run_in_executor(
                self._executor,
                self._client.execute,
                command,
                timeout,
                expect_prompt,
            )

    async def disconnect(self) -> None:
        """Disconnect from device (async, thread-safe)."""
        async with self._lock:
            if self._client:
                loop = asyncio.get_event_loop()
                await loop.run_in_executor(self._executor, self._client.disconnect)
                self._client = None

    async def reconnect(self) -> None:
        """Reconnect to device (async, thread-safe)."""
        async with self._lock:
            if self._client:
                loop = asyncio.get_event_loop()
                await loop.run_in_executor(self._executor, self._client.reconnect)
            else:
                await self.connect()

    @property
    async def connected(self) -> bool:
        """Check if connected (async).

        Returns
        -------
        bool
            True if connected
        """
        async with self._lock:
            return self._client is not None and self._client.connected

    async def __aenter__(self) -> "AsyncTelnetClient":
        """Async context manager entry."""
        await self.connect()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb) -> None:
        """Async context manager exit."""
        await self.disconnect()

