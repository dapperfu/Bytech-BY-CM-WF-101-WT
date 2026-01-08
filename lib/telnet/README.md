# Telnet Automation Framework

A comprehensive Python-based telnet automation framework for IoT device management, supporting both one-time scripts and long-running services with connection pooling.

## Features

- **Dual API Support**: Both synchronous (for scripts) and asynchronous (for services) APIs
- **Connection Pooling**: Persistent connections with automatic reconnection and health checks
- **Device Profiles**: Extensible profile system with auto-detection for different device types
- **Structured Logging**: JSON logging with text output compatibility
- **REST API**: FastAPI-based API for programmatic access
- **CLI Daemon**: Background service with CLI control
- **Comprehensive Testing**: Unit tests with mocks + optional integration tests

## Installation

```bash
# Install dependencies
pip install -e .

# Or with dev dependencies
pip install -e ".[dev]"
```

## Quick Start

### One-Time Scripts

```python
from lib.telnet.sync_client import SyncTelnetClient

# Connect and execute command
with SyncTelnetClient(host="10.0.0.227", username="root", password="pass") as client:
    output = client.execute("uname -a")
    print(output)
```

### CLI Usage

```bash
# Execute command
python -m lib.telnet.cli execute --target 10.0.0.227 --username root --password pass "uname -a"

# Interactive shell
python -m lib.telnet.cli shell --target 10.0.0.227 --username root --password pass
```

### Long-Running Service

```python
from lib.telnet.service import TelnetService
import asyncio

async def main():
    service = TelnetService()
    await service.start()
    
    # Connect device
    await service.connect_device("10.0.0.227", username="root", password="pass")
    
    # Execute command
    output = await service.execute_command("10.0.0.227", "uname -a")
    print(output)
    
    await service.stop()

asyncio.run(main())
```

### REST API

```bash
# Start API server
python -m lib.telnet.api.app

# Connect device
curl -X POST http://localhost:8000/devices/10.0.0.227/connect \
  -H "Content-Type: application/json" \
  -d '{"username": "root", "password": "pass"}'

# Execute command
curl -X POST http://localhost:8000/devices/10.0.0.227/execute \
  -H "Content-Type: application/json" \
  -d '{"command": "uname -a"}'
```

## API Documentation

### Synchronous API

`SyncTelnetClient` provides a thread-safe synchronous interface:

```python
from lib.telnet.sync_client import SyncTelnetClient

client = SyncTelnetClient(host="10.0.0.227", username="root", password="pass")
client.connect()
output = client.execute("command")
client.disconnect()
```

### Asynchronous API

`AsyncTelnetClient` provides a non-blocking async interface:

```python
from lib.telnet.async_client import AsyncTelnetClient

async def main():
    async with AsyncTelnetClient(host="10.0.0.227", username="root", password="pass") as client:
        output = await client.execute("command")
        print(output)
```

### Connection Pool

`ConnectionPool` manages multiple device connections:

```python
from lib.telnet.pool import ConnectionPool

async def main():
    async with ConnectionPool() as pool:
        # Connect devices
        await pool.connect("10.0.0.227", username="root", password="pass")
        await pool.connect("10.0.0.228", username="root", password="pass")
        
        # Execute commands
        client1 = await pool.get("10.0.0.227")
        output = await client1.execute("uname -a")
```

## Device Profiles

The framework supports device profiles for different IoT device types:

- **BusyBox**: BusyBox-based embedded devices
- **Linux**: Standard Linux systems
- **Custom**: Unknown devices with auto-detection

```python
from lib.telnet.sync_client import SyncTelnetClient
from lib.telnet.profiles import get_profile

# Auto-detect profile
client = SyncTelnetClient(host="10.0.0.227", username="root", password="pass")
client.connect()
profile = get_profile(client=client)

# Use specific profile
from lib.telnet.profiles import BusyBoxProfile
client = SyncTelnetClient(host="10.0.0.227", profile=BusyBoxProfile())
```

## Configuration

Configuration can be loaded from YAML files or environment variables:

```yaml
# telnet-config.yaml
telnet:
  default_port: 23
  default_username: root
  default_password: ""
  default_timeout: 30.0
  
  service:
    max_connections: 10
    health_check_interval: 30.0
    reconnect_delay: 2.0
  
  devices:
    device1:
      host: 10.0.0.227
      username: root
      password: pass
```

## Migration from Expect Scripts

The framework provides Python equivalents of existing expect scripts:

### Before (expect script)
```bash
execute_command() {
    local cmd="$1"
    expect <<EOF
    spawn telnet $TARGET_IP $TELNET_PORT
    expect "login:" { send "$USERNAME\r" }
    expect "# " { send "$cmd\r" }
    expect "# " { puts \$expect_out(buffer) }
EOF
}
```

### After (Python)
```python
from lib.telnet.sync_client import SyncTelnetClient

def execute_command(host, username, password, command):
    with SyncTelnetClient(host=host, username=username, password=password) as client:
        return client.execute(command)
```

## Testing

```bash
# Run unit tests
pytest tests/

# Run with coverage
pytest --cov=lib.telnet tests/

# Run integration tests (requires real devices)
pytest -m integration tests/integration/
```

## Examples

See `scripts/python/` for example scripts:
- `execute_command.py`: Basic command execution
- `analyze_connections.py`: Network connection analysis
- `block_cloud_process.py`: Process-level cloud blocking

## License

MIT

