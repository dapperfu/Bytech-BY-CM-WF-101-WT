#!/usr/bin/env bash
set -euo pipefail

# Chunked download script for large files
source scripts/expect-helper.sh

TARGET_IP="${1:-10.0.0.227}"
USERNAME="${2:-root}"
PASSWORD="${3:-hellotuya}"
REMOTE_FILE="${4:-/app/abin/apollo}"
LOCAL_FILE="${5:-./apollo-binary}"

CHUNK_SIZE=50000  # 50KB chunks

echo "[*] Downloading $REMOTE_FILE from $TARGET_IP..."

# Step 1: Encode to base64 on remote
echo "[*] Step 1/4: Encoding file on remote device..."
result=$(expect_execute "$TARGET_IP" "$USERNAME" "$PASSWORD" "base64 $REMOTE_FILE > /tmp/apollo_dl.b64 2>&1 && echo 'ENCODED' || echo 'ENCODE_FAILED'")
if echo "$result" | grep -q "ENCODE_FAILED"; then
    echo "[!] Error: Failed to encode file"
    exit 1
fi

# Step 2: Get file size
echo "[*] Step 2/4: Getting file size..."
size_output=$(expect_execute "$TARGET_IP" "$USERNAME" "$PASSWORD" "wc -c < /tmp/apollo_dl.b64")
file_size=$(echo "$size_output" | grep -oE '[0-9]+' | head -1)

if [[ -z "$file_size" ]] || [[ "$file_size" -lt 100 ]]; then
    echo "[!] Error: Failed to get file size"
    exit 1
fi

echo "[*] Base64 file size: $file_size bytes"
num_chunks=$(( (file_size + CHUNK_SIZE - 1) / CHUNK_SIZE ))
echo "[*] Will download in $num_chunks chunks"

# Step 3: Download chunks
echo "[*] Step 3/4: Downloading chunks..."
temp_parts_dir=$(mktemp -d)
trap "rm -rf $temp_parts_dir" EXIT

for ((i=0; i<num_chunks; i++)); do
    start=$((i * CHUNK_SIZE))
    end=$((start + CHUNK_SIZE - 1))
    if [[ $end -ge $file_size ]]; then
        end=$((file_size - 1))
    fi
    
    echo "[*] Downloading chunk $((i+1))/$num_chunks (bytes $start-$end)..."
    
    # Use dd to extract chunk, then base64 decode each chunk
    chunk_output=$(expect_execute "$TARGET_IP" "$USERNAME" "$PASSWORD" "dd if=/tmp/apollo_dl.b64 bs=1 skip=$start count=$((end-start+1)) 2>/dev/null")
    
    # Clean output
    chunk_data=$(echo "$chunk_output" | \
        grep -v "^dd if=" | \
        grep -v "^\[/app\]" | \
        grep -v "^#" | \
        grep -v "^\$" | \
        grep -v "^$" | \
        tr -d '\r\n')
    
    if [[ -n "$chunk_data" ]]; then
        echo -n "$chunk_data" > "$temp_parts_dir/chunk_$i.b64"
    else
        echo "[!] Warning: Chunk $i is empty"
    fi
done

# Step 4: Combine and decode
echo "[*] Step 4/4: Combining chunks and decoding..."
cat "$temp_parts_dir"/chunk_*.b64 > "$temp_parts_dir/combined.b64"

# Decode
if ! base64 -d "$temp_parts_dir/combined.b64" > "$LOCAL_FILE" 2>/dev/null; then
    if ! base64 -d < "$temp_parts_dir/combined.b64" > "$LOCAL_FILE" 2>/dev/null; then
        echo "[!] Error: Failed to decode base64"
        exit 1
    fi
fi

# Clean up remote
expect_execute "$TARGET_IP" "$USERNAME" "$PASSWORD" "rm -f /tmp/apollo_dl.b64" >/dev/null

# Verify
if [[ ! -f "$LOCAL_FILE" ]] || [[ ! -s "$LOCAL_FILE" ]]; then
    echo "[!] Error: Downloaded file is empty"
    exit 1
fi

file_size_local=$(stat -f%z "$LOCAL_FILE" 2>/dev/null || stat -c%s "$LOCAL_FILE" 2>/dev/null)
echo "[+] Success! Downloaded to $LOCAL_FILE ($file_size_local bytes)"
