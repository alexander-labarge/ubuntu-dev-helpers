Yes, VBoxManage is quite powerful for scripting VM creation. Here are some practical patterns:

## Basic VM Creation Template

```bash
#!/bin/bash

VM_NAME="ubuntu-server-01"
ISO_PATH="$HOME/vms/isos/ubuntu-24.04.3-live-server-amd64.iso"
VDI_PATH="$HOME/vms/disks/${VM_NAME}.vdi"
RAM_MB=4096
CPUS=2
DISK_SIZE_MB=51200
VRAM_MB=16

# Create the VM
VBoxManage createvm --name "$VM_NAME" --ostype Ubuntu_64 --register

# Configure system settings
VBoxManage modifyvm "$VM_NAME" \
    --memory "$RAM_MB" \
    --cpus "$CPUS" \
    --vram "$VRAM_MB" \
    --graphicscontroller vmsvga \
    --acpi on \
    --ioapic on \
    --boot1 dvd \
    --boot2 disk \
    --boot3 none \
    --boot4 none

# Network (NAT with port forwarding for SSH)
VBoxManage modifyvm "$VM_NAME" \
    --nic1 nat \
    --natpf1 "ssh,tcp,,2222,,22"

# Create and attach storage controller
VBoxManage storagectl "$VM_NAME" \
    --name "SATA Controller" \
    --add sata \
    --controller IntelAhci \
    --portcount 2

# Create virtual disk
mkdir -p "$(dirname "$VDI_PATH")"
VBoxManage createmedium disk \
    --filename "$VDI_PATH" \
    --size "$DISK_SIZE_MB" \
    --format VDI

# Attach disk and ISO
VBoxManage storageattach "$VM_NAME" \
    --storagectl "SATA Controller" \
    --port 0 \
    --device 0 \
    --type hdd \
    --medium "$VDI_PATH"

VBoxManage storageattach "$VM_NAME" \
    --storagectl "SATA Controller" \
    --port 1 \
    --device 0 \
    --type dvddrive \
    --medium "$ISO_PATH"

# Start the VM (headless for servers)
VBoxManage startvm "$VM_NAME" --type headless
```

## Reusable Function Library

```bash
#!/bin/bash
# vbox-lib.sh - Source this in your scripts

VBOX_BASE="$HOME/vms"
VBOX_DISKS="$VBOX_BASE/disks"
VBOX_ISOS="$VBOX_BASE/isos"

vbox_create() {
    local name="$1"
    local ostype="${2:-Ubuntu_64}"
    
    VBoxManage createvm --name "$name" --ostype "$ostype" --register
    echo "Created VM: $name"
}

vbox_configure() {
    local name="$1"
    local ram="${2:-2048}"
    local cpus="${3:-2}"
    
    VBoxManage modifyvm "$name" \
        --memory "$ram" \
        --cpus "$cpus" \
        --vram 16 \
        --graphicscontroller vmsvga \
        --acpi on \
        --ioapic on \
        --rtcuseutc on \
        --nested-hw-virt on
}

vbox_add_sata() {
    local name="$1"
    
    VBoxManage storagectl "$name" \
        --name "SATA" \
        --add sata \
        --controller IntelAhci \
        --portcount 4 \
        --bootable on
}

vbox_create_disk() {
    local name="$1"
    local size_mb="${2:-51200}"
    local disk_path="${VBOX_DISKS}/${name}.vdi"
    
    mkdir -p "$VBOX_DISKS"
    VBoxManage createmedium disk \
        --filename "$disk_path" \
        --size "$size_mb" \
        --format VDI \
        --variant Standard
    
    echo "$disk_path"
}

vbox_attach_disk() {
    local name="$1"
    local disk_path="$2"
    local port="${3:-0}"
    
    VBoxManage storageattach "$name" \
        --storagectl "SATA" \
        --port "$port" \
        --device 0 \
        --type hdd \
        --medium "$disk_path"
}

vbox_attach_iso() {
    local name="$1"
    local iso_path="$2"
    local port="${3:-1}"
    
    VBoxManage storageattach "$name" \
        --storagectl "SATA" \
        --port "$port" \
        --device 0 \
        --type dvddrive \
        --medium "$iso_path"
}

vbox_eject_iso() {
    local name="$1"
    local port="${2:-1}"
    
    VBoxManage storageattach "$name" \
        --storagectl "SATA" \
        --port "$port" \
        --device 0 \
        --type dvddrive \
        --medium emptydrive
}

vbox_network_nat() {
    local name="$1"
    local ssh_port="${2:-2222}"
    
    VBoxManage modifyvm "$name" \
        --nic1 nat \
        --nat-network1 "NatNetwork" \
        --natpf1 "ssh,tcp,,${ssh_port},,22"
}

vbox_network_bridge() {
    local name="$1"
    local iface="${2:-eth0}"
    
    VBoxManage modifyvm "$name" \
        --nic1 bridged \
        --bridgeadapter1 "$iface"
}

vbox_start() {
    local name="$1"
    local type="${2:-headless}"  # headless, gui, sdl
    
    VBoxManage startvm "$name" --type "$type"
}

vbox_stop() {
    local name="$1"
    local method="${2:-acpipowerbutton}"  # acpipowerbutton, poweroff, savestate
    
    VBoxManage controlvm "$name" "$method"
}

vbox_delete() {
    local name="$1"
    
    VBoxManage unregistervm "$name" --delete
}

vbox_snapshot() {
    local name="$1"
    local snap_name="$2"
    
    VBoxManage snapshot "$name" take "$snap_name"
}

vbox_restore_snapshot() {
    local name="$1"
    local snap_name="$2"
    
    VBoxManage snapshot "$name" restore "$snap_name"
}

vbox_list_running() {
    VBoxManage list runningvms
}

vbox_list_all() {
    VBoxManage list vms
}

vbox_info() {
    local name="$1"
    VBoxManage showvminfo "$name"
}
```

## Usage Example

```bash
#!/bin/bash
source ./vbox-lib.sh

VM="test-server"

vbox_create "$VM" "Ubuntu_64"
vbox_configure "$VM" 4096 2
vbox_add_sata "$VM"

DISK=$(vbox_create_disk "$VM" 40960)
vbox_attach_disk "$VM" "$DISK" 0
vbox_attach_iso "$VM" "$VBOX_ISOS/ubuntu-24.04.3-live-server-amd64.iso" 1

vbox_network_nat "$VM" 2222
vbox_start "$VM" headless

echo "SSH available at: ssh -p 2222 user@localhost"
```

## Clone from Template

```bash
#!/bin/bash

TEMPLATE="ubuntu-template"
NEW_VM="$1"

if [ -z "$NEW_VM" ]; then
    echo "Usage: $0 <new-vm-name>"
    exit 1
fi

# Full clone (independent copy)
VBoxManage clonevm "$TEMPLATE" \
    --name "$NEW_VM" \
    --register \
    --mode all

# Or linked clone (faster, shares base disk)
# VBoxManage clonevm "$TEMPLATE" \
#     --name "$NEW_VM" \
#     --register \
#     --options link

VBoxManage startvm "$NEW_VM" --type headless
```

The linked clone approach is particularly useful when you want to spin up multiple VMs quickly from a base template - it saves disk space and creation time since it only stores the delta from the base image.