"""Standard Linux device profile."""

import re

from lib.telnet.profiles.base import DeviceProfile


class LinuxProfile(DeviceProfile):
    """Profile for standard Linux systems."""

    name = "linux"
    description = "Standard Linux system (bash/sh)"

    def get_prompt_pattern(self) -> str:
        """Get Linux prompt pattern.

        Returns
        -------
        str
            Regex pattern for Linux prompt
        """
        return r"\[.*\]# |# |\$ "

    def detect(self, client: "TelnetClient") -> bool:
        """Detect standard Linux device.

        Parameters
        ----------
        client : TelnetClient
            Connected telnet client

        Returns
        -------
        bool
            True if device is standard Linux
        """
        try:
            # Check for Linux in uname
            output = client.execute("uname -a", timeout=5.0)
            if "Linux" in output and "BusyBox" not in output:
                return True

            # Check for bash shell
            output = client.execute("echo $SHELL", timeout=5.0)
            if "/bin/bash" in output:
                return True

            # Check for standard Linux directories
            output = client.execute("ls -d /usr /var /etc 2>/dev/null", timeout=5.0)
            if "/usr" in output and "/var" in output:
                return True

        except Exception:
            pass

        return False

