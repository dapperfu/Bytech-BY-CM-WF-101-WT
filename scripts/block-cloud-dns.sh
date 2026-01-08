#!/usr/bin/env bash
set -euo pipefail

#######################################
# DNS Blocking Script
# Blocks DNS queries to external servers
#######################################

TARGET_IP="${1:-}"
USERNAME="${2:-root}"
PASSWORD="${3:-hellotuya}"

# Default credentials from README
if [[ "$USERNAME" == "user" ]] && [[ "$PASSWORD" == "hellotuya" ]]; then
    PASSWORD="user123"
fi

TELNET_PORT="${TELNET_PORT:-23}"
COMMAND_TIMEOUT="${COMMAND_TIMEOUT:-30}"
RESOLV_CONF="/etc/resolv.conf"
LOCAL_DNS="${LOCAL_DNS:-10.0.0.1}"

# Check if expect is available
if ! command -v expect &> /dev/null; then
    echo "[!] Error: expect is not installed"
    echo "[*] Install with: apt-get install expect  or  yum install expect"
    exit 1
fi

if [[ -z "$TARGET_IP" ]]; then
    echo "Usage: $0 <target-ip> [username] [password] [local-dns]"
    echo ""
    echo "Example:"
    echo "  $0 10.0.0.227 root hellotuya"
    echo "  $0 10.0.0.227 root hellotuya 10.0.0.1"
    exit 1
fi

if [[ -n "${4:-}" ]]; then
    LOCAL_DNS="$4"
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
# DNS Blocking Functions
#######################################
backup_resolv_conf() {
    log_info "Backing up /etc/resolv.conf..."
    
    local backup_file="/tmp/resolv.conf.backup-$(date +%Y%m%d_%H%M%S)"
    local backup_result
    backup_result=$(execute_command "cp $RESOLV_CONF $backup_file 2>/dev/null && echo 'backup_ok' || echo 'backup_failed'" 15 || true)
    
    if echo "$backup_result" | grep -q "backup_ok"; then
        log_success "resolv.conf backed up to: $backup_file"
        echo "$backup_file"
        return 0
    else
        log_warn "resolv.conf not found or backup failed"
        return 1
    fi
}

modify_resolv_conf() {
    log_info "Modifying /etc/resolv.conf to use only local DNS..."
    
    # Create new resolv.conf with only local DNS
    local new_resolv
    new_resolv=$(cat <<RESOLV
# Local DNS only - cloud DNS blocked
nameserver $LOCAL_DNS
RESOLV
)
    
    # Write new resolv.conf
    local write_result
    write_result=$(execute_command "echo '$new_resolv' > $RESOLV_CONF && echo 'write_ok' || echo 'write_failed'" 15 || true)
    
    if echo "$write_result" | grep -q "write_ok"; then
        log_success "resolv.conf modified to use only local DNS: $LOCAL_DNS"
        return 0
    else
        log_error "Failed to modify resolv.conf"
        return 1
    fi
}

block_external_dns_iptables() {
    log_info "Blocking external DNS queries via iptables..."
    
    # Block DNS (port 53) to external servers
    execute_command "iptables -A OUTPUT -p udp --dport 53 ! -d $LOCAL_DNS -j DROP" 10 || true
    execute_command "iptables -A OUTPUT -p tcp --dport 53 ! -d $LOCAL_DNS -j DROP" 10 || true
    
    log_success "External DNS queries blocked via iptables"
}

verify_dns_blocking() {
    log_info "Verifying DNS blocking..."
    
    # Check resolv.conf
    local resolv_content
    resolv_content=$(execute_command "cat $RESOLV_CONF 2>/dev/null || echo 'not found'" 10 || true)
    
    echo ""
    echo "=== Current /etc/resolv.conf ==="
    echo "$resolv_content"
    echo ""
    
    # Check for external DNS servers
    local external_dns
    external_dns=$(echo "$resolv_content" | \
        grep nameserver | \
        awk '{print $2}' | \
        grep -vE "^127\.|^10\.|^192\.168\.|^172\.(1[6-9]|2[0-9]|3[0-1])\." || true)
    
    if [[ -z "$external_dns" ]]; then
        log_success "No external DNS servers found in resolv.conf"
    else
        log_warn "External DNS servers still present:"
        echo "$external_dns"
    fi
    
    # Check iptables rules
    local dns_rules
    dns_rules=$(execute_command "iptables -L OUTPUT -n -v | grep -E '53|dpt:53' || echo 'no DNS rules found'" 15 || true)
    
    if echo "$dns_rules" | grep -qv "no DNS rules found"; then
        log_success "DNS blocking rules found in iptables"
        echo "$dns_rules"
    else
        log_warn "No DNS blocking rules found in iptables"
    fi
}

create_restore_script() {
    log_info "Creating restore script..."
    
    local restore_script
    restore_script=$(cat <<RESTORE
#!/bin/sh
# Restore DNS configuration
# Usage: ./restore-dns.sh [backup-file]

BACKUP_FILE="\${1:-/tmp/resolv.conf.backup-*.conf}"

if [ -f "\$BACKUP_FILE" ]; then
    cp "\$BACKUP_FILE" $RESOLV_CONF
    echo "DNS configuration restored from \$BACKUP_FILE"
else
    # Restore default DNS
    cat > $RESOLV_CONF <<EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF
    echo "DNS configuration reset to defaults"
fi

# Remove DNS blocking iptables rules
iptables -D OUTPUT -p udp --dport 53 ! -d $LOCAL_DNS -j DROP 2>/dev/null || true
iptables -D OUTPUT -p tcp --dport 53 ! -d $LOCAL_DNS -j DROP 2>/dev/null || true
RESTORE
)
    
    log_info "Restore script created (save this for future use)"
    echo "$restore_script"
}

#######################################
# Main Function
#######################################
main() {
    log_info "Starting DNS blocking on $TARGET_IP"
    log_info "Local DNS: $LOCAL_DNS"
    
    # Backup resolv.conf
    local backup_file
    backup_file=$(backup_resolv_conf)
    
    # Modify resolv.conf
    if ! modify_resolv_conf; then
        log_error "Failed to modify resolv.conf"
        exit 1
    fi
    
    # Block external DNS via iptables
    block_external_dns_iptables
    
    # Verify blocking
    verify_dns_blocking
    
    # Create restore script
    echo ""
    echo "=== Restore Script ==="
    create_restore_script
    echo ""
    
    if [[ -n "$backup_file" ]]; then
        log_info "Backup file: $backup_file"
    fi
    
    log_success "DNS blocking complete!"
    log_info "Only local DNS ($LOCAL_DNS) is now accessible"
}

main "$@"

