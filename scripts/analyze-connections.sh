#!/usr/bin/env bash
set -euo pipefail

#######################################
# Connection Analysis Script
# Takes a snapshot of all connections and categorizes them
#######################################

TARGET_IP="${1:-}"
USERNAME="${2:-root}"
PASSWORD="${3:-hellotuya}"
OUTPUT_FILE="${4:-connection-analysis-$(date +%Y%m%d_%H%M%S).txt}"

# Default credentials from README
if [[ "$USERNAME" == "user" ]] && [[ "$PASSWORD" == "hellotuya" ]]; then
    PASSWORD="user123"
fi

TELNET_PORT="${TELNET_PORT:-23}"
COMMAND_TIMEOUT="${COMMAND_TIMEOUT:-30}"
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
    echo "Usage: $0 <target-ip> [username] [password] [output-file]"
    echo ""
    echo "Example:"
    echo "  $0 10.0.0.227 root hellotuya"
    echo "  $0 10.0.0.227 root hellotuya analysis.txt"
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
# Analysis Functions
#######################################
is_local_ip() {
    local ip="$1"
    echo "$ip" | grep -qE "^127\.|^10\.|^192\.168\.|^172\.(1[6-9]|2[0-9]|3[0-1])\."
}

is_cloud_ip() {
    local ip="$1"
    
    for cloud_ip in "${KNOWN_CLOUD_IPS[@]}"; do
        if [[ "$ip" == "$cloud_ip" ]]; then
            return 0
        fi
    done
    
    if ! is_local_ip "$ip"; then
        return 0
    fi
    
    return 1
}

analyze_connections() {
    log_info "Analyzing network connections..."
    echo "" >> "$OUTPUT_FILE"
    echo "=== Connection Analysis Report ===" >> "$OUTPUT_FILE"
    echo "Target: $TARGET_IP" >> "$OUTPUT_FILE"
    echo "Date: $(date)" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    # Get all connections
    local connections
    connections=$(execute_command "netstat -anp 2>/dev/null || ss -anp 2>/dev/null" 20 || true)
    
    echo "=== All Connections ===" >> "$OUTPUT_FILE"
    echo "$connections" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    # Categorize connections
    local local_connections=()
    local cloud_connections=()
    local listening_services=()
    
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        
        # Check for listening services
        if echo "$line" | grep -qE "LISTEN|LISTENING"; then
            listening_services+=("$line")
            continue
        fi
        
        # Extract remote IP
        local remote_ip
        remote_ip=$(echo "$line" | awk '{print $5}' | sed 's/:[0-9]*$//' | head -1)
        
        if [[ -z "$remote_ip" ]]; then
            continue
        fi
        
        if is_cloud_ip "$remote_ip"; then
            cloud_connections+=("$line")
        elif is_local_ip "$remote_ip"; then
            local_connections+=("$line")
        fi
    done <<< "$connections"
    
    # Write categorized connections
    echo "=== Listening Services ===" >> "$OUTPUT_FILE"
    for conn in "${listening_services[@]}"; do
        echo "$conn" >> "$OUTPUT_FILE"
    done
    echo "" >> "$OUTPUT_FILE"
    
    echo "=== Local Network Connections ($LOCAL_NETWORK) ===" >> "$OUTPUT_FILE"
    for conn in "${local_connections[@]}"; do
        echo "$conn" >> "$OUTPUT_FILE"
    done
    echo "" >> "$OUTPUT_FILE"
    
    echo "=== Cloud Connections (EXTERNAL) ===" >> "$OUTPUT_FILE"
    if [[ ${#cloud_connections[@]} -eq 0 ]]; then
        echo "No cloud connections detected" >> "$OUTPUT_FILE"
        log_success "No cloud connections found"
    else
        for conn in "${cloud_connections[@]}"; do
            echo "⚠️  $conn" >> "$OUTPUT_FILE"
        done
        log_warn "Found ${#cloud_connections[@]} cloud connection(s)"
    fi
    echo "" >> "$OUTPUT_FILE"
    
    # Identify processes making cloud connections
    echo "=== Processes Making Cloud Connections ===" >> "$OUTPUT_FILE"
    local cloud_processes
    cloud_processes=$(echo "$connections" | \
        grep -E "ESTABLISHED|CONNECT" | \
        awk '{print $5, $7}' | \
        grep -vE "^127\.|^10\.|^192\.168\.|^172\.(1[6-9]|2[0-9]|3[0-1])\." | \
        sort -u || true)
    
    if [[ -n "$cloud_processes" ]]; then
        echo "$cloud_processes" >> "$OUTPUT_FILE"
    else
        echo "No processes making cloud connections" >> "$OUTPUT_FILE"
    fi
    echo "" >> "$OUTPUT_FILE"
    
    # Summary
    echo "=== Summary ===" >> "$OUTPUT_FILE"
    echo "Listening services: ${#listening_services[@]}" >> "$OUTPUT_FILE"
    echo "Local connections: ${#local_connections[@]}" >> "$OUTPUT_FILE"
    echo "Cloud connections: ${#cloud_connections[@]}" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    log_success "Analysis complete. Results saved to: $OUTPUT_FILE"
}

#######################################
# Main Function
#######################################
main() {
    log_info "Starting connection analysis on $TARGET_IP"
    analyze_connections
}

main "$@"

