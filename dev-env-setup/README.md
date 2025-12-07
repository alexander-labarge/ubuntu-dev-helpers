# Development Environment Setup

Automated setup script for Ubuntu/Debian-based development environments.

## Quick Start

```bash
# Full setup (from project root)
sudo make setup

# Or run directly
sudo ./dev-server-setup.sh

# With Secure Boot configuration
sudo ./dev-server-setup.sh --secureboot
```

## What Gets Installed

- **Container Platforms:** Docker, Docker Compose, Apptainer
- **Languages:** Rust, Go, Java (OpenJDK 17/21), Python 3
- **Tools:** VS Code, Chrome, Git, build tools
- **VirtualBox:** With Secure Boot Manager
- **Monitoring:** btop, htop, neofetch
- **Utilities:** tmux, screen, tree, jq, ripgrep, etc.

## Installation Options

```bash
# Component-specific installations
./dev-server-setup.sh --docker-only          # Docker & Docker Compose
./dev-server-setup.sh --apptainer-only       # Apptainer only
./dev-server-setup.sh --packages-only        # Essential packages
./dev-server-setup.sh --vscode-only          # VS Code
./dev-server-setup.sh --chrome-only          # Google Chrome
./dev-server-setup.sh --rust-only            # Rust via rustup
./dev-server-setup.sh --go-only              # Go language
./dev-server-setup.sh --java-only            # Java (OpenJDK)
./dev-server-setup.sh --langs-only           # Rust + Go + Java
./dev-server-setup.sh --vbox-sb-manager-only # VBox Secure Boot Manager

# Display help
./dev-server-setup.sh --help
```

## Features

- ✅ Automated APT configuration and system updates
- ✅ Fixes common APT sandbox permission issues
- ✅ User group configuration (docker, vboxusers)
- ✅ Environment variable setup for all languages
- ✅ Modular installation (install only what you need)

## Post-Installation

After running the script:

1. **Log out and back in** (or run `newgrp docker && newgrp vboxusers`)
2. **Load environments:**
   ```bash
   source ~/.cargo/env              # Rust
   source /etc/profile.d/go.sh      # Go
   source /etc/profile.d/java.sh    # Java
   ```
3. **Test installations:**
   ```bash
   docker run hello-world           # Docker
   cargo --version                  # Rust
   go version                       # Go
   java -version                    # Java
   code .                           # VS Code
   ```

## Requirements

- Ubuntu 24.04.3 LTS or compatible Debian-based distribution
- Root/sudo access
- Internet connection

## Documentation

See [INSTALLATION.md](./INSTALLATION.md) for detailed installation guide.

See [main README](../README.md) for complete project documentation.
