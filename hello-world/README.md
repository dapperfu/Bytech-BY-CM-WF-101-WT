# Hello World Projects for ARMv6 FH8616

This directory contains simple "Hello, World!" programs in C, C++, and Rust, cross-compiled for the ARMv6 FH8616 chipset, along with scripts to build and transfer them to the target device.

## Project Structure

```
hello-world/
├── c/              # C hello world (ANSI C89)
│   ├── hello.c
│   └── Makefile
├── cpp/            # C++ hello world (C++11)
│   ├── hello.cpp
│   └── CMakeLists.txt
├── rust/           # Rust hello world
│   ├── Cargo.toml
│   └── src/
│       └── main.rs
├── bin/            # Compiled binaries (created by build.sh)
├── build.sh        # Build automation script
├── transfer-and-run.sh  # Transfer and execution script
└── README.md       # This file
```

## Prerequisites

- Docker (for cross-compilation)
- `expect` (for telnet automation)
- `lrzsz` (optional, for zmodem transfer)
- `sshpass` or `expect` (for SCP transfer)
- Python 3 (for HTTP server fallback)

## Building

### Build All Projects

```bash
./hello-world/build.sh
```

This will build all three projects (C, C++, Rust) and place the binaries in `hello-world/bin/`.

### Build Individual Projects

```bash
./hello-world/build.sh c      # Build C only
./hello-world/build.sh cpp    # Build C++ only
./hello-world/build.sh rust   # Build Rust only
```

The build script uses the `iot-pentest/armv6-cross-compile` Docker image. If the image doesn't exist, it will be built automatically.

## Transferring and Running

### Transfer and Execute

```bash
./hello-world/transfer-and-run.sh [target-ip] [username] [password]
```

Example:
```bash
./hello-world/transfer-and-run.sh 10.0.0.227 root hellotuya
```

### Transfer Only (No Execution)

```bash
./hello-world/transfer-and-run.sh 10.0.0.227 root hellotuya --transfer-only
```

## Transfer Methods

The script automatically detects and uses the best available transfer method:

1. **zmodem** (preferred for embedded devices)
   - Uses `rz` command on target
   - Requires `lrzsz` package on host
   - Most reliable for embedded Linux devices

2. **SCP** (if SSH available)
   - Uses standard `scp` command
   - Requires SSH server on target (port 22)

3. **HTTP + wget** (fallback)
   - Starts local HTTP server on host
   - Uses `wget` on target to download
   - Requires network connectivity

4. **base64** (last resort)
   - Encodes binary to base64
   - Transfers via telnet
   - Limited by telnet buffer size (~100KB)

## Default Credentials

- **Root**: `root` / `hellotuya`
- **User**: `user` / `user123`

## Target Device

Binaries are transferred to `/tmp` on the target device and made executable automatically.

## Troubleshooting

### Build Issues

- **Docker image not found**: The script will attempt to build it automatically
- **Build fails**: Check that the Docker image built successfully
- **Binary not found**: Verify the build completed and check `hello-world/bin/` directory

### Transfer Issues

- **Connection timeout**: Verify target IP and telnet port (default: 23)
- **Authentication failed**: Check username and password
- **Transfer method not available**: The script will try multiple methods automatically
- **zmodem fails**: Install `lrzsz` package: `apt-get install lrzsz` or `yum install lrzsz`

### Execution Issues

- **Permission denied**: Binaries are automatically made executable, but verify with `chmod +x`
- **Binary not found**: Check that transfer completed successfully
- **Wrong architecture**: Verify binaries are ARM architecture: `file hello-world/bin/*`

## Verification

After building, verify the binaries are correct architecture:

```bash
file hello-world/bin/*
```

You should see output like:
```
hello-world/bin/hello: ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux-armhf.so.3, ...
```

## Examples

### Complete Workflow

```bash
# 1. Build all projects
cd /projects/Bytech-BY-CM-WF-101-WT
./hello-world/build.sh

# 2. Transfer and run
./hello-world/transfer-and-run.sh 10.0.0.227 root hellotuya
```

### Manual Transfer (if script fails)

If the automated script fails, you can manually transfer using available methods:

**Using zmodem:**
```bash
telnet 10.0.0.227
# Login, then:
cd /tmp
rz
# In another terminal:
sz hello-world/bin/hello
```

**Using SCP:**
```bash
scp hello-world/bin/hello root@10.0.0.227:/tmp/
ssh root@10.0.0.227 "chmod +x /tmp/hello && /tmp/hello"
```

## Notes

- All binaries are statically or dynamically linked for ARMv6 architecture
- The target device runs BusyBox-based Linux
- Binaries are placed in `/tmp` which is typically writable
- The scripts handle authentication automatically using expect

