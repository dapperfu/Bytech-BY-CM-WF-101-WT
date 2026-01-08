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
echo "[*] Note: Some tools (Hydra, ONVIF, UPnP) will be built from Dockerfiles"

IMAGES=(
  "ivre/client"
  "jess/masscan"
  "uzyexe/nmap"
  "aler9/rtsp-simple-server"
  "frapsoft/nikto"
  "metasploitframework/metasploit-framework"
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
docker run --rm frapsoft/nikto -Version >/dev/null 2>&1 || true
docker run --rm metasploitframework/metasploit-framework msfconsole --version >/dev/null 2>&1 || true

#######################################
# Build custom Docker images
#######################################
echo
echo "[*] Building custom Docker images from dockerfiles/"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKERFILES_DIR="${SCRIPT_DIR}/dockerfiles"

if [[ -d "$DOCKERFILES_DIR" ]]; then
  for dockerfile_dir in "$DOCKERFILES_DIR"/*/; do
    if [[ -f "${dockerfile_dir}Dockerfile" ]]; then
      image_name=$(basename "$dockerfile_dir")
      echo "[*] Building ${image_name}..."
      if docker build -t "iot-pentest/${image_name}:latest" "$dockerfile_dir" >/dev/null 2>&1; then
        echo "[+] Successfully built iot-pentest/${image_name}:latest"
      else
        echo "[!] Failed to build iot-pentest/${image_name}:latest"
        FAILED=1
      fi
    fi
  done
else
  echo "[!] Dockerfiles directory not found: $DOCKERFILES_DIR"
  echo "[*] Skipping custom image builds"
fi

echo
echo "======================================"
echo "Docker prefetch complete"
echo "All images pulled and warmed"
echo "======================================"
