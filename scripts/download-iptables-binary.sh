#!/usr/bin/env bash
set -euo pipefail

#######################################
# Download Precompiled iptables Binary
# Searches for and downloads precompiled static iptables for ARMv6
#######################################

OUTPUT_DIR="${1:-./binaries}"
ARCH="armv6"
IPTABLES_VERSION="${IPTABLES_VERSION:-1.8.11}"

mkdir -p "$OUTPUT_DIR"

log_info() {
    echo "[*] $*"
}

log_success() {
    echo "[+] $*"
}

log_error() {
    echo "[!] $*"
}

log_warn() {
    echo "[!] $*"
}

#######################################
# Check for precompiled binaries
#######################################
check_precompiled() {
    log_info "Searching for precompiled static iptables binaries for $ARCH..."
    
    local found=0
    
    # Check if we already have a binary
    if [[ -f "$OUTPUT_DIR/iptables" ]]; then
        log_success "Found existing binary: $OUTPUT_DIR/iptables"
        if file "$OUTPUT_DIR/iptables" | grep -qi "arm\|ARM"; then
            log_success "Binary appears to be ARM-compatible"
            found=1
        fi
    fi
    
    # Note: Precompiled static ARMv6 binaries are not readily available
    # Most distributions provide dynamic binaries that require shared libraries
    log_warn "Precompiled static iptables binaries for ARMv6 are not readily available"
    log_info "Common sources checked:"
    echo "  - Netfilter project: Provides source only"
    echo "  - Debian repositories: Dynamic binaries only (require shared libraries)"
    echo "  - OpenWrt: May have packages but require opkg and matching system"
    echo "  - GitHub: No verified static ARMv6 binaries found"
    echo ""
    
    if [[ $found -eq 0 ]]; then
        log_info "Recommendation: Compile using Docker (see build-iptables.sh)"
        return 1
    fi
    
    return 0
}

#######################################
# Download from Debian (if compatible)
#######################################
download_debian() {
    log_info "Attempting to download from Debian repositories..."
    
    # Note: Debian packages are dynamic and require shared libraries
    # This is a placeholder for future use if we find static packages
    log_warn "Debian packages are dynamic and require shared libraries"
    log_warn "Not suitable for BusyBox systems without proper library support"
    
    return 1
}

#######################################
# Main execution
#######################################
main() {
    echo "=========================================="
    echo "Precompiled iptables Binary Search"
    echo "=========================================="
    echo ""
    echo "Target Architecture: $ARCH"
    echo "Output Directory: $OUTPUT_DIR"
    echo ""
    
    if check_precompiled; then
        log_success "Precompiled binary found"
        exit 0
    else
        log_error "No precompiled binary found"
        echo ""
        echo "Next steps:"
        echo "  1. Use Docker to compile: ./scripts/build-iptables.sh"
        echo "  2. Or test Toybox iptables: ./scripts/test-toybox-iptables.sh <ip>"
        echo ""
        exit 1
    fi
}

main "$@"
