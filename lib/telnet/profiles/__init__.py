"""Device profiles for different IoT device types."""

from lib.telnet.profiles.base import DeviceProfile
from lib.telnet.profiles.busybox import BusyBoxProfile
from lib.telnet.profiles.custom import CustomProfile
from lib.telnet.profiles.linux import LinuxProfile
from lib.telnet.profiles.registry import ProfileRegistry, get_profile

__all__ = [
    "DeviceProfile",
    "BusyBoxProfile",
    "LinuxProfile",
    "CustomProfile",
    "ProfileRegistry",
    "get_profile",
]

