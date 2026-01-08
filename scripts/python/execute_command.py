#!/usr/bin/env python3
"""Execute command on device via telnet.

Python equivalent of execute_command() function from expect scripts.
"""

import sys
from pathlib import Path

# Add lib to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from lib.telnet.cli import common_options, setup_cli_logging
from lib.telnet.logging import log_error, log_info, log_success
from lib.telnet.sync_client import SyncTelnetClient
import click


@click.command()
@common_options
@click.argument("command", required=True)
def main(
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
    """Execute a command on a device via telnet.

    COMMAND: Command to execute
    """
    setup_cli_logging(verbose, quiet, json_output)

    try:
        log_info(f"Connecting to {host}:{port}", device_ip=host)
        with SyncTelnetClient(
            host=host,
            port=port,
            username=username,
            password=password,
            timeout=timeout,
            profile=profile,
        ) as client:
            log_info(f"Executing command: {command}", device_ip=host)
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

            log_success(f"Command executed successfully", device_ip=host)
            sys.exit(0)

    except Exception as e:
        log_error(f"Command execution failed: {e}", device_ip=host)
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


if __name__ == "__main__":
    main()

