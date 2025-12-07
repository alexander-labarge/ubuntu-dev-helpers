#!/bin/bash

################################################################################
# KVM Disable Script for VirtualBox
# 
# Author: Alexander La Barge
# Date: 19 Nov 2025
# Contact: alex@labarge.dev
# Program Name: virtualbox-sb-manager
# Version: 0.1.0-beta
#
# VirtualBox and KVM cannot run simultaneously as they both require exclusive
# access to hardware virtualization (VT-x/AMD-V). This script helps manage
# KVM kernel modules to allow VirtualBox to operate.
#
# Usage: sudo ./disable-kvm.sh [--disable|--enable|--status|--permanent]
################################################################################

set -uo pipefail

# Configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly BLACKLIST_FILE="/etc/modprobe.d/blacklist-kvm.conf"
readonly LOG_FILE="/var/log/kvm-management.log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

################################################################################
# Logging Functions
################################################################################

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    printf '[%s] [%s] %s\n' "${timestamp}" "${level}" "${message}" >> "${LOG_FILE}" 2>/dev/null || true
}

log_info() {
    log "INFO" "$@"
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
    log "SUCCESS" "$@"
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_warning() {
    log "WARNING" "$@"
    echo -e "${YELLOW}[WARNING]${NC} $*" >&2
}

log_error() {
    log "ERROR" "$@"
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

error_exit() {
    log_error "$1"
    exit "${2:-1}"
}

################################################################################
# Check Functions
################################################################################

check_root() {
    if [ "$EUID" -ne 0 ]; then
        error_exit "This script must be run as root. Please use sudo." 1
    fi
}

check_virtualization_support() {
    log_info "Checking hardware virtualization support..."
    
    if grep -E '(vmx|svm)' /proc/cpuinfo > /dev/null; then
        if grep -q 'vmx' /proc/cpuinfo; then
            log_success "Intel VT-x detected"
        else
            log_success "AMD-V detected"
        fi
        return 0
    else
        log_error "No hardware virtualization support detected"
        return 1
    fi
}

check_kvm_loaded() {
    set +o pipefail
    if lsmod | grep -qw 'kvm'; then
        set -o pipefail
        return 0
    else
        set -o pipefail
        return 1
    fi
}

################################################################################
# KVM Management Functions
################################################################################

get_kvm_status() {
    log_info "Checking KVM status..."
    
    local kvm_loaded=false
    local kvm_intel_loaded=false
    local kvm_amd_loaded=false
    local blacklisted=false
    
    # Temporarily disable pipefail for grep commands (grep returns 1 when no match)
    set +o pipefail
    
    # Check if modules are loaded
    if lsmod | grep -qw 'kvm_intel'; then
        kvm_intel_loaded=true
        kvm_loaded=true
    fi
    
    if lsmod | grep -qw 'kvm_amd'; then
        kvm_amd_loaded=true
        kvm_loaded=true
    fi
    
    if lsmod | grep -qw 'kvm'; then
        kvm_loaded=true
    fi
    
    # Re-enable pipefail
    set -o pipefail
    
    # Check if blacklisted
    if [ -f "${BLACKLIST_FILE}" ]; then
        blacklisted=true
    fi
    
    echo ""
    echo "=========================================="
    echo "  KVM Status"
    echo "=========================================="
    echo ""
    
    if [ "$kvm_loaded" = true ]; then
        echo -e "${YELLOW}KVM Status:${NC}       ENABLED (loaded)"
    else
        echo -e "${GREEN}KVM Status:${NC}       DISABLED (not loaded)"
    fi
    
    if [ "$kvm_intel_loaded" = true ]; then
        echo -e "  kvm_intel:      ${YELLOW}LOADED${NC}"
    else
        echo "  kvm_intel:      not loaded"
    fi
    
    if [ "$kvm_amd_loaded" = true ]; then
        echo -e "  kvm_amd:        ${YELLOW}LOADED${NC}"
    else
        echo "  kvm_amd:        not loaded"
    fi
    
    echo ""
    
    if [ "$blacklisted" = true ]; then
        echo -e "${GREEN}Blacklist:${NC}        ENABLED (permanent)"
        echo "  File:           ${BLACKLIST_FILE}"
    else
        echo "Blacklist:        disabled"
    fi
    
    echo ""
    
    # Check what's using virtualization
    if [ "$kvm_loaded" = true ]; then
        log_warning "KVM is loaded - VirtualBox will NOT work!"
        echo -e "${YELLOW}WARNING:${NC} KVM is loaded. VirtualBox requires exclusive access."
        echo "           Run: sudo $0 --disable"
        echo ""
    else
        log_success "KVM is not loaded - VirtualBox can operate"
        echo -e "${GREEN}OK:${NC} KVM is not loaded. VirtualBox can operate normally."
        echo ""
    fi
}

disable_kvm_temporary() {
    log_info "Disabling KVM modules (temporary - until reboot)..."
    
    local unloaded_any=false
    
    # Temporarily disable pipefail for grep commands
    set +o pipefail
    
    # Try to unload KVM modules
    if lsmod | grep -qw 'kvm_intel'; then
        set -o pipefail
        log_info "Unloading kvm_intel module..."
        if modprobe -r kvm_intel 2>/dev/null; then
            log_success "kvm_intel unloaded"
            unloaded_any=true
        else
            log_error "Failed to unload kvm_intel (may be in use)"
            echo ""
            log_info "Checking what's using KVM..."
            lsof 2>/dev/null | grep kvm || true
            return 1
        fi
        set +o pipefail
    fi
    
    if lsmod | grep -qw 'kvm_amd'; then
        set -o pipefail
        log_info "Unloading kvm_amd module..."
        if modprobe -r kvm_amd 2>/dev/null; then
            log_success "kvm_amd unloaded"
            unloaded_any=true
        else
            log_error "Failed to unload kvm_amd (may be in use)"
            return 1
        fi
        set +o pipefail
    fi
    
    if lsmod | grep -qw 'kvm'; then
        set -o pipefail
        log_info "Unloading kvm module..."
        if modprobe -r kvm 2>/dev/null; then
            log_success "kvm unloaded"
            unloaded_any=true
        else
            log_error "Failed to unload kvm (may be in use)"
            return 1
        fi
        set +o pipefail
    fi
    
    # Re-enable pipefail
    set -o pipefail
    
    if [ "$unloaded_any" = true ]; then
        echo ""
        log_success "KVM disabled successfully (until next reboot)"
        log_info "VirtualBox can now be used"
        echo ""
        log_warning "NOTE: This is temporary. KVM will reload on next boot."
        log_info "      For permanent disable, use: sudo $0 --permanent"
        return 0
    else
        log_info "KVM modules were not loaded"
        return 0
    fi
}

disable_kvm_permanent() {
    log_info "Disabling KVM permanently (survives reboot)..."
    
    # First disable temporarily
    disable_kvm_temporary
    
    # Create blacklist file
    log_info "Creating blacklist configuration..."
    
    cat > "${BLACKLIST_FILE}" << 'EOF'
# Blacklist KVM modules to allow VirtualBox to operate
# VirtualBox and KVM cannot run simultaneously
# Generated by disable-kvm.sh

blacklist kvm
blacklist kvm_intel
blacklist kvm_amd
EOF
    
    if [ $? -eq 0 ]; then
        log_success "Blacklist file created: ${BLACKLIST_FILE}"
        
        # Update initramfs
        log_info "Updating initramfs..."
        if update-initramfs -u 2>&1 | tee -a "${LOG_FILE}"; then
            log_success "initramfs updated"
        else
            log_warning "Failed to update initramfs (may still work)"
        fi
        
        echo ""
        log_success "KVM disabled permanently"
        log_info "Changes will take full effect after reboot"
        echo ""
        log_info "To verify, run: sudo $0 --status"
        
        return 0
    else
        error_exit "Failed to create blacklist file" 1
    fi
}

enable_kvm() {
    log_info "Re-enabling KVM..."
    
    local changed=false
    
    # Remove blacklist file if it exists
    if [ -f "${BLACKLIST_FILE}" ]; then
        log_info "Removing blacklist file..."
        rm -f "${BLACKLIST_FILE}"
        log_success "Blacklist file removed"
        changed=true
        
        # Update initramfs
        log_info "Updating initramfs..."
        if update-initramfs -u 2>&1 | tee -a "${LOG_FILE}"; then
            log_success "initramfs updated"
        else
            log_warning "Failed to update initramfs"
        fi
    fi
    
    # Try to load KVM modules
    log_info "Loading KVM modules..."
    
    if grep -q 'vmx' /proc/cpuinfo; then
        # Intel
        if modprobe kvm_intel 2>/dev/null; then
            log_success "kvm_intel loaded"
            changed=true
        else
            log_warning "Could not load kvm_intel (may need reboot)"
        fi
    elif grep -q 'svm' /proc/cpuinfo; then
        # AMD
        if modprobe kvm_amd 2>/dev/null; then
            log_success "kvm_amd loaded"
            changed=true
        else
            log_warning "Could not load kvm_amd (may need reboot)"
        fi
    fi
    
    if [ "$changed" = true ]; then
        echo ""
        log_success "KVM re-enabled"
        log_warning "VirtualBox will NO LONGER work until KVM is disabled again"
        echo ""
        log_info "You may need to reboot for all changes to take effect"
        return 0
    else
        log_info "KVM was not disabled"
        return 0
    fi
}

################################################################################
# Main
################################################################################

show_help() {
    cat << EOF
Usage: sudo $0 [OPTION]

KVM Management Script for VirtualBox Compatibility

VirtualBox and KVM cannot run simultaneously. This script helps manage
KVM kernel modules to allow VirtualBox to operate.

Options:
  --disable    Disable KVM temporarily (until reboot)
  --permanent  Disable KVM permanently (blacklist)
  --enable     Re-enable KVM (remove blacklist)
  --status     Show current KVM status
  --help       Show this help message

Examples:
  # Quick disable (temporary)
  sudo $0 --disable

  # Permanent disable (survives reboot)
  sudo $0 --permanent

  # Check status
  sudo $0 --status

  # Re-enable KVM (for QEMU/libvirt)
  sudo $0 --enable

EOF
}

main() {
    # Initialize log file
    touch "${LOG_FILE}" 2>/dev/null || true
    
    log_info "========== KVM Management Script Started =========="
    
    # Check prerequisites
    check_root
    check_virtualization_support
    
    # Parse command line arguments
    case "${1:-}" in
        --disable)
            disable_kvm_temporary
            ;;
        --permanent)
            disable_kvm_permanent
            ;;
        --enable)
            enable_kvm
            ;;
        --status)
            get_kvm_status
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        "")
            get_kvm_status
            echo ""
            read -p "Do you want to disable KVM now? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo ""
                read -p "Permanent disable (survives reboot)? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    disable_kvm_permanent
                else
                    disable_kvm_temporary
                fi
            fi
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
    
    log_info "========== Script Completed =========="
}

# Run main function
main "$@"
