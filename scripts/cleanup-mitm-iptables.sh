#!/usr/bin/env bash
set -euo pipefail

#######################################
# MITMproxy iptables Cleanup Script
# Removes iptables rules and stops MITMproxy processes
# Works for both local and remote scenarios
#######################################

TARGET_IP="${1:-}"
USERNAME="${2:-}"
PASSWORD="${3:-}"
CLEANUP_REMOTE="${4:-false}"

# Default credentials from README
if [[ -n "$USERNAME" ]] && [[ "$USERNAME" == "user" ]] && [[ "$PASSWORD" == "hellotuya" ]]; then
    PASSWORD="user123"
fi

TELNET_PORT="${TELNET_PORT:-23}"
COMMAND_TIMEOUT="${COMMAND_TIMEOUT:-30}"

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
# Expect-Based Telnet Handler (for remote cleanup)
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
# Check Root Access (for local cleanup)
#######################################
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root for local cleanup (use sudo)"
        return 1
    fi
    return 0
}

#######################################
# Stop MITMproxy Processes (Local)
#######################################
stop_mitmweb_local() {
    log_info "Stopping MITMproxy processes..."
    
    # Kill mitmweb processes
    if pkill -f mitmweb 2>/dev/null; then
        log_success "MITMproxy processes stopped"
    else
        log_warn "No MITMproxy processes found"
    fi
    
    # Also check for processes in virtual environment
    if pkill -f ".venv-mitm.*mitmweb" 2>/dev/null; then
        log_success "MITMproxy virtual environment processes stopped"
    fi
}

#######################################
# Cleanup Local iptables Rules
#######################################
cleanup_local_iptables() {
    log_info "Cleaning up local iptables rules..."
    
    if ! check_root; then
        log_error "Cannot clean iptables without root access"
        return 1
    fi
    
    # Flush NAT table rules
    iptables -t nat -F PREROUTING 2>/dev/null && log_success "Flushed PREROUTING chain" || log_warn "Failed to flush PREROUTING chain"
    iptables -t nat -F OUTPUT 2>/dev/null && log_success "Flushed OUTPUT chain" || log_warn "Failed to flush OUTPUT chain"
    
    # Disable IP forwarding (optional, but cleaner)
    echo 0 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true
    
    log_success "Local iptables rules cleaned"
}

#######################################
# Cleanup Remote iptables Rules
#######################################
cleanup_remote_iptables() {
    if [[ -z "$TARGET_IP" ]] || [[ -z "$USERNAME" ]] || [[ -z "$PASSWORD" ]]; then
        log_error "Remote cleanup requires TARGET_IP, USERNAME, and PASSWORD"
        log_info "Usage: $0 <target-ip> <username> <password>"
        return 1
    fi
    
    log_info "Cleaning up remote iptables rules on $TARGET_IP..."
    
    # Check if expect is available
    if ! command -v expect >/dev/null 2>&1; then
        log_error "expect is not installed (required for remote cleanup)"
        return 1
    fi
    
    # Flush NAT table rules on remote device
    execute_command "iptables -t nat -F PREROUTING 2>/dev/null || true" 15 || log_warn "Failed to flush PREROUTING on remote"
    execute_command "iptables -t nat -F OUTPUT 2>/dev/null || true" 15 || log_warn "Failed to flush OUTPUT on remote"
    
    # Disable IP forwarding on remote
    execute_command "echo 0 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true" 10 || true
    
    log_success "Remote iptables rules cleaned"
}

#######################################
# Main Execution
#######################################
main() {
    log_info "MITMproxy iptables Cleanup"
    log_info "============================"
    
    # Determine if this is local or remote cleanup
    if [[ -n "$TARGET_IP" ]] && [[ -n "$USERNAME" ]] && [[ -n "$PASSWORD" ]]; then
        log_info "Performing remote cleanup on $TARGET_IP"
        cleanup_remote_iptables
    else
        log_info "Performing local cleanup"
        stop_mitmweb_local
        cleanup_local_iptables
    fi
    
    log_success "Cleanup complete"
    log_info "Note: iptables rules have been removed"
    log_info "MITMproxy processes have been stopped"
}

# Show usage if help requested
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [target-ip] [username] [password]"
    echo ""
    echo "Local cleanup (no arguments):"
    echo "  $0"
    echo ""
    echo "Remote cleanup:"
    echo "  $0 <target-ip> <username> <password>"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Local cleanup"
    echo "  $0 10.0.0.227 root hellotuya         # Remote cleanup"
    exit 0
fi

main "$@"

