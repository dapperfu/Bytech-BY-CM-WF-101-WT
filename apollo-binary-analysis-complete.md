# Apollo Binary Analysis - Complete Findings

## Executive Summary

While downloading the full binary for decompilation proved challenging due to size (1.3MB) and telnet limitations, we discovered that **apollo is highly configurable via config files**, not just hardcoded. Most settings are in `/app/prodid/{MODEL}/config/app.cfg`.

## Binary Information

- **Location**: `/app/abin/apollo`
- **Size**: 1.3MB (1,318,160 bytes)
- **Status**: UPX packed (compressed)
- **Architecture**: ARM (embedded Linux)
- **Invocation**: `./apollo &` (no command-line arguments)

## Command Line Options

**Answer: No command-line options are used.** Apollo is invoked without arguments:
```bash
cd /app/abin
./apollo &
```

However, apollo does check if it's already running:
- Warning: `[ut_check_proc_running, line:543] WARNING: apollo is already running`

## Configuration Files (NOT Hardcoded!)

Apollo reads configuration from multiple sources:

### 1. Main Config: `/app/prodid/{MODEL}/config/app.cfg`

Key settings found:
```ini
cloud_enable=yes          # Cloud connectivity
cloud_tuya=yes            # Tuya cloud service
rtsp_audio=yes            # RTSP with audio
onvif=yes                 # ONVIF support
web=no                    # Web interface disabled
product_key=biw8urjw2dvss3ur  # Tuya product key
```

**This means cloud connectivity can potentially be disabled by setting `cloud_enable=no`!**

### 2. Video Encoding Config: `/app/prodid/{MODEL}/config/venc_strategy.xml`
- H.264/S.264 encoding settings
- Bitrate, QP, frame rate controls
- Sensor-specific configurations

### 3. Other Config Files:
- `/app/app_config.sh` - Application configuration script
- `/app/app_config_ex.sh` - Extended configuration
- `/app/prodid/{MODEL}/config/board.cfg` - Board-specific settings
- `/app/prodid/{MODEL}/config/sensor_*.bin` - Sensor calibration

## Environment Variables

Apollo runs with:
```bash
LD_LIBRARY_PATH=/lib:/usr/lib:/app/lib:/app/lib
PATH=/bin:/sbin:/app/bin:/app/abin:/app:/usr/bin
PWD=/app/abin
USER=root
```

## Network Configuration

From runtime analysis:
- **RTSP**: Port 8554 (configurable via `rtsp_audio=yes`)
- **ONVIF**: Enabled (configurable via `onvif=yes`)
- **Cloud MQTT**: 52.42.98.25:8883 (configurable via `cloud_enable=yes`)
- **Other ports**: 6668, 8699, UDP 8000/8002, etc.

## Key Discovery: Configuration-Based, Not Hardcoded!

**Most settings are in config files, not hardcoded in the binary!**

This means:
1. ✅ **Cloud can be disabled**: Set `cloud_enable=no` in `app.cfg`
2. ✅ **RTSP can be configured**: Already enabled, can adjust settings
3. ✅ **ONVIF is available**: Can use ONVIF instead of cloud
4. ✅ **Product key is in config**: Can be changed/modified

## Replacement Strategy (Updated)

### Option 1: Disable Cloud via Config (Easiest)
```bash
# Edit config file
sed -i 's/cloud_enable=yes/cloud_enable=no/' /app/prodid/PYEWN-01/config/app.cfg
sed -i 's/cloud_tuya=yes/cloud_tuya=no/' /app/prodid/PYEWN-01/config/app.cfg
# Restart apollo
```

### Option 2: Kill and Replace (Previous recommendation)
- Still valid, but config modification might be simpler

### Option 3: Config + Local RTSP
- Disable cloud
- Ensure RTSP is enabled (already is)
- Use local RTSP stream on port 8554

## What We Still Don't Know (Requires Binary)

1. **Internal logic**: How apollo processes video, handles errors
2. **Library dependencies**: What shared libraries it uses
3. **Protocol details**: Exact RTSP/ONVIF implementation
4. **Security**: Authentication mechanisms, encryption
5. **UPX unpacking**: Need binary to unpack and analyze code

## Recommendations

### For Local-Only Operation:

1. **Try config modification first**:
   ```bash
   # Backup original
   cp /app/prodid/PYEWN-01/config/app.cfg /app/prodid/PYEWN-01/config/app.cfg.bak
   
   # Disable cloud
   sed -i 's/cloud_enable=yes/cloud_enable=no/' /app/prodid/PYEWN-01/config/app.cfg
   sed -i 's/cloud_tuya=yes/cloud_tuya=no/' /app/prodid/PYEWN-01/config/app.cfg
   
   # Restart apollo
   killall apollo
   cd /app/abin && ./apollo &
   ```

2. **Monitor if cloud connection stops**:
   - Check `netstat -an | grep 52.42.98.25`
   - Verify MQTT connection closes

3. **Use RTSP locally**:
   - RTSP URL: `rtsp://10.0.0.227:8554/...` (check actual path)
   - ONVIF: Available if enabled

### For Full Binary Analysis:

If you still need the binary:
1. Use physical access (USB/SD card)
2. Enable SSH/SCP if possible
3. Try very small chunk downloads (5KB chunks)
4. Use alternative transfer methods (FTP, HTTP server on device)

## Conclusion

**Apollo is NOT fully hardcoded!** It uses configuration files extensively. The cloud dependency can likely be disabled via config file modification, which is much simpler than binary replacement.

The binary itself is UPX packed, making decompilation more difficult, but the config files reveal most of what we need to know for local-only operation.
