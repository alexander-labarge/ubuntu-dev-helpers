.PHONY: help setup setup-secureboot dev-env vbox-manager docker langs packages clean build install test

# Default target
help:
	@echo "Development Server Helpers - Makefile"
	@echo ""
	@echo "Usage: make [TARGET]"
	@echo ""
	@echo "Main Targets:"
	@echo "  setup              - Full development environment setup"
	@echo "  setup-secureboot   - Full setup with VirtualBox Secure Boot configuration"
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
	@echo "Utility Targets:"
	@echo "  clean              - Remove build artifacts"
	@echo ""
	@echo "Examples:"
	@echo "  sudo make setup                # Full setup"
	@echo "  sudo make setup-secureboot     # Setup with Secure Boot"
	@echo "  sudo make docker               # Docker only"
	@echo "  make build                     # Build vbox-sb-manager"
	@echo "  sudo make install              # Install vbox-sb-manager"

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
