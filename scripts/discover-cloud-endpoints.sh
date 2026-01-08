#!/usr/bin/env bash
set -euo pipefail

#######################################
# Cloud Endpoint Discovery Script
# Discovers all cloud server IPs and domains the webcam connects to
#######################################

TARGET_IP="${1:-}"
USERNAME="${2:-root}"
PASSWORD="${3:-hellotuya}"
OUTPUT_FILE="${4:-cloud-endpoints-$(date +%Y%m%d_%H%M%S).txt}"

# Default credentials from README
if [[ "$USERNAME" == "user" ]] && [[ "$PASSWORD" == "hellotuya" ]]; then
    PASSWORD="user123"
fi

TELNET_PORT="${TELNET_PORT:-23}"
COMMAND_TIMEOUT="${COMMAND_TIMEOUT:-30}"
LOCAL_NETWORK="${LOCAL_NETWORK:-10.0.0.0/24}"

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
    echo "  $0 10.0.0.227 user user123 cloud-endpoints.txt"
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
# IP Address Validation
#######################################
is_local_ip() {
    local ip="$1"
    # Simple check for 10.x.x.x, 192.168.x.x, 172.16-31.x.x
    if echo "$ip" | grep -qE "^10\.|^192\.168\.|^172\.(1[6-9]|2[0-9]|3[0-1])\."; then
        return 0
    fi
    return 1
}

is_valid_ip() {
    local ip="$1"
    echo "$ip" | grep -qE "^([0-9]{1,3}\.){3}[0-9]{1,3}$"
}

#######################################
# Discovery Functions
#######################################
discover_active_connections() {
    log_info "Discovering active network connections..."
    echo "" >> "$OUTPUT_FILE"
    echo "=== Active Network Connections ===" >> "$OUTPUT_FILE"
    
    # Get all active connections
    local connections
    connections=$(execute_command "netstat -anp 2>/dev/null || ss -anp 2>/dev/null" 15 || true)
    echo "$connections" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    # Extract remote IPs (non-local)
    log_info "Extracting cloud endpoints from connections..."
    local cloud_ips
    cloud_ips=$(echo "$connections" | \
        grep -E "ESTABLISHED|CONNECT" | \
        awk '{print $5}' | \
        sed 's/:[0-9]*$//' | \
        sort -u | \
        grep -vE "^127\.|^::1|^10\.|^192\.168\.|^172\.(1[6-9]|2[0-9]|3[0-1])\." || true)
    
    if [[ -n "$cloud_ips" ]]; then
        echo "=== Cloud IP Addresses from Active Connections ===" >> "$OUTPUT_FILE"
        echo "$cloud_ips" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi
    
    # Extract ports for cloud IPs
    local cloud_connections
    cloud_connections=$(echo "$connections" | \
        grep -E "ESTABLISHED|CONNECT" | \
        awk '{print $5}' | \
        grep -vE "^127\.|^::1|^10\.|^192\.168\.|^172\.(1[6-9]|2[0-9]|3[0-1])\." || true)
    
    if [[ -n "$cloud_connections" ]]; then
        echo "=== Cloud Connections (IP:Port) ===" >> "$OUTPUT_FILE"
        echo "$cloud_connections" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi
}

discover_dns_servers() {
    log_info "Discovering DNS servers..."
    echo "" >> "$OUTPUT_FILE"
    echo "=== DNS Servers ===" >> "$OUTPUT_FILE"
    
    local dns_servers
    dns_servers=$(execute_command "cat /etc/resolv.conf 2>/dev/null | grep nameserver || echo 'resolv.conf not found'" 10 || true)
    echo "$dns_servers" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    # Extract external DNS servers
    local external_dns
    external_dns=$(echo "$dns_servers" | \
        grep nameserver | \
        awk '{print $2}' | \
        grep -vE "^127\.|^10\.|^192\.168\.|^172\.(1[6-9]|2[0-9]|3[0-1])\." || true)
    
    if [[ -n "$external_dns" ]]; then
        echo "=== External DNS Servers ===" >> "$OUTPUT_FILE"
        echo "$external_dns" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi
}

discover_process_env() {
    log_info "Discovering cloud endpoints from process environment..."
    echo "" >> "$OUTPUT_FILE"
    echo "=== Process Environment Variables ===" >> "$OUTPUT_FILE"
    
    # Find apollo process
    local apollo_pid
    apollo_pid=$(execute_command "ps | grep apollo | grep -v grep | awk '{print \$1}' | head -1" 10 || true)
    
    if [[ -n "$apollo_pid" ]] && [[ "$apollo_pid" != "COMMAND_TIMEOUT" ]] && [[ "$apollo_pid" != "CONNECTION_TIMEOUT" ]]; then
        local environ
        environ=$(execute_command "cat /proc/$apollo_pid/environ 2>/dev/null | tr '\0' '\n' | grep -E '(HOST|SERVER|URL|ENDPOINT|MQTT|CLOUD)' || echo 'No relevant environment variables'" 15 || true)
        echo "Apollo process environment (cloud-related):" >> "$OUTPUT_FILE"
        echo "$environ" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        
        # Extract IPs and domains from environment
        local env_endpoints
        env_endpoints=$(echo "$environ" | \
            grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}|[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" | \
            sort -u || true)
        
        if [[ -n "$env_endpoints" ]]; then
            echo "=== Endpoints from Environment Variables ===" >> "$OUTPUT_FILE"
            echo "$env_endpoints" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
        fi
    fi
}

discover_config_files() {
    log_info "Searching configuration files for cloud endpoints..."
    echo "" >> "$OUTPUT_FILE"
    echo "=== Configuration Files Analysis ===" >> "$OUTPUT_FILE"
    
    # Search for common config file patterns
    local config_files
    config_files=$(execute_command "find /app -type f \\( -name '*.cfg' -o -name '*.conf' -o -name '*.ini' -o -name '*.json' -o -name '*.xml' \\) 2>/dev/null | head -20 || echo 'No config files found'" 20 || true)
    
    echo "Configuration files found:" >> "$OUTPUT_FILE"
    echo "$config_files" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    # Search for IPs and domains in config files
    if echo "$config_files" | grep -qE "\.(cfg|conf|ini|json|xml)$"; then
        log_info "Extracting endpoints from configuration files..."
        local config_endpoints
        config_endpoints=$(execute_command "grep -hE '([0-9]{1,3}\.){3}[0-9]{1,3}|[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}' $config_files 2>/dev/null | grep -vE '^127\.|^10\.|^192\.168\.|^172\.(1[6-9]|2[0-9]|3[0-1])\\.' | sort -u | head -50 || echo 'No external endpoints in config files'" 30 || true)
        
        if [[ -n "$config_endpoints" ]] && ! echo "$config_endpoints" | grep -q "No external endpoints"; then
            echo "=== Endpoints from Configuration Files ===" >> "$OUTPUT_FILE"
            echo "$config_endpoints" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
        fi
    fi
}

discover_known_cloud_ips() {
    log_info "Checking for known cloud service IPs..."
    echo "" >> "$OUTPUT_FILE"
    echo "=== Known Cloud Service IPs ===" >> "$OUTPUT_FILE"
    
    # Known cloud IP from probe data
    echo "52.42.98.25 (MQTT server - from probe data)" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    # Check if this IP is in active connections
    local connections
    connections=$(execute_command "netstat -anp 2>/dev/null | grep 52.42.98.25 || ss -anp 2>/dev/null | grep 52.42.98.25 || echo 'Not in active connections'" 10 || true)
    
    if echo "$connections" | grep -q "52.42.98.25"; then
        log_success "Found active connection to known cloud IP: 52.42.98.25"
        echo "Active connection details:" >> "$OUTPUT_FILE"
        echo "$connections" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi
}

generate_summary() {
    log_info "Generating summary..."
    echo "" >> "$OUTPUT_FILE"
    echo "=== Cloud Endpoints Summary ===" >> "$OUTPUT_FILE"
    
    # Extract all unique IPs
    local all_ips
    all_ips=$(grep -E "([0-9]{1,3}\.){3}[0-9]{1,3}" "$OUTPUT_FILE" | \
        grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}" | \
        sort -u | \
        grep -vE "^127\.|^10\.|^192\.168\.|^172\.(1[6-9]|2[0-9]|3[0-1])\." || true)
    
    if [[ -n "$all_ips" ]]; then
        echo "Unique cloud IP addresses:" >> "$OUTPUT_FILE"
        echo "$all_ips" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        
        local ip_count
        ip_count=$(echo "$all_ips" | wc -l)
        log_success "Found $ip_count unique cloud IP address(es)"
    else
        log_warn "No cloud IP addresses found"
        echo "No cloud IP addresses discovered" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi
    
    # Extract all domains
    local all_domains
    all_domains=$(grep -E "[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" "$OUTPUT_FILE" | \
        grep -oE "[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" | \
        sort -u | \
        grep -vE "localhost|127\.0\.0\.1" || true)
    
    if [[ -n "$all_domains" ]]; then
        echo "Unique cloud domains:" >> "$OUTPUT_FILE"
        echo "$all_domains" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi
}

#######################################
# Main Discovery Function
#######################################
main() {
    log_info "Starting cloud endpoint discovery on $TARGET_IP"
    echo "=== Cloud Endpoint Discovery Report ===" > "$OUTPUT_FILE"
    echo "Target: $TARGET_IP" >> "$OUTPUT_FILE"
    echo "Date: $(date)" >> "$OUTPUT_FILE"
    echo "Local Network: $LOCAL_NETWORK" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    discover_active_connections
    discover_dns_servers
    discover_process_env
    discover_config_files
    discover_known_cloud_ips
    generate_summary
    
    log_success "Discovery complete. Results saved to: $OUTPUT_FILE"
}

main "$@"

