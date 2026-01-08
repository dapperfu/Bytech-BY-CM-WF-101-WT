#!/usr/bin/env bash
set -euo pipefail

#######################################
# iptables Alternatives Exploration Script
# Explores device to find alternatives to iptables for firewall/netfilter functionality
#######################################

TARGET_IP="${1:-}"
USERNAME="${2:-root}"
PASSWORD="${3:-hellotuya}"
OUTPUT_FILE="${4:-}"

# Default credentials from README
if [[ "$USERNAME" == "user" ]] && [[ "$PASSWORD" == "hellotuya" ]]; then
    PASSWORD="user123"
fi

TELNET_PORT="${TELNET_PORT:-23}"
COMMAND_TIMEOUT="${COMMAND_TIMEOUT:-30}"

# Check if expect is available
if ! command -v expect >/dev/null 2>&1; then
    echo "[!] Error: expect is not installed"
    echo "[*] Install with: apt-get install expect  or  yum install expect"
    exit 1
fi

if [[ -z "$TARGET_IP" ]]; then
    echo "Usage: $0 <target-ip> [username] [password] [output-file]"
    echo ""
    echo "Example:"
    echo "  $0 10.0.0.227 root hellotuya"
    echo "  $0 10.0.0.227 root hellotuya docs/device-iptables-analysis.md"
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
    "# " {
        send "$cmd\r"
        expect {
            "# " {
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
    "\$ " {
        send "$cmd\r"
        expect {
            "\$ " {
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
            "# " {
                send "$cmd\r"
                expect {
                    "# " {
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
            "\$ " {
                send "$cmd\r"
                expect {
                    "\$ " {
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
        grep -vF "$cmd" | \
        sed '/^$/d')
    
    # Remove command if it appears at the start (using fixed string matching)
    result=$(echo "$result" | grep -vF "$cmd" | sed '/^$/d')
    
    rm -f "$temp_output"
    echo "$result"
}

#######################################
# Output Functions
#######################################
output_section() {
    local title="$1"
    echo ""
    echo "=========================================="
    echo "$title"
    echo "=========================================="
    echo ""
}

output_subsection() {
    local title="$1"
    echo ""
    echo "--- $title ---"
    echo ""
}

output_result() {
    local label="$1"
    local result="$2"
    echo "**$label:**"
    if [[ -z "$result" ]] || echo "$result" | grep -q "not found\|No such file\|COMMAND_TIMEOUT\|CONNECTION"; then
        echo "  Not available or not found"
    else
        echo "  \`\`\`"
        echo "$result" | head -50
        echo "  \`\`\`"
    fi
    echo ""
}

#######################################
# System Architecture Detection
#######################################
check_system_architecture() {
    output_section "System Architecture"
    
    log_info "Detecting system architecture..."
    
    local uname_output
    uname_output=$(execute_command "uname -a" 15 || echo "")
    output_result "uname -a" "$uname_output"
    
    local cpuinfo
    cpuinfo=$(execute_command "cat /proc/cpuinfo" 15 || echo "")
    output_result "CPU Information" "$cpuinfo"
    
    local version
    version=$(execute_command "cat /proc/version" 10 || echo "")
    output_result "Kernel Version" "$version"
    
    # Extract architecture
    local arch
    arch=$(echo "$uname_output" | grep -oE '(armv[0-9]|arm|aarch64|x86_64|i[0-9]86|mips)' | head -1 || echo "unknown")
    echo "**Detected Architecture:** $arch"
    echo ""
}

#######################################
# Available Binaries and Tools
#######################################
check_available_binaries() {
    output_section "Available Binaries and Tools"
    
    log_info "Checking for iptables and related tools..."
    
    # Check standard binary locations
    local bin_dirs="/bin /sbin /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin"
    for dir in $bin_dirs; do
        local listing
        listing=$(execute_command "ls -1 $dir 2>/dev/null | head -50" 10 || echo "")
        if [[ -n "$listing" ]] && ! echo "$listing" | grep -q "No such file\|not found"; then
            output_subsection "Contents of $dir"
            echo "$listing" | head -30
            echo ""
        fi
    done
    
    # Check for specific tools
    local tools="iptables ip6tables ebtables arptables ip tc nft firewalld ufw ipset"
    output_subsection "Tool Availability Check"
    for tool in $tools; do
        local tool_check
        tool_check=$(execute_command "command -v $tool 2>/dev/null && $tool --version 2>&1 | head -3 || echo 'not found'" 10 || echo "not found")
        if echo "$tool_check" | grep -q "not found"; then
            echo "- **$tool**: Not found"
        else
            echo "- **$tool**: Available"
            echo "  \`\`\`"
            echo "$tool_check" | head -3
            echo "  \`\`\`"
        fi
    done
    echo ""
}

#######################################
# BusyBox Applets
#######################################
check_busybox_applets() {
    output_section "BusyBox Applets"
    
    log_info "Checking BusyBox applets..."
    
    # Check if busybox exists
    local busybox_check
    busybox_check=$(execute_command "busybox 2>&1 | head -5 || echo 'not found'" 10 || echo "")
    output_result "BusyBox" "$busybox_check"
    
    # List all applets
    local applets
    applets=$(execute_command "busybox --list 2>/dev/null || busybox 2>&1 | grep -A 200 'Currently defined functions' || echo 'Cannot list applets'" 15 || echo "")
    output_result "Available BusyBox Applets" "$applets"
    
    # Check for specific network/netfilter applets
    local netfilter_applets="iptables ip6tables ip tc"
    output_subsection "Network/Netfilter Applets"
    for applet in $netfilter_applets; do
        local applet_check
        applet_check=$(execute_command "busybox $applet 2>&1 | head -3 || echo 'not available'" 10 || echo "")
        if echo "$applet_check" | grep -q "not available\|not found"; then
            echo "- **$applet**: Not available in BusyBox"
        else
            echo "- **$applet**: Available in BusyBox"
            echo "  \`\`\`"
            echo "$applet_check" | head -3
            echo "  \`\`\`"
        fi
    done
    echo ""
}

#######################################
# Package Managers
#######################################
check_package_managers() {
    output_section "Package Managers"
    
    log_info "Checking for package managers..."
    
    local package_managers="opkg ipkg apt apt-get yum dnf apk pkg"
    output_subsection "Package Manager Availability"
    for pm in $package_managers; do
        local pm_check
        pm_check=$(execute_command "command -v $pm 2>/dev/null && $pm --version 2>&1 | head -2 || echo 'not found'" 10 || echo "not found")
        if echo "$pm_check" | grep -q "not found"; then
            echo "- **$pm**: Not found"
        else
            echo "- **$pm**: Available"
            echo "  \`\`\`"
            echo "$pm_check" | head -2
            echo "  \`\`\`"
        fi
    done
    echo ""
    
    # Check package manager configs
    output_subsection "Package Manager Configuration"
    local config_dirs="/etc/opkg /etc/ipkg /etc/apt /etc/yum.repos.d"
    for dir in $config_dirs; do
        local config_check
        config_check=$(execute_command "ls -la $dir 2>/dev/null | head -10 || echo 'not found'" 10 || echo "")
        if ! echo "$config_check" | grep -q "not found\|No such file"; then
            output_result "Contents of $dir" "$config_check"
        fi
    done
    
    # Check if repositories are configured
    local repo_check
    repo_check=$(execute_command "cat /etc/opkg/*.conf 2>/dev/null | grep -E 'src|dest' | head -10 || echo 'No opkg config found'" 10 || echo "")
    if ! echo "$repo_check" | grep -q "No opkg config found"; then
        output_result "opkg Repository Configuration" "$repo_check"
    fi
}

#######################################
# Kernel Netfilter Support
#######################################
check_kernel_netfilter() {
    output_section "Kernel Netfilter Support"
    
    log_info "Checking kernel netfilter support..."
    
    # Check /proc/net/ip_tables_* files
    local ip_tables_names
    ip_tables_names=$(execute_command "cat /proc/net/ip_tables_names 2>/dev/null || echo 'File not found'" 10 || echo "")
    output_result "/proc/net/ip_tables_names" "$ip_tables_names"
    
    local ip_tables_matches
    ip_tables_matches=$(execute_command "cat /proc/net/ip_tables_matches 2>/dev/null || echo 'File not found'" 10 || echo "")
    output_result "/proc/net/ip_tables_matches" "$ip_tables_matches"
    
    local ip_tables_targets
    ip_tables_targets=$(execute_command "cat /proc/net/ip_tables_targets 2>/dev/null || echo 'File not found'" 10 || echo "")
    output_result "/proc/net/ip_tables_targets" "$ip_tables_targets"
    
    # Check IP forwarding
    local ip_forward
    ip_forward=$(execute_command "cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo 'not available'" 10 || echo "")
    output_result "IP Forwarding (/proc/sys/net/ipv4/ip_forward)" "$ip_forward"
    
    # Check loaded netfilter modules
    local netfilter_modules
    netfilter_modules=$(execute_command "lsmod 2>/dev/null | grep -i netfilter || echo 'No netfilter modules loaded'" 10 || echo "")
    output_result "Loaded Netfilter Modules" "$netfilter_modules"
    
    # Check available netfilter modules
    local available_modules
    available_modules=$(execute_command "find /lib/modules -name '*netfilter*' -o -name '*iptable*' 2>/dev/null | head -20 || echo 'No modules found'" 15 || echo "")
    output_result "Available Netfilter Modules" "$available_modules"
    
    # Check if /proc/sys/net/ipv4/ is writable
    local writable_check
    writable_check=$(execute_command "test -w /proc/sys/net/ipv4/ip_forward && echo 'writable' || echo 'not writable'" 10 || echo "")
    output_result "/proc/sys/net/ipv4/ Writable" "$writable_check"
}

#######################################
# Alternative Tools
#######################################
check_alternative_tools() {
    output_section "Alternative Tools"
    
    log_info "Checking for alternative firewall/netfilter tools..."
    
    # Check iproute2 (ip command)
    local ip_check
    ip_check=$(execute_command "command -v ip >/dev/null && ip -V 2>&1 || echo 'not found'" 10 || echo "")
    if ! echo "$ip_check" | grep -q "not found"; then
        output_result "iproute2 (ip command)" "$ip_check"
        
        # Check ip rule and ip route capabilities
        local ip_rule
        ip_rule=$(execute_command "ip rule list 2>&1 | head -10 || echo 'not available'" 10 || echo "")
        output_result "ip rule list" "$ip_rule"
        
        local ip_route
        ip_route=$(execute_command "ip route list 2>&1 | head -10 || echo 'not available'" 10 || echo "")
        output_result "ip route list" "$ip_route"
    fi
    
    # Check tc (traffic control)
    local tc_check
    tc_check=$(execute_command "command -v tc >/dev/null && tc -V 2>&1 || echo 'not found'" 10 || echo "")
    output_result "tc (Traffic Control)" "$tc_check"
    
    # Check nftables
    local nft_check
    nft_check=$(execute_command "command -v nft >/dev/null && nft --version 2>&1 || echo 'not found'" 10 || echo "")
    output_result "nftables (nft)" "$nft_check"
    
    # Check firewalld
    local firewalld_check
    firewalld_check=$(execute_command "command -v firewall-cmd >/dev/null && firewall-cmd --version 2>&1 || echo 'not found'" 10 || echo "")
    output_result "firewalld" "$firewalld_check"
    
    # Check ufw
    local ufw_check
    ufw_check=$(execute_command "command -v ufw >/dev/null && ufw --version 2>&1 || echo 'not found'" 10 || echo "")
    output_result "ufw (Uncomplicated Firewall)" "$ufw_check"
    
    # Check ipset
    local ipset_check
    ipset_check=$(execute_command "command -v ipset >/dev/null && ipset --version 2>&1 || echo 'not found'" 10 || echo "")
    output_result "ipset" "$ipset_check"
}

#######################################
# Direct Kernel Interface
#######################################
check_direct_kernel_interface() {
    output_section "Direct Kernel Interface"
    
    log_info "Checking direct kernel interface capabilities..."
    
    # Check /proc/sys/net/ipv4/ writability
    local proc_writable
    proc_writable=$(execute_command "test -w /proc/sys/net/ipv4/ip_forward && echo 'yes' || echo 'no'" 10 || echo "no")
    output_result "/proc/sys/net/ipv4/ Writable" "$proc_writable"
    
    # List available /proc/sys/net/ipv4/ parameters
    local proc_params
    proc_params=$(execute_command "ls -1 /proc/sys/net/ipv4/ 2>/dev/null | head -30 || echo 'not accessible'" 10 || echo "")
    output_result "Available /proc/sys/net/ipv4/ Parameters" "$proc_params"
    
    # Check /proc/net/ contents
    local proc_net
    proc_net=$(execute_command "ls -1 /proc/net/ 2>/dev/null | head -30 || echo 'not accessible'" 10 || echo "")
    output_result "Contents of /proc/net/" "$proc_net"
}

#######################################
# Installation Options Research
#######################################
check_installation_options() {
    output_section "Installation Options"
    
    log_info "Checking installation feasibility..."
    
    # Check available disk space
    local disk_space
    disk_space=$(execute_command "df -h" 10 || echo "")
    output_result "Disk Space" "$disk_space"
    
    # Check writable directories
    output_subsection "Writable Directories"
    local writable_dirs="/tmp /opt /app /usr/local /var/tmp"
    for dir in $writable_dirs; do
        local writable_check
        writable_check=$(execute_command "test -w $dir && echo 'writable' || echo 'not writable'" 10 || echo "")
        echo "- **$dir**: $writable_check"
    done
    echo ""
    
    # Check if wget/curl available for downloading binaries
    output_subsection "Download Tools"
    local wget_check
    wget_check=$(execute_command "command -v wget >/dev/null && wget --version 2>&1 | head -1 || echo 'not found'" 10 || echo "")
    output_result "wget" "$wget_check"
    
    local curl_check
    curl_check=$(execute_command "command -v curl >/dev/null && curl --version 2>&1 | head -1 || echo 'not found'" 10 || echo "")
    output_result "curl" "$curl_check"
    
    # Document precompiled binary options
    output_subsection "Precompiled Binary Options"
    echo "Potential sources for precompiled iptables binaries:"
    echo ""
    echo "1. **Static ARM binaries from iptables project**"
    echo "   - Source: https://netfilter.org/projects/iptables/downloads.html"
    echo "   - Requires: Matching ARM architecture (ARMv5, ARMv6, ARMv7, etc.)"
    echo ""
    echo "2. **BusyBox with netfilter support**"
    echo "   - Source: BusyBox compiled with CONFIG_IPTABLES=y"
    echo "   - Requires: Recompiling BusyBox or finding precompiled version"
    echo ""
    echo "3. **Toybox (alternative to BusyBox)**"
    echo "   - Source: https://landley.net/toybox/downloads/binaries/latest/"
    echo "   - Note: User attempted wget but SSL failed - may need HTTP source"
    echo ""
    echo "4. **OpenWrt packages**"
    echo "   - If device is OpenWrt-based, use opkg to install iptables"
    echo "   - Command: opkg update && opkg install iptables"
    echo ""
}

#######################################
# Generate Recommendations
#######################################
generate_recommendations() {
    output_section "Recommendations and Alternatives"
    
    log_info "Generating recommendations..."
    
    echo "Based on the exploration results, here are potential alternatives:"
    echo ""
    
    echo "### 1. BusyBox iptables Applet"
    echo "If BusyBox has iptables compiled in, use:"
    echo "\`\`\`"
    echo "busybox iptables -L -n"
    echo "\`\`\`"
    echo ""
    
    echo "### 2. iproute2 (ip command)"
    echo "The \`ip\` command can handle some routing and filtering:"
    echo "\`\`\`"
    echo "ip rule add fwmark 1 table 100"
    echo "ip route add default via <gateway> table 100"
    echo "\`\`\`"
    echo "Note: Limited compared to iptables, but may work for basic routing"
    echo ""
    
    echo "### 3. Direct Kernel Interface"
    echo "If kernel supports netfilter but iptables binary is missing:"
    echo "- Check if netfilter modules can be loaded"
    echo "- Use /proc/sys/net/ipv4/ for basic IP forwarding"
    echo "- Limited functionality compared to full iptables"
    echo ""
    
    echo "### 4. Precompiled Static Binary"
    echo "Download and transfer a static ARM iptables binary:"
    echo "1. Identify exact architecture (ARMv5, ARMv6, ARMv7)"
    echo "2. Download matching static binary"
    echo "3. Transfer using transfer-file-telnet.sh with FORCE_HTTP=1"
    echo "4. Place in /tmp or /opt and make executable"
    echo ""
    
    echo "### 5. MITMproxy Workaround"
    echo "If iptables cannot be installed, alternatives for MITMproxy:"
    echo "- Use explicit proxy mode (configure applications to use proxy)"
    echo "- Use SOCKS5 proxy mode if supported"
    echo "- Modify application configuration to point to MITMproxy"
    echo "- Use DNS redirection if DNS server is configurable"
    echo ""
}

#######################################
# Main Execution
#######################################
main() {
    log_info "Starting iptables alternatives exploration for $TARGET_IP"
    
    local output
    if [[ -n "$OUTPUT_FILE" ]]; then
        output="$OUTPUT_FILE"
        mkdir -p "$(dirname "$output")" 2>/dev/null || true
        exec > >(tee "$output")
    fi
    
    echo "# iptables Alternatives Analysis"
    echo ""
    echo "**Target Device:** $TARGET_IP"
    echo "**Date:** $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    check_system_architecture
    check_available_binaries
    check_busybox_applets
    check_package_managers
    check_kernel_netfilter
    check_alternative_tools
    check_direct_kernel_interface
    check_installation_options
    generate_recommendations
    
    log_success "Exploration complete"
    
    if [[ -n "$OUTPUT_FILE" ]]; then
        log_info "Report saved to: $OUTPUT_FILE"
    fi
}

main "$@"
