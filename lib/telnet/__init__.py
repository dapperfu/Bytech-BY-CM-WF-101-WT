"""Telnet automation framework for IoT device management.

This package provides a comprehensive telnet automation framework supporting
both one-time scripts and long-running services with connection pooling.
"""

__version__ = "0.1.0"

from lib.telnet.async_client import AsyncTelnetClient
from lib.telnet.client import TelnetClient
from lib.telnet.exceptions import (
    AuthenticationError,
    CommandError,
    ConnectionError,
    TelnetError,
    TimeoutError,
)
from lib.telnet.pool import ConnectionPool
from lib.telnet.service import TelnetService
from lib.telnet.sync_client import SyncTelnetClient

__all__ = [
    "TelnetClient",
    "SyncTelnetClient",
    "AsyncTelnetClient",
    "ConnectionPool",
    "TelnetService",
    "TelnetError",
    "ConnectionError",
    "AuthenticationError",
    "TimeoutError",
    "CommandError",
]

