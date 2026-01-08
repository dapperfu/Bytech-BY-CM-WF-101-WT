---
name: Webcam Local RTSP Server and Cloud Blocking
overview: Set up a local RTSP server on the webcam device to serve video without cloud dependency, block all cloud communication using iptables and process modification, and create real-time connection monitoring tools.
todos:
  - id: save_plan
    content: Save plan to plans/ directory
    status: completed
  - id: discover_rtsp
    content: Create RTSP stream discovery script (discover-rtsp-streams.sh)
    status: pending
    dependencies:
      - save_plan
  - id: analyze_interface
    content: Create webcam interface analysis script (analyze-webcam-interface.sh)
    status: pending
    dependencies:
      - save_plan
  - id: discover_cloud
    content: Create cloud endpoint discovery script (discover-cloud-endpoints.sh)
    status: pending
    dependencies:
      - save_plan
  - id: setup_rtsp
    content: Create local RTSP server setup script (setup-local-rtsp.sh)
    status: pending
    dependencies:
      - discover_rtsp
      - analyze_interface
  - id: replace_apollo
    content: Create apollo replacement script (replace-apollo-rtsp.sh)
    status: pending
    dependencies:
      - setup_rtsp
  - id: block_iptables
    content: Create iptables cloud blocking script (block-cloud-iptables.sh)
    status: pending
    dependencies:
      - discover_cloud
  - id: block_process
    content: Create process-level cloud blocking script (block-cloud-process.sh)
    status: pending
    dependencies:
      - discover_cloud
  - id: block_dns
    content: Create DNS blocking script (block-cloud-dns.sh)
    status: pending
    dependencies:
      - discover_cloud
  - id: monitor_connections
    content: Create real-time connection monitoring script (monitor-connections.sh)
    status: pending
  - id: analyze_connections
    content: Create connection analysis script (analyze-connections.sh)
    status: pending
  - id: connection_alerts
    content: Create connection alert system (connection-alerts.sh)
    status: pending
    dependencies:
      - monitor_connections
  - id: integration_script
    content: Create master integration script (setup-local-only-mode.sh)
    status: pending
    dependencies:
      - replace_apollo
      - block_iptables
      - block_process
      - block_dns
      - monitor_connections
  - id: test_setup
    content: Create testing and validation script (test-local-setup.sh)
    status: pending
    dependencies:
      - integration_script
  - id: documentation
    content: Create documentation (README for local-only setup)
    status: pending
    dependencies:
      - test_setup
---

# Webcam Local RTSP Server and Cloud Blocking Setup

## Overview

This plan implements a local-only RTSP video streaming solution for the Bytech BY-CM-WF-101-WT webcam, replacing the cloud-dependent `apollo` process with a local RTSP server, blocking all cloud communication, and providing real-time connection monitoring.

## Current System Analysis

From the internal probe data:

- **RTSP Server**: `apollo` process (PID 637) listening on port 8554 (YGTek RTSP Server 2.0)
- **Cloud Connection**: MQTT connection to `52.42.98.25:8883` (process `apollo`)
- **Other Services**: `noodles` process (PID 704) on ports 843, 1300
- **Hardware**: FH8616 chipset (Fullhan), BusyBox-based embedded Linux
- **Binary Location**: `/app/abin/apollo`
- **No Firewall**: iptables is empty (no rules configured)

## Implementation Plan

### Phase 1: Discovery and Analysis

1. **RTSP Stream Discovery Script** (`scripts/discover-rtsp-streams.sh`)
   - Connect to webcam via telnet
   - Test common RTSP paths: `/stream1`, `/live`, `/video`, `/ch0`, `/ch1`
   - Use `ffprobe` or `curl` to discover working stream URLs
   - Document stream parameters (codec, resolution, framerate)
   - Output: Stream path, authentication requirements, stream parameters

2. **Webcam Interface Analysis** (`scripts/analyze-webcam-interface.sh`)
   - Examine `/app/abin/apollo` binary (strings, file info)
   - Check `/dev/video*` devices
   - Analyze `/proc/637/cmdline` and `/proc/637/environ` for apollo process
   - Check for V4L2 (Video4Linux2) interfaces
   - Identify camera hardware interface (USB, MIPI, etc.)
   - Document how apollo accesses the camera hardware

3. **Cloud Endpoint Discovery** (`scripts/discover-cloud-endpoints.sh`)
   - Extract all cloud server IPs/domains from:
     - Active connections (`netstat/ss`)
     - DNS lookups
     - Process environment variables
     - Configuration files in `/app`
   - Document all cloud dependencies

### Phase 2: Local RTSP Server Setup

4. **RTSP Server Selection and Installation**
   - Evaluate options for embedded Linux (BusyBox):
     - `rtsp-simple-server` (lightweight, Go-based)
     - `mediamtx` (formerly rtsp-simple-server)
     - Custom solution using `ffmpeg` + `ffserver`
   - Create installation script for chosen solution
   - Ensure compatibility with FH8616 ARM architecture

5. **Camera Capture Configuration** (`scripts/setup-local-rtsp.sh`)
   - Configure RTSP server to capture from camera device
   - Map discovered stream path to local server
   - Set up authentication (if needed)
   - Test local stream accessibility
   - Create startup script to replace apollo on boot

6. **Apollo Replacement Script** (`scripts/replace-apollo-rtsp.sh`)
   - Stop `apollo` process gracefully
   - Backup original `/app/abin/apollo` binary
   - Start local RTSP server on port 8554
   - Verify stream is accessible locally
   - Create rollback mechanism

### Phase 3: Cloud Communication Blocking

7. **iptables Firewall Rules** (`scripts/block-cloud-iptables.sh`)
   - Block outbound connections to cloud IPs:
     - `52.42.98.25` (MQTT server)
     - Any other discovered cloud endpoints
   - Allow local network (10.0.0.0/24)
   - Allow RTSP on port 8554 (inbound)
   - Block all other outbound internet traffic
   - Save rules to persist across reboots
   - Create restore script

8. **Process-Level Blocking** (`scripts/block-cloud-process.sh`)
   - Modify apollo startup to disable MQTT/cloud features
   - Or: Replace apollo binary with wrapper that blocks cloud connections
   - Or: Use `LD_PRELOAD` to intercept network calls
   - Create monitoring to ensure apollo doesn't restart with cloud features

9. **DNS Blocking** (`scripts/block-cloud-dns.sh`)
   - Modify `/etc/resolv.conf` to remove external DNS servers
   - Use only local DNS or block DNS entirely
   - Block DNS queries to external servers via iptables

### Phase 4: Connection Monitoring

10. **Real-Time Connection Monitor** (`scripts/monitor-connections.sh`)
    - Continuous monitoring using `watch` or loop
    - Display:
      - All active connections (TCP/UDP)
      - Process names and PIDs
      - Local and remote IPs/ports
      - Connection states
      - Highlight cloud connections (red flag)
    - Update every 1-2 seconds
    - Log suspicious connections to file

11. **Connection Analysis Script** (`scripts/analyze-connections.sh`)
    - One-time snapshot of all connections
    - Categorize connections:
      - Local network (10.0.0.0/24)
      - Cloud servers (external IPs)
      - Listening services
    - Generate report with connection details
    - Identify processes making cloud connections

12. **Alert System** (`scripts/connection-alerts.sh`)
    - Monitor for new cloud connections
    - Alert when blocked IPs attempt connection
    - Log all blocked connection attempts
    - Optional: Email/SMS alerts (if infrastructure available)

### Phase 5: Integration and Testing

13. **Integration Script** (`scripts/setup-local-only-mode.sh`)
    - Master script that orchestrates all components:
      1. Discover RTSP streams
      2. Set up local RTSP server
      3. Replace apollo
      4. Apply firewall rules
      5. Start monitoring
    - Include rollback functionality
    - Create status check script

14. **Testing and Validation** (`scripts/test-local-setup.sh`)
    - Verify RTSP stream is accessible locally
    - Confirm no cloud connections are active
    - Test firewall rules block cloud IPs
    - Validate monitoring shows correct information
    - Test rollback mechanism

15. **Documentation**
    - Create README for local-only setup
    - Document RTSP stream URL
    - Document firewall rules
    - Document rollback procedures
    - Create troubleshooting guide

## File Structure

```
scripts/
├── discover-rtsp-streams.sh          # Phase 1: Stream discovery
├── analyze-webcam-interface.sh       # Phase 1: Hardware interface analysis
├── discover-cloud-endpoints.sh       # Phase 1: Cloud dependency discovery
├── setup-local-rtsp.sh               # Phase 2: RTSP server setup
├── replace-apollo-rtsp.sh            # Phase 2: Apollo replacement
├── block-cloud-iptables.sh           # Phase 3: Firewall rules
├── block-cloud-process.sh            # Phase 3: Process-level blocking
├── block-cloud-dns.sh                # Phase 3: DNS blocking
├── monitor-connections.sh            # Phase 4: Real-time monitoring
├── analyze-connections.sh            # Phase 4: Connection analysis
├── connection-alerts.sh              # Phase 4: Alert system
├── setup-local-only-mode.sh          # Phase 5: Master integration script
└── test-local-setup.sh               # Phase 5: Testing and validation
```

## Git Commit Requirements

All file creation and modifications SHALL follow the atomic commit requirements specified in `.cursor/rules/git/`:

1. **Atomic Commits**: Each script file SHALL be committed atomically (one file per commit) following `git/commit-atomicity.mdc`
   - Exception: TODO checkoffs in plan file may be committed with the file changes that complete them (per `cursor/plans-todo-commits.mdc`)

2. **Commit Format**: All commits SHALL follow the format in `git/commit-format.mdc`:
   - Brief one-liner summary
   - List of changes (prefixed with `- `)
   - Technical attribution section with prompt, context, justification, and token estimation

3. **Upstream Sync**: Before each commit, SHALL sync with upstream per `git/upstream-sync.mdc`:
   - `git fetch upstream && git fetch origin`
   - Detect upstream branch and merge changes
   - Resolve conflicts if any

4. **Git User Configuration**: Before committing, SHALL configure git user per `git/user-config.mdc`:
   - `git config user.name "$(whoami) | Cursor.sh | Auto"`
   - `git config user.email "$(whoami)@$(hostname).local"`

5. **Push After Commit**: After each commit, SHALL push if remote exists per `git/push-requirement.mdc`

6. **Commit Frequency**: 
   - After every created file (per `git/commit-requirement.mdc`)
   - After each prompt with changes (per `cursor/plans-commit-execution.mdc`)

## Technical Considerations

1. **BusyBox Limitations**: Scripts must use BusyBox-compatible commands (no GNU extensions)
2. **ARM Architecture**: All binaries must be ARM-compatible (FH8616 is ARMv6/ARMv7)
3. **Limited Storage**: Webcam has limited storage, keep solutions lightweight
4. **Process Management**: Use BusyBox `killall` or PID files for process management
5. **Persistence**: Ensure firewall rules and RTSP server survive reboots
6. **Stream Quality**: Maintain original stream quality when replacing apollo

## Dependencies

- `expect` (for telnet automation - already used in project)
- `ffmpeg` or `ffprobe` (for RTSP stream testing)
- RTSP server binary (to be determined based on compatibility)
- Network tools: `netstat`, `ss`, `iptables` (should be available on device)

## Success Criteria

1. RTSP stream accessible locally at `rtsp://<webcam-ip>:8554/<stream-path>`
2. No active connections to cloud servers (52.42.98.25 or others)
3. Firewall rules block all outbound internet traffic except local network
4. Real-time monitoring shows only local connections
5. System functions normally without cloud dependency

