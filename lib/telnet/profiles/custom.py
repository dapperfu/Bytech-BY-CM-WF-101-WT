"""Custom/unknown device profile."""

from lib.telnet.profiles.base import DeviceProfile


class CustomProfile(DeviceProfile):
    """Profile for unknown/custom devices."""

    name = "custom"
    description = "Custom/unknown device type"

    def __init__(self, prompt_pattern: str | None = None) -> None:
        """Initialize custom profile.

        Parameters
        ----------
        prompt_pattern : str | None, optional
            Custom prompt pattern, by default None (auto-detect)
        """
        super().__init__()
        self._prompt_pattern = prompt_pattern

    def get_prompt_pattern(self) -> str:
        """Get custom prompt pattern.

        Returns
        -------
        str
            Regex pattern for custom prompt
        """
        if self._prompt_pattern:
            return self._prompt_pattern
        # Default fallback
        return r"# |\$ |> "

    def detect(self, client: "TelnetClient") -> bool:
        """Custom profile always matches (fallback).

        Parameters
        ----------
        client : TelnetClient
            Connected telnet client

        Returns
        -------
        bool
            Always True (fallback profile)
        """
        return True

