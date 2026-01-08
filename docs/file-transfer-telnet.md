# Transferring Files Over Telnet

## Overview

When working with IoT devices that only have telnet access (no SSH, SCP, or other file transfer methods), you need alternative methods to transfer files. This guide covers several approaches.

## Method 1: Automated Script (Recommended)

Use the provided script to automatically transfer files:

```bash
scripts/transfer-file-telnet.sh <target-ip> [username] [password] <local-file> [remote-path]
```

**Example:**
```bash
# Transfer setup script to /tmp/
scripts/transfer-file-telnet.sh 10.0.0.227 root hellotuya scripts/setup-mitm-iptables-local.sh /tmp/

# Transfer to specific directory
scripts/transfer-file-telnet.sh 10.0.0.227 root hellotuya script.sh /app/abin/
```

**How it works:**
1. Base64 encodes the file
2. Transfers via telnet using heredoc or echo
3. Decodes on remote device
4. Makes file executable
5. Verifies transfer success

## Method 2: Manual Base64 Transfer

If the automated script doesn't work, you can transfer manually:

### Step 1: Encode File Locally

```bash
base64 -w 0 scripts/setup-mitm-iptables-local.sh > file.b64
# Or if -w flag not available:
base64 scripts/setup-mitm-iptables-local.sh | tr -d '\n' > file.b64
```

### Step 2: Connect via Telnet

```bash
telnet 10.0.0.227
# Login with credentials
```

### Step 3: Create File on Remote

**Option A: Using heredoc (if supported):**
```bash
cat > /tmp/setup-mitm-iptables-local.sh.b64 << 'ENDOFFILE'
[paste base64 content here]
ENDOFFILE
```

**Option B: Using echo (BusyBox):**
```bash
# Copy base64 content in chunks (500-1000 chars at a time)
echo -n 'chunk1...' > /tmp/file.b64
echo -n 'chunk2...' >> /tmp/file.b64
# ... continue for all chunks
```

### Step 4: Decode on Remote

```bash
base64 -d /tmp/setup-mitm-iptables-local.sh.b64 > /tmp/setup-mitm-iptables-local.sh
# Or if -d not available:
base64 -d /tmp/setup-mitm-iptables-local.sh.b64 > /tmp/setup-mitm-iptables-local.sh
```

### Step 5: Make Executable and Cleanup

```bash
chmod +x /tmp/setup-mitm-iptables-local.sh
rm /tmp/setup-mitm-iptables-local.sh.b64
```

## Method 3: HTTP Server + wget/curl

If the device has `wget` or `curl` available:

### Step 1: Start HTTP Server Locally

```bash
# In project directory
python3 -m http.server 8000
```

### Step 2: Download on Remote Device

```bash
# Via telnet
telnet 10.0.0.227
# After login:
wget http://<your-ip>:8000/scripts/setup-mitm-iptables-local.sh -O /tmp/setup-mitm-iptables-local.sh
# Or with curl:
curl http://<your-ip>:8000/scripts/setup-mitm-iptables-local.sh -o /tmp/setup-mitm-iptables-local.sh
chmod +x /tmp/setup-mitm-iptables-local.sh
```

## Method 4: Netcat (if available)

If both devices have `netcat`:

### On Remote Device (via telnet):
```bash
nc -l -p 1234 > /tmp/setup-mitm-iptables-local.sh
```

### On Local Machine:
```bash
nc 10.0.0.227 1234 < scripts/setup-mitm-iptables-local.sh
```

## Method 5: Manual Copy-Paste (Small Files)

For very small files, you can manually copy-paste:

1. Open file locally
2. Copy contents
3. Connect via telnet
4. Use `cat > filename.sh` and paste
5. Press Ctrl+D to finish

## Troubleshooting

### Problem: Heredoc not supported
**Solution**: Use echo method or automated script with BusyBox detection

### Problem: Base64 command not found
**Solution**: Check if device has base64:
```bash
which base64
# If not available, may need to use uuencode/uudecode or other encoding
```

### Problem: File too large
**Solution**: 
- Split into smaller chunks
- Use HTTP server method if available
- Compress file first: `gzip file.sh` then transfer

### Problem: Transfer incomplete
**Solution**:
- Check telnet connection stability
- Use smaller chunks
- Verify file on remote: `ls -lh /tmp/file.sh`

## Best Practices

1. **Always verify transfer**: Check file exists and has correct size
2. **Test execution**: Run `chmod +x` and test script execution
3. **Use /tmp/**: Most devices have writable /tmp/ directory
4. **Check permissions**: Ensure target directory is writable
5. **Keep backups**: Don't overwrite important files without backup

## Related Documentation

- [MITMproxy Quick Start](mitmproxy-quick-start.md)
- [MITMproxy In-Depth Guide](mitmproxy-in-depth.md)
