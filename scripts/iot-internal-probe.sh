#!/usr/bin/env bash
set -euo pipefail

#######################################
# Configuration Section
#######################################
TARGET_IP="${1:-}"
USERNAME="${2:-root}"
PASSWORD="${3:-hellotuya}"
OUTPUT_DIR="${4:-}"

# Default credentials from README
if [[ "$USERNAME" == "user" ]] && [[ "$PASSWORD" == "hellotuya" ]]; then
    PASSWORD="user123"
fi

TELNET_PORT="${TELNET_PORT:-23}"
COMMAND_TIMEOUT="${COMMAND_TIMEOUT:-30}"
CONNECTION_TIMEOUT="${CONNECTION_TIMEOUT:-10}"
MAX_FILE_SIZE="${MAX_FILE_SIZE:-10485760}"  # 10MB default
MAX_EXTRACT_SIZE="${MAX_EXTRACT_SIZE:-52428800}"  # 50MB total extraction limit

# Check if expect is available
if ! command -v expect &> /dev/null; then
    echo "[!] Error: expect is not installed"
    echo "[*] Install with: apt-get install expect  or  yum install expect"
    exit 1
fi

if [[ -z "$TARGET_IP" ]]; then
    echo "Usage: $0 <target-ip> [username] [password] [output-dir]"
    echo ""
    echo "Example:"
    echo "  $0 10.0.0.227 root hellotuya"
    echo "  $0 10.0.0.227 user user123"
    exit 1
fi

#######################################
# Setup Output Directory
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$(date +%Y%m%d_%H%M%S)"

if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="iot_internal_${TARGET_IP}_${TS}"
fi

mkdir -p "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/system_info"
mkdir -p "$OUTPUT_DIR/processes"
mkdir -p "$OUTPUT_DIR/network"
mkdir -p "$OUTPUT_DIR/filesystem"
mkdir -p "$OUTPUT_DIR/services"
mkdir -p "$OUTPUT_DIR/application"
mkdir -p "$OUTPUT_DIR/security"
mkdir -p "$OUTPUT_DIR/extracted/configs"
mkdir -p "$OUTPUT_DIR/extracted/scripts"
mkdir -p "$OUTPUT_DIR/extracted/logs"
mkdir -p "$OUTPUT_DIR/extracted/binaries"
mkdir -p "$OUTPUT_DIR/vulnerabilities"

#######################################
# Logging Functions
#######################################
log() {
    local level="${1:-INFO}"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$OUTPUT_DIR/execution.log"
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
    local output_file="${2:-}"
    local timeout="${3:-$COMMAND_TIMEOUT}"
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
    
    # Run expect and capture output
    echo "$expect_script" | expect 2>&1 > "$temp_output"
    
    # Process output: remove spawn messages, connection messages, prompts, and clean up
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
    
    # Remove the command echo if it appears at the start
    result=$(echo "$result" | sed "1s/^${cmd}\r\?$//" | sed '/^$/d')
    
    if [[ -n "$output_file" ]]; then
        echo "$result" > "$output_file"
        echo "$result"
    else
        echo "$result"
    fi
    
    rm -f "$temp_output"
}

execute_command_silent() {
    execute_command "$1" "$2" "$3" >/dev/null 2>&1
}

#######################################
# System Information Gathering
#######################################
gather_system_info() {
    log_info "Gathering system information..."
    
    # CPU Information
    log_info "  - CPU information"
    execute_command "cat /proc/cpuinfo" "$OUTPUT_DIR/system_info/cpuinfo.txt" || log_warn "Failed to get CPU info"
    
    # Memory Information
    log_info "  - Memory information"
    execute_command "cat /proc/meminfo" "$OUTPUT_DIR/system_info/meminfo.txt" || log_warn "Failed to get memory info"
    
    # Kernel Version
    log_info "  - Kernel version"
    execute_command "cat /proc/version" "$OUTPUT_DIR/system_info/version.txt" || log_warn "Failed to get kernel version"
    
    # Kernel Command Line
    log_info "  - Kernel command line"
    execute_command "cat /proc/cmdline" "$OUTPUT_DIR/system_info/cmdline.txt" || log_warn "Failed to get cmdline"
    
    # System Uptime
    log_info "  - System uptime"
    execute_command "cat /proc/uptime" "$OUTPUT_DIR/system_info/uptime.txt" || log_warn "Failed to get uptime"
    
    # Uname
    log_info "  - System uname"
    execute_command "uname -a" "$OUTPUT_DIR/system_info/uname.txt" || log_warn "Failed to get uname"
    
    # Kernel Messages
    log_info "  - Kernel messages (dmesg)"
    execute_command "dmesg" "$OUTPUT_DIR/system_info/dmesg.txt" || log_warn "Failed to get dmesg"
    
    # Loaded Modules
    log_info "  - Loaded kernel modules"
    execute_command "lsmod" "$OUTPUT_DIR/system_info/modules.txt" || log_warn "Failed to get modules"
    
    # System Load
    log_info "  - System load"
    execute_command "cat /proc/loadavg" "$OUTPUT_DIR/system_info/loadavg.txt" || log_warn "Failed to get loadavg"
    
    # Memory Usage
    log_info "  - Memory usage (free)"
    execute_command "free" "$OUTPUT_DIR/system_info/free.txt" || log_warn "Failed to get free memory"
    
    # Disk Usage
    log_info "  - Disk usage"
    execute_command "df -h" "$OUTPUT_DIR/system_info/df.txt" || log_warn "Failed to get disk usage"
    
    # Mounted Filesystems
    log_info "  - Mounted filesystems"
    execute_command "mount" "$OUTPUT_DIR/system_info/mount.txt" || log_warn "Failed to get mount info"
    
    # Device Tree (if available)
    log_info "  - Device tree information"
    execute_command "find /proc/device-tree -type f 2>/dev/null | head -20" "$OUTPUT_DIR/system_info/device_tree.txt" || log_warn "Device tree not available"
    
    log_success "System information gathering complete"
}

#######################################
# Process Enumeration
#######################################
enumerate_processes() {
    log_info "Enumerating processes..."
    
    # Process List
    log_info "  - Process list (ps aux)"
    execute_command "ps aux" "$OUTPUT_DIR/processes/ps_aux.txt" || log_warn "Failed to get process list"
    
    # Process Tree
    log_info "  - Process tree (ps auxf)"
    execute_command "ps auxf" "$OUTPUT_DIR/processes/ps_auxf.txt" || log_warn "Failed to get process tree"
    
    # Pstree (if available)
    log_info "  - Process tree (pstree)"
    execute_command "pstree" "$OUTPUT_DIR/processes/pstree.txt" || log_warn "pstree not available"
    
    # Top Snapshot
    log_info "  - Process snapshot (top)"
    execute_command "top -bn1" "$OUTPUT_DIR/processes/top.txt" || log_warn "Failed to get top snapshot"
    
    # List Open Files (if available)
    log_info "  - Open files (lsof)"
    execute_command "lsof" "$OUTPUT_DIR/processes/lsof.txt" || log_warn "lsof not available"
    
    # Process Command Lines
    log_info "  - Process command lines"
    execute_command "for pid in \$(ls /proc | grep -E '^[0-9]+\$'); do echo \"=== PID \$pid ===\"; cat /proc/\$pid/cmdline 2>/dev/null | tr '\\0' ' '; echo; done" "$OUTPUT_DIR/processes/cmdlines.txt" || log_warn "Failed to get cmdlines"
    
    # Process Environments (sample)
    log_info "  - Process environments (sample)"
    execute_command "for pid in \$(ls /proc | grep -E '^[0-9]+\$' | head -10); do echo \"=== PID \$pid ===\"; cat /proc/\$pid/environ 2>/dev/null | tr '\\0' '\\n' | head -20; echo; done" "$OUTPUT_DIR/processes/environments.txt" || log_warn "Failed to get environments"
    
    # Process Status (sample)
    log_info "  - Process status (sample)"
    execute_command "for pid in \$(ls /proc | grep -E '^[0-9]+\$' | head -20); do echo \"=== PID \$pid ===\"; cat /proc/\$pid/status 2>/dev/null | head -30; echo; done" "$OUTPUT_DIR/processes/status.txt" || log_warn "Failed to get process status"
    
    log_success "Process enumeration complete"
}

#######################################
# Network Information Gathering
#######################################
gather_network_info() {
    log_info "Gathering network information..."
    
    # Network Interfaces
    log_info "  - Network interfaces"
    execute_command "ifconfig -a 2>/dev/null || ip addr show" "$OUTPUT_DIR/network/interfaces.txt" || log_warn "Failed to get interfaces"
    
    # Routing Table
    log_info "  - Routing table"
    execute_command "route -n 2>/dev/null || ip route show" "$OUTPUT_DIR/network/routes.txt" || log_warn "Failed to get routes"
    
    # ARP Table
    log_info "  - ARP table"
    execute_command "arp -a 2>/dev/null || ip neigh show" "$OUTPUT_DIR/network/arp.txt" || log_warn "Failed to get ARP table"
    
    # Network Connections
    log_info "  - Network connections"
    execute_command "netstat -anp 2>/dev/null || ss -anp" "$OUTPUT_DIR/network/connections.txt" || log_warn "Failed to get connections"
    
    # Listening Ports
    log_info "  - Listening ports"
    execute_command "netstat -tulpn 2>/dev/null || ss -tulpn" "$OUTPUT_DIR/network/listening_ports.txt" || log_warn "Failed to get listening ports"
    
    # Firewall Rules
    log_info "  - Firewall rules"
    execute_command "iptables -L -n -v 2>/dev/null" "$OUTPUT_DIR/network/firewall_rules.txt" || log_warn "iptables not available or no rules"
    
    # WiFi Configuration
    log_info "  - WiFi configuration"
    execute_command "iwconfig 2>/dev/null || iw dev 2>/dev/null || echo 'WiFi tools not available'" "$OUTPUT_DIR/network/wifi_config.txt" || log_warn "Failed to get WiFi config"
    
    # TCP Connections from /proc
    log_info "  - TCP connections (from /proc/net/tcp)"
    execute_command "cat /proc/net/tcp" "$OUTPUT_DIR/network/proc_tcp.txt" || log_warn "Failed to get /proc/net/tcp"
    
    # UDP Connections from /proc
    log_info "  - UDP connections (from /proc/net/udp)"
    execute_command "cat /proc/net/udp" "$OUTPUT_DIR/network/proc_udp.txt" || log_warn "Failed to get /proc/net/udp"
    
    # Routing Information from /proc
    log_info "  - Routing information (from /proc/net/route)"
    execute_command "cat /proc/net/route" "$OUTPUT_DIR/network/proc_route.txt" || log_warn "Failed to get /proc/net/route"
    
    # DNS Configuration
    log_info "  - DNS configuration"
    execute_command "cat /etc/resolv.conf 2>/dev/null || echo 'resolv.conf not found'" "$OUTPUT_DIR/network/resolv_conf.txt" || log_warn "Failed to get DNS config"
    
    # Hosts File
    log_info "  - Hosts file"
    execute_command "cat /etc/hosts 2>/dev/null || echo 'hosts file not found'" "$OUTPUT_DIR/network/hosts.txt" || log_warn "Failed to get hosts file"
    
    # Network Interface Statistics
    log_info "  - Network interface statistics"
    execute_command "cat /proc/net/dev" "$OUTPUT_DIR/network/interface_stats.txt" || log_warn "Failed to get interface stats"
    
    log_success "Network information gathering complete"
}

#######################################
# File System Exploration
#######################################
explore_filesystem() {
    log_info "Exploring file system..."
    
    # /app Directory Listing
    log_info "  - /app directory listing"
    execute_command "ls -lah /app" "$OUTPUT_DIR/filesystem/app_directory_listing.txt" || log_warn "Failed to list /app"
    
    # /app Directory Tree
    log_info "  - /app directory tree"
    execute_command "find /app -type f -o -type d 2>/dev/null | head -100" "$OUTPUT_DIR/filesystem/app_tree.txt" || log_warn "Failed to get /app tree"
    
    # /etc/passwd
    log_info "  - User accounts (/etc/passwd)"
    execute_command "cat /etc/passwd" "$OUTPUT_DIR/filesystem/etc_passwd.txt" || log_warn "Failed to get passwd"
    
    # /etc/shadow
    log_info "  - Password hashes (/etc/shadow)"
    execute_command "cat /etc/shadow 2>/dev/null || echo 'shadow file not readable'" "$OUTPUT_DIR/filesystem/etc_shadow.txt" || log_warn "Failed to get shadow"
    
    # /etc/group
    log_info "  - Groups (/etc/group)"
    execute_command "cat /etc/group" "$OUTPUT_DIR/filesystem/etc_group.txt" || log_warn "Failed to get group"
    
    # /etc/hosts
    log_info "  - Hosts file (/etc/hosts)"
    execute_command "cat /etc/hosts 2>/dev/null || echo 'hosts file not found'" "$OUTPUT_DIR/filesystem/etc_hosts.txt" || log_warn "Failed to get hosts"
    
    # /etc/resolv.conf
    log_info "  - DNS config (/etc/resolv.conf)"
    execute_command "cat /etc/resolv.conf 2>/dev/null || echo 'resolv.conf not found'" "$OUTPUT_DIR/filesystem/etc_resolv_conf.txt" || log_warn "Failed to get resolv.conf"
    
    # Network Configuration Files
    log_info "  - Network configuration files"
    execute_command "find /etc -name '*network*' -o -name '*interfaces*' -o -name '*net*' 2>/dev/null | head -20" "$OUTPUT_DIR/filesystem/network_config_files.txt" || log_warn "Failed to find network configs"
    
    # Startup Configuration
    log_info "  - Startup configuration"
    execute_command "cat /etc/inittab 2>/dev/null || ls -la /etc/systemd/system/ 2>/dev/null || ls -la /etc/init.d/ 2>/dev/null || echo 'No startup config found'" "$OUTPUT_DIR/filesystem/startup_config.txt" || log_warn "Failed to get startup config"
    
    # /etc/rc.local
    log_info "  - /etc/rc.local"
    execute_command "cat /etc/rc.local 2>/dev/null || echo 'rc.local not found'" "$OUTPUT_DIR/filesystem/rc_local.txt" || log_warn "Failed to get rc.local"
    
    # Mount Points
    log_info "  - Mount points"
    execute_command "cat /proc/mounts" "$OUTPUT_DIR/filesystem/mount_points.txt" || log_warn "Failed to get mount points"
    
    # Supported Filesystems
    log_info "  - Supported filesystems"
    execute_command "cat /proc/filesystems" "$OUTPUT_DIR/filesystem/filesystems.txt" || log_warn "Failed to get filesystems"
    
    # Important Directories
    log_info "  - Important directories"
    for dir in /etc /usr /var /tmp /opt /bin /sbin /lib; do
        execute_command "ls -la $dir 2>/dev/null | head -50" "$OUTPUT_DIR/filesystem/$(basename $dir)_listing.txt" || true
    done
    
    log_success "File system exploration complete"
}

#######################################
# Services and Startup Enumeration
#######################################
enumerate_services() {
    log_info "Enumerating services and startup..."
    
    # Init Scripts
    log_info "  - Init scripts"
    execute_command "ls -la /etc/init.d/ 2>/dev/null || echo 'No init.d directory'" "$OUTPUT_DIR/services/init_scripts.txt" || log_warn "Failed to get init scripts"
    
    # Systemd Units
    log_info "  - Systemd units"
    execute_command "ls -la /etc/systemd/system/ 2>/dev/null || echo 'No systemd directory'" "$OUTPUT_DIR/services/systemd_units.txt" || log_warn "Failed to get systemd units"
    
    # Cron Jobs (root)
    log_info "  - Cron jobs (root)"
    execute_command "crontab -l 2>/dev/null || echo 'No crontab for root'" "$OUTPUT_DIR/services/cron_root.txt" || log_warn "Failed to get root crontab"
    
    # System Cron
    log_info "  - System cron"
    execute_command "cat /etc/crontab 2>/dev/null || echo 'No system crontab'" "$OUTPUT_DIR/services/cron_system.txt" || log_warn "Failed to get system crontab"
    
    # User Crontabs
    log_info "  - User crontabs"
    execute_command "ls -la /var/spool/cron/ 2>/dev/null || echo 'No user crontabs directory'" "$OUTPUT_DIR/services/cron_users.txt" || log_warn "Failed to get user crontabs"
    
    # Startup Scripts in /app
    log_info "  - Startup scripts in /app"
    execute_command "find /app -name '*.sh' -o -name '*start*' -o -name '*init*' 2>/dev/null" "$OUTPUT_DIR/services/app_startup_scripts.txt" || log_warn "Failed to find startup scripts"
    
    # Running Services Status
    log_info "  - Running services status"
    execute_command "ps aux | grep -E '(httpd|nginx|apache|sshd|telnetd|rtsp|onvif)' | grep -v grep" "$OUTPUT_DIR/services/running_services.txt" || log_warn "Failed to get running services"
    
    log_success "Services enumeration complete"
}

#######################################
# Application/Webcam Specific Enumeration
#######################################
enumerate_application() {
    log_info "Enumerating application/webcam specific information..."
    
    # All Files in /app
    log_info "  - All files in /app"
    execute_command "find /app -type f -exec ls -lh {} \; 2>/dev/null" "$OUTPUT_DIR/application/app_files_listing.txt" || log_warn "Failed to list /app files"
    
    # Configuration Files
    log_info "  - Configuration files"
    execute_command "find /app -type f \\( -name '*.cfg' -o -name '*.conf' -o -name '*.ini' -o -name '*.xml' -o -name '*.json' \\) 2>/dev/null" "$OUTPUT_DIR/application/config_files.txt" || log_warn "Failed to find config files"
    
    # Script Files
    log_info "  - Script files"
    execute_command "find /app -type f -name '*.sh' 2>/dev/null" "$OUTPUT_DIR/application/scripts.txt" || log_warn "Failed to find scripts"
    
    # Log Files
    log_info "  - Log files"
    execute_command "find /app -type f -name '*.log' -o -name '*log*' 2>/dev/null | head -20" "$OUTPUT_DIR/application/logs.txt" || log_warn "Failed to find logs"
    
    # Firmware Version
    log_info "  - Firmware version information"
    execute_command "cat /app/prodid 2>/dev/null; cat /app/hdt_model 2>/dev/null; cat /proc/version 2>/dev/null" "$OUTPUT_DIR/application/firmware_version.txt" || log_warn "Failed to get firmware version"
    
    # Model/Product Information
    log_info "  - Model/product information"
    execute_command "cat /app/prodid 2>/dev/null; cat /app/hdt_model 2>/dev/null; find /proc/device-tree -type f -exec cat {} \; 2>/dev/null | head -50" "$OUTPUT_DIR/application/model_info.txt" || log_warn "Failed to get model info"
    
    # Application Binaries
    log_info "  - Application binaries"
    execute_command "find /app -type f -executable 2>/dev/null | head -30" "$OUTPUT_DIR/application/binaries.txt" || log_warn "Failed to find binaries"
    
    # Libraries
    log_info "  - Libraries"
    execute_command "find /app -type f -name '*.so*' 2>/dev/null | head -30" "$OUTPUT_DIR/application/libraries.txt" || log_warn "Failed to find libraries"
    
    # Environment Variables from Processes
    log_info "  - Environment variables from processes"
    execute_command "for pid in \$(ps aux | grep -E '(app|webcam|camera)' | grep -v grep | awk '{print \$2}' | head -5); do echo \"=== PID \$pid ===\"; cat /proc/\$pid/environ 2>/dev/null | tr '\\0' '\\n'; echo; done" "$OUTPUT_DIR/application/process_env.txt" || log_warn "Failed to get process environments"
    
    log_success "Application enumeration complete"
}

#######################################
# Security Assessment
#######################################
assess_security() {
    log_info "Performing security assessment..."
    
    # File Permissions Analysis
    log_info "  - File permissions analysis"
    execute_command "find /app -type f -exec ls -l {} \; 2>/dev/null | head -100" "$OUTPUT_DIR/security/file_permissions.txt" || log_warn "Failed to analyze permissions"
    
    # SUID/SGID Files
    log_info "  - SUID/SGID files"
    execute_command "find / -perm -4000 -o -perm -2000 2>/dev/null | head -50" "$OUTPUT_DIR/security/suid_sgid_files.txt" || log_warn "Failed to find SUID/SGID files"
    
    # World-Writable Files
    log_info "  - World-writable files"
    execute_command "find / -perm -002 -type f 2>/dev/null | head -50" "$OUTPUT_DIR/security/world_writable.txt" || log_warn "Failed to find world-writable files"
    
    # World-Readable Sensitive Files
    log_info "  - World-readable sensitive files"
    execute_command "find /app -type f -perm -004 \\( -name '*.cfg' -o -name '*.conf' -o -name '*pass*' -o -name '*key*' \\) 2>/dev/null" "$OUTPUT_DIR/security/world_readable_sensitive.txt" || log_warn "Failed to find world-readable sensitive files"
    
    # Password Analysis
    log_info "  - Password analysis"
    {
        if [[ -f "$OUTPUT_DIR/filesystem/etc_passwd.txt" ]]; then
            echo "=== /etc/passwd Analysis ==="
            cat "$OUTPUT_DIR/filesystem/etc_passwd.txt"
            echo ""
        fi
        if [[ -f "$OUTPUT_DIR/filesystem/etc_shadow.txt" ]]; then
            echo "=== /etc/shadow Analysis ==="
            cat "$OUTPUT_DIR/filesystem/etc_shadow.txt"
            echo ""
            echo "=== Weak Password Checks ==="
            grep -E "^\w+::|^\w+:\*:" "$OUTPUT_DIR/filesystem/etc_shadow.txt" 2>/dev/null || echo "No empty or disabled passwords found"
        fi
    } > "$OUTPUT_DIR/security/password_analysis.txt"
    
    # Open Ports from Internal Perspective
    log_info "  - Open ports (internal)"
    if [[ -f "$OUTPUT_DIR/network/listening_ports.txt" ]]; then
        cp "$OUTPUT_DIR/network/listening_ports.txt" "$OUTPUT_DIR/security/open_ports_internal.txt"
    fi
    
    # Firewall Rule Analysis
    log_info "  - Firewall rule analysis"
    if [[ -f "$OUTPUT_DIR/network/firewall_rules.txt" ]]; then
        {
            echo "=== Firewall Rules ==="
            cat "$OUTPUT_DIR/network/firewall_rules.txt"
            echo ""
            echo "=== Analysis ==="
            if grep -q "ACCEPT.*0.0.0.0/0" "$OUTPUT_DIR/network/firewall_rules.txt" 2>/dev/null; then
                echo "WARNING: Found firewall rules allowing connections from anywhere"
            fi
        } > "$OUTPUT_DIR/security/firewall_analysis.txt"
    fi
    
    # Network Service Exposure
    log_info "  - Network service exposure"
    {
        echo "=== Listening Services ==="
        if [[ -f "$OUTPUT_DIR/network/listening_ports.txt" ]]; then
            cat "$OUTPUT_DIR/network/listening_ports.txt"
        fi
        echo ""
        echo "=== Active Connections ==="
        if [[ -f "$OUTPUT_DIR/network/connections.txt" ]]; then
            head -50 "$OUTPUT_DIR/network/connections.txt"
        fi
    } > "$OUTPUT_DIR/security/network_exposure.txt"
    
    # Process Privilege Escalation Vectors
    log_info "  - Process privilege escalation vectors"
    {
        echo "=== Processes Running as Root ==="
        if [[ -f "$OUTPUT_DIR/processes/ps_aux.txt" ]]; then
            grep "^root" "$OUTPUT_DIR/processes/ps_aux.txt" | head -20
        fi
        echo ""
        echo "=== SUID/SGID Files ==="
        if [[ -f "$OUTPUT_DIR/security/suid_sgid_files.txt" ]]; then
            head -20 "$OUTPUT_DIR/security/suid_sgid_files.txt"
        fi
    } > "$OUTPUT_DIR/security/privilege_escalation.txt"
    
    # Insecure File Permissions in /app
    log_info "  - Insecure file permissions in /app"
    execute_command "find /app -type f \\( -perm -002 -o -perm -020 \\) 2>/dev/null" "$OUTPUT_DIR/security/app_insecure_perms.txt" || log_warn "Failed to find insecure permissions"
    
    log_success "Security assessment complete"
}

#######################################
# File Extraction
#######################################
extract_files() {
    log_info "Extracting files from device..."
    local total_size=0
    local extracted_count=0
    
    # Extract Configuration Files
    log_info "  - Extracting configuration files"
    local config_files
    config_files=$(execute_command "find /app -type f \\( -name '*.cfg' -o -name '*.conf' -o -name '*.ini' -o -name '*.xml' -o -name '*.json' \\) 2>/dev/null" | grep -v "^$" | head -50)
    
    while IFS= read -r file; do
        if [[ -n "$file" ]] && [[ "$file" != "COMMAND_TIMEOUT" ]] && [[ "$file" != "CONNECTION_TIMEOUT" ]]; then
            local file_size
            file_size=$(execute_command "stat -c%s '$file' 2>/dev/null || echo '0'" | grep -E '^[0-9]+$' || echo "0")
            
            if [[ "$file_size" -lt "$MAX_FILE_SIZE" ]] && [[ $((total_size + file_size)) -lt "$MAX_EXTRACT_SIZE" ]]; then
                local rel_path="${file#/}"
                local dest_path="$OUTPUT_DIR/extracted/configs/$rel_path"
                mkdir -p "$(dirname "$dest_path")"
                
                execute_command "cat '$file' 2>/dev/null" > "$dest_path" 2>/dev/null && {
                    ((extracted_count++))
                    total_size=$((total_size + file_size))
                    log_info "    Extracted: $file ($file_size bytes)"
                } || log_warn "    Failed to extract: $file"
            fi
        fi
    done <<< "$config_files"
    
    # Extract Shell Scripts
    log_info "  - Extracting shell scripts"
    local script_files
    script_files=$(execute_command "find /app -type f -name '*.sh' 2>/dev/null" | grep -v "^$" | head -50)
    
    while IFS= read -r file; do
        if [[ -n "$file" ]] && [[ "$file" != "COMMAND_TIMEOUT" ]] && [[ "$file" != "CONNECTION_TIMEOUT" ]]; then
            local file_size
            file_size=$(execute_command "stat -c%s '$file' 2>/dev/null || echo '0'" | grep -E '^[0-9]+$' || echo "0")
            
            if [[ "$file_size" -lt "$MAX_FILE_SIZE" ]] && [[ $((total_size + file_size)) -lt "$MAX_EXTRACT_SIZE" ]]; then
                local rel_path="${file#/}"
                local dest_path="$OUTPUT_DIR/extracted/scripts/$rel_path"
                mkdir -p "$(dirname "$dest_path")"
                
                execute_command "cat '$file' 2>/dev/null" > "$dest_path" 2>/dev/null && {
                    ((extracted_count++))
                    total_size=$((total_size + file_size))
                    log_info "    Extracted: $file ($file_size bytes)"
                } || log_warn "    Failed to extract: $file"
            fi
        fi
    done <<< "$script_files"
    
    # Extract Log Files (with size limit)
    log_info "  - Extracting log files (last 1000 lines)"
    local log_files
    log_files=$(execute_command "find /app -type f -name '*.log' 2>/dev/null | head -10" | grep -v "^$" | head -10)
    
    while IFS= read -r file; do
        if [[ -n "$file" ]] && [[ "$file" != "COMMAND_TIMEOUT" ]] && [[ "$file" != "CONNECTION_TIMEOUT" ]]; then
            local dest_path="$OUTPUT_DIR/extracted/logs/$(basename "$file")"
            execute_command "tail -1000 '$file' 2>/dev/null" > "$dest_path" 2>/dev/null && {
                ((extracted_count++))
                log_info "    Extracted log: $file"
            } || log_warn "    Failed to extract log: $file"
        fi
    done <<< "$log_files"
    
    # Extract Important Config Files
    log_info "  - Extracting important system config files"
    for file in /etc/passwd /etc/group /etc/hosts /etc/resolv.conf /etc/rc.local; do
        local dest_name="$(basename "$file")"
        execute_command "cat '$file' 2>/dev/null" > "$OUTPUT_DIR/extracted/configs/$dest_name" 2>/dev/null && {
            ((extracted_count++))
            log_info "    Extracted: $file"
        } || true
    done
    
    # Document Extraction Summary
    {
        echo "=== File Extraction Summary ==="
        echo "Total files extracted: $extracted_count"
        echo "Total size: $total_size bytes"
        echo "Extraction limit: $MAX_EXTRACT_SIZE bytes"
        echo ""
        echo "=== Extracted Files ==="
        find "$OUTPUT_DIR/extracted" -type f | sed "s|^$OUTPUT_DIR/extracted/||"
    } > "$OUTPUT_DIR/extracted/extraction_summary.txt"
    
    log_success "File extraction complete ($extracted_count files, $total_size bytes)"
}

#######################################
# Vulnerability Checks
#######################################
check_vulnerabilities() {
    log_info "Checking for vulnerabilities..."
    
    # Version Checks
    log_info "  - Checking software versions"
    {
        echo "=== Kernel Version ==="
        if [[ -f "$OUTPUT_DIR/system_info/version.txt" ]]; then
            cat "$OUTPUT_DIR/system_info/version.txt"
        fi
        echo ""
        echo "=== System Information ==="
        if [[ -f "$OUTPUT_DIR/system_info/uname.txt" ]]; then
            cat "$OUTPUT_DIR/system_info/uname.txt"
        fi
        echo ""
        echo "=== Running Services ==="
        if [[ -f "$OUTPUT_DIR/services/running_services.txt" ]]; then
            cat "$OUTPUT_DIR/services/running_services.txt"
        fi
    } > "$OUTPUT_DIR/vulnerabilities/version_checks.txt"
    
    # Credential Checks
    log_info "  - Checking for default/weak credentials"
    {
        echo "=== Default Credential Analysis ==="
        if [[ -f "$OUTPUT_DIR/filesystem/etc_passwd.txt" ]]; then
            echo "User accounts:"
            cat "$OUTPUT_DIR/filesystem/etc_passwd.txt"
            echo ""
        fi
        if [[ -f "$OUTPUT_DIR/filesystem/etc_shadow.txt" ]]; then
            echo "Password hashes:"
            grep -v "^$" "$OUTPUT_DIR/filesystem/etc_shadow.txt" | head -20
            echo ""
            echo "Empty or disabled passwords:"
            grep -E "^\w+::|^\w+:\*:" "$OUTPUT_DIR/filesystem/etc_shadow.txt" 2>/dev/null || echo "None found"
        fi
        echo ""
        echo "=== Known Default Credentials ==="
        echo "From README: root/hellotuya, user/user123"
    } > "$OUTPUT_DIR/vulnerabilities/credential_checks.txt"
    
    # Security Issues Summary
    log_info "  - Compiling security issues"
    {
        echo "=== Security Issues Summary ==="
        echo ""
        echo "=== SUID/SGID Files ==="
        if [[ -f "$OUTPUT_DIR/security/suid_sgid_files.txt" ]]; then
            wc -l < "$OUTPUT_DIR/security/suid_sgid_files.txt" | xargs echo "Count:"
            head -10 "$OUTPUT_DIR/security/suid_sgid_files.txt"
        fi
        echo ""
        echo "=== World-Writable Files ==="
        if [[ -f "$OUTPUT_DIR/security/world_writable.txt" ]]; then
            wc -l < "$OUTPUT_DIR/security/world_writable.txt" | xargs echo "Count:"
            head -10 "$OUTPUT_DIR/security/world_writable.txt"
        fi
        echo ""
        echo "=== Insecure File Permissions in /app ==="
        if [[ -f "$OUTPUT_DIR/security/app_insecure_perms.txt" ]]; then
            wc -l < "$OUTPUT_DIR/security/app_insecure_perms.txt" | xargs echo "Count:"
            head -10 "$OUTPUT_DIR/security/app_insecure_perms.txt"
        fi
        echo ""
        echo "=== Network Exposure ==="
        if [[ -f "$OUTPUT_DIR/network/listening_ports.txt" ]]; then
            echo "Listening ports:"
            head -20 "$OUTPUT_DIR/network/listening_ports.txt"
        fi
        echo ""
        echo "=== Firewall Analysis ==="
        if [[ -f "$OUTPUT_DIR/security/firewall_analysis.txt" ]]; then
            grep -i "WARNING" "$OUTPUT_DIR/security/firewall_analysis.txt" || echo "No obvious firewall issues found"
        fi
    } > "$OUTPUT_DIR/vulnerabilities/security_issues.txt"
    
    # CVE Database Check (if available)
    log_info "  - Checking CVE database"
    if [[ -f "$SCRIPT_DIR/data/cve-database.json" ]]; then
        log_info "    CVE database found, performing checks..."
        # Basic version extraction for CVE matching
        if [[ -f "$OUTPUT_DIR/system_info/version.txt" ]]; then
            {
                echo "=== CVE Database Check ==="
                echo "Kernel version from /proc/version:"
                cat "$OUTPUT_DIR/system_info/version.txt"
                echo ""
                echo "Note: Full CVE matching requires parsing the database file"
                echo "See: $SCRIPT_DIR/data/cve-database.json"
            } > "$OUTPUT_DIR/vulnerabilities/cve_check.txt"
        fi
    else
        log_warn "    CVE database not found at $SCRIPT_DIR/data/cve-database.json"
    fi
    
    log_success "Vulnerability checks complete"
}

#######################################
# Report Generation
#######################################
generate_reports() {
    log_info "Generating reports..."
    
    # Summary Report
    log_info "  - Generating summary report"
    {
        echo "=========================================="
        echo "IoT Internal Device Probing Summary"
        echo "=========================================="
        echo ""
        echo "Target: $TARGET_IP"
        echo "Username: $USERNAME"
        echo "Timestamp: $TS"
        echo "Output Directory: $OUTPUT_DIR"
        echo ""
        echo "=========================================="
        echo "System Information"
        echo "=========================================="
        if [[ -f "$OUTPUT_DIR/system_info/uname.txt" ]]; then
            echo "System: $(head -1 "$OUTPUT_DIR/system_info/uname.txt")"
        fi
        if [[ -f "$OUTPUT_DIR/system_info/version.txt" ]]; then
            echo "Kernel: $(head -1 "$OUTPUT_DIR/system_info/version.txt")"
        fi
        if [[ -f "$OUTPUT_DIR/system_info/uptime.txt" ]]; then
            local uptime_seconds
            uptime_seconds=$(head -1 "$OUTPUT_DIR/system_info/uptime.txt" | awk '{print int($1)}')
            local days=$((uptime_seconds / 86400))
            local hours=$(((uptime_seconds % 86400) / 3600))
            echo "Uptime: ${days}d ${hours}h"
        fi
        echo ""
        echo "=========================================="
        echo "Network Information"
        echo "=========================================="
        if [[ -f "$OUTPUT_DIR/network/interfaces.txt" ]]; then
            echo "Network Interfaces:"
            grep -E "^[a-z]|inet " "$OUTPUT_DIR/network/interfaces.txt" | head -10
        fi
        if [[ -f "$OUTPUT_DIR/network/listening_ports.txt" ]]; then
            echo ""
            echo "Listening Ports:"
            head -10 "$OUTPUT_DIR/network/listening_ports.txt"
        fi
        echo ""
        echo "=========================================="
        echo "Processes"
        echo "=========================================="
        if [[ -f "$OUTPUT_DIR/processes/ps_aux.txt" ]]; then
            echo "Total Processes: $(wc -l < "$OUTPUT_DIR/processes/ps_aux.txt")"
            echo ""
            echo "Top Processes:"
            head -10 "$OUTPUT_DIR/processes/ps_aux.txt"
        fi
        echo ""
        echo "=========================================="
        echo "Application Files"
        echo "=========================================="
        if [[ -f "$OUTPUT_DIR/application/app_files_listing.txt" ]]; then
            echo "Files in /app: $(wc -l < "$OUTPUT_DIR/application/app_files_listing.txt")"
        fi
        echo ""
        echo "=========================================="
        echo "Security Findings"
        echo "=========================================="
        if [[ -f "$OUTPUT_DIR/security/suid_sgid_files.txt" ]]; then
            echo "SUID/SGID Files: $(wc -l < "$OUTPUT_DIR/security/suid_sgid_files.txt")"
        fi
        if [[ -f "$OUTPUT_DIR/security/world_writable.txt" ]]; then
            echo "World-Writable Files: $(wc -l < "$OUTPUT_DIR/security/world_writable.txt")"
        fi
        if [[ -f "$OUTPUT_DIR/vulnerabilities/security_issues.txt" ]]; then
            echo ""
            echo "Key Security Issues:"
            grep -A 2 "Count:" "$OUTPUT_DIR/vulnerabilities/security_issues.txt" | head -20
        fi
        echo ""
        echo "=========================================="
        echo "File Extraction"
        echo "=========================================="
        if [[ -f "$OUTPUT_DIR/extracted/extraction_summary.txt" ]]; then
            head -10 "$OUTPUT_DIR/extracted/extraction_summary.txt"
        fi
        echo ""
        echo "=========================================="
        echo "Output Files"
        echo "=========================================="
        find "$OUTPUT_DIR" -type f | sed "s|^$OUTPUT_DIR/||" | sort
    } > "$OUTPUT_DIR/summary.txt"
    
    # Comprehensive Report
    log_info "  - Generating comprehensive report"
    {
        echo "=========================================="
        echo "IoT Internal Device Probing - Comprehensive Report"
        echo "=========================================="
        echo ""
        echo "Target: $TARGET_IP"
        echo "Username: $USERNAME"
        echo "Timestamp: $TS"
        echo ""
        echo "This report contains detailed information gathered from"
        echo "internal probing of the IoT device via telnet."
        echo ""
        echo "For detailed information, see the individual files in:"
        echo "  $OUTPUT_DIR"
        echo ""
        echo "=========================================="
        echo "Table of Contents"
        echo "=========================================="
        echo "1. System Information"
        echo "2. Process Enumeration"
        echo "3. Network Information"
        echo "4. File System Exploration"
        echo "5. Services and Startup"
        echo "6. Application/Webcam Specific"
        echo "7. Security Assessment"
        echo "8. Vulnerability Checks"
        echo "9. Extracted Files"
        echo ""
        echo "=========================================="
        echo "1. System Information"
        echo "=========================================="
        if [[ -f "$OUTPUT_DIR/system_info/uname.txt" ]]; then
            cat "$OUTPUT_DIR/system_info/uname.txt"
        fi
        echo ""
        if [[ -f "$OUTPUT_DIR/system_info/cpuinfo.txt" ]]; then
            head -20 "$OUTPUT_DIR/system_info/cpuinfo.txt"
        fi
        echo ""
        echo "See: system_info/ for detailed information"
        echo ""
        echo "=========================================="
        echo "2. Process Enumeration"
        echo "=========================================="
        if [[ -f "$OUTPUT_DIR/processes/ps_aux.txt" ]]; then
            head -30 "$OUTPUT_DIR/processes/ps_aux.txt"
        fi
        echo ""
        echo "See: processes/ for detailed information"
        echo ""
        echo "=========================================="
        echo "3. Network Information"
        echo "=========================================="
        if [[ -f "$OUTPUT_DIR/network/interfaces.txt" ]]; then
            head -30 "$OUTPUT_DIR/network/interfaces.txt"
        fi
        echo ""
        if [[ -f "$OUTPUT_DIR/network/listening_ports.txt" ]]; then
            echo "Listening Ports:"
            head -20 "$OUTPUT_DIR/network/listening_ports.txt"
        fi
        echo ""
        echo "See: network/ for detailed information"
        echo ""
        echo "=========================================="
        echo "4. File System Exploration"
        echo "=========================================="
        if [[ -f "$OUTPUT_DIR/filesystem/app_directory_listing.txt" ]]; then
            head -30 "$OUTPUT_DIR/filesystem/app_directory_listing.txt"
        fi
        echo ""
        echo "See: filesystem/ for detailed information"
        echo ""
        echo "=========================================="
        echo "5. Services and Startup"
        echo "=========================================="
        if [[ -f "$OUTPUT_DIR/services/running_services.txt" ]]; then
            cat "$OUTPUT_DIR/services/running_services.txt"
        fi
        echo ""
        echo "See: services/ for detailed information"
        echo ""
        echo "=========================================="
        echo "6. Application/Webcam Specific"
        echo "=========================================="
        if [[ -f "$OUTPUT_DIR/application/app_files_listing.txt" ]]; then
            head -30 "$OUTPUT_DIR/application/app_files_listing.txt"
        fi
        echo ""
        echo "See: application/ for detailed information"
        echo ""
        echo "=========================================="
        echo "7. Security Assessment"
        echo "=========================================="
        if [[ -f "$OUTPUT_DIR/vulnerabilities/security_issues.txt" ]]; then
            cat "$OUTPUT_DIR/vulnerabilities/security_issues.txt"
        fi
        echo ""
        echo "See: security/ and vulnerabilities/ for detailed information"
        echo ""
        echo "=========================================="
        echo "8. Vulnerability Checks"
        echo "=========================================="
        if [[ -f "$OUTPUT_DIR/vulnerabilities/version_checks.txt" ]]; then
            head -30 "$OUTPUT_DIR/vulnerabilities/version_checks.txt"
        fi
        echo ""
        echo "See: vulnerabilities/ for detailed information"
        echo ""
        echo "=========================================="
        echo "9. Extracted Files"
        echo "=========================================="
        if [[ -f "$OUTPUT_DIR/extracted/extraction_summary.txt" ]]; then
            cat "$OUTPUT_DIR/extracted/extraction_summary.txt"
        fi
        echo ""
        echo "See: extracted/ for all extracted files"
        echo ""
        echo "=========================================="
        echo "End of Report"
        echo "=========================================="
    } > "$OUTPUT_DIR/comprehensive_report.txt"
    
    log_success "Report generation complete"
}

#######################################
# Main Execution Flow
#######################################
main() {
    log_info "=========================================="
    log_info "IoT Internal Device Probing"
    log_info "=========================================="
    log_info "Target: $TARGET_IP"
    log_info "Username: $USERNAME"
    log_info "Output Directory: $OUTPUT_DIR"
    log_info "=========================================="
    echo ""
    
    # Test connection
    log_info "Testing telnet connection..."
    if ! execute_command "echo 'Connection test'" >/dev/null 2>&1; then
        log_error "Failed to connect to $TARGET_IP:$TELNET_PORT"
        log_error "Please verify:"
        log_error "  - Target IP is correct"
        log_error "  - Telnet service is running"
        log_error "  - Credentials are correct"
        exit 1
    fi
    log_success "Connection successful"
    echo ""
    
    # Execute all probing functions
    gather_system_info
    echo ""
    
    enumerate_processes
    echo ""
    
    gather_network_info
    echo ""
    
    explore_filesystem
    echo ""
    
    enumerate_services
    echo ""
    
    enumerate_application
    echo ""
    
    assess_security
    echo ""
    
    extract_files
    echo ""
    
    check_vulnerabilities
    echo ""
    
    generate_reports
    echo ""
    
    # Generate HTML report
    log_info "Generating HTML report..."
    if [[ -f "${SCRIPT_DIR}/iot-internal-report-generator.sh" ]]; then
        bash "${SCRIPT_DIR}/iot-internal-report-generator.sh" "$OUTPUT_DIR" "$TARGET_IP" "$TS" || log_warn "HTML report generation failed"
    else
        log_warn "HTML report generator not found at ${SCRIPT_DIR}/iot-internal-report-generator.sh"
    fi
    echo ""
    
    log_info "=========================================="
    log_success "Internal probing complete!"
    log_info "=========================================="
    log_info "Results saved to: $OUTPUT_DIR"
    log_info "Summary report: $OUTPUT_DIR/summary.txt"
    log_info "Comprehensive report: $OUTPUT_DIR/comprehensive_report.txt"
    log_info "HTML report: $OUTPUT_DIR/index.html"
    log_info "=========================================="
}

# Run main function
main "$@"

