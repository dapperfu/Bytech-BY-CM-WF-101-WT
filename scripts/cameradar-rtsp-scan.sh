#!/usr/bin/env bash
set -euo pipefail

#######################################
# Cameradar RTSP Penetration Testing Script
# Uses cameradar Docker image to discover and brute-force RTSP streams
#######################################

TARGET_IP="${1:-}"
PORTS="${2:-554,5554,8554}"
OUTPUT_DIR="${3:-}"
TIMEOUT="${4:-2000}"
ATTACK_INTERVAL="${5:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREDENTIALS_FILE="${SCRIPT_DIR}/wordlists/cameradar-credentials.json"
ROUTES_FILE="${SCRIPT_DIR}/wordlists/cameradar-routes.txt"

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "[!] Error: Docker is not installed or not in PATH"
    exit 1
fi

# Check if Docker daemon is running
if ! docker info &> /dev/null; then
    echo "[!] Error: Docker daemon is not running"
    exit 1
fi

# Validate inputs
if [[ -z "$TARGET_IP" ]]; then
    echo "Usage: $0 <target-ip> [ports] [output-dir] [timeout-ms] [attack-interval-ms]"
    echo ""
    echo "Examples:"
    echo "  $0 10.0.0.227"
    echo "  $0 10.0.0.227 554,8554"
    echo "  $0 10.0.0.227 554,8554 ./output 3000 100"
    echo ""
    echo "Parameters:"
    echo "  target-ip        : Target IP address or network range (required)"
    echo "  ports            : Comma-separated RTSP ports (default: 554,5554,8554)"
    echo "  output-dir       : Output directory for results (default: current directory)"
    echo "  timeout-ms        : Request timeout in milliseconds (default: 2000)"
    echo "  attack-interval-ms: Delay between attacks in milliseconds (default: 0)"
    exit 1
fi

# Set default output directory if not provided
if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="$(pwd)"
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Check if custom dictionaries exist
if [[ ! -f "$CREDENTIALS_FILE" ]]; then
    echo "[!] Warning: Credentials file not found: $CREDENTIALS_FILE"
    echo "[*] Using cameradar default credentials"
    CREDENTIALS_FILE=""
fi

if [[ ! -f "$ROUTES_FILE" ]]; then
    echo "[!] Warning: Routes file not found: $ROUTES_FILE"
    echo "[*] Using cameradar default routes"
    ROUTES_FILE=""
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
# Check if cameradar image exists
#######################################
check_cameradar_image() {
    if ! docker image inspect ullaakut/cameradar &> /dev/null; then
        log_warn "Cameradar Docker image not found. Pulling..."
        if ! docker pull ullaakut/cameradar; then
            log_error "Failed to pull cameradar image"
            return 1
        fi
    fi
    return 0
}

#######################################
# Run Cameradar Scan
#######################################
run_cameradar_scan() {
    local json_output="${OUTPUT_DIR}/cameradar_rtsp.json"
    local text_output="${OUTPUT_DIR}/cameradar_rtsp.txt"
    
    log_info "Starting cameradar RTSP penetration test"
    log_info "Target: $TARGET_IP"
    log_info "Ports: $PORTS"
    log_info "Timeout: ${TIMEOUT}ms"
    log_info "Attack Interval: ${ATTACK_INTERVAL}ms"
    
    # Build Docker run command
    local docker_cmd=(
        "docker" "run" "--rm"
        "--net=host"
    )
    
    # Add volume mounts for custom dictionaries if they exist
    if [[ -n "$CREDENTIALS_FILE" ]]; then
        docker_cmd+=("-v" "${CREDENTIALS_FILE}:/tmp/custom_credentials.json:ro")
    fi
    
    if [[ -n "$ROUTES_FILE" ]]; then
        docker_cmd+=("-v" "${ROUTES_FILE}:/tmp/custom_routes.txt:ro")
    fi
    
    # Add volume mount for output directory
    docker_cmd+=("-v" "${OUTPUT_DIR}:/output")
    
    # Add environment variables
    docker_cmd+=(
        "-e" "CAMERADAR_TARGET=${TARGET_IP}"
        "-e" "CAMERADAR_PORTS=${PORTS}"
        "-e" "CAMERADAR_TIMEOUT=${TIMEOUT}ms"
        "-e" "CAMERADAR_ATTACK_INTERVAL=${ATTACK_INTERVAL}ms"
        "-e" "CAMERADAR_LOGGING=true"
    )
    
    # Add custom dictionary paths if they exist
    if [[ -n "$CREDENTIALS_FILE" ]]; then
        docker_cmd+=("-e" "CAMERADAR_CUSTOM_CREDENTIALS=/tmp/custom_credentials.json")
    fi
    
    if [[ -n "$ROUTES_FILE" ]]; then
        docker_cmd+=("-e" "CAMERADAR_CUSTOM_ROUTES=/tmp/custom_routes.txt")
    fi
    
    # Add image and command
    docker_cmd+=(
        "ullaakut/cameradar"
        "-t" "$TARGET_IP"
        "-p" "$PORTS"
    )
    
    # Add JSON output flag
    docker_cmd+=("--json")
    
    log_info "Executing cameradar..."
    log_info "Command: ${docker_cmd[*]}"
    
    # Run cameradar and capture output
    local temp_json=$(mktemp)
    local temp_text=$(mktemp)
    
    # Execute with JSON output
    if "${docker_cmd[@]}" > "$temp_json" 2> "$temp_text"; then
        # Copy JSON output
        cp "$temp_json" "$json_output"
        log_success "JSON output saved to: $json_output"
        
        # Generate human-readable text output
        {
            echo "=========================================="
            echo "Cameradar RTSP Penetration Test Results"
            echo "=========================================="
            echo "Target: $TARGET_IP"
            echo "Ports: $PORTS"
            echo "Scan Date: $(date)"
            echo ""
            echo "------------------------------------------"
            echo "JSON Output (for parsing):"
            echo "------------------------------------------"
            cat "$temp_json"
            echo ""
            echo "------------------------------------------"
            echo "Execution Log:"
            echo "------------------------------------------"
            cat "$temp_text"
        } > "$text_output"
        
        log_success "Text output saved to: $text_output"
        
        # Parse and display summary
        if command -v jq &> /dev/null && [[ -s "$json_output" ]]; then
            log_info "Parsing results..."
            local stream_count
            stream_count=$(jq -r '.targets | length' "$json_output" 2>/dev/null || echo "0")
            if [[ "$stream_count" != "0" ]] && [[ "$stream_count" != "null" ]]; then
                log_success "Found $stream_count RTSP target(s)"
                echo ""
                echo "Discovered Streams:"
                jq -r '.targets[] | "  - \(.address):\(.port) - Route: \(.route // "unknown") - Credentials: \(.username // "none"):\(.password // "none")"' "$json_output" 2>/dev/null || true
            else
                log_warn "No RTSP streams discovered"
            fi
        else
            log_info "Results saved. Install 'jq' for automatic parsing."
        fi
        
        rm -f "$temp_json" "$temp_text"
        return 0
    else
        log_error "Cameradar execution failed"
        {
            echo "=========================================="
            echo "Cameradar RTSP Penetration Test - ERROR"
            echo "=========================================="
            echo "Target: $TARGET_IP"
            echo "Ports: $PORTS"
            echo "Scan Date: $(date)"
            echo ""
            echo "Error occurred during execution:"
            cat "$temp_text"
        } > "$text_output"
        
        rm -f "$temp_json" "$temp_text"
        return 1
    fi
}

#######################################
# Main Execution
#######################################
main() {
    log_info "Cameradar RTSP Penetration Testing Script"
    log_info "=========================================="
    
    # Check prerequisites
    if ! check_cameradar_image; then
        log_error "Prerequisites check failed"
        exit 1
    fi
    
    # Run scan
    if run_cameradar_scan; then
        log_success "Scan completed successfully"
        exit 0
    else
        log_error "Scan failed"
        exit 1
    fi
}

main "$@"

