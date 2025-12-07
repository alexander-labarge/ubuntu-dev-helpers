# Usage Examples

## Example 1: First-Time Setup

```bash
# Install prerequisites
sudo apt update
sudo apt install -y virtualbox dkms mokutil openssl linux-headers-$(uname -r)

# Run setup
sudo vbox-sb-manager setup

# You'll be prompted for:
# 1. Certificate name (or press Enter for default)
# 2. Signing key passphrase (enter twice)
# 3. Temporary MOK password (enter twice)

# Reboot
sudo reboot

# In MOK Manager (blue screen):
# - Select "Enroll MOK"
# - Select "Continue"
# - Select "Yes"
# - Enter the temporary MOK password
# - Reboot

# After reboot, sign and load modules
sudo vbox-sb-manager sign
sudo vbox-sb-manager load
```

## Example 2: After Kernel Update

```bash
# Check if VirtualBox modules need rebuilding
sudo vbox-sb-manager status

# Full rebuild, sign, verify, and load
sudo vbox-sb-manager full

# Or step-by-step:
sudo vbox-sb-manager rebuild
sudo vbox-sb-manager sign
sudo vbox-sb-manager verify
sudo vbox-sb-manager load
```

## Example 3: Fixing KVM Conflict

```bash
# Check if KVM is loaded
sudo vbox-sb-manager kvm status

# If KVM is loaded, disable it
sudo vbox-sb-manager kvm disable

# For permanent disable:
sudo vbox-sb-manager kvm disable --permanent
```

## Example 4: Scripted Automation

```bash
#!/bin/bash
# Script to rebuild and sign VirtualBox modules

set -e

# Store passphrase securely (not recommended for production)
# Better: use a secure vault or prompt
PASSPHRASE="your_secure_passphrase"

# Rebuild modules
sudo vbox-sb-manager rebuild

# Sign modules (passphrase will be prompted)
echo "$PASSPHRASE" | sudo -S vbox-sb-manager sign

# Verify
sudo vbox-sb-manager verify

# Load
sudo vbox-sb-manager load

echo "VirtualBox modules updated successfully!"
```

## Example 5: Interactive Mode

```bash
# Launch interactive menu
sudo vbox-sb-manager

# Or explicitly:
sudo vbox-sb-manager interactive

# Use arrow keys to navigate menu
# Press Enter to select option
```

## Example 6: Checking System Status

```bash
# Comprehensive system check
sudo vbox-sb-manager status

# With verbose output
sudo vbox-sb-manager --verbose status

# With debug output
sudo vbox-sb-manager --debug status
```

## Example 7: Troubleshooting

```bash
# Check logs
sudo tail -f /var/log/vbox-secure-boot-manager.log

# Verify MOK enrollment
sudo mokutil --list-enrolled

# Check if modules are loaded
lsmod | grep vbox

# Check module signatures
sudo modinfo vboxdrv | grep sig
```

## Example 8: Systemd Service (Advanced)

Create a systemd service to automatically sign modules after DKMS builds:

```bash
# Create service file
sudo tee /etc/systemd/system/vbox-sign-modules.service << 'EOF'
[Unit]
Description=Sign VirtualBox Kernel Modules
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/vbox-sb-manager sign
StandardInput=tty
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Enable service
sudo systemctl enable vbox-sign-modules.service
```

## Example 9: Recovery from Lost Passphrase

```bash
# If you lost your signing key passphrase, recreate keys
sudo rm -rf /root/module-signing

# Run setup again
sudo vbox-sb-manager setup

# Reboot and re-enroll MOK
sudo reboot
```

## Example 10: Uninstalling VirtualBox

```bash
# Unload modules
sudo vbox-sb-manager kvm enable  # Re-enable KVM if needed

# Remove VirtualBox
sudo apt remove --purge virtualbox virtualbox-dkms

# Optionally remove signing keys
sudo rm -rf /root/module-signing
```
