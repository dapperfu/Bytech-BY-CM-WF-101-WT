"""Device profile registry."""

from typing import TYPE_CHECKING

from lib.telnet.profiles.auto_detect import detect_device_profile
from lib.telnet.profiles.base import DeviceProfile
from lib.telnet.profiles.busybox import BusyBoxProfile
from lib.telnet.profiles.custom import CustomProfile
from lib.telnet.profiles.linux import LinuxProfile

if TYPE_CHECKING:
    from lib.telnet.client import TelnetClient

# Registry of available profiles
_PROFILE_REGISTRY: dict[str, type[DeviceProfile]] = {
    "busybox": BusyBoxProfile,
    "linux": LinuxProfile,
    "custom": CustomProfile,
}


class ProfileRegistry:
    """Registry for device profiles."""

    @staticmethod
    def register(name: str, profile_class: type[DeviceProfile]) -> None:
        """Register a device profile.

        Parameters
        ----------
        name : str
            Profile name
        profile_class : type[DeviceProfile]
            Profile class
        """
        _PROFILE_REGISTRY[name] = profile_class

    @staticmethod
    def get(name: str) -> DeviceProfile:
        """Get a profile by name.

        Parameters
        ----------
        name : str
            Profile name

        Returns
        -------
        DeviceProfile
            Profile instance

        Raises
        ------
        ValueError
            If profile not found
        """
        if name not in _PROFILE_REGISTRY:
            raise ValueError(f"Unknown profile: {name}")

        profile_class = _PROFILE_REGISTRY[name]
        return profile_class()

    @staticmethod
    def list_profiles() -> list[str]:
        """List all registered profile names.

        Returns
        -------
        list[str]
            List of profile names
        """
        return list(_PROFILE_REGISTRY.keys())


def get_profile(
    name: str | None = None,
    client: "TelnetClient | None" = None,
) -> DeviceProfile:
    """Get device profile by name or auto-detect.

    Parameters
    ----------
    name : str | None, optional
        Profile name, by default None (auto-detect)
    client : TelnetClient | None, optional
        Connected client for auto-detection, by default None

    Returns
    -------
    DeviceProfile
        Device profile

    Raises
    ------
    ValueError
        If name specified but not found, or auto-detect requested without client
    """
    if name:
        return ProfileRegistry.get(name)

    if not client:
        raise ValueError("Either name or client must be provided")

    return detect_device_profile(client)

