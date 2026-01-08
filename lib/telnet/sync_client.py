"""Synchronous API wrapper for telnet client."""

import threading
from typing import TYPE_CHECKING

from lib.telnet.client import TelnetClient
from lib.telnet.profiles.base import DeviceProfile

if TYPE_CHECKING:
    from lib.telnet.profiles.registry import ProfileRegistry


class SyncTelnetClient:
    """Synchronous telnet client wrapper.

    Thread-safe wrapper around TelnetClient for use in scripts.
    """

    def __init__(
        self,
        host: str,
        port: int = 23,
        username: str = "root",
        password: str = "",
        timeout: float = 30.0,
        profile: "DeviceProfile | str | None" = None,
    ) -> None:
        """Initialize synchronous telnet client.

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
        self._lock = threading.Lock()

    def connect(self) -> None:
        """Connect to device (thread-safe)."""
        with self._lock:
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
                self._client.connect()
                # Auto-detect profile if not set
                if self.profile is None and self._client.connected:
                    from lib.telnet.profiles.auto_detect import detect_device_profile

                    self.profile = detect_device_profile(self._client)
                    self._client.profile = self.profile

    def execute(
        self,
        command: str,
        timeout: float | None = None,
        expect_prompt: bool = True,
    ) -> str:
        """Execute command (thread-safe).

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
        with self._lock:
            if self._client is None or not self._client.connected:
                raise ConnectionError("Not connected", device_ip=self.host)

            return self._client.execute(command, timeout=timeout, expect_prompt=expect_prompt)

    def disconnect(self) -> None:
        """Disconnect from device (thread-safe)."""
        with self._lock:
            if self._client:
                self._client.disconnect()
                self._client = None

    def reconnect(self) -> None:
        """Reconnect to device (thread-safe)."""
        with self._lock:
            if self._client:
                self._client.reconnect()
            else:
                self.connect()

    @property
    def connected(self) -> bool:
        """Check if connected.

        Returns
        -------
        bool
            True if connected
        """
        with self._lock:
            return self._client is not None and self._client.connected

    def __enter__(self) -> "SyncTelnetClient":
        """Context manager entry."""
        self.connect()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:
        """Context manager exit."""
        self.disconnect()

