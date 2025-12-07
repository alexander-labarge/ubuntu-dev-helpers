#!/usr/bin/env bash
# create-vm.sh - Create Ubuntu VM with bridged networking and optional static IP
# Usage: ./create-vm.sh --name <vm-name> [OPTIONS]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vbox-lib.sh"

# ==============================================================================
# Defaults (sourced from vbox-defaults.sh via vbox-lib.sh)
# ==============================================================================
VM_NAME=""
VM_RAM="${VBOX_DEFAULT_RAM:-4096}"
VM_CPUS="${VBOX_DEFAULT_CPUS:-2}"
VM_DISK="${VBOX_DEFAULT_DISK:-512000}"
VM_VRAM=""  # Will be set based on type
VM_TYPE="${VBOX_DEFAULT_TYPE:-server}"
VM_NET="${VBOX_DEFAULT_NETWORK:-bridged}"
VM_IFACE=""  # auto-detect if empty
VM_IP=""     # static IP (optional)
VM_GATEWAY="${VBOX_DEFAULT_GATEWAY:-192.168.50.1}"
VM_DNS="${VBOX_DEFAULT_DNS:-8.8.8.8}"
VM_ISO=""    # auto-select based on type if empty
VM_START="1" # start after creation
VM_SSH_PORT="${VBOX_DEFAULT_SSH_PORT:-2222}"

# ==============================================================================
# Usage
# ==============================================================================
usage() {
    # Show current computed defaults
    log_section "Current Defaults (based on host system)"
    echo "  RAM:     ${VBOX_DEFAULT_RAM:-4096} MB (host RAM / 4)"
    echo "  CPUs:    ${VBOX_DEFAULT_CPUS:-2} (host CPUs / 4)"
    echo "  Disk:    ${VBOX_DEFAULT_DISK:-512000} MB ($(( ${VBOX_DEFAULT_DISK:-512000} / 1024 )) GB)"
    echo "  Gateway: ${VBOX_DEFAULT_GATEWAY:-192.168.50.1}"
    echo "  DNS:     ${VBOX_DEFAULT_DNS:-8.8.8.8}"
    echo "  Server VRAM:  ${VBOX_DEFAULT_VRAM_SERVER:-16} MB"
    echo "  Desktop VRAM: ${VBOX_DEFAULT_VRAM_DESKTOP:-128} MB"
    echo ""
    
    cat <<EOF
Usage: $(basename "$0") --name <vm-name> [OPTIONS]

Create a VirtualBox VM with Ubuntu, using bridged networking by default.
Defaults are computed from host system (RAM/4, CPUs/4) via vbox-defaults.sh.

Required:
  --name <name>             VM name (required)

System Configuration:
  --ram <MB>                RAM in MB (default: ${VBOX_DEFAULT_RAM:-4096})
  --cpus <N>                Number of CPUs (default: ${VBOX_DEFAULT_CPUS:-2})
  --disk <MB>               Disk size in MB (default: ${VBOX_DEFAULT_DISK:-512000})
  --type <server|desktop>   VM type for ISO selection (default: server)
                            Desktop uses ${VBOX_DEFAULT_VRAM_DESKTOP:-128}MB VRAM

Network Configuration:
  --network <bridged|nat>   Network mode (default: bridged)
  --iface <interface>       Bridge interface (default: auto-detect)
  --ssh-port <port>         SSH port for NAT mode (default: ${VBOX_DEFAULT_SSH_PORT:-2222})

Static IP (prints Netplan config for post-install):
  --ip <address>            Static IP address (e.g., 192.168.50.100)
  --gateway <address>       Gateway (default: ${VBOX_DEFAULT_GATEWAY:-192.168.50.1})
  --dns <address>           DNS server (default: ${VBOX_DEFAULT_DNS:-8.8.8.8})

Other:
  --iso <path>              Custom ISO path (default: auto from ~/vms/isos)
  --no-start                Don't start VM after creation
  --help, -h                Show this help

Security (enabled by default via vbox-defaults.sh):
  - EFI firmware:           ${VBOX_DEFAULT_EFI:-on}
  - Secure Boot:            ${VBOX_DEFAULT_SECUREBOOT:-on}
  - CPU passthrough:        ${VBOX_DEFAULT_NESTED_HW_VIRT:-on}
  - Hardware virtualization: ${VBOX_DEFAULT_HW_VIRT:-on}

Examples:
  # Create server VM (uses computed defaults)
  $(basename "$0") --name dev-server

  # Create server VM with static IP
  $(basename "$0") --name dev-server --ip 192.168.50.100

  # Create with custom specs
  $(basename "$0") --name build-box --ram 16384 --cpus 8 --disk 1024000

  # Create desktop VM (128MB VRAM)
  $(basename "$0") --name desktop --type desktop

  # Use NAT network instead
  $(basename "$0") --name isolated --network nat --ssh-port 2223

Via Makefile:
  make vm-create VM_NAME=dev-server VM_IP=192.168.50.100
  make vm-create VM_NAME=desktop VM_TYPE=desktop
EOF
    exit 0
}

# ==============================================================================
# Argument Parsing
# ==============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)      VM_NAME="$2"; shift 2 ;;
            --ram)       VM_RAM="$2"; shift 2 ;;
            --cpus)      VM_CPUS="$2"; shift 2 ;;
            --disk)      VM_DISK="$2"; shift 2 ;;
            --type)      VM_TYPE="$2"; shift 2 ;;
            --network)   VM_NET="$2"; shift 2 ;;
            --iface)     VM_IFACE="$2"; shift 2 ;;
            --ssh-port)  VM_SSH_PORT="$2"; shift 2 ;;
            --ip)        VM_IP="$2"; shift 2 ;;
            --gateway)   VM_GATEWAY="$2"; shift 2 ;;
            --dns)       VM_DNS="$2"; shift 2 ;;
            --iso)       VM_ISO="$2"; shift 2 ;;
            --no-start)  VM_START="0"; shift ;;
            --help|-h)   usage ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    if [ -z "$VM_NAME" ]; then
        log_error "VM name is required (--name)"
        echo "Use --help for usage information"
        exit 1
    fi
    
    # Validate type
    if [[ ! "$VM_TYPE" =~ ^(server|desktop)$ ]]; then
        log_error "Invalid VM type: $VM_TYPE (must be 'server' or 'desktop')"
        exit 1
    fi
    
    # Validate network
    if [[ ! "$VM_NET" =~ ^(bridged|nat)$ ]]; then
        log_error "Invalid network mode: $VM_NET (must be 'bridged' or 'nat')"
        exit 1
    fi
}

# ==============================================================================
# ISO Selection
# ==============================================================================
select_iso() {
    if [ -n "$VM_ISO" ] && [ -f "$VM_ISO" ]; then
        log_info "Using specified ISO: $VM_ISO"
        return
    fi
    
    local pattern
    if [ "$VM_TYPE" = "desktop" ]; then
        pattern="ubuntu-*-desktop-amd64.iso"
    else
        pattern="ubuntu-*-live-server-amd64.iso"
    fi
    
    # Find the latest matching ISO
    VM_ISO=$(find "$VBOX_ISOS" -maxdepth 1 -name "$pattern" -type f 2>/dev/null | sort -V | tail -1)
    
    if [ -z "$VM_ISO" ] || [ ! -f "$VM_ISO" ]; then
        log_error "No ISO found matching '$pattern' in $VBOX_ISOS"
        log_info "Download ISOs first: make iso-download"
        exit 1
    fi
    
    log_info "Selected ISO: $(basename "$VM_ISO")"
}

# ==============================================================================
# Static IP Configuration
# ==============================================================================
generate_netplan_config() {
    if [ -z "$VM_IP" ]; then
        return
    fi
    
    local iface="enp0s3"  # VirtualBox default interface name
    
    log_section "Static IP Configuration"
    log_info "After Ubuntu installation, apply this Netplan configuration:"
    
    cat <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Save to: /etc/netplan/01-static.yaml

network:
  version: 2
  renderer: networkd
  ethernets:
    ${iface}:
      dhcp4: false
      addresses:
        - ${VM_IP}/24
      routes:
        - to: default
          via: ${VM_GATEWAY}
      nameservers:
        addresses:
          - ${VM_DNS}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Apply commands:
  sudo tee /etc/netplan/01-static.yaml << 'NETPLAN'
network:
  version: 2
  renderer: networkd
  ethernets:
    ${iface}:
      dhcp4: false
      addresses:
        - ${VM_IP}/24
      routes:
        - to: default
          via: ${VM_GATEWAY}
      nameservers:
        addresses:
          - ${VM_DNS}
NETPLAN
  sudo netplan apply

EOF
}

# ==============================================================================
# VM Creation
# ==============================================================================
create_vm() {
    log_section "Creating VM: $VM_NAME"
    
    # Set VRAM based on type
    if [ "$VM_TYPE" = "desktop" ]; then
        VM_VRAM="${VM_VRAM:-${VBOX_DEFAULT_VRAM_DESKTOP:-128}}"
    else
        VM_VRAM="${VM_VRAM:-${VBOX_DEFAULT_VRAM_SERVER:-16}}"
    fi
    
    # Summary
    echo "Configuration:"
    echo "  Type:       $VM_TYPE"
    echo "  RAM:        ${VM_RAM} MB"
    echo "  CPUs:       $VM_CPUS"
    echo "  VRAM:       ${VM_VRAM} MB"
    echo "  Disk:       ${VM_DISK} MB ($(( VM_DISK / 1024 )) GB)"
    echo "  Network:    $VM_NET"
    echo "  EFI:        ${VBOX_DEFAULT_EFI:-on}"
    echo "  SecureBoot: ${VBOX_DEFAULT_SECUREBOOT:-on}"
    echo "  CPU Pass:   ${VBOX_DEFAULT_NESTED_HW_VIRT:-on}"
    [ -n "$VM_IP" ] && echo "  Static IP:  $VM_IP"
    echo ""
    
    # Check if VM already exists
    if vm_exists "$VM_NAME"; then
        log_error "VM '$VM_NAME' already exists"
        log_info "Delete it first: make vm-delete VM_NAME=$VM_NAME"
        exit 1
    fi
    
    # Create VM
    vbox_create "$VM_NAME" "${VBOX_DEFAULT_OSTYPE:-Ubuntu_64}"
    
    # Configure VM (pass type for VRAM selection)
    vbox_configure "$VM_NAME" "$VM_RAM" "$VM_CPUS" "$VM_VRAM" "$VM_TYPE"
    
    # Add storage controller
    vbox_add_sata "$VM_NAME"
    
    # Create and attach disk
    local disk_path
    disk_path=$(vbox_create_disk "$VM_NAME" "$VM_DISK")
    vbox_attach_disk "$VM_NAME" "$disk_path" 0
    
    # Attach ISO
    vbox_attach_iso "$VM_NAME" "$VM_ISO" 1
    
    # Configure network
    log_section "Network Configuration"
    if [ "$VM_NET" = "nat" ]; then
        vbox_network_nat "$VM_NAME" "$VM_SSH_PORT"
    else
        vbox_network_bridged "$VM_NAME" "$VM_IFACE"
    fi
    
    # Generate static IP instructions if requested
    generate_netplan_config
    
    # Start VM
    if [ "$VM_START" = "1" ]; then
        log_section "Starting VM"
        vbox_start "$VM_NAME" headless
        
        echo ""
        echo "Access instructions:"
        if [ "$VM_NET" = "bridged" ]; then
            echo "  1. Complete Ubuntu installation via VirtualBox GUI or console"
            echo "  2. VM will get an IP via DHCP on your LAN"
            echo "  3. After install, SSH to the assigned IP"
            [ -n "$VM_IP" ] && echo "  4. Apply the static IP configuration above"
        else
            echo "  1. Complete Ubuntu installation"
            echo "  2. SSH: ssh -p $VM_SSH_PORT user@localhost"
        fi
        echo ""
        echo "To open GUI: VBoxManage startvm \"$VM_NAME\" --type gui"
        echo "Or: make vm-start VM_NAME=$VM_NAME VM_GUI=1"
    else
        log_info "VM created but not started (--no-start)"
        echo "Start with: make vm-start VM_NAME=$VM_NAME"
    fi
    
    log_section "Done"
    log_success "VM '$VM_NAME' is ready"
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    require_vboxmanage
    parse_args "$@"
    select_iso
    create_vm
}

main "$@"
