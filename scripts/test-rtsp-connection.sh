#!/usr/bin/env bash
set -euo pipefail

#######################################
# RTSP Connection Test Script
# Tests RTSP stream connectivity and displays stream information
#######################################

RTSP_URL="${1:-}"
TIMEOUT="${2:-10}"

if [[ -z "$RTSP_URL" ]]; then
    echo "Usage: $0 <rtsp-url> [timeout-seconds]"
    echo ""
    echo "Example:"
    echo "  $0 rtsp://10.0.0.227:8554/stream1"
    echo "  $0 rtsp://10.0.0.227:8554/stream1 15"
    echo ""
    echo "This script tests RTSP connectivity using:"
    echo "  1. ffprobe (if available) - shows detailed stream info"
    echo "  2. ffmpeg (if available) - attempts to read stream"
    echo "  3. curl - basic RTSP OPTIONS request"
    echo "  4. nc/netcat - manual RTSP DESCRIBE request"
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
# Test Functions
#######################################
test_with_ffprobe() {
    if ! command -v ffprobe &> /dev/null; then
        return 1
    fi
    
    log_info "Testing RTSP connection with ffprobe..."
    echo ""
    
    # Get stream information
    local probe_output
    probe_output=$(timeout "$TIMEOUT" ffprobe -v error \
        -show_entries stream=codec_name,codec_type,width,height,r_frame_rate,bit_rate \
        -show_entries format=format_name,duration,size,bit_rate \
        -of default=noprint_wrappers=1:nokey=0 \
        "$RTSP_URL" 2>&1)
    
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]] && echo "$probe_output" | grep -q "codec_name"; then
        log_success "RTSP stream is accessible and readable!"
        echo ""
        echo "=== Stream Information ==="
        echo "$probe_output" | grep -E "(codec_name|codec_type|width|height|r_frame_rate|bit_rate|format_name|duration|size)" | head -20
        echo ""
        
        # Try to get a frame to prove it's working
        log_info "Attempting to capture a frame..."
        local frame_output
        frame_output=$(timeout "$TIMEOUT" ffmpeg -i "$RTSP_URL" -vframes 1 -f image2 -y /tmp/rtsp_test_frame.jpg 2>&1 || true)
        
        if [[ -f /tmp/rtsp_test_frame.jpg ]]; then
            local frame_size
            frame_size=$(stat -f%z /tmp/rtsp_test_frame.jpg 2>/dev/null || stat -c%s /tmp/rtsp_test_frame.jpg 2>/dev/null || echo "unknown")
            log_success "Frame captured successfully! (Size: $frame_size bytes)"
            log_info "Frame saved to: /tmp/rtsp_test_frame.jpg"
            return 0
        else
            log_warn "Could not capture frame, but stream is accessible"
            return 0
        fi
    else
        log_error "ffprobe failed or stream not accessible"
        echo "$probe_output" | tail -10
        return 1
    fi
}

test_with_ffmpeg() {
    if ! command -v ffmpeg &> /dev/null; then
        return 1
    fi
    
    log_info "Testing RTSP connection with ffmpeg..."
    echo ""
    
    # Try to read stream for a few seconds
    local ffmpeg_output
    ffmpeg_output=$(timeout "$TIMEOUT" ffmpeg -i "$RTSP_URL" -t 2 -f null - 2>&1 || true)
    
    if echo "$ffmpeg_output" | grep -qiE "Stream.*Video|Stream.*Audio|Duration"; then
        log_success "ffmpeg can read the RTSP stream!"
        echo ""
        echo "=== Stream Details ==="
        echo "$ffmpeg_output" | grep -E "Stream|Duration|Input" | head -10
        echo ""
        return 0
    else
        log_warn "ffmpeg test inconclusive"
        return 1
    fi
}

test_with_curl() {
    if ! command -v curl &> /dev/null; then
        return 1
    fi
    
    log_info "Testing RTSP connection with curl (OPTIONS request)..."
    echo ""
    
    # Extract host and port from URL
    local host_port
    host_port=$(echo "$RTSP_URL" | sed -E 's|rtsp://([^/]+).*|\1|')
    
    # Send RTSP OPTIONS request
    local rtsp_response
    rtsp_response=$(curl -s --max-time 5 \
        -X OPTIONS \
        -H "User-Agent: curl/8.0" \
        -H "CSeq: 1" \
        "$RTSP_URL" 2>&1 || true)
    
    if echo "$rtsp_response" | grep -qiE "RTSP/1.0.*200|OK|Public"; then
        log_success "RTSP server responds to OPTIONS request!"
        echo ""
        echo "=== RTSP Response ==="
        echo "$rtsp_response" | head -10
        echo ""
        return 0
    else
        log_warn "curl test inconclusive or server doesn't support OPTIONS"
        return 1
    fi
}

test_with_nc() {
    if ! command -v nc &> /dev/null && ! command -v netcat &> /dev/null; then
        return 1
    fi
    
    local nc_cmd
    nc_cmd=$(command -v nc 2>/dev/null || command -v netcat 2>/dev/null || echo "")
    
    if [[ -z "$nc_cmd" ]]; then
        return 1
    fi
    
    log_info "Testing RTSP connection with netcat (DESCRIBE request)..."
    echo ""
    
    # Extract host and port from URL
    local host_port
    host_port=$(echo "$RTSP_URL" | sed -E 's|rtsp://([^/]+).*|\1|')
    local host
    host=$(echo "$host_port" | cut -d: -f1)
    local port
    port=$(echo "$host_port" | cut -d: -f2)
    port="${port:-554}"  # Default RTSP port
    
    # Extract path
    local path
    path=$(echo "$RTSP_URL" | sed -E 's|rtsp://[^/]+(.*)|\1|')
    path="${path:-/}"
    
    # Send RTSP DESCRIBE request
    local describe_request
    describe_request=$(cat <<EOF
DESCRIBE ${RTSP_URL} RTSP/1.0
CSeq: 1
User-Agent: curl/8.0
Accept: application/sdp

EOF
)
    
    local rtsp_response
    rtsp_response=$(echo -e "$describe_request" | timeout 5 "$nc_cmd" -w 2 "$host" "$port" 2>/dev/null || true)
    
    if echo "$rtsp_response" | grep -qiE "RTSP/1.0.*200|sdp|m=video|m=audio"; then
        log_success "RTSP server responds to DESCRIBE request!"
        echo ""
        echo "=== RTSP DESCRIBE Response ==="
        echo "$rtsp_response" | head -30
        echo ""
        
        # Extract SDP information
        if echo "$rtsp_response" | grep -q "m=video"; then
            log_info "Video stream detected in SDP"
            echo "$rtsp_response" | grep -E "m=video|a=rtpmap|a=fmtp" | head -5
        fi
        if echo "$rtsp_response" | grep -q "m=audio"; then
            log_info "Audio stream detected in SDP"
            echo "$rtsp_response" | grep -E "m=audio|a=rtpmap|a=fmtp" | head -5
        fi
        echo ""
        return 0
    else
        log_warn "netcat test inconclusive"
        return 1
    fi
}

test_with_vlc() {
    if ! command -v vlc &> /dev/null && ! command -v cvlc &> /dev/null; then
        return 1
    fi
    
    local vlc_cmd
    vlc_cmd=$(command -v cvlc 2>/dev/null || command -v vlc 2>/dev/null || echo "")
    
    if [[ -z "$vlc_cmd" ]]; then
        return 1
    fi
    
    log_info "Testing RTSP connection with VLC..."
    echo ""
    log_info "Note: VLC test requires GUI or headless mode"
    log_info "Running brief connection test..."
    
    # Try to open stream for a few seconds (headless)
    local vlc_output
    vlc_output=$("$vlc_cmd" --intf dummy --run-time=2 "$RTSP_URL" vlc://quit 2>&1 || true)
    
    if echo "$vlc_output" | grep -qiE "streaming|playing|sout"; then
        log_success "VLC can access RTSP stream!"
        return 0
    else
        log_warn "VLC test inconclusive"
        return 1
    fi
}

#######################################
# Main Test Function
#######################################
main() {
    log_info "Testing RTSP connection: $RTSP_URL"
    log_info "Timeout: ${TIMEOUT} seconds"
    echo ""
    
    local success_count=0
    local test_count=0
    
    # Test with ffprobe (best option)
    if test_with_ffprobe; then
        ((success_count++)) || true
        ((test_count++)) || true
        echo ""
        log_success "✓ RTSP connection verified with ffprobe!"
        return 0
    else
        ((test_count++)) || true
    fi
    
    echo ""
    
    # Test with ffmpeg
    if test_with_ffmpeg; then
        ((success_count++)) || true
        ((test_count++)) || true
        echo ""
        log_success "✓ RTSP connection verified with ffmpeg!"
        return 0
    else
        ((test_count++)) || true
    fi
    
    echo ""
    
    # Test with curl
    if test_with_curl; then
        ((success_count++)) || true
        ((test_count++)) || true
    else
        ((test_count++)) || true
    fi
    
    echo ""
    
    # Test with netcat
    if test_with_nc; then
        ((success_count++)) || true
        ((test_count++)) || true
    else
        ((test_count++)) || true
    fi
    
    echo ""
    
    # Summary
    echo "=== Test Summary ==="
    echo "Successful tests: $success_count / $test_count"
    echo ""
    
    if [[ $success_count -gt 0 ]]; then
        log_success "RTSP connection is working! ($success_count test(s) passed)"
        return 0
    else
        log_error "RTSP connection test failed (all $test_count tests failed)"
        log_info "Possible issues:"
        log_info "  - RTSP URL is incorrect"
        log_info "  - RTSP server is not running"
        log_info "  - Network connectivity issues"
        log_info "  - Authentication required"
        log_info "  - Firewall blocking connection"
        return 1
    fi
}

main "$@"

