#!/usr/bin/env bash
set -euo pipefail

#######################################
# Testing and Validation Script
# Verifies local-only mode setup is working correctly
#######################################

TARGET_IP="${1:-}"
USERNAME="${2:-root}"
PASSWORD="${3:-hellotuya}"
RTSP_STREAM_PATH="${4:-/stream1}"
RTSP_PORT="${5:-8554}"

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
    echo "Usage: $0 <target-ip> [username] [password] [rtsp-stream-path] [rtsp-port]"
    echo ""
    echo "Example:"
    echo "  $0 10.0.0.227 root hellotuya /stream1 8554"
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
# Test Functions
#######################################
test_rtsp_stream() {
    log_info "Testing RTSP stream accessibility..."
    
    local rtsp_url="rtsp://${TARGET_IP}:${RTSP_PORT}${RTSP_STREAM_PATH}"
    
    # Try RTSP OPTIONS request
    local rtsp_response
    rtsp_response=$(echo -e "OPTIONS ${rtsp_url} RTSP/1.0\r\nCSeq: 1\r\nUser-Agent: curl/8.0\r\n\r\n" | \
        nc -w 2 "$TARGET_IP" "$RTSP_PORT" 2>/dev/null || true)
    
    if echo "$rtsp_response" | grep -qi "RTSP/1.0.*200\|OK"; then
        log_success "RTSP stream is accessible: $rtsp_url"
        return 0
    else
        log_error "RTSP stream test failed: $rtsp_url"
        return 1
    fi
}

test_cloud_connections() {
    log_info "Testing for cloud connections..."
    
    local connections
    connections=$(execute_command "netstat -anp 2>/dev/null | grep -E 'ESTABLISHED|CONNECT' || ss -anp 2>/dev/null | grep -E 'ESTABLISHED|CONNECT'" 20 || true)
    
    local cloud_conns
    cloud_conns=$(echo "$connections" | \
        grep -E "52\.42\.98\.25" || true)
    
    if [[ -z "$cloud_conns" ]]; then
        log_success "No cloud connections detected"
        return 0
    else
        log_error "Cloud connections still active:"
        echo "$cloud_conns"
        return 1
    fi
}

test_firewall_rules() {
    log_info "Testing firewall rules..."
    
    local iptables_output
    iptables_output=$(execute_command "iptables -L OUTPUT -n -v 2>/dev/null" 15 || true)
    
    if echo "$iptables_output" | grep -q "52.42.98.25"; then
        log_success "Firewall rules blocking cloud IPs are present"
        return 0
    else
        log_warn "Firewall rules for cloud blocking not found"
        return 1
    fi
}

test_dns_blocking() {
    log_info "Testing DNS blocking..."
    
    local resolv_content
    resolv_content=$(execute_command "cat /etc/resolv.conf 2>/dev/null || echo 'not found'" 10 || true)
    
    local external_dns
    external_dns=$(echo "$resolv_content" | \
        grep nameserver | \
        awk '{print $2}' | \
        grep -vE "^127\.|^10\.|^192\.168\.|^172\.(1[6-9]|2[0-9]|3[0-1])\." || true)
    
    if [[ -z "$external_dns" ]]; then
        log_success "No external DNS servers found"
        return 0
    else
        log_warn "External DNS servers still present:"
        echo "$external_dns"
        return 1
    fi
}

test_monitoring() {
    log_info "Testing monitoring tools..."
    
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    local scripts=(
        "monitor-connections.sh"
        "analyze-connections.sh"
        "connection-alerts.sh"
    )
    
    local all_ok=true
    for script in "${scripts[@]}"; do
        if [[ -f "$script_dir/$script" ]] && [[ -x "$script_dir/$script" ]]; then
            log_success "Monitoring script available: $script"
        else
            log_error "Monitoring script not found or not executable: $script"
            all_ok=false
        fi
    done
    
    if [[ "$all_ok" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

test_rollback() {
    log_info "Testing rollback mechanism..."
    
    # Check if rollback scripts exist
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    if [[ -f "$script_dir/rollback-local-only.sh" ]]; then
        log_success "Rollback script exists"
        return 0
    else
        log_warn "Rollback script not found"
        return 1
    fi
}

#######################################
# Main Test Function
#######################################
main() {
    log_info "Starting local-only mode validation tests for $TARGET_IP"
    echo ""
    
    local tests_passed=0
    local tests_failed=0
    
    # Test RTSP stream
    if test_rtsp_stream; then
        ((tests_passed++)) || true
    else
        ((tests_failed++)) || true
    fi
    
    echo ""
    
    # Test cloud connections
    if test_cloud_connections; then
        ((tests_passed++)) || true
    else
        ((tests_failed++)) || true
    fi
    
    echo ""
    
    # Test firewall rules
    if test_firewall_rules; then
        ((tests_passed++)) || true
    else
        ((tests_failed++)) || true
    fi
    
    echo ""
    
    # Test DNS blocking
    if test_dns_blocking; then
        ((tests_passed++)) || true
    else
        ((tests_failed++)) || true
    fi
    
    echo ""
    
    # Test monitoring
    if test_monitoring; then
        ((tests_passed++)) || true
    else
        ((tests_failed++)) || true
    fi
    
    echo ""
    
    # Test rollback
    if test_rollback; then
        ((tests_passed++)) || true
    else
        ((tests_failed++)) || true
    fi
    
    echo ""
    echo "=== Test Summary ==="
    echo "Tests passed: $tests_passed"
    echo "Tests failed: $tests_failed"
    echo ""
    
    if [[ $tests_failed -eq 0 ]]; then
        log_success "All tests passed! Local-only mode is working correctly."
        return 0
    else
        log_error "Some tests failed. Please review the output above."
        return 1
    fi
}

main "$@"

