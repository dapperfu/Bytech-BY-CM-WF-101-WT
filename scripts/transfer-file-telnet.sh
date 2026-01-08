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
FORCE_HTTP="${FORCE_HTTP:-}"

# If base64 is known to not work, force HTTP method
if [[ "${FORCE_HTTP}" == "1" ]] || [[ "${FORCE_HTTP}" == "true" ]]; then
    USE_HTTP=1
else
    USE_HTTP=0
fi

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
    echo "The file will be transferred via telnet (base64 or HTTP method)."
    echo "Remote path defaults to /tmp/ if not specified."
    echo ""
    echo "Environment variables:"
    echo "  FORCE_HTTP=1  - Force HTTP transfer method (useful when base64 not available)"
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

log_warn() {
    log "WARN" "$@"
}

#######################################
# Base64 Encode File
#######################################
encode_file() {
    local file="$1"
    base64 -w 0 < "$file" || base64 < "$file" | tr -d '\n'
}

#######################################
# Transfer File via HTTP Server
#######################################
transfer_file_http() {
    log_info "Transferring file via HTTP server (no base64 required)..."
    
    # Get local IP address that remote device can reach
    local local_ip
    local_ip=$(ip route get "$TARGET_IP" 2>/dev/null | grep -oP 'src \K\S+' | head -1 || \
               ip addr show | grep -oP 'inet \K[0-9.]+' | grep -v '127.0.0.1' | head -1 || \
               hostname -I 2>/dev/null | awk '{print $1}' || \
               echo "127.0.0.1")
    
    # Use random high port (10000-65535)
    local http_port
    http_port=$((RANDOM % 55536 + 10000))
    
    # Get directory and filename
    local file_dir
    local file_name
    file_dir=$(dirname "$LOCAL_FILE")
    file_name=$(basename "$LOCAL_FILE")
    
    log_info "Starting HTTP server on $local_ip:$http_port"
    log_info "Serving file: $file_name"
    
    # Start HTTP server in background
    local server_pid
    if command -v python3 >/dev/null 2>&1; then
        cd "$file_dir" && python3 -m http.server "$http_port" >/dev/null 2>&1 &
        server_pid=$!
    elif command -v python >/dev/null 2>&1; then
        cd "$file_dir" && python -m SimpleHTTPServer "$http_port" >/dev/null 2>&1 &
        server_pid=$!
    else
        log_error "Python not found. Cannot start HTTP server."
        return 1
    fi
    
    # Wait a moment for server to start
    sleep 1
    
    # Check if server is running
    if ! kill -0 "$server_pid" 2>/dev/null; then
        log_error "Failed to start HTTP server"
        return 1
    fi
    
    # Cleanup function
    cleanup_server() {
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    }
    trap cleanup_server EXIT
    
    # Write expect script to download file via wget/curl
    local temp_expect
    temp_expect=$(mktemp)
    
    cat > "$temp_expect" <<EXPECT_HTTP_BASE
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
    "\$ " {
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

# Try wget first, then curl, then fail
send "if command -v wget >/dev/null 2>&1; then wget http://LOCAL_IP_VAL:HTTP_PORT_VAL/FILE_NAME_VAL -O REMOTE_FILE_VAL; elif command -v curl >/dev/null 2>&1; then curl http://LOCAL_IP_VAL:HTTP_PORT_VAL/FILE_NAME_VAL -o REMOTE_FILE_VAL; else echo 'DOWNLOAD_TOOL_MISSING'; fi\r"
expect {
    "DOWNLOAD_TOOL_MISSING" {
        puts "DOWNLOAD_TOOL_MISSING"
        send "exit\r"
        expect eof
        exit 1
    }
    "# " {}
    "\$ " {}
    timeout {
        puts "DOWNLOAD_TIMEOUT"
        send "exit\r"
        expect eof
        exit 1
    }
}

# Wait a moment for download to complete
sleep 2

# Make executable
send "chmod +x REMOTE_FILE_VAL 2>/dev/null || true\r"
expect {
    "# " {}
    "\$ " {}
    timeout {}
}

# Verify file exists and has content
send "test -f REMOTE_FILE_VAL && test -s REMOTE_FILE_VAL && echo 'FILE_EXISTS' || echo 'FILE_MISSING'\r"
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
EXPECT_HTTP_BASE
    
    # Replace placeholders
    sed -i "s|TIMEOUT_VAL|$COMMAND_TIMEOUT|g" "$temp_expect"
    sed -i "s|TARGET_IP_VAL|$TARGET_IP|g" "$temp_expect"
    sed -i "s|TELNET_PORT_VAL|$TELNET_PORT|g" "$temp_expect"
    sed -i "s|USERNAME_VAL|$USERNAME|g" "$temp_expect"
    sed -i "s|PASSWORD_VAL|$PASSWORD|g" "$temp_expect"
    sed -i "s|REMOTE_FILE_VAL|$REMOTE_FILE|g" "$temp_expect"
    sed -i "s|LOCAL_IP_VAL|$local_ip|g" "$temp_expect"
    sed -i "s|HTTP_PORT_VAL|$http_port|g" "$temp_expect"
    sed -i "s|FILE_NAME_VAL|$file_name|g" "$temp_expect"
    
    local result
    result=$(expect -f "$temp_expect" 2>&1)
    local expect_exit=$?
    
    # Cleanup server
    cleanup_server
    trap - EXIT
    
    rm -f "$temp_expect"
    
    if echo "$result" | grep -q "DOWNLOAD_TOOL_MISSING"; then
        log_error "Neither wget nor curl available on remote device"
        return 1
    elif echo "$result" | grep -q "TRANSFER_SUCCESS"; then
        log_success "File transferred successfully via HTTP: $REMOTE_FILE"
        return 0
    else
        log_error "HTTP transfer failed"
        echo "$result" | grep -v "^spawn telnet" | grep -v "^Trying" | head -20
        return 1
    fi
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
        
        # Check if base64 is available before trying to decode
        send "command -v base64 >/dev/null 2>&1 && echo 'BASE64_AVAILABLE' || echo 'BASE64_NOT_AVAILABLE'\r"
        expect {
            "BASE64_AVAILABLE" {
                # Decode base64 file
                send "base64 -d REMOTE_FILE_VAL.b64 > REMOTE_FILE_VAL 2>/dev/null || base64 -d REMOTE_FILE_VAL.b64 > REMOTE_FILE_VAL 2>&1\r"
                expect {
                    "# " {}
                    "$ " {}
                    timeout {}
                }
                # Verify decode worked by checking first line
                send "head -1 REMOTE_FILE_VAL 2>/dev/null | grep -q '^#!/' && echo 'DECODE_OK' || echo 'DECODE_FAILED'\r"
                expect {
                    "DECODE_FAILED" {
                        puts "BASE64_DECODE_FAILED"
                        send "rm -f REMOTE_FILE_VAL.b64 REMOTE_FILE_VAL\r"
                        expect {
                            "# " {}
                            "$ " {}
                            timeout {}
                        }
                        send "exit\r"
                        expect eof
                        return
                    }
                    "DECODE_OK" {
                        # Success, continue
                    }
                    "# " {}
                    "$ " {}
                    timeout {}
                }
            }
            "BASE64_NOT_AVAILABLE" {
                # Base64 not available - signal that we need direct transfer
                puts "BASE64_NOT_AVAILABLE"
                send "rm -f REMOTE_FILE_VAL.b64\r"
                expect {
                    "# " {}
                    "$ " {}
                    timeout {}
                }
                # Exit this expect block - we'll handle direct transfer in main function
                send "exit\r"
                expect eof
                return
            }
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
        
        # Fix shebang if bash not available (for BusyBox systems) and ensure Unix line endings
        send "command -v bash >/dev/null 2>&1 || sed -i '1s|#!/usr/bin/env bash|#!/bin/sh|' REMOTE_FILE_VAL 2>/dev/null\r"
        expect {
            "# " {}
            "$ " {}
            timeout {}
        }
        
        # Ensure Unix line endings (remove any CR characters)
        send "sed -i 's/\r$//' REMOTE_FILE_VAL 2>/dev/null || tr -d '\r' < REMOTE_FILE_VAL > REMOTE_FILE_VAL.tmp && mv REMOTE_FILE_VAL.tmp REMOTE_FILE_VAL\r"
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
    
    if echo "$result" | grep -q "BASE64_NOT_AVAILABLE\|BASE64_DECODE_FAILED"; then
        log_warn "base64 not available or decode failed on remote device, using HTTP transfer method"
        return 2  # Special return code for base64 not available
    elif echo "$result" | grep -q "TRANSFER_SUCCESS"; then
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
    
    # Try HTTP method first if forced, or base64 method with HTTP fallback
    if [ "$USE_HTTP" -eq 1 ]; then
        log_info "Using HTTP transfer method (forced)"
        if transfer_file_http; then
            log_success "HTTP transfer complete"
            log_info "File is available at: $REMOTE_FILE"
            log_info ""
            log_info "To execute on remote device:"
            log_info "  sh $REMOTE_FILE"
            exit 0
        else
            log_error "HTTP transfer failed"
            exit 1
        fi
    fi
    
    # Try base64 method first, fallback to HTTP if base64 not available
    transfer_file
    local transfer_result=$?
    
    if [ "$transfer_result" -eq 0 ]; then
        log_success "Transfer complete"
        log_info "File is available at: $REMOTE_FILE"
        log_info ""
        log_info "To execute on remote device:"
        log_info "  sh $REMOTE_FILE"
        log_info "  OR if bash is available:"
        log_info "  $REMOTE_FILE"
        log_info ""
        log_info "Note: If script uses bash syntax and device only has sh, use 'sh' to run it"
        exit 0
    elif [ "$transfer_result" -eq 2 ]; then
        log_warn "base64 not available on remote device, using HTTP server method..."
        if transfer_file_http; then
            log_success "HTTP transfer complete"
            log_info "File is available at: $REMOTE_FILE"
            log_info ""
            log_info "To execute on remote device:"
            log_info "  sh $REMOTE_FILE"
            exit 0
        else
            log_error "HTTP transfer failed"
            exit 1
        fi
    else
        log_warn "Base64 transfer failed, trying HTTP server method..."
        if transfer_file_http; then
            log_success "HTTP transfer complete"
            log_info "File is available at: $REMOTE_FILE"
            log_info ""
            log_info "To execute on remote device:"
            log_info "  sh $REMOTE_FILE"
            exit 0
        else
            log_error "All transfer methods failed"
            exit 1
        fi
    fi
}

main "$@"
