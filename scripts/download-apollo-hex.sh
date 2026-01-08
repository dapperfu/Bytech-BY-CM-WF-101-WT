#!/usr/bin/env bash
set -euo pipefail

# Download using hexdump (more reliable for binary files)
source scripts/expect-helper.sh

TARGET_IP="${1:-10.0.0.227}"
USERNAME="${2:-root}"
PASSWORD="${3:-hellotuya}"
REMOTE_FILE="${4:-/app/abin/apollo}"
LOCAL_FILE="${5:-./apollo-binary}"

echo "[*] Downloading $REMOTE_FILE from $TARGET_IP using hexdump method..."

# Get file size first
echo "[*] Getting file size..."
size_output=$(expect_execute "$TARGET_IP" "$USERNAME" "$PASSWORD" "wc -c < $REMOTE_FILE")
file_size=$(echo "$size_output" | grep -oE '[0-9]+' | head -1)

if [[ -z "$file_size" ]] || [[ "$file_size" -lt 100 ]]; then
    echo "[!] Error: Failed to get file size or file too small"
    exit 1
fi

echo "[*] File size: $file_size bytes"

# Use od (octal dump) to convert binary to text, then convert back
# od -A x -t x1z -v outputs hex in a format we can parse
echo "[*] Converting binary to hex on remote device..."
hex_output=$(expect_execute "$TARGET_IP" "$USERNAME" "$PASSWORD" "od -A x -t x1z -v $REMOTE_FILE | head -1000")

# For now, let's try a different approach - use base64 but with a simpler method
# Split into smaller base64 files
echo "[*] Trying base64 with split method..."

# Create a script on remote that splits the base64
split_script=$(cat <<'REMOTE_SCRIPT'
#!/bin/sh
base64 /app/abin/apollo > /tmp/apollo_b64.txt
split -b 50000 /tmp/apollo_b64.txt /tmp/apollo_b64_part_
ls -1 /tmp/apollo_b64_part_* | wc -l
REMOTE_SCRIPT
)

# Upload the split script
echo "[*] Creating split script on remote..."
expect_execute "$TARGET_IP" "$USERNAME" "$PASSWORD" "cat > /tmp/split_base64.sh << 'EOF'
base64 $REMOTE_FILE > /tmp/apollo_b64.txt
split -b 50000 /tmp/apollo_b64.txt /tmp/apollo_b64_part_ 2>/dev/null || (echo 'SPLIT_FAILED'; exit 1)
ls -1 /tmp/apollo_b64_part_* 2>/dev/null | wc -l
EOF
chmod +x /tmp/split_base64.sh" >/dev/null

# Run split script
echo "[*] Running split script..."
num_parts_output=$(expect_execute "$TARGET_IP" "$USERNAME" "$PASSWORD" "/tmp/split_base64.sh")
num_parts=$(echo "$num_parts_output" | grep -oE '[0-9]+' | head -1)

if [[ -z "$num_parts" ]] || [[ "$num_parts" -eq 0 ]]; then
    echo "[!] Error: Failed to split file"
    exit 1
fi

echo "[*] File split into $num_parts parts"

# Download each part
temp_parts_dir=$(mktemp -d)
trap "rm -rf $temp_parts_dir" EXIT

for ((i=0; i<num_parts; i++)); do
    part_file="/tmp/apollo_b64_part_$(printf "%02d" $i)"
    if [[ $i -eq 0 ]]; then
        part_file="/tmp/apollo_b64_part_aa"
    fi
    
    echo "[*] Downloading part $((i+1))/$num_parts..."
    
    part_output=$(expect_execute "$TARGET_IP" "$USERNAME" "$PASSWORD" "cat $part_file 2>/dev/null || echo 'PART_NOT_FOUND'")
    
    if echo "$part_output" | grep -q "PART_NOT_FOUND"; then
        # Try with different naming (split uses aa, ab, ac...)
        part_name=$(printf "%02x" $i | sed 's/\(..\)/\\x\1/g')
        part_file="/tmp/apollo_b64_part_$(printf "%c%c" $((97+i/26)) $((97+i%26)))"
        part_output=$(expect_execute "$TARGET_IP" "$USERNAME" "$PASSWORD" "cat $part_file 2>/dev/null || echo 'PART_NOT_FOUND'")
    fi
    
    if echo "$part_output" | grep -q "PART_NOT_FOUND"; then
        echo "[!] Warning: Part $i not found, trying to list files..."
        list_output=$(expect_execute "$TARGET_IP" "$USERNAME" "$PASSWORD" "ls -1 /tmp/apollo_b64_part_* 2>/dev/null")
        echo "[*] Available parts: $list_output"
        continue
    fi
    
    # Clean output
    part_data=$(echo "$part_output" | \
        grep -v "^cat " | \
        grep -v "^\[/app\]" | \
        grep -v "^#" | \
        grep -v "^\$" | \
        grep -v "^$" | \
        grep -v "PART_NOT_FOUND" | \
        tr -d '\r\n')
    
    if [[ -n "$part_data" ]]; then
        echo -n "$part_data" >> "$temp_parts_dir/combined.b64"
    fi
done

# Decode
echo "[*] Decoding combined base64..."
if ! base64 -d "$temp_parts_dir/combined.b64" > "$LOCAL_FILE" 2>/dev/null; then
    if ! base64 -d < "$temp_parts_dir/combined.b64" > "$LOCAL_FILE" 2>/dev/null; then
        echo "[!] Error: Failed to decode base64"
        echo "[*] Combined file size: $(wc -c < $temp_parts_dir/combined.b64)"
        exit 1
    fi
fi

# Clean up remote
expect_execute "$TARGET_IP" "$USERNAME" "$PASSWORD" "rm -f /tmp/apollo_b64.txt /tmp/apollo_b64_part_* /tmp/split_base64.sh" >/dev/null

# Verify
if [[ ! -f "$LOCAL_FILE" ]] || [[ ! -s "$LOCAL_FILE" ]]; then
    echo "[!] Error: Downloaded file is empty"
    exit 1
fi

file_size_local=$(stat -f%z "$LOCAL_FILE" 2>/dev/null || stat -c%s "$LOCAL_FILE" 2>/dev/null)
echo "[+] Success! Downloaded to $LOCAL_FILE ($file_size_local bytes)"
echo "[*] Expected size: $file_size bytes, Actual: $file_size_local bytes"
