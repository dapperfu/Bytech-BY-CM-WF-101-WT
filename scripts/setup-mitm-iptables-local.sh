#!/usr/bin/env bash
set -euo pipefail

#######################################
# Local MITMproxy iptables Setup Script
# Sets up iptables rules to redirect local traffic through MITMproxy
#######################################

MITM_HTTP_PORT="${MITM_HTTP_PORT:-58080}"
MITM_WIREGUARD_PORT="${MITM_WIREGUARD_PORT:-51820}"
MITM_SOCKS5_PORT="${MITM_SOCKS5_PORT:-51080}"
MITM_MODE="${MITM_MODE:-transparent}"
MITM_INTERFACE="${MITM_INTERFACE:-}"

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
# Check Root Access
#######################################
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

#######################################
# Check iptables Availability
#######################################
check_iptables() {
    if ! command -v iptables >/dev/null 2>&1; then
        log_error "iptables not found. Please install iptables."
        exit 1
    fi
    log_success "iptables is available"
}

#######################################
# Auto-detect Network Interface
#######################################
detect_interface() {
    if [[ -n "$MITM_INTERFACE" ]]; then
        log_info "Using specified interface: $MITM_INTERFACE"
        echo "$MITM_INTERFACE"
        return 0
    fi
    
    log_info "Auto-detecting network interface..."
    
    # Try to get default gateway interface
    local default_route
    default_route=$(ip route | grep default | head -1 | awk '{print $5}' 2>/dev/null || echo "")
    
    if [[ -n "$default_route" ]]; then
        log_success "Detected interface: $default_route"
        echo "$default_route"
        return 0
    fi
    
    # Fallback: try to find first non-lo interface
    local first_interface
    first_interface=$(ip link show | grep -E '^[0-9]+:' | grep -v lo | head -1 | awk -F': ' '{print $2}' | awk '{print $1}' 2>/dev/null || echo "")
    
    if [[ -n "$first_interface" ]]; then
        log_warn "Using fallback interface: $first_interface"
        echo "$first_interface"
        return 0
    fi
    
    log_error "Could not detect network interface. Please specify MITM_INTERFACE environment variable."
    exit 1
}

#######################################
# Setup Transparent Proxy Rules
#######################################
setup_transparent_mode() {
    local interface="$1"
    log_info "Setting up transparent proxy mode..."
    
    # Enable IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    # Flush existing NAT rules (be careful!)
    iptables -t nat -F PREROUTING 2>/dev/null || true
    iptables -t nat -F OUTPUT 2>/dev/null || true
    
    # Allow loopback
    iptables -t nat -A OUTPUT -o lo -j ACCEPT
    
    # Redirect HTTP traffic (port 80) to MITMproxy
    iptables -t nat -A PREROUTING -i "$interface" -p tcp --dport 80 -j REDIRECT --to-port "$MITM_HTTP_PORT"
    iptables -t nat -A OUTPUT -p tcp --dport 80 -j REDIRECT --to-port "$MITM_HTTP_PORT"
    
    # Redirect HTTPS traffic (port 443) to MITMproxy
    iptables -t nat -A PREROUTING -i "$interface" -p tcp --dport 443 -j REDIRECT --to-port "$MITM_HTTP_PORT"
    iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-port "$MITM_HTTP_PORT"
    
    # Allow direct connections to MITMproxy ports
    iptables -t nat -A OUTPUT -p tcp --dport "$MITM_HTTP_PORT" -j ACCEPT
    iptables -t nat -A OUTPUT -p tcp --dport "$MITM_WIREGUARD_PORT" -j ACCEPT
    iptables -t nat -A OUTPUT -p tcp --dport "$MITM_SOCKS5_PORT" -j ACCEPT
    
    log_success "Transparent proxy rules configured"
}

#######################################
# Setup Explicit Proxy Rules
#######################################
setup_explicit_mode() {
    local interface="$1"
    log_info "Setting up explicit proxy mode..."
    
    # Enable IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    # Flush existing NAT rules
    iptables -t nat -F PREROUTING 2>/dev/null || true
    iptables -t nat -F OUTPUT 2>/dev/null || true
    
    # Allow loopback
    iptables -t nat -A OUTPUT -o lo -j ACCEPT
    
    # Redirect all TCP traffic to MITMproxy HTTP port (for explicit proxy)
    # Note: In explicit mode, applications must be configured to use the proxy
    # This rule redirects unconfigured traffic to the proxy
    iptables -t nat -A PREROUTING -i "$interface" -p tcp ! --dport "$MITM_HTTP_PORT" ! --dport "$MITM_WIREGUARD_PORT" ! --dport "$MITM_SOCKS5_PORT" -j REDIRECT --to-port "$MITM_HTTP_PORT"
    iptables -t nat -A OUTPUT -p tcp ! --dport "$MITM_HTTP_PORT" ! --dport "$MITM_WIREGUARD_PORT" ! --dport "$MITM_SOCKS5_PORT" -j REDIRECT --to-port "$MITM_HTTP_PORT"
    
    # Allow direct connections to MITMproxy ports
    iptables -t nat -A OUTPUT -p tcp --dport "$MITM_HTTP_PORT" -j ACCEPT
    iptables -t nat -A OUTPUT -p tcp --dport "$MITM_WIREGUARD_PORT" -j ACCEPT
    iptables -t nat -A OUTPUT -p tcp --dport "$MITM_SOCKS5_PORT" -j ACCEPT
    
    log_success "Explicit proxy rules configured"
    log_warn "Note: Applications must be configured to use proxy on port $MITM_HTTP_PORT"
}

#######################################
# Display Current Rules
#######################################
show_rules() {
    log_info "Current iptables NAT rules:"
    echo ""
    iptables -t nat -L -n -v
    echo ""
}

#######################################
# Main Execution
#######################################
main() {
    log_info "MITMproxy Local iptables Setup"
    log_info "=================================="
    
    check_root
    check_iptables
    
    local interface
    interface=$(detect_interface)
    
    log_info "Interface: $interface"
    log_info "HTTP Port: $MITM_HTTP_PORT"
    log_info "WireGuard Port: $MITM_WIREGUARD_PORT"
    log_info "SOCKS5 Port: $MITM_SOCKS5_PORT"
    log_info "Mode: $MITM_MODE"
    
    case "$MITM_MODE" in
        transparent)
            setup_transparent_mode "$interface"
            ;;
        explicit)
            setup_explicit_mode "$interface"
            ;;
        *)
            log_error "Invalid mode: $MITM_MODE. Use 'transparent' or 'explicit'"
            exit 1
            ;;
    esac
    
    show_rules
    
    log_success "iptables rules configured successfully"
    log_info "To remove rules, run: make mitm-clean"
    log_info "Or manually: iptables -t nat -F PREROUTING && iptables -t nat -F OUTPUT"
}

main "$@"

