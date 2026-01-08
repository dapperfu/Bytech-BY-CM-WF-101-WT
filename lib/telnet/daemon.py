"""CLI daemon for background telnet service."""

import asyncio
import os
import sys
from pathlib import Path

import click

from lib.telnet.api.app import create_app
from lib.telnet.config import load_config
from lib.telnet.logging import setup_logging
from lib.telnet.service import TelnetService

# PID file location
PID_FILE = Path("/tmp/telnet-service.pid")


def is_running() -> bool:
    """Check if service is running.

    Returns
    -------
    bool
        True if service is running
    """
    if not PID_FILE.exists():
        return False

    try:
        pid = int(PID_FILE.read_text().strip())
        os.kill(pid, 0)  # Check if process exists
        return True
    except (OSError, ValueError):
        # Process doesn't exist, remove stale PID file
        PID_FILE.unlink(missing_ok=True)
        return False


def save_pid(pid: int) -> None:
    """Save process ID to file.

    Parameters
    ----------
    pid : int
        Process ID
    """
    PID_FILE.write_text(str(pid))


def remove_pid() -> None:
    """Remove PID file."""
    PID_FILE.unlink(missing_ok=True)


def get_pid() -> int | None:
    """Get process ID from file.

    Returns
    -------
    int | None
        Process ID if available
    """
    if not PID_FILE.exists():
        return None

    try:
        return int(PID_FILE.read_text().strip())
    except (ValueError, OSError):
        return None


@click.group()
def cli() -> None:
    """Telnet service daemon management."""
    pass


@cli.command()
def start() -> None:
    """Start the telnet service daemon."""
    if is_running():
        click.echo("Service is already running", err=True)
        sys.exit(1)

    click.echo("Starting telnet service daemon...")

    # Fork to background
    pid = os.fork()
    if pid > 0:
        # Parent process
        save_pid(pid)
        click.echo(f"Service started with PID {pid}")
        sys.exit(0)

    # Child process - daemon
    os.setsid()
    os.chdir("/")

    # Redirect stdio
    sys.stdin.close()
    sys.stdout.close()
    sys.stderr.close()

    # Run service
    config = load_config()
    setup_logging(
        level=getattr(__import__("logging"), config.log_level),
        json_output=config.log_json,
        log_file=config.log_file or "/tmp/telnet-service.log",
    )

    service = TelnetService(config=config)
    asyncio.run(service.run())


@cli.command()
def stop() -> None:
    """Stop the telnet service daemon."""
    if not is_running():
        click.echo("Service is not running", err=True)
        sys.exit(1)

    pid = get_pid()
    if pid:
        try:
            os.kill(pid, 15)  # SIGTERM
            click.echo(f"Stopped service (PID {pid})")
            remove_pid()
        except OSError as e:
            click.echo(f"Failed to stop service: {e}", err=True)
            sys.exit(1)


@cli.command()
def status() -> None:
    """Get service status."""
    if is_running():
        pid = get_pid()
        click.echo(f"Service is running (PID {pid})")
    else:
        click.echo("Service is not running")


@cli.command()
def restart() -> None:
    """Restart the telnet service daemon."""
    if is_running():
        stop()
        import time

        time.sleep(1)
    start()


@cli.command()
def run() -> None:
    """Run service in foreground (for testing)."""
    config = load_config()
    setup_logging(
        level=getattr(__import__("logging"), config.log_level),
        json_output=config.log_json,
        log_file=config.log_file,
    )

    service = TelnetService(config=config)

    try:
        asyncio.run(service.run())
    except KeyboardInterrupt:
        click.echo("\nShutting down...")


def main() -> None:
    """Main entry point."""
    cli()


if __name__ == "__main__":
    main()

