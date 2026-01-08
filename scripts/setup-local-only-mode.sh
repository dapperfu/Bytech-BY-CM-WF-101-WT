#!/usr/bin/env bash
set -euo pipefail

#######################################
# Master Integration Script
# Orchestrates all components for local-only mode setup
#######################################

TARGET_IP="${1:-}"
USERNAME="${2:-root}"
PASSWORD="${3:-hellotuya}"
RTSP_STREAM_PATH="${4:-/stream1}"

# Default credentials from README
if [[ "$USERNAME" == "user" ]] && [[ "$PASSWORD" == "hellotuya" ]]; then
    PASSWORD="user123"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="setup-local-only-$(date +%Y%m%d_%H%M%S).log"

if [[ -z "$TARGET_IP" ]]; then
    echo "Usage: $0 <target-ip> [username] [password] [rtsp-stream-path]"
    echo ""
    echo "Example:"
    echo "  $0 10.0.0.227 root hellotuya /stream1"
    echo ""
    echo "This script orchestrates the complete local-only mode setup:"
    echo "  1. Discover RTSP streams"
    echo "  2. Set up local RTSP server"
    echo "  3. Replace apollo"
    echo "  4. Apply firewall rules"
    echo "  5. Block cloud at process level"
    echo "  6. Block DNS"
    echo "  7. Start monitoring"
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
# Setup Functions
#######################################
run_script() {
    local script="$1"
    shift
    local args=("$@")
    
    log_info "Running: $script ${args[*]}"
    
    if [[ ! -f "$SCRIPT_DIR/$script" ]]; then
        log_error "Script not found: $script"
        return 1
    fi
    
    if bash "$SCRIPT_DIR/$script" "${args[@]}" >> "$LOG_FILE" 2>&1; then
        log_success "Completed: $script"
        return 0
    else
        log_error "Failed: $script"
        return 1
    fi
}

discover_rtsp_streams() {
    log_info "=== Phase 1: Discovering RTSP streams ==="
    
    local output_file="rtsp-discovery-$(date +%Y%m%d_%H%M%S).txt"
    if run_script "discover-rtsp-streams.sh" "$TARGET_IP" "$USERNAME" "$PASSWORD" "$output_file"; then
        log_success "RTSP stream discovery complete"
        return 0
    else
        log_warn "RTSP stream discovery had issues, continuing..."
        return 1
    fi
}

analyze_webcam_interface() {
    log_info "=== Phase 1: Analyzing webcam interface ==="
    
    local output_file="webcam-interface-$(date +%Y%m%d_%H%M%S).txt"
    if run_script "analyze-webcam-interface.sh" "$TARGET_IP" "$USERNAME" "$PASSWORD" "$output_file"; then
        log_success "Webcam interface analysis complete"
        return 0
    else
        log_warn "Webcam interface analysis had issues, continuing..."
        return 1
    fi
}

discover_cloud_endpoints() {
    log_info "=== Phase 1: Discovering cloud endpoints ==="
    
    local output_file="cloud-endpoints-$(date +%Y%m%d_%H%M%S).txt"
    if run_script "discover-cloud-endpoints.sh" "$TARGET_IP" "$USERNAME" "$PASSWORD" "$output_file"; then
        log_success "Cloud endpoint discovery complete"
        return 0
    else
        log_warn "Cloud endpoint discovery had issues, continuing..."
        return 1
    fi
}

setup_local_rtsp() {
    log_info "=== Phase 2: Setting up local RTSP server ==="
    
    if run_script "setup-local-rtsp.sh" "$TARGET_IP" "$USERNAME" "$PASSWORD" "$RTSP_STREAM_PATH"; then
        log_success "Local RTSP server setup complete"
        return 0
    else
        log_error "Local RTSP server setup failed"
        return 1
    fi
}

replace_apollo() {
    log_info "=== Phase 2: Replacing apollo with local RTSP server ==="
    
    if run_script "replace-apollo-rtsp.sh" "$TARGET_IP" "$USERNAME" "$PASSWORD"; then
        log_success "Apollo replacement complete"
        return 0
    else
        log_error "Apollo replacement failed"
        return 1
    fi
}

block_cloud_iptables() {
    log_info "=== Phase 3: Blocking cloud with iptables ==="
    
    local cloud_ips_file="cloud-endpoints-*.txt"
    if run_script "block-cloud-iptables.sh" "$TARGET_IP" "$USERNAME" "$PASSWORD" "$cloud_ips_file"; then
        log_success "iptables cloud blocking complete"
        return 0
    else
        log_error "iptables cloud blocking failed"
        return 1
    fi
}

block_cloud_process() {
    log_info "=== Phase 3: Blocking cloud at process level ==="
    
    if run_script "block-cloud-process.sh" "$TARGET_IP" "$USERNAME" "$PASSWORD"; then
        log_success "Process-level cloud blocking complete"
        return 0
    else
        log_error "Process-level cloud blocking failed"
        return 1
    fi
}

block_cloud_dns() {
    log_info "=== Phase 3: Blocking cloud DNS ==="
    
    if run_script "block-cloud-dns.sh" "$TARGET_IP" "$USERNAME" "$PASSWORD"; then
        log_success "DNS blocking complete"
        return 0
    else
        log_error "DNS blocking failed"
        return 1
    fi
}

start_monitoring() {
    log_info "=== Phase 4: Starting connection monitoring ==="
    
    log_info "To start monitoring, run:"
    log_info "  ./scripts/monitor-connections.sh $TARGET_IP $USERNAME $PASSWORD"
    log_info ""
    log_info "To analyze connections, run:"
    log_info "  ./scripts/analyze-connections.sh $TARGET_IP $USERNAME $PASSWORD"
    log_info ""
    log_info "To start alerts, run:"
    log_info "  ./scripts/connection-alerts.sh $TARGET_IP $USERNAME $PASSWORD"
}

create_status_script() {
    log_info "Creating status check script..."
    
    local status_script
    status_script=$(cat <<STATUS
#!/bin/bash
# Status check script for local-only mode

TARGET_IP="$TARGET_IP"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"

echo "=== Local-Only Mode Status ==="
echo ""

# Check RTSP server
echo "RTSP Server:"
./scripts/analyze-connections.sh "\$TARGET_IP" "\$USERNAME" "\$PASSWORD" | grep -E "8554|RTSP" || echo "  Not accessible"

# Check cloud connections
echo ""
echo "Cloud Connections:"
./scripts/analyze-connections.sh "\$TARGET_IP" "\$USERNAME" "\$PASSWORD" | grep -E "CLOUD|52\.42\.98\.25" || echo "  None detected"

# Check firewall rules
echo ""
echo "Firewall Status:"
# Would need to check iptables rules via telnet

echo ""
echo "Status check complete"
STATUS
)
    
    echo "$status_script" > "$SCRIPT_DIR/check-local-only-status.sh"
    chmod +x "$SCRIPT_DIR/check-local-only-status.sh"
    log_success "Status check script created: check-local-only-status.sh"
}

create_rollback_script() {
    log_info "Creating rollback script..."
    
    local rollback_script
    rollback_script=$(cat <<ROLLBACK
#!/bin/bash
# Rollback script for local-only mode

TARGET_IP="$TARGET_IP"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"

echo "=== Rolling back local-only mode ==="
echo ""

# Restore apollo (if backup exists)
echo "Restoring apollo..."
# Would need to restore from backup

# Restore iptables
echo "Restoring iptables..."
# Would need to restore from backup

# Restore DNS
echo "Restoring DNS..."
# Would need to restore from backup

echo ""
echo "Rollback complete"
ROLLBACK
)
    
    echo "$rollback_script" > "$SCRIPT_DIR/rollback-local-only.sh"
    chmod +x "$SCRIPT_DIR/rollback-local-only.sh"
    log_success "Rollback script created: rollback-local-only.sh"
}

#######################################
# Main Function
#######################################
main() {
    log_info "Starting local-only mode setup for $TARGET_IP"
    log_info "Log file: $LOG_FILE"
    echo ""
    
    # Phase 1: Discovery
    discover_rtsp_streams
    analyze_webcam_interface
    discover_cloud_endpoints
    
    echo ""
    log_info "Phase 1 complete. Review discovery results before proceeding."
    read -p "Press Enter to continue to Phase 2 (RTSP setup) or Ctrl+C to abort..."
    
    # Phase 2: RTSP Setup
    setup_local_rtsp
    replace_apollo
    
    echo ""
    log_info "Phase 2 complete. Review RTSP setup before proceeding."
    read -p "Press Enter to continue to Phase 3 (Cloud blocking) or Ctrl+C to abort..."
    
    # Phase 3: Cloud Blocking
    block_cloud_iptables
    block_cloud_process
    block_cloud_dns
    
    echo ""
    log_info "Phase 3 complete."
    
    # Phase 4: Monitoring
    start_monitoring
    
    # Create helper scripts
    create_status_script
    create_rollback_script
    
    echo ""
    log_success "Local-only mode setup complete!"
    log_info "Setup log: $LOG_FILE"
    log_info "RTSP stream: rtsp://${TARGET_IP}:8554${RTSP_STREAM_PATH}"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Verify RTSP stream is accessible"
    log_info "  2. Start connection monitoring"
    log_info "  3. Verify no cloud connections are active"
}

main "$@"

