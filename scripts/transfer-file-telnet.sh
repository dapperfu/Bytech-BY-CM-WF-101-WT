#!/usr/bin/env bash
set -euo pipefail

#######################################
# Transfer File Over Telnet Script
# Transfers files to remote devices using only telnet access
#######################################

TARGET_IP="${1:-}"
USERNAME="${2:-root}"
PASSWORD="${3:-hellotuya}"
LOCAL_FILE="${4:-}"
REMOTE_PATH="${5:-/tmp/}"

# Default credentials from README
if [[ "$USERNAME" == "user" ]] && [[ "$PASSWORD" == "hellotuya" ]]; then
    PASSWORD="user123"
fi

TELNET_PORT="${TELNET_PORT:-23}"
COMMAND_TIMEOUT="${COMMAND_TIMEOUT:-30}"

# Check if expect is available
if ! command -v expect >/dev/null 2>&1; then
    echo "[!] Error: expect is not installed"
    echo "[*] Install with: apt-get install expect  or  yum install expect"
    exit 1
fi

if [[ -z "$TARGET_IP" ]] || [[ -z "$LOCAL_FILE" ]]; then
    echo "Usage: $0 <target-ip> [username] [password] <local-file> [remote-path]"
    echo ""
    echo "Example:"
    echo "  $0 10.0.0.227 root hellotuya scripts/setup-mitm-iptables-local.sh /tmp/"
    echo "  $0 10.0.0.227 root hellotuya script.sh /app/abin/"
    echo ""
    echo "The file will be base64 encoded and transferred via telnet."
    echo "Remote path defaults to /tmp/ if not specified."
    echo ""
    if [[ -n "$1" ]] && [[ ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "[!] Error: First argument must be target IP address (e.g., 10.0.0.227)"
        echo "[!] You provided: $1"
    fi
    exit 1
fi

if [[ ! -f "$LOCAL_FILE" ]]; then
    echo "[!] Error: Local file not found: $LOCAL_FILE"
    echo ""
    echo "Check that:"
    echo "  1. The file path is correct"
    echo "  2. You provided the target IP as the first argument"
    echo "  3. All arguments are in the correct order"
    echo ""
    echo "Correct usage: $0 <target-ip> [username] [password] <local-file> [remote-path]"
    exit 1
fi

# Get filename from path
REMOTE_FILENAME=$(basename "$LOCAL_FILE")
REMOTE_FILE="${REMOTE_PATH}${REMOTE_FILENAME}"

#######################################
# Logging Functions
#######################################
log() {
    local level="${1:-INFO}"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message"
}

log_info() {
    log "INFO" "$@"
}

log_error() {
    log "ERROR" "$@"
}

log_success() {
    log "SUCCESS" "$@"
}

#######################################
# Base64 Encode File
#######################################
encode_file() {
    local file="$1"
    base64 -w 0 < "$file" || base64 < "$file" | tr -d '\n'
}

#######################################
# Transfer File via Telnet
#######################################
transfer_file() {
    local encoded_content
    encoded_content=$(encode_file "$LOCAL_FILE")
    local file_size=${#encoded_content}
    
    log_info "Transferring file: $LOCAL_FILE"
    log_info "Target: $TARGET_IP:$REMOTE_FILE"
    log_info "File size: $file_size bytes (base64 encoded)"
    
    # Split into chunks if too large (some telnet implementations have line length limits)
    local chunk_size=1000
    local total_chunks=$(( (file_size + chunk_size - 1) / chunk_size ))
    
    log_info "Transferring in $total_chunks chunks..."
    
    # Write expect script to temp file with encoded content properly escaped
    local temp_expect
    temp_expect=$(mktemp)
    local temp_encoded
    temp_encoded=$(mktemp)
    echo "$encoded_content" > "$temp_encoded"
    
    # Create expect script that reads encoded content from file
    # Use simpler pattern matching to avoid regex issues
    cat > "$temp_expect" <<'EXPECT_SCRIPT_BASE'
set timeout TIMEOUT_VAL
log_user 0

# Read encoded content from file
set f [open "ENCODED_FILE" r]
set encoded_content [read $f]
close $f
set encoded [string trim $encoded_content]

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

# Create remote file using heredoc
send "cat > REMOTE_FILE_VAL.b64 << 'ENDOFFILE'\r"
expect {
    "> " {
        # Send base64 content in chunks
        set len [string length $encoded]
        set chunk_size 1000
        set i 0
        while {$i < $len} {
            set chunk [string range $encoded $i [expr $i + $chunk_size - 1]]
            send "$chunk\r"
            set i [expr $i + $chunk_size]
            expect {
                "> " {
                    # Continue
                }
                timeout {
                    puts "CHUNK_TIMEOUT"
                    break
                }
            }
        }
        send "ENDOFFILE\r"
        expect {
            "# " {}
            "$ " {}
            timeout {
                puts "HEREDOC_END_TIMEOUT"
            }
        }
        
        # Decode base64 file
        send "base64 -d REMOTE_FILE_VAL.b64 > REMOTE_FILE_VAL 2>/dev/null || base64 -d REMOTE_FILE_VAL.b64 > REMOTE_FILE_VAL 2>&1\r"
        expect {
            "# " {}
            "$ " {}
            timeout {}
        }
        
        # Remove base64 file
        send "rm -f REMOTE_FILE_VAL.b64\r"
        expect {
            "# " {}
            "$ " {}
            timeout {}
        }
        
        # Make executable if it's a script
        send "chmod +x REMOTE_FILE_VAL 2>/dev/null || true\r"
        expect {
            "# " {}
            "$ " {}
            timeout {}
        }
        
        # Verify file exists
        send "test -f REMOTE_FILE_VAL && echo 'FILE_EXISTS' || echo 'FILE_MISSING'\r"
        expect {
            "FILE_EXISTS" {
                puts "TRANSFER_SUCCESS"
            }
            "FILE_MISSING" {
                puts "TRANSFER_FAILED"
            }
            timeout {
                puts "VERIFY_TIMEOUT"
            }
        }
        send "exit\r"
        expect eof
    }
    timeout {
        puts "HEREDOC_TIMEOUT"
        send "\x03"
        send "exit\r"
        expect eof
    }
}
EXPECT_SCRIPT_BASE
    
    # Replace placeholders in expect script
    sed -i "s|TIMEOUT_VAL|$COMMAND_TIMEOUT|g" "$temp_expect"
    sed -i "s|ENCODED_FILE|$temp_encoded|g" "$temp_expect"
    sed -i "s|TARGET_IP_VAL|$TARGET_IP|g" "$temp_expect"
    sed -i "s|TELNET_PORT_VAL|$TELNET_PORT|g" "$temp_expect"
    sed -i "s|USERNAME_VAL|$USERNAME|g" "$temp_expect"
    sed -i "s|PASSWORD_VAL|$PASSWORD|g" "$temp_expect"
    sed -i "s|REMOTE_FILE_VAL|$REMOTE_FILE|g" "$temp_expect"
    
    local result
    result=$(expect -f "$temp_expect" 2>&1)
    
    rm -f "$temp_expect" "$temp_encoded"
    
    if echo "$result" | grep -q "TRANSFER_SUCCESS"; then
        log_success "File transferred successfully: $REMOTE_FILE"
        return 0
    elif echo "$result" | grep -q "TRANSFER_FAILED\|FILE_MISSING"; then
        log_error "File transfer failed - file not found on remote"
        echo "$result" | grep -v "^spawn telnet" | grep -v "^Trying" | head -20
        return 1
    else
        log_error "File transfer failed"
        echo "$result" | grep -v "^spawn telnet" | grep -v "^Trying" | head -20
        return 1
    fi
}

#######################################
# Main Execution
#######################################
main() {
    log_info "File Transfer Over Telnet"
    log_info "=========================="
    log_info "Target: $TARGET_IP"
    log_info "Local file: $LOCAL_FILE"
    log_info "Remote path: $REMOTE_FILE"
    
    if transfer_file; then
        log_success "Transfer complete"
        log_info "File is available at: $REMOTE_FILE"
        log_info "To execute: telnet $TARGET_IP && chmod +x $REMOTE_FILE && $REMOTE_FILE"
        exit 0
    else
        log_error "Transfer failed"
        exit 1
    fi
}

main "$@"
