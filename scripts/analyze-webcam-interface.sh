#!/usr/bin/env bash
set -euo pipefail

#######################################
# Webcam Interface Analysis Script
# Analyzes how the webcam hardware is interfaced and accessed by apollo process
#######################################

TARGET_IP="${1:-}"
USERNAME="${2:-root}"
PASSWORD="${3:-hellotuya}"
OUTPUT_FILE="${4:-webcam-interface-analysis-$(date +%Y%m%d_%H%M%S).txt}"

# Default credentials from README
if [[ "$USERNAME" == "user" ]] && [[ "$PASSWORD" == "hellotuya" ]]; then
    PASSWORD="user123"
fi

TELNET_PORT="${TELNET_PORT:-23}"
COMMAND_TIMEOUT="${COMMAND_TIMEOUT:-30}"

# Check if expect is available
if ! command -v expect &> /dev/null; then
    echo "[!] Error: expect is not installed"
    echo "[*] Install with: apt-get install expect  or  yum install expect"
    exit 1
fi

if [[ -z "$TARGET_IP" ]]; then
    echo "Usage: $0 <target-ip> [username] [password] [output-file]"
    echo ""
    echo "Example:"
    echo "  $0 10.0.0.227 root hellotuya"
    echo "  $0 10.0.0.227 user user123 webcam-analysis.txt"
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
    echo "[$timestamp] [$level] $message" | tee -a "$OUTPUT_FILE"
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
# Analysis Functions
#######################################
analyze_apollo_binary() {
    log_info "Analyzing apollo binary..."
    echo "" >> "$OUTPUT_FILE"
    echo "=== Apollo Binary Analysis ===" >> "$OUTPUT_FILE"
    
    # Get binary location and info
    local binary_info
    binary_info=$(execute_command "ls -lh /app/abin/apollo 2>/dev/null || echo 'Binary not found'" 10 || true)
    echo "Binary location and size:" >> "$OUTPUT_FILE"
    echo "$binary_info" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    # Get file type
    local file_type
    file_type=$(execute_command "file /app/abin/apollo 2>/dev/null || echo 'file command not available'" 10 || true)
    echo "File type:" >> "$OUTPUT_FILE"
    echo "$file_type" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    # Extract strings (limited to avoid huge output)
    log_info "Extracting strings from apollo binary..."
    local strings_output
    strings_output=$(execute_command "strings /app/abin/apollo 2>/dev/null | grep -E '(video|camera|v4l|uvc|mjpeg|h264|rtsp|stream)' | head -50 || echo 'strings command not available'" 30 || true)
    echo "Relevant strings (video/camera related):" >> "$OUTPUT_FILE"
    echo "$strings_output" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
}

analyze_video_devices() {
    log_info "Analyzing video devices..."
    echo "" >> "$OUTPUT_FILE"
    echo "=== Video Device Analysis ===" >> "$OUTPUT_FILE"
    
    # List /dev/video* devices
    local video_devices
    video_devices=$(execute_command "ls -la /dev/video* 2>/dev/null || echo 'No /dev/video* devices found'" 10 || true)
    echo "Video devices:" >> "$OUTPUT_FILE"
    echo "$video_devices" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    # Check V4L2 devices
    if echo "$video_devices" | grep -q "video"; then
        for device in $(echo "$video_devices" | grep -o "/dev/video[0-9]*" || true); do
            log_info "Checking V4L2 capabilities for $device..."
            local v4l2_info
            v4l2_info=$(execute_command "v4l2-ctl --device=$device --all 2>/dev/null || echo 'v4l2-ctl not available'" 15 || true)
            if [[ -n "$v4l2_info" ]] && ! echo "$v4l2_info" | grep -q "not available"; then
                echo "V4L2 info for $device:" >> "$OUTPUT_FILE"
                echo "$v4l2_info" >> "$OUTPUT_FILE"
                echo "" >> "$OUTPUT_FILE"
            fi
        done
    fi
}

analyze_apollo_process() {
    log_info "Analyzing apollo process..."
    echo "" >> "$OUTPUT_FILE"
    echo "=== Apollo Process Analysis ===" >> "$OUTPUT_FILE"
    
    # Find apollo process PID
    local apollo_pid
    apollo_pid=$(execute_command "ps | grep apollo | grep -v grep | awk '{print \$1}' | head -1" 10 || true)
    
    if [[ -z "$apollo_pid" ]] || [[ "$apollo_pid" == "COMMAND_TIMEOUT" ]] || [[ "$apollo_pid" == "CONNECTION_TIMEOUT" ]]; then
        log_warn "Apollo process not found or not running"
        echo "Apollo process not found" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        return
    fi
    
    log_success "Found apollo process with PID: $apollo_pid"
    echo "Apollo PID: $apollo_pid" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    # Get process command line
    local cmdline
    cmdline=$(execute_command "cat /proc/$apollo_pid/cmdline 2>/dev/null | tr '\0' ' ' || echo 'cmdline not accessible'" 10 || true)
    echo "Command line:" >> "$OUTPUT_FILE"
    echo "$cmdline" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    # Get process environment (limited)
    log_info "Getting process environment variables..."
    local environ
    environ=$(execute_command "cat /proc/$apollo_pid/environ 2>/dev/null | tr '\0' '\n' | grep -E '(VIDEO|CAMERA|V4L|UVC|RTSP|STREAM)' | head -20 || echo 'environ not accessible or no relevant vars'" 15 || true)
    echo "Relevant environment variables:" >> "$OUTPUT_FILE"
    echo "$environ" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    # Get open file descriptors
    log_info "Checking open file descriptors..."
    local open_files
    open_files=$(execute_command "ls -la /proc/$apollo_pid/fd/ 2>/dev/null | head -30 || echo 'fd directory not accessible'" 10 || true)
    echo "Open file descriptors (first 30):" >> "$OUTPUT_FILE"
    echo "$open_files" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    # Check for video device file descriptors
    local video_fds
    video_fds=$(execute_command "ls -la /proc/$apollo_pid/fd/ 2>/dev/null | grep video || echo 'No video device file descriptors found'" 10 || true)
    if echo "$video_fds" | grep -q video; then
        log_success "Apollo has open file descriptors to video devices"
        echo "Video device file descriptors:" >> "$OUTPUT_FILE"
        echo "$video_fds" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi
}

analyze_hardware_interface() {
    log_info "Analyzing hardware interface..."
    echo "" >> "$OUTPUT_FILE"
    echo "=== Hardware Interface Analysis ===" >> "$OUTPUT_FILE"
    
    # Check USB devices
    local usb_devices
    usb_devices=$(execute_command "lsusb 2>/dev/null || cat /proc/bus/usb/devices 2>/dev/null | head -50 || echo 'USB device info not available'" 15 || true)
    echo "USB devices:" >> "$OUTPUT_FILE"
    echo "$usb_devices" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    # Check for camera-related USB devices
    if echo "$usb_devices" | grep -qiE "(camera|video|uvc|webcam)"; then
        log_success "Found camera-related USB device"
    fi
    
    # Check kernel modules
    local modules
    modules=$(execute_command "lsmod 2>/dev/null | grep -E '(video|v4l|uvc|camera)' || echo 'No relevant kernel modules found or lsmod not available'" 10 || true)
    echo "Relevant kernel modules:" >> "$OUTPUT_FILE"
    echo "$modules" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    # Check dmesg for camera-related messages
    log_info "Checking kernel messages for camera devices..."
    local dmesg_camera
    dmesg_camera=$(execute_command "dmesg 2>/dev/null | grep -iE '(video|camera|uvc|v4l)' | tail -30 || echo 'dmesg not available or no camera messages'" 15 || true)
    echo "Kernel messages (camera related):" >> "$OUTPUT_FILE"
    echo "$dmesg_camera" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    # Check /sys/class/video4linux
    local v4l_class
    v4l_class=$(execute_command "ls -la /sys/class/video4linux/ 2>/dev/null || echo 'No /sys/class/video4linux directory'" 10 || true)
    echo "V4L2 class devices:" >> "$OUTPUT_FILE"
    echo "$v4l_class" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
}

analyze_camera_access() {
    log_info "Analyzing how apollo accesses camera..."
    echo "" >> "$OUTPUT_FILE"
    echo "=== Camera Access Method Analysis ===" >> "$OUTPUT_FILE"
    
    # Check if apollo uses direct device access
    local apollo_pid
    apollo_pid=$(execute_command "ps | grep apollo | grep -v grep | awk '{print \$1}' | head -1" 10 || true)
    
    if [[ -n "$apollo_pid" ]] && [[ "$apollo_pid" != "COMMAND_TIMEOUT" ]] && [[ "$apollo_pid" != "CONNECTION_TIMEOUT" ]]; then
        # Check memory maps for device files
        local mem_maps
        mem_maps=$(execute_command "cat /proc/$apollo_pid/maps 2>/dev/null | grep -E '(video|dev)' | head -20 || echo 'maps not accessible'" 10 || true)
        echo "Memory maps (device files):" >> "$OUTPUT_FILE"
        echo "$mem_maps" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi
    
    # Check for camera-related shared libraries
    local libs
    libs=$(execute_command "ldd /app/abin/apollo 2>/dev/null | grep -E '(video|camera|v4l)' || echo 'ldd not available or no camera libraries'" 10 || true)
    echo "Camera-related libraries:" >> "$OUTPUT_FILE"
    echo "$libs" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
}

#######################################
# Main Analysis Function
#######################################
main() {
    log_info "Starting webcam interface analysis on $TARGET_IP"
    echo "=== Webcam Interface Analysis Report ===" > "$OUTPUT_FILE"
    echo "Target: $TARGET_IP" >> "$OUTPUT_FILE"
    echo "Date: $(date)" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    analyze_apollo_binary
    analyze_video_devices
    analyze_apollo_process
    analyze_hardware_interface
    analyze_camera_access
    
    log_success "Analysis complete. Results saved to: $OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "=== Analysis Summary ===" >> "$OUTPUT_FILE"
    echo "Report generated: $(date)" >> "$OUTPUT_FILE"
}

main "$@"

