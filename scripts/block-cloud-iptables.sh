#!/usr/bin/env bash
set -euo pipefail

#######################################
# iptables Cloud Blocking Script
# Blocks all cloud communication using iptables firewall rules
#######################################

TARGET_IP="${1:-}"
USERNAME="${2:-root}"
PASSWORD="${3:-hellotuya}"
CLOUD_IPS_FILE="${4:-}"

# Default credentials from README
if [[ "$USERNAME" == "user" ]] && [[ "$PASSWORD" == "hellotuya" ]]; then
    PASSWORD="user123"
fi

TELNET_PORT="${TELNET_PORT:-23}"
COMMAND_TIMEOUT="${COMMAND_TIMEOUT:-30}"
LOCAL_NETWORK="${LOCAL_NETWORK:-10.0.0.0/24}"
RTSP_PORT="${RTSP_PORT:-8554}"

# Known cloud IPs (from probe data)
KNOWN_CLOUD_IPS=(
    "52.42.98.25"  # MQTT server
)

# Check if expect is available
if ! command -v expect &> /dev/null; then
    echo "[!] Error: expect is not installed"
    echo "[*] Install with: apt-get install expect  or  yum install expect"
    exit 1
fi

if [[ -z "$TARGET_IP" ]]; then
    echo "Usage: $0 <target-ip> [username] [password] [cloud-ips-file]"
    echo ""
    echo "Example:"
    echo "  $0 10.0.0.227 root hellotuya"
    echo "  $0 10.0.0.227 root hellotuya cloud-ips.txt"
    echo ""
    echo "The cloud-ips-file should contain one IP address per line."
    echo "If not provided, known cloud IPs will be used."
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
# Cloud IP Collection
#######################################
collect_cloud_ips() {
    local cloud_ips=()
    
    # Add known cloud IPs
    for ip in "${KNOWN_CLOUD_IPS[@]}"; do
        cloud_ips+=("$ip")
    done
    
    # Read from file if provided
    if [[ -n "$CLOUD_IPS_FILE" ]] && [[ -f "$CLOUD_IPS_FILE" ]]; then
        while IFS= read -r ip; do
            # Skip comments and empty lines
            [[ -z "$ip" ]] && continue
            [[ "$ip" =~ ^# ]] && continue
            cloud_ips+=("$ip")
        done < "$CLOUD_IPS_FILE"
    fi
    
    # Remove duplicates
    local unique_ips
    unique_ips=$(printf '%s\n' "${cloud_ips[@]}" | sort -u)
    
    echo "$unique_ips"
}

#######################################
# Firewall Rule Functions
#######################################
check_iptables() {
    log_info "Checking iptables availability..."
    
    local iptables_check
    iptables_check=$(execute_command "which iptables 2>/dev/null || echo 'not found'" 10 || true)
    
    if echo "$iptables_check" | grep -q "not found"; then
        log_error "iptables not found on device"
        return 1
    fi
    
    log_success "iptables is available"
    return 0
}

backup_iptables_rules() {
    log_info "Backing up current iptables rules..."
    
    local backup_file="/tmp/iptables-backup-$(date +%Y%m%d_%H%M%S).rules"
    local backup_result
    backup_result=$(execute_command "iptables-save > $backup_file 2>/dev/null && echo 'backup_ok' || echo 'backup_failed'" 15 || true)
    
    if echo "$backup_result" | grep -q "backup_ok"; then
        log_success "iptables rules backed up to: $backup_file"
        echo "$backup_file"
        return 0
    else
        log_warn "Failed to backup iptables rules (may be empty)"
        return 1
    fi
}

apply_firewall_rules() {
    local cloud_ips
    cloud_ips=$(collect_cloud_ips)
    
    log_info "Applying firewall rules to block cloud communication..."
    
    # Flush existing rules (be careful!)
    log_warn "Flushing existing iptables rules..."
    execute_command "iptables -F" 10 || true
    execute_command "iptables -X" 10 || true
    execute_command "iptables -t nat -F" 10 || true
    execute_command "iptables -t nat -X" 10 || true
    
    # Set default policies
    log_info "Setting default policies..."
    execute_command "iptables -P INPUT ACCEPT" 10 || true
    execute_command "iptables -P FORWARD ACCEPT" 10 || true
    execute_command "iptables -P OUTPUT ACCEPT" 10 || true
    
    # Allow loopback
    log_info "Allowing loopback traffic..."
    execute_command "iptables -A INPUT -i lo -j ACCEPT" 10 || true
    execute_command "iptables -A OUTPUT -o lo -j ACCEPT" 10 || true
    
    # Allow local network
    log_info "Allowing local network traffic ($LOCAL_NETWORK)..."
    execute_command "iptables -A INPUT -s $LOCAL_NETWORK -j ACCEPT" 10 || true
    execute_command "iptables -A OUTPUT -d $LOCAL_NETWORK -j ACCEPT" 10 || true
    
    # Allow RTSP inbound
    log_info "Allowing RTSP inbound on port $RTSP_PORT..."
    execute_command "iptables -A INPUT -p tcp --dport $RTSP_PORT -j ACCEPT" 10 || true
    
    # Block specific cloud IPs
    log_info "Blocking cloud IP addresses..."
    while IFS= read -r ip; do
        [[ -z "$ip" ]] && continue
        log_info "  Blocking: $ip"
        execute_command "iptables -A OUTPUT -d $ip -j DROP" 10 || true
    done <<< "$cloud_ips"
    
    # Block all other outbound internet traffic
    log_info "Blocking all other outbound internet traffic..."
    execute_command "iptables -A OUTPUT -d 0.0.0.0/0 ! -d $LOCAL_NETWORK -j DROP" 10 || true
    
    log_success "Firewall rules applied"
}

save_iptables_rules() {
    log_info "Saving iptables rules for persistence..."
    
    # Try to save rules (device-specific)
    local save_result
    save_result=$(execute_command "iptables-save > /etc/iptables.rules 2>/dev/null && echo 'saved' || echo 'save_failed'" 15 || true)
    
    if echo "$save_result" | grep -q "saved"; then
        log_success "iptables rules saved to /etc/iptables.rules"
    else
        log_warn "Failed to save iptables rules (may not persist across reboots)"
        log_info "Rules will need to be reapplied after reboot"
    fi
}

create_restore_script() {
    log_info "Creating restore script..."
    
    local restore_script
    restore_script=$(cat <<RESTORE
#!/bin/sh
# Restore iptables rules
# Usage: ./restore-iptables.sh [backup-file]

BACKUP_FILE="\${1:-/tmp/iptables-backup-*.rules}"

if [ -f "\$BACKUP_FILE" ]; then
    iptables-restore < "\$BACKUP_FILE"
    echo "iptables rules restored from \$BACKUP_FILE"
else
    # Flush all rules and set defaults
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    echo "iptables rules reset to defaults"
fi
RESTORE
)
    
    log_info "Restore script created (save this for future use)"
    echo "$restore_script"
}

verify_rules() {
    log_info "Verifying firewall rules..."
    
    local rules_output
    rules_output=$(execute_command "iptables -L -n -v" 15 || true)
    
    echo ""
    echo "=== Current iptables Rules ==="
    echo "$rules_output"
    echo ""
    
    # Check if cloud IPs are blocked
    local cloud_ips
    cloud_ips=$(collect_cloud_ips)
    
    while IFS= read -r ip; do
        [[ -z "$ip" ]] && continue
        if echo "$rules_output" | grep -q "$ip"; then
            log_success "Cloud IP $ip is blocked"
        else
            log_warn "Cloud IP $ip blocking rule not found"
        fi
    done <<< "$cloud_ips"
}

#######################################
# Main Function
#######################################
main() {
    log_info "Starting cloud blocking with iptables on $TARGET_IP"
    
    # Check prerequisites
    if ! check_iptables; then
        log_error "Cannot proceed without iptables"
        exit 1
    fi
    
    # Backup current rules
    local backup_file
    backup_file=$(backup_iptables_rules)
    
    # Apply firewall rules
    apply_firewall_rules
    
    # Save rules
    save_iptables_rules
    
    # Verify rules
    verify_rules
    
    # Create restore script
    echo ""
    echo "=== Restore Script ==="
    create_restore_script
    echo ""
    
    if [[ -n "$backup_file" ]]; then
        log_info "Backup file: $backup_file"
    fi
    
    log_success "Cloud blocking with iptables complete!"
}

main "$@"

