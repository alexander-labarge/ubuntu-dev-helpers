.PHONY: help setup setup-secureboot dev-env vbox-manager docker langs packages clean build install test
.PHONY: iso-download vm-create vm-list vm-running vm-start vm-stop vm-delete vm-snapshot vm-restore vm-clone vm-info vm-eject vm-attach-iso vm-show-iso
.PHONY: ssh-gen ssh-enroll ssh-config ssh-test ssh-copy-scripts

# Use bash for shell commands (needed for source, [[ ]], etc.)
SHELL := /bin/bash

# Default target
help:
	@echo "Development Server Helpers - Makefile"
	@echo ""
	@echo "Usage: make [TARGET]"
	@echo ""
	@echo "Main Targets:"
	@echo "  setup              - Full development environment setup"
	@echo "  setup-secureboot   - Full setup with VirtualBox Secure Boot configuration"
	@echo "  iso-download       - Download Ubuntu ISOs"
	@echo ""
	@echo "Component-Specific Targets:"
	@echo "  dev-env            - Run development environment setup script"
	@echo "  docker             - Install Docker and Docker Compose only"
	@echo "  langs              - Install programming languages (Rust, Go, Java)"
	@echo "  packages           - Install essential development packages"
	@echo "  vbox-manager       - Build and install VirtualBox Secure Boot Manager"
	@echo ""
	@echo "VirtualBox Secure Boot Manager:"
	@echo "  build              - Build the Rust binary"
	@echo "  install            - Install the built binary to /usr/local/bin"
	@echo "  test               - Run integration tests"
	@echo "  vbox-setup         - Setup VirtualBox Secure Boot (interactive)"
	@echo ""
	@echo "VBox Factory (VM Management):"
	@echo "  vm-create          - Create a new VM (bridged network default)"
	@echo "  vm-list            - List all VMs"
	@echo "  vm-running         - List running VMs"
	@echo "  vm-start           - Start a VM"
	@echo "  vm-stop            - Stop a VM"
	@echo "  vm-delete          - Delete a VM and its disk"
	@echo "  vm-snapshot        - Take a snapshot"
	@echo "  vm-restore         - Restore a snapshot"
	@echo "  vm-clone           - Clone a VM"
	@echo "  vm-info            - Show VM details"
	@echo "  vm-eject           - Eject ISO from VM"
	@echo ""
	@echo "SSH Key Manager:"
	@echo "  ssh-gen            - Generate SSH key pair (interactive)"
	@echo "  ssh-enroll         - Enroll SSH key on remote host (interactive)"
	@echo "  ssh-config         - Run full SSH configuration (interactive)"
	@echo "  ssh-test           - Test SSH connection to a host"
	@echo "  ssh-copy-scripts   - Copy ./scripts to remote host"
	@echo ""
	@echo "Utility Targets:"
	@echo "  clean              - Remove build artifacts"
	@echo ""
	@echo "Examples:"
	@echo "  sudo make setup                      # Full setup"
	@echo "  sudo make setup-secureboot           # Setup with Secure Boot"
	@echo "  make iso-download                    # Download Ubuntu ISOs"
	@echo "  make vm-create VM_NAME=dev-server VM_IP=192.168.50.100"
	@echo "  make vm-create VM_NAME=desktop VM_TYPE=desktop VM_GUI=1"
	@echo "  make vm-start VM_NAME=dev-server"
	@echo "  make vm-stop VM_NAME=dev-server"
	@echo "  make vm-snapshot VM_NAME=dev-server SNAP_NAME=clean-install"
	@echo "  make ssh-gen                         # Generate SSH key"
	@echo "  make ssh-enroll SSH_HOST=192.168.50.100 SSH_USER=skywalker"
	@echo "  make ssh-test SSH_HOST=192.168.50.100"

# Full development environment setup
setup:
	@echo "Running full development environment setup..."
	sudo ./dev-env-setup/dev-server-setup.sh

# Full setup with Secure Boot configuration
setup-secureboot:
	@echo "Running full setup with Secure Boot configuration..."
	sudo ./dev-env-setup/dev-server-setup.sh --secureboot

# Run dev environment setup
dev-env:
	@echo "Running development environment setup..."
	sudo ./dev-env-setup/dev-server-setup.sh

# Docker only
docker:
	@echo "Installing Docker and Docker Compose..."
	sudo ./dev-env-setup/dev-server-setup.sh --docker-only

# Programming languages only
langs:
	@echo "Installing programming languages..."
	sudo ./dev-env-setup/dev-server-setup.sh --langs-only

# Essential packages only
packages:
	@echo "Installing essential packages..."
	sudo ./dev-env-setup/dev-server-setup.sh --packages-only

# Download Ubuntu ISOs (defaults to 24.04.3) with optional env overrides:
#   UBUNTU_VERSION=24.04.3 ISO_DIR=$HOME/vms/isos DOWNLOAD_SERVER=1 DOWNLOAD_DESKTOP=1
iso-download:
	@echo "Downloading Ubuntu ISOs..."
	ISO_DIR="$$ISO_DIR" UBUNTU_VERSION="$$UBUNTU_VERSION" DOWNLOAD_SERVER="$$DOWNLOAD_SERVER" DOWNLOAD_DESKTOP="$$DOWNLOAD_DESKTOP" ./iso-manager/download_ubuntu_24.04.3.sh

# Build VirtualBox Secure Boot Manager
build:
	@echo "Building VirtualBox Secure Boot Manager..."
	cd vbox-sb-manager && cargo build --release

# Install VirtualBox Secure Boot Manager
install: build
	@echo "Installing VirtualBox Secure Boot Manager..."
	sudo cp vbox-sb-manager/target/release/virtualbox-sb-manager /usr/local/bin/
	sudo chmod +x /usr/local/bin/virtualbox-sb-manager
	@echo "Installed to /usr/local/bin/virtualbox-sb-manager"
	@virtualbox-sb-manager --version

# Build and install VirtualBox Secure Boot Manager
vbox-manager:
	@echo "Building and installing VirtualBox Secure Boot Manager..."
	sudo ./dev-env-setup/dev-server-setup.sh --vbox-sb-manager-only

# Setup VirtualBox Secure Boot
vbox-setup:
	@echo "Setting up VirtualBox Secure Boot..."
	sudo virtualbox-sb-manager setup

# Run tests
test:
	@echo "Running integration tests..."
	cd vbox-sb-manager && cargo test

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	cd vbox-sb-manager && cargo clean
	rm -rf target

# ==============================================================================
# VBox Factory - VM Management
# ==============================================================================

# Create a new VM (bridged network + static IP by default)
# Usage: make vm-create VM_NAME=myvm [VM_RAM=4096] [VM_CPUS=2] [VM_DISK=51200] \
#        [VM_IP=192.168.1.100] [VM_GATEWAY=192.168.1.1] [VM_DNS=8.8.8.8] \
#        [VM_IFACE=eth0] [VM_TYPE=server] [VM_ISO=...] [VM_NET=bridged|nat]
vm-create:
ifndef VM_NAME
	$(error VM_NAME is required. Usage: make vm-create VM_NAME=myvm)
endif
	@./vbox-factory/create-vm.sh \
		--name "$(VM_NAME)" \
		$(if $(VM_RAM),--ram "$(VM_RAM)") \
		$(if $(VM_CPUS),--cpus "$(VM_CPUS)") \
		$(if $(VM_DISK),--disk "$(VM_DISK)") \
		$(if $(VM_IP),--ip "$(VM_IP)") \
		$(if $(VM_GATEWAY),--gateway "$(VM_GATEWAY)") \
		$(if $(VM_DNS),--dns "$(VM_DNS)") \
		$(if $(VM_IFACE),--iface "$(VM_IFACE)") \
		$(if $(VM_TYPE),--type "$(VM_TYPE)") \
		$(if $(VM_ISO),--iso "$(VM_ISO)") \
		$(if $(VM_NET),--network "$(VM_NET)") \
		$(if $(VM_SSH_PORT),--ssh-port "$(VM_SSH_PORT)") \
		$(if $(filter 1,$(VM_NO_START)),--no-start) \
		$(if $(filter 1,$(VM_GUI)),--gui)

# List all VMs
vm-list:
	@VBoxManage list vms

# List running VMs
vm-running:
	@VBoxManage list runningvms

# Start a VM (GUI by default) - automatically disables KVM if needed
# Usage: make vm-start VM_NAME=myvm [VM_HEADLESS=1]
vm-start:
ifndef VM_NAME
	$(error VM_NAME is required. Usage: make vm-start VM_NAME=myvm)
endif
	@./vbox-factory/start-vm.sh "$(VM_NAME)" $(if $(VM_HEADLESS),headless,gui)

# Stop a VM gracefully (use VM_FORCE=1 for immediate poweroff)
# Usage: make vm-stop VM_NAME=myvm [VM_FORCE=1]
vm-stop:
ifndef VM_NAME
	$(error VM_NAME is required. Usage: make vm-stop VM_NAME=myvm)
endif
	@VBoxManage controlvm "$(VM_NAME)" $(if $(VM_FORCE),poweroff,acpipowerbutton) 2>/dev/null || echo "VM '$(VM_NAME)' is not running or does not exist"

# Delete a VM and its disk
# Usage: make vm-delete VM_NAME=myvm
vm-delete:
ifndef VM_NAME
	$(error VM_NAME is required. Usage: make vm-delete VM_NAME=myvm)
endif
	@VBoxManage unregistervm "$(VM_NAME)" --delete

# Take a snapshot
# Usage: make vm-snapshot VM_NAME=myvm SNAP_NAME=before-update
vm-snapshot:
ifndef VM_NAME
	$(error VM_NAME is required. Usage: make vm-snapshot VM_NAME=myvm SNAP_NAME=snap1)
endif
ifndef SNAP_NAME
	$(error SNAP_NAME is required. Usage: make vm-snapshot VM_NAME=myvm SNAP_NAME=snap1)
endif
	@VBoxManage snapshot "$(VM_NAME)" take "$(SNAP_NAME)"

# Restore a snapshot
# Usage: make vm-restore VM_NAME=myvm SNAP_NAME=before-update
vm-restore:
ifndef VM_NAME
	$(error VM_NAME is required. Usage: make vm-restore VM_NAME=myvm SNAP_NAME=snap1)
endif
ifndef SNAP_NAME
	$(error SNAP_NAME is required. Usage: make vm-restore VM_NAME=myvm SNAP_NAME=snap1)
endif
	@VBoxManage snapshot "$(VM_NAME)" restore "$(SNAP_NAME)"

# Clone a VM (full clone by default, use VM_LINKED=1 for linked clone)
# Usage: make vm-clone VM_TEMPLATE=ubuntu-base VM_NAME=new-vm [VM_LINKED=1]
vm-clone:
ifndef VM_TEMPLATE
	$(error VM_TEMPLATE is required. Usage: make vm-clone VM_TEMPLATE=base VM_NAME=clone)
endif
ifndef VM_NAME
	$(error VM_NAME is required. Usage: make vm-clone VM_TEMPLATE=base VM_NAME=clone)
endif
	@VBoxManage clonevm "$(VM_TEMPLATE)" --name "$(VM_NAME)" --register \
		$(if $(VM_LINKED),--options link,--mode all)

# Show VM info
# Usage: make vm-info VM_NAME=myvm
vm-info:
ifndef VM_NAME
	$(error VM_NAME is required. Usage: make vm-info VM_NAME=myvm)
endif
	@VBoxManage showvminfo "$(VM_NAME)"

# Attach ISO to VM
# Usage: make vm-attach-iso VM_NAME=myvm [VM_ISO=/path/to/iso] [VM_TYPE=desktop|server]
# If VM_ISO not specified, auto-selects based on VM_TYPE (default: desktop)
vm-attach-iso:
ifndef VM_NAME
	$(error VM_NAME is required. Usage: make vm-attach-iso VM_NAME=myvm [VM_ISO=/path/to/iso])
endif
	@source vbox-factory/vbox-defaults.sh && \
	ISO_PATH="$(VM_ISO)"; \
	if [ -z "$$ISO_PATH" ]; then \
		VM_TYPE="$${VM_TYPE:-desktop}"; \
		if [ "$$VM_TYPE" = "server" ]; then \
			ISO_PATH="$$VBOX_DEFAULT_ISO_SERVER"; \
		else \
			ISO_PATH="$$VBOX_DEFAULT_ISO_DESKTOP"; \
		fi; \
	fi; \
	if [ ! -f "$$ISO_PATH" ]; then \
		echo "Error: ISO not found at $$ISO_PATH"; \
		echo "Available ISOs in $$VBOX_DEFAULT_ISO_DIR:"; \
		ls -la "$$VBOX_DEFAULT_ISO_DIR"/*.iso 2>/dev/null || echo "  (none)"; \
		exit 1; \
	fi; \
	echo "Attaching ISO: $$ISO_PATH to $(VM_NAME)"; \
	VBoxManage storageattach "$(VM_NAME)" --storagectl "SATA" --port 1 --device 0 --type dvddrive --medium "$$ISO_PATH"; \
	echo "[OK] ISO attached successfully"

# Eject ISO from VM
# Usage: make vm-eject VM_NAME=myvm
vm-eject:
ifndef VM_NAME
	$(error VM_NAME is required. Usage: make vm-eject VM_NAME=myvm)
endif
	@VBoxManage storageattach "$(VM_NAME)" --storagectl "SATA" --port 1 --device 0 --type dvddrive --medium emptydrive
	@echo "[OK] ISO ejected"

# Show what ISO is attached to a VM
# Usage: make vm-show-iso VM_NAME=myvm
vm-show-iso:
ifndef VM_NAME
	$(error VM_NAME is required. Usage: make vm-show-iso VM_NAME=myvm)
endif
	@echo "ISO status for $(VM_NAME):"
	@VBoxManage showvminfo "$(VM_NAME)" --machinereadable | grep -E "SATA-1-0" || echo "No SATA-1-0 found"

# ==============================================================================
# SSH Key Manager
# ==============================================================================

# Generate SSH key pair (interactive)
# Usage: make ssh-gen [SSH_KEY_TYPE=ed25519] [SSH_KEY_NAME=id_ed25519]
ssh-gen:
	@SSH_KEY_TYPE="$(SSH_KEY_TYPE)" SSH_KEY_NAME="$(SSH_KEY_NAME)" \
		./vbox-ssh-manager/ssh-gen.sh

# Enroll SSH key on remote host (interactive)
# Usage: make ssh-enroll [SSH_HOST=192.168.50.100] [SSH_USER=skywalker] [SSH_PORT=22]
ssh-enroll:
	@TARGET_IP="$(SSH_HOST)" TARGET_SSH_USER="$(SSH_USER)" TARGET_SSH_PORT="$(SSH_PORT)" \
		./vbox-ssh-manager/ssh-remote-enroll.sh

# Run full SSH configuration (interactive)
# Usage: make ssh-config
ssh-config:
	@./vbox-ssh-manager/config.sh all

# Test SSH connection to a host
# Usage: make ssh-test SSH_HOST=192.168.50.100 [SSH_USER=skywalker] [SSH_PORT=22] [SSH_KEY=~/.ssh/id_rsa]
ssh-test:
ifndef SSH_HOST
	$(error SSH_HOST is required. Usage: make ssh-test SSH_HOST=192.168.50.100)
endif
	@echo "Testing SSH connection to $(SSH_HOST)..."
	@ssh -o BatchMode=yes \
		-o ConnectTimeout=5 \
		-o StrictHostKeyChecking=accept-new \
		$(if $(SSH_KEY),-i "$(SSH_KEY)") \
		-p $(or $(SSH_PORT),22) \
		$(or $(SSH_USER),$$USER)@$(SSH_HOST) \
		"echo '[OK] SSH connection successful to $$(hostname)'" \
		|| (echo "[ERROR] SSH connection failed"; exit 1)

# Copy ./scripts directory to remote host
# Usage: make ssh-copy-scripts [SSH_HOST=x.x.x.x] [SSH_USER=user] [SSH_PORT=22] [REMOTE_DIR=~/scripts]
# Defaults are loaded from vbox-ssh-manager/config.sh
ssh-copy-scripts:
	@source vbox-ssh-manager/config.sh && \
	HOST="$${SSH_HOST:-$$TARGET_IP}" && \
	USER="$${SSH_USER:-$$TARGET_SSH_USER}" && \
	PORT="$${SSH_PORT:-$$TARGET_SSH_PORT}" && \
	REMOTE="$${REMOTE_DIR:-~/scripts}" && \
	echo "Copying ./scripts to $$USER@$$HOST:$$REMOTE ..." && \
	ssh -p "$$PORT" "$$USER@$$HOST" "mkdir -p $$REMOTE" && \
	scp -r -P "$$PORT" ./scripts/* "$$USER@$$HOST:$$REMOTE/" && \
	echo "[OK] Scripts copied successfully to $$USER@$$HOST:$$REMOTE"
