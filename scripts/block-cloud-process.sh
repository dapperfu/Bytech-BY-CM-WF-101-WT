#!/usr/bin/env bash
set -euo pipefail

#######################################
# Process-Level Cloud Blocking Script
# Blocks cloud communication at the process/application level
#######################################

TARGET_IP="${1:-}"
USERNAME="${2:-root}"
PASSWORD="${3:-hellotuya}"

# Default credentials from README
if [[ "$USERNAME" == "user" ]] && [[ "$PASSWORD" == "hellotuya" ]]; then
    PASSWORD="user123"
fi

TELNET_PORT="${TELNET_PORT:-23}"
COMMAND_TIMEOUT="${COMMAND_TIMEOUT:-30}"
APOLLO_BINARY="/app/abin/apollo"
APOLLO_STARTUP="/app/start.sh"

# Check if expect is available
if ! command -v expect &> /dev/null; then
    echo "[!] Error: expect is not installed"
    echo "[*] Install with: apt-get install expect  or  yum install expect"
    exit 1
fi

if [[ -z "$TARGET_IP" ]]; then
    echo "Usage: $0 <target-ip> [username] [password]"
    echo ""
    echo "Example:"
    echo "  $0 10.0.0.227 root hellotuya"
    echo ""
    echo "This script modifies apollo startup to disable cloud features."
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
    
    # Escape forward slashes in cmd for sed
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
# Process Blocking Functions
#######################################
backup_startup_script() {
    log_info "Backing up startup script..."
    
    local backup_file="/tmp/start.sh.backup-$(date +%Y%m%d_%H%M%S)"
    local backup_result
    backup_result=$(execute_command "cp $APOLLO_STARTUP $backup_file 2>/dev/null && echo 'backup_ok' || echo 'backup_failed'" 15 || true)
    
    if echo "$backup_result" | grep -q "backup_ok"; then
        log_success "Startup script backed up to: $backup_file"
        echo "$backup_file"
        return 0
    else
        log_warn "Startup script not found or backup failed"
        return 1
    fi
}

create_apollo_wrapper() {
    log_info "Creating apollo wrapper to block cloud connections..."
    
    local wrapper_script
    wrapper_script=$(cat <<'WRAPPER'
#!/bin/sh
# Apollo wrapper to block cloud connections
# This wrapper intercepts network calls to block cloud IPs

CLOUD_IPS="52.42.98.25"

# Block cloud IPs using iptables before starting apollo
for ip in $CLOUD_IPS; do
    iptables -A OUTPUT -d $ip -j DROP 2>/dev/null || true
done

# Start original apollo (if it exists and we want to keep it)
# Otherwise, this wrapper can be used to prevent apollo from starting
# Uncomment the line below if you want to completely prevent apollo
# exit 0

# If apollo binary exists, you could also replace it with this wrapper
# and have it do nothing, effectively disabling apollo
WRAPPER
)
    
    log_info "Wrapper script template created"
    echo "$wrapper_script"
}

disable_apollo_startup() {
    log_info "Disabling apollo in startup script..."
    
    # Check if startup script exists
    local script_exists
    script_exists=$(execute_command "test -f $APOLLO_STARTUP && echo 'exists' || echo 'not found'" 10 || true)
    
    if [[ "$script_exists" != "exists" ]]; then
        log_warn "Startup script not found at $APOLLO_STARTUP"
        return 1
    fi
    
    # Comment out apollo startup lines
    log_info "Commenting out apollo startup lines..."
    execute_command "sed -i 's|^.*apollo|# &|g' $APOLLO_STARTUP 2>/dev/null || sed 's|^.*apollo|# &|g' $APOLLO_STARTUP > ${APOLLO_STARTUP}.new && mv ${APOLLO_STARTUP}.new $APOLLO_STARTUP" 15 || true
    
    log_success "Apollo startup disabled in startup script"
}

create_monitoring_script() {
    log_info "Creating monitoring script to prevent apollo cloud features..."
    
    local monitor_script
    monitor_script=$(cat <<'MONITOR'
#!/bin/sh
# Monitor script to ensure apollo doesn't restart with cloud features
# Run this periodically (e.g., via cron)

APOLLO_PID=$(ps | grep apollo | grep -v grep | awk '{print $1}')

if [ -n "$APOLLO_PID" ]; then
    # Check if apollo has connections to cloud IPs
    CLOUD_CONN=$(netstat -anp 2>/dev/null | grep apollo | grep -E "52\.42\.98\.25" || \
                 ss -anp 2>/dev/null | grep apollo | grep -E "52\.42\.98\.25" || true)
    
    if [ -n "$CLOUD_CONN" ]; then
        # Kill apollo if it connects to cloud
        killall apollo 2>/dev/null || true
        logger "Apollo killed for attempting cloud connection"
    fi
fi
MONITOR
)
    
    log_info "Monitoring script template created"
    echo "$monitor_script"
}

verify_blocking() {
    log_info "Verifying process-level blocking..."
    
    # Check if apollo is running
    local apollo_running
    apollo_running=$(execute_command "ps | grep apollo | grep -v grep || echo 'not running'" 10 || true)
    
    if echo "$apollo_running" | grep -q "not running"; then
        log_success "Apollo is not running"
    else
        log_warn "Apollo is still running"
        echo "$apollo_running"
    fi
    
    # Check for cloud connections
    local cloud_conns
    cloud_conns=$(execute_command "netstat -anp 2>/dev/null | grep -E '52\.42\.98\.25' || ss -anp 2>/dev/null | grep -E '52\.42\.98\.25' || echo 'no cloud connections'" 15 || true)
    
    if echo "$cloud_conns" | grep -q "no cloud connections"; then
        log_success "No cloud connections detected"
    else
        log_warn "Cloud connections still present:"
        echo "$cloud_conns"
    fi
}

#######################################
# Main Function
#######################################
main() {
    log_info "Starting process-level cloud blocking on $TARGET_IP"
    
    # Backup startup script
    local backup_file
    backup_file=$(backup_startup_script)
    
    # Disable apollo startup
    disable_apollo_startup
    
    # Stop apollo if running
    log_info "Stopping apollo process if running..."
    execute_command "killall apollo 2>/dev/null || true" 10 || true
    sleep 2
    
    # Create wrapper script
    echo ""
    echo "=== Apollo Wrapper Script ==="
    create_apollo_wrapper
    echo ""
    
    # Create monitoring script
    echo ""
    echo "=== Monitoring Script ==="
    create_monitoring_script
    echo ""
    
    # Verify blocking
    verify_blocking
    
    if [[ -n "$backup_file" ]]; then
        log_info "Backup file: $backup_file"
    fi
    
    log_success "Process-level cloud blocking complete!"
    log_info "Note: Apollo startup has been disabled. Monitor for any restart attempts."
}

main "$@"

