"""Integration tests with real devices.

These tests require actual telnet-accessible devices.
Mark with @pytest.mark.integration to run separately.
"""

import pytest

from lib.telnet.sync_client import SyncTelnetClient


@pytest.mark.integration
def test_real_device_connection() -> None:
    """Test connection to real device.

    Requires TELNET_TEST_HOST environment variable.
    """
    import os

    host = os.getenv("TELNET_TEST_HOST")
    if not host:
        pytest.skip("TELNET_TEST_HOST not set")

    username = os.getenv("TELNET_TEST_USERNAME", "root")
    password = os.getenv("TELNET_TEST_PASSWORD", "")

    with SyncTelnetClient(host=host, username=username, password=password) as client:
        output = client.execute("echo test")
        assert "test" in output


@pytest.mark.integration
@pytest.mark.slow
def test_real_device_multiple_commands() -> None:
    """Test multiple commands on real device."""
    import os

    host = os.getenv("TELNET_TEST_HOST")
    if not host:
        pytest.skip("TELNET_TEST_HOST not set")

    username = os.getenv("TELNET_TEST_USERNAME", "root")
    password = os.getenv("TELNET_TEST_PASSWORD", "")

    with SyncTelnetClient(host=host, username=username, password=password) as client:
        # Execute multiple commands
        commands = ["uname -a", "whoami", "pwd"]
        for cmd in commands:
            output = client.execute(cmd)
            assert output  # Should have some output

