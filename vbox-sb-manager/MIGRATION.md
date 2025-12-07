# Migration Guide: Bash Scripts to Rust CLI

This guide helps you migrate from the bash scripts to the new Rust CLI application.

## Why Migrate?

The Rust application offers several advantages:

- **Type Safety**: Compile-time guarantees reduce runtime errors
- **Better Error Messages**: Clear, actionable error messages with recovery suggestions
- **Structured Logging**: Both console and file logging with different levels
- **Performance**: Faster execution and lower resource usage
- **Maintainability**: Easier to extend and maintain
- **Testing**: Comprehensive test coverage
- **User Experience**: Improved interactive mode and help system

## Key Differences

| Feature | Bash Scripts | Rust CLI |
|---------|-------------|----------|
| Binary Name | `sign-vbox-modules.sh` | `vbox-sb-manager` |
| Interactive Mode | Default | `vbox-sb-manager` or `vbox-sb-manager interactive` |
| Setup | `--setup` | `setup` subcommand |
| Sign | `--sign` | `sign` subcommand |
| Verify | `--verify` | `verify` subcommand |
| Load | `--load` | `load` subcommand |
| Full | `--full` | `full` subcommand |
| Rebuild | `--rebuild` | `rebuild` subcommand |
| KVM | `disable-kvm.sh` | `kvm` subcommand |
| Help | `--help` | `--help` or `help` |
| Verbose | N/A | `--verbose` or `-v` |
| Debug | N/A | `--debug` or `-d` |

## Command Mapping

### Setup

**Bash:**
```bash
sudo ./sign-vbox-modules.sh --setup
```

**Rust:**
```bash
sudo vbox-sb-manager setup
```

### Sign Modules

**Bash:**
```bash
sudo ./sign-vbox-modules.sh --sign
```

**Rust:**
```bash
sudo vbox-sb-manager sign
```

### Verify Signatures

**Bash:**
```bash
sudo ./sign-vbox-modules.sh --verify
```

**Rust:**
```bash
sudo vbox-sb-manager verify
```

### Load Modules

**Bash:**
```bash
sudo ./sign-vbox-modules.sh --load
```

**Rust:**
```bash
sudo vbox-sb-manager load
```

### Rebuild Modules

**Bash:**
```bash
sudo ./sign-vbox-modules.sh --rebuild
```

**Rust:**
```bash
sudo vbox-sb-manager rebuild
```

### Full Process

**Bash:**
```bash
sudo ./sign-vbox-modules.sh --full
```

**Rust:**
```bash
sudo vbox-sb-manager full
```

### Interactive Mode

**Bash:**
```bash
sudo ./sign-vbox-modules.sh
```

**Rust:**
```bash
sudo vbox-sb-manager
# or explicitly:
sudo vbox-sb-manager interactive
```

### KVM Management

**Bash:**
```bash
sudo ./disable-kvm.sh --disable
sudo ./disable-kvm.sh --permanent
sudo ./disable-kvm.sh --enable
sudo ./disable-kvm.sh --status
```

**Rust:**
```bash
sudo vbox-sb-manager kvm disable
sudo vbox-sb-manager kvm disable --permanent
sudo vbox-sb-manager kvm enable
sudo vbox-sb-manager kvm status
```

## Migration Steps

### Step 1: Install Rust CLI

```bash
# Build from source
cd /path/to/virtualbox_sb_sign
cargo build --release

# Install binary
sudo cp target/release/vbox-sb-manager /usr/local/bin/

# Verify installation
vbox-sb-manager --version
```

### Step 2: Test with Existing Keys

The Rust CLI uses the same key locations as the bash scripts:

```bash
# Check status
sudo vbox-sb-manager status

# Try signing with existing keys
sudo vbox-sb-manager sign
```

### Step 3: Update Scripts/Aliases

If you have scripts or aliases using the bash version:

**Old script:**
```bash
#!/bin/bash
sudo /path/to/sign-vbox-modules.sh --full
```

**New script:**
```bash
#!/bin/bash
sudo vbox-sb-manager full
```

**Old alias:**
```bash
alias vbox-sign='sudo /path/to/sign-vbox-modules.sh --sign'
```

**New alias:**
```bash
alias vbox-sign='sudo vbox-sb-manager sign'
```

### Step 4: Update Automation

If you have automated processes (cron, systemd, etc.):

**Old cron job:**
```cron
0 2 * * * /path/to/sign-vbox-modules.sh --full
```

**New cron job:**
```cron
0 2 * * * /usr/local/bin/vbox-sb-manager full
```

**Old systemd service:**
```ini
[Service]
ExecStart=/path/to/sign-vbox-modules.sh --sign
```

**New systemd service:**
```ini
[Service]
ExecStart=/usr/local/bin/vbox-sb-manager sign
```

### Step 5: Remove Old Scripts (Optional)

Once you've verified everything works:

```bash
# Backup bash scripts
mkdir ~/vbox-bash-backup
cp sign-vbox-modules.sh disable-kvm.sh ~/vbox-bash-backup/

# Remove from PATH (if applicable)
# The Rust CLI is now your primary tool
```

## Compatibility

### Preserved Features

** Same key locations (`/root/module-signing/`)
** Same log location pattern (now `/var/log/vbox-secure-boot-manager.log`)
** Same workflow (setup → sign → load)
** Same module detection logic
** Same compression support (.ko, .ko.xz, .ko.gz, .ko.zst)

### New Features

➕ Improved error messages with recovery suggestions
➕ Structured logging with levels (error, warn, info, debug)
➕ Better interactive menu
➕ Subcommand structure for better organization
➕ Status command for system overview
➕ Verbose and debug modes
➕ Comprehensive help system

### Breaking Changes

⚠️ Command syntax changed (from flags to subcommands)
⚠️ Script names changed (unified into single binary)
⚠️ Log file name changed
⚠️ Some error messages are different (but more helpful)

## Rollback Plan

If you need to rollback to bash scripts:

```bash
# The bash scripts still exist in the repository
cd /path/to/virtualbox_sb_sign
sudo ./sign-vbox-modules.sh --sign

# Your keys are unchanged, so no re-setup needed
```

## Troubleshooting Migration

### "Keys not found"

The Rust CLI looks in the same location as bash scripts:

```bash
# Check if keys exist
ls -la /root/module-signing/

# If not, run setup
sudo vbox-sb-manager setup
```

### "Command not found"

Ensure the binary is in your PATH:

```bash
which vbox-sb-manager
# Should output: /usr/local/bin/vbox-sb-manager

# If not found, add to PATH or use full path
/usr/local/bin/vbox-sb-manager status
```

### "Different behavior"

The Rust CLI should behave the same for core operations. If you notice differences:

1. Check the logs: `/var/log/vbox-secure-boot-manager.log`
2. Run with `--verbose` or `--debug` for more details
3. Report issues on GitHub

## Performance Comparison

Expected improvements:

- **Startup time**: ~10-50ms (bash) → ~1-5ms (Rust)
- **Module signing**: Similar (bottleneck is OpenSSL)
- **Memory usage**: ~5-10MB (bash) → ~2-5MB (Rust)
- **Binary size**: N/A → ~5-10MB (Rust, fully static)

## Support

For migration help:

- GitHub Issues: https://github.com/alexander-labarge/virtualbox_sb_sign/issues
- Documentation: See docs/ directory
- Examples: See examples/USAGE_EXAMPLES.md

## Feedback

We'd love to hear about your migration experience! Please:

1. Report any issues on GitHub
2. Share your feedback
3. Contribute improvements

The bash scripts will remain in the repository for reference and backward compatibility.
