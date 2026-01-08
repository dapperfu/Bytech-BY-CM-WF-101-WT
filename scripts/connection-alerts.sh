#!/usr/bin/env bash
set -euo pipefail

#######################################
# Connection Alert System
# Monitors for new cloud connections and alerts when blocked IPs attempt connection
#######################################

TARGET_IP="${1:-}"
USERNAME="${2:-root}"
PASSWORD="${3:-hellotuya}"
ALERT_LOG="${4:-connection-alerts-$(date +%Y%m%d_%H%M%S).log}"
CHECK_INTERVAL="${5:-5}"

# Default credentials from README
if [[ "$USERNAME" == "user" ]] && [[ "$PASSWORD" == "hellotuya" ]]; then
    PASSWORD="user123"
fi

TELNET_PORT="${TELNET_PORT:-23}"
COMMAND_TIMEOUT="${COMMAND_TIMEOUT:-10}"
LOCAL_NETWORK="${LOCAL_NETWORK:-10.0.0.0/24}"

# Known cloud IPs to monitor
KNOWN_CLOUD_IPS=(
    "52.42.98.25"
)

# Blocked IPs (from iptables or other blocking mechanisms)
BLOCKED_IPS=(
    "52.42.98.25"
)

# Check if expect is available
if ! command -v expect &> /dev/null; then
    echo "[!] Error: expect is not installed"
    echo "[*] Install with: apt-get install expect  or  yum install expect"
    exit 1
fi

if [[ -z "$TARGET_IP" ]]; then
    echo "Usage: $0 <target-ip> [username] [password] [alert-log] [check-interval]"
    echo ""
    echo "Example:"
    echo "  $0 10.0.0.227 root hellotuya alerts.log 5"
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
    echo "[$timestamp] [$level] $message" | tee -a "$ALERT_LOG"
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

log_alert() {
    log "ALERT" "$@"
    # Could add email/SMS notification here if infrastructure available
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
# Alert Functions
#######################################
is_cloud_ip() {
    local ip="$1"
    
    for cloud_ip in "${KNOWN_CLOUD_IPS[@]}"; do
        if [[ "$ip" == "$cloud_ip" ]]; then
            return 0
        fi
    done
    
    if ! echo "$ip" | grep -qE "^127\.|^10\.|^192\.168\.|^172\.(1[6-9]|2[0-9]|3[0-1])\."; then
        return 0
    fi
    
    return 1
}

is_blocked_ip() {
    local ip="$1"
    
    for blocked_ip in "${BLOCKED_IPS[@]}"; do
        if [[ "$ip" == "$blocked_ip" ]]; then
            return 0
        fi
    done
    
    return 1
}

get_current_connections() {
    local connections
    connections=$(execute_command "netstat -anp 2>/dev/null | grep -E 'ESTABLISHED|CONNECT' || ss -anp 2>/dev/null | grep -E 'ESTABLISHED|CONNECT'" 15 || true)
    echo "$connections"
}

check_blocked_attempts() {
    log_info "Checking for blocked IP connection attempts..."
    
    # Check iptables for dropped packets
    local dropped_packets
    dropped_packets=$(execute_command "iptables -L OUTPUT -n -v 2>/dev/null | grep DROP || echo 'no drops'" 15 || true)
    
    if echo "$dropped_packets" | grep -qv "no drops"; then
        local drop_count
        drop_count=$(echo "$dropped_packets" | awk '{sum+=$1} END {print sum}')
        
        if [[ -n "$drop_count" ]] && [[ "$drop_count" -gt 0 ]]; then
            log_alert "Blocked connection attempts detected: $drop_count packet(s) dropped"
            echo "$dropped_packets" >> "$ALERT_LOG"
        fi
    fi
}

monitor_cloud_connections() {
    local previous_connections_file
    previous_connections_file=$(mktemp)
    
    # Get initial connections
    get_current_connections > "$previous_connections_file"
    
    log_info "Starting cloud connection monitoring..."
    log_info "Alert log: $ALERT_LOG"
    log_info "Check interval: ${CHECK_INTERVAL} seconds"
    
    # Trap Ctrl+C
    trap 'log_info "Monitoring stopped by user"; rm -f "$previous_connections_file"; exit 0' INT TERM
    
    while true; do
        local current_connections
        current_connections=$(get_current_connections)
        local current_connections_file
        current_connections_file=$(mktemp)
        echo "$current_connections" > "$current_connections_file"
        
        # Find new cloud connections
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            
            local remote_ip
            remote_ip=$(echo "$line" | awk '{print $5}' | sed 's/:[0-9]*$//' | head -1)
            
            if [[ -z "$remote_ip" ]]; then
                continue
            fi
            
            if is_cloud_ip "$remote_ip"; then
                # Check if this is a new connection
                if ! grep -q "$remote_ip" "$previous_connections_file"; then
                    local process_info
                    process_info=$(echo "$line" | awk '{print $7}' || echo "unknown")
                    
                    log_alert "NEW CLOUD CONNECTION DETECTED!"
                    log_alert "  IP: $remote_ip"
                    log_alert "  Process: $process_info"
                    log_alert "  Connection: $line"
                    
                    if is_blocked_ip "$remote_ip"; then
                        log_alert "  ⚠️  BLOCKED IP ATTEMPTED CONNECTION!"
                    fi
                fi
            fi
        done <<< "$current_connections"
        
        # Check for blocked connection attempts
        check_blocked_attempts
        
        # Update previous connections
        mv "$current_connections_file" "$previous_connections_file"
        
        sleep "$CHECK_INTERVAL"
    done
}

#######################################
# Main Function
#######################################
main() {
    log_info "Starting connection alert system on $TARGET_IP"
    monitor_cloud_connections
}

main "$@"

