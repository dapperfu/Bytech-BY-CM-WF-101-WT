"""Auto-detection logic for device profiles."""

from lib.telnet.profiles.base import DeviceProfile
from lib.telnet.profiles.busybox import BusyBoxProfile
from lib.telnet.profiles.custom import CustomProfile
from lib.telnet.profiles.linux import LinuxProfile


def detect_device_profile(client: "TelnetClient") -> DeviceProfile:
    """Auto-detect device profile from connection.

    Parameters
    ----------
    client : TelnetClient
        Connected telnet client

    Returns
    -------
    DeviceProfile
        Detected device profile
    """
    profiles: list[DeviceProfile] = [
        BusyBoxProfile(),
        LinuxProfile(),
    ]

    # Try each profile in order
    for profile in profiles:
        try:
            if profile.detect(client):
                return profile
        except Exception:
            # Continue to next profile on error
            continue

    # Fallback to custom profile
    return CustomProfile()

