#!/usr/bin/env bash
set -euo pipefail

#######################################
# Hello World Transfer and Run Script
# Transfers compiled binaries to target device and executes them
#######################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_IP="${1:-10.0.0.227}"
USERNAME="${2:-root}"
PASSWORD="${3:-hellotuya}"
TRANSFER_ONLY="${4:-}"

TELNET_PORT="${TELNET_PORT:-23}"
COMMAND_TIMEOUT="${COMMAND_TIMEOUT:-30}"
TARGET_DIR="/tmp"
BIN_DIR="$SCRIPT_DIR/bin"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[*]${NC} $*"
}

log_error() {
    echo -e "${RED}[!]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $*"
}

log_success() {
    echo -e "${BLUE}[+]${NC} $*"
}

# Check if expect is available
if ! command -v expect &> /dev/null; then
    log_error "expect is not installed"
    log_info "Install with: apt-get install expect  or  yum install expect"
    exit 1
fi

# Check if binaries exist
if [[ ! -d "$BIN_DIR" ]] || [[ -z "$(ls -A "$BIN_DIR" 2>/dev/null)" ]]; then
    log_error "No binaries found in $BIN_DIR"
    log_info "Run ./build.sh first to build the projects"
    exit 1
fi

# Expect-based telnet command execution
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
        expect "# "
        set output \$expect_out(buffer)
        puts \$output
        send "exit\r"
        expect eof
    }
    "$ " {
        send "$cmd\r"
        expect "$ "
        set output \$expect_out(buffer)
        puts \$output
        send "exit\r"
        expect eof
    }
    timeout {
        puts "ERROR: Connection timeout"
        exit 1
    }
    eof {
        puts "ERROR: Connection closed"
        exit 1
    }
}
EOF
)
    expect <<< "$expect_script" 2>/dev/null | grep -v "^spawn telnet" | grep -v "^$" | tail -n +2 | head -n -1
}

# Test telnet connectivity
test_connectivity() {
    log_info "Testing telnet connectivity to $TARGET_IP:$TELNET_PORT..."
    if execute_command "echo 'Connection test'" &>/dev/null; then
        log_success "Telnet connection successful"
        return 0
    else
        log_error "Failed to connect via telnet"
        return 1
    fi
}

# Detect available transfer methods
detect_transfer_method() {
    log_info "Detecting available transfer methods..."
    
    # Check for zmodem (rz command)
    if execute_command "which rz" &>/dev/null | grep -q "rz"; then
        log_success "zmodem (rz) available"
        echo "zmodem"
        return 0
    fi
    
    # Check for SSH/SCP
    if timeout 2 bash -c "nc -z $TARGET_IP 22" &>/dev/null; then
        log_success "SSH/SCP available"
        echo "scp"
        return 0
    fi
    
    # Check for wget
    if execute_command "which wget" &>/dev/null | grep -q "wget"; then
        log_success "wget available (HTTP method possible)"
        echo "http"
        return 0
    fi
    
    # Check for base64 (fallback)
    if execute_command "which base64" &>/dev/null | grep -q "base64"; then
        log_warn "Only base64 available (limited method)"
        echo "base64"
        return 0
    fi
    
    log_error "No suitable transfer method found"
    return 1
}

# Transfer using zmodem
transfer_zmodem() {
    local binary="$1"
    local target_name="$2"
    
    log_info "Transferring $binary via zmodem..."
    
    if ! command -v sz &>/dev/null; then
        log_error "sz command not found (install lrzsz package)"
        return 1
    fi
    
    local expect_script=$(cat <<EOF
set timeout 60
log_user 0
spawn telnet $TARGET_IP $TELNET_PORT
expect {
    "login:" { send "$USERNAME\r"; exp_continue }
    "Login:" { send "$USERNAME\r"; exp_continue }
    "Password:" { send "$PASSWORD\r"; exp_continue }
    "password:" { send "$PASSWORD\r"; exp_continue }
    "# " {
        send "cd $TARGET_DIR\r"
        expect "# "
        send "rz\r"
        expect {
            "rz waiting" {
                spawn sz "$binary"
                expect eof
            }
            "**B0100" {
                spawn sz "$binary"
                expect eof
            }
        }
        expect "# "
        send "mv $binary $target_name\r"
        expect "# "
        send "chmod +x $target_name\r"
        expect "# "
        send "exit\r"
        expect eof
    }
    "$ " {
        send "cd $TARGET_DIR\r"
        expect "$ "
        send "rz\r"
        expect {
            "rz waiting" {
                spawn sz "$binary"
                expect eof
            }
            "**B0100" {
                spawn sz "$binary"
                expect eof
            }
        }
        expect "$ "
        send "mv $binary $target_name\r"
        expect "$ "
        send "chmod +x $target_name\r"
        expect "$ "
        send "exit\r"
        expect eof
    }
}
EOF
)
    expect <<< "$expect_script" &>/dev/null
}

# Transfer using SCP
transfer_scp() {
    local binary="$1"
    local target_name="$2"
    
    log_info "Transferring $binary via SCP..."
    
    # Try SCP with password (using sshpass if available, or expect)
    if command -v sshpass &>/dev/null; then
        sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no "$binary" "$USERNAME@$TARGET_IP:$TARGET_DIR/$target_name" &>/dev/null || return 1
    else
        # Use expect for SCP
        local expect_script=$(cat <<EOF
set timeout 30
spawn scp -o StrictHostKeyChecking=no "$binary" $USERNAME@$TARGET_IP:$TARGET_DIR/$target_name
expect {
    "password:" { send "$PASSWORD\r"; exp_continue }
    "Password:" { send "$PASSWORD\r"; exp_continue }
    eof
}
EOF
)
        expect <<< "$expect_script" &>/dev/null || return 1
    fi
    
    # Make executable
    execute_command "chmod +x $TARGET_DIR/$target_name" &>/dev/null
}

# Transfer using HTTP (wget)
transfer_http() {
    local binary="$1"
    local target_name="$2"
    
    log_info "Transferring $binary via HTTP (wget)..."
    
    # Get host IP (simplified - assumes same network)
    local host_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}' || echo "127.0.0.1")
    local binary_name=$(basename "$binary")
    local http_port=8000
    
    # Start HTTP server in background
    log_info "Starting HTTP server on port $http_port..."
    cd "$(dirname "$binary")"
    python3 -m http.server "$http_port" >/dev/null 2>&1 &
    local server_pid=$!
    sleep 2
    
    # Download on target
    local download_cmd="wget http://$host_ip:$http_port/$binary_name -O $TARGET_DIR/$target_name"
    if ! execute_command "$download_cmd" &>/dev/null; then
        kill $server_pid 2>/dev/null
        return 1
    fi
    
    # Stop server
    kill $server_pid 2>/dev/null
    wait $server_pid 2>/dev/null
    
    # Make executable
    execute_command "chmod +x $TARGET_DIR/$target_name" &>/dev/null
}

# Transfer using base64 (fallback)
transfer_base64() {
    local binary="$1"
    local target_name="$2"
    
    log_info "Transferring $binary via base64 (fallback method)..."
    
    # Check file size (base64 has limitations)
    local file_size=$(stat -f%z "$binary" 2>/dev/null || stat -c%s "$binary" 2>/dev/null)
    if [[ $file_size -gt 100000 ]]; then
        log_warn "File is large ($file_size bytes), base64 transfer may fail"
    fi
    
    # Encode to base64
    local b64_file="${binary}.b64"
    base64 "$binary" > "$b64_file"
    
    # Transfer base64 string via telnet
    local b64_content=$(cat "$b64_file")
    local expect_script=$(cat <<EOF
set timeout 120
log_user 0
spawn telnet $TARGET_IP $TELNET_PORT
expect {
    "login:" { send "$USERNAME\r"; exp_continue }
    "Login:" { send "$USERNAME\r"; exp_continue }
    "Password:" { send "$PASSWORD\r"; exp_continue }
    "password:" { send "$PASSWORD\r"; exp_continue }
    "# " {
        send "cd $TARGET_DIR\r"
        expect "# "
        send "cat > $target_name.b64 <<'EOFB64'\r"
        expect "# "
        send "$b64_content\r"
        expect "# "
        send "EOFB64\r"
        expect "# "
        send "base64 -d < $target_name.b64 > $target_name\r"
        expect "# "
        send "chmod +x $target_name\r"
        expect "# "
        send "rm $target_name.b64\r"
        expect "# "
        send "exit\r"
        expect eof
    }
    "$ " {
        send "cd $TARGET_DIR\r"
        expect "$ "
        send "cat > $target_name.b64 <<'EOFB64'\r"
        expect "$ "
        send "$b64_content\r"
        expect "$ "
        send "EOFB64\r"
        expect "$ "
        send "base64 -d < $target_name.b64 > $target_name\r"
        expect "$ "
        send "chmod +x $target_name\r"
        expect "$ "
        send "rm $target_name.b64\r"
        expect "$ "
        send "exit\r"
        expect eof
    }
}
EOF
)
    expect <<< "$expect_script" &>/dev/null
    
    # Cleanup
    rm -f "$b64_file"
}

# Transfer binary using detected method
transfer_binary() {
    local binary="$1"
    local target_name="$2"
    local method="$3"
    
    case "$method" in
        zmodem)
            transfer_zmodem "$binary" "$target_name"
            ;;
        scp)
            transfer_scp "$binary" "$target_name"
            ;;
        http)
            transfer_http "$binary" "$target_name"
            ;;
        base64)
            transfer_base64 "$binary" "$target_name"
            ;;
        *)
            log_error "Unknown transfer method: $method"
            return 1
            ;;
    esac
}

# Execute binary on target
run_binary() {
    local target_name="$1"
    log_info "Executing $target_name on target..."
    
    local output=$(execute_command "$TARGET_DIR/$target_name" 10)
    echo "$output" | grep -v "^spawn" | grep -v "^$" | tail -n +2
}

# Main execution
main() {
    log_info "Hello World Transfer and Run Script"
    log_info "Target: $TARGET_IP"
    log_info "User: $USERNAME"
    echo
    
    # Test connectivity
    if ! test_connectivity; then
        exit 1
    fi
    
    # Detect transfer method
    local method=$(detect_transfer_method)
    if [[ -z "$method" ]]; then
        exit 1
    fi
    
    log_info "Using transfer method: $method"
    echo
    
    # Transfer and run each binary
    for binary in "$BIN_DIR"/*; do
        if [[ -f "$binary" ]] && [[ -x "$binary" ]]; then
            local binary_name=$(basename "$binary")
            local target_name="hello_${binary_name}"
            
            log_info "Processing: $binary_name"
            
            if transfer_binary "$binary" "$target_name" "$method"; then
                log_success "Transfer successful: $target_name"
                
                if [[ "$TRANSFER_ONLY" != "--transfer-only" ]]; then
                    echo
                    log_info "Output from $target_name:"
                    echo "----------------------------------------"
                    run_binary "$target_name"
                    echo "----------------------------------------"
                    echo
                fi
            else
                log_error "Transfer failed: $binary_name"
            fi
        fi
    done
    
    log_success "Transfer complete!"
}

main

