# MITMproxy In-Depth Guide

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Installation and Setup](#installation-and-setup)
4. [Configuration](#configuration)
5. [Local Traffic Redirection](#local-traffic-redirection)
6. [Remote Device Redirection](#remote-device-redirection)
7. [Log Management](#log-management)
8. [Web Interface](#web-interface)
9. [Troubleshooting](#troubleshooting)
10. [Advanced Usage](#advanced-usage)

## Overview

MITMproxy is a powerful tool for intercepting, inspecting, and modifying HTTP/HTTPS traffic. This guide covers using MITMproxy with iptables to transparently redirect all network traffic through the proxy for deep inspection.

### What You Can Do

- **Intercept Traffic**: Capture all HTTP/HTTPS traffic from devices
- **Inspect Requests**: View headers, bodies, and responses
- **Modify Traffic**: Alter requests/responses on the fly
- **Log Everything**: Save all traffic to files for analysis
- **Real-time Monitoring**: Watch traffic as it happens

## Architecture

```
┌─────────────────┐
│  Network Traffic │
└────────┬─────────┘
         │
         ▼
┌─────────────────┐
│  iptables Rules │ (Transparent/Explicit)
│  NAT Table      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   MITMproxy     │
│   Ports:        │
│   - 51820 (WG)  │
│   - 58080 (HTTP)│
│   - 51080 (SOCKS)│
│   - 58081 (Web) │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Log Files      │
│  mitm_logs/     │
└─────────────────┘
```

## Installation and Setup

### Step 1: Create Virtual Environment

The Makefile provides a target to create an isolated Python environment:

```bash
make mitm-venv
```

This will:
- Create a UV virtual environment in `.venv-mitm/`
- Install mitmproxy and dependencies
- Verify installation

**Manual Installation** (if Makefile not available):
```bash
uv venv .venv-mitm
.venv-mitm/bin/pip install mitmproxy
```

### Step 2: Launch MITMproxy

Start MITMproxy with all proxy modes:

```bash
make mitmweb
```

This launches:
- **WireGuard proxy** on port 51820
- **HTTP proxy** on port 58080
- **SOCKS5 proxy** on port 51080
- **Web interface** on port 58081

**Manual Launch**:
```bash
.venv-mitm/bin/mitmweb \
    --mode wireguard@0.0.0.0:51820 \
    --mode regular@0.0.0.0:58080 \
    --mode socks5@0.0.0.0:51080 \
    --web-port 58081 \
    --web-host 0.0.0.0 \
    --save-stream-file mitm_logs/mitm_$(date +%Y%m%d_%H%M%S).log \
    --set block_global=false
```

### Step 3: Verify MITMproxy is Running

Check that MITMproxy is listening:
```bash
netstat -tlnp | grep -E '51820|58080|51080|58081'
```

Or use `ss`:
```bash
ss -tlnp | grep -E '51820|58080|51080|58081'
```

## Configuration

### Makefile Variables

You can customize MITMproxy behavior via Makefile variables:

```bash
# Virtual environment directory
MITM_VENV_DIR=.venv-mitm make mitm-venv

# Log directory
MITM_LOG_DIR=./logs make mitmweb

# Custom ports
MITM_HTTP_PORT=8080 MITM_WEB_PORT=8081 make mitmweb

# Proxy mode (transparent or explicit)
MITM_MODE=explicit scripts/setup-mitm-iptables-local.sh
```

### Default Configuration

- **Virtual Environment**: `.venv-mitm/`
- **Log Directory**: `mitm_logs/`
- **WireGuard Port**: 51820
- **HTTP Port**: 58080
- **SOCKS5 Port**: 51080
- **Web Interface Port**: 58081
- **Proxy Mode**: transparent

## Local Traffic Redirection

### Transparent Mode (Recommended)

Transparent mode automatically intercepts HTTP/HTTPS traffic without requiring application configuration.

#### Setup

1. **Launch MITMproxy** (in one terminal):
   ```bash
   make mitmweb
   ```

2. **Set up iptables** (in another terminal, with root):
   ```bash
   sudo MITM_MODE=transparent scripts/setup-mitm-iptables-local.sh
   ```

#### How It Works

- iptables redirects HTTP (port 80) → MITMproxy (port 58080)
- iptables redirects HTTPS (port 443) → MITMproxy (port 58080)
- MITMproxy handles SSL/TLS termination
- Traffic is logged and can be inspected

#### Verify Rules

```bash
sudo iptables -t nat -L -n -v
```

You should see:
- PREROUTING rules redirecting ports 80/443
- OUTPUT rules redirecting ports 80/443

### Explicit Mode

Explicit mode requires applications to be configured to use the proxy.

#### Setup

```bash
sudo MITM_MODE=explicit scripts/setup-mitm-iptables-local.sh
```

#### Application Configuration

Configure applications to use proxy:
- **HTTP Proxy**: `http://localhost:58080`
- **HTTPS Proxy**: `http://localhost:58080`
- **SOCKS5 Proxy**: `socks5://localhost:51080`

## Remote Device Redirection

Redirect traffic from remote IoT devices through your MITMproxy server.

### Prerequisites

- MITMproxy running on your machine
- Network access to target device
- Telnet/SSH access to device
- iptables available on target device

### Setup

```bash
scripts/setup-mitm-iptables-remote.sh <device-ip> <username> <password> [mitm-server-ip]
```

**Example**:
```bash
scripts/setup-mitm-iptables-remote.sh 10.0.0.227 root hellotuya 10.0.0.1
```

If `mitm-server-ip` is not provided, the script auto-detects it from the device's default gateway.

### How It Works

1. Script connects to device via telnet
2. Sets up iptables DNAT rules on device
3. Redirects device traffic to MITMproxy server
4. MITMproxy intercepts and logs traffic

### Verify Remote Rules

Connect to device and check:
```bash
telnet 10.0.0.227
# After login:
iptables -t nat -L -n -v
```

## Log Management

### Log File Structure

Logs are saved to `mitm_logs/` directory with format:
```
mitm_YYYYMMDD_HHMMSS.log
```

Example: `mitm_20260108_010000.log`

### Log Rotation

MITMproxy automatically rotates logs every hour. Each log file contains:
- 1 hour of traffic
- Binary format (not plain text)
- All HTTP/HTTPS requests and responses

### Viewing Logs in Real-Time

#### Method 1: Tail Latest Log File

```bash
# Find latest log file and tail it
LATEST_LOG=$(ls -t mitm_logs/mitm_*.log | head -1)
tail -f "$LATEST_LOG" | mitmdump --set flow_detail=2 -
```

#### Method 2: Watch All Logs

```bash
# Watch all log files as they're created
tail -f mitm_logs/mitm_*.log | mitmdump --set flow_detail=2 -
```

#### Method 3: Continuous Monitoring Script

Create a script to continuously monitor logs:

```bash
#!/bin/bash
while true; do
    LATEST_LOG=$(ls -t mitm_logs/mitm_*.log 2>/dev/null | head -1)
    if [ -n "$LATEST_LOG" ]; then
        echo "Monitoring: $LATEST_LOG"
        tail -f "$LATEST_LOG" | mitmdump --set flow_detail=2 -
    fi
    sleep 1
done
```

### Analyzing Log Files

#### View Specific Log File

```bash
mitmdump -r mitm_logs/mitm_20260108_010000.log --set flow_detail=2
```

#### Search for Specific Content

```bash
# Find all requests to specific domain
mitmdump -r mitm_logs/mitm_*.log --set flow_detail=2 | grep "example.com"

# Find POST requests
mitmdump -r mitm_logs/mitm_*.log --set flow_detail=2 | grep "POST"
```

#### Export to HAR Format

```bash
mitmdump -r mitm_logs/mitm_20260108_010000.log -s export_har.py > output.har
```

#### Filter by URL Pattern

```bash
mitmdump -r mitm_logs/mitm_*.log --set flow_detail=2 --set view_filter="~u example.com"
```

### Log Analysis Tips

1. **Use flow_detail levels**:
   - `0`: No details
   - `1`: Basic info
   - `2`: Full details (recommended)
   - `3`: Maximum verbosity

2. **Filter by domain**:
   ```bash
   mitmdump -r mitm_logs/mitm_*.log --set view_filter="~d example.com"
   ```

3. **Filter by method**:
   ```bash
   mitmdump -r mitm_logs/mitm_*.log --set view_filter="~m POST"
   ```

4. **Count requests**:
   ```bash
   mitmdump -r mitm_logs/mitm_*.log --set flow_detail=1 | wc -l
   ```

## Web Interface

### Accessing the Interface

Open your browser to: **http://localhost:58081**

### Features

- **Real-time Traffic View**: See requests as they happen
- **Request/Response Inspection**: View headers, bodies, timing
- **Search and Filter**: Find specific requests
- **Export**: Download flows in various formats
- **Replay**: Replay captured requests

### Using the Web Interface

1. **View Flows**: All intercepted traffic appears in the flow list
2. **Inspect Details**: Click on a flow to see full request/response
3. **Search**: Use the search bar to filter flows
4. **Export**: Right-click flows to export
5. **Replay**: Right-click to replay requests

### Keyboard Shortcuts

- `?`: Show help
- `f`: Focus search
- `q`: Quit
- `↑↓`: Navigate flows
- `Enter`: Inspect flow

## Troubleshooting

### Problem: No Traffic Appearing

**Check iptables rules**:
```bash
sudo iptables -t nat -L -n -v
```

**Verify MITMproxy is running**:
```bash
ps aux | grep mitmweb
```

**Check network interface**:
```bash
ip route | grep default
```

**Solution**: Ensure iptables rules are applied and MITMproxy is running.

### Problem: Can't Access Web Interface

**Check firewall**:
```bash
sudo ufw status
sudo iptables -L -n | grep 58081
```

**Verify MITMproxy is listening**:
```bash
netstat -tlnp | grep 58081
```

**Solution**: Open port 58081 or disable firewall temporarily.

### Problem: SSL/TLS Errors

**Install MITMproxy certificate**:
1. Access http://mitm.it in browser
2. Download certificate for your platform
3. Install certificate in system/browser

**For command-line tools**:
```bash
export REQUESTS_CA_BUNDLE=~/.mitmproxy/mitmproxy-ca-cert.pem
```

### Problem: Logs Not Rotating

**Check log directory**:
```bash
ls -lh mitm_logs/
```

**Verify MITMproxy is running**:
```bash
ps aux | grep mitmweb
```

**Solution**: MITMproxy rotates logs hourly. Check that the process is still running.

### Problem: Remote Device Not Redirecting

**Verify device can reach MITMproxy server**:
```bash
# On device
ping <mitm-server-ip>
telnet <mitm-server-ip> 58080
```

**Check remote iptables rules**:
```bash
# Connect to device and check
iptables -t nat -L -n -v
```

**Solution**: Ensure device can reach MITMproxy server and iptables rules are applied.

## Advanced Usage

### Custom Scripts

Create custom Python scripts to modify traffic:

```python
# modify_request.py
def request(flow):
    if "example.com" in flow.request.pretty_host:
        flow.request.headers["X-Custom-Header"] = "value"
```

Run with:
```bash
mitmweb -s modify_request.py
```

### Filtering Traffic

Use view filters in web interface:
- `~u example.com`: Filter by URL
- `~d example.com`: Filter by domain
- `~m POST`: Filter by method
- `~c 200`: Filter by status code

### Performance Tuning

**Increase buffer sizes**:
```bash
mitmweb --set stream_large_bodies=1m
```

**Limit connections**:
```bash
mitmweb --set connection_strategy=lazy
```

### Integration with Other Tools

**Export to Wireshark**:
```bash
mitmdump -r mitm_logs/mitm_*.log -w output.pcap
```

**Export to JSON**:
```bash
mitmdump -r mitm_logs/mitm_*.log -s export_json.py > output.json
```

## Cleanup

### Remove iptables Rules

**Local cleanup**:
```bash
make mitm-clean
```

Or manually:
```bash
sudo iptables -t nat -F PREROUTING
sudo iptables -t nat -F OUTPUT
```

**Remote cleanup**:
```bash
scripts/cleanup-mitm-iptables.sh <device-ip> <username> <password>
```

### Stop MITMproxy

Press `Ctrl+C` in the terminal running MITMproxy, or:
```bash
pkill -f mitmweb
```

## Best Practices

1. **Use isolated network**: Test in isolated network environment
2. **Monitor resources**: MITMproxy can use significant resources
3. **Rotate logs**: Clean up old log files regularly
4. **Secure access**: Restrict web interface access if on network
5. **Document findings**: Keep notes on interesting traffic patterns

## Related Documentation

- [MITMproxy Quick Start](mitmproxy-quick-start.md)
- [Network Exposure](network-exposure.md)
- [Security Methodology](methodology.md)

