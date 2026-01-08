#!/usr/bin/env bash
set -euo pipefail

#######################################
# RTSP Stream Discovery Script
# Discovers RTSP stream paths and parameters for Bytech BY-CM-WF-101-WT webcam
#######################################

TARGET_IP="${1:-}"
USERNAME="${2:-root}"
PASSWORD="${3:-hellotuya}"
OUTPUT_FILE="${4:-rtsp-discovery-$(date +%Y%m%d_%H%M%S).txt}"

# Default credentials from README
if [[ "$USERNAME" == "user" ]] && [[ "$PASSWORD" == "hellotuya" ]]; then
    PASSWORD="user123"
fi

TELNET_PORT="${TELNET_PORT:-23}"
RTSP_PORT="${RTSP_PORT:-8554}"
COMMAND_TIMEOUT="${COMMAND_TIMEOUT:-30}"

# Check if expect is available
if ! command -v expect &> /dev/null; then
    echo "[!] Error: expect is not installed"
    echo "[*] Install with: apt-get install expect  or  yum install expect"
    exit 1
fi

if [[ -z "$TARGET_IP" ]]; then
    echo "Usage: $0 <target-ip> [username] [password] [output-file]"
    echo ""
    echo "Example:"
    echo "  $0 10.0.0.227 root hellotuya"
    echo "  $0 10.0.0.227 user user123 rtsp-discovery.txt"
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
    echo "[$timestamp] [$level] $message" | tee -a "$OUTPUT_FILE"
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
        sed "s/^${cmd}$//" | \
        sed "s/^${cmd}\r$//" | \
        sed '/^$/d')
    
    result=$(echo "$result" | sed "1s/^${cmd}\r\?$//" | sed '/^$/d')
    
    rm -f "$temp_output"
    echo "$result"
}

#######################################
# RTSP Stream Testing Functions
#######################################
test_rtsp_path() {
    local path="$1"
    local rtsp_url="rtsp://${TARGET_IP}:${RTSP_PORT}${path}"
    
    log_info "Testing RTSP path: $path"
    
    # Try with curl first (lighter weight)
    if command -v curl &> /dev/null; then
        local curl_result
        curl_result=$(curl -s --max-time 5 \
            --user-agent "RTSP/1.0" \
            "$rtsp_url" 2>&1 || true)
        
        if echo "$curl_result" | grep -qi "RTSP\|200\|OK"; then
            log_success "RTSP path accessible: $path"
            echo "$rtsp_url" >> "$OUTPUT_FILE"
            return 0
        fi
    fi
    
    # Try with ffprobe if available
    if command -v ffprobe &> /dev/null; then
        local ffprobe_result
        ffprobe_result=$(timeout 5 ffprobe -v error -show_entries stream=codec_name,width,height,r_frame_rate \
            -of default=noprint_wrappers=1 "$rtsp_url" 2>&1 || true)
        
        if echo "$ffprobe_result" | grep -q "codec_name"; then
            log_success "RTSP stream found: $path"
            echo "=== RTSP Stream: $rtsp_url ===" >> "$OUTPUT_FILE"
            echo "$ffprobe_result" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
            return 0
        fi
    fi
    
    # Try RTSP OPTIONS request manually
    local rtsp_response
    rtsp_response=$(echo -e "OPTIONS ${rtsp_url} RTSP/1.0\r\nCSeq: 1\r\nUser-Agent: curl/8.0\r\n\r\n" | \
        nc -w 2 "$TARGET_IP" "$RTSP_PORT" 2>/dev/null || true)
    
    if echo "$rtsp_response" | grep -qi "RTSP/1.0.*200\|OK"; then
        log_success "RTSP path responds: $path"
        echo "$rtsp_url" >> "$OUTPUT_FILE"
        return 0
    fi
    
    return 1
}

#######################################
# Main Discovery Function
#######################################
discover_rtsp_streams() {
    log_info "Starting RTSP stream discovery on $TARGET_IP:$RTSP_PORT"
    echo "=== RTSP Stream Discovery Report ===" > "$OUTPUT_FILE"
    echo "Target: $TARGET_IP:$RTSP_PORT" >> "$OUTPUT_FILE"
    echo "Date: $(date)" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    # Check if RTSP port is open
    log_info "Checking if RTSP port $RTSP_PORT is accessible..."
    if ! nc -z -w 2 "$TARGET_IP" "$RTSP_PORT" 2>/dev/null; then
        log_warn "RTSP port $RTSP_PORT is not accessible"
        echo "WARNING: RTSP port $RTSP_PORT is not accessible" >> "$OUTPUT_FILE"
    else
        log_success "RTSP port $RTSP_PORT is open"
        echo "RTSP port $RTSP_PORT is open" >> "$OUTPUT_FILE"
    fi
    echo "" >> "$OUTPUT_FILE"
    
    # Common RTSP paths to test
    local rtsp_paths=(
        "/stream1"
        "/live"
        "/video"
        "/ch0"
        "/ch1"
        "/cam"
        "/camera"
        "/main"
        "/sub"
        "/"
        "/stream"
        "/h264"
        "/mjpeg"
    )
    
    log_info "Testing common RTSP paths..."
    echo "=== Tested RTSP Paths ===" >> "$OUTPUT_FILE"
    
    local found_streams=0
    for path in "${rtsp_paths[@]}"; do
        if test_rtsp_path "$path"; then
            ((found_streams++)) || true
        fi
    done
    
    echo "" >> "$OUTPUT_FILE"
    echo "Total streams found: $found_streams" >> "$OUTPUT_FILE"
    
    # Try to get RTSP server info from device
    log_info "Querying RTSP server information from device..."
    local server_info
    server_info=$(execute_command "netstat -tulpn 2>/dev/null | grep $RTSP_PORT || ss -tulpn 2>/dev/null | grep $RTSP_PORT" 10 || true)
    
    if [[ -n "$server_info" ]]; then
        echo "" >> "$OUTPUT_FILE"
        echo "=== RTSP Server Process Information ===" >> "$OUTPUT_FILE"
        echo "$server_info" >> "$OUTPUT_FILE"
    fi
    
    # Try to discover streams via RTSP DESCRIBE
    log_info "Attempting RTSP DESCRIBE on common paths..."
    echo "" >> "$OUTPUT_FILE"
    echo "=== RTSP DESCRIBE Results ===" >> "$OUTPUT_FILE"
    
    for path in "${rtsp_paths[@]}"; do
        local rtsp_url="rtsp://${TARGET_IP}:${RTSP_PORT}${path}"
        local describe_response
        describe_response=$(echo -e "DESCRIBE ${rtsp_url} RTSP/1.0\r\nCSeq: 2\r\nUser-Agent: curl/8.0\r\nAccept: application/sdp\r\n\r\n" | \
            nc -w 2 "$TARGET_IP" "$RTSP_PORT" 2>/dev/null || true)
        
        if echo "$describe_response" | grep -qi "RTSP/1.0.*200\|sdp\|m=video"; then
            log_success "RTSP DESCRIBE successful for: $path"
            echo "Path: $path" >> "$OUTPUT_FILE"
            echo "$describe_response" | head -20 >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
        fi
    done
    
    log_info "Discovery complete. Results saved to: $OUTPUT_FILE"
    
    if [[ $found_streams -eq 0 ]]; then
        log_warn "No RTSP streams discovered. The camera may require authentication or use a non-standard path."
        return 1
    fi
    
    return 0
}

#######################################
# Main Execution
#######################################
main() {
    discover_rtsp_streams
}

main "$@"

