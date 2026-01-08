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
    
    local expect_script
    expect_script=$(cat <<EOF
set timeout $COMMAND_TIMEOUT
log_user 0
spawn telnet $TARGET_IP $TELNET_PORT
expect {
    "login:" {
        send "$USERNAME\r"
        exp_continue
    }
    "Login:" {
        send "$USERNAME\r"
        exp_continue
    }
    "Username:" {
        send "$USERNAME\r"
        exp_continue
    }
    "Password:" {
        send "$PASSWORD\r"
        exp_continue
    }
    "password:" {
        send "$PASSWORD\r"
        exp_continue
    }
    -re "\\\[.*\\\]# |# |\\\$ " {
        # Create remote file
        send "cat > $REMOTE_FILE.b64 << 'ENDOFFILE'\r"
        expect {
            -re "> " {
                # Send base64 content in chunks
                set encoded "$encoded_content"
                set len [string length \$encoded]
                set chunk_size 1000
                set i 0
                while {\$i < \$len} {
                    set chunk [string range \$encoded \$i [expr \$i + \$chunk_size - 1]]
                    send "\$chunk\r"
                    set i [expr \$i + \$chunk_size]
                    expect {
                        -re "> " {
                            # Continue
                        }
                        timeout {
                            puts "CHUNK_TIMEOUT"
                            break
                        }
                    }
                }
                send "ENDOFFILE\r"
                expect -re "\\\[.*\\\]# |# |\\\$ "
                
                # Decode base64 file
                send "base64 -d $REMOTE_FILE.b64 > $REMOTE_FILE 2>/dev/null || base64 -d $REMOTE_FILE.b64 > $REMOTE_FILE 2>&1\r"
                expect -re "\\\[.*\\\]# |# |\\\$ "
                
                # Remove base64 file
                send "rm -f $REMOTE_FILE.b64\r"
                expect -re "\\\[.*\\\]# |# |\\\$ "
                
                # Make executable if it's a script
                send "chmod +x $REMOTE_FILE 2>/dev/null || true\r"
                expect -re "\\\[.*\\\]# |# |\\\$ "
                
                # Verify file exists
                send "test -f $REMOTE_FILE && echo 'FILE_EXISTS' || echo 'FILE_MISSING'\r"
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
    }
    "BusyBox" {
        expect {
            -re "\\\[.*\\\]# |# |\\\$ " {
                # BusyBox version - use printf instead of heredoc
                send "rm -f $REMOTE_FILE.b64\r"
                expect -re "\\\[.*\\\]# |# |\\\$ "
                
                # Use echo to write base64 (may need to split)
                set encoded "$encoded_content"
                set len [string length \$encoded]
                set chunk_size 500
                set i 0
                while {\$i < \$len} {
                    set chunk [string range \$encoded \$i [expr \$i + \$chunk_size - 1]]
                    if {\$i == 0} {
                        send "echo -n '\$chunk' > $REMOTE_FILE.b64\r"
                    } else {
                        send "echo -n '\$chunk' >> $REMOTE_FILE.b64\r"
                    }
                    expect -re "\\\[.*\\\]# |# |\\\$ "
                    set i [expr \$i + \$chunk_size]
                }
                
                # Decode
                send "base64 -d $REMOTE_FILE.b64 > $REMOTE_FILE 2>/dev/null || base64 -d $REMOTE_FILE.b64 > $REMOTE_FILE 2>&1\r"
                expect -re "\\\[.*\\\]# |# |\\\$ "
                
                # Cleanup and verify
                send "rm -f $REMOTE_FILE.b64\r"
                expect -re "\\\[.*\\\]# |# |\\\$ "
                send "chmod +x $REMOTE_FILE 2>/dev/null || true\r"
                expect -re "\\\[.*\\\]# |# |\\\$ "
                send "test -f $REMOTE_FILE && echo 'FILE_EXISTS' || echo 'FILE_MISSING'\r"
                expect {
                    "FILE_EXISTS" {
                        puts "TRANSFER_SUCCESS"
                    }
                    "FILE_MISSING" {
                        puts "TRANSFER_FAILED"
                    }
                }
                send "exit\r"
                expect eof
            }
            timeout {
                puts "PROMPT_TIMEOUT"
                exit 1
            }
        }
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
EOF
)
    
    # Replace encoded_content in expect script
    local temp_expect
    temp_expect=$(mktemp)
    echo "$expect_script" | sed "s|set encoded \".*\"|set encoded \"$encoded_content\"|" > "$temp_expect"
    
    local result
    result=$(expect -f "$temp_expect" 2>&1)
    
    rm -f "$temp_expect"
    
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
