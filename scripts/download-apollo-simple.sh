#!/usr/bin/env bash
set -euo pipefail

# Simple download script using expect-helper
source scripts/expect-helper.sh

TARGET_IP="${1:-10.0.0.227}"
USERNAME="${2:-root}"
PASSWORD="${3:-hellotuya}"
REMOTE_FILE="${4:-/app/abin/apollo}"
LOCAL_FILE="${5:-./apollo-binary}"

echo "[*] Downloading $REMOTE_FILE from $TARGET_IP..."

# First, encode to base64 on remote and save to file
echo "[*] Encoding file on remote device..."
expect_execute "$TARGET_IP" "$USERNAME" "$PASSWORD" "base64 $REMOTE_FILE > /tmp/apollo_dl.b64 && echo 'ENCODED' || echo 'ENCODE_FAILED'"

# Get the base64 file size to know how to read it
echo "[*] Getting file size..."
file_size=$(expect_execute "$TARGET_IP" "$USERNAME" "$PASSWORD" "wc -c < /tmp/apollo_dl.b64" | grep -E '^[0-9]+$' | head -1)
echo "[*] Base64 file size: $file_size bytes"

if [[ -z "$file_size" ]] || [[ "$file_size" -lt 100 ]]; then
    echo "[!] Error: Failed to get file size or file too small"
    exit 1
fi

# Read the base64 file in chunks (expect has buffer limits)
# For large files, we'll need to read in multiple passes
echo "[*] Reading base64 content..."
base64_content=""

# Try reading the entire file
output=$(expect_execute "$TARGET_IP" "$USERNAME" "$PASSWORD" "cat /tmp/apollo_dl.b64")

# Extract base64 from output (remove command echo, prompts, etc.)
base64_content=$(echo "$output" | \
    grep -v "^cat /tmp/apollo_dl.b64" | \
    grep -v "^\[/app\]" | \
    grep -v "^#" | \
    grep -v "^\$" | \
    grep -v "^$" | \
    tr -d '\r\n' | \
    head -c "$file_size")

if [[ -z "$base64_content" ]] || [[ ${#base64_content} -lt 100 ]]; then
    echo "[!] Error: Failed to extract base64 content"
    echo "[*] Output length: ${#base64_content}"
    echo "[*] First 200 chars: ${output:0:200}"
    exit 1
fi

echo "[*] Extracted base64 content (${#base64_content} characters)"

# Save to temp file
temp_b64=$(mktemp)
echo -n "$base64_content" > "$temp_b64"

# Decode
echo "[*] Decoding base64..."
if ! base64 -d "$temp_b64" > "$LOCAL_FILE" 2>/dev/null; then
    if ! base64 -d < "$temp_b64" > "$LOCAL_FILE" 2>/dev/null; then
        echo "[!] Error: Failed to decode base64"
        rm -f "$temp_b64"
        exit 1
    fi
fi

rm -f "$temp_b64"

# Clean up remote file
expect_execute "$TARGET_IP" "$USERNAME" "$PASSWORD" "rm -f /tmp/apollo_dl.b64" >/dev/null

# Verify
if [[ ! -f "$LOCAL_FILE" ]] || [[ ! -s "$LOCAL_FILE" ]]; then
    echo "[!] Error: Downloaded file is empty"
    exit 1
fi

file_size_local=$(stat -f%z "$LOCAL_FILE" 2>/dev/null || stat -c%s "$LOCAL_FILE" 2>/dev/null)
echo "[+] Success! Downloaded to $LOCAL_FILE ($file_size_local bytes)"
