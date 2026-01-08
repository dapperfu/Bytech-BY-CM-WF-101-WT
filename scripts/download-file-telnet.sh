#!/usr/bin/env bash
set -euo pipefail

#######################################
# Download File Over Telnet Script
# Downloads files from remote devices using only telnet access
#######################################

TARGET_IP="${1:-}"
USERNAME="${2:-root}"
PASSWORD="${3:-hellotuya}"
REMOTE_FILE="${4:-}"
LOCAL_FILE="${5:-}"

TELNET_PORT="${TELNET_PORT:-23}"
COMMAND_TIMEOUT="${COMMAND_TIMEOUT:-60}"

# Check if expect is available
if ! command -v expect >/dev/null 2>&1; then
    echo "[!] Error: expect is not installed"
    echo "[*] Install with: apt-get install expect  or  yum install expect"
    exit 1
fi

if [[ -z "$TARGET_IP" ]] || [[ -z "$REMOTE_FILE" ]]; then
    echo "Usage: $0 <target-ip> [username] [password] <remote-file> [local-file]"
    echo ""
    echo "Example:"
    echo "  $0 10.0.0.227 root hellotuya /app/abin/apollo ./apollo-binary"
    echo "  $0 10.0.0.227 root hellotuya /app/start.sh ./start.sh"
    echo ""
    echo "The file will be downloaded via telnet (base64 encoding)."
    echo "Local file defaults to ./<basename> if not specified."
    exit 1
fi

# Default local file name if not specified
if [[ -z "$LOCAL_FILE" ]]; then
    LOCAL_FILE="./$(basename "$REMOTE_FILE")"
fi

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

log_success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] $*"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

log_warn() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] $*"
}

#######################################
# Download File via Telnet (Base64)
#######################################
download_file() {
    log_info "Downloading file: $REMOTE_FILE"
    log_info "Target: $TARGET_IP:$REMOTE_FILE"
    log_info "Local destination: $LOCAL_FILE"
    
    # Create temp file for base64 content
    local temp_b64
    temp_b64=$(mktemp)
    
    # Create expect script
    local temp_expect
    temp_expect=$(mktemp)
    
    cat > "$temp_expect" <<'EXPECT_SCRIPT_BASE'
set timeout TIMEOUT_VAL
log_user 0

spawn telnet TARGET_IP_VAL TELNET_PORT_VAL
expect {
    "login:" {
        send "USERNAME_VAL\r"
        exp_continue
    }
    "Login:" {
        send "USERNAME_VAL\r"
        exp_continue
    }
    "Username:" {
        send "USERNAME_VAL\r"
        exp_continue
    }
    "Password:" {
        send "PASSWORD_VAL\r"
        exp_continue
    }
    "password:" {
        send "PASSWORD_VAL\r"
        exp_continue
    }
    "# " {
        # Got prompt, proceed
    }
    "$ " {
        # Got prompt, proceed
    }
    timeout {
        puts "CONNECTION_TIMEOUT"
        exit 1
    }
    eof {
        puts "CONNECTION_CLOSED"
        exit 1
    }
}

# Check if file exists
send "test -f REMOTE_FILE_VAL && echo 'FILE_EXISTS' || echo 'FILE_MISSING'\r"
expect {
    "FILE_EXISTS" {
        # File exists, continue
    }
    "FILE_MISSING" {
        puts "FILE_NOT_FOUND"
        send "exit\r"
        expect eof
        exit 1
    }
    "# " {}
    "$ " {}
    timeout {
        puts "CHECK_TIMEOUT"
        send "exit\r"
        expect eof
        exit 1
    }
}

# Check if base64 is available
send "command -v base64 >/dev/null 2>&1 && echo 'BASE64_AVAILABLE' || echo 'BASE64_NOT_AVAILABLE'\r"
expect {
    "BASE64_AVAILABLE" {
        # Base64 available, use it
    }
    "BASE64_NOT_AVAILABLE" {
        puts "BASE64_NOT_AVAILABLE"
        send "exit\r"
        expect eof
        exit 1
    }
    "# " {}
    "$ " {}
    timeout {
        puts "BASE64_CHECK_TIMEOUT"
        send "exit\r"
        expect eof
        exit 1
    }
}

# Get file size for progress (skip this for now - causes regex issues)
# send "wc -c < REMOTE_FILE_VAL\r"
# expect {
#     "# " {}
#     "$ " {}
#     timeout {}
# }

# Encode file to base64 and save to temp file
send "base64 REMOTE_FILE_VAL > /tmp/file_download.b64\r"
expect {
    "# " {}
    "$ " {}
    timeout {
        puts "ENCODE_TIMEOUT"
        send "exit\r"
        expect eof
        exit 1
    }
}

# Read the base64 file in chunks (expect has buffer limits)
log_user 1
set encoded_content ""
send "cat /tmp/file_download.b64\r"
expect {
    -re "(.+)" {
        append encoded_content $expect_out(buffer)
        exp_continue
    }
    "# " {
        # Got prompt, done reading
    }
    "$ " {
        # Got prompt, done reading
    }
    timeout {
        puts "READ_TIMEOUT"
        send "exit\r"
        expect eof
        exit 1
    }
}
log_user 0

# Clean up temp file
send "rm -f /tmp/file_download.b64\r"
expect {
    "# " {}
    "$ " {}
    timeout {}
}

# Exit telnet
send "exit\r"
expect eof

# Output base64 content (clean it up)
set clean_content [string trim $encoded_content]
# Remove command echo and prompts
regsub -all {base64.*\r\n} $clean_content {} clean_content
regsub -all {cat.*\r\n} $clean_content {} clean_content
regsub -all {rm.*\r\n} $clean_content {} clean_content
regsub -all {# |\$ } $clean_content {} clean_content
regsub -all {\r\n} $clean_content {} clean_content
regsub -all {\n} $clean_content {} clean_content
puts $clean_content
EXPECT_SCRIPT_BASE
    
    # Replace placeholders
    sed -i "s|TIMEOUT_VAL|$COMMAND_TIMEOUT|g" "$temp_expect"
    sed -i "s|TARGET_IP_VAL|$TARGET_IP|g" "$temp_expect"
    sed -i "s|TELNET_PORT_VAL|$TELNET_PORT|g" "$temp_expect"
    sed -i "s|USERNAME_VAL|$USERNAME|g" "$temp_expect"
    sed -i "s|PASSWORD_VAL|$PASSWORD|g" "$temp_expect"
    sed -i "s|REMOTE_FILE_VAL|$REMOTE_FILE|g" "$temp_expect"
    
    log_info "Connecting to device and encoding file..."
    
    # Run expect and capture base64 output
    local result
    result=$(expect -f "$temp_expect" 2>&1)
    local expect_exit=$?
    
    rm -f "$temp_expect"
    
    # Check for errors
    if echo "$result" | grep -q "CONNECTION_TIMEOUT\|CONNECTION_CLOSED"; then
        log_error "Failed to connect to device"
        echo "$result" | grep -v "^spawn telnet" | grep -v "^Trying" | head -10
        return 1
    fi
    
    if echo "$result" | grep -q "FILE_NOT_FOUND"; then
        log_error "File not found on remote device: $REMOTE_FILE"
        return 1
    fi
    
    if echo "$result" | grep -q "BASE64_NOT_AVAILABLE"; then
        log_error "base64 command not available on remote device"
        return 1
    fi
    
    if echo "$result" | grep -q "ENCODE_TIMEOUT\|CHECK_TIMEOUT"; then
        log_error "Timeout during file encoding"
        return 1
    fi
    
    # Extract base64 content
    # The expect script outputs the base64, we need to extract it
    # Look for lines that look like base64 (alphanumeric, +, /, =)
    local base64_content
    base64_content=$(echo "$result" | \
        grep -v "^spawn telnet" | \
        grep -v "^Trying" | \
        grep -v "^Connected" | \
        grep -v "login:" | \
        grep -v "Login:" | \
        grep -v "Username:" | \
        grep -v "Password:" | \
        grep -v "password:" | \
        grep -v "FILE_EXISTS" | \
        grep -v "BASE64_AVAILABLE" | \
        grep -v "FILE_MISSING" | \
        grep -v "BASE64_NOT_AVAILABLE" | \
        grep -v "CONNECTION" | \
        grep -v "TIMEOUT" | \
        grep -v "READ_TIMEOUT" | \
        grep -v "ENCODE_TIMEOUT" | \
        grep -v "exit" | \
        grep -v "^$" | \
        sed 's/^[[:space:]]*//' | \
        sed 's/[[:space:]]*$//' | \
        tr -d '\r' | \
        grep -E '^[A-Za-z0-9+/=]+$' | \
        tr -d '\n')
    
    # If that didn't work, try a different approach - get everything between cat and prompt
    if [[ -z "$base64_content" ]] || [[ ${#base64_content} -lt 100 ]]; then
        log_warn "First extraction method failed, trying alternative..."
        # Find the line with "cat" and extract everything after it until prompt
        base64_content=$(echo "$result" | \
            sed -n '/cat \/tmp\/file_download\.b64/,/# \|$ /p' | \
            grep -v "cat /tmp/file_download.b64" | \
            grep -v "^#" | \
            grep -v "^\$" | \
            grep -v "^$" | \
            sed 's/^[[:space:]]*//' | \
            sed 's/[[:space:]]*$//' | \
            tr -d '\r\n')
    fi
    
    if [[ -z "$base64_content" ]] || [[ ${#base64_content} -lt 100 ]]; then
        log_error "Failed to extract base64 content from output"
        log_error "Base64 length: ${#base64_content}"
        log_error "Raw output (last 100 lines):"
        echo "$result" | tail -100 > /tmp/download-debug.txt
        echo "Debug output saved to /tmp/download-debug.txt"
        return 1
    fi
    
    log_info "Extracted base64 content (${#base64_content} characters)"
    
    # Save base64 to temp file
    echo -n "$base64_content" > "$temp_b64"
    
    log_info "Decoding base64 content..."
    
    # Decode base64
    if ! base64 -d "$temp_b64" > "$LOCAL_FILE" 2>/dev/null; then
        # Try alternative base64 decode
        if ! base64 -d < "$temp_b64" > "$LOCAL_FILE" 2>/dev/null; then
            log_error "Failed to decode base64 content"
            rm -f "$temp_b64"
            return 1
        fi
    fi
    
    rm -f "$temp_b64"
    
    # Verify file was created and has content
    if [[ ! -f "$LOCAL_FILE" ]] || [[ ! -s "$LOCAL_FILE" ]]; then
        log_error "Downloaded file is empty or missing"
        return 1
    fi
    
    local file_size
    file_size=$(stat -f%z "$LOCAL_FILE" 2>/dev/null || stat -c%s "$LOCAL_FILE" 2>/dev/null || echo "unknown")
    log_success "File downloaded successfully: $LOCAL_FILE ($file_size bytes)"
    return 0
}

#######################################
# Main Execution
#######################################
main() {
    log_info "File Download Over Telnet"
    log_info "=========================="
    
    if download_file; then
        log_success "Download complete!"
        exit 0
    else
        log_error "Download failed!"
        exit 1
    fi
}

main "$@"
