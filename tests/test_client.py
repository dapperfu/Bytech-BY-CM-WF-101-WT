"""Tests for telnet client."""

import pytest

from lib.telnet.client import TelnetClient
from lib.telnet.exceptions import AuthenticationError, ConnectionError, TimeoutError
from tests.mock_telnet_server import MockTelnetServer


def test_client_connection(mock_server: MockTelnetServer) -> None:
    """Test client connection."""
    with TelnetClient(
        host="127.0.0.1",
        port=mock_server.actual_port,
        username="test",
        password="test",
        timeout=5.0,
    ) as client:
        assert client.connected


def test_client_authentication_failure() -> None:
    """Test authentication failure."""
    with MockTelnetServer() as server:
        port = server.start()

        with pytest.raises(AuthenticationError):
            client = TelnetClient(
                host="127.0.0.1",
                port=port,
                username="wrong",
                password="wrong",
                timeout=5.0,
            )
            client.connect()


def test_client_execute_command(mock_server: MockTelnetServer) -> None:
    """Test command execution."""
    def command_handler(cmd: str) -> str:
        if cmd == "echo test":
            return "test\n"
        return f"Unknown command: {cmd}\n"

    mock_server.set_command_handler(command_handler)

    with TelnetClient(
        host="127.0.0.1",
        port=mock_server.actual_port,
        username="test",
        password="test",
        timeout=5.0,
    ) as client:
        output = client.execute("echo test")
        assert "test" in output


def test_client_timeout(mock_server: MockTelnetServer) -> None:
    """Test command timeout."""
    def command_handler(cmd: str) -> str:
        import time
        time.sleep(10)  # Simulate slow command
        return "done\n"

    mock_server.set_command_handler(command_handler)

    with TelnetClient(
        host="127.0.0.1",
        port=mock_server.actual_port,
        username="test",
        password="test",
        timeout=1.0,
    ) as client:
        with pytest.raises(TimeoutError):
            client.execute("slow_command", timeout=0.5)


@pytest.fixture
def mock_server() -> MockTelnetServer:
    """Create mock telnet server fixture."""
    server = MockTelnetServer()
    server.start()
    yield server
    server.stop()

