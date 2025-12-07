# Architecture and Design

## Overview

VirtualBox Secure Boot Manager is a Rust CLI application designed to manage VirtualBox kernel module signing on Linux systems with UEFI Secure Boot enabled. It replaces bash scripts with a type-safe, robust solution.

## Design Principles

1. **Safety**: Leverage Rust's type system for compile-time guarantees
2. **User Experience**: Clear error messages with recovery suggestions
3. **Maintainability**: Modular architecture with clear separation of concerns
4. **Security**: Proper permission checks and secure key handling
5. **Testability**: Comprehensive unit and integration tests

## Architecture

### Module Organization

```
virtualbox-secure-boot-manager/
├── cli/              # Command-line interface
│   ├── commands.rs   # Command implementations
│   └── interactive.rs # Interactive menu
├── modules/          # Core business logic
│   ├── kvm.rs        # KVM management
│   ├── signing.rs    # Module signing
│   ├── mok.rs        # MOK enrollment
│   └── verification.rs # Verification
├── utils/            # Utilities
│   ├── logger.rs     # Logging
│   ├── output.rs     # Terminal output
│   └── system.rs     # System operations
├── error.rs          # Error types
├── config.rs         # Configuration
└── lib.rs            # Public API
```

### Data Flow

```
User Input (CLI/Interactive)
    ↓
Command Handler (cli/commands.rs)
    ↓
Core Module (modules/*)
    ↓
System Operation (utils/system.rs)
    ↓
External Command (OpenSSL, mokutil, etc.)
```

### Error Handling

The application uses a custom `VBoxError` enum with `thiserror` for structured error handling:

```rust
pub enum VBoxError {
    PermissionDenied(String),
    DependencyMissing(String),
    ModuleNotFound(String),
    // ... more variants
}
```

Each error provides:
- Clear error message
- Recovery suggestion
- Automatic conversion from common error types (IO, JSON, etc.)

### Configuration Management

Configuration is managed through a `Config` struct with sensible defaults:

```rust
pub struct Config {
    pub key_dir: PathBuf,
    pub private_key: PathBuf,
    pub public_key: PathBuf,
    pub hash_algo: String,
    pub log_file: PathBuf,
    // ...
}
```

## Key Components

### 1. KVM Management (`modules/kvm.rs`)

Handles VirtualBox-KVM conflicts:
- Check hardware virtualization support
- Detect loaded KVM modules
- Disable KVM (temporary or permanent)
- Re-enable KVM

### 2. Module Signing (`modules/signing.rs`)

Core signing functionality:
- Find VirtualBox modules (including compressed variants)
- Decompress modules (.xz, .gz, .zst)
- Sign with OpenSSL
- Recompress modules
- Handle DKMS rebuilds

### 3. MOK Management (`modules/mok.rs`)

Machine Owner Key operations:
- Generate RSA key pairs with OpenSSL
- Enroll MOK with mokutil
- Verify MOK enrollment status
- Complete setup workflow

### 4. Verification (`modules/verification.rs`)

Module verification and loading:
- Verify module signatures
- Load kernel modules
- Check module status
- Get module information

### 5. CLI (`cli/commands.rs` and `cli/interactive.rs`)

User interface:
- Command-line parsing with clap
- Interactive menu with dialoguer
- Secure password prompts
- Progress indicators

## Security Considerations

### Key Storage

- Private keys stored in `/root/module-signing/` with 600 permissions
- Only accessible by root
- Protected by passphrase

### Passphrase Handling

- Never stored on disk
- Only in memory during operations
- Environment variables cleared after use
- Interactive prompts with hidden input

### Permission Checks

- Root checks before privileged operations
- Clear error messages for permission issues
- Suggestions for proper invocation

## Testing Strategy

### Unit Tests

- Error handling and recovery suggestions
- Module detection and naming
- Configuration validation
- System utilities

### Integration Tests

- Can be added using `assert_cmd` for CLI testing
- Mock system calls for reproducible tests

## Logging

Dual logging strategy:
- Console output (colored, user-friendly)
- File logging (structured, detailed)

Log levels:
- Error: Critical failures
- Warn: Non-fatal issues
- Info: Progress and status
- Debug: Detailed execution flow

## Dependencies

Key dependencies and their purposes:

| Crate | Purpose |
|-------|---------|
| `clap` | CLI argument parsing |
| `dialoguer` | Interactive prompts |
| `colored` | Terminal colors |
| `log` + `env_logger` | Logging framework |
| `anyhow` + `thiserror` | Error handling |
| `tokio` | Async runtime (future expansion) |
| `serde` + `serde_json` | Configuration serialization |
| `nix` | Unix system calls |
| `which` | Command detection |
| `walkdir` | Directory traversal |
| `regex` | Pattern matching |
| `chrono` | Timestamps |

## Future Enhancements

Potential improvements:

1. **Configuration File**: Support for `/etc/vbox-sb-manager.conf`
2. **Async Operations**: Parallel module signing
3. **Systemd Integration**: Automatic module signing on kernel updates
4. **Web Dashboard**: Optional web interface for status monitoring
5. **Distribution Packages**: .deb and .rpm packages
6. **Backup/Restore**: Key backup and recovery
7. **Multiple Key Sets**: Support for different signing keys
8. **Audit Trail**: Enhanced logging with audit capabilities

## Performance Considerations

- Minimal overhead compared to bash scripts
- Efficient file I/O with Rust's standard library
- Parallel processing potential for multiple modules
- Small binary size (~5-10 MB with release optimizations)

## Compatibility

- **OS**: Linux (Ubuntu, Debian, RHEL, Fedora, Arch)
- **Architecture**: x86_64, aarch64 (where UEFI Secure Boot is supported)
- **Rust**: Edition 2021, MSRV 1.70+
- **Kernel**: Linux 4.0+ with module signing support
