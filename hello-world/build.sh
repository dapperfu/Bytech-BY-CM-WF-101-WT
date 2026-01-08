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
BLUE='\033[0;34m'
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

log_success() {
    echo -e "${BLUE}[+]${NC} $*"
}

# Check if Docker image exists
log_info "Checking for Docker image: $DOCKER_IMAGE"
if ! docker image inspect "$DOCKER_IMAGE" &>/dev/null; then
    log_warn "Docker image $DOCKER_IMAGE not found"
    log_info "Building Docker image..."
    log_info "This will take several minutes on first build..."
    log_info "Docker build command: docker build -t $DOCKER_IMAGE $SCRIPT_DIR/../scripts/dockerfiles/armv6-cross-compile/"
    
    if docker build -t "$DOCKER_IMAGE" "$SCRIPT_DIR/../scripts/dockerfiles/armv6-cross-compile/" 2>&1 | tee /tmp/docker_build.log; then
        log_success "Docker image built successfully"
    else
        log_error "Failed to build Docker image"
        log_info "Last 30 lines of build output:"
        tail -30 /tmp/docker_build.log 2>/dev/null || echo "No log file found"
        exit 1
    fi
else
    log_success "Docker image found"
fi

# Create bin directory
log_info "Creating bin directory: $SCRIPT_DIR/bin"
mkdir -p "$SCRIPT_DIR/bin"
log_info "Starting build process for: $BUILD_PROJECT"
echo

# Build function for C
build_c() {
    log_info "Building C hello world..."
    log_info "Docker command: docker run --rm -v $SCRIPT_DIR:/workspace -v $SCRIPT_DIR/bin:/output -w /workspace/c $DOCKER_IMAGE make clean all"
    
    if docker run --rm \
        -v "$SCRIPT_DIR:/workspace" \
        -v "$SCRIPT_DIR/bin:/output" \
        -w /workspace/c \
        "$DOCKER_IMAGE" \
        make clean all 2>&1 | tee /tmp/build_c.log; then
        log_info "Docker command completed"
    else
        log_error "Docker command failed"
        log_info "Last 20 lines of output:"
        tail -20 /tmp/build_c.log 2>/dev/null || echo "No log file found"
        return 1
    fi
    
    log_info "Checking for binary at $SCRIPT_DIR/bin/hello"
    if [[ -f "$SCRIPT_DIR/bin/hello" ]]; then
        log_info "C build successful"
        file "$SCRIPT_DIR/bin/hello"
    else
        log_error "C build failed - binary not found"
        log_info "Contents of bin directory:"
        ls -la "$SCRIPT_DIR/bin/" 2>/dev/null || echo "bin directory does not exist"
        return 1
    fi
}

# Build function for C++
build_cpp() {
    log_info "Building C++ hello world..."
    log_info "Step 1: Running cmake configuration..."
    log_info "Docker command: docker run --rm -v $SCRIPT_DIR:/workspace -v $SCRIPT_DIR/bin:/output -w /workspace/cpp $DOCKER_IMAGE cmake -B build -DCMAKE_TOOLCHAIN_FILE=/opt/cmake-toolchain.cmake"
    
    if docker run --rm \
        -v "$SCRIPT_DIR:/workspace" \
        -v "$SCRIPT_DIR/bin:/output" \
        -w /workspace/cpp \
        "$DOCKER_IMAGE" \
        cmake -B build -DCMAKE_TOOLCHAIN_FILE=/opt/cmake-toolchain.cmake 2>&1 | tee /tmp/build_cpp_cmake.log; then
        log_info "CMake configuration completed"
    else
        log_error "CMake configuration failed"
        log_info "Last 20 lines of cmake output:"
        tail -20 /tmp/build_cpp_cmake.log 2>/dev/null || echo "No log file found"
        return 1
    fi
    
    log_info "Step 2: Building with cmake..."
    log_info "Docker command: docker run --rm -v $SCRIPT_DIR:/workspace -v $SCRIPT_DIR/bin:/output -w /workspace/cpp $DOCKER_IMAGE cmake --build build"
    
    if docker run --rm \
        -v "$SCRIPT_DIR:/workspace" \
        -v "$SCRIPT_DIR/bin:/output" \
        -w /workspace/cpp \
        "$DOCKER_IMAGE" \
        cmake --build build 2>&1 | tee /tmp/build_cpp_build.log; then
        log_info "CMake build completed"
    else
        log_error "CMake build failed"
        log_info "Last 20 lines of build output:"
        tail -20 /tmp/build_cpp_build.log 2>/dev/null || echo "No log file found"
        return 1
    fi
    
    log_info "Checking for binary..."
    # CMake outputs to ../bin, but we need to check
    if [[ -f "$SCRIPT_DIR/cpp/build/hello" ]]; then
        log_info "Found binary at $SCRIPT_DIR/cpp/build/hello"
        cp "$SCRIPT_DIR/cpp/build/hello" "$SCRIPT_DIR/bin/hello_cpp"
        log_info "C++ build successful"
        file "$SCRIPT_DIR/bin/hello_cpp"
    elif [[ -f "$SCRIPT_DIR/bin/hello" ]]; then
        log_info "Found binary at $SCRIPT_DIR/bin/hello, renaming to hello_cpp"
        mv "$SCRIPT_DIR/bin/hello" "$SCRIPT_DIR/bin/hello_cpp"
        log_info "C++ build successful"
        file "$SCRIPT_DIR/bin/hello_cpp"
    else
        log_error "C++ build failed - binary not found"
        log_info "Contents of cpp/build directory:"
        ls -la "$SCRIPT_DIR/cpp/build/" 2>/dev/null || echo "build directory does not exist"
        log_info "Contents of bin directory:"
        ls -la "$SCRIPT_DIR/bin/" 2>/dev/null || echo "bin directory does not exist"
        return 1
    fi
}

# Build function for Rust
build_rust() {
    log_info "Building Rust hello world..."
    log_info "Docker command: docker run --rm -v $SCRIPT_DIR:/workspace -v $SCRIPT_DIR/bin:/output -w /workspace/rust $DOCKER_IMAGE cargo build --target arm-unknown-linux-gnueabihf --release"
    log_info "This may take a while as Rust downloads dependencies on first build..."
    
    if docker run --rm \
        -v "$SCRIPT_DIR:/workspace" \
        -v "$SCRIPT_DIR/bin:/output" \
        -w /workspace/rust \
        -e RUSTFLAGS="-C target-feature=+crt-static -C link-arg=-static" \
        "$DOCKER_IMAGE" \
        sh -c "cargo build --target arm-unknown-linux-gnueabihf --release" 2>&1 | tee /tmp/build_rust.log; then
        log_info "Docker command completed"
    else
        log_error "Docker command failed"
        log_info "Last 30 lines of output:"
        tail -30 /tmp/build_rust.log 2>/dev/null || echo "No log file found"
        return 1
    fi
    
    log_info "Checking for binary at $SCRIPT_DIR/rust/target/arm-unknown-linux-gnueabihf/release/hello"
    if [[ -f "$SCRIPT_DIR/rust/target/arm-unknown-linux-gnueabihf/release/hello" ]]; then
        log_info "Found binary, copying to bin directory"
        cp "$SCRIPT_DIR/rust/target/arm-unknown-linux-gnueabihf/release/hello" "$SCRIPT_DIR/bin/hello_rust"
        log_info "Rust build successful"
        file "$SCRIPT_DIR/bin/hello_rust"
    else
        log_error "Rust build failed - binary not found"
        log_info "Contents of rust/target directory:"
        find "$SCRIPT_DIR/rust/target" -name "hello" -type f 2>/dev/null || echo "No hello binary found in target directory"
        log_info "Contents of rust/target/arm-unknown-linux-gnueabihf/release:"
        ls -la "$SCRIPT_DIR/rust/target/arm-unknown-linux-gnueabihf/release/" 2>/dev/null || echo "release directory does not exist"
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

