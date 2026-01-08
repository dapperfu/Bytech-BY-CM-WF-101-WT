"""Tests for device profiles."""

import pytest

from lib.telnet.client import TelnetClient
from lib.telnet.profiles.auto_detect import detect_device_profile
from lib.telnet.profiles.busybox import BusyBoxProfile
from lib.telnet.profiles.linux import LinuxProfile
from lib.telnet.profiles.registry import ProfileRegistry
from tests.mock_telnet_server import MockTelnetServer


def test_profile_registry() -> None:
    """Test profile registry."""
    profile = ProfileRegistry.get("busybox")
    assert isinstance(profile, BusyBoxProfile)

    profile = ProfileRegistry.get("linux")
    assert isinstance(profile, LinuxProfile)

    with pytest.raises(ValueError):
        ProfileRegistry.get("unknown")


def test_busybox_profile() -> None:
    """Test BusyBox profile."""
    profile = BusyBoxProfile()
    assert profile.name == "busybox"
    pattern = profile.get_prompt_pattern()
    assert "# " in pattern or "$ " in pattern


def test_linux_profile() -> None:
    """Test Linux profile."""
    profile = LinuxProfile()
    assert profile.name == "linux"
    pattern = profile.get_prompt_pattern()
    assert "# " in pattern or "$ " in pattern


def test_auto_detect(mock_server: MockTelnetServer) -> None:
    """Test auto-detection."""
    def command_handler(cmd: str) -> str:
        if cmd == "uname -a":
            return "Linux test 5.4.0 #1 SMP\n"
        return ""

    mock_server.set_command_handler(command_handler)

    with TelnetClient(
        host="127.0.0.1",
        port=mock_server.actual_port,
        username="test",
        password="test",
        timeout=5.0,
    ) as client:
        profile = detect_device_profile(client)
        # Should detect Linux (not BusyBox)
        assert profile.name in ["linux", "custom"]


@pytest.fixture
def mock_server() -> MockTelnetServer:
    """Create mock telnet server fixture."""
    server = MockTelnetServer()
    server.start()
    yield server
    server.stop()

