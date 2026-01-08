# Apollo Comprehensive Analysis Report
Generated: 2026-01-08

## Executive Summary

Apollo is the main application running on the Bytech BY-CM-WF-101-WT webcam. It handles:
- RTSP video streaming (port 8554)
- Cloud connectivity via MQTT (port 8883 to 52.42.98.25)
- Multiple local services (ports 6668, 8699, UDP 8000/8002, etc.)
- Unix domain sockets for internal communication

## Key Findings

### 1. Binary Information
- **Location**: `/app/abin/apollo`
- **Size**: 1.3MB (1,318,160 bytes)
- **Status**: UPX packed (compressed)
- **Permissions**: Executable by user/group
- **Date**: July 9, 2025

### 2. Process Information
- **PID**: 637 (when running)
- **Parent**: Started from `/app/start.sh`
- **User**: root
- **Status**: Running as background process (`./apollo &`)

### 3. Network Ports and Services

#### Listening TCP Ports:
- **8554**: RTSP video streaming (primary service) - **CRITICAL**
- **6668**: Unknown service
- **8699**: Unknown service

#### Listening UDP Ports:
- **35107**: Unknown service
- **8000**: Unknown service (possibly HTTP alternative)
- **8002**: Unknown service
- **51454**: Unknown service

#### Cloud Connections:
- **52.42.98.25:8883**: MQTT cloud connection (ESTABLISHED)
  - This is the cloud dependency that needs to be blocked/replaced
  - Local port: 40886

#### Unix Domain Sockets:
- `@sd_event`: SD card event handling
- `@jap_server`: Japanese server? (internal service)
- `@ble_event`: Bluetooth Low Energy event handling

### 4. Startup Sequence

Apollo is started from `/app/start.sh` with the following sequence:

1. **Pre-checks**:
   - Flash check (`app_check_flash.sh`)
   - Sensor detection (`myinfo.sh sensor`)
   - Autorun flag check (`fw_printenv autorun`)
   - UVC mode check (`una` binary)

2. **Apollo Launch**:
   ```bash
   cd /app/abin
   ./apollo &
   ```

3. **Post-launch**:
   - `app_post.sh` (if exists) - runs after apollo starts
   - `cld_upd` (cloud updater) - starts after apollo
   - `andlink` - starts 10 seconds after apollo

### 5. Dependencies

**Required Files**:
- `/app/abin/apollo` (main binary)
- `/app/start.sh` (startup script)
- `/app/abin/app_pre.sh` (optional pre-script)
- `/app/abin/app_post.sh` (optional post-script)

**Related Processes**:
- `noodles` (PID 704) - related service
- `cld_upd` - cloud updater (may restore apollo)
- `andlink` - network linking service

**Environment**:
- `PATH=/bin:/sbin:/app/bin:/app/abin:/app:/usr/bin`
- `LD_LIBRARY_PATH=/lib:/usr/lib:/app/lib`

### 6. Camera Access

- No `/dev/video*` devices found in standard locations
- Camera access likely handled through proprietary drivers or V4L2 abstraction
- Apollo manages camera internally
- No video device file descriptors visible in process

### 7. Factory Test Mode

The system has a factory test mode:
- If `/mnt/sd/factory_test/{product}/fac_apollo` exists, it runs `fac_apollo` instead of `apollo`
- Creates `/tmp/fac_apollo` flag file
- Copies factory test binary to `/home/fac_apollo`

## Replacement Strategy Recommendations

### Option 1: Kill and Replace with Local RTSP Server (Recommended)
**Steps**:
1. Kill apollo process (PID 637)
2. Kill related processes (`cld_upd`, `andlink`, `noodles`)
3. Block cloud connection (52.42.98.25:8883) via iptables
4. Start local RTSP server on port 8554
5. Disable apollo startup in `/app/start.sh`

**Pros**:
- Clean separation
- Easy to reverse
- No binary modification

**Cons**:
- May need to handle other ports (6668, 8699)
- Unknown dependencies on other services

### Option 2: Binary Replacement with Wrapper
**Steps**:
1. Backup original apollo binary
2. Replace with wrapper script that:
   - Blocks cloud connections
   - Redirects to local RTSP server
   - Logs all calls
3. Maintains same startup sequence

**Pros**:
- Preserves startup sequence
- Can intercept all apollo calls

**Cons**:
- More complex
- May break if apollo checks its own binary

### Option 3: Startup Script Modification (Safest)
**Steps**:
1. Modify `/app/start.sh` to:
   - Skip apollo launch
   - Start local RTSP server instead
   - Block cloud DNS/IPs
2. Comment out apollo launch line

**Pros**:
- Most reversible
- No binary modification
- Clean separation

**Cons**:
- May need to handle other services that depend on apollo

## Critical Ports to Preserve

- **8554**: RTSP streaming (must be replaced with local server)
- **6668, 8699**: Unknown - may be needed for local functionality
- **UDP 8000/8002**: Unknown - may be discovery or control

## Cloud Dependencies to Block

- **52.42.98.25:8883** (MQTT) - Primary cloud connection
- DNS queries to cloud domains (if any)
- Consider blocking `cld_upd` process as it may restore apollo

## Implementation Checklist

- [ ] Test local RTSP server on port 8554
- [ ] Block cloud connection (52.42.98.25:8883) via iptables
- [ ] Kill apollo and verify it doesn't auto-restart
- [ ] Kill related processes (`cld_upd`, `andlink`, `noodles`)
- [ ] Start local RTSP server on port 8554
- [ ] Test RTSP streaming works locally
- [ ] Modify `/app/start.sh` to prevent apollo restart
- [ ] Test system reboot to ensure changes persist
- [ ] Monitor for any auto-restart mechanisms

## Warnings

- **UPX Packed Binary**: Binary is compressed, making reverse engineering difficult
- **Multiple Services**: Apollo runs multiple services - ensure all needed ports are handled
- **Auto-restart**: May have watchdog or auto-restart mechanism - test thoroughly
- **Factory Mode**: System has factory test mode (fac_apollo) - may interfere
- **Cloud Updater**: `cld_upd` process may try to restore apollo or update it
- **Andlink Service**: `andlink` may depend on apollo or cloud connectivity
- **Unknown Ports**: Ports 6668, 8699, UDP 8000/8002 have unknown purposes

## Next Steps

1. **Test Local RTSP Server**: Verify local RTSP server works on port 8554
2. **Block Cloud Connection**: Use iptables to block 52.42.98.25:8883
3. **Kill Apollo**: Test killing apollo and verify it doesn't auto-restart
4. **Kill Related Processes**: Stop `cld_upd`, `andlink`, `noodles`
5. **Replace with Local Server**: Start local RTSP server on port 8554
6. **Verify Functionality**: Test RTSP streaming works locally
7. **Disable Startup**: Modify `/app/start.sh` to prevent apollo restart
8. **Test Reboot**: Ensure changes persist after reboot
