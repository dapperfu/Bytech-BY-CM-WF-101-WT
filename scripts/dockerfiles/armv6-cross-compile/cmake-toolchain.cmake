# CMake toolchain file for ARMv6 cross-compilation
# Target: ARMv6 FH8616 chipset (ARMv6-compatible processor rev 7)
# Hardware: FH8616
# OS: Linux (BusyBox-based)

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)

# Cross-compiler settings
set(CMAKE_C_COMPILER arm-linux-gnueabihf-gcc)
set(CMAKE_CXX_COMPILER arm-linux-gnueabihf-g++)

# Compiler flags for ARMv6
# Note: ARMv6 may not have FPU, so use soft-float even with gnueabihf toolchain
set(CMAKE_C_FLAGS_INIT "-march=armv6 -mtune=arm1176jzf-s -mfloat-abi=softfp")
set(CMAKE_CXX_FLAGS_INIT "-march=armv6 -mtune=arm1176jzf-s -mfloat-abi=softfp")

# Default C/C++ standards (only set if not already set by project)
if(NOT DEFINED CMAKE_C_STANDARD)
    set(CMAKE_C_STANDARD 90)  # C90 (ANSI C) - CMake doesn't recognize C89
    set(CMAKE_C_STANDARD_REQUIRED ON)
endif()
if(NOT DEFINED CMAKE_CXX_STANDARD)
    set(CMAKE_CXX_STANDARD 11)
    set(CMAKE_CXX_STANDARD_REQUIRED ON)
endif()

# Search paths
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Binary utilities
set(CMAKE_AR arm-linux-gnueabihf-ar)
set(CMAKE_RANLIB arm-linux-gnueabihf-ranlib)
set(CMAKE_STRIP arm-linux-gnueabihf-strip)

# Linker settings - support both static and dynamic linking
set(CMAKE_EXE_LINKER_FLAGS_INIT "")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "")

# Set pkg-config to use cross-compilation prefix
set(PKG_CONFIG_EXECUTABLE arm-linux-gnueabihf-pkg-config)

# Disable compiler checks that might fail in cross-compilation
set(CMAKE_C_COMPILER_WORKS 1)
set(CMAKE_CXX_COMPILER_WORKS 1)

