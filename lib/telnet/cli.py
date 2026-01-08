"""Click-based CLI framework for telnet scripts."""

import sys
from typing import Any, Callable

import click

from lib.telnet.logging import setup_logging
from lib.telnet.sync_client import SyncTelnetClient


def common_options(func: Callable[..., Any]) -> Callable[..., Any]:
    """Decorator for common CLI options.

    Parameters
    ----------
    func : Callable[..., Any]
        Function to decorate

    Returns
    -------
    Callable[..., Any]
        Decorated function
    """
    func = click.option(
        "--target",
        "-t",
        "host",
        required=True,
        help="Target device IP address",
    )(func)
    func = click.option(
        "--username",
        "-u",
        default="root",
        help="Username for authentication",
    )(func)
    func = click.option(
        "--password",
        "-p",
        default="",
        help="Password for authentication",
    )(func)
    func = click.option(
        "--port",
        default=23,
        type=int,
        help="Telnet port",
    )(func)
    func = click.option(
        "--timeout",
        default=30.0,
        type=float,
        help="Command timeout in seconds",
    )(func)
    func = click.option(
        "--profile",
        help="Device profile name (busybox, linux, custom)",
    )(func)
    func = click.option(
        "--json",
        "json_output",
        is_flag=True,
        help="Output in JSON format",
    )(func)
    func = click.option(
        "--verbose",
        "-v",
        is_flag=True,
        help="Verbose output",
    )(func)
    func = click.option(
        "--quiet",
        "-q",
        is_flag=True,
        help="Quiet output (errors only)",
    )(func)
    return func


def setup_cli_logging(verbose: bool, quiet: bool, json_output: bool) -> None:
    """Set up logging for CLI.

    Parameters
    ----------
    verbose : bool
        Enable verbose logging
    quiet : bool
        Enable quiet logging
    json_output : bool
        Enable JSON output
    """
    import logging

    if quiet:
        level = logging.ERROR
    elif verbose:
        level = logging.DEBUG
    else:
        level = logging.INFO

    setup_logging(level=level, json_output=json_output)


@click.group()
@click.version_option(version="0.1.0")
def cli() -> None:
    """Telnet automation framework CLI."""
    pass


@cli.command()
@common_options
@click.argument("command", required=True)
def execute(
    host: str,
    username: str,
    password: str,
    port: int,
    timeout: float,
    profile: str | None,
    json_output: bool,
    verbose: bool,
    quiet: bool,
    command: str,
) -> None:
    """Execute a command on a device.

    COMMAND: Command to execute
    """
    setup_cli_logging(verbose, quiet, json_output)

    try:
        with SyncTelnetClient(
            host=host,
            port=port,
            username=username,
            password=password,
            timeout=timeout,
            profile=profile,
        ) as client:
            output = client.execute(command, timeout=timeout)

            if json_output:
                import json

                result = {
                    "host": host,
                    "command": command,
                    "output": output,
                    "success": True,
                }
                click.echo(json.dumps(result))
            else:
                click.echo(output)

            sys.exit(0)

    except Exception as e:
        if json_output:
            import json

            result = {
                "host": host,
                "command": command,
                "error": str(e),
                "success": False,
            }
            click.echo(json.dumps(result))
        else:
            click.echo(f"Error: {e}", err=True)

        sys.exit(1)


@cli.command()
@common_options
@click.option(
    "--output",
    "-o",
    type=click.Path(),
    help="Output file path",
)
def shell(
    host: str,
    username: str,
    password: str,
    port: int,
    timeout: float,
    profile: str | None,
    json_output: bool,
    verbose: bool,
    quiet: bool,
    output: str | None,
) -> None:
    """Open interactive shell session."""
    setup_cli_logging(verbose, quiet, json_output)

    try:
        with SyncTelnetClient(
            host=host,
            port=port,
            username=username,
            password=password,
            timeout=timeout,
            profile=profile,
        ) as client:
            click.echo(f"Connected to {host}. Type 'exit' to disconnect.")

            output_file = None
            if output:
                output_file = open(output, "w")

            try:
                while True:
                    try:
                        cmd = click.prompt("", default="", show_default=False)
                        if not cmd or cmd.lower() == "exit":
                            break

                        result = client.execute(cmd, timeout=timeout)
                        click.echo(result)

                        if output_file:
                            output_file.write(f"{cmd}\n{result}\n\n")
                            output_file.flush()

                    except KeyboardInterrupt:
                        break
                    except Exception as e:
                        click.echo(f"Error: {e}", err=True)

            finally:
                if output_file:
                    output_file.close()

            sys.exit(0)

    except Exception as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)


if __name__ == "__main__":
    cli()

