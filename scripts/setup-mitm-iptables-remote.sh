#!/usr/bin/env bash
set -euo pipefail

#######################################
# Remote MITMproxy iptables Setup Script
# Sets up iptables rules on remote IoT device to redirect traffic through MITMproxy
#######################################

TARGET_IP="${1:-}"
USERNAME="${2:-root}"
PASSWORD="${3:-hellotuya}"
MITM_SERVER_IP="${4:-}"
MITM_HTTP_PORT="${MITM_HTTP_PORT:-58080}"
MITM_WIREGUARD_PORT="${MITM_WIREGUARD_PORT:-51820}"
MITM_SOCKS5_PORT="${MITM_SOCKS5_PORT:-51080}"
MITM_MODE="${MITM_MODE:-transparent}"

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

if [[ -z "$TARGET_IP" ]]; then
    echo "Usage: $0 <target-ip> [username] [password] [mitm-server-ip]"
    echo ""
    echo "Example:"
    echo "  $0 10.0.0.227 root hellotuya 10.0.0.1"
    echo ""
    echo "The mitm-server-ip is the IP address of the machine running MITMproxy."
    echo "If not provided, will attempt to auto-detect from default gateway."
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
# Detect MITM Server IP
#######################################
detect_mitm_server_ip() {
    if [[ -n "$MITM_SERVER_IP" ]]; then
        log_info "Using specified MITM server IP: $MITM_SERVER_IP"
        echo "$MITM_SERVER_IP"
        return 0
    fi
    
    log_info "Auto-detecting MITM server IP from default gateway..."
    
    # Get default gateway (usually the MITMproxy server)
    local gateway
    gateway=$(execute_command "ip route | grep default | head -1 | awk '{print \$3}'" 15 || echo "")
    
    if [[ -n "$gateway" ]]; then
        log_success "Detected MITM server IP: $gateway"
        echo "$gateway"
        return 0
    fi
    
    log_error "Could not detect MITM server IP. Please specify as 4th argument."
    exit 1
}

#######################################
# Check iptables on Remote Device
#######################################
check_remote_iptables() {
    log_info "Checking iptables availability on remote device..."
    
    local iptables_check
    iptables_check=$(execute_command "which iptables 2>/dev/null || echo 'not found'" 15 || true)
    
    if echo "$iptables_check" | grep -q "not found"; then
        log_error "iptables not found on remote device"
        return 1
    fi
    
    log_success "iptables is available on remote device"
    return 0
}

#######################################
# Setup Transparent Proxy Rules (Remote)
#######################################
setup_transparent_mode_remote() {
    local mitm_server_ip="$1"
    log_info "Setting up transparent proxy mode on remote device..."
    
    # Enable IP forwarding
    execute_command "echo 1 > /proc/sys/net/ipv4/ip_forward" 10 || log_warn "Failed to enable IP forwarding"
    
    # Flush existing NAT rules
    execute_command "iptables -t nat -F PREROUTING 2>/dev/null || true" 10 || true
    execute_command "iptables -t nat -F OUTPUT 2>/dev/null || true" 10 || true
    
    # Allow loopback
    execute_command "iptables -t nat -A OUTPUT -o lo -j ACCEPT" 10 || log_warn "Failed to add loopback rule"
    
    # Redirect HTTP traffic (port 80) to MITMproxy server
    execute_command "iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination ${mitm_server_ip}:${MITM_HTTP_PORT}" 10 || log_warn "Failed to add HTTP redirect"
    execute_command "iptables -t nat -A OUTPUT -p tcp --dport 80 -j DNAT --to-destination ${mitm_server_ip}:${MITM_HTTP_PORT}" 10 || log_warn "Failed to add HTTP output redirect"
    
    # Redirect HTTPS traffic (port 443) to MITMproxy server
    execute_command "iptables -t nat -A PREROUTING -p tcp --dport 443 -j DNAT --to-destination ${mitm_server_ip}:${MITM_HTTP_PORT}" 10 || log_warn "Failed to add HTTPS redirect"
    execute_command "iptables -t nat -A OUTPUT -p tcp --dport 443 -j DNAT --to-destination ${mitm_server_ip}:${MITM_HTTP_PORT}" 10 || log_warn "Failed to add HTTPS output redirect"
    
    # Allow direct connections to MITMproxy server
    execute_command "iptables -t nat -A OUTPUT -p tcp -d ${mitm_server_ip} --dport ${MITM_HTTP_PORT} -j ACCEPT" 10 || log_warn "Failed to add MITMproxy allow rule"
    execute_command "iptables -t nat -A OUTPUT -p tcp -d ${mitm_server_ip} --dport ${MITM_WIREGUARD_PORT} -j ACCEPT" 10 || log_warn "Failed to add WireGuard allow rule"
    execute_command "iptables -t nat -A OUTPUT -p tcp -d ${mitm_server_ip} --dport ${MITM_SOCKS5_PORT} -j ACCEPT" 10 || log_warn "Failed to add SOCKS5 allow rule"
    
    log_success "Transparent proxy rules configured on remote device"
}

#######################################
# Setup Explicit Proxy Rules (Remote)
#######################################
setup_explicit_mode_remote() {
    local mitm_server_ip="$1"
    log_info "Setting up explicit proxy mode on remote device..."
    
    # Enable IP forwarding
    execute_command "echo 1 > /proc/sys/net/ipv4/ip_forward" 10 || log_warn "Failed to enable IP forwarding"
    
    # Flush existing NAT rules
    execute_command "iptables -t nat -F PREROUTING 2>/dev/null || true" 10 || true
    execute_command "iptables -t nat -F OUTPUT 2>/dev/null || true" 10 || true
    
    # Allow loopback
    execute_command "iptables -t nat -A OUTPUT -o lo -j ACCEPT" 10 || log_warn "Failed to add loopback rule"
    
    # Redirect all TCP traffic to MITMproxy server (except MITMproxy ports)
    # Note: In explicit mode, applications should be configured to use the proxy
    execute_command "iptables -t nat -A PREROUTING -p tcp ! --dport ${MITM_HTTP_PORT} ! --dport ${MITM_WIREGUARD_PORT} ! --dport ${MITM_SOCKS5_PORT} -j DNAT --to-destination ${mitm_server_ip}:${MITM_HTTP_PORT}" 10 || log_warn "Failed to add TCP redirect"
    execute_command "iptables -t nat -A OUTPUT -p tcp ! --dport ${MITM_HTTP_PORT} ! --dport ${MITM_WIREGUARD_PORT} ! --dport ${MITM_SOCKS5_PORT} -j DNAT --to-destination ${mitm_server_ip}:${MITM_HTTP_PORT}" 10 || log_warn "Failed to add TCP output redirect"
    
    # Allow direct connections to MITMproxy server
    execute_command "iptables -t nat -A OUTPUT -p tcp -d ${mitm_server_ip} --dport ${MITM_HTTP_PORT} -j ACCEPT" 10 || log_warn "Failed to add MITMproxy allow rule"
    execute_command "iptables -t nat -A OUTPUT -p tcp -d ${mitm_server_ip} --dport ${MITM_WIREGUARD_PORT} -j ACCEPT" 10 || log_warn "Failed to add WireGuard allow rule"
    execute_command "iptables -t nat -A OUTPUT -p tcp -d ${mitm_server_ip} --dport ${MITM_SOCKS5_PORT} -j ACCEPT" 10 || log_warn "Failed to add SOCKS5 allow rule"
    
    log_success "Explicit proxy rules configured on remote device"
    log_warn "Note: Applications on device must be configured to use proxy on ${mitm_server_ip}:${MITM_HTTP_PORT}"
}

#######################################
# Display Remote Rules
#######################################
show_remote_rules() {
    log_info "Current iptables NAT rules on remote device:"
    local rules_output
    rules_output=$(execute_command "iptables -t nat -L -n -v" 15 || echo "Failed to retrieve rules")
    echo "$rules_output"
    echo ""
}

#######################################
# Main Execution
#######################################
main() {
    log_info "MITMproxy Remote iptables Setup"
    log_info "=================================="
    log_info "Target: $TARGET_IP"
    log_info "Username: $USERNAME"
    
    if ! check_remote_iptables; then
        log_error "Cannot proceed without iptables on remote device"
        exit 1
    fi
    
    local mitm_server_ip
    mitm_server_ip=$(detect_mitm_server_ip)
    
    log_info "MITM Server IP: $mitm_server_ip"
    log_info "HTTP Port: $MITM_HTTP_PORT"
    log_info "WireGuard Port: $MITM_WIREGUARD_PORT"
    log_info "SOCKS5 Port: $MITM_SOCKS5_PORT"
    log_info "Mode: $MITM_MODE"
    
    case "$MITM_MODE" in
        transparent)
            setup_transparent_mode_remote "$mitm_server_ip"
            ;;
        explicit)
            setup_explicit_mode_remote "$mitm_server_ip"
            ;;
        *)
            log_error "Invalid mode: $MITM_MODE. Use 'transparent' or 'explicit'"
            exit 1
            ;;
    esac
    
    show_remote_rules
    
    log_success "iptables rules configured successfully on remote device"
    log_info "To remove rules, run cleanup script or manually:"
    log_info "  iptables -t nat -F PREROUTING && iptables -t nat -F OUTPUT"
}

main "$@"

