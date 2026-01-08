.PHONY: help prefetch enum probe cameradar serve clean mitm-venv mitmweb mitm-clean

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
	@echo "  make mitm-venv             - Create MITMproxy virtual environment"
	@echo "  make mitmweb               - Launch MITMproxy with all proxy modes"
	@echo "  make mitm-clean            - Remove iptables rules and stop MITMproxy"
	@echo ""
	@echo "Examples:"
	@echo "  make prefetch"
	@echo "  make enum TARGET_IP=10.0.0.227"
	@echo "  make probe TARGET_IP=10.0.0.227 USERNAME=root PASSWORD=hellotuya"
	@echo "  make cameradar TARGET_IP=10.0.0.227"
	@echo "  make serve"
	@echo "  make mitm-venv"
	@echo "  make mitmweb"
	@echo "  make mitm-clean"

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

# MITMproxy Configuration
MITM_VENV_DIR ?= .venv-mitm
MITM_LOG_DIR ?= mitm_logs
MITM_WIREGUARD_PORT ?= 51820
MITM_HTTP_PORT ?= 58080
MITM_SOCKS5_PORT ?= 51080
MITM_WEB_PORT ?= 58081
MITM_INTERFACE ?=
MITM_MODE ?= transparent

# Script paths
SCRIPT_DIR := scripts
PREFETCH_SCRIPT := $(SCRIPT_DIR)/iot-mega-enum-prefetch.sh
ENUM_SCRIPT := $(SCRIPT_DIR)/iot-mega-enum.sh
PROBE_SCRIPT := $(SCRIPT_DIR)/iot-internal-probe.sh
CAMERADAR_SCRIPT := $(SCRIPT_DIR)/cameradar-rtsp-scan.sh
MITM_LOCAL_IPTABLES_SCRIPT := $(SCRIPT_DIR)/setup-mitm-iptables-local.sh
MITM_REMOTE_IPTABLES_SCRIPT := $(SCRIPT_DIR)/setup-mitm-iptables-remote.sh
MITM_CLEANUP_SCRIPT := $(SCRIPT_DIR)/cleanup-mitm-iptables.sh

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
# MITMproxy Virtual Environment
#######################################
mitm-venv:
	@echo "[*] Creating MITMproxy virtual environment..."
	@if command -v uv >/dev/null 2>&1; then \
		echo "[*] Using UV package manager"; \
		uv venv $(MITM_VENV_DIR); \
		$(MITM_VENV_DIR)/bin/pip install --upgrade pip; \
		$(MITM_VENV_DIR)/bin/pip install mitmproxy; \
	else \
		echo "[!] Error: UV package manager not found"; \
		echo "[*] Install UV: curl -LsSf https://astral.sh/uv/install.sh | sh"; \
		exit 1; \
	fi
	@echo "[+] MITMproxy virtual environment created"
	@echo "[*] Virtual environment location: $(MITM_VENV_DIR)"
	@$(MITM_VENV_DIR)/bin/mitmweb --version || true

#######################################
# Launch MITMproxy
#######################################
mitmweb: mitm-venv
	@if [ ! -d "$(MITM_VENV_DIR)" ]; then \
		echo "[!] Error: Virtual environment not found"; \
		echo "[*] Run 'make mitm-venv' first"; \
		exit 1; \
	fi
	@echo "[*] Creating log directory: $(MITM_LOG_DIR)"
	@mkdir -p $(MITM_LOG_DIR)
	@echo "[*] Launching MITMproxy with all proxy modes..."
	@echo "[*] WireGuard proxy: 0.0.0.0:$(MITM_WIREGUARD_PORT)"
	@echo "[*] HTTP proxy: 0.0.0.0:$(MITM_HTTP_PORT)"
	@echo "[*] SOCKS5 proxy: 0.0.0.0:$(MITM_SOCKS5_PORT)"
	@echo "[*] Web interface: http://0.0.0.0:$(MITM_WEB_PORT)"
	@echo "[*] Log directory: $(MITM_LOG_DIR)"
	@echo "[*] Press Ctrl+C to stop"
	@echo ""
	@trap 'echo "[*] Stopping MITMproxy..."; exit 0' INT TERM; \
	while true; do \
		TS=$$(date +%Y%m%d_%H%M%S); \
		LOG_FILE="$(MITM_LOG_DIR)/mitm_$$TS.log"; \
		echo "[*] Starting mitmweb, logging to $$LOG_FILE"; \
		timeout --signal=SIGTERM --kill-after=30s 3600 $(MITM_VENV_DIR)/bin/mitmweb \
			--mode wireguard@0.0.0.0:$(MITM_WIREGUARD_PORT) \
			--mode regular@0.0.0.0:$(MITM_HTTP_PORT) \
			--mode socks5@0.0.0.0:$(MITM_SOCKS5_PORT) \
			--web-port $(MITM_WEB_PORT) \
			--web-host 0.0.0.0 \
			--save-stream-file "$$LOG_FILE" \
			--set block_global=false || break; \
	done

#######################################
# Clean MITMproxy iptables Rules
#######################################
mitm-clean:
	@echo "[*] Cleaning MITMproxy iptables rules..."
	@if [ -f "$(MITM_CLEANUP_SCRIPT)" ]; then \
		bash $(MITM_CLEANUP_SCRIPT); \
	else \
		echo "[!] Warning: Cleanup script not found: $(MITM_CLEANUP_SCRIPT)"; \
		echo "[*] Attempting manual cleanup..."; \
		iptables -t nat -F PREROUTING 2>/dev/null || true; \
		iptables -t nat -F OUTPUT 2>/dev/null || true; \
		pkill -f mitmweb 2>/dev/null || true; \
	fi
	@echo "[+] MITMproxy cleanup complete"

#######################################
# All-in-one: Prefetch, Enum, Probe
#######################################
all: prefetch enum probe
	@echo "[+] All steps complete"

