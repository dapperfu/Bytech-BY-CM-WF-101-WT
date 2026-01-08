"""FastAPI REST API for telnet device management."""

from lib.telnet.api.app import create_app, main

__all__ = ["create_app", "main"]

