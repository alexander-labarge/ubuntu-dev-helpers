# VBox SSH Manager

Interactive SSH key generation and remote enrollment for VirtualBox VMs.

## Quick Start

```bash
# 1. Generate a new SSH key
./ssh-gen.sh

# 2. Enroll the key on a remote VM
./ssh-remote-enroll.sh
```

## Scripts

### config.sh

Central configuration file with all defaults. Can be:
- **Sourced** by other scripts to inherit configuration
- **Run directly** for interactive configuration

```bash
# Run interactive configuration
./config.sh

# Source in your own scripts
source ./config.sh
```

### ssh-gen.sh

Interactive SSH key generation with sensible defaults.

**Features:**
- Supports ed25519 (recommended), RSA, and ECDSA key types
- Optional passphrase protection
- Automatic SSH agent integration
- Proper permission setting (600 for private, 644 for public)

```bash
./ssh-gen.sh
```

### ssh-remote-enroll.sh

Enroll your SSH public key on a remote host.

**Features:**
- Uses `ssh-copy-id` when available (with manual fallback)
- Automatic backup of remote `authorized_keys`
- Adds entry to `~/.ssh/config` for easy access
- Optional hostname setting on remote
- Optional password authentication disable (with safety checks)

```bash
./ssh-remote-enroll.sh
```

## Configuration Variables

### SSH Target

| Variable | Default | Description |
|----------|---------|-------------|
| `TARGET_IP` | 192.168.50.89 | Remote host IP or hostname |
| `TARGET_SSH_PORT` | 22 | SSH port |
| `TARGET_SSH_USER` | skywalker | Remote username |
| `TARGET_HOSTNAME` | (empty) | Set hostname on remote |
| `SSH_CONFIG_ALIAS` | (auto) | Alias for ~/.ssh/config |

### SSH Key Generation

| Variable | Default | Description |
|----------|---------|-------------|
| `SSH_KEY_DIR` | ~/.ssh | Directory for keys |
| `SSH_KEY_NAME` | id_rsa | Key filename |
| `SSH_KEY_TYPE` | ed25519 | Key type (ed25519, rsa, ecdsa) |
| `SSH_KEY_BITS` | 4096 | RSA key bits |
| `SSH_KEY_COMMENT` | user@hostname | Key comment |

### Enrollment Options

| Variable | Default | Description |
|----------|---------|-------------|
| `ENROLL_COPY_ID` | true | Use ssh-copy-id |
| `ENROLL_BACKUP_AUTHORIZED_KEYS` | true | Backup before modifying |
| `ENROLL_TEST_CONNECTION` | true | Test after enrollment |
| `ENROLL_ADD_TO_SSH_CONFIG` | true | Add ~/.ssh/config entry |
| `ENROLL_DISABLE_PASSWORD_AUTH` | false | Disable password auth (dangerous!) |

## Workflow Example

```bash
# Step 1: Create a VM with vbox-factory
make vm-create VM_NAME=dev-server VM_GUI=1

# Step 2: Install Ubuntu, get the IP (e.g., via DHCP)

# Step 3: Generate SSH key (if you don't have one)
cd vbox-ssh-manager
./ssh-gen.sh

# Step 4: Enroll the key on the VM
./ssh-remote-enroll.sh
# - Enter the VM's IP when prompted
# - Enter password when prompted for enrollment

# Step 5: Connect!
ssh dev-server-vm    # Uses the SSH config alias
```

## Environment Overrides

Override defaults via environment variables:

```bash
TARGET_IP=192.168.1.100 TARGET_SSH_USER=admin ./ssh-remote-enroll.sh
```

Or export before running:

```bash
export TARGET_IP=192.168.1.100
export TARGET_SSH_USER=admin
./ssh-remote-enroll.sh
```
