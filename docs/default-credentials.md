# Default Credentials

## Overview

The Bytech BY-CM-WF-101-WT camera uses hardcoded default credentials for multiple accounts, accessible via Telnet service.

## Credential Details

### User Account
- **Username**: `user`
- **Password**: `user123`
- **Access Level**: User-level access
- **Access Method**: Telnet (port 23)

### Root Account
- **Username**: `root`
- **Password**: `hellotuya`
- **Access Level**: Root/administrative access
- **Access Method**: Telnet (port 23)

## Access Points

Both accounts are accessible via Telnet in:
1. **AP Mode**: When device is in access point mode during initial setup
2. **Local Network**: After device is configured and connected to local network

## Security Implications

1. **Unauthorized Access**: Anyone with network access can gain device access
2. **Privilege Escalation**: Root account provides full system control
3. **Persistent Risk**: Credentials cannot be changed (hardcoded)
4. **Network Exposure**: Telnet service exposed on local network

## Testing Results

Default credentials were successfully tested and confirmed:
- [Default Credentials Test](../iot_enum_10.0.0.227_20260107_204102/default_creds.txt)
- [Telnet Connection Test](../iot_enum_10.0.0.227_20260107_204102/telnet_test.txt)

## Recommendations

1. **Immediate**: Change default credentials (if device supports it)
2. **Network**: Restrict Telnet access via firewall rules
3. **Long-term**: Disable Telnet service entirely
4. **Alternative**: Use SSH with key-based authentication if available

## Related Documentation

- [Network Exposure](network-exposure.md)
- [Assessment Reports](assessment-reports.md)
- [Security Methodology](methodology.md)

