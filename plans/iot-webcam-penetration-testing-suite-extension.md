---
name: IoT WebCam Penetration Testing Suite Extension
overview: Extend the existing IoT enumeration scripts with comprehensive penetration testing tools targeting IoT devices and WebCams, including Hydra, Metasploit, Nikto, ONVIF tools, RTSP tools, and UPnP tools. Add smart parallel/sequential execution, configuration file support, HTML reporting, and vulnerability testing capabilities.
todos:
  - id: save-plan
    content: Save plan to plans/ folder as first TODO item
    status: completed
  - id: extend-prefetch
    content: Extend iot-mega-enum-prefetch.sh with new Docker images (Hydra, Metasploit, Nikto, ONVIF, UPnP)
    status: in_progress
    dependencies:
      - save-plan
  - id: create-config
    content: Create iot-config.yaml configuration file with tool selection, execution mode, and vulnerability testing options
    status: pending
    dependencies:
      - save-plan
  - id: create-dockerfiles
    content: Create Dockerfiles for tools without existing images (hydra, metasploit, nikto, onvif-tools, upnp-tools)
    status: pending
    dependencies:
      - save-plan
  - id: add-config-parsing
    content: Add YAML configuration file parsing to iot-mega-enum.sh using yq or python-yaml
    status: pending
    dependencies:
      - create-config
  - id: implement-tool-functions
    content: Implement tool execution functions in iot-mega-enum.sh (run_hydra, run_nikto, run_metasploit, run_onvif_scan, run_rtsp_scan, run_upnp_scan)
    status: pending
    dependencies:
      - add-config-parsing
  - id: implement-smart-execution
    content: Implement smart execution mode with dependency detection and parallel execution logic
    status: pending
    dependencies:
      - implement-tool-functions
  - id: add-vulnerability-testing
    content: Add vulnerability testing functions (default_creds, cve_checking, protocol_exploits, firmware_analysis)
    status: pending
    dependencies:
      - implement-tool-functions
  - id: create-report-generator
    content: Create iot-report-generator.sh script for HTML and summary report generation
    status: pending
    dependencies:
      - implement-smart-execution
  - id: integrate-reporting
    content: Integrate report generation into main enumeration script execution flow
    status: pending
    dependencies:
      - create-report-generator
  - id: update-documentation
    content: Update README.md with new tools, configuration, usage examples, and report interpretation
    status: completed
    dependencies:
      - integrate-reporting
  - id: test-suite
    content: Test complete suite with actual IoT device, verify all tools execute correctly, validate reports
    status: completed
    dependencies:
      - update-documentation
---

# IoT WebCam Penetrati

on Testing Suite Extension

## Overview

Extend `scripts/iot-mega-enum.sh` and `scripts/iot-mega-enum-prefetch.sh` with comprehensive penetration testing tools for IoT devices and WebCams. Add configuration file support, smart execution orchestration, HTML reporting, and vulnerability testing capabilities.

## Architecture

```javascript
scripts/
├── iot-mega-enum-prefetch.sh      # Extended: Add new Docker images
├── iot-mega-enum.sh                # Extended: Main orchestration script
├── iot-config.yaml                 # New: Tool configuration file
├── iot-report-generator.sh         # New: HTML report generator
└── dockerfiles/                    # New: Dockerfiles for tools without images
    ├── hydra/
    ├── metasploit/
    ├── nikto/
    ├── onvif-tools/
    └── upnp-tools/
```



## Implementation Tasks

### 1. Extend Prefetch Script (`scripts/iot-mega-enum-prefetch.sh`)

**Add Docker images to prefetch:**

- `vanhauser-thc/thc-hydra` or `frapsoft/hydra` (credential brute-forcing)

- `metasploitframework/metasploit-framework` (exploitation framework)

- `frapsoft/nikto` or `crazymax/nikto` (web server scanner)
- `aler9/rtsp-simple-server` (already present, verify)

- ONVIF tools: Check for `alcalzone/onvif-cli` alternative or create Dockerfile
- UPnP tools: Check for existing images or create Dockerfile

- `ivre/client` (already present)

**Update container warming section** to test all new images.

### 2. Create Configuration File (`scripts/iot-config.yaml`)

**Structure:**

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
    metasploit: false  # Optional, more dangerous
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
    - /path/to/common-passwords.txt
    - /path/to/camera-passwords.txt
  known_cves:
    enabled: true
    database: cve-database.json
  firmware_analysis:
    enabled: true
  protocol_exploits:
    enabled: true

reporting:
  html: true
  summary: true
  json: false
```



### 3. Extend Main Enumeration Script (`scripts/iot-mega-enum.sh`)

**Add functionality:**

- Parse `iot-config.yaml` configuration file

- Implement smart execution mode (dependency detection, parallel execution for independent tools)
- Add tool execution functions:

- `run_hydra()` - Credential brute-forcing for discovered services

- `run_nikto()` - Web server vulnerability scanning

- `run_metasploit()` - Exploitation framework (optional, configurable)
- `run_onvif_scan()` - ONVIF device discovery and enumeration

- `run_rtsp_scan()` - RTSP stream enumeration and authentication testing

- `run_upnp_scan()` - UPnP device discovery and information gathering
- `test_default_creds()` - Test common IoT/WebCam default credentials

- `check_known_cves()` - Match discovered services against CVE database

- `analyze_firmware()` - Firmware extraction and analysis (if accessible)

**Execution flow:**

1. Parse config file

2. Run network scanning (sequential, required first)
3. Identify services and protocols

4. Run protocol-specific tools in parallel where possible
5. Run vulnerability tests

6. Generate reports

### 4. Create Dockerfiles for Missing Tools

**Create Dockerfiles in `scripts/dockerfiles/`:**

- **`dockerfiles/hydra/Dockerfile`**: Based on Alpine, install THC-Hydra

- **`dockerfiles/metasploit/Dockerfile`**: Based on official Metasploit image or Kali

- **`dockerfiles/nikto/Dockerfile`**: Based on Alpine, install Nikto

- **`dockerfiles/onvif-tools/Dockerfile`**: Install ONVIF CLI tools (onvif-cli, python-onvif-zeep)

- **`dockerfiles/upnp-tools/Dockerfile`**: Install UPnP tools (upnp-info, upnpc)

**Each Dockerfile should:**

- Use minimal base images (Alpine preferred)

- Install only necessary dependencies

- Set appropriate working directories
- Include version tags

### 5. Create Report Generator (`scripts/iot-report-generator.sh`)

**Generate HTML report with:**

- Executive summary (target IP, scan date, total findings)

- Network scan results (open ports, services)

- Service enumeration results (banners, versions)

- Protocol-specific findings (RTSP streams, ONVIF devices, UPnP services)
- Vulnerability findings (default credentials, CVEs, protocol exploits)

- Tool execution logs
- Recommendations

**Generate summary report (text) with:**

- Quick overview
- Critical findings

- Open ports summary

- Service versions

- Credential test results

### 6. Add Smart Execution Logic

**Dependency detection:**

- Network scanning must complete before service enumeration

- Service enumeration must complete before protocol-specific tools

- Credential testing can run in parallel with vulnerability scanning

- Reporting runs last (depends on all tools)

**Parallel execution:**

- Group independent tools (e.g., RTSP scan, ONVIF scan, UPnP scan can run simultaneously)
- Limit concurrent executions (configurable, default 4)
- Track tool completion and dependencies

### 7. Add Vulnerability Testing Functions

**Default credential testing:**

- Common IoT/WebCam credentials (admin/admin, admin/12345, root/root, etc.)

- Test discovered services (HTTP, Telnet, SSH, RTSP, ONVIF)

- Use Hydra for brute-forcing

- Maintain wordlist of common camera passwords

**CVE checking:**

- Match discovered service versions against CVE database

- Use NVD API or local CVE database

- Report CVEs with severity scores

**Protocol exploit testing:**

- RTSP authentication bypass attempts
- ONVIF authentication issues

- UPnP information disclosure

- HTTP authentication weaknesses

**Firmware analysis:**

- Attempt firmware extraction from HTTP endpoints

- Analyze firmware if accessible

- Check for hardcoded credentials, backdoors

### 8. Update Documentation

**Update README.md with:**

- New tool descriptions
- Configuration file format

- Usage examples

- Docker image requirements

- Report interpretation guide

## File Changes

### Modified Files

- `scripts/iot-mega-enum-prefetch.sh`: Add new Docker images, update warming section

- `scripts/iot-mega-enum.sh`: Major extension with new tools, config parsing, smart execution, reporting

### New Files

- `scripts/iot-config.yaml`: Configuration file for tool selection and execution

- `scripts/iot-report-generator.sh`: HTML and summary report generation

- `scripts/dockerfiles/hydra/Dockerfile`: Hydra Docker image

- `scripts/dockerfiles/metasploit/Dockerfile`: Metasploit Docker image

- `scripts/dockerfiles/nikto/Dockerfile`: Nikto Docker image

- `scripts/dockerfiles/onvif-tools/Dockerfile`: ONVIF tools Docker image

- `scripts/dockerfiles/upnp-tools/Dockerfile`: UPnP tools Docker image

## Dependencies

- Docker (required)

- yq or python-yaml (for YAML parsing in bash)

- jq (for JSON processing in reports)

- Standard Unix tools (grep, awk, sed, etc.)

## Testing Considerations

- Test with actual IoT device (Bytech camera)

- Verify Docker images build and run correctly
- Test parallel execution with multiple tools

- Validate HTML report generation

- Test configuration file parsing

- Verify vulnerability detection accuracy

## Security Considerations

- Metasploit execution should be opt-in (disabled by default in config)
- Credential brute-forcing should respect rate limits

- Add warnings for potentially disruptive tools