# Assessment Reports

## Overview

This document provides links to all security assessment reports generated during the evaluation of the Bytech BY-CM-WF-101-WT camera.

## External Network Enumeration

### Full HTML Report
- **Location**: [iot_enum_10.0.0.227_20260107_204102/report.html](../iot_enum_10.0.0.227_20260107_204102/report.html)
- **Content**: Comprehensive network scan results, service enumeration, and vulnerability assessment
- **Format**: HTML with interactive navigation

### Summary Report
- **Location**: [iot_enum_10.0.0.227_20260107_204102/summary.txt](../iot_enum_10.0.0.227_20260107_204102/summary.txt)
- **Content**: High-level summary of findings and discovered services
- **Format**: Plain text

### Default Credentials Test
- **Location**: [iot_enum_10.0.0.227_20260107_204102/default_creds.txt](../iot_enum_10.0.0.227_20260107_204102/default_creds.txt)
- **Content**: Results of default credential testing
- **Format**: Plain text

### Telnet Connection Test
- **Location**: [iot_enum_10.0.0.227_20260107_204102/telnet_test.txt](../iot_enum_10.0.0.227_20260107_204102/telnet_test.txt)
- **Content**: Telnet service connection and authentication test results
- **Format**: Plain text

### RTSP Connection Test
- **Location**: [iot_enum_10.0.0.227_20260107_204102/rtsp_connection_test.txt](../iot_enum_10.0.0.227_20260107_204102/rtsp_connection_test.txt)
- **Content**: RTSP stream discovery and connection test results
- **Format**: Plain text

## Internal Device Analysis

### Internal Security Assessment
- **Location**: [iot_internal_10.0.0.227_20260107_221109/index.html](../iot_internal_10.0.0.227_20260107_221109/index.html)
- **Content**: Comprehensive internal device security assessment including:
  - Filesystem enumeration
  - Process analysis
  - Network configuration review
  - Security posture assessment
  - Application analysis
  - Service enumeration
- **Format**: HTML with detailed sections

## Report Structure

### External Enumeration Reports
Located in: `iot_enum_<ip>_<timestamp>/`
- Network scan results
- Service enumeration
- Credential testing
- Protocol-specific tests

### Internal Analysis Reports
Located in: `iot_internal_<ip>_<timestamp>/`
- Filesystem structure
- Process information
- Network configuration
- Security configurations
- Application binaries
- System logs

## Generating New Reports

To generate new assessment reports, use the IoT penetration testing suite:

```bash
# External enumeration
make enum TARGET_IP=<ip-address>

# Internal probing
make probe TARGET_IP=<ip-address> USERNAME=root PASSWORD=hellotuya
```

See the main [README](../README.md) for full usage instructions.

## Related Documentation

- [Network Exposure](network-exposure.md)
- [Default Credentials](default-credentials.md)
- [Security Methodology](methodology.md)

