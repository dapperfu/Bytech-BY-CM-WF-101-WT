# Bytech BY-CM-WF-101-WT Security Assessment

## Executive Summary

This repository documents a comprehensive security assessment of the Bytech BY-CM-WF-101-WT indoor 1080p smart camera. The assessment was conducted using a custom IoT penetration testing suite to evaluate network exposure, service enumeration, credential security, and internal device configuration.

The device was found to contain multiple critical security vulnerabilities, including exposed Telnet services with default credentials, unencrypted network protocols, and weak access controls. Full assessment reports and tool outputs are available in the repository.

**Target Device:** [Bytech BY-CM-WF-101-WT](https://www.menards.com/main/electrical/alarms-security-systems/security-cameras/bytech-reg-indoor-1080p-smart-camera/by-cm-wf-101-wt/p-1642874359318832-c-1530022081634.htm)

**Reference:** Original research by [AzureADTrent/Bytech-BY-CM-WF-101-WT](https://github.com/AzureADTrent/Bytech-BY-CM-WF-101-WT)

--------------- Assessment Reports  --------------- 

## Critical Findings

### Network Exposure
- **Telnet service (port 23)**: Exposed with default credentials
- **HTTP service (port 843)**: Web interface accessible without authentication
- **RTSP service (port 8554)**: Unencrypted video streaming protocol
- **Additional services**: Ports 1300, 6668, 8699 identified and enumerated

### Default Credentials
- **User account**: `user` / `user123`
- **Root account**: `root` / `hellotuya`
- Both accounts accessible via Telnet in AP mode and on local network

### Assessment Reports

**External Network Enumeration:**
- [Full HTML Report](iot_enum_10.0.0.227_20260107_204102/report.html)
- [Summary Report](iot_enum_10.0.0.227_20260107_204102/summary.txt)
- [Default Credentials Test](iot_enum_10.0.0.227_20260107_204102/default_creds.txt)
- [Telnet Connection Test](iot_enum_10.0.0.227_20260107_204102/telnet_test.txt)
- [RTSP Connection Test](iot_enum_10.0.0.227_20260107_204102/rtsp_connection_test.txt)

**Internal Device Analysis:**
- [Internal Security Assessment](iot_internal_10.0.0.227_20260107_221109/index.html)
- Filesystem enumeration, process analysis, network configuration, and security posture assessment

### Methodology

The assessment utilized a comprehensive IoT penetration testing suite including:
- Network scanning (Nmap, Masscan)
- Service enumeration and vulnerability scanning
- Credential testing and brute-force analysis
- Protocol-specific enumeration (RTSP, ONVIF, UPnP)
- Internal device probing and filesystem analysis
- Security configuration review

Full tool documentation and usage instructions are provided in the sections below.












--------------- Original ReadMe Cursor Do Not Edit Below --------------- 

# Bytech-BY-CM-WF-101-WT
This is repo for keeping track of the Bytech security camera BY-CM-WF-101-WT details found during testing of the hardware.

## Disassembly
This repo contains photos of the diassembly of the device to access the main board. Check out Photos to see this process.
#### Note: This process may damage your casing if you aren't careful. You may need a slim metal object to pry up the front face to gain access to the body screws.

## Telnet
The Bytech BY-CM-WF-101-WT model camera hosts a telnet server that is accessible in AP mode as well as after setup on the local network.

### These are the default passwords for each account to login over telnet
#### User
username: user

password: user123
#### Root
username: root

password: hellotuya

## IoT Penetration Testing Suite

This repository includes a comprehensive penetration testing suite for IoT devices and WebCams, with specialized tools for network scanning, service enumeration, credential testing, and vulnerability assessment.

### Prerequisites

- Docker installed and running
- Python 3 with PyYAML module (for configuration parsing): `pip3 install pyyaml`
- Network access to target device
- Appropriate permissions for network scanning

### Quick Start

1. **Prefetch Docker images:**
   ```bash
   ./scripts/iot-mega-enum-prefetch.sh
   ```

2. **Run penetration test:**
   ```bash
   ./scripts/iot-mega-enum.sh <target-ip> [interface] [config-file]
   ```

   Example:
   ```bash
   ./scripts/iot-mega-enum.sh 192.168.1.100 eth0 scripts/iot-config.yaml
   ```

3. **View results:**
   - HTML report: `iot_enum_<ip>_<timestamp>/report.html`
   - Summary report: `iot_enum_<ip>_<timestamp>/summary.txt`
   - Detailed tool outputs in the output directory

### Tools Included

#### Network Scanning
- **Nmap**: Comprehensive network scanning and service detection
- **Masscan**: Fast port scanning

#### Service Enumeration
- **Nmap Scripts**: Deep service enumeration with NSE scripts
- **Nikto**: Web server vulnerability scanner

#### Credential Testing
- **Hydra**: Credential brute-forcing for multiple protocols
- **Default Credential Testing**: Tests common IoT/WebCam default credentials

#### Protocol-Specific Tools
- **RTSP Scanner**: RTSP stream discovery and enumeration
- **ONVIF Scanner**: ONVIF camera device discovery and enumeration
- **UPnP Scanner**: UPnP device discovery and information gathering
- **Telnet/SSH/HTTP**: Protocol-specific enumeration

#### Vulnerability Testing
- **CVE Checking**: Matches discovered services against known CVEs
- **Protocol Exploit Testing**: Tests for protocol-specific vulnerabilities
- **Firmware Analysis**: Attempts firmware extraction and analysis

#### Exploitation (Optional)
- **Metasploit Framework**: Exploitation framework (disabled by default)

### Configuration File

The suite uses a YAML configuration file (`scripts/iot-config.yaml`) to control which tools are executed and how they run.

#### Configuration Structure

```yaml
tools:
  network_scanning:
    nmap: true
    masscan: true
  service_enumeration:
    nmap_scripts: true
    nikto: true
  credential_testing:
    hydra: true
    default_creds: true
  exploitation:
    metasploit: false  # Disabled by default
  protocol_specific:
    rtsp: true
    onvif: true
    upnp: true
    telnet: true
    ssh: true
    http: true

execution:
  mode: smart  # smart, parallel, sequential
  max_parallel: 4

vulnerability_testing:
  default_credentials:
    enabled: true
    wordlists:
      - scripts/wordlists/common-passwords.txt
      - scripts/wordlists/camera-passwords.txt
  known_cves:
    enabled: true
    database: scripts/data/cve-database.json
  firmware_analysis:
    enabled: true
  protocol_exploits:
    enabled: true

reporting:
  html: true
  summary: true
  json: false
```

#### Execution Modes

- **smart**: Automatically detects dependencies and runs tools in parallel where possible
- **parallel**: Runs all independent tools in parallel (respects max_parallel limit)
- **sequential**: Runs all tools one after another

### Output Structure

Each penetration test creates a timestamped output directory:

```
iot_enum_<ip>_<timestamp>/
├── report.html              # HTML report with all findings
├── summary.txt               # Text summary report
├── execution.log            # Execution log
├── open_ports.txt           # List of open ports
├── fastscan.*               # Initial port scan results
├── deep.*                   # Deep service enumeration results
├── nikto_*.txt              # Nikto scan results per port
├── rtsp_scan.txt             # RTSP enumeration results
├── onvif_scan.txt           # ONVIF enumeration results
├── upnp_scan.txt            # UPnP enumeration results
├── default_creds.txt        # Default credential test results
├── hydra_*.txt              # Hydra brute-force results
├── cve_check.txt            # CVE check results
├── protocol_exploits.txt    # Protocol exploit test results
├── firmware_analysis.txt    # Firmware analysis results
└── traffic.pcap             # Network traffic capture
```

### Report Interpretation

#### HTML Report

The HTML report provides:
- **Executive Summary**: Quick overview of findings
- **Network Scan Results**: Open ports and services
- **Service Enumeration**: Detailed service information
- **Protocol-Specific Findings**: RTSP, ONVIF, UPnP discoveries
- **Vulnerability Assessment**: Credentials, CVEs, exploits
- **Recommendations**: Security improvement suggestions

#### Summary Report

The text summary includes:
- Target information and scan date
- Open ports list
- Services detected
- Critical findings (default credentials, vulnerabilities)
- List of generated files

### Docker Images

The suite uses both pre-built Docker images and custom-built images:

#### Pre-built Images
- `ivre/client`: IVRE network recon framework
- `jess/masscan`: Masscan port scanner
- `uzyexe/nmap`: Nmap network scanner
- `aler9/rtsp-simple-server`: RTSP server for testing
- `frapsoft/nikto`: Nikto web scanner
- `metasploitframework/metasploit-framework`: Metasploit framework

#### Custom Images (Built from Dockerfiles)
- `iot-pentest/hydra`: THC-Hydra credential brute-forcer
- `iot-pentest/nikto`: Alternative Nikto image
- `iot-pentest/metasploit`: Metasploit wrapper
- `iot-pentest/onvif-tools`: ONVIF CLI tools
- `iot-pentest/upnp-tools`: UPnP discovery tools

Custom images are automatically built during the prefetch process.

### Security Considerations

⚠️ **Important Security Notes:**

1. **Legal Authorization**: Only use this suite on devices you own or have explicit written authorization to test
2. **Metasploit**: Disabled by default - enable only if you understand the risks
3. **Rate Limiting**: Credential brute-forcing respects rate limits to avoid DoS
4. **Disruptive Tools**: Some tools may cause service disruption - use with caution
5. **Network Impact**: Network scanning may trigger security alerts

### Troubleshooting

#### Docker Issues
- Ensure Docker daemon is running: `docker info`
- Check Docker images: `docker images`
- Rebuild custom images: `./scripts/iot-mega-enum-prefetch.sh`

#### Configuration Parsing
- Install PyYAML: `pip3 install pyyaml`
- Verify config file syntax: `python3 -c "import yaml; yaml.safe_load(open('scripts/iot-config.yaml'))"`

#### Tool Execution Failures
- Check execution log: `iot_enum_*/execution.log`
- Verify network connectivity to target
- Ensure required ports are accessible
- Check Docker container logs

### Contributing

When adding new tools:
1. Add Docker image to `iot-mega-enum-prefetch.sh`
2. Create tool execution function in `iot-mega-enum.sh`
3. Add configuration options to `iot-config.yaml`
4. Update report generator if needed
5. Update this README

### License

This penetration testing suite is for authorized security testing only. Users are responsible for ensuring they have proper authorization before testing any devices.
