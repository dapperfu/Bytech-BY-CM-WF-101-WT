# Apollo Binary Analysis Summary

## Current Status

We attempted to download the apollo binary for decompilation and analysis, but encountered challenges with large file transfers over telnet. However, we can still provide insights based on runtime analysis.

## What We Know Without the Binary

### 1. Command Line Options
- **No command-line arguments**: Apollo is invoked as `./apollo &` with no arguments
- **Process check**: Apollo checks if it's already running before starting
- **Warning message**: `[ut_check_proc_running, line:543] WARNING: apollo is already running`

### 2. Binary Characteristics
- **Location**: `/app/abin/apollo`
- **Size**: 1.3MB (1,318,160 bytes)
- **Status**: UPX packed (compressed)
- **Architecture**: ARM (based on device)
- **Permissions**: Executable by user/group

### 3. Runtime Behavior (from process analysis)
- **PID**: 637 (when running)
- **User**: root
- **Network ports**:
  - TCP 8554: RTSP streaming
  - TCP 6668: Unknown service
  - TCP 8699: Unknown service
  - UDP 35107, 8000, 8002, 51454: Unknown services
- **Cloud connection**: 52.42.98.25:8883 (MQTT)
- **Unix sockets**: `@sd_event`, `@jap_server`, `@ble_event`

### 4. Startup Sequence
- Started from `/app/start.sh`
- No command-line arguments passed
- Runs as background process
- Related processes: `cld_upd`, `andlink`, `noodles`

## What We Cannot Determine Without the Binary

1. **Command-line options**: Need to decompile to see if any are supported
2. **Configuration file locations**: May be hardcoded or use environment variables
3. **Internal logic**: How it handles video, network, cloud connections
4. **Dependencies**: What libraries it links against (need `ldd` or binary analysis)
5. **UPX unpacking**: Need to download and unpack to see actual code

## Recommendations for Full Analysis

### Option 1: Download via Alternative Method
If you have physical access or can enable other services:
- Enable SSH/SCP if possible
- Use USB/serial connection
- Enable FTP/TFTP service
- Use SD card to transfer

### Option 2: Analyze on Device
Since downloading is challenging, analyze on-device:
```bash
# Extract strings (even from UPX packed binary, some may be visible)
hexdump -C /app/abin/apollo | grep -E '[[:print:]]{4,}' > /tmp/apollo_strings.txt

# Check for config files
find /app -name "*apollo*" -o -name "*config*" | xargs grep -l apollo

# Monitor system calls
strace -p 637 -e trace=open,read,write,connect 2>&1 | head -100

# Check environment variables
cat /proc/637/environ | tr '\0' '\n'
```

### Option 3: Partial Download
Download in very small chunks (10KB) and combine, or use a different encoding method.

### Option 4: Runtime Analysis
Since we can't easily get the binary, focus on:
- **Network monitoring**: Capture packets to understand protocols
- **System call tracing**: Use `strace` to see file/network operations
- **Memory analysis**: If `/proc/637/mem` is accessible
- **Configuration discovery**: Find config files it reads

## Conclusion

**Most things appear to be hardcoded** based on:
1. No command-line arguments used
2. UPX packing suggests single-purpose binary
3. No config files found in standard locations
4. Direct invocation without parameters

However, there may be:
- Environment variables it reads
- Config files in non-standard locations
- Runtime configuration via the cloud connection
- Unix socket communication for control

## Next Steps

1. **Try runtime analysis** (strace, network capture)
2. **Search for config files** more thoroughly
3. **Attempt smaller chunk downloads** if full download needed
4. **Focus on replacement strategy** rather than full reverse engineering
