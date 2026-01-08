#!/usr/bin/env bash
set -euo pipefail

#######################################
# Local RTSP Server Setup Script
# Sets up a local RTSP server to serve video from the webcam
#######################################

TARGET_IP="${1:-}"
USERNAME="${2:-root}"
PASSWORD="${3:-hellotuya}"
RTSP_STREAM_PATH="${4:-/stream1}"
RTSP_PORT="${5:-8554}"

# Default credentials from README
if [[ "$USERNAME" == "user" ]] && [[ "$PASSWORD" == "hellotuya" ]]; then
    PASSWORD="user123"
fi

TELNET_PORT="${TELNET_PORT:-23}"
COMMAND_TIMEOUT="${COMMAND_TIMEOUT:-30}"

# Check if expect is available
if ! command -v expect &> /dev/null; then
    echo "[!] Error: expect is not installed"
    echo "[*] Install with: apt-get install expect  or  yum install expect"
    exit 1
fi

if [[ -z "$TARGET_IP" ]]; then
    echo "Usage: $0 <target-ip> [username] [password] [rtsp-stream-path] [rtsp-port]"
    echo ""
    echo "Example:"
    echo "  $0 10.0.0.227 root hellotuya /stream1 8554"
    echo ""
    echo "Note: This script provides instructions and helper functions for setting up"
    echo "      a local RTSP server. The actual RTSP server binary must be compatible"
    echo "      with the FH8616 ARM architecture (ARMv6/ARMv7)."
    exit 1
fi

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

log_warn() {
    log "WARN" "$@"
}

log_success() {
    log "SUCCESS" "$@"
}

#######################################
# Expect-Based Telnet Handler
#######################################
execute_command() {
    local cmd="$1"
    local timeout="${2:-$COMMAND_TIMEOUT}"
    local expect_script
    
    expect_script=$(cat <<EOF
set timeout $timeout
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
        send "$cmd\r"
        expect {
            -re "\\\[.*\\\]# |# |\\\$ " {
                puts \$expect_out(buffer)
                send "exit\r"
                expect eof
            }
            timeout {
                puts \$expect_out(buffer)
                puts "COMMAND_TIMEOUT"
                send "\x03"
                send "exit\r"
                expect eof
            }
        }
    }
    "BusyBox" {
        expect {
            -re "\\\[.*\\\]# |# |\\\$ " {
                send "$cmd\r"
                expect {
                    -re "\\\[.*\\\]# |# |\\\$ " {
                        puts \$expect_out(buffer)
                        send "exit\r"
                        expect eof
                    }
                    timeout {
                        puts \$expect_out(buffer)
                        puts "COMMAND_TIMEOUT"
                        send "\x03"
                        send "exit\r"
                        expect eof
                    }
                }
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
    
    local result
    local temp_output
    temp_output=$(mktemp)
    
    echo "$expect_script" | expect 2>&1 > "$temp_output"
    
    # Escape forward slashes in cmd for sed
    local cmd_escaped
    cmd_escaped=$(echo "$cmd" | sed 's|/|\\/|g')
    
    result=$(cat "$temp_output" | \
        grep -v "^spawn telnet" | \
        grep -v "^Trying" | \
        grep -v "^Connected to" | \
        grep -v "^Escape character" | \
        grep -v "^login:" | \
        grep -v "^Login:" | \
        grep -v "^Username:" | \
        grep -v "^Password:" | \
        grep -v "^password:" | \
        grep -v "^BusyBox" | \
        grep -v "^Enter 'help'" | \
        sed 's/\r//g' | \
        sed 's/^\[.*\]# //' | \
        sed 's/^# //' | \
        sed 's/^\$ //' | \
        sed "s|^${cmd_escaped}$||" | \
        sed "s|^${cmd_escaped}\r$||" | \
        sed '/^$/d')
    
    result=$(echo "$result" | sed "1s|^${cmd_escaped}\r\?$||" | sed '/^$/d')
    
    rm -f "$temp_output"
    echo "$result"
}

#######################################
# RTSP Server Setup Functions
#######################################
check_video_device() {
    log_info "Checking for video devices..."
    
    local video_devices
    video_devices=$(execute_command "ls -la /dev/video* 2>/dev/null || echo 'No video devices found'" 10 || true)
    
    if echo "$video_devices" | grep -q "video"; then
        log_success "Video devices found"
        echo "$video_devices"
        return 0
    else
        log_warn "No video devices found in /dev/"
        return 1
    fi
}

check_rtsp_server_binary() {
    log_info "Checking for RTSP server binary..."
    
    # Check common locations
    local rtsp_binary
    rtsp_binary=$(execute_command "which rtsp-simple-server mediamtx ffmpeg 2>/dev/null | head -1 || echo 'No RTSP server found'" 10 || true)
    
    if echo "$rtsp_binary" | grep -qv "No RTSP server found"; then
        log_success "Found RTSP server: $rtsp_binary"
        echo "$rtsp_binary"
        return 0
    else
        log_warn "No RTSP server binary found on device"
        return 1
    fi
}

create_rtsp_config() {
    log_info "Creating RTSP server configuration..."
    
    local config_content
    config_content=$(cat <<'RTSPCONFIG'
# RTSP Server Configuration
# For local-only video streaming

# Paths configuration
paths:
  ${RTSP_STREAM_PATH}:
    source: device
    sourceDevice: /dev/video0
    sourceOnDemand: no
    sourceOnDemandStartTimeout: 10s
    sourceOnDemandCloseAfter: 10s

# Server configuration
protocols: [tcp]
encryption: no
serverName: Local RTSP Server
RTSPCONFIG
)
    
    log_info "RTSP configuration template created"
    echo "$config_content"
}

setup_rtsp_service() {
    log_info "Setting up RTSP server as a service..."
    
    # Create startup script
    local startup_script
    startup_script=$(cat <<'STARTUP'
#!/bin/sh
# Local RTSP Server Startup Script
# This script starts the local RTSP server

RTSP_SERVER="/app/abin/local-rtsp-server"
RTSP_CONFIG="/app/local-rtsp-config.yaml"
RTSP_PORT="8554"

# Check if apollo is running and stop it
if pgrep apollo > /dev/null; then
    killall apollo 2>/dev/null || true
    sleep 2
fi

# Start local RTSP server
if [ -f "$RTSP_SERVER" ]; then
    $RTSP_SERVER -config "$RTSP_CONFIG" -port "$RTSP_PORT" &
    echo $! > /var/run/local-rtsp-server.pid
fi
STARTUP
)
    
    log_info "Startup script template created"
    echo "$startup_script"
}

test_rtsp_stream() {
    log_info "Testing RTSP stream accessibility..."
    
    local rtsp_url="rtsp://${TARGET_IP}:${RTSP_PORT}${RTSP_STREAM_PATH}"
    
    # Try RTSP OPTIONS request
    local rtsp_response
    rtsp_response=$(echo -e "OPTIONS ${rtsp_url} RTSP/1.0\r\nCSeq: 1\r\nUser-Agent: curl/8.0\r\n\r\n" | \
        nc -w 2 "$TARGET_IP" "$RTSP_PORT" 2>/dev/null || true)
    
    if echo "$rtsp_response" | grep -qi "RTSP/1.0.*200\|OK"; then
        log_success "RTSP stream is accessible: $rtsp_url"
        return 0
    else
        log_warn "RTSP stream test failed or server not responding"
        return 1
    fi
}

#######################################
# Main Setup Function
#######################################
main() {
    log_info "Starting local RTSP server setup for $TARGET_IP"
    log_info "RTSP Stream Path: $RTSP_STREAM_PATH"
    log_info "RTSP Port: $RTSP_PORT"
    
    echo ""
    echo "=== Local RTSP Server Setup Guide ==="
    echo ""
    echo "This script provides setup instructions and helper functions."
    echo "The actual RTSP server binary must be ARM-compatible (FH8616 ARMv6/ARMv7)."
    echo ""
    echo "Recommended RTSP server options:"
    echo "  1. rtsp-simple-server (lightweight Go-based, ARM compatible)"
    echo "  2. mediamtx (formerly rtsp-simple-server)"
    echo "  3. Custom ffmpeg-based solution"
    echo ""
    echo "Steps to complete setup:"
    echo "  1. Obtain ARM-compatible RTSP server binary"
    echo "  2. Transfer binary to device: /app/abin/local-rtsp-server"
    echo "  3. Create configuration file"
    echo "  4. Set up startup script"
    echo "  5. Test stream accessibility"
    echo ""
    
    # Check prerequisites
    check_video_device
    check_rtsp_server_binary
    
    # Generate configuration templates
    echo ""
    echo "=== Configuration Template ==="
    create_rtsp_config
    
    echo ""
    echo "=== Startup Script Template ==="
    setup_rtsp_service
    
    echo ""
    log_info "Setup guide complete. Use the templates above to configure your RTSP server."
    log_info "After setup, test the stream with:"
    log_info "  rtsp://${TARGET_IP}:${RTSP_PORT}${RTSP_STREAM_PATH}"
}

main "$@"

