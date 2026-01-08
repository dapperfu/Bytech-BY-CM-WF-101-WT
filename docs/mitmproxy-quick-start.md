# MITMproxy Quick Start Guide

## Overview

This guide shows you how to quickly set up MITMproxy to intercept and inspect all network traffic using iptables redirection.

## Prerequisites

- Root/sudo access (for iptables)
- UV package manager installed
- Network access to target device (for remote setup)

## Quick Setup (5 Steps)

### 1. Create Virtual Environment
```bash
make mitm-venv
```

### 2. Launch MITMproxy
```bash
make mitmweb
```
This starts MITMproxy with all proxy modes. Keep this terminal open.

### 3. Set Up iptables Rules (Local)
In a new terminal with root access:
```bash
sudo MITM_MODE=transparent scripts/setup-mitm-iptables-local.sh
```

### 4. Access Web Interface
Open your browser to: **http://localhost:58081**

### 5. Watch Logs
Logs are saved to `mitm_logs/` directory. To watch them in real-time:
```bash
tail -f mitm_logs/mitm_*.log | mitmdump --set flow_detail=2 -
```

## Cleanup

When done, remove iptables rules:
```bash
make mitm-clean
```

## Remote Device Setup

To redirect traffic from a remote IoT device:

```bash
scripts/setup-mitm-iptables-remote.sh <device-ip> <username> <password> [mitm-server-ip]
```

Example:
```bash
scripts/setup-mitm-iptables-remote.sh 10.0.0.227 root hellotuya
```

## Viewing Logs

### Real-time Log Viewing
```bash
# Watch latest log file
tail -f mitm_logs/mitm_*.log | mitmdump --set flow_detail=2 -

# Or use mitmdump directly on log file
mitmdump -r mitm_logs/mitm_20260108_010000.log --set flow_detail=2
```

### Analyze Specific Log File
```bash
mitmdump -r mitm_logs/mitm_YYYYMMDD_HHMMSS.log --set flow_detail=2
```

## Common Issues

**Problem**: Can't access web interface
- **Solution**: Check firewall, ensure port 58081 is open

**Problem**: No traffic appearing
- **Solution**: Verify iptables rules are applied: `sudo iptables -t nat -L -n -v`

**Problem**: Logs not rotating
- **Solution**: MITMproxy rotates logs hourly automatically

## Next Steps

For detailed information, see [MITMproxy In-Depth Guide](mitmproxy-in-depth.md).

