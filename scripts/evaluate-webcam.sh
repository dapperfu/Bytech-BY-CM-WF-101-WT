#!/usr/bin/env bash
set -euo pipefail

#######################################
# Master Evaluation Script
# Runs all discovery and analysis scripts and evaluates results
#######################################

TARGET_IP="${1:-}"
USERNAME="${2:-root}"
PASSWORD="${3:-hellotuya}"

# Default credentials from README
if [[ "$USERNAME" == "user" ]] && [[ "$PASSWORD" == "hellotuya" ]]; then
    PASSWORD="user123"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="webcam-evaluation-${TARGET_IP}-${TS}"
SUMMARY_FILE="${OUTPUT_DIR}/evaluation-summary.txt"

if [[ -z "$TARGET_IP" ]]; then
    echo "Usage: $0 <target-ip> [username] [password]"
    echo ""
    echo "Example:"
    echo "  $0 10.0.0.227 root hellotuya"
    echo ""
    echo "This script runs all discovery and analysis scripts and provides"
    echo "a comprehensive evaluation of the webcam's current state."
    exit 1
fi

#######################################
# Setup
#######################################
mkdir -p "$OUTPUT_DIR"

#######################################
# Logging Functions
#######################################
log() {
    local level="${1:-INFO}"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$SUMMARY_FILE"
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

log_section() {
    echo "" | tee -a "$SUMMARY_FILE"
    echo "========================================" | tee -a "$SUMMARY_FILE"
    echo "$1" | tee -a "$SUMMARY_FILE"
    echo "========================================" | tee -a "$SUMMARY_FILE"
    echo "" | tee -a "$SUMMARY_FILE"
}

#######################################
# Evaluation Functions
#######################################
run_discovery() {
    log_section "Phase 1: Discovery and Analysis"
    
    log_info "Running RTSP stream discovery..."
    local rtsp_output="${OUTPUT_DIR}/rtsp-discovery.txt"
    if bash "$SCRIPT_DIR/discover-rtsp-streams.sh" "$TARGET_IP" "$USERNAME" "$PASSWORD" "$rtsp_output" >> "$SUMMARY_FILE" 2>&1; then
        log_success "RTSP discovery complete"
        if [[ -f "$rtsp_output" ]]; then
            # Extract discovered streams
            local streams
            streams=$(grep -E "^rtsp://" "$rtsp_output" 2>/dev/null || true)
            if [[ -n "$streams" ]]; then
                log_info "Discovered RTSP streams:"
                echo "$streams" | while read -r stream; do
                    log_info "  - $stream"
                done
            else
                log_warn "No RTSP streams discovered"
            fi
        fi
    else
        log_error "RTSP discovery failed"
    fi
    
    echo "" | tee -a "$SUMMARY_FILE"
    
    log_info "Running webcam interface analysis..."
    local interface_output="${OUTPUT_DIR}/webcam-interface.txt"
    if bash "$SCRIPT_DIR/analyze-webcam-interface.sh" "$TARGET_IP" "$USERNAME" "$PASSWORD" "$interface_output" >> "$SUMMARY_FILE" 2>&1; then
        log_success "Interface analysis complete"
        # Check for video devices
        if [[ -f "$interface_output" ]] && grep -q "video" "$interface_output" 2>/dev/null; then
            log_info "Video devices found (see $interface_output for details)"
        else
            log_warn "No video devices detected"
        fi
    else
        log_error "Interface analysis failed"
    fi
    
    echo "" | tee -a "$SUMMARY_FILE"
    
    log_info "Running cloud endpoint discovery..."
    local cloud_output="${OUTPUT_DIR}/cloud-endpoints.txt"
    if bash "$SCRIPT_DIR/discover-cloud-endpoints.sh" "$TARGET_IP" "$USERNAME" "$PASSWORD" "$cloud_output" >> "$SUMMARY_FILE" 2>&1; then
        log_success "Cloud endpoint discovery complete"
        if [[ -f "$cloud_output" ]]; then
            # Extract cloud IPs
            local cloud_ips
            cloud_ips=$(grep -E "^([0-9]{1,3}\.){3}[0-9]{1,3}$" "$cloud_output" 2>/dev/null | sort -u || true)
            if [[ -n "$cloud_ips" ]]; then
                log_warn "Cloud endpoints discovered:"
                echo "$cloud_ips" | while read -r ip; do
                    log_warn "  - $ip"
                done
            else
                log_success "No cloud endpoints found"
            fi
        fi
    else
        log_error "Cloud endpoint discovery failed"
    fi
}

run_connection_analysis() {
    log_section "Phase 2: Connection Analysis"
    
    log_info "Analyzing current connections..."
    local conn_output="${OUTPUT_DIR}/connection-analysis.txt"
    if bash "$SCRIPT_DIR/analyze-connections.sh" "$TARGET_IP" "$USERNAME" "$PASSWORD" "$conn_output" >> "$SUMMARY_FILE" 2>&1; then
        log_success "Connection analysis complete"
        
        if [[ -f "$conn_output" ]]; then
            # Count cloud connections
            local cloud_count
            cloud_count=$(grep -c "CLOUD\|52\.42\.98\.25" "$conn_output" 2>/dev/null || echo "0")
            
            if [[ "$cloud_count" -gt 0 ]]; then
                log_warn "Active cloud connections detected: $cloud_count"
                log_info "Cloud connections:"
                grep "CLOUD\|52\.42\.98\.25" "$conn_output" | head -10 | while read -r conn; do
                    log_warn "  - $conn"
                done
            else
                log_success "No active cloud connections detected"
            fi
            
            # Count listening services
            local listening_count
            listening_count=$(grep -c "LISTEN\|LISTENING" "$conn_output" 2>/dev/null || echo "0")
            log_info "Listening services: $listening_count"
            
            # Check for RTSP port
            if grep -q "8554\|RTSP" "$conn_output" 2>/dev/null; then
                log_success "RTSP service detected on port 8554"
            else
                log_warn "RTSP service not detected on port 8554"
            fi
        fi
    else
        log_error "Connection analysis failed"
    fi
}

evaluate_rtsp_setup() {
    log_section "Phase 3: RTSP Setup Evaluation"
    
    log_info "Evaluating RTSP server setup requirements..."
    
    # Check if RTSP stream was discovered
    local rtsp_output="${OUTPUT_DIR}/rtsp-discovery.txt"
    if [[ -f "$rtsp_output" ]] && grep -q "rtsp://" "$rtsp_output" 2>/dev/null; then
        log_success "RTSP stream path discovered"
        local stream_path
        stream_path=$(grep "rtsp://" "$rtsp_output" | head -1 | sed 's|rtsp://[^/]*||' || echo "unknown")
        log_info "Stream path: $stream_path"
    else
        log_warn "RTSP stream path not discovered - may need manual configuration"
    fi
    
    # Check video device availability
    local interface_output="${OUTPUT_DIR}/webcam-interface.txt"
    if [[ -f "$interface_output" ]] && grep -q "/dev/video" "$interface_output" 2>/dev/null; then
        log_success "Video device available for RTSP server"
    else
        log_warn "Video device not detected - RTSP server may not be able to capture video"
    fi
    
    log_info "RTSP server setup status:"
    log_info "  - Stream path: $(grep -m1 "rtsp://" "${OUTPUT_DIR}/rtsp-discovery.txt" 2>/dev/null | sed 's|rtsp://[^/]*||' || echo "Not discovered")"
    log_info "  - Video device: $(grep -m1 "/dev/video" "${OUTPUT_DIR}/webcam-interface.txt" 2>/dev/null | awk '{print $NF}' || echo "Not found")"
    log_info "  - RTSP port: 8554"
}

evaluate_cloud_blocking() {
    log_section "Phase 4: Cloud Blocking Evaluation"
    
    log_info "Evaluating cloud blocking requirements..."
    
    # Get cloud endpoints
    local cloud_output="${OUTPUT_DIR}/cloud-endpoints.txt"
    local cloud_ips=()
    
    if [[ -f "$cloud_output" ]]; then
        while IFS= read -r ip; do
            [[ -z "$ip" ]] && continue
            [[ "$ip" =~ ^# ]] && continue
            if echo "$ip" | grep -qE "^([0-9]{1,3}\.){3}[0-9]{1,3}$"; then
                cloud_ips+=("$ip")
            fi
        done < <(grep -E "^([0-9]{1,3}\.){3}[0-9]{1,3}$" "$cloud_output" 2>/dev/null || true)
    fi
    
    # Add known cloud IP
    cloud_ips+=("52.42.98.25")
    
    # Remove duplicates
    local unique_ips
    unique_ips=$(printf '%s\n' "${cloud_ips[@]}" | sort -u)
    
    if [[ -n "$unique_ips" ]]; then
        local ip_count
        ip_count=$(echo "$unique_ips" | wc -l)
        log_warn "Cloud IPs to block: $ip_count"
        echo "$unique_ips" | while read -r ip; do
            log_info "  - $ip"
        done
        
        log_info ""
        log_info "Blocking methods available:"
        log_info "  1. iptables firewall rules (network level)"
        log_info "  2. Process-level blocking (application level)"
        log_info "  3. DNS blocking (prevent resolution)"
    else
        log_success "No cloud endpoints to block"
    fi
    
    # Check current blocking status
    local conn_output="${OUTPUT_DIR}/connection-analysis.txt"
    if [[ -f "$conn_output" ]]; then
        local active_cloud
        active_cloud=$(grep -c "CLOUD\|52\.42\.98\.25" "$conn_output" 2>/dev/null || echo "0")
        
        if [[ "$active_cloud" -gt 0 ]]; then
            log_warn "Cloud blocking NOT active - $active_cloud cloud connection(s) detected"
        else
            log_success "Cloud blocking appears active - no cloud connections detected"
        fi
    fi
}

evaluate_monitoring() {
    log_section "Phase 5: Monitoring Evaluation"
    
    log_info "Evaluating monitoring capabilities..."
    
    local monitoring_scripts=(
        "monitor-connections.sh:Real-time connection monitoring"
        "analyze-connections.sh:One-time connection analysis"
        "connection-alerts.sh:Cloud connection alerts"
    )
    
    local all_available=true
    for script_info in "${monitoring_scripts[@]}"; do
        local script_name
        script_name=$(echo "$script_info" | cut -d: -f1)
        local script_desc
        script_desc=$(echo "$script_info" | cut -d: -f2)
        
        if [[ -f "$SCRIPT_DIR/$script_name" ]] && [[ -x "$SCRIPT_DIR/$script_name" ]]; then
            log_success "$script_desc: Available"
        else
            log_error "$script_desc: Not found or not executable"
            all_available=false
        fi
    done
    
    if [[ "$all_available" == "true" ]]; then
        log_success "All monitoring tools are available"
    else
        log_warn "Some monitoring tools are missing"
    fi
}

generate_summary() {
    log_section "Evaluation Summary"
    
    echo "Target: $TARGET_IP" | tee -a "$SUMMARY_FILE"
    echo "Evaluation Date: $(date)" | tee -a "$SUMMARY_FILE"
    echo "" | tee -a "$SUMMARY_FILE"
    
    # RTSP Status
    echo "=== RTSP Stream Status ===" | tee -a "$SUMMARY_FILE"
    local rtsp_output="${OUTPUT_DIR}/rtsp-discovery.txt"
    if [[ -f "$rtsp_output" ]] && grep -q "rtsp://" "$rtsp_output" 2>/dev/null; then
        local stream_url
        stream_url=$(grep "rtsp://" "$rtsp_output" | head -1)
        echo "Stream URL: $stream_url" | tee -a "$SUMMARY_FILE"
        echo "Status: DISCOVERED" | tee -a "$SUMMARY_FILE"
    else
        echo "Status: NOT DISCOVERED" | tee -a "$SUMMARY_FILE"
    fi
    echo "" | tee -a "$SUMMARY_FILE"
    
    # Cloud Connection Status
    echo "=== Cloud Connection Status ===" | tee -a "$SUMMARY_FILE"
    local conn_output="${OUTPUT_DIR}/connection-analysis.txt"
    if [[ -f "$conn_output" ]]; then
        local cloud_count
        cloud_count=$(grep -c "CLOUD\|52\.42\.98\.25" "$conn_output" 2>/dev/null | tr -d '[:space:]' || echo "0")
        # Ensure cloud_count is a valid integer
        cloud_count="${cloud_count:-0}"
        if [[ "$cloud_count" =~ ^[0-9]+$ ]] && [[ "$cloud_count" -gt 0 ]]; then
            echo "Status: ACTIVE CLOUD CONNECTIONS DETECTED" | tee -a "$SUMMARY_FILE"
            echo "Count: $cloud_count" | tee -a "$SUMMARY_FILE"
        else
            echo "Status: NO CLOUD CONNECTIONS" | tee -a "$SUMMARY_FILE"
        fi
    else
        echo "Status: UNKNOWN" | tee -a "$SUMMARY_FILE"
    fi
    echo "" | tee -a "$SUMMARY_FILE"
    
    # Cloud Endpoints
    echo "=== Cloud Endpoints ===" | tee -a "$SUMMARY_FILE"
    local cloud_output="${OUTPUT_DIR}/cloud-endpoints.txt"
    if [[ -f "$cloud_output" ]]; then
        local endpoint_count
        endpoint_count=$(grep -cE "^([0-9]{1,3}\.){3}[0-9]{1,3}$" "$cloud_output" 2>/dev/null || echo "0")
        echo "Discovered: $endpoint_count cloud endpoint(s)" | tee -a "$SUMMARY_FILE"
        if [[ "$endpoint_count" -gt 0 ]]; then
            grep -E "^([0-9]{1,3}\.){3}[0-9]{1,3}$" "$cloud_output" | head -10 | tee -a "$SUMMARY_FILE"
        fi
    else
        echo "No cloud endpoints file found" | tee -a "$SUMMARY_FILE"
    fi
    echo "" | tee -a "$SUMMARY_FILE"
    
    # Recommendations
    echo "=== Recommendations ===" | tee -a "$SUMMARY_FILE"
    
    local interface_output="${OUTPUT_DIR}/webcam-interface.txt"
    
    if [[ -f "$rtsp_output" ]] && ! grep -q "rtsp://" "$rtsp_output" 2>/dev/null; then
        echo "- Run RTSP discovery with different paths or check authentication" | tee -a "$SUMMARY_FILE"
    fi
    
    if [[ -f "$conn_output" ]] && grep -q "52\.42\.98\.25" "$conn_output" 2>/dev/null; then
        echo "- Apply cloud blocking immediately (iptables, process-level, DNS)" | tee -a "$SUMMARY_FILE"
    fi
    
    if [[ -f "$interface_output" ]] && ! grep -q "/dev/video" "$interface_output" 2>/dev/null; then
        echo "- Verify video device is accessible before setting up RTSP server" | tee -a "$SUMMARY_FILE"
    fi
    
    echo "" | tee -a "$SUMMARY_FILE"
    echo "Full reports available in: $OUTPUT_DIR" | tee -a "$SUMMARY_FILE"
}

#######################################
# Main Function
#######################################
main() {
    log_section "Webcam Evaluation Report"
    log_info "Starting comprehensive evaluation of $TARGET_IP"
    log_info "Output directory: $OUTPUT_DIR"
    echo ""
    
    # Run all discovery and analysis
    run_discovery
    run_connection_analysis
    evaluate_rtsp_setup
    evaluate_cloud_blocking
    evaluate_monitoring
    
    # Generate summary
    generate_summary
    
    echo ""
    log_success "Evaluation complete!"
    log_info "Summary report: $SUMMARY_FILE"
    log_info "All outputs: $OUTPUT_DIR"
    echo ""
    echo "To view the summary:"
    echo "  cat $SUMMARY_FILE"
    echo ""
    echo "To view all results:"
    echo "  ls -lh $OUTPUT_DIR"
}

main "$@"

