"""Device profiles for different IoT device types."""

from lib.telnet.profiles.base import DeviceProfile
from lib.telnet.profiles.registry import ProfileRegistry, get_profile

__all__ = [
    "DeviceProfile",
    "ProfileRegistry",
    "get_profile",
]

