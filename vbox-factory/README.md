# VBox Factory

Automated VirtualBox VM provisioning for Ubuntu Server/Desktop with bridged networking, static IP support, and automatic KVM conflict resolution.

## Quick Start

All VM operations are driven via the root **Makefile**:

```bash
# From the repo root

# 1. Download Ubuntu ISOs first
make iso-download

# 2. Create a desktop VM (default type)
make vm-create VM_NAME=test-desktop

# 3. Start the VM (auto-disables KVM if needed)
make vm-start VM_NAME=test-desktop

# 4. Start with GUI window
make vm-start VM_NAME=test-desktop VM_GUI=1

# 5. List running VMs
make vm-running

# 6. Stop the VM
make vm-stop VM_NAME=test-desktop
```

## Complete Usage Example

```bash
# Create a desktop VM with computed defaults (RAM/4, CPUs/4, 500GB disk)
$ make vm-create VM_NAME=test-desktop
[INFO] Selected ISO: ubuntu-24.04.3-desktop-amd64.iso

=== Creating VM: test-desktop ===

Configuration:
  Type:       desktop
  RAM:        28144 MB
  CPUs:       8
  VRAM:       128 MB
  Disk:       512000 MB (500 GB)
  Network:    bridged
  EFI:        on
  SecureBoot: on
  CPU Pass:   on

[OK] Created VM: test-desktop (ostype: Ubuntu_64)
[OK] Configured VM: test-desktop (RAM=28144MB, CPUs=8, VRAM=128MB)
[OK] Added SATA controller to test-desktop
[OK] Created disk: /home/user/vms/disks/test-desktop.vdi (512000MB / 500GB)
[OK] Attached disk to test-desktop on port 0
[OK] Attached ISO: ubuntu-24.04.3-desktop-amd64.iso
[OK] Configured bridged network on eno4

# Start the VM - automatically disables KVM if needed
$ make vm-start VM_NAME=test-desktop
[WARN] KVM modules are loaded - VirtualBox cannot run alongside KVM
[INFO] Automatically disabling KVM...
[INFO] Disabling KVM using virtualbox-sb-manager...
[OK] KVM disabled successfully
VM "test-desktop" has been successfully started.
[OK] Started test-desktop (headless mode)

# Check running VMs
$ make vm-running
"test-desktop" {e92fa134-a69b-44ec-9a38-664e1f992543}

# Restart with GUI to see the display
$ make vm-stop VM_NAME=test-desktop VM_FORCE=1
$ make vm-start VM_NAME=test-desktop VM_GUI=1
[OK] Started test-desktop (gui mode)
```

## Prerequisites

1. **VirtualBox installed** - The `dev-env-setup` can handle this:
   ```bash
   sudo make setup
   ```

2. **Ubuntu ISOs downloaded** - To `$HOME/vms/isos`:
   ```bash
   make iso-download
   ```

3. **virtualbox-sb-manager installed** (for automatic KVM handling):
   ```bash
   make build && sudo make install
   ```

## Automatic KVM Conflict Resolution

VirtualBox and KVM cannot run simultaneously. When you start a VM, the system automatically:

1. Detects if KVM modules are loaded
2. Uses `virtualbox-sb-manager kvm disable` to unload them
3. Starts the VM

```bash
$ make vm-start VM_NAME=test-desktop
[WARN] KVM modules are loaded - VirtualBox cannot run alongside KVM
[INFO] Automatically disabling KVM...
[INFO] Disabling KVM using virtualbox-sb-manager...
[OK] KVM disabled successfully
VM "test-desktop" has been successfully started.
```

To re-enable KVM after you're done with VirtualBox:
```bash
sudo virtualbox-sb-manager kvm enable
```

## VM Creation Options

```bash
make vm-create VM_NAME=<name> [OPTIONS]
```

| Variable | Default | Description |
|----------|---------|-------------|
| `VM_NAME` | (required) | Name of the VM |
| `VM_RAM` | host RAM / 4 | RAM in MB (auto-computed) |
| `VM_CPUS` | host CPUs / 4 | Number of CPUs (auto-computed) |
| `VM_DISK` | 512000 (500GB) | Disk size in MB |
| `VM_TYPE` | desktop | `server` or `desktop` |
| `VM_NET` | bridged | `bridged` or `nat` |
| `VM_IFACE` | auto-detect | Bridge interface (e.g., `eth0`, `eno4`) |
| `VM_IP` | (none) | Static IP - prints Netplan config |
| `VM_GATEWAY` | 192.168.50.1 | Gateway for static IP |
| `VM_DNS` | 8.8.8.8 | DNS server for static IP |
| `VM_ISO` | auto-select | Custom ISO path |
| `VM_SSH_PORT` | 2222 | SSH port (NAT mode only) |
| `VM_NO_START` | 0 | Set to `1` to skip auto-start |

### Default Configuration

Defaults are computed from your host system via `vbox-defaults.sh`:

```bash
$ ./vbox-factory/vbox-defaults.sh
--------------------------------------------------------------------
VBox Factory Defaults (computed from host system)
--------------------------------------------------------------------
  Host RAM:        112608 MB
  Host CPUs:       32

  VM RAM:          28144 MB (host/4, rounded to 16MB)
  VM CPUs:         8 (host/4, min 1)
  VM Disk:         512000 MB (500 GB)
  Server VRAM:     16 MB
  Desktop VRAM:    128 MB

  Network:         bridged
  Gateway:         192.168.50.1
  DNS:             8.8.8.8

  Secure Boot:     on
  EFI:             on
  Nested HW Virt:  on
--------------------------------------------------------------------
```

### Security Features (Enabled by Default)

- **EFI firmware** - Modern UEFI boot
- **Secure Boot** - EFI secure boot mode
- **CPU passthrough** - Nested VT-x/AMD-V for running VMs inside VMs
- **Hardware virtualization** - VT-x/AMD-V acceleration
- **PAE/NX** - Physical Address Extension

### Examples

```bash
# Basic desktop VM (uses computed defaults)
make vm-create VM_NAME=dev-desktop

# Server VM with static IP
make vm-create VM_NAME=web-server VM_TYPE=server VM_IP=192.168.50.100

# Custom specs
make vm-create VM_NAME=build-box VM_RAM=16384 VM_CPUS=8 VM_DISK=1024000

# Isolated VM using NAT (SSH via localhost:2222)
make vm-create VM_NAME=sandbox VM_NET=nat VM_SSH_PORT=2223

# Don't start automatically
make vm-create VM_NAME=template VM_NO_START=1
```

## VM Lifecycle

| Command | Description |
|---------|-------------|
| `make vm-list` | List all VMs |
| `make vm-running` | List running VMs |
| `make vm-start VM_NAME=x` | Start VM (headless, auto-disables KVM) |
| `make vm-start VM_NAME=x VM_GUI=1` | Start VM with GUI window |
| `make vm-stop VM_NAME=x` | Graceful shutdown (ACPI) |
| `make vm-stop VM_NAME=x VM_FORCE=1` | Force power off |
| `make vm-delete VM_NAME=x` | Delete VM and disk |
| `make vm-info VM_NAME=x` | Show VM details |
| `make vm-eject VM_NAME=x` | Eject ISO after install |

## Snapshots

```bash
# Take a snapshot
make vm-snapshot VM_NAME=dev-server SNAP_NAME=clean-install

# Restore a snapshot
make vm-restore VM_NAME=dev-server SNAP_NAME=clean-install
```

## Cloning

```bash
# Full clone (independent copy)
make vm-clone VM_TEMPLATE=ubuntu-base VM_NAME=worker-01

# Linked clone (faster, shares base disk - saves space)
make vm-clone VM_TEMPLATE=ubuntu-base VM_NAME=worker-02 VM_LINKED=1
```

## Static IP Configuration

When you specify `VM_IP`, the script prints a Netplan configuration to apply after Ubuntu installation:

```yaml
# /etc/netplan/01-static.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s3:
      dhcp4: false
      addresses:
        - 192.168.50.100/24
      routes:
        - to: default
          via: 192.168.50.1
      nameservers:
        addresses:
          - 8.8.8.8
```

Apply with:
```bash
sudo netplan apply
```

## Network Modes

### Bridged (Default)

- VM gets an IP on your LAN (via DHCP or static)
- Directly accessible from other machines on the network
- Best for servers that need to be reachable

### NAT

- VM is isolated behind NAT
- Access via port forwarding (SSH on localhost:2222 by default)
- Best for isolated development/testing

```bash
# Use NAT instead of bridged
make vm-create VM_NAME=isolated VM_NET=nat
```

## Troubleshooting

### KVM Conflict Error

If you see:
```
VBoxManage: error: VirtualBox can't operate in VMX root mode. 
Please disable the KVM kernel extension...
```

This is automatically handled when using `make vm-start`. If you need to manually fix:
```bash
sudo virtualbox-sb-manager kvm disable
```

### Orphaned Disk in VirtualBox Registry

If VM creation fails and leaves a registered disk:
```bash
# Check registered disks
VBoxManage list hdds | grep -A5 <vm-name>

# Remove from registry and delete file
VBoxManage closemedium disk /home/user/vms/disks/<vm-name>.vdi --delete
```

### VM Won't Start After Previous Failure

Clean up completely and recreate:
```bash
make vm-delete VM_NAME=<vm-name>
rm -f ~/vms/disks/<vm-name>.vdi
make vm-create VM_NAME=<vm-name>
```

## Directory Structure

```
vbox-factory/
|--- README.md           # This file
|--- plan.md             # Implementation plan and VBoxManage reference
|--- vbox-defaults.sh    # Computed defaults (RAM, CPUs, etc.)
|--- vbox-lib.sh         # Reusable function library
|--- create-vm.sh        # Main VM creation script
+--- start-vm.sh         # VM start with KVM handling
```

**Standard VM paths:**
```
$HOME/vms/
|--- disks/              # Virtual disk files (.vdi)
+--- isos/               # Ubuntu ISO files
```

## Direct Script Usage

You can also use the scripts directly:

```bash
# Show all options with current defaults
./vbox-factory/create-vm.sh --help

# Create VM directly
./vbox-factory/create-vm.sh --name myvm --ip 192.168.50.100

# Source the library in your own scripts
source ./vbox-factory/vbox-lib.sh
vbox_create "test-vm" "Ubuntu_64"
vbox_configure "test-vm" 4096 2
vbox_network_bridged "test-vm"
vbox_start "test-vm"  # Auto-handles KVM
```

## Quick Reference

| Action | Command |
|--------|---------|
| Download ISOs | `make iso-download` |
| Create desktop VM | `make vm-create VM_NAME=desk` |
| Create server VM | `make vm-create VM_NAME=srv VM_TYPE=server` |
| Create with static IP | `make vm-create VM_NAME=srv VM_IP=192.168.50.100` |
| Start headless | `make vm-start VM_NAME=srv` |
| Start with GUI | `make vm-start VM_NAME=srv VM_GUI=1` |
| Stop gracefully | `make vm-stop VM_NAME=srv` |
| Force stop | `make vm-stop VM_NAME=srv VM_FORCE=1` |
| Take snapshot | `make vm-snapshot VM_NAME=srv SNAP_NAME=clean` |
| Restore snapshot | `make vm-restore VM_NAME=srv SNAP_NAME=clean` |
| Clone VM | `make vm-clone VM_TEMPLATE=base VM_NAME=clone` |
| Linked clone | `make vm-clone VM_TEMPLATE=base VM_NAME=clone VM_LINKED=1` |
| Delete VM | `make vm-delete VM_NAME=srv` |
| Eject ISO | `make vm-eject VM_NAME=srv` |
| Show VM info | `make vm-info VM_NAME=srv` |
| List all VMs | `make vm-list` |
| List running | `make vm-running` |
| Disable KVM manually | `sudo virtualbox-sb-manager kvm disable` |
| Re-enable KVM | `sudo virtualbox-sb-manager kvm enable` |
