# Local-Only Mode Setup Guide

This guide explains how to set up the Bytech BY-CM-WF-101-WT webcam for local-only operation, removing all cloud dependencies and serving video via local RTSP server.

## Overview

The local-only mode setup replaces the cloud-dependent `apollo` process with a local RTSP server, blocks all cloud communication using multiple methods (iptables, process-level, DNS), and provides real-time connection monitoring.

## Prerequisites

- Access to the webcam via telnet (default: port 23)
- Credentials: `root`/`hellotuya` or `user`/`user123`
- `expect` installed on your system
- ARM-compatible RTSP server binary (for FH8616 ARMv6/ARMv7 architecture)
- Network access to the webcam device

## Quick Start

### Option 1: Automated Setup (Recommended)

Run the master integration script to set up everything automatically:

```bash
./scripts/setup-local-only-mode.sh 10.0.0.227 root hellotuya /stream1
```

This script will:
1. Discover RTSP streams and analyze the webcam interface
2. Discover all cloud endpoints
3. Set up local RTSP server
4. Replace apollo process
5. Apply firewall rules to block cloud
6. Block cloud at process level
7. Block external DNS
8. Set up monitoring

### Option 2: Manual Step-by-Step Setup

Follow the phases below for manual setup with more control.

## Phase 1: Discovery and Analysis

### 1.1 Discover RTSP Streams

```bash
./scripts/discover-rtsp-streams.sh 10.0.0.227 root hellotuya
```

This will:
- Test common RTSP paths (`/stream1`, `/live`, `/video`, etc.)
- Document stream parameters (codec, resolution, framerate)
- Output results to `rtsp-discovery-*.txt`

### 1.2 Analyze Webcam Interface

```bash
./scripts/analyze-webcam-interface.sh 10.0.0.227 root hellotuya
```

This will:
- Examine apollo binary and process
- Check video devices (`/dev/video*`)
- Identify camera hardware interface
- Document how apollo accesses the camera
- Output results to `webcam-interface-*.txt`

### 1.3 Discover Cloud Endpoints

```bash
./scripts/discover-cloud-endpoints.sh 10.0.0.227 root hellotuya
```

This will:
- Extract cloud server IPs from active connections
- Find external DNS servers
- Search configuration files for cloud endpoints
- Output results to `cloud-endpoints-*.txt`

## Phase 2: Local RTSP Server Setup

### 2.1 Set Up Local RTSP Server

```bash
./scripts/setup-local-rtsp.sh 10.0.0.227 root hellotuya /stream1 8554
```

This script provides:
- Configuration templates for RTSP server
- Startup script templates
- Instructions for installing ARM-compatible RTSP server

**Important**: You must obtain and install an ARM-compatible RTSP server binary (e.g., `rtsp-simple-server` or `mediamtx`) before proceeding.

### 2.2 Replace Apollo

```bash
./scripts/replace-apollo-rtsp.sh 10.0.0.227 root hellotuya
```

This will:
- Backup original apollo binary
- Stop apollo process
- Start local RTSP server
- Verify stream is accessible
- Create rollback script

**RTSP Stream URL**: After replacement, the stream will be available at:
```
rtsp://<webcam-ip>:8554/<stream-path>
```

Example: `rtsp://10.0.0.227:8554/stream1`

## Phase 3: Cloud Communication Blocking

### 3.1 Block Cloud with iptables

```bash
./scripts/block-cloud-iptables.sh 10.0.0.227 root hellotuya [cloud-ips-file]
```

This will:
- Block specific cloud IP addresses (52.42.98.25 and others)
- Allow local network traffic (10.0.0.0/24)
- Allow RTSP inbound on port 8554
- Block all other outbound internet traffic
- Save rules for persistence
- Create restore script

### 3.2 Block Cloud at Process Level

```bash
./scripts/block-cloud-process.sh 10.0.0.227 root hellotuya
```

This will:
- Disable apollo in startup script
- Create apollo wrapper to block cloud connections
- Create monitoring script to prevent apollo cloud features
- Stop apollo if running

### 3.3 Block External DNS

```bash
./scripts/block-cloud-dns.sh 10.0.0.227 root hellotuya [local-dns]
```

This will:
- Modify `/etc/resolv.conf` to use only local DNS
- Block external DNS queries via iptables (port 53)
- Create restore script

## Phase 4: Connection Monitoring

### 4.1 Real-Time Connection Monitor

```bash
./scripts/monitor-connections.sh 10.0.0.227 root hellotuya 2 monitor.log
```

This provides:
- Continuous monitoring (updates every 1-2 seconds)
- Highlights cloud connections
- Logs suspicious connections
- Shows summary statistics

### 4.2 Connection Analysis

```bash
./scripts/analyze-connections.sh 10.0.0.227 root hellotuya
```

This provides:
- One-time snapshot of all connections
- Categorization: local, cloud, listening services
- Process identification
- Summary report

### 4.3 Connection Alerts

```bash
./scripts/connection-alerts.sh 10.0.0.227 root hellotuya alerts.log 5
```

This provides:
- Monitoring for new cloud connections
- Alerts when blocked IPs attempt connection
- Logging of all blocked attempts
- Configurable check interval

## Phase 5: Testing and Validation

### Run Complete Test Suite

```bash
./scripts/test-local-setup.sh 10.0.0.227 root hellotuya /stream1 8554
```

This will test:
- RTSP stream accessibility
- No cloud connections active
- Firewall rules blocking cloud IPs
- DNS blocking effectiveness
- Monitoring tools availability
- Rollback mechanism

## RTSP Stream URL

After setup, access the video stream at:

```
rtsp://<webcam-ip>:8554/<stream-path>
```

Common stream paths:
- `/stream1`
- `/live`
- `/video`
- `/ch0`
- `/ch1`

Use the discovery script to find the correct path for your device.

## Firewall Rules

The iptables rules applied:

- **Allow**: Loopback traffic
- **Allow**: Local network (10.0.0.0/24)
- **Allow**: RTSP inbound on port 8554
- **Block**: Specific cloud IPs (52.42.98.25, etc.)
- **Block**: All other outbound internet traffic

## Rollback Procedures

### Restore Apollo

If you need to restore the original apollo process:

1. Use the rollback script created by `replace-apollo-rtsp.sh`
2. Or manually:
   ```bash
   # Restore apollo binary from backup
   cp /tmp/apollo-backup-*/apollo.original /app/abin/apollo
   
   # Stop local RTSP server
   killall local-rtsp-server
   
   # Restart apollo (if startup script exists)
   /app/start.sh &
   ```

### Restore iptables

```bash
# Restore from backup
iptables-restore < /tmp/iptables-backup-*.rules

# Or reset to defaults
iptables -F
iptables -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
```

### Restore DNS

```bash
# Restore from backup
cp /tmp/resolv.conf.backup-* /etc/resolv.conf

# Or set default DNS
cat > /etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF
```

## Troubleshooting

### RTSP Stream Not Accessible

1. Verify RTSP server is running:
   ```bash
   ps | grep local-rtsp-server
   ```

2. Check port 8554 is listening:
   ```bash
   netstat -tulpn | grep 8554
   ```

3. Test RTSP connection:
   ```bash
   echo -e "OPTIONS rtsp://10.0.0.227:8554/stream1 RTSP/1.0\r\nCSeq: 1\r\n\r\n" | nc 10.0.0.227 8554
   ```

### Cloud Connections Still Active

1. Check firewall rules:
   ```bash
   iptables -L OUTPUT -n -v
   ```

2. Verify apollo is stopped:
   ```bash
   ps | grep apollo
   ```

3. Check for other processes making connections:
   ```bash
   netstat -anp | grep 52.42.98.25
   ```

### Firewall Rules Not Persisting

1. Save rules manually:
   ```bash
   iptables-save > /etc/iptables.rules
   ```

2. Add to startup script to restore on boot:
   ```bash
   iptables-restore < /etc/iptables.rules
   ```

### DNS Blocking Issues

1. Verify resolv.conf:
   ```bash
   cat /etc/resolv.conf
   ```

2. Check iptables DNS rules:
   ```bash
   iptables -L OUTPUT -n -v | grep 53
   ```

3. Test DNS resolution:
   ```bash
   nslookup example.com
   ```

## Status Check

Use the status check script created by the integration script:

```bash
./scripts/check-local-only-status.sh
```

Or manually check:

```bash
# Check RTSP server
./scripts/analyze-connections.sh 10.0.0.227 root hellotuya | grep 8554

# Check cloud connections
./scripts/analyze-connections.sh 10.0.0.227 root hellotuya | grep CLOUD
```

## Security Considerations

1. **Backup Everything**: All scripts create backups before making changes. Keep these backups safe.

2. **Test in Controlled Environment**: Test the setup in a controlled environment before deploying.

3. **Monitor Regularly**: Use the monitoring scripts to ensure no cloud connections are established.

4. **Keep RTSP Server Updated**: Ensure your RTSP server binary is kept up to date for security.

5. **Firewall Rules**: Review and adjust firewall rules based on your network requirements.

## Architecture

```
┌─────────────────┐
│   Webcam Device │
│                 │
│  ┌───────────┐  │
│  │  Camera   │  │
│  │ Hardware  │  │
│  └─────┬─────┘  │
│        │        │
│  ┌─────▼─────┐  │
│  │ Local RTSP│  │
│  │  Server    │  │
│  └─────┬─────┘  │
│        │        │
│  ┌─────▼─────┐  │
│  │ iptables  │  │
│  │  Firewall │  │
│  └───────────┘  │
│                 │
│  ┌───────────┐  │
│  │ Monitoring│  │
│  │  Scripts  │  │
│  └───────────┘  │
└─────────────────┘
        │
        │ RTSP Stream
        │ (Local Network Only)
        ▼
┌─────────────────┐
│  Local Network  │
│  (10.0.0.0/24)  │
└─────────────────┘
```

## Files Created

- `rtsp-discovery-*.txt` - RTSP stream discovery results
- `webcam-interface-*.txt` - Webcam interface analysis
- `cloud-endpoints-*.txt` - Cloud endpoint discovery
- `connection-analysis-*.txt` - Connection analysis reports
- `connection-monitor-*.log` - Real-time monitoring logs
- `connection-alerts-*.log` - Alert logs
- `setup-local-only-*.log` - Setup process log

## Support

For issues or questions:
1. Review the troubleshooting section
2. Check the setup log files
3. Verify all prerequisites are met
4. Test individual components using the phase scripts

## License

This setup guide and scripts are part of the Bytech BY-CM-WF-101-WT penetration testing suite.

