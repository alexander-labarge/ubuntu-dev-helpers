# Installation Guide

## Prerequisites

### System Requirements

- **Operating System**: Ubuntu 24.04 LTS (or other Debian-based distributions)
- **Architecture**: x86_64
- **UEFI Secure Boot**: Must be enabled
- **Root Access**: Required for module operations

### Required Packages

Install VirtualBox and dependencies:

```bash
sudo apt update
sudo apt install -y \
    virtualbox \
    virtualbox-dkms \
    dkms \
    mokutil \
    openssl \
    linux-headers-$(uname -r) \
    build-essential \
    zstd
```

### Rust Toolchain (for building from source)

If building from source, install Rust:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env
```

## Installation Methods

### Method 1: Pre-built Binary (Recommended)

Download the latest release:

```bash
# Download binary (replace VERSION with actual version)
wget https://github.com/alexander-labarge/virtualbox_sb_sign/releases/download/VERSION/vbox-sb-manager

# Make it executable
chmod +x vbox-sb-manager

# Move to system path
sudo mv vbox-sb-manager /usr/local/bin/

# Verify installation
vbox-sb-manager --version
```

### Method 2: Build from Source

Clone and build:

```bash
# Clone repository
git clone https://github.com/alexander-labarge/virtualbox_sb_sign.git
cd virtualbox_sb_sign

# Build release version
cargo build --release

# Install binary
sudo cp target/release/vbox-sb-manager /usr/local/bin/

# Or use cargo install
cargo install --path .

# Verify installation
vbox-sb-manager --version
```

### Method 3: Cargo Install (from crates.io)

Once published to crates.io:

```bash
cargo install virtualbox-secure-boot-manager
```

## Post-Installation

### Verify Installation

```bash
# Check version
vbox-sb-manager --version

# Check help
vbox-sb-manager --help

# Check system status (requires sudo)
sudo vbox-sb-manager status
```

### Initial Setup

Run the setup process:

```bash
sudo vbox-sb-manager setup
```

Follow the prompts to:
1. Create signing keys
2. Set signing key passphrase
3. Set temporary MOK password
4. Reboot and enroll MOK

## Upgrading

### From Bash Scripts

If you're migrating from the bash scripts:

1. The Rust application uses the same key locations (`/root/module-signing/`)
2. Your existing keys will be preserved
3. No need to re-enroll MOK
4. Simply install the binary and start using it

```bash
# Install the Rust version
sudo cp vbox-sb-manager /usr/local/bin/

# Use existing keys - no setup needed
sudo vbox-sb-manager sign
sudo vbox-sb-manager load
```

### Updating the Application

To update to a new version:

```bash
# If installed via cargo
cargo install virtualbox-secure-boot-manager --force

# If installed manually
# Download new binary and replace:
sudo wget -O /usr/local/bin/vbox-sb-manager \
    https://github.com/alexander-labarge/virtualbox_sb_sign/releases/download/VERSION/vbox-sb-manager
sudo chmod +x /usr/local/bin/vbox-sb-manager
```

## Uninstallation

### Remove Application

```bash
# Remove binary
sudo rm /usr/local/bin/vbox-sb-manager

# If installed via cargo
cargo uninstall virtualbox-secure-boot-manager
```

### Remove Keys (Optional)

```bash
# Remove signing keys
sudo rm -rf /root/module-signing

# Note: This will require re-enrolling MOK if you reinstall
```

### Remove Logs (Optional)

```bash
# Remove log file
sudo rm /var/log/vbox-secure-boot-manager.log
```

## Troubleshooting Installation

### "command not found"

Make sure `/usr/local/bin` is in your PATH:

```bash
echo $PATH | grep -q "/usr/local/bin" || echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### "Permission denied" when running

The binary needs to be executable:

```bash
sudo chmod +x /usr/local/bin/vbox-sb-manager
```

### Build errors

Ensure you have the Rust toolchain:

```bash
rustc --version
cargo --version

# If not installed:
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

### Missing dependencies during build

Install build dependencies:

```bash
sudo apt install -y build-essential pkg-config libssl-dev
```

## Platform-Specific Notes

### Ubuntu / Debian

Standard installation works as described above.

### Fedora / RHEL

Replace `apt` with `dnf`:

```bash
sudo dnf install -y virtualbox kernel-devel mokutil openssl
```

### Arch Linux

Use `pacman`:

```bash
sudo pacman -S virtualbox linux-headers mokutil openssl
```

## Verification

After installation, verify everything works:

```bash
# Check version
vbox-sb-manager --version

# Check help
vbox-sb-manager --help

# Check status (requires sudo)
sudo vbox-sb-manager status

# Test interactive mode (requires sudo)
sudo vbox-sb-manager interactive
```

## Next Steps

After installation:

1. Read [RUST_README.md](../RUST_README.md) for usage instructions
2. Review [examples/USAGE_EXAMPLES.md](../examples/USAGE_EXAMPLES.md) for common scenarios
3. Run `sudo vbox-sb-manager setup` if this is your first time
4. Check `sudo vbox-sb-manager status` to verify system state

## Support

For issues, questions, or bug reports:
- GitHub Issues: https://github.com/alexander-labarge/virtualbox_sb_sign/issues
- Documentation: See docs/ directory
