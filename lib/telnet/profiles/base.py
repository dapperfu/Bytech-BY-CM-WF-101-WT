"""Base device profile class."""

from abc import ABC, abstractmethod
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from lib.telnet.client import TelnetClient


class DeviceProfile(ABC):
    """Base class for device profiles."""

    name: str = "unknown"
    description: str = "Unknown device type"

    @abstractmethod
    def get_prompt_pattern(self) -> str:
        """Get regex pattern for shell prompt.

        Returns
        -------
        str
            Regex pattern matching the device's shell prompt
        """
        pass

    @abstractmethod
    def detect(self, client: "TelnetClient") -> bool:
        """Detect if this profile matches the device.

        Parameters
        ----------
        client : TelnetClient
            Connected telnet client

        Returns
        -------
        bool
            True if this profile matches the device
        """
        pass

    def get_login_prompts(self) -> list[str]:
        """Get list of login prompt patterns.

        Returns
        -------
        list[str]
            List of login prompt patterns to match
        """
        return ["login:", "Login:", "Username:"]

    def get_password_prompts(self) -> list[str]:
        """Get list of password prompt patterns.

        Returns
        -------
        list[str]
            List of password prompt patterns to match
        """
        return ["Password:", "password:"]

