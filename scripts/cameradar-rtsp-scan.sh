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
EXECUTION_TIMEOUT="${6:-90}"  # Overall execution timeout in seconds (default: 90)
VERBOSE="${7:-true}"  # Verbose logging (default: true)

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
    echo "Usage: $0 <target-ip> [ports] [output-dir] [timeout-ms] [attack-interval-ms] [execution-timeout-sec]"
    echo ""
    echo "Examples:"
    echo "  $0 10.0.0.227"
    echo "  $0 10.0.0.227 554,8554"
    echo "  $0 10.0.0.227 554,8554 ./output 3000 100"
    echo "  $0 10.0.0.227 554,8554 ./output 3000 100 60"
    echo ""
    echo "Parameters:"
    echo "  target-ip           : Target IP address or network range (required)"
    echo "  ports               : Comma-separated RTSP ports (default: 554,5554,8554)"
    echo "  output-dir          : Output directory for results (default: current directory)"
    echo "  timeout-ms          : Request timeout in milliseconds (default: 2000)"
    echo "  attack-interval-ms  : Delay between attacks in milliseconds (default: 0)"
    echo "  execution-timeout-sec: Overall execution timeout in seconds (default: 90)"
    echo "  verbose             : Enable verbose logging (default: true)"
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
    log_info "Request Timeout: ${TIMEOUT}ms"
    log_info "Attack Interval: ${ATTACK_INTERVAL}ms"
    log_info "Execution Timeout: ${EXECUTION_TIMEOUT}s"
    log_info "Verbose: ${VERBOSE}"
    
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "=== VERBOSE MODE ENABLED ==="
        log_info "All cameradar output will be displayed in real-time"
    fi
    
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
    
    # Force verbose output
    if [[ "$VERBOSE" == "true" ]]; then
        docker_cmd+=("-e" "CAMERADAR_VERBOSE=true")
    fi
    
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
    
    # Add verbose flag for detailed output
    if [[ "$VERBOSE" == "true" ]]; then
        docker_cmd+=("-v" "--verbose")
    fi
    
    # Add debug flag for maximum verbosity
    if [[ "$VERBOSE" == "true" ]]; then
        docker_cmd+=("-d" "--debug")
    fi
    
    log_info "Executing cameradar (max ${EXECUTION_TIMEOUT}s)..."
    log_info "Command: ${docker_cmd[*]}"
    echo ""
    
    # Run cameradar and capture output with timeout
    local temp_json=$(mktemp)
    local temp_text=$(mktemp)
    
    # In verbose mode, show output in real-time
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "=== STARTING CAMERADAR EXECUTION ==="
        log_info "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        echo "--- Real-time cameradar output (stdout) ---"
        
        # Execute with JSON output and timeout, showing output in real-time
        local timeout_exit=0
        local start_time=$(date +%s)
        
        # Use tee to show output in real-time while also capturing it
        if timeout "${EXECUTION_TIMEOUT}" "${docker_cmd[@]}" 2>&1 | tee >(grep -v "^$" > "$temp_text") | tee "$temp_json"; then
            timeout_exit=0
        else
            timeout_exit=$?
            local end_time=$(date +%s)
            local elapsed=$((end_time - start_time))
            
            if [[ $timeout_exit -eq 124 ]]; then
                echo ""
                log_warn "=== TIMEOUT DETECTED ==="
                log_warn "Execution exceeded ${EXECUTION_TIMEOUT} seconds (elapsed: ${elapsed}s)"
                log_warn "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
                echo "TIMEOUT: Execution exceeded ${EXECUTION_TIMEOUT} seconds (elapsed: ${elapsed}s)" >> "$temp_text"
            else
                echo ""
                log_error "=== EXECUTION FAILED ==="
                log_error "Exit code: $timeout_exit"
                log_error "Elapsed time: ${elapsed}s"
                log_error "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
            fi
        fi
        
        echo ""
        echo "--- End of real-time output ---"
        log_info "=== CAMERADAR EXECUTION COMPLETE ==="
        log_info "Final timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    else
        # Non-verbose mode: execute silently
        local timeout_exit=0
        if timeout "${EXECUTION_TIMEOUT}" "${docker_cmd[@]}" > "$temp_json" 2> "$temp_text"; then
            timeout_exit=0
        else
            timeout_exit=$?
            if [[ $timeout_exit -eq 124 ]]; then
                log_warn "Cameradar execution timed out after ${EXECUTION_TIMEOUT} seconds"
                echo "TIMEOUT: Execution exceeded ${EXECUTION_TIMEOUT} seconds" >> "$temp_text"
            fi
        fi
    fi
    
    # Process output even if timeout occurred (may have partial results)
    if [[ -s "$temp_json" ]] || [[ $timeout_exit -eq 0 ]]; then
        # Copy JSON output
        if [[ -s "$temp_json" ]]; then
            cp "$temp_json" "$json_output"
            log_success "JSON output saved to: $json_output ($(wc -l < "$temp_json" | tr -d ' ') lines)"
        else
            log_warn "JSON output is empty"
            echo "{}" > "$json_output"
        fi
        
        # Generate human-readable text output
        {
            echo "=========================================="
            echo "Cameradar RTSP Penetration Test Results"
            echo "=========================================="
            echo "Target: $TARGET_IP"
            echo "Ports: $PORTS"
            echo "Scan Date: $(date)"
            echo "Request Timeout: ${TIMEOUT}ms"
            echo "Attack Interval: ${ATTACK_INTERVAL}ms"
            echo "Execution Timeout: ${EXECUTION_TIMEOUT}s"
            echo "Verbose Mode: ${VERBOSE}"
            echo ""
            
            if [[ $timeout_exit -eq 124 ]]; then
                echo "WARNING: Execution timed out after ${EXECUTION_TIMEOUT} seconds"
                echo ""
            fi
            
            echo "------------------------------------------"
            echo "Full Execution Output (stdout + stderr):"
            echo "------------------------------------------"
            if [[ -s "$temp_text" ]]; then
                cat "$temp_text"
            else
                echo "(No stderr output captured)"
            fi
            echo ""
            echo "------------------------------------------"
            echo "JSON Output (for parsing):"
            echo "------------------------------------------"
            if [[ -s "$temp_json" ]]; then
                cat "$temp_json"
            else
                echo "{}"
                echo "(No JSON output - execution may have been interrupted)"
            fi
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
        if [[ $timeout_exit -eq 124 ]]; then
            log_warn "Scan completed with timeout - check results for partial data"
            return 2  # Timeout exit code
        else
            return 0
        fi
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
            if [[ $timeout_exit -eq 124 ]]; then
                echo "ERROR: Execution timed out after ${EXECUTION_TIMEOUT} seconds"
            else
                echo "Error occurred during execution:"
            fi
            echo ""
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

