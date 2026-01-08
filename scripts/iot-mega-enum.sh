#!/usr/bin/env bash
set -euo pipefail

TARGET_IP="${1:-}"
IFACE="${2:-eth0}"
CONFIG_FILE="${3:-scripts/iot-config.yaml}"

if [[ -z "$TARGET_IP" ]]; then
  echo "Usage: $0 <target-ip> [interface] [config-file]"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$(date +%Y%m%d_%H%M%S)"
OUTDIR="iot_enum_${TARGET_IP}_${TS}"
mkdir -p "$OUTDIR"

echo "[*] Target: $TARGET_IP"
echo "[*] Output: $OUTDIR"
echo "[*] Config: $CONFIG_FILE"

#######################################
# Configuration Parsing
#######################################
parse_config() {
  local config_file="$1"
  
  if [[ ! -f "$config_file" ]]; then
    echo "[!] Config file not found: $config_file"
    echo "[*] Using default configuration"
    return
  fi
  
  # Try to use python3 with yaml if available, otherwise use basic parsing
  if command -v python3 &> /dev/null && python3 -c "import yaml" 2>/dev/null; then
    # Use python to parse YAML
    eval "$(python3 <<EOF
import yaml
import sys
import os

with open('$config_file', 'r') as f:
    config = yaml.safe_load(f)

def export_var(path, value):
    var_name = path.upper().replace('/', '_')
    if isinstance(value, bool):
        print(f"export {var_name}={str(value).lower()}")
    elif isinstance(value, (int, str)):
        print(f"export {var_name}={value}")
    elif isinstance(value, list):
        print(f"export {var_name}=\"{' '.join(str(v) for v in value)}\"")
    else:
        print(f"export {var_name}=\"{value}\"")

# Export tool settings
for category, tools in config.get('tools', {}).items():
    for tool, enabled in tools.items():
        export_var(f"TOOL_{category}_{tool}", enabled)

# Export execution settings
for key, value in config.get('execution', {}).items():
    export_var(f"EXEC_{key}", value)

# Export vulnerability testing settings
for key, value in config.get('vulnerability_testing', {}).items():
    if isinstance(value, dict):
        for subkey, subvalue in value.items():
            export_var(f"VULN_{key}_{subkey}", subvalue)
    else:
        export_var(f"VULN_{key}", value)

# Export reporting settings
for key, value in config.get('reporting', {}).items():
    export_var(f"REPORT_{key}", value)

# Export cameradar settings
for key, value in config.get('cameradar', {}).items():
    if key == 'execution_timeout':
        export_var(f"CAMERADAR_EXECUTION_TIMEOUT", value)
    else:
        export_var(f"CAMERADAR_{key.upper()}", value)
EOF
)"
  else
    echo "[!] Python3 with yaml module not found. Install with: pip3 install pyyaml"
    echo "[*] Using default configuration (all tools enabled)"
  fi
}

# Set defaults
TOOL_NETWORK_SCANNING_NMAP=true
TOOL_NETWORK_SCANNING_MASSCAN=true
TOOL_SERVICE_ENUMERATION_NMAP_SCRIPTS=true
TOOL_SERVICE_ENUMERATION_NIKTO=true
TOOL_CREDENTIAL_TESTING_HYDRA=true
TOOL_CREDENTIAL_TESTING_DEFAULT_CREDS=true
TOOL_EXPLOITATION_METASPLOIT=false
TOOL_PROTOCOL_SPECIFIC_RTSP=true
TOOL_PROTOCOL_SPECIFIC_ONVIF=true
TOOL_PROTOCOL_SPECIFIC_UPNP=true
TOOL_PROTOCOL_SPECIFIC_TELNET=true
TOOL_PROTOCOL_SPECIFIC_SSH=true
TOOL_PROTOCOL_SPECIFIC_HTTP=true
EXEC_MODE=smart
EXEC_MAX_PARALLEL=4
VULN_DEFAULT_CREDENTIALS_ENABLED=true
VULN_KNOWN_CVES_ENABLED=true
VULN_FIRMWARE_ANALYSIS_ENABLED=true
VULN_PROTOCOL_EXPLOITS_ENABLED=true
REPORT_HTML=true
REPORT_SUMMARY=true
REPORT_JSON=false

# Parse config file
parse_config "$CONFIG_FILE"

#######################################
# Helper Functions
#######################################
log() {
  echo "[*] $*" | tee -a "$OUTDIR/execution.log"
}

error() {
  echo "[!] $*" | tee -a "$OUTDIR/execution.log"
}

run_docker() {
  local image="$1"
  shift
  docker run --rm --net=host -v "${SCRIPT_DIR}:${SCRIPT_DIR}:ro" -v "$(pwd):$(pwd)" -w "$(pwd)" "$image" "$@"
}

run_custom_docker() {
  local image="iot-pentest/$1"
  shift
  docker run --rm --net=host -v "${SCRIPT_DIR}:${SCRIPT_DIR}:ro" "$image" "$@"
}

#######################################
# Network Scanning Functions
#######################################
run_nmap_scan() {
  log "Fast full-port scan (nmap -T5)"
  run_docker uzyexe/nmap \
    -p- -T5 --min-rate=1000 "$TARGET_IP" \
    -oA "/tmp/fastscan" || return 1
  
  cp /tmp/fastscan.* "$OUTDIR/" 2>/dev/null || true
  
  PORTS=$(grep -E "^[0-9]+/tcp.*open|^[0-9]+/udp.*open" "$OUTDIR/fastscan.nmap" 2>/dev/null | awk '{print $1}' | cut -d/ -f1 | paste -sd, - || echo "")
  echo "$PORTS" > "$OUTDIR/open_ports.txt"
  log "Open ports: $PORTS"
  
  if [[ -z "$PORTS" ]]; then
    error "No open ports found"
    return 1
  fi
  return 0
}

run_deep_enumeration() {
  local ports="$1"
  log "Deep service enumeration"
  run_docker uzyexe/nmap \
    -sS -sV -O -A \
    --script default,safe,discovery,rtsp-url-brute,rtsp-methods \
    -p "$ports" "$TARGET_IP" \
    -oA "/tmp/deep" || return 1
  
  cp /tmp/deep.* "$OUTDIR/" 2>/dev/null || true
  return 0
}

#######################################
# Service Enumeration Functions
#######################################
run_nikto() {
  local port="$1"
  log "Running Nikto on port $port"
  run_docker frapsoft/nikto \
    -h "http://$TARGET_IP:$port" \
    -Format txt \
    -output "$OUTDIR/nikto_${port}.txt" || return 1
  return 0
}

#######################################
# Protocol-Specific Functions
#######################################
run_rtsp_scan() {
  log "RTSP stream enumeration"
  {
    echo "=== RTSP Stream Discovery ==="
    # Try common RTSP ports
    for port in 554 8554; do
      if echo "$PORTS" | grep -q "$port"; then
        echo "Testing RTSP on port $port"
        run_docker uzyexe/nmap \
          --script rtsp-url-brute \
          --script rtsp-methods \
          -p "$port" "$TARGET_IP" \
          -oN "$OUTDIR/rtsp_${port}.txt" || true
      fi
    done
    # Try to discover RTSP streams
    run_docker aler9/rtsp-simple-server rtsp-simple-server --help >/dev/null 2>&1 || true
  } >> "$OUTDIR/rtsp_scan.txt" 2>&1
  return 0
}

run_cameradar() {
  log "Cameradar RTSP penetration testing"
  
  # Check if RTSP ports are detected
  local rtsp_ports=""
  for port in 554 5554 8554; do
    if echo "$PORTS" | grep -q "$port"; then
      if [[ -z "$rtsp_ports" ]]; then
        rtsp_ports="$port"
      else
        rtsp_ports="$rtsp_ports,$port"
      fi
    fi
  done
  
  if [[ -z "$rtsp_ports" ]]; then
    log "No RTSP ports detected, skipping cameradar"
    return 0
  fi
  
  log "Running cameradar on RTSP ports: $rtsp_ports"
  
  # Get custom dictionary paths
  local credentials_file="${SCRIPT_DIR}/wordlists/cameradar-credentials.json"
  local routes_file="${SCRIPT_DIR}/wordlists/cameradar-routes.txt"
  
  # Build Docker command
  local docker_cmd=(
    "docker" "run" "--rm"
    "--net=host"
  )
  
  # Add volume mounts for custom dictionaries if they exist
  if [[ -f "$credentials_file" ]]; then
    docker_cmd+=("-v" "${credentials_file}:/tmp/custom_credentials.json:ro")
  fi
  
  if [[ -f "$routes_file" ]]; then
    docker_cmd+=("-v" "${routes_file}:/tmp/custom_routes.txt:ro")
  fi
  
  # Add volume mount for output
  docker_cmd+=("-v" "$(pwd):/output")
  
  # Add environment variables
  docker_cmd+=(
    "-e" "CAMERADAR_TARGET=${TARGET_IP}"
    "-e" "CAMERADAR_PORTS=${rtsp_ports}"
    "-e" "CAMERADAR_TIMEOUT=${CAMERADAR_TIMEOUT:-2000}ms"
    "-e" "CAMERADAR_ATTACK_INTERVAL=${CAMERADAR_ATTACK_INTERVAL:-0}ms"
    "-e" "CAMERADAR_LOGGING=true"
  )
  
  # Add custom dictionary paths if they exist
  if [[ -f "$credentials_file" ]]; then
    docker_cmd+=("-e" "CAMERADAR_CUSTOM_CREDENTIALS=/tmp/custom_credentials.json")
  fi
  
  if [[ -f "$routes_file" ]]; then
    docker_cmd+=("-e" "CAMERADAR_CUSTOM_ROUTES=/tmp/custom_routes.txt")
  fi
  
  # Add image and command
  docker_cmd+=(
    "ullaakut/cameradar"
    "-t" "$TARGET_IP"
    "-p" "$rtsp_ports"
    "--json"
  )
  
  # Run cameradar and save outputs
  local json_output="${OUTDIR}/cameradar_rtsp.json"
  local text_output="${OUTDIR}/cameradar_rtsp.txt"
  
  {
    echo "=== Cameradar RTSP Penetration Test ==="
    echo "Target: $TARGET_IP"
    echo "Ports: $rtsp_ports"
    echo "Date: $(date)"
    echo ""
    echo "Command: ${docker_cmd[*]}"
    echo ""
    echo "--- JSON Output ---"
  } > "$text_output"
  
  # Execute cameradar with timeout (90 seconds default)
  local execution_timeout="${CAMERADAR_EXECUTION_TIMEOUT:-90}"
  log "Running cameradar with ${execution_timeout}s timeout..."
  
  if timeout "${execution_timeout}" "${docker_cmd[@]}" > "$json_output" 2>> "$text_output"; then
    {
      echo ""
      echo "--- Execution Complete ---"
      echo "JSON output saved to: cameradar_rtsp.json"
    } >> "$text_output"
    log "Cameradar scan completed"
  else
    local exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
      {
        echo ""
        echo "--- Execution Timed Out ---"
        echo "Cameradar exceeded ${execution_timeout}s timeout"
        echo "Partial results may be available in JSON output"
      } >> "$text_output"
      log "Cameradar scan timed out after ${execution_timeout}s"
    else
      {
        echo ""
        echo "--- Execution Failed ---"
        echo "Check execution log above for details"
      } >> "$text_output"
      log "Cameradar scan failed (check logs)"
    fi
  fi
  
  return 0
}

run_onvif_scan() {
  log "ONVIF device enumeration"
  {
    echo "=== ONVIF Device Discovery ==="
    # Try common ONVIF ports (80, 8080, 554)
    for port in 80 8080 554; do
      if echo "$PORTS" | grep -q "$port"; then
        echo "Testing ONVIF on port $port"
        python3 <<EOF 2>&1 || true
from onvif import ONVIFCamera
try:
    mycam = ONVIFCamera('$TARGET_IP', $port, 'admin', 'admin')
    print(f"ONVIF camera found on port $port")
    print(f"Device info: {mycam.devicemgmt.GetDeviceInformation()}")
except Exception as e:
    print(f"ONVIF test on port $port: {e}")
EOF
      fi
    done
  } >> "$OUTDIR/onvif_scan.txt" 2>&1
  return 0
}

run_upnp_scan() {
  log "UPnP device discovery"
  {
    echo "=== UPnP Device Discovery ==="
    run_custom_docker upnp-tools python3 <<EOF 2>&1 || true
import upnpclient
import socket

try:
    devices = upnpclient.discover()
    print(f"Found {len(devices)} UPnP devices")
    for device in devices:
        print(f"Device: {device.friendly_name}")
        print(f"  Location: {device.location}")
        print(f"  Services: {list(device.services.keys())}")
except Exception as e:
    print(f"UPnP discovery error: {e}")
EOF
  } >> "$OUTDIR/upnp_scan.txt" 2>&1
  return 0
}

#######################################
# Credential Testing Functions
#######################################
run_hydra() {
  local service="$1"
  local port="$2"
  log "Running Hydra on $service (port $port)"
  
  # Create wordlist if it doesn't exist
  local wordlist="${SCRIPT_DIR}/wordlists/common-passwords.txt"
  mkdir -p "${SCRIPT_DIR}/wordlists"
  if [[ ! -f "$wordlist" ]]; then
    cat > "$wordlist" <<EOF
admin
password
12345
123456
root
user
admin123
password123
EOF
  fi
  
  run_custom_docker hydra \
    -L "${SCRIPT_DIR}/wordlists/common-passwords.txt" \
    -P "${SCRIPT_DIR}/wordlists/common-passwords.txt" \
    "$service"://"$TARGET_IP":"$port" \
    -o "$OUTDIR/hydra_${service}_${port}.txt" 2>&1 || true
  return 0
}

test_default_creds() {
  log "Testing default credentials"
  {
    echo "=== Default Credential Testing ==="
    # Common IoT/WebCam credentials
    declare -a creds=(
      "admin:admin"
      "admin:12345"
      "admin:password"
      "root:root"
      "root:12345"
      "user:user"
      "user:user123"
      "admin:"
      "root:"
    )
    
    # Test HTTP
    if echo "$PORTS" | grep -qE "(80|8080|443|8443)"; then
      for cred in "${creds[@]}"; do
        IFS=':' read -r user pass <<< "$cred"
        echo "Testing HTTP: $user:$pass"
        curl -s -u "$user:$pass" "http://$TARGET_IP" >/dev/null 2>&1 && echo "SUCCESS: $user:$pass" || true
      done
    fi
    
    # Test Telnet
    if echo "$PORTS" | grep -q "23"; then
      for cred in "${creds[@]}"; do
        IFS=':' read -r user pass <<< "$cred"
        echo "Testing Telnet: $user:$pass"
        timeout 2 bash -c "echo -e '$user\n$pass\n' | telnet $TARGET_IP 23" 2>&1 | grep -q "Login incorrect" || echo "Possible success: $user:$pass"
      done
    fi
  } >> "$OUTDIR/default_creds.txt" 2>&1
  return 0
}

#######################################
# Vulnerability Testing Functions
#######################################
check_known_cves() {
  log "Checking for known CVEs"
  {
    echo "=== CVE Check ==="
    # Extract service versions from nmap output
    if [[ -f "$OUTDIR/deep.xml" ]]; then
      grep -i "version\|product" "$OUTDIR/deep.xml" | head -20
      echo "Note: Full CVE checking requires CVE database file"
    fi
  } >> "$OUTDIR/cve_check.txt" 2>&1
  return 0
}

analyze_firmware() {
  log "Attempting firmware analysis"
  {
    echo "=== Firmware Analysis ==="
    # Try to find firmware download endpoints
    for port in 80 8080 443 8443; do
      if echo "$PORTS" | grep -q "$port"; then
        echo "Checking for firmware on port $port"
        curl -s "http://$TARGET_IP:$port/firmware" >/dev/null 2>&1 && echo "Found: /firmware" || true
        curl -s "http://$TARGET_IP:$port/update" >/dev/null 2>&1 && echo "Found: /update" || true
        curl -s "http://$TARGET_IP:$port/fw" >/dev/null 2>&1 && echo "Found: /fw" || true
      fi
    done
  } >> "$OUTDIR/firmware_analysis.txt" 2>&1
  return 0
}

test_protocol_exploits() {
  log "Testing protocol-specific exploits"
  {
    echo "=== Protocol Exploit Testing ==="
    # RTSP authentication bypass attempts
    if echo "$PORTS" | grep -q "554"; then
      echo "Testing RTSP authentication bypass"
      curl -s "rtsp://$TARGET_IP:554/" >/dev/null 2>&1 && echo "RTSP accessible without auth" || true
    fi
    
    # HTTP authentication weaknesses
    for port in 80 8080; do
      if echo "$PORTS" | grep -q "$port"; then
        echo "Testing HTTP authentication on port $port"
        curl -s -I "http://$TARGET_IP:$port" | grep -i "www-authenticate" || echo "No authentication required"
      fi
    done
  } >> "$OUTDIR/protocol_exploits.txt" 2>&1
  return 0
}

#######################################
# Exploitation Functions
#######################################
run_metasploit() {
  if [[ "${TOOL_EXPLOITATION_METASPLOIT:-false}" != "true" ]]; then
    log "Metasploit disabled in configuration"
    return 0
  fi
  
  log "WARNING: Running Metasploit - this may be disruptive"
  {
    echo "=== Metasploit Scan ==="
    echo "Note: Metasploit requires manual interaction"
    echo "Run: docker run -it --rm --net=host metasploitframework/metasploit-framework msfconsole"
  } >> "$OUTDIR/metasploit.txt" 2>&1
  return 0
}

#######################################
# Main Execution Flow
#######################################
main() {
  # Phase 1: Network Scanning (required first)
  if [[ "${TOOL_NETWORK_SCANNING_NMAP:-true}" == "true" ]]; then
    if ! run_nmap_scan; then
      error "Network scan failed or no ports found"
      exit 0
    fi
    PORTS=$(cat "$OUTDIR/open_ports.txt")
  else
    error "Nmap scanning is required but disabled"
    exit 1
  fi
  
  # Phase 2: Deep Service Enumeration
  if [[ "${TOOL_SERVICE_ENUMERATION_NMAP_SCRIPTS:-true}" == "true" ]]; then
    run_deep_enumeration "$PORTS"
  fi
  
  # Phase 3: Service-Specific Enumeration (can run in parallel)
  declare -a parallel_jobs=()
  
  if [[ "${TOOL_SERVICE_ENUMERATION_NIKTO:-true}" == "true" ]]; then
    for port in ${PORTS//,/ }; do
      if [[ "$port" =~ ^(80|443|8080|8443)$ ]]; then
        run_nikto "$port" &
        parallel_jobs+=($!)
      fi
    done
  fi
  
  # Phase 4: Protocol-Specific Scans (can run in parallel)
  if [[ "${TOOL_PROTOCOL_SPECIFIC_RTSP:-true}" == "true" ]]; then
    run_rtsp_scan &
    parallel_jobs+=($!)
  fi
  
  if [[ "${TOOL_PROTOCOL_SPECIFIC_CAMERADAR:-true}" == "true" ]]; then
    run_cameradar &
    parallel_jobs+=($!)
  fi
  
  if [[ "${TOOL_PROTOCOL_SPECIFIC_ONVIF:-true}" == "true" ]]; then
    run_onvif_scan &
    parallel_jobs+=($!)
  fi
  
  if [[ "${TOOL_PROTOCOL_SPECIFIC_UPNP:-true}" == "true" ]]; then
    run_upnp_scan &
    parallel_jobs+=($!)
  fi
  
  # Wait for parallel jobs (with limit)
  local max_parallel="${EXEC_MAX_PARALLEL:-4}"
  local running=0
  for pid in "${parallel_jobs[@]}"; do
    while [[ $running -ge $max_parallel ]]; do
      sleep 1
      running=$(jobs -r | wc -l)
    done
    wait "$pid" 2>/dev/null || true
    ((running++)) || true
  done
  wait
  
  # Phase 5: Credential Testing
  if [[ "${TOOL_CREDENTIAL_TESTING_HYDRA:-true}" == "true" ]]; then
    for port in ${PORTS//,/ }; do
      if echo "$port" | grep -qE "(80|443|8080|8443)"; then
        run_hydra "http" "$port" &
      elif echo "$port" | grep -q "23"; then
        run_hydra "telnet" "$port" &
      elif echo "$port" | grep -q "22"; then
        run_hydra "ssh" "$port" &
      fi
    done
    wait
  fi
  
  if [[ "${TOOL_CREDENTIAL_TESTING_DEFAULT_CREDS:-true}" == "true" ]]; then
    test_default_creds
  fi
  
  # Phase 6: Vulnerability Testing
  if [[ "${VULN_KNOWN_CVES_ENABLED:-true}" == "true" ]]; then
    check_known_cves
  fi
  
  if [[ "${VULN_FIRMWARE_ANALYSIS_ENABLED:-true}" == "true" ]]; then
    analyze_firmware
  fi
  
  if [[ "${VULN_PROTOCOL_EXPLOITS_ENABLED:-true}" == "true" ]]; then
    test_protocol_exploits
  fi
  
  # Phase 7: Exploitation (optional)
  if [[ "${TOOL_EXPLOITATION_METASPLOIT:-false}" == "true" ]]; then
    run_metasploit
  fi
  
  # Phase 8: Passive Capture
  log "Capturing traffic (30s)"
  timeout 30 tcpdump -i "$IFACE" host "$TARGET_IP" \
    -w "$OUTDIR/traffic.pcap" 2>&1 || true
  
  # Phase 9: Generate Reports
  if [[ "${REPORT_HTML:-true}" == "true" ]] || [[ "${REPORT_SUMMARY:-true}" == "true" ]]; then
    log "Generating reports"
    if [[ -f "${SCRIPT_DIR}/iot-report-generator.sh" ]]; then
      bash "${SCRIPT_DIR}/iot-report-generator.sh" "$OUTDIR" "$TARGET_IP" "$TS"
    else
      error "Report generator not found"
    fi
  fi
  
  log "======================================"
  log "Enumeration complete"
  log "Results in: $OUTDIR"
  log "======================================"
}

main "$@"
