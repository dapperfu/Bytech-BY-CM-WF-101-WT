#!/usr/bin/env bash
set -euo pipefail

OUTDIR="${1:-}"
TARGET_IP="${2:-}"
TIMESTAMP="${3:-}"

if [[ -z "$OUTDIR" ]] || [[ -z "$TARGET_IP" ]]; then
  echo "Usage: $0 <output-directory> <target-ip> [timestamp]"
  exit 1
fi

#######################################
# Generate Summary Report
#######################################
generate_summary() {
  local summary_file="$OUTDIR/summary.txt"
  
  {
    echo "=========================================="
    echo "IoT Penetration Test Summary Report"
    echo "=========================================="
    echo "Target IP: $TARGET_IP"
    echo "Scan Date: $(date)"
    echo "Timestamp: ${TIMESTAMP:-$(date +%Y%m%d_%H%M%S)}"
    echo ""
    echo "------------------------------------------"
    echo "OPEN PORTS"
    echo "------------------------------------------"
    if [[ -f "$OUTDIR/open_ports.txt" ]]; then
      cat "$OUTDIR/open_ports.txt"
    else
      echo "No open ports found"
    fi
    echo ""
    echo "------------------------------------------"
    echo "SERVICES DETECTED"
    echo "------------------------------------------"
    if [[ -f "$OUTDIR/deep.nmap" ]]; then
      grep -E "^\d+/" "$OUTDIR/deep.nmap" | head -20
    fi
    echo ""
    echo "------------------------------------------"
    echo "CRITICAL FINDINGS"
    echo "------------------------------------------"
    
    # Check for default credentials
    if [[ -f "$OUTDIR/default_creds.txt" ]]; then
      if grep -qi "SUCCESS\|success" "$OUTDIR/default_creds.txt"; then
        echo "[!] Default credentials found!"
        grep -i "SUCCESS\|success" "$OUTDIR/default_creds.txt"
      fi
    fi
    
    # Check for RTSP streams
    if [[ -f "$OUTDIR/rtsp_scan.txt" ]]; then
      if grep -qi "stream\|rtsp" "$OUTDIR/rtsp_scan.txt"; then
        echo "[*] RTSP streams detected"
      fi
    fi
    
    # Check for ONVIF devices
    if [[ -f "$OUTDIR/onvif_scan.txt" ]]; then
      if grep -qi "camera\|onvif" "$OUTDIR/onvif_scan.txt"; then
        echo "[*] ONVIF devices detected"
      fi
    fi
    
    # Check for vulnerabilities
    if [[ -f "$OUTDIR/nikto"*.txt ]]; then
      echo "[*] Web vulnerabilities found (check nikto reports)"
    fi
    
    echo ""
    echo "------------------------------------------"
    echo "FILES GENERATED"
    echo "------------------------------------------"
    find "$OUTDIR" -type f -name "*.txt" -o -name "*.xml" -o -name "*.nmap" | sort
    
  } > "$summary_file"
  
  echo "[+] Summary report: $summary_file"
}

#######################################
# Generate HTML Report
#######################################
generate_html() {
  local html_file="$OUTDIR/report.html"
  
  {
    cat <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>IoT Penetration Test Report - $TARGET_IP</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 20px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background-color: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            border-bottom: 3px solid #4CAF50;
            padding-bottom: 10px;
        }
        h2 {
            color: #555;
            margin-top: 30px;
            border-bottom: 2px solid #ddd;
            padding-bottom: 5px;
        }
        .summary {
            background-color: #e8f5e9;
            padding: 15px;
            border-radius: 5px;
            margin: 20px 0;
        }
        .finding {
            background-color: #fff3cd;
            padding: 10px;
            margin: 10px 0;
            border-left: 4px solid #ffc107;
            border-radius: 4px;
        }
        .critical {
            background-color: #f8d7da;
            border-left-color: #dc3545;
        }
        .info {
            background-color: #d1ecf1;
            border-left-color: #17a2b8;
        }
        pre {
            background-color: #f4f4f4;
            padding: 10px;
            border-radius: 4px;
            overflow-x: auto;
            font-size: 12px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
        }
        th, td {
            border: 1px solid #ddd;
            padding: 8px;
            text-align: left;
        }
        th {
            background-color: #4CAF50;
            color: white;
        }
        tr:nth-child(even) {
            background-color: #f2f2f2;
        }
        .timestamp {
            color: #666;
            font-size: 0.9em;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>IoT Penetration Test Report</h1>
        <p class="timestamp">Target: <strong>$TARGET_IP</strong> | Date: $(date) | Timestamp: ${TIMESTAMP:-$(date +%Y%m%d_%H%M%S)}</p>
        
        <div class="summary">
            <h2>Executive Summary</h2>
            <p>This report contains the results of a comprehensive penetration test performed on the IoT device at IP address <strong>$TARGET_IP</strong>.</p>
EOF

    # Open Ports Section
    if [[ -f "$OUTDIR/open_ports.txt" ]]; then
      local ports=$(cat "$OUTDIR/open_ports.txt")
      echo "            <h3>Open Ports</h3>"
      echo "            <p><strong>$ports</strong></p>"
    fi
    
    # Critical Findings
    echo "            <h3>Critical Findings</h3>"
    if [[ -f "$OUTDIR/default_creds.txt" ]] && grep -qi "SUCCESS\|success" "$OUTDIR/default_creds.txt" 2>/dev/null; then
      echo "            <div class=\"finding critical\">"
      echo "                <strong>⚠️ Default Credentials Found!</strong>"
      echo "                <pre>$(grep -i "SUCCESS\|success" "$OUTDIR/default_creds.txt" | head -5)</pre>"
      echo "            </div>"
    fi
    
    cat <<EOF
        </div>
        
        <h2>Network Scan Results</h2>
EOF

    # Ports Table
    if [[ -f "$OUTDIR/deep.nmap" ]]; then
      echo "        <table>"
      echo "            <tr><th>Port</th><th>State</th><th>Service</th><th>Version</th></tr>"
      grep -E "^\d+/" "$OUTDIR/deep.nmap" | while read -r line; do
        port=$(echo "$line" | awk '{print $1}')
        state=$(echo "$line" | awk '{print $2}')
        service=$(echo "$line" | awk '{print $3}')
        version=$(echo "$line" | awk '{for(i=4;i<=NF;i++) printf "%s ", $i; print ""}')
        echo "            <tr><td>$port</td><td>$state</td><td>$service</td><td>$version</td></tr>"
      done
      echo "        </table>"
    fi
    
    cat <<EOF
        
        <h2>Service Enumeration</h2>
EOF

    # Nikto Results
    for nikto_file in "$OUTDIR"/nikto_*.txt; do
      if [[ -f "$nikto_file" ]]; then
        local port=$(basename "$nikto_file" | sed 's/nikto_\(.*\)\.txt/\1/')
        echo "        <h3>Nikto Results - Port $port</h3>"
        echo "        <pre>$(head -50 "$nikto_file")</pre>"
      fi
    done
    
    cat <<EOF
        
        <h2>Protocol-Specific Findings</h2>
EOF

    # RTSP
    if [[ -f "$OUTDIR/rtsp_scan.txt" ]]; then
      echo "        <h3>RTSP Streams</h3>"
      echo "        <div class=\"finding info\">"
      echo "            <pre>$(head -30 "$OUTDIR/rtsp_scan.txt")</pre>"
      echo "        </div>"
    fi
    
    # ONVIF
    if [[ -f "$OUTDIR/onvif_scan.txt" ]]; then
      echo "        <h3>ONVIF Devices</h3>"
      echo "        <div class=\"finding info\">"
      echo "            <pre>$(head -30 "$OUTDIR/onvif_scan.txt")</pre>"
      echo "        </div>"
    fi
    
    # UPnP
    if [[ -f "$OUTDIR/upnp_scan.txt" ]]; then
      echo "        <h3>UPnP Devices</h3>"
      echo "        <div class=\"finding info\">"
      echo "            <pre>$(head -30 "$OUTDIR/upnp_scan.txt")</pre>"
      echo "        </div>"
    fi
    
    cat <<EOF
        
        <h2>Vulnerability Assessment</h2>
EOF

    # Default Credentials
    if [[ -f "$OUTDIR/default_creds.txt" ]]; then
      echo "        <h3>Default Credential Testing</h3>"
      echo "        <pre>$(head -50 "$OUTDIR/default_creds.txt")</pre>"
    fi
    
    # CVE Check
    if [[ -f "$OUTDIR/cve_check.txt" ]]; then
      echo "        <h3>Known CVEs</h3>"
      echo "        <pre>$(cat "$OUTDIR/cve_check.txt")</pre>"
    fi
    
    # Protocol Exploits
    if [[ -f "$OUTDIR/protocol_exploits.txt" ]]; then
      echo "        <h3>Protocol Exploit Testing</h3>"
      echo "        <pre>$(cat "$OUTDIR/protocol_exploits.txt")</pre>"
    fi
    
    # Firmware Analysis
    if [[ -f "$OUTDIR/firmware_analysis.txt" ]]; then
      echo "        <h3>Firmware Analysis</h3>"
      echo "        <pre>$(cat "$OUTDIR/firmware_analysis.txt")</pre>"
    fi
    
    cat <<EOF
        
        <h2>Recommendations</h2>
        <div class="finding">
            <ul>
                <li>Change all default credentials immediately</li>
                <li>Update firmware to latest version</li>
                <li>Disable unnecessary services and ports</li>
                <li>Implement proper authentication mechanisms</li>
                <li>Enable encryption for sensitive communications</li>
                <li>Regular security audits and penetration testing</li>
            </ul>
        </div>
        
        <hr>
        <p class="timestamp">Report generated: $(date)</p>
    </div>
</body>
</html>
EOF

  } > "$html_file"
  
  echo "[+] HTML report: $html_file"
}

#######################################
# Main
#######################################
main() {
  echo "[*] Generating reports for $TARGET_IP"
  
  generate_summary
  generate_html
  
  echo "[+] Reports generated in $OUTDIR"
}

main "$@"

