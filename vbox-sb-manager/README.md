# VirtualBox Secure Boot Manager

Production-ready tooling for managing VirtualBox kernel module signing on UEFI Secure Boot enabled systems.

## Quick Start

```bash
# Build and install (from project root)
make build install

# Or build directly
cd vbox-sb-manager
cargo build --release
sudo cp target/release/virtualbox-sb-manager /usr/local/bin/

# Initial setup
sudo virtualbox-sb-manager setup

# After reboot (to enroll MOK key)
sudo virtualbox-sb-manager full
```

## What This Solves

VirtualBox requires kernel modules that must be cryptographically signed when Secure Boot is enabled. This tool automates:

- - Signing key generation
- - MOK (Machine Owner Key) enrollment
- - Automatic module signing after kernel updates
- - Module verification and loading
- - KVM conflict management

## Components

### Rust Binary (Recommended)

Production-ready implementation with comprehensive error handling:

```bash
# Interactive mode
sudo virtualbox-sb-manager

# Command-line usage
sudo virtualbox-sb-manager setup     # Initial setup
sudo virtualbox-sb-manager sign      # Sign modules
sudo virtualbox-sb-manager verify    # Verify signatures
sudo virtualbox-sb-manager full      # Do everything
sudo virtualbox-sb-manager kvm disable  # Handle KVM conflicts

# With logging
sudo virtualbox-sb-manager --verbose full
sudo virtualbox-sb-manager --debug status
```

### Shell Scripts (Alternative)

Battle-tested bash implementations:

```bash
# Sign VirtualBox modules
sudo ./sign-vbox-modules.sh

# KVM management
sudo ./disable-kvm.sh --status
sudo ./disable-kvm.sh --disable
```

Both implementations use the same key storage and are fully compatible.

## Systemd Service (Optional)

Enable automatic module signing after kernel updates:

```bash
# Install service
sudo cp systemd/virtualbox-sb-manager.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable virtualbox-sb-manager.service
sudo systemctl start virtualbox-sb-manager.service

# Check status
sudo systemctl status virtualbox-sb-manager.service
```

## Requirements

- Ubuntu 24.04.3 LTS (or compatible Debian-based distribution)
- UEFI Secure Boot enabled
- VirtualBox installed
- Root/sudo access
- Rust toolchain 1.70+ (for building)

## Installation

```bash
# Prerequisites
sudo apt install virtualbox dkms mokutil openssl linux-headers-$(uname -r)

# Build from source
cargo build --release

# Install
sudo cp target/release/virtualbox-sb-manager /usr/local/bin/
sudo chmod +x /usr/local/bin/virtualbox-sb-manager
```

## Documentation

- [ARCHITECTURE.md](./ARCHITECTURE.md) - Technical architecture and design
- [PASSWORD-GUIDE.md](./PASSWORD-GUIDE.md) - Password management guide
- [MIGRATION.md](./MIGRATION.md) - Migration from shell scripts
- [examples/](./examples/) - Usage examples

See [main README](../README.md) for complete project documentation.

## Testing

```bash
# Run integration tests
cargo test

# Or from project root
make test
```

## Key Files

- `Cargo.toml` - Rust project manifest
- `src/` - Source code
  - `main.rs` - Entry point
  - `cli/` - Command-line interface
  - `modules/` - Core functionality (signing, MOK, KVM, verification)
  - `config.rs` - Configuration management
  - `error.rs` - Error handling
- `systemd/` - Systemd service files
- `tests/` - Integration tests
- Shell scripts:
  - `sign-vbox-modules.sh` - Module signing script
  - `disable-kvm.sh` - KVM management script

## License

MIT License - see [LICENSE](../LICENSE) file for details.
