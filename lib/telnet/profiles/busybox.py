"""BusyBox device profile."""

import re

from lib.telnet.profiles.base import DeviceProfile


class BusyBoxProfile(DeviceProfile):
    """Profile for BusyBox-based devices."""

    name = "busybox"
    description = "BusyBox embedded Linux device"

    def get_prompt_pattern(self) -> str:
        """Get BusyBox prompt pattern.

        Returns
        -------
        str
            Regex pattern for BusyBox prompt
        """
        return r"\[.*\]# |# |\$ "

    def detect(self, client: "TelnetClient") -> bool:
        """Detect BusyBox device.

        Parameters
        ----------
        client : TelnetClient
            Connected telnet client

        Returns
        -------
        bool
            True if device is BusyBox
        """
        try:
            # Check for BusyBox in uname or version
            output = client.execute("uname -a", timeout=5.0)
            if "BusyBox" in output:
                return True

            # Check for BusyBox in /proc/version
            output = client.execute("cat /proc/version 2>/dev/null", timeout=5.0)
            if "BusyBox" in output:
                return True

            # Check for ash shell (common in BusyBox)
            output = client.execute("echo $SHELL", timeout=5.0)
            if "/bin/ash" in output or "/bin/sh" in output:
                # Additional check - BusyBox often has limited commands
                output = client.execute("which ls", timeout=5.0)
                if "/bin/busybox" in output or output.strip() == "":
                    return True

        except Exception:
            pass

        return False

