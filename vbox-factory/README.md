# VBox Factory

Automated VirtualBox VM provisioning for Ubuntu Server/Desktop with bridged networking and static IP support.

## Quick Start

All VM operations are driven via the root **Makefile**:

```bash
# From the repo root

# Create a server VM with static IP (bridged network is default)
make vm-create VM_NAME=dev-server VM_IP=192.168.1.50

# Create a desktop VM with more resources
make vm-create VM_NAME=desktop VM_TYPE=desktop VM_RAM=8192 VM_CPUS=4

# List all VMs
make vm-list

# Start/stop VMs
make vm-start VM_NAME=dev-server
make vm-stop VM_NAME=dev-server
```

## Prerequisites

1. **VirtualBox installed** — The `dev-env-setup` can handle this:
   ```bash
   sudo make setup
   ```

2. **Ubuntu ISOs downloaded** — To `$HOME/vms/isos`:
   ```bash
   make iso-download
   ```

## VM Creation Options

```bash
make vm-create VM_NAME=<name> [OPTIONS]
```

| Variable | Default | Description |
|----------|---------|-------------|
| `VM_NAME` | (required) | Name of the VM |
| `VM_RAM` | 4096 | RAM in MB |
| `VM_CPUS` | 2 | Number of CPUs |
| `VM_DISK` | 51200 | Disk size in MB |
| `VM_TYPE` | server | `server` or `desktop` (affects ISO selection) |
| `VM_NET` | bridged | `bridged` or `nat` |
| `VM_IFACE` | auto-detect | Bridge interface (e.g., `eth0`, `enp0s3`) |
| `VM_IP` | (none) | Static IP — prints Netplan config |
| `VM_GATEWAY` | 192.168.1.1 | Gateway for static IP |
| `VM_DNS` | 8.8.8.8 | DNS server for static IP |
| `VM_ISO` | auto-select | Custom ISO path |
| `VM_SSH_PORT` | 2222 | SSH port (NAT mode only) |
| `VM_NO_START` | 0 | Set to `1` to skip auto-start |

### Examples

```bash
# Basic server VM (gets DHCP IP on LAN via bridged network)
make vm-create VM_NAME=web-server

# Server with static IP
make vm-create VM_NAME=db-server VM_IP=192.168.1.100 VM_RAM=8192

# Desktop VM with GUI-ready specs
make vm-create VM_NAME=dev-desktop VM_TYPE=desktop VM_RAM=8192 VM_CPUS=4 VM_DISK=102400

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
| `make vm-start VM_NAME=x` | Start VM (headless) |
| `make vm-start VM_NAME=x VM_GUI=1` | Start VM with GUI |
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

# Linked clone (faster, shares base disk — saves space)
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
        - 192.168.1.50/24
      routes:
        - to: default
          via: 192.168.1.1
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

## Directory Structure

```
vbox-factory/
├── README.md           # This file
├── plan.md             # Implementation plan and VBoxManage reference
├── vbox-lib.sh         # Reusable function library
└── create-vm.sh        # Main VM creation script
```

**Standard VM paths:**
```
$HOME/vms/
├── disks/              # Virtual disk files (.vdi)
└── isos/               # Ubuntu ISO files
```

## Direct Script Usage

You can also use the scripts directly:

```bash
# Show all options
./vbox-factory/create-vm.sh --help

# Create VM directly
./vbox-factory/create-vm.sh --name myvm --ram 4096 --cpus 2 --ip 192.168.1.50

# Source the library in your own scripts
source ./vbox-factory/vbox-lib.sh
vbox_create "test-vm" "Ubuntu_64"
vbox_configure "test-vm" 4096 2
vbox_network_bridged "test-vm"
```

## Quick Reference

| Action | Command |
|--------|---------|
| Download ISOs | `make iso-download` |
| Create server VM | `make vm-create VM_NAME=srv VM_IP=192.168.1.50` |
| Create desktop VM | `make vm-create VM_NAME=desk VM_TYPE=desktop` |
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
