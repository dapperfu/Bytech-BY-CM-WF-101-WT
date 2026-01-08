---
name: MITMproxy iptables integration
overview: Create MITMproxy virtual environment setup, mitmweb launch target with all proxy modes, and iptables scripts to redirect traffic through MITMproxy in both transparent and explicit modes for local and remote scenarios.
todos:
  - id: save_plan
    content: Save plan to plans/ directory
    status: pending
  - id: update_makefile
    content: Add mitm-venv, mitmweb, and mitm-clean targets to Makefile with configuration variables
    status: pending
    dependencies:
      - save_plan
  - id: create_local_iptables_script
    content: Create scripts/setup-mitm-iptables-local.sh for local traffic redirection with transparent and explicit modes
    status: pending
    dependencies:
      - save_plan
  - id: create_remote_iptables_script
    content: Create scripts/setup-mitm-iptables-remote.sh for remote device traffic redirection
    status: pending
    dependencies:
      - save_plan
  - id: create_cleanup_script
    content: Create scripts/cleanup-mitm-iptables.sh to remove iptables rules and stop processes
    status: pending
    dependencies:
      - save_plan
  - id: test_venv_creation
    content: Test mitm-venv target creates virtual environment and installs mitmproxy
    status: pending
    dependencies:
      - update_makefile
  - id: test_mitmweb_launch
    content: Test mitmweb target launches all proxy modes correctly
    status: pending
    dependencies:
      - update_makefile
  - id: test_iptables_rules
    content: Test iptables scripts apply and remove rules correctly
    status: pending
    dependencies:
      - create_local_iptables_script
      - create_remote_iptables_script
      - create_cleanup_script
---

# MITMprox

y Integration with iptables Traffic Redirection

## Overview

This plan adds MITMproxy integration to enable deep traffic inspection by redirecting all network traffic through MITMproxy using iptables. The implementation includes virtual environment setup, proxy server launch, and traffic redirection scripts for both local and remote scenarios.

## Implementation Details

### 1. Makefile Targets

Add to [Makefile](Makefile):

- `make mitm-venv`: Creates UV virtual environment and installs mitmproxy

- `make mitmweb`: Launches mitmweb with all proxy modes (WireGuard, HTTP, SOCKS5)

- `make mitm-clean`: Removes iptables rules and stops mitmweb processes

### 2. Configuration Variables

Add configurable variables to Makefile:

- `MITM_VENV_DIR`: Virtual environment directory (default: `.venv-mitm`)

- `MITM_LOG_DIR`: Log directory (default: `mitm_logs`)

- `MITM_WIREGUARD_PORT`: WireGuard proxy port (default: 51820)

- `MITM_HTTP_PORT`: HTTP proxy port (default: 58080)

- `MITM_SOCKS5_PORT`: SOCKS5 proxy port (default: 51080)

- `MITM_WEB_PORT`: Web interface port (default: 58081)

- `MITM_INTERFACE`: Network interface for iptables (auto-detect with override)

- `MITM_MODE`: Proxy mode - transparent or explicit (default: transparent)

### 3. Scripts to Create

#### 3.1 `scripts/setup-mitm-iptables-local.sh`

- Sets up iptables rules on local machine

- Supports transparent and explicit proxy modes

- Auto-detects network interface (default gateway)

- Allows interface override via environment variable

- Redirects traffic to MITMproxy ports

#### 3.2 `scripts/setup-mitm-iptables-remote.sh`

- Sets up iptables rules on remote IoT device

- Requires TARGET_IP, USERNAME, PASSWORD parameters
- Supports transparent and explicit proxy modes

- Redirects device traffic to MITMproxy server

- Includes error handling and rollback capability

#### 3.3 `scripts/cleanup-mitm-iptables.sh`

- Removes iptables rules created by setup scripts

- Works for both local and remote scenarios

- Stops mitmweb processes

- Cleans up NAT table rules

### 4. iptables Rules Strategy

**Transparent Mode:**

- Redirect HTTP (port 80) to MITMproxy HTTP port

- Redirect HTTPS (port 443) to MITMproxy HTTP port

- Use NAT table PREROUTING chain for incoming traffic

- Use NAT table OUTPUT chain for local traffic

**Explicit Mode:**

- Redirect all TCP traffic to MITMproxy ports

- Allow direct connections to MITMproxy ports

- Configure routing for proxy communication

### 5. Virtual Environment Setup

- Use UV package manager (per user preference)

- Create isolated virtual environment for mitmproxy

- Install mitmproxy package

- Verify installation with version check

### 6. mitmweb Launch Configuration

Following reference script `/home/jed/.local/bin/mitmlog.sh`:

- Launch with multiple proxy modes:

- `--mode wireguard@0.0.0.0:${MITM_WIREGUARD_PORT}`

- `--mode regular@0.0.0.0:${MITM_HTTP_PORT}`

- `--mode socks5@0.0.0.0:${MITM_SOCKS5_PORT}`

- Web interface on `--web-port ${MITM_WEB_PORT}`

- Hourly log rotation with timestamped files

- Log format: `mitm_YYYYMMDD_HHMMSS.log`

- Save to `--save-stream-file` in `${MITM_LOG_DIR}`

## Files to Create/Modify

1. **Makefile** - Add mitm-venv, mitmweb, mitm-clean targets

2. **scripts/setup-mitm-iptables-local.sh** - Local iptables setup script

3. **scripts/setup-mitm-iptables-remote.sh** - Remote iptables setup script

4. **scripts/cleanup-mitm-iptables.sh** - iptables cleanup script

## Architecture Flow

```javascript
┌─────────────────┐
│  Network Traffic │
└────────┬─────────┘
         │
         ▼
┌─────────────────┐
│  iptables Rules │ (Transparent/Explicit)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   MITMproxy     │ (WireGuard/HTTP/SOCKS5)
│   Ports:        │
│   51820/58080/  │
│   51080         │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Log Files      │ (mitm_logs/)
│  Hourly Rotation│
└─────────────────┘
```



## Dependencies

- UV package manager (for virtual environment)

- mitmproxy Python package

- iptables (for traffic redirection)
- Root/sudo access (for iptables rules)

## Testing Considerations

- Verify virtual environment creation

- Test mitmweb launch with all proxy modes

- Verify iptables rules are applied correctly

- Test traffic redirection in transparent mode

- Test traffic redirection in explicit mode

- Verify log rotation works correctly

- Test cleanup script removes all rules

## Notes

- iptables rules are NOT persisted (per user preference)

- Logs follow mitmproxy binary format (use mitmdump for analysis)

- WireGuard mode uses MITMproxy's built-in WireGuard support