#!/usr/bin/env python3
"""Analyze network connections on device.

Migrated version of analyze-connections.sh.
"""

import re
import sys
from datetime import datetime
from pathlib import Path

# Add lib to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from lib.telnet.cli import common_options, setup_cli_logging
from lib.telnet.logging import log_error, log_info, log_success, log_warn
from lib.telnet.sync_client import SyncTelnetClient
import click


KNOWN_CLOUD_IPS = ["52.42.98.25"]
LOCAL_NETWORK = "10.0.0.0/24"


def is_local_ip(ip: str) -> bool:
    """Check if IP is in local network.

    Parameters
    ----------
    ip : str
        IP address

    Returns
    -------
    bool
        True if local IP
    """
    patterns = [
        r"^127\.",
        r"^10\.",
        r"^192\.168\.",
        r"^172\.(1[6-9]|2[0-9]|3[0-1])\.",
    ]
    return any(re.match(pattern, ip) for pattern in patterns)


def is_cloud_ip(ip: str) -> bool:
    """Check if IP is a cloud/external IP.

    Parameters
    ----------
    ip : str
        IP address

    Returns
    -------
    bool
        True if cloud IP
    """
    if ip in KNOWN_CLOUD_IPS:
        return True
    return not is_local_ip(ip)


def analyze_connections(client: SyncTelnetClient, output_file: str | None = None) -> dict:
    """Analyze network connections.

    Parameters
    ----------
    client : SyncTelnetClient
        Connected telnet client
    output_file : str | None, optional
        Output file path, by default None

    Returns
    -------
    dict
        Analysis results
    """
    log_info("Analyzing network connections...", device_ip=client.host)

    # Get all connections
    try:
        connections_output = client.execute(
            "netstat -anp 2>/dev/null || ss -anp 2>/dev/null", timeout=20.0
        )
    except Exception as e:
        log_error(f"Failed to get connections: {e}", device_ip=client.host)
        connections_output = ""

    # Parse connections
    local_connections = []
    cloud_connections = []
    listening_services = []

    for line in connections_output.split("\n"):
        if not line.strip():
            continue

        # Check for listening services
        if "LISTEN" in line or "LISTENING" in line:
            listening_services.append(line)
            continue

        # Extract remote IP
        parts = line.split()
        if len(parts) < 5:
            continue

        remote_addr = parts[4]
        # Remove port
        remote_ip = re.sub(r":\d+$", "", remote_addr)

        if not remote_ip:
            continue

        if is_cloud_ip(remote_ip):
            cloud_connections.append(line)
        elif is_local_ip(remote_ip):
            local_connections.append(line)

    # Build report
    report_lines = [
        "=== Connection Analysis Report ===",
        f"Target: {client.host}",
        f"Date: {datetime.now().isoformat()}",
        "",
        "=== All Connections ===",
        connections_output,
        "",
        "=== Listening Services ===",
    ]
    report_lines.extend(listening_services)
    report_lines.extend([
        "",
        f"=== Local Network Connections ({LOCAL_NETWORK}) ===",
    ])
    report_lines.extend(local_connections)
    report_lines.extend([
        "",
        "=== Cloud Connections (EXTERNAL) ===",
    ])
    if cloud_connections:
        report_lines.extend(cloud_connections)
    else:
        report_lines.append("No cloud connections detected")

    report = "\n".join(report_lines)

    # Write to file if specified
    if output_file:
        with open(output_file, "w") as f:
            f.write(report)
        log_success(f"Report written to {output_file}", device_ip=client.host)
    else:
        click.echo(report)

    return {
        "total_connections": len(local_connections) + len(cloud_connections),
        "local_connections": len(local_connections),
        "cloud_connections": len(cloud_connections),
        "listening_services": len(listening_services),
    }


@click.command()
@common_options
@click.option(
    "--output",
    "-o",
    type=click.Path(),
    help="Output file path",
)
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
    output: str | None,
) -> None:
    """Analyze network connections on device."""
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
            results = analyze_connections(client, output)

            if json_output:
                import json

                click.echo(json.dumps(results, indent=2))
            else:
                log_success("Connection analysis complete", device_ip=host)

            sys.exit(0)

    except Exception as e:
        log_error(f"Analysis failed: {e}", device_ip=host)
        if json_output:
            import json

            click.echo(json.dumps({"error": str(e), "success": False}))
        else:
            click.echo(f"Error: {e}", err=True)

        sys.exit(1)


if __name__ == "__main__":
    main()

