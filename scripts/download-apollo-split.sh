#!/usr/bin/env bash
set -euo pipefail

# Download by splitting base64 on remote and downloading chunks
TARGET_IP="${1:-10.0.0.227}"
USERNAME="${2:-root}"
PASSWORD="${3:-hellotuya}"
REMOTE_FILE="${4:-/app/abin/apollo}"
LOCAL_FILE="${5:-./apollo-binary}"

CHUNK_SIZE=40000  # 40KB chunks (smaller for reliability)

echo "[*] Downloading $REMOTE_FILE from $TARGET_IP..."

# Use expect directly with a simpler script
temp_expect=$(mktemp)
cat > "$temp_expect" <<'EXPECT_BASE'
set timeout 30
log_user 0

spawn telnet TARGET_IP_VAL 23
expect {
    "login:" { send "USERNAME_VAL\r"; exp_continue }
    "Login:" { send "USERNAME_VAL\r"; exp_continue }
    "Username:" { send "USERNAME_VAL\r"; exp_continue }
    "Password:" { send "PASSWORD_VAL\r"; exp_continue }
    "password:" { send "PASSWORD_VAL\r"; exp_continue }
    "# " {}
    "$ " {}
    timeout { exit 1 }
    eof { exit 1 }
}

# Command to execute
send "COMMAND_VAL\r"
expect {
    timeout { exit 1 }
}

# Capture output until prompt
set output ""
expect {
    -re "(.+)" {
        append output $expect_out(buffer)
        exp_continue
    }
    "# " {
        set output [string trimright $output "# "]
    }
    "$ " {
        set output [string trimright $output "$ "]
    }
    timeout {
        # Got what we can
    }
}

send "exit\r"
expect eof

puts $output
EXPECT_BASE

# Function to execute command via expect
expect_cmd() {
    local cmd="$1"
    local temp_script=$(mktemp)
    # Escape special characters in command for sed
    local cmd_escaped=$(echo "$cmd" | sed 's/[[\.*^$()+?{|]/\\&/g' | sed "s/|/\\|/g")
    sed "s|TARGET_IP_VAL|$TARGET_IP|g; s|USERNAME_VAL|$USERNAME|g; s|PASSWORD_VAL|$PASSWORD|g; s|COMMAND_VAL|$cmd_escaped|g" "$temp_expect" > "$temp_script"
    local result=$(expect -f "$temp_script" 2>&1)
    rm -f "$temp_script"
    echo "$result" | grep -v "^spawn telnet" | grep -v "^Trying" | grep -v "^Connected" | \
        grep -v "login:" | grep -v "Login:" | grep -v "Username:" | grep -v "Password:" | \
        grep -v "password:" | grep -v "^\[/app\]" | grep -v "^#" | grep -v "^\$" | \
        grep -v "^exit" | grep -v "^$" | tr -d '\r' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//'
}

# Step 1: Encode to base64
echo "[*] Step 1: Encoding file to base64 on remote device..."
result=$(expect_cmd "base64 $REMOTE_FILE > /tmp/apollo_b64.txt 2>&1 && echo 'ENCODED' || echo 'FAILED'")
if echo "$result" | grep -q "FAILED"; then
    echo "[!] Error: Failed to encode file"
    echo "$result"
    rm -f "$temp_expect"
    exit 1
fi

# Step 2: Get size and calculate chunks
echo "[*] Step 2: Getting file size..."
size_result=$(expect_cmd "wc -c < /tmp/apollo_b64.txt")
file_size=$(echo "$size_result" | grep -oE '[0-9]+' | head -1)

if [[ -z "$file_size" ]] || [[ "$file_size" -lt 100 ]]; then
    echo "[!] Error: Failed to get file size"
    echo "Size result: $size_result"
    rm -f "$temp_expect"
    exit 1
fi

num_chunks=$(( (file_size + CHUNK_SIZE - 1) / CHUNK_SIZE ))
echo "[*] Base64 size: $file_size bytes, will download in $num_chunks chunks"

# Step 3: Download chunks
echo "[*] Step 3: Downloading chunks..."
temp_dir=$(mktemp -d)
trap "rm -rf $temp_dir $temp_expect" EXIT

for ((i=0; i<num_chunks; i++)); do
    start=$((i * CHUNK_SIZE))
    end=$((start + CHUNK_SIZE))
    
    echo "[*] Downloading chunk $((i+1))/$num_chunks (offset $start)..."
    
    # Use dd to extract chunk
    chunk_result=$(expect_cmd "dd if=/tmp/apollo_b64.txt bs=1 skip=$start count=$CHUNK_SIZE 2>/dev/null | tr -d '\n'")
    
    # Clean the chunk
    chunk_clean=$(echo "$chunk_result" | grep -v "^dd if=" | grep -v "^[0-9]*+[0-9]*" | tr -d '\n' | head -c $CHUNK_SIZE)
    
    if [[ -n "$chunk_clean" ]]; then
        echo -n "$chunk_clean" >> "$temp_dir/combined.b64"
        echo "  Got $(echo -n "$chunk_clean" | wc -c) bytes"
    else
        echo "[!] Warning: Chunk $i is empty"
    fi
done

# Step 4: Decode
echo "[*] Step 4: Decoding base64..."
combined_size=$(wc -c < "$temp_dir/combined.b64")
echo "[*] Combined size: $combined_size bytes (expected ~$file_size)"

if ! base64 -d "$temp_dir/combined.b64" > "$LOCAL_FILE" 2>/dev/null; then
    if ! base64 -d < "$temp_dir/combined.b64" > "$LOCAL_FILE" 2>/dev/null; then
        echo "[!] Error: Failed to decode base64"
        echo "[*] First 200 chars of combined file:"
        head -c 200 "$temp_dir/combined.b64"
        echo ""
        exit 1
    fi
fi

# Clean up remote
expect_cmd "rm -f /tmp/apollo_b64.txt" >/dev/null

# Verify
if [[ ! -f "$LOCAL_FILE" ]] || [[ ! -s "$LOCAL_FILE" ]]; then
    echo "[!] Error: Downloaded file is empty"
    exit 1
fi

file_size_local=$(stat -f%z "$LOCAL_FILE" 2>/dev/null || stat -c%s "$LOCAL_FILE" 2>/dev/null)
echo "[+] Success! Downloaded to $LOCAL_FILE ($file_size_local bytes)"
