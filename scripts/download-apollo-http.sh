#!/usr/bin/env bash
set -euo pipefail

# Download using HTTP server (device uploads to us)
source scripts/expect-helper.sh

TARGET_IP="${1:-10.0.0.227}"
USERNAME="${2:-root}"
PASSWORD="${3:-hellotuya}"
REMOTE_FILE="${4:-/app/abin/apollo}"
LOCAL_FILE="${5:-./apollo-binary}"

# Get local IP that device can reach
LOCAL_IP=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' | head -1)
if [[ -z "$LOCAL_IP" ]]; then
    LOCAL_IP=$(hostname -I | awk '{print $1}')
fi

HTTP_PORT=8888

echo "[*] Downloading $REMOTE_FILE from $TARGET_IP..."
echo "[*] Local IP: $LOCAL_IP, Port: $HTTP_PORT"

# Start simple HTTP server in background
echo "[*] Starting HTTP server..."
python3 -m http.server $HTTP_PORT > /tmp/http_server.log 2>&1 &
HTTP_PID=$!
trap "kill $HTTP_PID 2>/dev/null; rm -f /tmp/apollo_download.b64" EXIT

sleep 2

# Create a script on remote that base64 encodes and uploads
echo "[*] Creating upload script on remote device..."
upload_script=$(cat <<REMOTE_SCRIPT
base64 $REMOTE_FILE > /tmp/apollo_upload.b64
wget http://$LOCAL_IP:$HTTP_PORT/ -O /dev/null --post-file=/tmp/apollo_upload.b64 --header="Content-Type: application/octet-stream" 2>&1 || curl -X POST http://$LOCAL_IP:$HTTP_PORT/ -d @/tmp/apollo_upload.b64 2>&1 || echo 'UPLOAD_FAILED'
rm -f /tmp/apollo_upload.b64
REMOTE_SCRIPT
)

# Actually, wget/curl POST won't work with simple HTTP server
# Let's use a different approach - have device serve the file via HTTP

# Check if device has HTTP server capability
echo "[*] Checking if device can serve file via HTTP..."

# Try using netcat or creating a simple server on device
# For now, let's try the simplest: use base64 and transfer via expect but with better buffering

echo "[*] Using improved base64 transfer method..."

# Create expect script that handles large output better
temp_expect=$(mktemp)
cat > "$temp_expect" <<'EXPECT_SCRIPT'
set timeout 120
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
    timeout { puts "CONNECTION_TIMEOUT"; exit 1 }
    eof { puts "CONNECTION_CLOSED"; exit 1 }
}

# Encode to base64 and save to file
send "base64 REMOTE_FILE_VAL > /tmp/apollo_final.b64 2>&1\r"
expect {
    "# " {}
    "$ " {}
    timeout { puts "ENCODE_TIMEOUT"; exit 1 }
}

# Output the file using cat, but we'll capture it differently
send "cat /tmp/apollo_final.b64\r"
expect {
    timeout { puts "READ_TIMEOUT"; exit 1 }
}

# We need to capture all output until prompt
set output ""
expect {
    -re "(.+)" {
        append output $expect_out(buffer)
        exp_continue
    }
    "# " {
        # Got prompt, we're done
    }
    "$ " {
        # Got prompt, we're done  
    }
    timeout {
        # Timeout, but we might have data
    }
}

# Clean up
send "rm -f /tmp/apollo_final.b64\r"
expect {
    "# " {}
    "$ " {}
    timeout {}
}

send "exit\r"
expect eof

# Output the base64 content
puts $output
EXPECT_SCRIPT

sed -i "s|TARGET_IP_VAL|$TARGET_IP|g" "$temp_expect"
sed -i "s|USERNAME_VAL|$USERNAME|g" "$temp_expect"
sed -i "s|PASSWORD_VAL|$PASSWORD|g" "$temp_expect"
sed -i "s|REMOTE_FILE_VAL|$REMOTE_FILE|g" "$temp_expect"

echo "[*] Running expect script (this may take a minute for large files)..."
result=$(expect -f "$temp_expect" 2>&1)
rm -f "$temp_expect"

# Kill HTTP server
kill $HTTP_PID 2>/dev/null || true

# Extract base64 from result
base64_content=$(echo "$result" | \
    grep -v "^spawn telnet" | \
    grep -v "^Trying" | \
    grep -v "^Connected" | \
    grep -v "login:" | \
    grep -v "Login:" | \
    grep -v "Username:" | \
    grep -v "Password:" | \
    grep -v "password:" | \
    grep -v "base64 " | \
    grep -v "cat /tmp/apollo_final.b64" | \
    grep -v "rm -f /tmp/apollo_final.b64" | \
    grep -v "^\[/app\]" | \
    grep -v "^#" | \
    grep -v "^\$" | \
    grep -v "^exit" | \
    grep -v "CONNECTION" | \
    grep -v "TIMEOUT" | \
    grep -v "^$" | \
    tr -d '\r\n' | \
    sed 's/^[[:space:]]*//' | \
    sed 's/[[:space:]]*$//')

if [[ -z "$base64_content" ]] || [[ ${#base64_content} -lt 1000 ]]; then
    echo "[!] Error: Failed to extract base64 content"
    echo "[*] Output length: ${#base64_content}"
    echo "[*] First 500 chars of raw output:"
    echo "$result" | head -20
    exit 1
fi

echo "[*] Extracted base64 (${#base64_content} characters)"

# Save and decode
temp_b64=$(mktemp)
echo -n "$base64_content" > "$temp_b64"

echo "[*] Decoding base64..."
if ! base64 -d "$temp_b64" > "$LOCAL_FILE" 2>/dev/null; then
    if ! base64 -d < "$temp_b64" > "$LOCAL_FILE" 2>/dev/null; then
        echo "[!] Error: Failed to decode base64"
        echo "[*] Base64 file size: $(wc -c < $temp_b64)"
        echo "[*] First 200 chars: $(head -c 200 $temp_b64)"
        rm -f "$temp_b64"
        exit 1
    fi
fi

rm -f "$temp_b64"

# Verify
if [[ ! -f "$LOCAL_FILE" ]] || [[ ! -s "$LOCAL_FILE" ]]; then
    echo "[!] Error: Downloaded file is empty"
    exit 1
fi

file_size_local=$(stat -f%z "$LOCAL_FILE" 2>/dev/null || stat -c%s "$LOCAL_FILE" 2>/dev/null)
echo "[+] Success! Downloaded to $LOCAL_FILE ($file_size_local bytes)"
