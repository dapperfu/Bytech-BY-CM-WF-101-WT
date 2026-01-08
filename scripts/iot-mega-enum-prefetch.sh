#!/usr/bin/env bash
set -euo pipefail

# Check if Docker is available
if ! command -v docker &> /dev/null; then
  echo "[!] Error: Docker is not installed or not in PATH"
  exit 1
fi

# Check if Docker daemon is running
if ! docker info &> /dev/null; then
  echo "[!] Error: Docker daemon is not running"
  exit 1
fi

echo "[*] Prefetching Docker images for IoT enumeration (Docker Hub only)"

IMAGES=(
  "ivre/client"
  "jess/masscan"
  "uzyexe/nmap"
  "aler9/rtsp-simple-server"
)

FAILED=0

for IMG in "${IMAGES[@]}"; do
  echo
  echo "[*] Pulling $IMG"
  if ! docker pull "$IMG"; then
    echo "[!] Failed to pull $IMG"
    FAILED=1
  fi
done

echo
if [[ "$FAILED" -ne 0 ]]; then
  echo "[!] One or more images failed to pull"
  exit 1
fi

#######################################
# Warm containers (first-run cost)
#######################################
echo
echo "[*] Warming containers"

docker run --rm ivre/client nmap --version >/dev/null 2>&1 || true
docker run --rm jess/masscan --version >/dev/null 2>&1 || true
docker run --rm uzyexe/nmap --version >/dev/null 2>&1 || true
docker run --rm aler9/rtsp-simple-server --help >/dev/null 2>&1 || true

echo
echo "======================================"
echo "Docker prefetch complete"
echo "All images pulled and warmed"
echo "======================================"
