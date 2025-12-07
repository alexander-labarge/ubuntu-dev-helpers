.PHONY: help setup setup-secureboot dev-env vbox-manager docker langs packages clean build install test
.PHONY: iso-download vm-create vm-list vm-running vm-start vm-stop vm-delete vm-snapshot vm-restore vm-clone vm-info vm-eject

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
	@echo "Utility Targets:"
	@echo "  clean              - Remove build artifacts"
	@echo ""
	@echo "Examples:"
	@echo "  sudo make setup                      # Full setup"
	@echo "  sudo make setup-secureboot           # Setup with Secure Boot"
	@echo "  make iso-download                    # Download Ubuntu ISOs"
	@echo "  make vm-create VM_NAME=dev-server VM_IP=192.168.50.100"
	@echo "  make vm-create VM_NAME=desktop VM_TYPE=desktop"
	@echo "  make vm-start VM_NAME=dev-server"
	@echo "  make vm-stop VM_NAME=dev-server"
	@echo "  make vm-snapshot VM_NAME=dev-server SNAP_NAME=clean-install"

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
		$(if $(filter 1,$(VM_NO_START)),--no-start)

# List all VMs
vm-list:
	@VBoxManage list vms

# List running VMs
vm-running:
	@VBoxManage list runningvms

# Start a VM (headless by default) - automatically disables KVM if needed
# Usage: make vm-start VM_NAME=myvm [VM_GUI=1]
vm-start:
ifndef VM_NAME
	$(error VM_NAME is required. Usage: make vm-start VM_NAME=myvm)
endif
	@./vbox-factory/start-vm.sh "$(VM_NAME)" $(if $(VM_GUI),gui,headless)

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

# Eject ISO from VM
# Usage: make vm-eject VM_NAME=myvm
vm-eject:
ifndef VM_NAME
	$(error VM_NAME is required. Usage: make vm-eject VM_NAME=myvm)
endif
	@VBoxManage storageattach "$(VM_NAME)" --storagectl "SATA" --port 1 --device 0 --type dvddrive --medium emptydrive
