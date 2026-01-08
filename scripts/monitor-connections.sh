#!/usr/bin/env bash
set -euo pipefail

#######################################
# Real-Time Connection Monitoring Script
# Continuously monitors network connections and highlights cloud connections
#######################################

TARGET_IP="${1:-}"
USERNAME="${2:-root}"
PASSWORD="${3:-hellotuya}"
INTERVAL="${4:-2}"
LOG_FILE="${5:-connection-monitor-$(date +%Y%m%d_%H%M%S).log}"

# Default credentials from README
if [[ "$USERNAME" == "user" ]] && [[ "$PASSWORD" == "hellotuya" ]]; then
    PASSWORD="user123"
fi

TELNET_PORT="${TELNET_PORT:-23}"
COMMAND_TIMEOUT="${COMMAND_TIMEOUT:-10}"
LOCAL_NETWORK="${LOCAL_NETWORK:-10.0.0.0/24}"

# Known cloud IPs
KNOWN_CLOUD_IPS=(
    "52.42.98.25"
)

# Check if expect is available
if ! command -v expect &> /dev/null; then
    echo "[!] Error: expect is not installed"
    echo "[*] Install with: apt-get install expect  or  yum install expect"
    exit 1
fi

if [[ -z "$TARGET_IP" ]]; then
    echo "Usage: $0 <target-ip> [username] [password] [interval-seconds] [log-file]"
    echo ""
    echo "Example:"
    echo "  $0 10.0.0.227 root hellotuya 2 monitor.log"
    echo ""
    echo "Press Ctrl+C to stop monitoring"
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
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
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
# Connection Analysis Functions
#######################################
is_cloud_ip() {
    local ip="$1"
    
    # Check known cloud IPs
    for cloud_ip in "${KNOWN_CLOUD_IPS[@]}"; do
        if [[ "$ip" == "$cloud_ip" ]]; then
            return 0
        fi
    done
    
    # Check if it's not a local IP
    if ! echo "$ip" | grep -qE "^127\.|^10\.|^192\.168\.|^172\.(1[6-9]|2[0-9]|3[0-1])\."; then
        return 0
    fi
    
    return 1
}

get_connections() {
    local connections
    connections=$(execute_command "netstat -anp 2>/dev/null || ss -anp 2>/dev/null" 15 || true)
    echo "$connections"
}

display_connections() {
    local connections="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    clear
    echo "=========================================="
    echo "Connection Monitor - $TARGET_IP"
    echo "Time: $timestamp"
    echo "Interval: ${INTERVAL}s | Log: $LOG_FILE"
    echo "=========================================="
    echo ""
    
    # Parse and display connections
    echo "=== Active Connections ==="
    echo ""
    
    local cloud_count=0
    local local_count=0
    
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        
        # Extract remote IP
        local remote_ip
        remote_ip=$(echo "$line" | awk '{print $5}' | sed 's/:[0-9]*$//' | head -1)
        
        if [[ -z "$remote_ip" ]]; then
            continue
        fi
        
        if is_cloud_ip "$remote_ip"; then
            echo "⚠️  CLOUD: $line" | tee -a "$LOG_FILE"
            ((cloud_count++)) || true
        else
            echo "   LOCAL: $line"
            ((local_count++)) || true
        fi
    done <<< "$connections"
    
    echo ""
    echo "=== Summary ==="
    echo "Local connections: $local_count"
    echo "Cloud connections: $cloud_count"
    
    if [[ $cloud_count -gt 0 ]]; then
        log_warn "WARNING: $cloud_count cloud connection(s) detected!"
    fi
    
    echo ""
    echo "Press Ctrl+C to stop monitoring"
}

#######################################
# Main Monitoring Loop
#######################################
main() {
    log_info "Starting real-time connection monitoring on $TARGET_IP"
    log_info "Monitoring interval: ${INTERVAL} seconds"
    log_info "Log file: $LOG_FILE"
    
    # Trap Ctrl+C
    trap 'log_info "Monitoring stopped by user"; exit 0' INT TERM
    
    while true; do
        local connections
        connections=$(get_connections)
        
        if [[ -n "$connections" ]]; then
            display_connections "$connections"
        else
            log_warn "Failed to get connections"
        fi
        
        sleep "$INTERVAL"
    done
}

main "$@"

