#!/usr/bin/env bash
set -euo pipefail

#######################################
# Configuration
#######################################
OUTDIR="${1:-}"
TARGET_IP="${2:-}"
TIMESTAMP="${3:-}"

if [[ -z "$OUTDIR" ]]; then
    echo "Usage: $0 <output-directory> [target-ip] [timestamp]"
    exit 1
fi

if [[ ! -d "$OUTDIR" ]]; then
    echo "[!] Error: Output directory does not exist: $OUTDIR"
    exit 1
fi

#######################################
# Severity Categorization Functions
#######################################
categorize_finding() {
    local finding="$1"
    local file_path="$2"
    
    # Critical findings
    if grep -qiE "(default.*credential|root.*password|empty.*password|hellotuya|user123)" "$file_path" 2>/dev/null; then
        echo "critical"
        return
    fi
    
    if grep -qiE "(privilege.*escalation|suid.*root|world.*writable.*etc|shadow.*readable)" "$file_path" 2>/dev/null; then
        echo "critical"
        return
    fi
    
    # High findings
    if grep -qiE "(suid|sgid|world.*writable|firewall.*disabled|exposed.*service)" "$file_path" 2>/dev/null; then
        echo "high"
        return
    fi
    
    if [[ "$file_path" == *"suid_sgid"* ]] || [[ "$file_path" == *"world_writable"* ]]; then
        echo "high"
        return
    fi
    
    # Medium findings
    if grep -qiE "(insecure|weak.*permission|information.*disclosure|config.*exposed)" "$file_path" 2>/dev/null; then
        echo "medium"
        return
    fi
    
    if [[ "$file_path" == *"app_insecure_perms"* ]] || [[ "$file_path" == *"password_analysis"* ]]; then
        echo "medium"
        return
    fi
    
    # Low findings
    if grep -qiE "(best.*practice|recommendation|informational)" "$file_path" 2>/dev/null; then
        echo "low"
        return
    fi
    
    # Default to info
    echo "info"
}

count_severity() {
    local severity="$1"
    local count=0
    
    # Count critical
    if [[ "$severity" == "critical" ]]; then
        if [[ -f "$OUTDIR/security/password_analysis.txt" ]]; then
            count=$((count + $(grep -ciE "(empty|disabled|::)" "$OUTDIR/security/password_analysis.txt" 2>/dev/null || echo 0)))
        fi
        if [[ -f "$OUTDIR/vulnerabilities/credential_checks.txt" ]]; then
            count=$((count + $(grep -ciE "(hellotuya|user123|default)" "$OUTDIR/vulnerabilities/credential_checks.txt" 2>/dev/null || echo 0)))
        fi
        if [[ -f "$OUTDIR/security/suid_sgid_files.txt" ]]; then
            count=$((count + $(grep -c "^/" "$OUTDIR/security/suid_sgid_files.txt" 2>/dev/null || echo 0)))
        fi
    fi
    
    # Count high
    if [[ "$severity" == "high" ]]; then
        if [[ -f "$OUTDIR/security/world_writable.txt" ]]; then
            count=$((count + $(grep -c "^/" "$OUTDIR/security/world_writable.txt" 2>/dev/null || echo 0)))
        fi
        if [[ -f "$OUTDIR/security/app_insecure_perms.txt" ]]; then
            count=$((count + $(grep -c "^/" "$OUTDIR/security/app_insecure_perms.txt" 2>/dev/null || echo 0)))
        fi
    fi
    
    # Count medium
    if [[ "$severity" == "medium" ]]; then
        if [[ -f "$OUTDIR/vulnerabilities/security_issues.txt" ]]; then
            count=$((count + $(grep -ciE "(insecure|weak)" "$OUTDIR/vulnerabilities/security_issues.txt" 2>/dev/null || echo 0)))
        fi
    fi
    
    echo "$count"
}

#######################################
# HTML Generation Functions
#######################################
generate_html_header() {
    cat <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Internal Device Security Assessment - Red Dune Cyber Research</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Arial', 'Helvetica', sans-serif;
            background-color: #0a0a0a;
            color: #E0E0E0;
            line-height: 1.6;
        }
        
        .header {
            background: linear-gradient(135deg, #8B0000 0%, #000000 100%);
            padding: 30px 20px;
            border-bottom: 3px solid #DC143C;
            box-shadow: 0 4px 6px rgba(220, 20, 60, 0.3);
        }
        
        .header-content {
            max-width: 1200px;
            margin: 0 auto;
        }
        
        .company-name {
            font-size: 2.5em;
            font-weight: bold;
            color: #FFFFFF;
            text-shadow: 2px 2px 4px rgba(0, 0, 0, 0.8);
            margin-bottom: 10px;
            letter-spacing: 2px;
        }
        
        .company-tagline {
            color: #FF6666;
            font-size: 1.1em;
            font-style: italic;
            margin-bottom: 20px;
        }
        
        .report-title {
            font-size: 1.8em;
            color: #FFFFFF;
            margin-top: 20px;
            border-top: 2px solid rgba(255, 255, 255, 0.2);
            padding-top: 20px;
        }
        
        .report-meta {
            margin-top: 15px;
            display: flex;
            flex-wrap: wrap;
            gap: 20px;
            font-size: 0.95em;
        }
        
        .meta-item {
            background-color: rgba(139, 0, 0, 0.3);
            padding: 8px 15px;
            border-radius: 5px;
            border-left: 3px solid #DC143C;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 30px 20px;
        }
        
        .severity-badge {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 12px;
            font-size: 0.85em;
            font-weight: bold;
            text-transform: uppercase;
            margin: 0 5px;
        }
        
        .severity-critical {
            background-color: #8B0000;
            color: #FFFFFF;
            border: 1px solid #FF4444;
        }
        
        .severity-high {
            background-color: #FF6600;
            color: #FFFFFF;
            border: 1px solid #FF8844;
        }
        
        .severity-medium {
            background-color: #FFAA00;
            color: #000000;
            border: 1px solid #FFCC44;
        }
        
        .severity-low {
            background-color: #0066CC;
            color: #FFFFFF;
            border: 1px solid #4488FF;
        }
        
        .severity-info {
            background-color: #666666;
            color: #FFFFFF;
            border: 1px solid #888888;
        }
        
        .section {
            background-color: #1a1a1a;
            border: 1px solid #333333;
            border-radius: 8px;
            padding: 25px;
            margin: 25px 0;
            box-shadow: 0 4px 8px rgba(0, 0, 0, 0.5);
        }
        
        .section-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
            cursor: pointer;
            user-select: none;
        }
        
        .section-title {
            font-size: 1.5em;
            color: #FF6666;
            border-bottom: 2px solid #DC143C;
            padding-bottom: 10px;
            flex-grow: 1;
        }
        
        .section-toggle {
            color: #FF6666;
            font-size: 1.2em;
            margin-left: 15px;
        }
        
        .section-content {
            margin-top: 20px;
        }
        
        .finding-card {
            background-color: #2a2a2a;
            border-left: 4px solid #DC143C;
            padding: 15px;
            margin: 15px 0;
            border-radius: 5px;
            transition: all 0.3s ease;
        }
        
        .finding-card:hover {
            background-color: #333333;
            border-left-color: #FF4444;
        }
        
        .finding-card.critical {
            border-left-color: #FF4444;
            background-color: #3a1a1a;
        }
        
        .finding-card.high {
            border-left-color: #FF8844;
            background-color: #3a2a1a;
        }
        
        .finding-card.medium {
            border-left-color: #FFCC44;
            background-color: #3a3a1a;
        }
        
        .finding-card.low {
            border-left-color: #4488FF;
            background-color: #1a1a3a;
        }
        
        .finding-card.info {
            border-left-color: #888888;
            background-color: #2a2a2a;
        }
        
        .finding-title {
            font-size: 1.1em;
            font-weight: bold;
            color: #FFFFFF;
            margin-bottom: 8px;
        }
        
        .finding-description {
            color: #CCCCCC;
            margin: 10px 0;
        }
        
        pre {
            background-color: #0a0a0a;
            border: 1px solid #DC143C;
            border-radius: 5px;
            padding: 15px;
            overflow-x: auto;
            font-size: 0.9em;
            color: #E0E0E0;
            margin: 10px 0;
        }
        
        code {
            background-color: #0a0a0a;
            padding: 2px 6px;
            border-radius: 3px;
            color: #FF6666;
            font-family: 'Courier New', monospace;
        }
        
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
            background-color: #1a1a1a;
        }
        
        th {
            background-color: #8B0000;
            color: #FFFFFF;
            padding: 12px;
            text-align: left;
            border: 1px solid #DC143C;
            font-weight: bold;
        }
        
        td {
            padding: 10px;
            border: 1px solid #333333;
            color: #E0E0E0;
        }
        
        tr:nth-child(even) {
            background-color: #222222;
        }
        
        tr:hover {
            background-color: #2a2a2a;
        }
        
        .executive-summary {
            background: linear-gradient(135deg, #1a0a0a 0%, #2a1a1a 100%);
            border: 2px solid #DC143C;
            border-radius: 10px;
            padding: 30px;
            margin: 30px 0;
        }
        
        .summary-stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin: 20px 0;
        }
        
        .stat-card {
            background-color: #2a2a2a;
            border: 1px solid #444444;
            border-radius: 8px;
            padding: 20px;
            text-align: center;
        }
        
        .stat-number {
            font-size: 2.5em;
            font-weight: bold;
            color: #FF6666;
            margin-bottom: 5px;
        }
        
        .stat-label {
            color: #CCCCCC;
            font-size: 0.9em;
            text-transform: uppercase;
        }
        
        .filter-buttons {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
            margin: 20px 0;
            padding: 15px;
            background-color: #1a1a1a;
            border-radius: 8px;
        }
        
        .filter-btn {
            padding: 8px 16px;
            border: 2px solid;
            border-radius: 5px;
            background-color: transparent;
            color: #E0E0E0;
            cursor: pointer;
            font-weight: bold;
            transition: all 0.3s ease;
        }
        
        .filter-btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 8px rgba(220, 20, 60, 0.4);
        }
        
        .filter-btn.active {
            background-color: #DC143C;
            border-color: #FF4444;
        }
        
        .filter-btn.critical {
            border-color: #FF4444;
        }
        
        .filter-btn.critical:hover {
            background-color: #8B0000;
        }
        
        .filter-btn.high {
            border-color: #FF8844;
        }
        
        .filter-btn.high:hover {
            background-color: #FF6600;
        }
        
        .filter-btn.medium {
            border-color: #FFCC44;
        }
        
        .filter-btn.medium:hover {
            background-color: #FFAA00;
        }
        
        .filter-btn.low {
            border-color: #4488FF;
        }
        
        .filter-btn.low:hover {
            background-color: #0066CC;
        }
        
        .filter-btn.info {
            border-color: #888888;
        }
        
        .filter-btn.info:hover {
            background-color: #666666;
        }
        
        .recommendations {
            background-color: #1a2a1a;
            border-left: 5px solid #00AA00;
            padding: 20px;
            margin: 20px 0;
            border-radius: 5px;
        }
        
        .recommendations ul {
            margin-left: 20px;
            margin-top: 10px;
        }
        
        .recommendations li {
            margin: 10px 0;
            color: #CCFFCC;
        }
        
        .risk-score {
            font-size: 3em;
            font-weight: bold;
            text-align: center;
            margin: 20px 0;
        }
        
        .risk-critical {
            color: #FF4444;
        }
        
        .risk-high {
            color: #FF8844;
        }
        
        .risk-medium {
            color: #FFCC44;
        }
        
        .risk-low {
            color: #4488FF;
        }
        
        @media print {
            body {
                background-color: white;
                color: black;
            }
            
            .section {
                page-break-inside: avoid;
            }
            
            .filter-buttons {
                display: none;
            }
        }
        
        .collapsed .section-content {
            display: none;
        }
        
        .collapsed .section-toggle::before {
            content: "▶ ";
        }
        
        .section-toggle::before {
            content: "▼ ";
        }
    </style>
</head>
<body>
    <div class="header">
        <div class="header-content">
            <div class="company-name">RED DUNE CYBER RESEARCH</div>
            <div class="company-tagline">Advanced Threat Intelligence & Security Assessment</div>
            <div class="report-title">Internal Device Security Assessment Report</div>
            <div class="report-meta">
EOF
}

generate_html_footer() {
    cat <<'EOF'
            </div>
        </div>
    </div>
    
    <script>
        // Toggle section collapse
        document.querySelectorAll('.section-header').forEach(header => {
            header.addEventListener('click', function() {
                this.parentElement.classList.toggle('collapsed');
            });
        });
        
        // Filter by severity
        document.querySelectorAll('.filter-btn').forEach(btn => {
            btn.addEventListener('click', function() {
                const severity = this.dataset.severity;
                const allCards = document.querySelectorAll('.finding-card');
                
                // Toggle active state
                document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
                this.classList.add('active');
                
                // Show/hide cards
                allCards.forEach(card => {
                    if (severity === 'all' || card.classList.contains(severity)) {
                        card.style.display = 'block';
                    } else {
                        card.style.display = 'none';
                    }
                });
            });
        });
    </script>
</body>
</html>
EOF
}

#######################################
# Content Generation Functions
#######################################
generate_executive_summary() {
    local critical_count=$(count_severity "critical")
    local high_count=$(count_severity "high")
    local medium_count=$(count_severity "medium")
    local low_count=$(count_severity "low")
    
    # Calculate risk score
    local risk_score=$((critical_count * 10 + high_count * 5 + medium_count * 2 + low_count))
    local risk_level="low"
    local risk_class="risk-low"
    
    if [[ $risk_score -ge 50 ]]; then
        risk_level="critical"
        risk_class="risk-critical"
    elif [[ $risk_score -ge 30 ]]; then
        risk_level="high"
        risk_class="risk-high"
    elif [[ $risk_score -ge 15 ]]; then
        risk_level="medium"
        risk_class="risk-medium"
    fi
    
    cat <<EOF
        <div class="executive-summary">
            <h2 style="color: #FF6666; margin-bottom: 20px;">Executive Summary</h2>
            <p style="margin-bottom: 20px; font-size: 1.1em;">
                This report presents the findings from a comprehensive internal security assessment 
                of the IoT device. The assessment was conducted through direct system access and 
                includes analysis of system configuration, network services, file permissions, 
                and security controls.
            </p>
            
            <div class="risk-score $risk_class">Risk Score: $risk_score</div>
            <div style="text-align: center; margin-bottom: 30px;">
                <span class="severity-badge severity-$risk_level">$risk_level Risk</span>
            </div>
            
            <div class="summary-stats">
                <div class="stat-card">
                    <div class="stat-number" style="color: #FF4444;">$critical_count</div>
                    <div class="stat-label">Critical Findings</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number" style="color: #FF8844;">$high_count</div>
                    <div class="stat-label">High Findings</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number" style="color: #FFCC44;">$medium_count</div>
                    <div class="stat-label">Medium Findings</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number" style="color: #4488FF;">$low_count</div>
                    <div class="stat-label">Low Findings</div>
                </div>
            </div>
        </div>
        
        <div class="filter-buttons">
            <button class="filter-btn active" data-severity="all">All Findings</button>
            <button class="filter-btn critical" data-severity="critical">Critical ($critical_count)</button>
            <button class="filter-btn high" data-severity="high">High ($high_count)</button>
            <button class="filter-btn medium" data-severity="medium">Medium ($medium_count)</button>
            <button class="filter-btn low" data-severity="low">Low ($low_count)</button>
            <button class="filter-btn info" data-severity="info">Info</button>
        </div>
EOF
}

generate_section() {
    local section_id="$1"
    local section_title="$2"
    local severity="$3"
    local content="$4"
    
    cat <<EOF
        <div class="section" id="$section_id">
            <div class="section-header">
                <div class="section-title">$section_title</div>
                <div class="section-toggle"></div>
            </div>
            <div class="section-content">
                $content
            </div>
        </div>
EOF
}

generate_finding_card() {
    local severity="$1"
    local title="$2"
    local description="$3"
    local details="$4"
    
    cat <<EOF
                <div class="finding-card $severity">
                    <div class="finding-title">
                        <span class="severity-badge severity-$severity">$severity</span>
                        $title
                    </div>
                    <div class="finding-description">$description</div>
                    $details
                </div>
EOF
}

#######################################
# Main HTML Generation
#######################################
generate_html_report() {
    local html_file="$OUTDIR/index.html"
    
    {
        # Header
        generate_html_header
        
        # Report metadata
        echo "                <div class=\"meta-item\"><strong>Target IP:</strong> ${TARGET_IP:-Unknown}</div>"
        echo "                <div class=\"meta-item\"><strong>Assessment Date:</strong> $(date '+%Y-%m-%d %H:%M:%S')</div>"
        if [[ -n "$TIMESTAMP" ]]; then
            echo "                <div class=\"meta-item\"><strong>Timestamp:</strong> $TIMESTAMP</div>"
        fi
        echo "            </div>"
        echo "        </div>"
        echo "    </div>"
        echo ""
        echo "    <div class=\"container\">"
        
        # Executive Summary
        generate_executive_summary
        
        # System Information Section
        local system_content=""
        if [[ -f "$OUTDIR/system_info/uname.txt" ]]; then
            system_content+="<h3 style='color: #FF6666; margin-top: 20px;'>System Information</h3>"
            system_content+="<pre>$(head -5 "$OUTDIR/system_info/uname.txt")</pre>"
        fi
        if [[ -f "$OUTDIR/system_info/version.txt" ]]; then
            system_content+="<h3 style='color: #FF6666; margin-top: 20px;'>Kernel Version</h3>"
            system_content+="<pre>$(head -3 "$OUTDIR/system_info/version.txt")</pre>"
        fi
        if [[ -f "$OUTDIR/system_info/cpuinfo.txt" ]]; then
            system_content+="<h3 style='color: #FF6666; margin-top: 20px;'>CPU Information</h3>"
            system_content+="<pre>$(head -15 "$OUTDIR/system_info/cpuinfo.txt")</pre>"
        fi
        if [[ -f "$OUTDIR/system_info/meminfo.txt" ]]; then
            system_content+="<h3 style='color: #FF6666; margin-top: 20px;'>Memory Information</h3>"
            system_content+="<pre>$(head -10 "$OUTDIR/system_info/meminfo.txt")</pre>"
        fi
        generate_section "system-info" "System Information" "info" "$system_content"
        
        # Process Enumeration Section
        local process_content=""
        if [[ -f "$OUTDIR/processes/ps_aux.txt" ]]; then
            process_content+="<h3 style='color: #FF6666; margin-top: 20px;'>Running Processes</h3>"
            process_content+="<table><tr><th>USER</th><th>PID</th><th>%CPU</th><th>%MEM</th><th>COMMAND</th></tr>"
            while IFS= read -r line; do
                if [[ -n "$line" ]] && [[ ! "$line" =~ ^USER ]]; then
                    user=$(echo "$line" | awk '{print $1}')
                    pid=$(echo "$line" | awk '{print $2}')
                    cpu=$(echo "$line" | awk '{print $3}')
                    mem=$(echo "$line" | awk '{print $4}')
                    cmd=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf "%s ", $i; print ""}')
                    process_content+="<tr><td>$user</td><td>$pid</td><td>$cpu</td><td>$mem</td><td>$cmd</td></tr>"
                fi
            done < <(head -20 "$OUTDIR/processes/ps_aux.txt")
            process_content+="</table>"
        fi
        generate_section "processes" "Process Enumeration" "info" "$process_content"
        
        # Network Information Section
        local network_content=""
        if [[ -f "$OUTDIR/network/interfaces.txt" ]]; then
            network_content+="<h3 style='color: #FF6666; margin-top: 20px;'>Network Interfaces</h3>"
            network_content+="<pre>$(head -30 "$OUTDIR/network/interfaces.txt")</pre>"
        fi
        if [[ -f "$OUTDIR/network/listening_ports.txt" ]]; then
            network_content+="<h3 style='color: #FF6666; margin-top: 20px;'>Listening Ports</h3>"
            network_content+="<pre>$(head -20 "$OUTDIR/network/listening_ports.txt")</pre>"
        fi
        if [[ -f "$OUTDIR/network/connections.txt" ]]; then
            network_content+="<h3 style='color: #FF6666; margin-top: 20px;'>Active Connections</h3>"
            network_content+="<pre>$(head -20 "$OUTDIR/network/connections.txt")</pre>"
        fi
        if [[ -f "$OUTDIR/network/wifi_config.txt" ]]; then
            network_content+="<h3 style='color: #FF6666; margin-top: 20px;'>WiFi Configuration</h3>"
            network_content+="<pre>$(head -20 "$OUTDIR/network/wifi_config.txt")</pre>"
        fi
        generate_section "network" "Network Information" "info" "$network_content"
        
        # Security Assessment Section
        local security_content=""
        
        # Critical: Default Credentials
        if [[ -f "$OUTDIR/vulnerabilities/credential_checks.txt" ]]; then
            if grep -qiE "(hellotuya|user123|default)" "$OUTDIR/vulnerabilities/credential_checks.txt" 2>/dev/null; then
                local cred_details="<pre>$(grep -iE "(hellotuya|user123|default)" "$OUTDIR/vulnerabilities/credential_checks.txt" | head -10)</pre>"
                security_content+=$(generate_finding_card "critical" "Default Credentials Detected" "The device uses default credentials that are publicly documented." "$cred_details")
            fi
        fi
        
        # Critical: SUID/SGID Files
        if [[ -f "$OUTDIR/security/suid_sgid_files.txt" ]]; then
            local suid_count=$(grep -c "^/" "$OUTDIR/security/suid_sgid_files.txt" 2>/dev/null || echo 0)
            if [[ $suid_count -gt 0 ]]; then
                local suid_details="<pre>$(head -20 "$OUTDIR/security/suid_sgid_files.txt")</pre>"
                security_content+=$(generate_finding_card "critical" "SUID/SGID Files Found ($suid_count)" "Files with SUID or SGID bits set may allow privilege escalation." "$suid_details")
            fi
        fi
        
        # High: World-Writable Files
        if [[ -f "$OUTDIR/security/world_writable.txt" ]]; then
            local ww_count=$(grep -c "^/" "$OUTDIR/security/world_writable.txt" 2>/dev/null || echo 0)
            if [[ $ww_count -gt 0 ]]; then
                local ww_details="<pre>$(head -20 "$OUTDIR/security/world_writable.txt")</pre>"
                security_content+=$(generate_finding_card "high" "World-Writable Files Found ($ww_count)" "Files writable by all users pose a security risk." "$ww_details")
            fi
        fi
        
        # High: Insecure Permissions in /app
        if [[ -f "$OUTDIR/security/app_insecure_perms.txt" ]]; then
            local app_perm_count=$(grep -c "^/" "$OUTDIR/security/app_insecure_perms.txt" 2>/dev/null || echo 0)
            if [[ $app_perm_count -gt 0 ]]; then
                local app_perm_details="<pre>$(head -20 "$OUTDIR/security/app_insecure_perms.txt")</pre>"
                security_content+=$(generate_finding_card "high" "Insecure Permissions in Application Directory ($app_perm_count)" "Application files have insecure permissions." "$app_perm_details")
            fi
        fi
        
        # Medium: Password Analysis
        if [[ -f "$OUTDIR/security/password_analysis.txt" ]]; then
            if grep -qiE "(empty|disabled)" "$OUTDIR/security/password_analysis.txt" 2>/dev/null; then
                local pass_details="<pre>$(grep -iE "(empty|disabled)" "$OUTDIR/security/password_analysis.txt" | head -10)</pre>"
                security_content+=$(generate_finding_card "medium" "Weak Password Configuration" "Some user accounts have empty or disabled passwords." "$pass_details")
            fi
        fi
        
        # File Permissions
        if [[ -f "$OUTDIR/security/file_permissions.txt" ]]; then
            security_content+="<h3 style='color: #FF6666; margin-top: 20px;'>File Permissions Analysis</h3>"
            security_content+="<pre>$(head -30 "$OUTDIR/security/file_permissions.txt")</pre>"
        fi
        
        generate_section "security" "Security Assessment" "high" "$security_content"
        
        # Vulnerability Assessment Section
        local vuln_content=""
        
        if [[ -f "$OUTDIR/vulnerabilities/version_checks.txt" ]]; then
            vuln_content+="<h3 style='color: #FF6666; margin-top: 20px;'>Software Versions</h3>"
            vuln_content+="<pre>$(head -30 "$OUTDIR/vulnerabilities/version_checks.txt")</pre>"
        fi
        
        if [[ -f "$OUTDIR/vulnerabilities/security_issues.txt" ]]; then
            vuln_content+="<h3 style='color: #FF6666; margin-top: 20px;'>Security Issues Summary</h3>"
            vuln_content+="<pre>$(head -50 "$OUTDIR/vulnerabilities/security_issues.txt")</pre>"
        fi
        
        if [[ -f "$OUTDIR/vulnerabilities/cve_check.txt" ]]; then
            vuln_content+="<h3 style='color: #FF6666; margin-top: 20px;'>CVE Database Check</h3>"
            vuln_content+="<pre>$(cat "$OUTDIR/vulnerabilities/cve_check.txt")</pre>"
        fi
        
        generate_section "vulnerabilities" "Vulnerability Assessment" "high" "$vuln_content"
        
        # File System Analysis Section
        local fs_content=""
        if [[ -f "$OUTDIR/filesystem/app_directory_listing.txt" ]]; then
            fs_content+="<h3 style='color: #FF6666; margin-top: 20px;'>Application Directory (/app)</h3>"
            fs_content+="<pre>$(head -30 "$OUTDIR/filesystem/app_directory_listing.txt")</pre>"
        fi
        if [[ -f "$OUTDIR/filesystem/etc_passwd.txt" ]]; then
            fs_content+="<h3 style='color: #FF6666; margin-top: 20px;'>User Accounts</h3>"
            fs_content+="<pre>$(cat "$OUTDIR/filesystem/etc_passwd.txt")</pre>"
        fi
        generate_section "filesystem" "File System Analysis" "info" "$fs_content"
        
        # Application/Webcam Specific Section
        local app_content=""
        if [[ -f "$OUTDIR/application/app_files_listing.txt" ]]; then
            app_content+="<h3 style='color: #FF6666; margin-top: 20px;'>Application Files</h3>"
            app_content+="<pre>$(head -30 "$OUTDIR/application/app_files_listing.txt")</pre>"
        fi
        if [[ -f "$OUTDIR/application/firmware_version.txt" ]]; then
            app_content+="<h3 style='color: #FF6666; margin-top: 20px;'>Firmware Version</h3>"
            app_content+="<pre>$(cat "$OUTDIR/application/firmware_version.txt")</pre>"
        fi
        if [[ -f "$OUTDIR/application/config_files.txt" ]]; then
            app_content+="<h3 style='color: #FF6666; margin-top: 20px;'>Configuration Files</h3>"
            app_content+="<pre>$(cat "$OUTDIR/application/config_files.txt")</pre>"
        fi
        generate_section "application" "Application/Webcam Specific" "info" "$app_content"
        
        # Services & Startup Section
        local services_content=""
        if [[ -f "$OUTDIR/services/running_services.txt" ]]; then
            services_content+="<h3 style='color: #FF6666; margin-top: 20px;'>Running Services</h3>"
            services_content+="<pre>$(cat "$OUTDIR/services/running_services.txt")</pre>"
        fi
        if [[ -f "$OUTDIR/services/cron_root.txt" ]]; then
            services_content+="<h3 style='color: #FF6666; margin-top: 20px;'>Cron Jobs (Root)</h3>"
            services_content+="<pre>$(cat "$OUTDIR/services/cron_root.txt")</pre>"
        fi
        generate_section "services" "Services & Startup" "info" "$services_content"
        
        # Extracted Files Section
        local extracted_content=""
        if [[ -f "$OUTDIR/extracted/extraction_summary.txt" ]]; then
            extracted_content+="<h3 style='color: #FF6666; margin-top: 20px;'>Extraction Summary</h3>"
            extracted_content+="<pre>$(cat "$OUTDIR/extracted/extraction_summary.txt")</pre>"
        fi
        generate_section "extracted" "Extracted Files" "info" "$extracted_content"
        
        # Recommendations Section
        local recommendations_content="
            <div class=\"recommendations\">
                <h3 style='color: #00AA00; margin-bottom: 15px;'>Security Recommendations</h3>
                <ul>
                    <li><strong>Immediate Actions:</strong> Change all default credentials immediately. The device uses publicly documented default passwords.</li>
                    <li><strong>File Permissions:</strong> Review and restrict file permissions, especially for SUID/SGID files and world-writable files.</li>
                    <li><strong>Network Security:</strong> Implement firewall rules to restrict unnecessary network access and close unused ports.</li>
                    <li><strong>Firmware Updates:</strong> Update to the latest firmware version to address known vulnerabilities.</li>
                    <li><strong>Access Control:</strong> Implement proper authentication mechanisms and disable unnecessary services.</li>
                    <li><strong>Monitoring:</strong> Enable logging and monitoring for security events and unauthorized access attempts.</li>
                    <li><strong>Regular Audits:</strong> Conduct regular security assessments and penetration testing.</li>
                </ul>
            </div>
        "
        generate_section "recommendations" "Recommendations" "low" "$recommendations_content"
        
        echo "    </div>"
        
        # Footer
        generate_html_footer
        
    } > "$html_file"
    
    echo "[+] HTML report generated: $html_file"
}

#######################################
# Main
#######################################
main() {
    echo "[*] Generating Red Team HTML report..."
    echo "[*] Output directory: $OUTDIR"
    
    generate_html_report
    
    echo "[+] Report generation complete"
    echo "[+] Open $OUTDIR/index.html in a web browser to view the report"
}

main "$@"

