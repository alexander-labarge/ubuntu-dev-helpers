#!/usr/bin/env bash
# vbox-defaults.sh - Global defaults for VBox Factory
# Source this file to get sensible defaults based on host system
# All values can be overridden via environment variables or CLI arguments

set -euo pipefail

# ==============================================================================
# Helper Functions for Computing Defaults
# ==============================================================================

# Round down to nearest multiple of a base (e.g., 16, 32, 48, 64...)
_round_down_to_multiple() {
    local value="$1"
    local base="${2:-16}"
    echo $(( (value / base) * base ))
}

# Get total system RAM in MB
_get_total_ram_mb() {
    local ram_kb
    ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    echo $(( ram_kb / 1024 ))
}

# Get number of CPU cores
_get_cpu_count() {
    nproc
}

# Compute default RAM: total_ram / 4, rounded down to nearest 16MB multiple
_compute_default_ram() {
    local total_ram
    total_ram=$(_get_total_ram_mb)
    local quarter=$(( total_ram / 4 ))
    _round_down_to_multiple "$quarter" 16
}

# Compute default CPUs: nproc / 4, minimum 1
_compute_default_cpus() {
    local total_cpus
    total_cpus=$(_get_cpu_count)
    local quarter=$(( total_cpus / 4 ))
    [ "$quarter" -lt 1 ] && quarter=1
    echo "$quarter"
}

# ==============================================================================
# Directory Paths
# ==============================================================================
export VBOX_BASE="${VBOX_BASE:-$HOME/vms}"
export VBOX_DISKS="${VBOX_DISKS:-$VBOX_BASE/disks}"
export VBOX_ISOS="${VBOX_ISOS:-$VBOX_BASE/isos}"

# ==============================================================================
# VM System Defaults
# ==============================================================================
# RAM: 1/4 of host RAM, rounded to nearest 16MB
export VBOX_DEFAULT_RAM="${VBOX_DEFAULT_RAM:-$(_compute_default_ram)}"

# CPUs: 1/4 of host CPUs, minimum 1
export VBOX_DEFAULT_CPUS="${VBOX_DEFAULT_CPUS:-$(_compute_default_cpus)}"

# Disk size in MB (500GB default)
export VBOX_DEFAULT_DISK="${VBOX_DEFAULT_DISK:-512000}"

# VRAM for server VMs (16MB is sufficient for headless)
export VBOX_DEFAULT_VRAM_SERVER="${VBOX_DEFAULT_VRAM_SERVER:-16}"

# VRAM for desktop VMs (128MB for GUI)
export VBOX_DEFAULT_VRAM_DESKTOP="${VBOX_DEFAULT_VRAM_DESKTOP:-128}"

# ==============================================================================
# VM Type Defaults
# ==============================================================================
export VBOX_DEFAULT_TYPE="${VBOX_DEFAULT_TYPE:-desktop}"
export VBOX_DEFAULT_OSTYPE="${VBOX_DEFAULT_OSTYPE:-Ubuntu_64}"

# ==============================================================================
# Network Defaults
# ==============================================================================
# Network mode: bridged (default) or nat
export VBOX_DEFAULT_NETWORK="${VBOX_DEFAULT_NETWORK:-bridged}"

# Gateway for static IP configuration
export VBOX_DEFAULT_GATEWAY="${VBOX_DEFAULT_GATEWAY:-192.168.50.1}"

# DNS server
export VBOX_DEFAULT_DNS="${VBOX_DEFAULT_DNS:-8.8.8.8}"

# SSH port for NAT mode
export VBOX_DEFAULT_SSH_PORT="${VBOX_DEFAULT_SSH_PORT:-2222}"

# ==============================================================================
# Security & Advanced Features
# ==============================================================================
# Enable Secure Boot for VMs
export VBOX_DEFAULT_SECUREBOOT="${VBOX_DEFAULT_SECUREBOOT:-on}"

# Enable EFI (required for Secure Boot)
export VBOX_DEFAULT_EFI="${VBOX_DEFAULT_EFI:-on}"

# Enable nested virtualization / CPU passthrough
export VBOX_DEFAULT_NESTED_HW_VIRT="${VBOX_DEFAULT_NESTED_HW_VIRT:-on}"

# Enable PAE/NX
export VBOX_DEFAULT_PAE="${VBOX_DEFAULT_PAE:-on}"

# Enable hardware virtualization (VT-x/AMD-V)
export VBOX_DEFAULT_HW_VIRT="${VBOX_DEFAULT_HW_VIRT:-on}"

# ==============================================================================
# Graphics & Display
# ==============================================================================
export VBOX_DEFAULT_GRAPHICS_CONTROLLER="${VBOX_DEFAULT_GRAPHICS_CONTROLLER:-vmsvga}"

# ==============================================================================
# Storage
# ==============================================================================
export VBOX_DEFAULT_DISK_FORMAT="${VBOX_DEFAULT_DISK_FORMAT:-VDI}"
export VBOX_DEFAULT_DISK_VARIANT="${VBOX_DEFAULT_DISK_VARIANT:-Standard}"
export VBOX_DEFAULT_STORAGE_CONTROLLER="${VBOX_DEFAULT_STORAGE_CONTROLLER:-SATA}"

# ==============================================================================
# Boot Order
# ==============================================================================
export VBOX_DEFAULT_BOOT1="${VBOX_DEFAULT_BOOT1:-dvd}"
export VBOX_DEFAULT_BOOT2="${VBOX_DEFAULT_BOOT2:-disk}"
export VBOX_DEFAULT_BOOT3="${VBOX_DEFAULT_BOOT3:-none}"
export VBOX_DEFAULT_BOOT4="${VBOX_DEFAULT_BOOT4:-none}"

# ==============================================================================
# Logging
# ==============================================================================
_log_defaults() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "VBox Factory Defaults (computed from host system)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Host RAM:        $(_get_total_ram_mb) MB"
    echo "  Host CPUs:       $(_get_cpu_count)"
    echo ""
    echo "  VM RAM:          ${VBOX_DEFAULT_RAM} MB (host/4, rounded to 16MB)"
    echo "  VM CPUs:         ${VBOX_DEFAULT_CPUS} (host/4, min 1)"
    echo "  VM Disk:         ${VBOX_DEFAULT_DISK} MB ($(( VBOX_DEFAULT_DISK / 1024 )) GB)"
    echo "  Server VRAM:     ${VBOX_DEFAULT_VRAM_SERVER} MB"
    echo "  Desktop VRAM:    ${VBOX_DEFAULT_VRAM_DESKTOP} MB"
    echo ""
    echo "  Network:         ${VBOX_DEFAULT_NETWORK}"
    echo "  Gateway:         ${VBOX_DEFAULT_GATEWAY}"
    echo "  DNS:             ${VBOX_DEFAULT_DNS}"
    echo ""
    echo "  Secure Boot:     ${VBOX_DEFAULT_SECUREBOOT}"
    echo "  EFI:             ${VBOX_DEFAULT_EFI}"
    echo "  Nested HW Virt:  ${VBOX_DEFAULT_NESTED_HW_VIRT}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# If run directly (not sourced), show the defaults
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _log_defaults
fi
