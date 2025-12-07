#!/bin/bash

################################################################################
# VirtualBox Module Signing Script for Ubuntu 24.04.3 LTS with Secure Boot
# 
# Author: Alexander La Barge
# Date: 19 Nov 2025
# Contact: alex@labarge.dev
# Program Name: virtualbox-sb-manager
# Version: 0.1.0-beta
#
# This script handles the signing of VirtualBox kernel modules to enable
# VirtualBox to run on Ubuntu systems with UEFI Secure Boot enabled.
#
# Usage: sudo ./sign-vbox-modules.sh [--setup|--sign|--verify|--load|--rebuild|--full]
#   --setup  : Create signing keys and enroll MOK
#   --sign   : Sign VirtualBox modules
#   --verify : Verify module signatures
#   --load   : Load VirtualBox modules
#   --rebuild: Rebuild modules via DKMS
#   --full   : Complete workflow (rebuild + sign + verify + load)
#   (no args): Interactive mode
################################################################################

set -uo pipefail  # Don't exit automatically on command failure; we handle errors explicitly

# Configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="/var/log/vbox-module-signing.log"
readonly KEY_DIR="/root/module-signing"
readonly PRIVATE_KEY="${KEY_DIR}/MOK.priv"
readonly PUBLIC_KEY="${KEY_DIR}/MOK.der"
readonly HASH_ALGO="sha256"

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
    # Append structured log entry to the log file only. Avoid printing
    # timestamped log lines to stdout because some functions use
    # command-substitution (e.g. mapfile < <(find_vbox_modules)) and
    # must not receive log text on stdout.
    printf '[%s] [%s] %s\n' "${timestamp}" "${level}" "${message}" >> "${LOG_FILE}" 2>/dev/null || true
}

log_info() {
    log "INFO" "$@"
    # Print human-friendly info messages to stderr so command-substitution
    # that reads stdout (e.g. mapfile < <(find_vbox_modules)) does not
    # capture log text.
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

################################################################################
# Error Handling
################################################################################

cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Script exited with error code ${exit_code}"
    fi
}

trap cleanup EXIT

error_exit() {
    log_error "$1"
    exit "${2:-1}"
}

################################################################################
# Validation Functions
################################################################################

check_root() {
    if [ "$EUID" -ne 0 ]; then
        error_exit "This script must be run as root. Please use sudo." 1
    fi
}

check_dependencies() {
    log_info "Checking required dependencies..."
    
    local missing_deps=()
    local deps=("openssl" "mokutil" "modinfo" "modprobe")
    # zstd may be needed for compressed kernel modules (*.ko.zst)
    deps+=("zstd")
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        error_exit "Missing required dependencies: ${missing_deps[*]}. Please install them first." 1
    fi
    
    log_success "All dependencies found"
}

check_secure_boot() {
    log_info "Checking Secure Boot status..."
    
    if [ -f /sys/firmware/efi/efivars/SecureBoot-* ]; then
        local sb_status=$(mokutil --sb-state 2>/dev/null || echo "unknown")
        log_info "Secure Boot status: ${sb_status}"
        
        if echo "$sb_status" | grep -q "SecureBoot enabled"; then
            log_success "Secure Boot is enabled"
            return 0
        else
            log_warning "Secure Boot appears to be disabled"
            return 1
        fi
    else
        log_warning "Could not determine Secure Boot status (UEFI variables not accessible)"
        return 1
    fi
}

check_virtualbox_installed() {
    log_info "Checking if VirtualBox is installed..."
    
    if ! command -v VBoxManage &> /dev/null; then
        error_exit "VirtualBox is not installed. Please install it first." 1
    fi
    
    local vbox_version=$(VBoxManage --version 2>/dev/null || echo "unknown")
    log_success "VirtualBox version ${vbox_version} found"
}

rebuild_vbox_modules() {
    log_info "Rebuilding VirtualBox kernel modules via DKMS..."
    
    # Check if virtualbox-dkms is installed
    if ! dpkg -l | grep -q virtualbox-dkms; then
        log_warning "virtualbox-dkms package not found"
        read -p "Install virtualbox-dkms? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if apt-get install -y virtualbox-dkms 2>&1 | tee -a "${LOG_FILE}"; then
                log_success "virtualbox-dkms installed"
            else
                error_exit "Failed to install virtualbox-dkms" 1
            fi
        else
            error_exit "virtualbox-dkms is required to rebuild modules" 1
        fi
    fi
    
    # Find VirtualBox DKMS version
    local vbox_dkms_version=$(dkms status virtualbox 2>/dev/null | head -1 | grep -oP 'virtualbox/\K[^,]+' || echo "")
    
    if [ -z "$vbox_dkms_version" ]; then
        error_exit "Could not determine VirtualBox DKMS version. Is virtualbox-dkms installed?" 1
    fi
    
    log_info "Found VirtualBox DKMS version: ${vbox_dkms_version}"
    
    local kernel_version=$(uname -r)
    
    # Unload modules if loaded
    log_info "Unloading existing VirtualBox modules..."
    if lsmod | grep -q vboxdrv; then
        modprobe -r vboxnetadp vboxnetflt vboxdrv 2>/dev/null || true
    fi
    
    # Remove old modules
    log_info "Removing old module files..."
    rm -f /lib/modules/${kernel_version}/updates/dkms/vbox*.ko* 2>/dev/null || true
    
    # Force rebuild
    log_info "Forcing DKMS rebuild (this may take a minute)..."
    if dkms install virtualbox/${vbox_dkms_version} -k ${kernel_version} --force 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "VirtualBox modules rebuilt successfully"
        
        # Verify modules were created
        if ls /lib/modules/${kernel_version}/updates/dkms/vbox*.ko* &> /dev/null; then
            local module_count=$(ls /lib/modules/${kernel_version}/updates/dkms/vbox*.ko* | wc -l)
            log_success "Created ${module_count} module file(s)"
            return 0
        else
            error_exit "DKMS build completed but no module files found" 1
        fi
    else
        error_exit "Failed to rebuild VirtualBox modules via DKMS" 1
    fi
}

find_sign_file_tool() {
    log_info "Locating sign-file tool..."
    
    local kernel_version=$(uname -r)
    local sign_file_paths=(
        "/usr/src/linux-headers-${kernel_version}/scripts/sign-file"
        "/lib/modules/${kernel_version}/build/scripts/sign-file"
        "/usr/src/kernels/${kernel_version}/scripts/sign-file"
    )
    
    for path in "${sign_file_paths[@]}"; do
        if [ -f "$path" ]; then
            log_success "Found sign-file at: $path"
            echo "$path"
            return 0
        fi
    done
    
    error_exit "Could not find sign-file tool. You may need to install linux-headers-$(uname -r)" 1
}

################################################################################
# Setup Functions
################################################################################

create_signing_keys() {
    log_info "Creating signing keys..."
    
    if [ -f "${PRIVATE_KEY}" ] && [ -f "${PUBLIC_KEY}" ]; then
        log_warning "Signing keys already exist at ${KEY_DIR}"
        read -p "Do you want to recreate them? This will require re-enrolling MOK. (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Keeping existing keys"
            return 0
        fi
    fi
    
    # Create key directory
    mkdir -p "${KEY_DIR}" || error_exit "Failed to create key directory" 1
    
    # Get user name for certificate
    local cert_name
    echo ""
    read -p "Enter name for certificate (e.g., your name) [VirtualBox Module Signing]: " cert_name
    cert_name="${cert_name:-VirtualBox Module Signing}"
    
    echo ""
    log_info "========================================================"
    log_info "Generating RSA Key Pair - Setting Passphrase"
    log_info "========================================================"
    echo ""
    log_warning "You will be prompted to create a PASSPHRASE for your signing key."
    log_warning "This is the MAIN password - you'll need it every time you sign modules!"
    echo ""
    log_info "Requirements:"
    log_info "  - You'll need to enter it TWICE (must match)"
    log_info "  - Make it memorable but secure"
    log_info "  - Write it down somewhere safe"
    echo ""
    log_warning "OpenSSL will prompt:"
    log_warning "  1. 'Enter PEM pass phrase:' (type your passphrase)"
    log_warning "  2. 'Verifying - Enter PEM pass phrase:' (type it again)"
    echo ""
    read -p "Press Enter when ready to create the signing key passphrase..."
    echo ""
    
    if openssl req \
        -new \
        -x509 \
        -newkey rsa:2048 \
        -keyout "${PRIVATE_KEY}" \
        -outform DER \
        -out "${PUBLIC_KEY}" \
        -days 36500 \
        -subj "/CN=${cert_name}/" 2>&1 | tee -a "${LOG_FILE}"; then
        
        # Set restrictive permissions
        chmod 600 "${KEY_DIR}"/MOK.* || error_exit "Failed to set key permissions" 1
        
        echo ""
        log_success "Signing keys created successfully"
        log_info "Private key: ${PRIVATE_KEY}"
        log_info "Public key: ${PUBLIC_KEY}"
        return 0
    else
        echo ""
        error_exit "Failed to create signing keys" 1
    fi
}

enroll_mok() {
    log_info "Enrolling Machine Owner Key (MOK)..."
    
    if [ ! -f "${PUBLIC_KEY}" ]; then
        error_exit "Public key not found at ${PUBLIC_KEY}. Run --setup first." 1
    fi
    
    # Check if key is already enrolled
    if mokutil --list-enrolled 2>/dev/null | grep -q "$(openssl x509 -inform DER -in ${PUBLIC_KEY} -noout -subject 2>/dev/null)"; then
        log_success "MOK already enrolled"
        return 0
    fi
    
    echo ""
    log_info "========================================================"
    log_info "MOK Enrollment - Setting Temporary Password"
    log_info "========================================================"
    echo ""
    log_warning "You will now be prompted to set a TEMPORARY password for MOK enrollment."
    log_warning "This is NOT the same as your signing key passphrase!"
    echo ""
    log_info "Requirements:"
    log_info "  - Minimum 8 characters (recommended: 12+)"
    log_info "  - You'll need to enter it TWICE (must match)"
    log_info "  - Only needed during next boot for MOK Manager"
    log_info "  - Can be simple since it's temporary (e.g., 'temppass123')"
    echo ""
    log_warning "IMPORTANT: You will enter this password THREE times total:"
    log_warning "  1. First entry (mokutil will prompt: 'input password:')"
    log_warning "  2. Confirmation (mokutil will prompt: 'input password again:')"
    log_warning "  3. At next boot in MOK Manager blue screen"
    echo ""
    read -p "Press Enter when ready to set the temporary MOK password..."
    echo ""
    
    # Attempt to import MOK
    if mokutil --import "${PUBLIC_KEY}"; then
        echo ""
        log_success "MOK import initiated successfully!"
        echo ""
        log_warning "=============================================="
        log_warning "NEXT STEPS - READ CAREFULLY!"
        log_warning "=============================================="
        echo ""
        log_info "1. REBOOT your system now:"
        log_info "   sudo reboot"
        echo ""
        log_info "2. During boot, you'll see a BLUE SCREEN (MOK Manager):"
        log_info "   - Select 'Enroll MOK'"
        log_info "   - Select 'Continue'"
        log_info "   - Select 'Yes' to confirm enrollment"
        log_info "   - Enter the temporary password you just created"
        log_info "   - Select 'Reboot'"
        echo ""
        log_info "3. After reboot, sign the modules:"
        log_info "   sudo $0 --sign"
        echo ""
        read -p "Press Enter to continue or Ctrl+C to cancel..."
        return 0
    else
        local exit_code=$?
        echo ""
        log_error "Failed to import MOK (exit code: ${exit_code})"
        echo ""
        log_info "Common issues:"
        log_info "  - Passwords didn't match: Try again and type carefully"
        log_info "  - Password too short: Use at least 8 characters"
        log_info "  - Cancelled: Press Ctrl+C if you want to abort"
        echo ""
        log_info "To retry: sudo $0 --setup"
        return 1
    fi
}

################################################################################
# Signing Functions
################################################################################

find_vbox_modules() {
    log_info "Locating VirtualBox kernel modules..."
    
    local module_base
    if ! module_base=$(modinfo -n vboxdrv 2>/dev/null); then
        error_exit "Could not locate vboxdrv module. Is VirtualBox installed correctly?" 1
    fi
    
    local module_dir=$(dirname "$module_base")
    log_info "Module directory: ${module_dir}"
    
    # Find all .ko files (both compressed and uncompressed)
    local modules=()
    while IFS= read -r -d '' module; do
        modules+=("$module")
    done < <(find "$module_dir" -name "vbox*.ko*" -print0 2>/dev/null)
    
    if [ ${#modules[@]} -eq 0 ]; then
        error_exit "No VirtualBox modules found in ${module_dir}" 1
    fi
    
    printf '%s\n' "${modules[@]}"
}

decompress_module() {
    local module="$1"
    
    if [[ "$module" == *.ko.xz ]]; then
        log_info "Decompressing ${module}..."
        if xz -dk "$module" 2>&1 >> "${LOG_FILE}"; then
            echo "${module%.xz}"
            return 0
        else
            log_error "Failed to decompress ${module}"
            return 1
        fi
    elif [[ "$module" == *.ko.gz ]]; then
        log_info "Decompressing ${module}..."
        if gunzip -k "$module" 2>&1 >> "${LOG_FILE}"; then
            echo "${module%.gz}"
            return 0
        else
            log_error "Failed to decompress ${module}"
            return 1
        fi
    elif [[ "$module" == *.ko.zst ]]; then
        log_info "Decompressing ${module} (zstd)..."
        # -k keeps the original file, -d decompresses, -f force overwrite, -q quiet
        if zstd -dkfq "$module" 2>&1 >> "${LOG_FILE}"; then
            echo "${module%.zst}"
            return 0
        else
            log_error "Failed to decompress ${module}"
            return 1
        fi
    else
        echo "$module"
        return 0
    fi
}

compress_module() {
    local module="$1"
    local original_name="$2"
    
    if [[ "$original_name" == *.ko.xz ]]; then
        log_info "Recompressing ${module}..."
        xz -f "$module" 2>&1 >> "${LOG_FILE}"
    elif [[ "$original_name" == *.ko.gz ]]; then
        log_info "Recompressing ${module}..."
        gzip -f "$module" 2>&1 >> "${LOG_FILE}"
    elif [[ "$original_name" == *.ko.zst ]]; then
        log_info "Recompressing ${module} (zstd)..."
        # -f force overwrite, --rm remove source file after compression, -q quiet
        zstd -qf --rm "$module" 2>&1 >> "${LOG_FILE}"
    fi
}

sign_module() {
    local module="$1"
    local sign_file_tool="$2"
    
    log_info "Signing module: ${module}..."
    
    # Check if module exists
    if [ ! -f "$module" ]; then
        log_error "Module file not found: ${module}"
        return 1
    fi
    
    # Sign the module
    if "${sign_file_tool}" "${HASH_ALGO}" "${PRIVATE_KEY}" "${PUBLIC_KEY}" "$module" 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "Successfully signed: $(basename ${module})"
        return 0
    else
        log_error "Failed to sign: ${module}"
        return 1
    fi
}

sign_all_modules() {
    log_info "Starting VirtualBox module signing process..."
    
    # Verify keys exist
    if [ ! -f "${PRIVATE_KEY}" ] || [ ! -f "${PUBLIC_KEY}" ]; then
        error_exit "Signing keys not found. Run with --setup first." 1
    fi
    
    # Find sign-file tool
    local sign_file_tool
    sign_file_tool=$(find_sign_file_tool)
    
    # Find modules
    local modules
    mapfile -t modules < <(find_vbox_modules)
    
    log_info "Found ${#modules[@]} VirtualBox module(s) to sign"
    
    # Set up passphrase
    if [ -z "${KBUILD_SIGN_PIN:-}" ]; then
        read -s -p "Enter passphrase for ${PRIVATE_KEY}: " KBUILD_SIGN_PIN
        echo
        export KBUILD_SIGN_PIN
    fi
    
    local signed_count=0
    local failed_count=0
    
    # Sign each module
    for module in "${modules[@]}"; do
        local original_module="$module"
        local was_compressed=false
        local decompressed_module="$module"
        
        # Decompress if needed
        if [[ "$module" == *.ko.xz ]] || [[ "$module" == *.ko.gz ]] || [[ "$module" == *.ko.zst ]]; then
            was_compressed=true
            decompressed_module=$(decompress_module "$module")
            if [ $? -ne 0 ] || [ -z "$decompressed_module" ]; then
                log_error "Failed to decompress ${module}"
                ((failed_count++))
                continue
            fi
            module="$decompressed_module"
        fi
        
        # Sign the module
        if sign_module "$module" "$sign_file_tool"; then
            ((signed_count++))
        else
            ((failed_count++))
        fi
        
        # Recompress if it was compressed
        if [ "$was_compressed" = true ]; then
            compress_module "$module" "$original_module"
        fi
    done
    
    echo ""
    log_info "Signing complete: ${signed_count} successful, ${failed_count} failed"
    
    if [ $failed_count -eq 0 ]; then
        log_success "All modules signed successfully!"
        return 0
    else
        log_error "Some modules failed to sign"
        return 1
    fi
}

################################################################################
# Verification Functions
################################################################################

verify_mok_enrolled() {
    log_info "Verifying MOK enrollment..."
    
    if mokutil --list-enrolled 2>/dev/null | grep -q "CN="; then
        log_success "MOK is enrolled"
        mokutil --list-enrolled 2>&1 | grep "Subject:" | tee -a "${LOG_FILE}"
        return 0
    else
        log_error "MOK is not enrolled"
        return 1
    fi
}

verify_module_signature() {
    local module="$1"
    
    # Decompress if needed
    local decompressed=false
    local original_module="$module"
    
    if [[ "$module" == *.xz ]]; then
        xz -dk "$module" 2>/dev/null
        module="${module%.xz}"
        decompressed=true
    elif [[ "$module" == *.gz ]]; then
        gunzip -k "$module" 2>/dev/null
        module="${module%.gz}"
        decompressed=true
    elif [[ "$module" == *.zst ]]; then
        zstd -dkf "$module" 2>/dev/null
        module="${module%.zst}"
        decompressed=true
    fi
    
    # Check signature
    local result=1
    if modinfo "$module" 2>/dev/null | grep -q "sig_id:"; then
        log_success "Module is signed: $(basename ${original_module})"
        result=0
    else
        log_error "Module is NOT signed: $(basename ${original_module})"
        result=1
    fi
    
    # Remove decompressed file if we created it
    if [ "$decompressed" = true ] && [ -f "$module" ]; then
        rm -f "$module" 2>/dev/null
    fi
    
    return $result
}

verify_all_modules() {
    log_info "Verifying VirtualBox module signatures..."
    
    local modules
    mapfile -t modules < <(find_vbox_modules)
    
    local verified_count=0
    local unverified_count=0
    
    for module in "${modules[@]}"; do
        if verify_module_signature "$module"; then
            ((verified_count++))
        else
            ((unverified_count++))
        fi
    done
    
    echo ""
    log_info "Verification complete: ${verified_count} signed, ${unverified_count} unsigned"
    
    if [ $unverified_count -eq 0 ]; then
        log_success "All modules are properly signed!"
        return 0
    else
        log_error "Some modules are not signed"
        return 1
    fi
}

load_vbox_modules() {
    log_info "Loading VirtualBox kernel modules..."
    
    local modules=("vboxdrv" "vboxnetflt" "vboxnetadp")
    
    for mod in "${modules[@]}"; do
        if modprobe "$mod" 2>&1 | tee -a "${LOG_FILE}"; then
            log_success "Loaded module: ${mod}"
        else
            log_error "Failed to load module: ${mod}"
            return 1
        fi
    done
    
    log_success "All VirtualBox modules loaded successfully"
    return 0
}

################################################################################
# Interactive Menu
################################################################################

show_menu() {
    echo ""
    echo "========================================"
    echo "  VirtualBox Secure Boot Module Signer"
    echo "========================================"
    echo ""
    echo "1) Complete Setup (create keys + enroll MOK)"
    echo "2) Create Signing Keys Only"
    echo "3) Enroll MOK Only"
    echo "4) Rebuild VirtualBox Modules (DKMS)"
    echo "5) Sign VirtualBox Modules"
    echo "6) Verify Module Signatures"
    echo "7) Load VirtualBox Modules"
    echo "8) Full Process (rebuild + sign + verify + load)"
    echo "9) System Information"
    echo "0) Exit"
    echo ""
}

show_system_info() {
    echo ""
    log_info "System Information:"
    echo "  Kernel: $(uname -r)"
    echo "  OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    
    if command -v VBoxManage &> /dev/null; then
        echo "  VirtualBox: $(VBoxManage --version)"
    else
        echo "  VirtualBox: Not installed"
    fi
    
    check_secure_boot
    
    if [ -f "${PRIVATE_KEY}" ]; then
        echo "  Signing Key: Present"
    else
        echo "  Signing Key: Not found"
    fi
    
    verify_mok_enrolled
    echo ""
}

interactive_mode() {
    while true; do
        show_menu
        read -p "Select an option [0-9]: " choice
        
        case $choice in
            1)
                create_signing_keys
                enroll_mok
                ;;
            2)
                create_signing_keys
                ;;
            3)
                enroll_mok
                ;;
            4)
                rebuild_vbox_modules
                ;;
            5)
                sign_all_modules
                ;;
            6)
                verify_all_modules
                ;;
            7)
                load_vbox_modules
                ;;
            8)
                rebuild_vbox_modules && sign_all_modules && verify_all_modules && load_vbox_modules
                ;;
            9)
                show_system_info
                ;;
            0)
                log_info "Exiting..."
                exit 0
                ;;
            *)
                log_error "Invalid option. Please select 0-9."
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

################################################################################
# Main
################################################################################

main() {
    # Initialize log file
    touch "${LOG_FILE}" 2>/dev/null || error_exit "Cannot create log file at ${LOG_FILE}" 1
    
    log_info "========== VirtualBox Module Signing Script Started =========="
    log_info "Script version: 1.0"
    log_info "Running on: $(uname -a)"
    
    # Check prerequisites
    check_root
    check_dependencies
    check_secure_boot
    check_virtualbox_installed
    
    # Parse command line arguments
    case "${1:-}" in
        --setup)
            create_signing_keys
            enroll_mok
            ;;
        --rebuild)
            rebuild_vbox_modules
            ;;
        --sign)
            sign_all_modules
            ;;
        --verify)
            verify_all_modules
            ;;
        --load)
            load_vbox_modules
            ;;
        --full)
            rebuild_vbox_modules && sign_all_modules && verify_all_modules && load_vbox_modules
            ;;
        --help|-h)
            echo "Usage: sudo $0 [OPTION]"
            echo ""
            echo "Options:"
            echo "  --setup    Create signing keys and enroll MOK"
            echo "  --rebuild  Rebuild VirtualBox modules via DKMS"
            echo "  --sign     Sign VirtualBox modules"
            echo "  --verify   Verify module signatures"
            echo "  --load     Load VirtualBox modules"
            echo "  --full     Rebuild, sign, verify, and load modules"
            echo "  --help     Show this help message"
            echo ""
            echo "If no option is provided, interactive mode will start."
            exit 0
            ;;
        "")
            interactive_mode
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
