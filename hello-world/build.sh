#!/usr/bin/env bash
set -euo pipefail

#######################################
# Hello World Build Script
# Cross-compiles C, C++, and Rust hello world programs for ARMv6
#######################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_IMAGE="iot-pentest/armv6-cross-compile:latest"
BUILD_PROJECT="${1:-all}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[*]${NC} $*"
}

log_error() {
    echo -e "${RED}[!]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $*"
}

# Check if Docker image exists
if ! docker image inspect "$DOCKER_IMAGE" &>/dev/null; then
    log_error "Docker image $DOCKER_IMAGE not found"
    log_info "Building Docker image..."
    docker build -t "$DOCKER_IMAGE" "$SCRIPT_DIR/../scripts/dockerfiles/armv6-cross-compile/" || {
        log_error "Failed to build Docker image"
        exit 1
    }
fi

# Create bin directory
mkdir -p "$SCRIPT_DIR/bin"

# Build function for C
build_c() {
    log_info "Building C hello world..."
    docker run --rm \
        -v "$SCRIPT_DIR:/workspace" \
        -v "$SCRIPT_DIR/bin:/output" \
        -w /workspace/c \
        "$DOCKER_IMAGE" \
        make clean all
    
    if [[ -f "$SCRIPT_DIR/bin/hello" ]]; then
        log_info "C build successful"
        file "$SCRIPT_DIR/bin/hello"
    else
        log_error "C build failed - binary not found"
        return 1
    fi
}

# Build function for C++
build_cpp() {
    log_info "Building C++ hello world..."
    docker run --rm \
        -v "$SCRIPT_DIR:/workspace" \
        -v "$SCRIPT_DIR/bin:/output" \
        -w /workspace/cpp \
        "$DOCKER_IMAGE" \
        sh -c "cmake -B build -DCMAKE_TOOLCHAIN_FILE=/opt/cmake-toolchain.cmake && cmake --build build"
    
    # CMake outputs to ../bin, but we need to check
    if [[ -f "$SCRIPT_DIR/cpp/build/hello" ]]; then
        cp "$SCRIPT_DIR/cpp/build/hello" "$SCRIPT_DIR/bin/hello_cpp"
        log_info "C++ build successful"
        file "$SCRIPT_DIR/bin/hello_cpp"
    elif [[ -f "$SCRIPT_DIR/bin/hello" ]]; then
        mv "$SCRIPT_DIR/bin/hello" "$SCRIPT_DIR/bin/hello_cpp"
        log_info "C++ build successful"
        file "$SCRIPT_DIR/bin/hello_cpp"
    else
        log_error "C++ build failed - binary not found"
        return 1
    fi
}

# Build function for Rust
build_rust() {
    log_info "Building Rust hello world..."
    docker run --rm \
        -v "$SCRIPT_DIR:/workspace" \
        -v "$SCRIPT_DIR/bin:/output" \
        -w /workspace/rust \
        "$DOCKER_IMAGE" \
        sh -c "cargo build --target arm-unknown-linux-gnueabihf --release"
    
    if [[ -f "$SCRIPT_DIR/rust/target/arm-unknown-linux-gnueabihf/release/hello" ]]; then
        cp "$SCRIPT_DIR/rust/target/arm-unknown-linux-gnueabihf/release/hello" "$SCRIPT_DIR/bin/hello_rust"
        log_info "Rust build successful"
        file "$SCRIPT_DIR/bin/hello_rust"
    else
        log_error "Rust build failed - binary not found"
        return 1
    fi
}

# Main build logic
case "$BUILD_PROJECT" in
    c)
        build_c
        ;;
    cpp)
        build_cpp
        ;;
    rust)
        build_rust
        ;;
    all)
        log_info "Building all projects..."
        build_c
        build_cpp
        build_rust
        log_info "All builds complete!"
        echo
        log_info "Built binaries:"
        ls -lh "$SCRIPT_DIR/bin/"
        ;;
    *)
        log_error "Unknown project: $BUILD_PROJECT"
        echo "Usage: $0 [c|cpp|rust|all]"
        exit 1
        ;;
esac

