#!/usr/bin/env bash
set -euo pipefail

#######################################
# Apollo Replacement Script
# Replaces apollo process with local RTSP server
#######################################

TARGET_IP="${1:-}"
USERNAME="${2:-root}"
PASSWORD="${3:-hellotuya}"
BACKUP_DIR="${4:-/tmp/apollo-backup-$(date +%Y%m%d_%H%M%S)}"

# Default credentials from README
if [[ "$USERNAME" == "user" ]] && [[ "$PASSWORD" == "hellotuya" ]]; then
    PASSWORD="user123"
fi

TELNET_PORT="${TELNET_PORT:-23}"
COMMAND_TIMEOUT="${COMMAND_TIMEOUT:-30}"
APOLLO_BINARY="/app/abin/apollo"
APOLLO_BACKUP="${BACKUP_DIR}/apollo.original"
RTSP_SERVER="/app/abin/local-rtsp-server"
RTSP_PORT="8554"

# Check if expect is available
if ! command -v expect &> /dev/null; then
    echo "[!] Error: expect is not installed"
    echo "[*] Install with: apt-get install expect  or  yum install expect"
    exit 1
fi

if [[ -z "$TARGET_IP" ]]; then
    echo "Usage: $0 <target-ip> [username] [password] [backup-dir]"
    echo ""
    echo "Example:"
    echo "  $0 10.0.0.227 root hellotuya"
    echo ""
    echo "WARNING: This script will stop apollo and replace it with local RTSP server."
    echo "         A backup will be created before replacement."
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
# Replacement Functions
#######################################
backup_apollo() {
    log_info "Backing up apollo binary..."
    
    # Create backup directory
    execute_command "mkdir -p $BACKUP_DIR" 10 || true
    
    # Check if apollo exists
    local apollo_exists
    apollo_exists=$(execute_command "test -f $APOLLO_BINARY && echo 'exists' || echo 'not found'" 10 || true)
    
    if [[ "$apollo_exists" != "exists" ]]; then
        log_error "Apollo binary not found at $APOLLO_BINARY"
        return 1
    fi
    
    # Copy apollo to backup
    local backup_result
    backup_result=$(execute_command "cp $APOLLO_BINARY $APOLLO_BACKUP && echo 'backup_ok' || echo 'backup_failed'" 15 || true)
    
    if [[ "$backup_result" == *"backup_ok"* ]]; then
        log_success "Apollo binary backed up to: $APOLLO_BACKUP"
        return 0
    else
        log_error "Failed to backup apollo binary"
        return 1
    fi
}

stop_apollo() {
    log_info "Stopping apollo process..."
    
    # Find apollo process
    local apollo_pid
    apollo_pid=$(execute_command "ps | grep apollo | grep -v grep | awk '{print \$1}' | head -1" 10 || true)
    
    if [[ -z "$apollo_pid" ]] || [[ "$apollo_pid" == "COMMAND_TIMEOUT" ]] || [[ "$apollo_pid" == "CONNECTION_TIMEOUT" ]]; then
        log_warn "Apollo process not found or not running"
        return 0
    fi
    
    log_info "Found apollo process with PID: $apollo_pid"
    
    # Stop apollo gracefully
    local stop_result
    stop_result=$(execute_command "kill $apollo_pid 2>/dev/null && sleep 2 && ps | grep $apollo_pid | grep -v grep || echo 'stopped'" 15 || true)
    
    if echo "$stop_result" | grep -q "stopped"; then
        log_success "Apollo process stopped"
        return 0
    else
        # Try force kill
        log_warn "Graceful stop failed, trying force kill..."
        execute_command "killall apollo 2>/dev/null || kill -9 $apollo_pid 2>/dev/null || true" 10 || true
        sleep 2
        
        local still_running
        still_running=$(execute_command "ps | grep apollo | grep -v grep || echo 'stopped'" 10 || true)
        
        if echo "$still_running" | grep -q "stopped"; then
            log_success "Apollo process force stopped"
            return 0
        else
            log_error "Failed to stop apollo process"
            return 1
        fi
    fi
}

verify_rtsp_server() {
    log_info "Verifying local RTSP server is available..."
    
    local rtsp_exists
    rtsp_exists=$(execute_command "test -f $RTSP_SERVER && echo 'exists' || echo 'not found'" 10 || true)
    
    if [[ "$rtsp_exists" != "exists" ]]; then
        log_error "Local RTSP server not found at $RTSP_SERVER"
        log_error "Please install and configure the RTSP server first using setup-local-rtsp.sh"
        return 1
    fi
    
    log_success "Local RTSP server found"
    return 0
}

start_local_rtsp() {
    log_info "Starting local RTSP server..."
    
    # Check if RTSP server is already running
    local rtsp_running
    rtsp_running=$(execute_command "ps | grep local-rtsp-server | grep -v grep || echo 'not running'" 10 || true)
    
    if echo "$rtsp_running" | grep -qv "not running"; then
        log_warn "Local RTSP server is already running"
        return 0
    fi
    
    # Start RTSP server
    local start_result
    start_result=$(execute_command "$RTSP_SERVER -port $RTSP_PORT > /dev/null 2>&1 &" 10 || true)
    
    sleep 2
    
    # Verify it's running
    local verify_running
    verify_running=$(execute_command "ps | grep local-rtsp-server | grep -v grep || echo 'not running'" 10 || true)
    
    if echo "$verify_running" | grep -qv "not running"; then
        log_success "Local RTSP server started"
        return 0
    else
        log_error "Failed to start local RTSP server"
        return 1
    fi
}

verify_stream() {
    log_info "Verifying RTSP stream is accessible..."
    
    local rtsp_url="rtsp://${TARGET_IP}:${RTSP_PORT}/stream1"
    
    # Try RTSP OPTIONS request
    local rtsp_response
    rtsp_response=$(echo -e "OPTIONS ${rtsp_url} RTSP/1.0\r\nCSeq: 1\r\nUser-Agent: curl/8.0\r\n\r\n" | \
        nc -w 2 "$TARGET_IP" "$RTSP_PORT" 2>/dev/null || true)
    
    if echo "$rtsp_response" | grep -qi "RTSP/1.0.*200\|OK"; then
        log_success "RTSP stream is accessible: $rtsp_url"
        return 0
    else
        log_warn "RTSP stream verification failed (server may still be starting)"
        return 1
    fi
}

create_rollback_script() {
    log_info "Creating rollback script..."
    
    local rollback_script
    rollback_script=$(cat <<ROLLBACK
#!/bin/sh
# Rollback script to restore apollo
# Usage: ./rollback-apollo.sh

# Stop local RTSP server
killall local-rtsp-server 2>/dev/null || true

# Restore apollo binary
if [ -f "$APOLLO_BACKUP" ]; then
    cp $APOLLO_BACKUP $APOLLO_BINARY
    chmod +x $APOLLO_BINARY
fi

# Restart apollo (if startup script exists)
if [ -f /app/start.sh ]; then
    /app/start.sh &
fi
ROLLBACK
)
    
    log_info "Rollback script created (save this for future use)"
    echo "$rollback_script"
}

#######################################
# Main Replacement Function
#######################################
main() {
    log_info "Starting apollo replacement process for $TARGET_IP"
    
    # Pre-flight checks
    if ! verify_rtsp_server; then
        log_error "Pre-flight check failed. Cannot proceed."
        exit 1
    fi
    
    # Backup apollo
    if ! backup_apollo; then
        log_error "Backup failed. Cannot proceed without backup."
        exit 1
    fi
    
    # Stop apollo
    if ! stop_apollo; then
        log_error "Failed to stop apollo. Cannot proceed."
        exit 1
    fi
    
    # Start local RTSP server
    if ! start_local_rtsp; then
        log_error "Failed to start local RTSP server."
        log_error "You may need to restore apollo using the backup at: $APOLLO_BACKUP"
        exit 1
    fi
    
    # Verify stream
    verify_stream
    
    # Create rollback script
    echo ""
    echo "=== Rollback Script ==="
    create_rollback_script
    echo ""
    
    log_success "Apollo replacement complete!"
    log_info "Backup location: $APOLLO_BACKUP"
    log_info "RTSP stream: rtsp://${TARGET_IP}:${RTSP_PORT}/stream1"
}

main "$@"

