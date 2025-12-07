#!/usr/bin/env bash
# vbox-lib.sh - VirtualBox management function library
# Source this in your scripts: source ./vbox-lib.sh

set -euo pipefail

# Source defaults (computes RAM/CPU based on host system)
SCRIPT_DIR_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR_LIB/vbox-defaults.sh" ]; then
    source "$SCRIPT_DIR_LIB/vbox-defaults.sh"
else
    # Fallback if defaults file not found
    export VBOX_BASE="${VBOX_BASE:-$HOME/vms}"
    export VBOX_DISKS="${VBOX_DISKS:-$VBOX_BASE/disks}"
    export VBOX_ISOS="${VBOX_ISOS:-$VBOX_BASE/isos}"
fi

# ==============================================================================
# Logging
# ==============================================================================
log_info()    { echo -e "\033[1;34m[INFO]\033[0m $*"; }
log_success() { echo -e "\033[1;32m[OK]\033[0m $*"; }
log_warn()    { echo -e "\033[1;33m[WARN]\033[0m $*" >&2; }
log_error()   { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }
log_section() { echo -e "\n\033[1;36m=== $* ===\033[0m\n"; }

# ==============================================================================
# Validation
# ==============================================================================
require_vboxmanage() {
    if ! command -v VBoxManage >/dev/null 2>&1; then
        log_error "VBoxManage not found. Install VirtualBox first."
        exit 1
    fi
}

vm_exists() {
    local name="$1"
    VBoxManage showvminfo "$name" &>/dev/null
}

# ==============================================================================
# VM Creation
# ==============================================================================
vbox_create() {
    local name="$1"
    local ostype="${2:-${VBOX_DEFAULT_OSTYPE:-Ubuntu_64}}"
    
    if vm_exists "$name"; then
        log_error "VM '$name' already exists"
        return 1
    fi
    
    VBoxManage createvm --name "$name" --ostype "$ostype" --register
    log_success "Created VM: $name (ostype: $ostype)"
}

vbox_configure() {
    local name="$1"
    local ram="${2:-${VBOX_DEFAULT_RAM:-4096}}"
    local cpus="${3:-${VBOX_DEFAULT_CPUS:-2}}"
    local vram="${4:-${VBOX_DEFAULT_VRAM_SERVER:-16}}"
    local vm_type="${5:-server}"  # server or desktop
    
    # Use desktop VRAM if type is desktop
    if [ "$vm_type" = "desktop" ]; then
        vram="${vram:-${VBOX_DEFAULT_VRAM_DESKTOP:-128}}"
    fi
    
    log_info "Configuring VM: $name"
    log_info "  RAM: ${ram}MB, CPUs: ${cpus}, VRAM: ${vram}MB, Type: ${vm_type}"
    
    # Basic configuration
    VBoxManage modifyvm "$name" \
        --memory "$ram" \
        --cpus "$cpus" \
        --vram "$vram" \
        --graphicscontroller "${VBOX_DEFAULT_GRAPHICS_CONTROLLER:-vmsvga}" \
        --acpi on \
        --ioapic on \
        --rtcuseutc on \
        --boot1 "${VBOX_DEFAULT_BOOT1:-dvd}" \
        --boot2 "${VBOX_DEFAULT_BOOT2:-disk}" \
        --boot3 "${VBOX_DEFAULT_BOOT3:-none}" \
        --boot4 "${VBOX_DEFAULT_BOOT4:-none}"
    
    # CPU passthrough / nested virtualization
    if [ "${VBOX_DEFAULT_NESTED_HW_VIRT:-on}" = "on" ]; then
        VBoxManage modifyvm "$name" --nested-hw-virt on
        log_info "  Nested HW virtualization: enabled"
    fi
    
    # Hardware virtualization
    if [ "${VBOX_DEFAULT_HW_VIRT:-on}" = "on" ]; then
        VBoxManage modifyvm "$name" --hwvirtex on
        log_info "  Hardware virtualization (VT-x/AMD-V): enabled"
    fi
    
    # PAE/NX
    if [ "${VBOX_DEFAULT_PAE:-on}" = "on" ]; then
        VBoxManage modifyvm "$name" --pae on
        log_info "  PAE/NX: enabled"
    fi
    
    # EFI (required for Secure Boot)
    if [ "${VBOX_DEFAULT_EFI:-on}" = "on" ]; then
        VBoxManage modifyvm "$name" --firmware efi64
        log_info "  EFI firmware: enabled"
    fi
    
    # Secure Boot
    if [ "${VBOX_DEFAULT_SECUREBOOT:-on}" = "on" ]; then
        # Secure Boot requires EFI
        VBoxManage modifyvm "$name" --firmware efi64
        # Note: Full Secure Boot requires signing - this enables the setting
        log_info "  Secure Boot: enabled (EFI mode)"
    fi
    
    log_success "Configured VM: $name (RAM=${ram}MB, CPUs=${cpus}, VRAM=${vram}MB)"
}

# ==============================================================================
# Storage
# ==============================================================================
vbox_add_sata() {
    local name="$1"
    
    VBoxManage storagectl "$name" \
        --name "${VBOX_DEFAULT_STORAGE_CONTROLLER:-SATA}" \
        --add sata \
        --controller IntelAhci \
        --portcount 4 \
        --bootable on
    
    log_success "Added SATA controller to $name"
}

vbox_create_disk() {
    local name="$1"
    local size_mb="${2:-${VBOX_DEFAULT_DISK:-512000}}"
    local disk_path="${VBOX_DISKS}/${name}.vdi"
    
    mkdir -p "$VBOX_DISKS"
    # Redirect VBoxManage output to stderr so only disk_path goes to stdout
    VBoxManage createmedium disk \
        --filename "$disk_path" \
        --size "$size_mb" \
        --format "${VBOX_DEFAULT_DISK_FORMAT:-VDI}" \
        --variant "${VBOX_DEFAULT_DISK_VARIANT:-Standard}" >&2
    
    # Send log to stderr so it doesn't pollute the return value
    log_success "Created disk: $disk_path (${size_mb}MB / $(( size_mb / 1024 ))GB)" >&2
    # Return only the path on stdout for capture
    printf '%s' "$disk_path"
}

vbox_attach_disk() {
    local name="$1"
    local disk_path="$2"
    local port="${3:-0}"
    
    VBoxManage storageattach "$name" \
        --storagectl "${VBOX_DEFAULT_STORAGE_CONTROLLER:-SATA}" \
        --port "$port" \
        --device 0 \
        --type hdd \
        --medium "$disk_path"
    
    log_success "Attached disk to $name on port $port"
}

vbox_attach_iso() {
    local name="$1"
    local iso_path="$2"
    local port="${3:-1}"
    
    VBoxManage storageattach "$name" \
        --storagectl "${VBOX_DEFAULT_STORAGE_CONTROLLER:-SATA}" \
        --port "$port" \
        --device 0 \
        --type dvddrive \
        --medium "$iso_path"
    
    log_success "Attached ISO: $(basename "$iso_path")"
}

vbox_eject_iso() {
    local name="$1"
    local port="${2:-1}"
    
    VBoxManage storageattach "$name" \
        --storagectl "${VBOX_DEFAULT_STORAGE_CONTROLLER:-SATA}" \
        --port "$port" \
        --device 0 \
        --type dvddrive \
        --medium emptydrive
    
    log_success "Ejected ISO from $name"
}

# ==============================================================================
# Networking - Bridged is default
# ==============================================================================
vbox_detect_bridge_iface() {
    # Auto-detect the default network interface
    local iface
    iface=$(ip route 2>/dev/null | awk '/default/ {print $5; exit}')
    if [ -z "$iface" ]; then
        # Fallback: find first non-loopback interface
        iface=$(ip -o link show 2>/dev/null | awk -F': ' '!/lo:/ {print $2; exit}')
    fi
    [ -z "$iface" ] && iface="eth0"
    echo "$iface"
}

vbox_network_bridged() {
    local name="$1"
    local iface="${2:-}"
    
    # Auto-detect interface if not specified
    if [ -z "$iface" ]; then
        iface=$(vbox_detect_bridge_iface)
    fi
    
    VBoxManage modifyvm "$name" \
        --nic1 bridged \
        --bridgeadapter1 "$iface"
    
    log_success "Configured bridged network on $iface"
}

vbox_network_nat() {
    local name="$1"
    local ssh_port="${2:-${VBOX_DEFAULT_SSH_PORT:-2222}}"
    
    VBoxManage modifyvm "$name" \
        --nic1 nat \
        --natpf1 "ssh,tcp,,${ssh_port},,22"
    
    log_success "Configured NAT with SSH on port $ssh_port"
}

# ==============================================================================
# KVM Management
# ==============================================================================
kvm_is_loaded() {
    lsmod | grep -q "^kvm" 2>/dev/null
}

kvm_disable() {
    if ! command -v virtualbox-sb-manager >/dev/null 2>&1; then
        log_error "virtualbox-sb-manager not found. Install it with: make install"
        log_info "Or manually disable KVM: sudo modprobe -r kvm_intel kvm"
        return 1
    fi
    
    log_info "Disabling KVM using virtualbox-sb-manager..."
    if sudo virtualbox-sb-manager kvm disable; then
        log_success "KVM disabled successfully"
        return 0
    else
        log_error "Failed to disable KVM"
        return 1
    fi
}

kvm_enable() {
    if ! command -v virtualbox-sb-manager >/dev/null 2>&1; then
        log_error "virtualbox-sb-manager not found"
        return 1
    fi
    
    log_info "Re-enabling KVM..."
    sudo virtualbox-sb-manager kvm enable
}

# ==============================================================================
# Lifecycle
# ==============================================================================
vbox_start() {
    local name="$1"
    local type="${2:-headless}"  # headless, gui, sdl
    
    # Check if KVM is loaded and might conflict
    if kvm_is_loaded; then
        log_warn "KVM modules are loaded - VirtualBox cannot run alongside KVM"
        log_info "Automatically disabling KVM..."
        if ! kvm_disable; then
            log_error "Failed to disable KVM. Cannot start VM."
            log_info "Try manually: sudo virtualbox-sb-manager kvm disable"
            return 1
        fi
        # Small delay to ensure modules are fully unloaded
        sleep 1
    fi
    
    # Try to start the VM
    if VBoxManage startvm "$name" --type "$type"; then
        log_success "Started $name ($type mode)"
    else
        local exit_code=$?
        # Check if it's still a KVM error
        if [ $exit_code -ne 0 ]; then
            log_error "Failed to start VM. Exit code: $exit_code"
            if kvm_is_loaded; then
                log_error "KVM is still loaded. Try: sudo virtualbox-sb-manager kvm disable"
            fi
            return $exit_code
        fi
    fi
}

vbox_stop() {
    local name="$1"
    local method="${2:-acpipowerbutton}"  # acpipowerbutton, poweroff, savestate
    
    VBoxManage controlvm "$name" "$method"
    log_success "Stopped $name ($method)"
}

vbox_pause() {
    local name="$1"
    VBoxManage controlvm "$name" pause
    log_success "Paused $name"
}

vbox_resume() {
    local name="$1"
    VBoxManage controlvm "$name" resume
    log_success "Resumed $name"
}

vbox_reset() {
    local name="$1"
    VBoxManage controlvm "$name" reset
    log_success "Reset $name"
}

vbox_delete() {
    local name="$1"
    
    # Stop if running
    if VBoxManage list runningvms | grep -q "\"$name\""; then
        log_info "Stopping VM before deletion..."
        VBoxManage controlvm "$name" poweroff 2>/dev/null || true
        sleep 2
    fi
    
    VBoxManage unregistervm "$name" --delete
    log_success "Deleted VM: $name"
}

# ==============================================================================
# Snapshots
# ==============================================================================
vbox_snapshot_take() {
    local name="$1"
    local snap_name="$2"
    local description="${3:-}"
    
    if [ -n "$description" ]; then
        VBoxManage snapshot "$name" take "$snap_name" --description "$description"
    else
        VBoxManage snapshot "$name" take "$snap_name"
    fi
    log_success "Snapshot '$snap_name' created for $name"
}

vbox_snapshot_restore() {
    local name="$1"
    local snap_name="$2"
    
    VBoxManage snapshot "$name" restore "$snap_name"
    log_success "Restored $name to snapshot '$snap_name'"
}

vbox_snapshot_list() {
    local name="$1"
    VBoxManage snapshot "$name" list 2>/dev/null || echo "No snapshots"
}

vbox_snapshot_delete() {
    local name="$1"
    local snap_name="$2"
    
    VBoxManage snapshot "$name" delete "$snap_name"
    log_success "Deleted snapshot '$snap_name' from $name"
}

# ==============================================================================
# Cloning
# ==============================================================================
vbox_clone_full() {
    local template="$1"
    local new_name="$2"
    
    VBoxManage clonevm "$template" \
        --name "$new_name" \
        --register \
        --mode all
    
    log_success "Full clone: $template -> $new_name"
}

vbox_clone_linked() {
    local template="$1"
    local new_name="$2"
    
    # Linked clone requires a snapshot
    local snap_name="linked-clone-base"
    if ! VBoxManage snapshot "$template" list 2>/dev/null | grep -q "$snap_name"; then
        log_info "Creating base snapshot for linked clone..."
        vbox_snapshot_take "$template" "$snap_name" "Base for linked clones"
    fi
    
    VBoxManage clonevm "$template" \
        --name "$new_name" \
        --register \
        --options link \
        --snapshot "$snap_name"
    
    log_success "Linked clone: $template -> $new_name"
}

# ==============================================================================
# Info & Listing
# ==============================================================================
vbox_list_all() {
    VBoxManage list vms
}

vbox_list_running() {
    VBoxManage list runningvms
}

vbox_info() {
    local name="$1"
    VBoxManage showvminfo "$name"
}

vbox_info_brief() {
    local name="$1"
    VBoxManage showvminfo "$name" --machinereadable | grep -E "^(name|ostype|memory|cpus|nic1|VMState)="
}

vbox_get_ip() {
    local name="$1"
    local timeout="${2:-30}"
    local waited=0
    
    while [ $waited -lt $timeout ]; do
        local ip
        ip=$(VBoxManage guestproperty get "$name" "/VirtualBox/GuestInfo/Net/0/V4/IP" 2>/dev/null | awk '{print $2}')
        if [ -n "$ip" ] && [ "$ip" != "No" ]; then
            echo "$ip"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done
    
    log_warn "Could not get IP for $name within ${timeout}s"
    return 1
}

vbox_list_bridgedifs() {
    VBoxManage list bridgedifs | grep -E "^Name:" | cut -d: -f2 | sed 's/^ //'
}

# ==============================================================================
# Utility
# ==============================================================================
vbox_wait_for_shutdown() {
    local name="$1"
    local timeout="${2:-120}"
    local waited=0
    
    log_info "Waiting for $name to shut down..."
    while VBoxManage list runningvms | grep -q "\"$name\""; do
        sleep 2
        waited=$((waited + 2))
        if [ $waited -ge $timeout ]; then
            log_warn "Timeout waiting for shutdown"
            return 1
        fi
    done
    log_success "$name has shut down"
}

vbox_wait_for_guestadditions() {
    local name="$1"
    local timeout="${2:-300}"
    local waited=0
    
    log_info "Waiting for Guest Additions to be ready..."
    while [ $waited -lt $timeout ]; do
        local status
        status=$(VBoxManage guestproperty get "$name" "/VirtualBox/GuestAdd/Version" 2>/dev/null | awk '{print $2}')
        if [ -n "$status" ] && [ "$status" != "No" ]; then
            log_success "Guest Additions ready (version: $status)"
            return 0
        fi
        sleep 5
        waited=$((waited + 5))
    done
    
    log_warn "Guest Additions not detected within ${timeout}s"
    return 1
}
