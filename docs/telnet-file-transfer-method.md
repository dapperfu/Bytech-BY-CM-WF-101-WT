# The Brilliant Method: File Transfer Over Telnet Using Base64 Encoding

## Overview

When working with IoT devices that only provide telnet access (no SSH, SCP, FTP, or other file transfer protocols), transferring files seems impossible at first glance. However, there exists an elegant solution that leverages base64 encoding and shell heredoc capabilities to transfer files bidirectionally using only telnet.

This document explains the core technique, why it works, and how to use it effectively.

## The Core Problem

Telnet is a text-based protocol designed for interactive terminal sessions. It has several limitations:

1. **No built-in file transfer**: Unlike SSH/SCP, telnet has no file transfer capabilities
2. **Text-only**: Telnet transmits data as text, making binary file transfer challenging
3. **Line length limits**: Many telnet implementations have limits on command line length
4. **No protocol support**: No built-in mechanisms for file upload/download

## The Brilliant Solution: Base64 + Heredoc

The solution combines three key techniques:

1. **Base64 Encoding**: Converts any file (binary or text) into ASCII-safe characters
2. **Shell Heredoc**: Uses shell heredoc syntax to create files with arbitrary content
3. **Chunked Transfer**: Breaks large files into manageable chunks to avoid line length limits

### Why Base64?

Base64 encoding transforms binary data into a 64-character alphabet (A-Z, a-z, 0-9, +, /) plus padding (=). This makes it:

- **Telnet-safe**: All characters are printable ASCII, safe for telnet transmission
- **Universal**: Works with any file type (scripts, binaries, images, etc.)
- **Standard**: Available on virtually all Unix-like systems via the `base64` command
- **Reversible**: Can be decoded back to original file with perfect fidelity

### Why Heredoc?

Shell heredoc (`cat > file << 'ENDOFFILE'`) allows creating files with arbitrary content:

- **No escaping needed**: Content between delimiters is taken literally
- **Handles special characters**: Works with any content, including newlines, quotes, etc.
- **Standard feature**: Available in all POSIX-compliant shells (sh, bash, etc.)

### Why Chunking?

Large base64 strings can exceed telnet command line limits. Chunking:

- **Avoids limits**: Sends content in smaller pieces (typically 1000 characters)
- **Maintains reliability**: Reduces risk of transmission errors
- **Works universally**: Compatible with all telnet implementations

## Method 1: Uploading Files (Local → Remote)

### The Process

1. **Encode locally**: Convert file to base64 on your local machine
2. **Connect via telnet**: Establish telnet session to remote device
3. **Create base64 file**: Use heredoc to write base64 content to temporary file
4. **Decode remotely**: Use `base64 -d` to decode the file
5. **Cleanup**: Remove temporary base64 file
6. **Verify**: Check that file exists and has correct content

### Step-by-Step Manual Method

#### Step 1: Encode File Locally

```bash
# Encode file to base64 (no line breaks)
base64 -w 0 myfile.sh > myfile.b64

# Or if -w flag not available:
base64 myfile.sh | tr -d '\n' > myfile.b64
```

#### Step 2: Connect via Telnet

```bash
telnet 10.0.0.227
# Login with credentials (e.g., root/hellotuya)
```

#### Step 3: Create Base64 File on Remote Device

```bash
# Use heredoc to create the base64 file
cat > /tmp/myfile.b64 << 'ENDOFFILE'
[paste entire base64 content here - can be very long]
ENDOFFILE
```

**Note**: The heredoc waits for the delimiter (`ENDOFFILE`). You paste the base64 content, then type `ENDOFFILE` on a new line to finish.

#### Step 4: Decode on Remote Device

```bash
# Decode base64 to original file
base64 -d /tmp/myfile.b64 > /tmp/myfile.sh

# Or if -d flag not available:
base64 -d < /tmp/myfile.b64 > /tmp/myfile.sh
```

#### Step 5: Verify and Cleanup

```bash
# Verify file exists and has content
ls -lh /tmp/myfile.sh
head -1 /tmp/myfile.sh  # Check first line (should show shebang for scripts)

# Make executable if it's a script
chmod +x /tmp/myfile.sh

# Clean up temporary base64 file
rm /tmp/myfile.b64
```

### Automated Method (Using Expect Script)

The manual method works but is tedious. The automated script (`transfer-file-telnet.sh`) handles all steps:

```bash
scripts/transfer-file-telnet.sh <target-ip> [username] [password] <local-file> [remote-path]
```

**Example:**
```bash
scripts/transfer-file-telnet.sh 10.0.0.227 root hellotuya scripts/setup.sh /tmp/
```

**How the automation works:**

1. Encodes file locally using `base64`
2. Uses `expect` to automate telnet interaction
3. Sends base64 content in chunks (1000 characters) via heredoc
4. Automatically decodes on remote device
5. Verifies transfer success
6. Handles errors and edge cases

**Key features:**
- Chunked transfer (1000 char chunks) to avoid line length limits
- Automatic base64 availability detection
- Fallback to HTTP method if base64 unavailable
- Error handling and verification
- Handles different shell prompts (# vs $)

## Method 2: Downloading Files (Remote → Local)

### The Process

1. **Connect via telnet**: Establish telnet session to remote device
2. **Encode remotely**: Use `base64` command on remote device to encode file
3. **Read base64**: Capture base64 output via telnet
4. **Decode locally**: Decode base64 on local machine to recover original file

### Step-by-Step Manual Method

#### Step 1: Connect and Encode on Remote Device

```bash
telnet 10.0.0.227
# Login with credentials

# Encode file to base64
base64 /app/abin/apollo > /tmp/apollo.b64
```

#### Step 2: Read Base64 Content

```bash
# Display base64 content (will be very long)
cat /tmp/apollo.b64
```

#### Step 3: Copy Base64 Content

Copy the entire base64 output from your terminal.

#### Step 4: Decode Locally

```bash
# Save base64 content to file
cat > apollo.b64 << 'EOF'
[paste base64 content here]
EOF

# Decode to original file
base64 -d apollo.b64 > apollo-binary

# Cleanup
rm apollo.b64
```

### Automated Method (Using Expect Script)

The automated script (`download-file-telnet.sh`) handles all steps:

```bash
scripts/download-file-telnet.sh <target-ip> [username] [password] <remote-file> [local-file]
```

**Example:**
```bash
scripts/download-file-telnet.sh 10.0.0.227 root hellotuya /app/abin/apollo ./apollo-binary
```

**How the automation works:**

1. Uses `expect` to automate telnet interaction
2. Encodes file on remote device using `base64`
3. Reads base64 content in chunks (handles expect buffer limits)
4. Cleans up base64 content (removes prompts, command echoes)
5. Decodes locally to recover original file
6. Verifies download success

**Key features:**
- Handles large files by reading in chunks
- Cleans telnet output (removes prompts, command echoes)
- Automatic error detection
- File verification

## Method 3: HTTP Server Fallback

When `base64` is not available on the remote device, the scripts fall back to an HTTP server method:

### How It Works

1. **Start HTTP server locally**: Python's built-in HTTP server on random high port
2. **Download via wget/curl**: Remote device downloads file using `wget` or `curl`
3. **Automatic cleanup**: Server stops after transfer completes

### Process

```bash
# Script automatically:
# 1. Detects local IP address
# 2. Starts Python HTTP server on random port (10000-65535)
# 3. Uses wget/curl on remote device to download
# 4. Stops server after transfer
```

**Advantages:**
- Works when base64 unavailable
- Faster for large files
- No encoding overhead

**Requirements:**
- Remote device must have `wget` or `curl`
- Network connectivity between devices
- Python on local machine

## Technical Details

### Chunking Strategy

The scripts use 1000-character chunks for base64 transfer:

- **Why 1000?**: Balances between efficiency and reliability
- **Telnet limits**: Most implementations handle 1000+ characters per line
- **Expect limits**: Expect has buffer size limits, chunking avoids overflow
- **Error recovery**: Smaller chunks mean less data lost if error occurs

### Heredoc Delimiter Selection

The scripts use `'ENDOFFILE'` as the heredoc delimiter:

- **Quoted delimiter**: Prevents variable expansion in content
- **Unique name**: Unlikely to appear in file content
- **Case-sensitive**: Reduces false matches

### Base64 Variants

Different systems have different `base64` implementations:

- **GNU coreutils**: `base64 -w 0` (no wrap), `base64 -d` (decode)
- **BusyBox**: `base64` (no wrap flag), `base64 -d` (decode)
- **macOS**: `base64` (no wrap by default), `base64 -D` (decode)

The scripts handle these variations automatically.

### Error Handling

The scripts include comprehensive error handling:

- **Connection failures**: Detects telnet connection issues
- **Authentication failures**: Handles login errors
- **Base64 availability**: Checks if base64 command exists
- **File verification**: Confirms file exists and has content
- **Decode verification**: For uploads, checks decoded file integrity

## Advantages of This Method

1. **Universal**: Works with any device that has telnet and base64
2. **No additional software**: Uses standard Unix tools
3. **Reliable**: Base64 encoding ensures data integrity
4. **Flexible**: Works with any file type (binary, text, scripts)
5. **Automated**: Scripts handle all complexity
6. **Bidirectional**: Can upload and download files

## Limitations

1. **Base64 overhead**: Increases file size by ~33%
2. **Speed**: Slower than dedicated file transfer protocols
3. **Large files**: Very large files may take significant time
4. **Base64 requirement**: Remote device needs `base64` command (or wget/curl for fallback)
5. **Network stability**: Requires stable telnet connection

## Best Practices

1. **Use /tmp/**: Most devices have writable `/tmp/` directory
2. **Verify transfers**: Always check file exists and has correct size
3. **Test execution**: For scripts, test execution after transfer
4. **Handle permissions**: Use `chmod +x` for executable files
5. **Cleanup**: Remove temporary base64 files after transfer
6. **Check line endings**: Some devices need Unix line endings (CRLF → LF)
7. **Monitor progress**: For large files, monitor transfer progress

## Real-World Examples

### Example 1: Transfer Setup Script

```bash
# Transfer a setup script to IoT device
scripts/transfer-file-telnet.sh 10.0.0.227 root hellotuya \
    scripts/setup-mitm-iptables-local.sh /tmp/

# Execute on device
telnet 10.0.0.227
sh /tmp/setup-mitm-iptables-local.sh
```

### Example 2: Download Binary for Analysis

```bash
# Download binary from device
scripts/download-file-telnet.sh 10.0.0.227 root hellotuya \
    /app/abin/apollo ./apollo-binary

# Analyze locally
file apollo-binary
strings apollo-binary | head -20
```

### Example 3: Transfer Multiple Files

```bash
# Transfer multiple files in sequence
for file in script1.sh script2.sh config.txt; do
    scripts/transfer-file-telnet.sh 10.0.0.227 root hellotuya \
        "$file" /tmp/
done
```

## Troubleshooting

### Problem: Heredoc Not Supported

**Symptoms**: Device doesn't recognize heredoc syntax

**Solution**: 
- Use HTTP fallback method: `FORCE_HTTP=1 scripts/transfer-file-telnet.sh ...`
- Or use echo method (manual, tedious)

### Problem: Base64 Command Not Found

**Symptoms**: Script reports "BASE64_NOT_AVAILABLE"

**Solution**:
- Script automatically falls back to HTTP method
- Or manually use HTTP method: `FORCE_HTTP=1`

### Problem: Transfer Incomplete

**Symptoms**: File exists but is corrupted or incomplete

**Solution**:
- Check telnet connection stability
- Verify base64 decode worked: `head -1 /tmp/file.sh`
- Try smaller chunks (modify script's chunk_size)
- Use HTTP method for more reliable transfer

### Problem: File Too Large

**Symptoms**: Transfer times out or fails

**Solution**:
- Use HTTP method (faster, more reliable)
- Compress file first: `gzip file.sh`, transfer, then `gunzip` on device
- Split into smaller files

### Problem: Permission Denied

**Symptoms**: Cannot write to target directory

**Solution**:
- Use `/tmp/` directory (usually writable)
- Check directory permissions: `ls -ld /path/to/dir`
- Use different target directory

## Security Considerations

1. **Credentials**: Telnet transmits credentials in plaintext
2. **Network**: Use on trusted networks only
3. **File verification**: Always verify transferred files
4. **Temporary files**: Clean up base64 files after transfer
5. **Permissions**: Be careful with executable files

## Conclusion

The base64 + heredoc method for file transfer over telnet is a brilliant solution to a common problem in IoT device management. By leveraging standard Unix tools and shell features, it enables file transfer where no dedicated protocol exists.

The automated scripts (`transfer-file-telnet.sh` and `download-file-telnet.sh`) make this technique practical for everyday use, handling all the complexity while providing robust error handling and fallback methods.

This method demonstrates that sometimes the most elegant solutions come from creatively combining simple, standard tools rather than requiring complex protocols or additional software.

## Related Documentation

- [File Transfer Telnet Guide](file-transfer-telnet.md) - Practical usage guide
- [MITMproxy Quick Start](mitmproxy-quick-start.md) - Using transferred scripts
- [Network Exposure Analysis](network-exposure.md) - Device analysis

## Scripts Reference

- `scripts/transfer-file-telnet.sh` - Upload files to device
- `scripts/download-file-telnet.sh` - Download files from device
