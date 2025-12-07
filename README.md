# Development Server Helpers

**Author:** Alexander La Barge  
**Date:** December 7, 2025  
**Contact:** alex@labarge.dev  
**Version:** 0.1.0-beta

A comprehensive collection of tools for setting up and managing Ubuntu/Debian-based development environments, with special focus on VirtualBox Secure Boot integration.

## Table of Contents

- [Quick Start](#quick-start)
- [Project Structure](#project-structure)
- [Development Environment Setup](#development-environment-setup)
  - [Full Setup with dev-server-setup.sh](#full-setup-with-dev-server-setupsh)
  - [Installation Options](#installation-options)
  - [What Gets Installed](#what-gets-installed)
- [VirtualBox Secure Boot Manager](#virtualbox-secure-boot-manager)
  - [Why This Component Exists](#why-this-component-exists)
  - [Rust Binary Usage](#rust-binary-usage)
  - [Shell Scripts Alternative](#shell-scripts-alternative)
  - [Systemd Service Installation](#systemd-service-installation)
- [Makefile Targets](#makefile-targets)
- [Command Reference](#command-reference)
- [Initial Setup Workflow](#initial-setup-workflow)
- [After Kernel Updates](#after-kernel-updates)
- [Understanding the Two Passwords](#understanding-the-two-passwords)
- [Troubleshooting](#troubleshooting)
- [Security Considerations](#security-considerations)
- [File Locations](#file-locations)
- [References](#references)
- [Contributing](#contributing)
- [License](#license)

## Quick Start

**Automated Full Setup (Recommended):**
```bash
# Clone the repository
git clone https://github.com/alexander-labarge/ubuntu-dev-helpers.git
cd ubuntu-dev-helpers

# Run full development environment setup (using Makefile)
sudo make setup

# Or with Secure Boot configuration for VirtualBox
sudo make setup-secureboot

# Or run the script directly
sudo ./dev-env-setup/dev-server-setup.sh
sudo ./dev-env-setup/dev-server-setup.sh --secureboot
```

**Modular Installation:**
```bash
# Using Makefile
sudo make docker      # Docker & Docker Compose
sudo make langs       # Rust, Go, Java
sudo make packages    # Essential dev packages

# Or run script directly
sudo ./dev-env-setup/dev-server-setup.sh --docker-only
sudo ./dev-env-setup/dev-server-setup.sh --langs-only
sudo ./dev-env-setup/dev-server-setup.sh --vscode-only
```

**Build VirtualBox Secure Boot Manager:**
```bash
# Using Makefile (recommended)
make build install

# Or build directly
cd vbox-sb-manager
cargo build --release
sudo cp target/release/virtualbox-sb-manager /usr/local/bin/
```

## Project Structure

```
ubuntu-dev-helpers/
├── Makefile                    # Main build/install targets
├── README.md                   # This file
├── .gitignore                  # Git ignore rules
│
├── dev-env-setup/              # Development environment setup
│   ├── dev-server-setup.sh     # Main setup script
│   ├── INSTALLATION.md         # Installation guide
│   └── README.md               # Component documentation
│
├── iso-manager/                # ISO download utilities
│   ├── download_ubuntu_24.04.3.sh  # Ubuntu ISO downloader
│   └── README.md               # Component documentation
│
└── vbox-sb-manager/            # VirtualBox Secure Boot Manager
    ├── Cargo.toml              # Rust project manifest
    ├── Cargo.lock              # Dependency lock file
    ├── src/                    # Rust source code
    ├── tests/                  # Integration tests
    ├── systemd/                # Systemd service files
    ├── examples/               # Usage examples
    ├── sign-vbox-modules.sh    # Shell script version
    ├── disable-kvm.sh          # KVM management script
    ├── ARCHITECTURE.md         # Technical architecture
    ├── PASSWORD-GUIDE.md       # Password management
    ├── MIGRATION.md            # Migration guide
    └── README.md               # Component documentation
```

## Development Environment Setup

### Full Setup with dev-server-setup.sh

The `dev-server-setup.sh` script is the **main entry point** for setting up a complete Ubuntu/Debian development environment. It automates the installation and configuration of all essential development tools, languages, and utilities.

**Features:**
- ✅ Automated APT configuration and system updates
- ✅ Docker Engine + Docker Compose installation
- ✅ Apptainer (Singularity) container runtime
- ✅ Programming languages (Rust, Go, Java, Python)
- ✅ Development tools (VS Code, Chrome, Git, etc.)
- ✅ VirtualBox with Secure Boot support
- ✅ System monitoring tools (btop, htop, neofetch)
- ✅ User group configuration (docker, vboxusers)
- ✅ Environment variable setup for all languages

### Installation Options

```bash
# Using Makefile (recommended)
sudo make setup                  # Full development environment setup
sudo make setup-secureboot       # Full setup with VirtualBox Secure Boot configuration
sudo make docker                 # Docker & Docker Compose only
sudo make langs                  # Rust + Go + Java
sudo make packages               # Essential packages only

# Or run script directly from dev-env-setup directory
sudo ./dev-env-setup/dev-server-setup.sh
sudo ./dev-env-setup/dev-server-setup.sh --secureboot

# Component-specific installations
sudo ./dev-env-setup/dev-server-setup.sh --docker-only          # Docker & Docker Compose
sudo ./dev-env-setup/dev-server-setup.sh --apptainer-only       # Apptainer only
sudo ./dev-env-setup/dev-server-setup.sh --packages-only        # Essential packages
sudo ./dev-env-setup/dev-server-setup.sh --vscode-only          # VS Code
sudo ./dev-env-setup/dev-server-setup.sh --chrome-only          # Google Chrome
sudo ./dev-env-setup/dev-server-setup.sh --rust-only            # Rust via rustup
sudo ./dev-env-setup/dev-server-setup.sh --go-only              # Go language
sudo ./dev-env-setup/dev-server-setup.sh --java-only            # Java (OpenJDK)
sudo ./dev-env-setup/dev-server-setup.sh --langs-only           # Rust + Go + Java
sudo ./dev-env-setup/dev-server-setup.sh --vbox-sb-manager-only # VBox Secure Boot Manager

# Display help
./dev-env-setup/dev-server-setup.sh --help
```

### What Gets Installed

**Container Platforms:**
- Docker Engine (latest stable)
- Docker Compose V2
- Apptainer (formerly Singularity)
- Container networking tools

**Programming Languages:**
- **Rust:** via rustup (stable toolchain with rustfmt and clippy)
- **Go:** Latest stable release (system-wide)
- **Java:** OpenJDK 17 & 21 with Maven and Gradle
- **Python 3:** Full installation with pip, venv, and dev headers

**Development Tools:**
- Visual Studio Code (latest stable)
- Google Chrome (stable channel)
- Git with Git LFS
- Build essentials (gcc, g++, make, cmake, gdb)
- Text editors (vim, neovim, nano)

**VirtualBox Components:**
- VirtualBox (latest from Ubuntu repos)
- VirtualBox Extension Pack
- VirtualBox Guest Additions
- VirtualBox DKMS modules
- Secure Boot signing tools (mokutil, sbsigntool, openssl)
- **VirtualBox Secure Boot Manager** (Rust binary)

**System Monitoring & Utilities:**
- btop, htop, iotop, iftop
- neofetch
- tmux, screen
- tree, jq, ripgrep, fd-find, bat
- curl, wget, net-tools
- Archive tools (zip, tar, gzip)

**Post-Installation:**
After running the script:
1. Log out and back in (or run `newgrp docker && newgrp vboxusers`)
2. Environment variables are configured in `/etc/profile.d/`
3. All tools are ready to use immediately

## VirtualBox Secure Boot Manager

The VirtualBox Secure Boot Manager is a specialized component of this toolkit that solves the VirtualBox + UEFI Secure Boot integration challenge.

### Why This Component Exists

##### The Problem: VirtualBox + Secure Boot = Manual Intervention

VirtualBox requires kernel modules (`vboxdrv`, `vboxnetadp`, `vboxnetflt`, `vboxpci`) to function. On Linux systems with **UEFI Secure Boot enabled**, the kernel will only load modules that are **cryptographically signed** with a key enrolled in the system's MOK (Machine Owner Key) database.

**Why Ubuntu and Linux distributions don't automatically handle this:**

1. **Security by Design**: Secure Boot is designed to prevent unsigned code from running at the kernel level. This is a security feature, not a bug. Distributions cannot pre-sign third-party kernel modules like VirtualBox because:
   - They would need to distribute private keys (a security disaster)
   - Each user needs their own unique key pair for proper security
   - Signing modules with a universal key would defeat Secure Boot's purpose

2. **VirtualBox's Dynamic Kernel Modules**: VirtualBox uses DKMS (Dynamic Kernel Module Support) to build modules for each kernel version. When Ubuntu installs a new kernel:
   - DKMS rebuilds the VirtualBox modules
   - The rebuilt modules are **unsigned**
   - Secure Boot rejects these unsigned modules
   - VirtualBox fails to start with cryptic errors

3. **No Standard Automation**: While the VirtualBox documentation mentions this requirement (see [VirtualBox Manual - Secure Boot](https://www.virtualbox.org/manual/ch02.html#secureboot)), it doesn't provide automated tooling. Users are left to:
   - Manually create key pairs
   - Manually enroll MOK keys
   - Manually sign modules after every kernel update
   - Navigate mokutil's confusing UI during boot

4. **Distribution-Specific Quirks**: Different distributions handle kernel module signing differently, making universal solutions difficult. Ubuntu's specific implementation requires specific paths and tools.

#### The Solution: Automated Signing with Your Own Keys

The VirtualBox Secure Boot Manager component provides:
- **Automated key generation and MOK enrollment** (one-time setup)
- **Automatic module signing** after kernel updates (via systemd service or manual command)
- **Clear, helpful error messages** when something goes wrong
- **Support for both interactive and automated workflows**

By automating the signing process with your own securely-stored keys, you maintain Secure Boot's security benefits while eliminating the manual toil of re-signing modules after every kernel update.

**Key Features:**
- Production-ready Rust binary with comprehensive error handling
- Battle-tested shell scripts for those who prefer bash
- Systemd service integration for unattended kernel upgrades
- Interactive and CLI modes for flexibility
- Works with pre-existing MOK (Machine Owner Key) database keys

### Rust Binary Usage

The Rust version (`virtualbox-sb-manager`) is the **recommended** implementation, offering better error handling, type safety, and a modern CLI experience.

#### Automatic Installation via dev-server-setup.sh

The easiest way to get the VirtualBox Secure Boot Manager is through the main setup script:

```bash
# Using Makefile (recommended)
sudo make setup                     # Full setup including VirtualBox Secure Boot Manager
sudo make vbox-manager              # Install only the Secure Boot Manager (includes Rust if needed)
sudo make setup-secureboot          # Full setup with Secure Boot configuration

# Or run script directly
sudo ./dev-env-setup/dev-server-setup.sh
sudo ./dev-env-setup/dev-server-setup.sh --vbox-sb-manager-only
sudo ./dev-env-setup/dev-server-setup.sh --secureboot
```

The script will:
1. Install Rust (if not already installed)
2. Build the `virtualbox-sb-manager` binary from source in `vbox-sb-manager/` directory
3. Install it to `/usr/local/bin/`
4. Make it available system-wide

#### Manual Build and Installation

If you prefer to build manually:

**Prerequisites:**
```bash
# Install required packages (if not using dev-server-setup.sh)
sudo apt update
sudo apt install -y virtualbox dkms mokutil openssl linux-headers-$(uname -r)

# Install Rust (if not already installed)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

**Build from Source:**
```bash
# Navigate to vbox-sb-manager directory
cd vbox-sb-manager

# Build the release version (optimized)
cargo build --release

# The binary will be located at:
# vbox-sb-manager/target/release/virtualbox-sb-manager
```

**Installation:**
```bash
# Using Makefile (from project root - recommended)
make build install

# Or manually
sudo cp vbox-sb-manager/target/release/virtualbox-sb-manager /usr/local/bin/

# Verify installation
virtualbox-sb-manager --version
# Output: virtualbox-sb-manager 0.1.0-beta

# Check help
virtualbox-sb-manager --help
```

**Build time:** ~55 seconds on modern hardware (clean build)  
**Binary size:** ~8 MB (stripped, optimized)

#### Usage Examples

#### Interactive Mode (Recommended for First-Time Users)

```bash
# Launch interactive menu
sudo virtualbox-sb-manager
# or explicitly:
sudo virtualbox-sb-manager interactive
```

The interactive menu provides:
- Step-by-step guidance
- Status checks before operations
- Clear error messages with recovery suggestions

#### Command-Line Mode (For Automation)

```bash
# Initial setup (create keys and enroll MOK)
sudo virtualbox-sb-manager setup

# After reboot and MOK enrollment:
sudo virtualbox-sb-manager sign      # Sign modules
sudo virtualbox-sb-manager verify    # Verify signatures
sudo virtualbox-sb-manager load      # Load modules

# Or do it all in one command:
sudo virtualbox-sb-manager full      # rebuild + sign + verify + load
```

#### KVM Management (VirtualBox and KVM Conflict)

```bash
# Check KVM status
sudo virtualbox-sb-manager kvm status

# Disable KVM temporarily (until reboot)
sudo virtualbox-sb-manager kvm disable

# Disable KVM permanently
sudo virtualbox-sb-manager kvm disable --permanent

# Re-enable KVM
sudo virtualbox-sb-manager kvm enable
```

#### Verbose Logging

```bash
# Enable verbose output
sudo virtualbox-sb-manager --verbose status

# Enable debug output
sudo virtualbox-sb-manager --debug full
```

### Shell Scripts Alternative

For users who prefer shell scripts, the original bash implementation is included in the `vbox-sb-manager/` directory:

```bash
# Navigate to vbox-sb-manager directory
cd vbox-sb-manager

# Interactive mode
sudo ./sign-vbox-modules.sh

# Command-line mode
sudo ./sign-vbox-modules.sh --setup
sudo ./sign-vbox-modules.sh --sign
sudo ./sign-vbox-modules.sh --load
sudo ./sign-vbox-modules.sh --full

# KVM management
sudo ./disable-kvm.sh --status
sudo ./disable-kvm.sh --disable
sudo ./disable-kvm.sh --enable
```

**Note:** Both the Rust binary and shell scripts use the same key locations and are fully compatible. You can switch between them at any time.

### Systemd Service Installation

Systemd services enable **automatic module signing after kernel updates**, allowing for truly unattended upgrades without breaking VirtualBox.

#### For Rust Binary

```bash
# Copy the service file from vbox-sb-manager directory
sudo cp vbox-sb-manager/systemd/virtualbox-sb-manager.service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable the service (start on boot)
sudo systemctl enable virtualbox-sb-manager.service

# Start the service now
sudo systemctl start virtualbox-sb-manager.service

# Check status
sudo systemctl status virtualbox-sb-manager.service

# View logs
sudo journalctl -u virtualbox-sb-manager.service -f
```

#### For Shell Scripts

```bash
# Copy the scripts to a permanent location
sudo mkdir -p /opt/virtualbox-sb-sign
sudo cp vbox-sb-manager/sign-vbox-modules.sh /opt/virtualbox-sb-sign/
sudo chmod +x /opt/virtualbox-sb-sign/sign-vbox-modules.sh

# Copy the service file
sudo cp vbox-sb-manager/systemd/vbox-sign-modules.service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable the service
sudo systemctl enable vbox-sign-modules.service

# Start the service
sudo systemctl start vbox-sign-modules.service

# Check status
sudo systemctl status vbox-sign-modules.service
```

### Unattended Kernel Upgrades

With the systemd service enabled, the workflow becomes:

1. **Ubuntu installs a kernel update** (via apt upgrade or automatic updates)
2. **DKMS automatically rebuilds** VirtualBox modules for the new kernel
3. **Systemd service triggers** after module rebuild
4. **Modules are automatically signed** using your pre-existing key in the MOK database
5. **Modules are loaded** and VirtualBox is ready to use
6. **No manual intervention required**

**Important Notes:**

- The service requires your signing key passphrase. For true unattended operation, you have two options:
  1. **Use a kernel hook** (APT post-invoke) to run signing during package installation
  2. **Store the passphrase in an environment variable** (reduces security)

Example APT hook (`/etc/apt/apt.conf.d/99-vbox-sign`):

```
DPkg::Post-Invoke {
    "if [ -x /usr/local/bin/virtualbox-sb-manager ]; then /usr/local/bin/virtualbox-sb-manager full; fi";
};
```

This runs the signing command after every package installation, including kernel updates.

## Makefile Targets

The project includes a Makefile for convenient access to common operations:

### Main Setup Targets

| Target | Description | Example |
|--------|-------------|---------|
| `help` | Display all available targets | `make help` |
| `setup` | Full development environment setup | `sudo make setup` |
| `setup-secureboot` | Full setup with Secure Boot configuration | `sudo make setup-secureboot` |

### Component-Specific Targets

| Target | Description | Example |
|--------|-------------|---------|
| `dev-env` | Run development environment setup | `sudo make dev-env` |
| `docker` | Install Docker and Docker Compose only | `sudo make docker` |
| `langs` | Install programming languages (Rust, Go, Java) | `sudo make langs` |
| `packages` | Install essential packages only | `sudo make packages` |
| `vbox-manager` | Build and install VirtualBox Secure Boot Manager | `sudo make vbox-manager` |

### VirtualBox Secure Boot Manager Targets

| Target | Description | Example |
|--------|-------------|---------|
| `build` | Build the Rust binary | `make build` |
| `install` | Install the built binary to /usr/local/bin | `sudo make install` |
| `test` | Run integration tests | `make test` |
| `vbox-setup` | Setup VirtualBox Secure Boot (interactive) | `sudo make vbox-setup` |
| `clean` | Remove build artifacts | `make clean` |

### Usage Examples

```bash
# Full development environment
sudo make setup

# Install only Docker
sudo make docker

# Build and install VirtualBox Secure Boot Manager
make build
sudo make install

# Run tests
make test

# Clean build artifacts
make clean
```

## Command Reference

### Rust Binary Commands

| Command | Description | Example |
|---------|-------------|---------|
| `setup` | Create signing keys and enroll MOK | `sudo virtualbox-sb-manager setup` |
| `sign` | Sign VirtualBox kernel modules | `sudo virtualbox-sb-manager sign` |
| `verify` | Verify module signatures | `sudo virtualbox-sb-manager verify` |
| `load` | Load VirtualBox kernel modules | `sudo virtualbox-sb-manager load` |
| `rebuild` | Rebuild modules via DKMS | `sudo virtualbox-sb-manager rebuild` |
| `full` | Rebuild + sign + verify + load | `sudo virtualbox-sb-manager full` |
| `kvm disable` | Disable KVM (temporary or permanent) | `sudo virtualbox-sb-manager kvm disable --permanent` |
| `kvm enable` | Re-enable KVM | `sudo virtualbox-sb-manager kvm enable` |
| `kvm status` | Check KVM status | `sudo virtualbox-sb-manager kvm status` |
| `status` | Show system status | `sudo virtualbox-sb-manager status` |
| `interactive` | Launch interactive menu | `sudo virtualbox-sb-manager interactive` |
| `--help` | Show help | `virtualbox-sb-manager --help` |
| `--version` | Show version | `virtualbox-sb-manager --version` |
| `--verbose` | Enable verbose logging | `sudo virtualbox-sb-manager --verbose status` |
| `--debug` | Enable debug logging | `sudo virtualbox-sb-manager --debug full` |

### Shell Script Options

| Option | Description | Example |
|--------|-------------|---------|
| `--setup` | Create signing keys and enroll MOK | `sudo ./sign-vbox-modules.sh --setup` |
| `--sign` | Sign VirtualBox modules | `sudo ./sign-vbox-modules.sh --sign` |
| `--verify` | Verify module signatures | `sudo ./sign-vbox-modules.sh --verify` |
| `--load` | Load modules | `sudo ./sign-vbox-modules.sh --load` |
| `--rebuild` | Rebuild modules via DKMS | `sudo ./sign-vbox-modules.sh --rebuild` |
| `--full` | Rebuild + sign + verify + load | `sudo ./sign-vbox-modules.sh --full` |
| `--help` | Show help | `./sign-vbox-modules.sh --help` |
| *(no option)* | Launch interactive menu | `sudo ./sign-vbox-modules.sh` |

## Initial Setup Workflow

This is a **one-time process** required before first use:

### Step 1: Run Setup

```bash
sudo virtualbox-sb-manager setup
```

This will:
1. Create an RSA key pair in `/root/module-signing/`
2. Prompt for **Signing Key Passphrase** (entered twice via OpenSSL)
3. Prompt for **Temporary MOK Password** (entered twice via mokutil)
4. Initiate MOK enrollment with mokutil

### Step 2: Reboot and Enroll MOK

```bash
sudo reboot
```

During boot, the MOK Manager (blue screen) will appear:
1. Select **"Enroll MOK"**
2. Select **"Continue"**
3. Select **"Yes"** to confirm
4. Enter the **temporary MOK password** (from Step 1)
5. Select **"OK"** to reboot

### Step 3: Sign and Load Modules

After the system reboots:

```bash
# Sign the modules
sudo virtualbox-sb-manager sign

# Verify signatures (optional)
sudo virtualbox-sb-manager verify

# Load the modules
sudo virtualbox-sb-manager load
```

Or do it all at once:

```bash
sudo virtualbox-sb-manager full
```

### Step 4: Verify VirtualBox Works

```bash
# Check if modules are loaded
lsmod | grep vbox

# Start VirtualBox
virtualbox
```

You should see:
- `vboxdrv`, `vboxnetadp`, `vboxnetflt`, `vboxpci` in the module list
- VirtualBox GUI launches without errors

**Setup is now complete!** For future kernel updates, simply run `sudo virtualbox-sb-manager full` or enable the systemd service.

## After Kernel Updates

When Ubuntu installs a new kernel (via `apt upgrade`):

### Manual Method

```bash
# Rebuild, sign, verify, and load modules
sudo virtualbox-sb-manager full
```

Or step-by-step:

```bash
sudo virtualbox-sb-manager rebuild    # Rebuild modules for new kernel
sudo virtualbox-sb-manager sign       # Sign the rebuilt modules
sudo virtualbox-sb-manager verify     # Verify signatures (optional)
sudo virtualbox-sb-manager load       # Load the signed modules
```

### Automatic Method (Systemd Service)

If you've enabled the systemd service (recommended):

```bash
sudo systemctl start virtualbox-sb-manager.service
```

Or better yet, set up an APT hook (see [Systemd Service Installation](#systemd-service-installation)) for fully automatic handling during package upgrades.

## Understanding the Two Passwords

During setup, you will create **two different passwords**. Understanding the difference is crucial:

### 1. Signing Key Passphrase (OpenSSL)

**Purpose:** Protects your private signing key  
**Prompted as:** `Enter PEM pass phrase:` (then `Verifying - Enter PEM pass phrase:`)  
**When needed:** Every time you sign modules (after kernel updates)  
**Characteristics:**
- This is your **permanent** password
- Make it **secure and memorable**
- **Write it down** and store safely - you cannot recover it if forgotten
- Used by OpenSSL to encrypt `/root/module-signing/MOK.priv`

**Example usage:**
```bash
$ sudo virtualbox-sb-manager sign
Enter PEM pass phrase: [your signing key passphrase here]
```

### 2. Temporary MOK Password (mokutil)

**Purpose:** One-time password for MOK enrollment at next boot  
**Prompted as:** `input password:` (then `input password again:`)  
**When needed:** ONLY at next boot in MOK Manager  
**Characteristics:**
- This is a **one-time** password
- Can be **simple** (e.g., "temppass123")
- Only used during the MOK enrollment screen (blue screen)
- Can be forgotten after successful MOK enrollment

**Example:**
```bash
$ sudo virtualbox-sb-manager setup
...
input password: temppass123
input password again: temppass123
```

Then at next boot:
```
MOK Manager: [Enter password]
temppass123
```

**Important:** These passwords can (and should) be different! The MOK password is temporary; the signing key passphrase is permanent.

### What If I Forget the Signing Key Passphrase?

If you forget your signing key passphrase:

1. You'll need to recreate the keys:
```bash
sudo virtualbox-sb-manager setup
# Answer 'y' when asked to recreate keys
```

2. **Reboot** and re-enroll the new MOK key in MOK Manager

3. Sign the modules with the new key:
```bash
sudo virtualbox-sb-manager sign
```

## Troubleshooting

### "Could not insert 'vboxdrv': Key was rejected by service"

**Cause:** MOK not enrolled properly or expired.

**Solution:**
```bash
# Verify MOK enrollment
mokutil --list-enrolled | grep Subject

# If your key is not listed, re-enroll:
sudo virtualbox-sb-manager setup
# Or manually:
sudo mokutil --import /root/module-signing/MOK.der
sudo reboot
# Then enroll in MOK Manager
```

### "sign-file: command not found"

**Cause:** Kernel headers not installed.

**Solution:**
```bash
sudo apt install linux-headers-$(uname -r)
```

### "Module is NOT signed"

**Cause:** Modules haven't been signed yet.

**Solution:**
```bash
sudo virtualbox-sb-manager sign
```

### "Permission denied" or "Cannot create log file"

**Cause:** Not running as root.

**Solution:**
```bash
# Always use sudo
sudo virtualbox-sb-manager <command>
```

### "VirtualBox can't operate in VMX root mode (VERR_VMX_IN_VMX_ROOT_MODE)"

**Cause:** KVM is loaded and conflicts with VirtualBox.

**Solution:**
```bash
# Disable KVM temporarily
sudo virtualbox-sb-manager kvm disable

# Or permanently
sudo virtualbox-sb-manager kvm disable --permanent
```

### Modules not loading after kernel update

**Cause:** Modules need to be rebuilt and re-signed.

**Solution:**
```bash
sudo virtualbox-sb-manager full
```

### Secure Boot is disabled but modules still won't load

**Verify Secure Boot status:**
```bash
mokutil --sb-state
# Should output: SecureBoot enabled
```

If disabled, modules should load without signing. Check:
```bash
# Try loading manually
sudo modprobe vboxdrv

# Check kernel logs for errors
sudo dmesg | grep vbox
```

## Security Considerations

### Key Storage and Permissions

1. **Private Key Location:** `/root/module-signing/MOK.priv`
   - Permissions: `600` (read/write for root only)
   - Protected by passphrase encryption

2. **Public Key Location:** `/root/module-signing/MOK.der`
   - Permissions: `644` (readable by all)
   - Enrolled in MOK database

3. **No Stored Passphrases:** Your signing key passphrase is never stored on disk. It's only held in memory during signing operations.

### Secure Boot Benefits Maintained

- **Secure Boot remains enabled** throughout the process
- Only modules signed with your enrolled key can load
- Protection against unsigned/malicious kernel modules
- Full UEFI Secure Boot chain of trust preserved

### Key Validity

Keys are generated with a validity period of 36500 days (~100 years). To change this, modify the `-days` parameter in the setup command or edit the source code.

### Systemd Service Security

The provided systemd service files include security hardening:
- `PrivateTmp=yes` - Isolated /tmp directory
- `NoNewPrivileges=yes` - Cannot gain additional privileges
- `ProtectHome=yes` - Home directories inaccessible
- `ProtectSystem=strict` - Most of filesystem read-only

## File Locations

| Item | Location |
|------|----------|
| Rust Binary | `/usr/local/bin/virtualbox-sb-manager` |
| Shell Script | `./sign-vbox-modules.sh` or `/opt/virtualbox-sb-sign/sign-vbox-modules.sh` |
| Private Key | `/root/module-signing/MOK.priv` |
| Public Key (MOK) | `/root/module-signing/MOK.der` |
| Rust Log File | `/var/log/vbox-secure-boot-manager.log` |
| Shell Script Log | `/var/log/vbox-module-signing.log` |
| VBox Modules | `/lib/modules/$(uname -r)/kernel/drivers/virt/` or `/lib/modules/$(uname -r)/updates/dkms/` |
| sign-file Tool | `/usr/src/linux-headers-$(uname -r)/scripts/sign-file` |
| Systemd Services | `/etc/systemd/system/virtualbox-sb-manager.service` or `/etc/systemd/system/vbox-sign-modules.service` |

## References

### VirtualBox Documentation

- [VirtualBox Manual - Secure Boot](https://www.virtualbox.org/manual/ch02.html#secureboot) - Official documentation on Secure Boot requirements
- [VirtualBox Manual - Linux Hosts](https://www.virtualbox.org/manual/ch02.html#install-linux-host) - Installation and setup for Linux

### Ubuntu/Linux Secure Boot

- [Ubuntu SecureBoot Documentation](https://wiki.ubuntu.com/UEFI/SecureBoot) - Ubuntu's Secure Boot implementation
- [Kernel Module Signing](https://www.kernel.org/doc/html/latest/admin-guide/module-signing.html) - Linux kernel documentation on module signing

### Community Resources

- Original guide by Øyvind Stegard
- [GitHub Gist by reillysiemens](https://gist.github.com/reillysiemens/ac6bea1e6c7684d62f544bd79b2182a4) - Popular VirtualBox signing guide

### Related Tools

- [mokutil man page](https://manpages.ubuntu.com/manpages/focal/man1/mokutil.1.html) - Machine Owner Key management
- [DKMS documentation](https://github.com/dell/dkms) - Dynamic Kernel Module Support

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes with tests
4. Run the test suite (`cargo test`)
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

**Development:**
```bash
# Run tests
cargo test

# Check formatting
cargo fmt --check

# Run clippy (linter)
cargo clippy -- -D warnings

# Build and run locally
cargo run -- --help
sudo cargo run -- status
```

## License

MIT License - see LICENSE file for details.

## Support

- **Repository:** https://github.com/alexander-labarge/ubuntu-dev-helpers
- **Issues:** [GitHub Issues](https://github.com/alexander-labarge/ubuntu-dev-helpers/issues)
- **Contact:** alex@labarge.dev

---

**Target Platform:** Ubuntu 24.04.3 LTS (Primary), Gentoo (Future)  
**Last Updated:** December 7, 2025  
**Version:** 0.1.0-beta
