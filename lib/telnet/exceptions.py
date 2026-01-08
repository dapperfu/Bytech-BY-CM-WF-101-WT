"""Custom exceptions for telnet automation framework."""


class TelnetError(Exception):
    """Base exception for all telnet-related errors."""

    def __init__(self, message: str, device_ip: str | None = None) -> None:
        """Initialize telnet error.

        Parameters
        ----------
        message : str
            Error message
        device_ip : str | None, optional
            Device IP address if applicable, by default None
        """
        super().__init__(message)
        self.message = message
        self.device_ip = device_ip

    def __str__(self) -> str:
        """Return string representation of error."""
        if self.device_ip:
            return f"[{self.device_ip}] {self.message}"
        return self.message


class ConnectionError(TelnetError):
    """Raised when connection to device fails."""

    pass


class AuthenticationError(TelnetError):
    """Raised when authentication fails."""

    pass


class TimeoutError(TelnetError):
    """Raised when operation times out."""

    def __init__(
        self,
        message: str,
        device_ip: str | None = None,
        timeout: float | None = None,
    ) -> None:
        """Initialize timeout error.

        Parameters
        ----------
        message : str
            Error message
        device_ip : str | None, optional
            Device IP address if applicable, by default None
        timeout : float | None, optional
            Timeout value in seconds, by default None
        """
        super().__init__(message, device_ip)
        self.timeout = timeout


class CommandError(TelnetError):
    """Raised when command execution fails."""

    def __init__(
        self,
        message: str,
        device_ip: str | None = None,
        command: str | None = None,
        exit_code: int | None = None,
    ) -> None:
        """Initialize command error.

        Parameters
        ----------
        message : str
            Error message
        device_ip : str | None, optional
            Device IP address if applicable, by default None
        command : str | None, optional
            Command that failed, by default None
        exit_code : int | None, optional
            Command exit code if available, by default None
        """
        super().__init__(message, device_ip)
        self.command = command
        self.exit_code = exit_code

