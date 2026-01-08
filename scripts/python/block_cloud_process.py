#!/usr/bin/env python3
"""Block cloud communication at process level.

Migrated version of block-cloud-process.sh.
"""

import sys
from pathlib import Path

# Add lib to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from lib.telnet.cli import common_options, setup_cli_logging
from lib.telnet.logging import log_error, log_info, log_success, log_warn
from lib.telnet.sync_client import SyncTelnetClient
import click


APOLLO_BINARY = "/app/abin/apollo"
APOLLO_STARTUP = "/app/start.sh"


def backup_startup_script(client: SyncTelnetClient) -> str | None:
    """Backup startup script.

    Parameters
    ----------
    client : SyncTelnetClient
        Connected telnet client

    Returns
    -------
    str | None
        Backup file path if successful, None otherwise
    """
    log_info("Backing up startup script...", device_ip=client.host)

    from datetime import datetime

    backup_file = f"/tmp/start.sh.backup-{datetime.now().strftime('%Y%m%d_%H%M%S')}"

    try:
        result = client.execute(
            f"cp {APOLLO_STARTUP} {backup_file} 2>/dev/null && echo 'backup_ok' || echo 'backup_failed'",
            timeout=15.0,
        )

        if "backup_ok" in result:
            log_success(f"Startup script backed up to: {backup_file}", device_ip=client.host)
            return backup_file
        else:
            log_warn("Startup script not found or backup failed", device_ip=client.host)
            return None

    except Exception as e:
        log_warn(f"Backup failed: {e}", device_ip=client.host)
        return None


def disable_apollo_startup(client: SyncTelnetClient) -> bool:
    """Disable apollo in startup script.

    Parameters
    ----------
    client : SyncTelnetClient
        Connected telnet client

    Returns
    -------
    bool
        True if successful
    """
    log_info("Disabling apollo in startup script...", device_ip=client.host)

    try:
        # Check if startup script exists
        result = client.execute(
            f"test -f {APOLLO_STARTUP} && echo 'exists' || echo 'not found'",
            timeout=10.0,
        )

        if "not found" in result:
            log_warn(f"Startup script not found at {APOLLO_STARTUP}", device_ip=client.host)
            return False

        # Comment out apollo startup lines
        log_info("Commenting out apollo startup lines...", device_ip=client.host)
        client.execute(
            f"sed -i 's|^.*apollo|# &|g' {APOLLO_STARTUP} 2>/dev/null || sed 's|^.*apollo|# &|g' {APOLLO_STARTUP} > {APOLLO_STARTUP}.new && mv {APOLLO_STARTUP}.new {APOLLO_STARTUP}",
            timeout=15.0,
        )

        log_success("Apollo startup disabled in startup script", device_ip=client.host)
        return True

    except Exception as e:
        log_error(f"Failed to disable apollo startup: {e}", device_ip=client.host)
        return False


def stop_apollo(client: SyncTelnetClient) -> None:
    """Stop apollo process if running.

    Parameters
    ----------
    client : SyncTelnetClient
        Connected telnet client
    """
    log_info("Stopping apollo process if running...", device_ip=client.host)

    try:
        client.execute("killall apollo 2>/dev/null || true", timeout=10.0)
        import time

        time.sleep(2)
        log_success("Apollo process stopped", device_ip=client.host)
    except Exception as e:
        log_warn(f"Failed to stop apollo: {e}", device_ip=client.host)


@click.command()
@common_options
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
) -> None:
    """Block cloud communication at process level."""
    setup_cli_logging(verbose, quiet, json_output)

    try:
        log_info(f"Starting process-level cloud blocking on {host}", device_ip=host)

        with SyncTelnetClient(
            host=host,
            port=port,
            username=username,
            password=password,
            timeout=timeout,
            profile=profile,
        ) as client:
            # Backup startup script
            backup_file = backup_startup_script(client)

            # Disable apollo startup
            disable_apollo_startup(client)

            # Stop apollo if running
            stop_apollo(client)

            if backup_file:
                log_info(f"Backup file: {backup_file}", device_ip=host)

            log_success("Process-level cloud blocking complete!", device_ip=host)
            log_info(
                "Note: Apollo startup has been disabled. Monitor for any restart attempts.",
                device_ip=host,
            )

            if json_output:
                import json

                click.echo(
                    json.dumps(
                        {
                            "success": True,
                            "backup_file": backup_file,
                            "message": "Cloud blocking enabled",
                        }
                    )
                )

            sys.exit(0)

    except Exception as e:
        log_error(f"Blocking failed: {e}", device_ip=host)
        if json_output:
            import json

            click.echo(json.dumps({"error": str(e), "success": False}))
        else:
            click.echo(f"Error: {e}", err=True)

        sys.exit(1)


if __name__ == "__main__":
    main()

