FROM debian:stable-slim

LABEL maintainer="IoT Pentest Suite"
LABEL description="ARMv6 cross-compilation environment for FH8616 chipset (C, C++, Rust)"

# Build arguments
ARG RUST_VERSION=stable
ARG DEBIAN_FRONTEND=noninteractive

# Install base dependencies and C/C++ cross-compilation toolchain
RUN apt-get update && apt-get install -y --no-install-recommends \
    # C/C++ cross-compilation toolchain (hard-float for ARMv6)
    gcc-arm-linux-gnueabihf \
    g++-arm-linux-gnueabihf \
    binutils-arm-linux-gnueabihf \
    # Build systems
    cmake \
    make \
    # Development and debugging tools
    gdb-multiarch \
    strace \
    file \
    binutils \
    # Rust installation dependencies
    curl \
    ca-certificates \
    # Additional utilities
    git \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Install Rust toolchain
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    --default-toolchain ${RUST_VERSION} \
    && . "$HOME/.cargo/env" \
    && rustup target add arm-unknown-linux-gnueabihf

# Set up environment variables
ENV TARGET_ARCH=arm
ENV TARGET_TRIPLE=arm-linux-gnueabihf
ENV CC=arm-linux-gnueabihf-gcc
ENV CXX=arm-linux-gnueabihf-g++
ENV AR=arm-linux-gnueabihf-ar
ENV STRIP=arm-linux-gnueabihf-strip
ENV RANLIB=arm-linux-gnueabihf-ranlib
ENV RUST_TARGET=arm-unknown-linux-gnueabihf
ENV C_STANDARD=c89
ENV CXX_STANDARD=c++11
ENV OUTPUT_DIR=/output
ENV PATH="/root/.cargo/bin:${PATH}"

# Copy CMake toolchain file to standard location
COPY cmake-toolchain.cmake /opt/cmake-toolchain.cmake

# Create workspace and output directories
WORKDIR /workspace
RUN mkdir -p /output

# Default command (can be overridden)
CMD ["/bin/bash"]

