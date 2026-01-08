"""Tests for connection pool."""

import asyncio

import pytest

from lib.telnet.pool import ConnectionPool
from tests.mock_telnet_server import MockTelnetServer


@pytest.mark.asyncio
async def test_pool_connect(mock_server: MockTelnetServer) -> None:
    """Test pool connection."""
    pool = ConnectionPool(max_connections=5)
    client = await pool.connect(
        host="127.0.0.1",
        port=mock_server.actual_port,
        username="test",
        password="test",
        timeout=5.0,
    )
    assert client is not None
    assert await client.connected
    await pool.disconnect_all()


@pytest.mark.asyncio
async def test_pool_max_connections(mock_server: MockTelnetServer) -> None:
    """Test pool max connections limit."""
    pool = ConnectionPool(max_connections=2)

    # Connect 2 devices
    await pool.connect("127.0.0.1", port=mock_server.actual_port, username="test", password="test")
    await pool.connect("127.0.0.1", port=mock_server.actual_port, username="test", password="test")

    # Third should fail
    from lib.telnet.exceptions import ConnectionError

    with pytest.raises(ConnectionError):
        await pool.connect("127.0.0.1", port=mock_server.actual_port, username="test", password="test")

    await pool.disconnect_all()


@pytest.mark.asyncio
async def test_pool_reconnect(mock_server: MockTelnetServer) -> None:
    """Test pool reconnection."""
    pool = ConnectionPool(max_connections=5)
    await pool.connect(
        host="127.0.0.1",
        port=mock_server.actual_port,
        username="test",
        password="test",
    )

    # Reconnect
    client = await pool.reconnect("127.0.0.1")
    assert client is not None
    assert await client.connected

    await pool.disconnect_all()


@pytest.fixture
def mock_server() -> MockTelnetServer:
    """Create mock telnet server fixture."""
    server = MockTelnetServer()
    server.start()
    yield server
    server.stop()

