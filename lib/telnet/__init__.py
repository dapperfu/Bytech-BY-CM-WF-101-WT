"""Telnet automation framework for IoT device management.

This package provides a comprehensive telnet automation framework supporting
both one-time scripts and long-running services with connection pooling.
"""

__version__ = "0.1.0"

from lib.telnet.exceptions import (
    TelnetError,
    ConnectionError,
    AuthenticationError,
    TimeoutError,
    CommandError,
)

__all__ = [
    "TelnetError",
    "ConnectionError",
    "AuthenticationError",
    "TimeoutError",
    "CommandError",
]

