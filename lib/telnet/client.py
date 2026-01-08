"""Core telnet client using pexpect."""

import re
import time
from typing import TYPE_CHECKING

import pexpect

from lib.telnet.exceptions import (
    AuthenticationError,
    CommandError,
    ConnectionError,
    TelnetError,
    TimeoutError,
)

if TYPE_CHECKING:
    from lib.telnet.profiles.base import DeviceProfile


class TelnetClient:
    """Core telnet client for device interaction."""

    def __init__(
        self,
        host: str,
        port: int = 23,
        username: str = "root",
        password: str = "",
        timeout: float = 30.0,
        profile: "DeviceProfile | None" = None,
    ) -> None:
        """Initialize telnet client.

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
        profile : DeviceProfile | None, optional
            Device profile for prompt detection, by default None
        """
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.timeout = timeout
        self.profile = profile
        self.process: pexpect.spawn | None = None
        self.connected = False
        self.prompt_pattern: str | None = None

    def connect(self) -> None:
        """Connect to telnet device and authenticate.

        Raises
        ------
        ConnectionError
            If connection fails
        AuthenticationError
            If authentication fails
        TimeoutError
            If connection times out
        """
        try:
            cmd = f"telnet {self.host} {self.port}"
            self.process = pexpect.spawn(cmd, timeout=self.timeout, encoding="utf-8")
            self.process.logfile_read = None  # Disable logging by default

            # Wait for connection
            index = self.process.expect(
                [
                    pexpect.TIMEOUT,
                    "Connected",
                    "Escape character",
                    "login:",
                    "Login:",
                    "Username:",
                    "Password:",
                    "password:",
                    "BusyBox",
                    r"\[.*\]# ",
                    r"# ",
                    r"\$ ",
                ],
                timeout=self.timeout,
            )

            if index == 0:
                raise ConnectionError(
                    f"Connection timeout after {self.timeout}s",
                    device_ip=self.host,
                )

            # Handle authentication
            self._authenticate()

            # Detect prompt pattern
            self._detect_prompt()

            self.connected = True

        except pexpect.TIMEOUT as e:
            raise TimeoutError(
                f"Connection timeout: {str(e)}",
                device_ip=self.host,
                timeout=self.timeout,
            ) from e
        except pexpect.EOF as e:
            raise ConnectionError(
                f"Connection closed: {str(e)}",
                device_ip=self.host,
            ) from e
        except Exception as e:
            if isinstance(e, (ConnectionError, AuthenticationError, TimeoutError)):
                raise
            raise ConnectionError(
                f"Connection failed: {str(e)}",
                device_ip=self.host,
            ) from e

    def _authenticate(self) -> None:
        """Handle authentication sequence.

        Raises
        ------
        AuthenticationError
            If authentication fails
        """
        max_attempts = 10
        attempt = 0

        while attempt < max_attempts:
            try:
                index = self.process.expect(
                    [
                        pexpect.TIMEOUT,
                        "login:",
                        "Login:",
                        "Username:",
                        "Password:",
                        "password:",
                        "BusyBox",
                        r"\[.*\]# ",
                        r"# ",
                        r"\$ ",
                    ],
                    timeout=5.0,
                )

            except pexpect.TIMEOUT:
                attempt += 1
                continue
            except pexpect.EOF:
                raise AuthenticationError(
                    "Connection closed during authentication",
                    device_ip=self.host,
                )

            if index in [1, 2, 3]:  # login:, Login:, Username:
                self.process.sendline(self.username)
                attempt += 1
                continue

            if index in [4, 5]:  # Password:, password:
                self.process.sendline(self.password)
                attempt += 1
                continue

            if index in [6, 7, 8, 9]:  # BusyBox or prompt
                # Already authenticated or no auth needed
                return

            if index == 0:  # TIMEOUT
                attempt += 1
                continue

        raise AuthenticationError(
            "Authentication failed: max attempts reached",
            device_ip=self.host,
        )

    def _detect_prompt(self) -> None:
        """Detect shell prompt pattern.

        Uses device profile if available, otherwise auto-detects.
        """
        if self.profile:
            self.prompt_pattern = self.profile.get_prompt_pattern()
            return

        # Auto-detect prompt
        try:
            # Send a harmless command to get prompt
            self.process.sendline("echo PROMPT_TEST")
            self.process.expect([r"\[.*\]# ", r"# ", r"\$ ", "PROMPT_TEST"], timeout=2.0)

            # Common prompt patterns
            patterns = [
                r"\[.*\]# ",  # [user@host]#
                r"# ",  # root#
                r"\$ ",  # user$
            ]

            for pattern in patterns:
                if re.search(pattern, self.process.before + self.process.after):
                    self.prompt_pattern = pattern
                    return

            # Default pattern
            self.prompt_pattern = r"# |\$ "

        except Exception:
            # Fallback to default
            self.prompt_pattern = r"# |\$ "

    def execute(
        self,
        command: str,
        timeout: float | None = None,
        expect_prompt: bool = True,
    ) -> str:
        """Execute command on device.

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
        CommandError
            If command execution fails
        TimeoutError
            If command times out
        """
        if not self.connected or not self.process:
            raise ConnectionError("Not connected to device", device_ip=self.host)

        cmd_timeout = timeout if timeout is not None else self.timeout

        try:
            # Send command
            self.process.sendline(command)

            if not expect_prompt:
                # Just wait a bit for output
                time.sleep(0.5)
                return self.process.before + self.process.after

            # Wait for prompt
            if self.prompt_pattern:
                patterns = [self.prompt_pattern, pexpect.TIMEOUT, pexpect.EOF]
            else:
                patterns = [r"\[.*\]# ", r"# ", r"\$ ", pexpect.TIMEOUT, pexpect.EOF]

            index = self.process.expect(patterns, timeout=cmd_timeout)

            if index == len(patterns) - 2:  # TIMEOUT
                # Try to recover
                self.process.send("\x03")  # Ctrl+C
                self.process.expect(patterns, timeout=2.0)
                raise TimeoutError(
                    f"Command timeout: {command}",
                    device_ip=self.host,
                    timeout=cmd_timeout,
                )

            if index == len(patterns) - 1:  # EOF
                raise ConnectionError(
                    "Connection closed during command execution",
                    device_ip=self.host,
                )

            # Extract output (remove command echo and prompt)
            output = self.process.before + self.process.after
            # Remove command echo
            output = re.sub(rf"^{re.escape(command)}\r\n", "", output, flags=re.MULTILINE)
            # Remove prompt
            if self.prompt_pattern:
                output = re.sub(rf"{self.prompt_pattern}$", "", output, flags=re.MULTILINE)

            return output.strip()

        except pexpect.TIMEOUT as e:
            raise TimeoutError(
                f"Command timeout: {command}",
                device_ip=self.host,
                timeout=cmd_timeout,
            ) from e
        except pexpect.EOF as e:
            raise ConnectionError(
                "Connection closed during command execution",
                device_ip=self.host,
            ) from e
        except (TimeoutError, ConnectionError):
            raise
        except Exception as e:
            raise CommandError(
                f"Command execution failed: {str(e)}",
                device_ip=self.host,
                command=command,
            ) from e

    def disconnect(self) -> None:
        """Disconnect from device."""
        if self.process:
            try:
                self.process.sendline("exit")
                self.process.expect([pexpect.EOF, pexpect.TIMEOUT], timeout=2.0)
            except Exception:
                pass
            finally:
                self.process.close()
                self.process = None
                self.connected = False

    def reconnect(self) -> None:
        """Reconnect to device."""
        self.disconnect()
        time.sleep(1.0)  # Brief delay before reconnecting
        self.connect()

    def __enter__(self) -> "TelnetClient":
        """Context manager entry."""
        self.connect()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:
        """Context manager exit."""
        self.disconnect()

