.PHONY: help prefetch enum probe cameradar serve clean

# Default target
help:
	@echo "IoT Penetration Testing Suite - Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  make prefetch              - Prefetch Docker images for enumeration"
	@echo "  make enum TARGET_IP=IP     - Run external enumeration (requires TARGET_IP)"
	@echo "  make probe TARGET_IP=IP    - Run internal device probing (requires TARGET_IP)"
	@echo "  make cameradar TARGET_IP=IP - Run cameradar RTSP penetration test (requires TARGET_IP)"
	@echo "  make serve                 - Serve latest generated directory with Python HTTP server"
	@echo "  make clean                 - Clean generated directories"
	@echo ""
	@echo "Examples:"
	@echo "  make prefetch"
	@echo "  make enum TARGET_IP=10.0.0.227"
	@echo "  make probe TARGET_IP=10.0.0.227 USERNAME=root PASSWORD=hellotuya"
	@echo "  make cameradar TARGET_IP=10.0.0.227"
	@echo "  make serve"

# Configuration
TARGET_IP ?=
USERNAME ?= root
PASSWORD ?= hellotuya
INTERFACE ?= eth0
CONFIG_FILE ?= scripts/iot-config.yaml
PORT ?= 8000
PORTS ?= 554,5554,8554
TIMEOUT ?= 2000
ATTACK_INTERVAL ?= 0
OUTPUT_DIR ?=

# Script paths
SCRIPT_DIR := scripts
PREFETCH_SCRIPT := $(SCRIPT_DIR)/iot-mega-enum-prefetch.sh
ENUM_SCRIPT := $(SCRIPT_DIR)/iot-mega-enum.sh
PROBE_SCRIPT := $(SCRIPT_DIR)/iot-internal-probe.sh
CAMERADAR_SCRIPT := $(SCRIPT_DIR)/cameradar-rtsp-scan.sh

#######################################
# Prefetch Docker Images
#######################################
prefetch:
	@echo "[*] Prefetching Docker images..."
	@bash $(PREFETCH_SCRIPT)
	@echo "[+] Prefetch complete"

#######################################
# External Enumeration
#######################################
enum:
	@if [ -z "$(TARGET_IP)" ]; then \
		echo "[!] Error: TARGET_IP is required"; \
		echo "Usage: make enum TARGET_IP=<ip-address>"; \
		exit 1; \
	fi
	@echo "[*] Starting external enumeration on $(TARGET_IP)..."
	@bash $(ENUM_SCRIPT) $(TARGET_IP) $(INTERFACE) $(CONFIG_FILE)
	@echo "[+] External enumeration complete"

#######################################
# Internal Device Probing
#######################################
probe:
	@if [ -z "$(TARGET_IP)" ]; then \
		echo "[!] Error: TARGET_IP is required"; \
		echo "Usage: make probe TARGET_IP=<ip-address> [USERNAME=<user>] [PASSWORD=<pass>]"; \
		exit 1; \
	fi
	@echo "[*] Starting internal device probing on $(TARGET_IP)..."
	@echo "[*] Username: $(USERNAME)"
	@bash $(PROBE_SCRIPT) $(TARGET_IP) $(USERNAME) $(PASSWORD)
	@echo "[+] Internal probing complete"

#######################################
# Cameradar RTSP Penetration Test
#######################################
cameradar:
	@if [ -z "$(TARGET_IP)" ]; then \
		echo "[!] Error: TARGET_IP is required"; \
		echo "Usage: make cameradar TARGET_IP=<ip-address> [PORTS=<ports>] [OUTPUT_DIR=<dir>]"; \
		exit 1; \
	fi
	@echo "[*] Starting cameradar RTSP penetration test on $(TARGET_IP)..."
	@bash $(CAMERADAR_SCRIPT) $(TARGET_IP) $(PORTS) $(OUTPUT_DIR) $(TIMEOUT) $(ATTACK_INTERVAL)
	@echo "[+] Cameradar scan complete"

#######################################
# Serve Latest Generated Directory
#######################################
serve:
	@echo "[*] Finding latest generated directory..."
	@LATEST_DIR=$$(ls -td iot_enum_* iot_internal_* 2>/dev/null | head -1); \
	if [ -z "$$LATEST_DIR" ]; then \
		echo "[!] Error: No generated directories found"; \
		echo "[*] Run 'make enum' or 'make probe' first"; \
		exit 1; \
	fi; \
	echo "[+] Serving: $$LATEST_DIR"; \
	echo "[*] Starting Python HTTP server on port $(PORT)..."; \
	echo "[*] Open http://localhost:$(PORT) in your browser"; \
	echo "[*] If index.html exists, it will be served automatically"; \
	echo "[*] Press Ctrl+C to stop"; \
	echo ""; \
	cd $$LATEST_DIR && python3 -m http.server $(PORT)

#######################################
# Clean Generated Directories
#######################################
clean:
	@echo "[*] Cleaning generated directories..."
	@rm -rf iot_enum_* iot_internal_*
	@echo "[+] Clean complete"

#######################################
# All-in-one: Prefetch, Enum, Probe
#######################################
all: prefetch enum probe
	@echo "[+] All steps complete"

