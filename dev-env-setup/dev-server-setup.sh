#!/bin/bash
#===============================================================================
# Development Server Setup Script
# A comprehensive setup script for Ubuntu/Debian-based development environments
# Includes: Docker, Apptainer, development tools, and essential packages
#===============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${CYAN}${BOLD}=== $1 ===${NC}\n"; }

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Get the actual user (even when running with sudo)
get_real_user() {
    if [[ -n "${SUDO_USER:-}" ]]; then
        REAL_USER="$SUDO_USER"
        REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    else
        REAL_USER="$USER"
        REAL_HOME="$HOME"
    fi
    log_info "Running setup for user: $REAL_USER (home: $REAL_HOME)"
}

# Fix apt sandbox permissions error
fix_apt_sandbox() {
    log_section "Fixing APT Sandbox Permissions"
    
    # Fix the _apt user permissions issue
    if id "_apt" &>/dev/null; then
        # Ensure _apt user can access the necessary directories
        chown -R _apt:root /var/cache/apt/archives/partial/ 2>/dev/null || true
        chmod 700 /var/cache/apt/archives/partial/ 2>/dev/null || true
    fi
    
    # Fix potential sandbox issues with AppArmor
    if [[ -f /etc/apparmor.d/usr.bin.apt ]]; then
        log_info "AppArmor apt profile found, ensuring it's not blocking"
    fi
    
    # Create apt configuration to handle sandbox issues
    cat > /etc/apt/apt.conf.d/99sandbox-fix <<EOF
# Fix sandbox permissions for apt
APT::Sandbox::Seccomp "false";
EOF
    
    # Alternative: set proper permissions on apt directories
    mkdir -p /var/lib/apt/lists/partial
    chmod 755 /var/lib/apt/lists
    chmod 700 /var/lib/apt/lists/partial
    chown root:root /var/lib/apt/lists/partial
    
    log_success "APT sandbox permissions fixed"
}

# Update system packages
update_system() {
    log_section "Updating System Packages"
    
    apt-get update -y
    apt-get upgrade -y
    apt-get dist-upgrade -y
    
    log_success "System packages updated"
}

# Install essential development packages
install_essential_packages() {
    log_section "Installing Essential Development Packages"
    
    # Pre-accept VirtualBox license
    echo virtualbox-ext-pack virtualbox-ext-pack/license select true | debconf-set-selections
    
    # Core development tools
    local packages=(
        # Build essentials
        build-essential
        make
        cmake
        gcc
        g++
        gdb
        
        # Python
        python3-full
        python3-pip
        python3-venv
        python3-dev
        
        # Editors and tools
        vim
        neovim
        nano
        
        # System monitoring
        btop
        htop
        neofetch
        iotop
        iftop
        
        # Version control
        git
        git-lfs
        
        # Networking tools
        curl
        wget
        net-tools
        openssh-server
        
        # Archive tools
        zip
        unzip
        tar
        gzip
        
        # System utilities
        tmux
        screen
        tree
        jq
        ripgrep
        fd-find
        bat
        
        # VirtualBox
        virtualbox
        virtualbox-ext-pack
        virtualbox-guest-additions-iso
        virtualbox-guest-utils
        virtualbox-dkms
        
        # Secure Boot signing tools (for VirtualBox)
        mokutil
        sbsigntool
        openssl
        
        # Java Development
        default-jdk
        default-jre
        maven
        gradle
        
        # Additional development libraries
        libssl-dev
        libffi-dev
        zlib1g-dev
        libbz2-dev
        libreadline-dev
        libsqlite3-dev
        libncurses5-dev
        libncursesw5-dev
        xz-utils
        tk-dev
        liblzma-dev
    )
    
    log_info "Installing packages: ${packages[*]}"
    
    # Install packages, continue even if some fail
    for pkg in "${packages[@]}"; do
        if apt-get install -y "$pkg" 2>/dev/null; then
            log_success "Installed: $pkg"
        else
            log_warning "Failed to install: $pkg (may not be available)"
        fi
    done
    
    log_success "Essential packages installation completed"
}

# Install VS Code
install_vscode() {
    log_section "Installing Visual Studio Code"
    
    # Check if VS Code is already installed
    if command -v code &>/dev/null; then
        log_warning "VS Code is already installed"
        dpkg-query -W -f='${Version}\n' code 2>/dev/null || log_info "Version check skipped (cannot run as root)"
        return 0
    fi
    
    log_info "Adding Microsoft GPG key..."
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /usr/share/keyrings/microsoft.gpg
    chmod 644 /usr/share/keyrings/microsoft.gpg
    
    log_info "Adding VS Code repository..."
    cat > /etc/apt/sources.list.d/vscode.sources <<EOF
### THIS FILE IS AUTOMATICALLY CONFIGURED ###
# You may comment out this entry, but any other modifications may be lost.
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF
    
    log_info "Installing VS Code..."
    apt-get update -y
    apt-get install -y code
    
    dpkg-query -W -f='${Version}\n' code 2>/dev/null || true
    log_success "VS Code installed successfully"
}

# Install Google Chrome
install_chrome() {
    log_section "Installing Google Chrome"
    
    # Check if Chrome is already installed
    if command -v google-chrome &>/dev/null || command -v google-chrome-stable &>/dev/null; then
        log_warning "Google Chrome is already installed"
        dpkg-query -W -f='${Version}\n' google-chrome-stable 2>/dev/null || log_info "Version check skipped"
        return 0
    fi
    
    log_info "Adding Google GPG key..."
    wget -qO- https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor > /usr/share/keyrings/google-chrome.gpg
    chmod 644 /usr/share/keyrings/google-chrome.gpg
    
    log_info "Adding Google Chrome repository..."
    cat > /etc/apt/sources.list.d/google-chrome.list <<EOF
### THIS FILE IS AUTOMATICALLY CONFIGURED ###
# You may comment out this entry, but any other modifications may be lost.
deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main
EOF
    
    log_info "Installing Google Chrome..."
    apt-get update -y
    apt-get install -y google-chrome-stable
    
    dpkg-query -W -f='${Version}\n' google-chrome-stable 2>/dev/null || true
    log_success "Google Chrome installed successfully"
}

# Install Docker
install_docker() {
    log_section "Installing Docker"
    
    # Check if Docker is already installed
    if command -v docker &>/dev/null; then
        log_warning "Docker is already installed"
        docker --version
        # Still ensure user is in docker group
        usermod -aG docker "$REAL_USER" 2>/dev/null || true
        return 0
    fi
    
    # Remove old Docker installations
    log_info "Removing old Docker versions (if any)..."
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Install prerequisites
    log_info "Installing Docker prerequisites..."
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Add Docker's official GPG key
    log_info "Adding Docker GPG key..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Set up the repository
    log_info "Setting up Docker repository..."
    
    # Detect distribution
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO_ID="${ID:-ubuntu}"
        DISTRO_CODENAME="${VERSION_CODENAME:-$(lsb_release -cs 2>/dev/null || echo 'jammy')}"
    else
        DISTRO_ID="ubuntu"
        DISTRO_CODENAME="jammy"
    fi
    
    # Use Ubuntu repo for Ubuntu-based distros, Debian for others
    if [[ "$DISTRO_ID" == "ubuntu" || "$DISTRO_ID" == "linuxmint" || "$DISTRO_ID" == "pop" ]]; then
        DOCKER_REPO="https://download.docker.com/linux/ubuntu"
        # Map derivative codenames to Ubuntu codenames if needed
        case "$DISTRO_CODENAME" in
            vanessa|vera|victoria|virginia) DISTRO_CODENAME="jammy" ;;
            wilma) DISTRO_CODENAME="noble" ;;
        esac
    else
        DOCKER_REPO="https://download.docker.com/linux/debian"
    fi
    
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] $DOCKER_REPO $DISTRO_CODENAME stable" > /etc/apt/sources.list.d/docker.list
    
    # Install Docker Engine
    log_info "Installing Docker Engine..."
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Add user to docker group
    log_info "Adding $REAL_USER to docker group..."
    usermod -aG docker "$REAL_USER"
    
    # Enable and start Docker
    systemctl enable docker
    systemctl start docker
    
    # Verify installation
    docker --version
    log_success "Docker installed successfully"
    log_warning "Please log out and back in for docker group changes to take effect"
}

# Add user to required groups
add_user_to_groups() {
    log_section "Adding User to Required Groups"
    
    local groups_to_add=("docker" "vboxusers")
    
    for group in "${groups_to_add[@]}"; do
        if getent group "$group" &>/dev/null; then
            if id -nG "$REAL_USER" | grep -qw "$group"; then
                log_info "$REAL_USER is already in $group group"
            else
                usermod -aG "$group" "$REAL_USER"
                log_success "Added $REAL_USER to $group group"
            fi
        else
            log_warning "Group $group does not exist yet (will be created when package is installed)"
        fi
    done
    
    log_success "User group configuration completed"
    log_warning "Please log out and back in for group changes to take effect"
}

# Install Docker Compose (standalone version)
install_docker_compose() {
    log_section "Installing Docker Compose (Standalone)"
    
    # Check if already installed
    if command -v docker-compose &>/dev/null; then
        log_warning "Docker Compose standalone is already installed"
        docker-compose --version
        return 0
    fi
    
    # Get latest version
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    
    if [[ -z "$COMPOSE_VERSION" ]]; then
        COMPOSE_VERSION="v2.24.0"
        log_warning "Could not fetch latest version, using $COMPOSE_VERSION"
    fi
    
    log_info "Installing Docker Compose $COMPOSE_VERSION..."
    
    # Download Docker Compose
    curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # Create symlink
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    docker-compose --version
    log_success "Docker Compose installed successfully"
}

# Install Apptainer (formerly Singularity)
install_apptainer() {
    log_section "Installing Apptainer"
    
    # Check if Apptainer is already installed
    if command -v apptainer &>/dev/null; then
        log_warning "Apptainer is already installed"
        apptainer --version
        return 0
    fi
    
    # Install prerequisites
    log_info "Installing Apptainer prerequisites..."
    apt-get install -y \
        software-properties-common \
        dirmngr \
        gpg-agent
    
    # Add Apptainer repository
    log_info "Adding Apptainer repository..."
    
    # Method 1: Try using the official PPA (for Ubuntu)
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" == "ubuntu" || "$ID_LIKE" == *"ubuntu"* ]]; then
            add-apt-repository -y ppa:apptainer/ppa
            apt-get update -y
            apt-get install -y apptainer
            
            if command -v apptainer &>/dev/null; then
                apptainer --version
                log_success "Apptainer installed successfully via PPA"
                return 0
            fi
        fi
    fi
    
    # Method 2: Install from GitHub releases (fallback)
    log_info "Installing Apptainer from GitHub releases..."
    
    # Get latest release
    APPTAINER_VERSION=$(curl -s https://api.github.com/repos/apptainer/apptainer/releases/latest | grep '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\1/')
    
    if [[ -z "$APPTAINER_VERSION" ]]; then
        APPTAINER_VERSION="1.3.0"
        log_warning "Could not fetch latest version, using $APPTAINER_VERSION"
    fi
    
    log_info "Downloading Apptainer $APPTAINER_VERSION..."
    
    # Determine architecture
    ARCH=$(dpkg --print-architecture)
    
    # Download and install .deb package
    local DEB_URL="https://github.com/apptainer/apptainer/releases/download/v${APPTAINER_VERSION}/apptainer_${APPTAINER_VERSION}_${ARCH}.deb"
    
    cd /tmp
    wget -q "$DEB_URL" -O apptainer.deb || {
        log_warning "Direct .deb download failed, trying alternative method..."
        # Alternative: try without architecture suffix
        DEB_URL="https://github.com/apptainer/apptainer/releases/download/v${APPTAINER_VERSION}/apptainer_${APPTAINER_VERSION}_amd64.deb"
        wget -q "$DEB_URL" -O apptainer.deb
    }
    
    apt-get install -y ./apptainer.deb
    rm -f apptainer.deb
    
    apptainer --version
    log_success "Apptainer installed successfully"
}

# Install additional container tools
install_container_tools() {
    log_section "Installing Additional Container Tools"
    
    # Install Podman (rootless containers)
    log_info "Installing Podman..."
    apt-get install -y podman 2>/dev/null || log_warning "Podman not available in repositories"
    
    # Install buildah (container builder)
    log_info "Installing Buildah..."
    apt-get install -y buildah 2>/dev/null || log_warning "Buildah not available in repositories"
    
    # Install skopeo (container image tool)
    log_info "Installing Skopeo..."
    apt-get install -y skopeo 2>/dev/null || log_warning "Skopeo not available in repositories"
    
    log_success "Additional container tools installation completed"
}

# Configure system settings for development
configure_system() {
    log_section "Configuring System Settings"
    
    # Increase inotify watchers for IDEs
    log_info "Increasing inotify watchers..."
    echo "fs.inotify.max_user_watches=524288" > /etc/sysctl.d/99-inotify.conf
    sysctl -p /etc/sysctl.d/99-inotify.conf 2>/dev/null || true
    
    # Configure Git global settings for user
    log_info "Setting up Git configuration..."
    sudo -u "$REAL_USER" git config --global init.defaultBranch main 2>/dev/null || true
    sudo -u "$REAL_USER" git config --global pull.rebase false 2>/dev/null || true
    
    # Enable BBR congestion control (improves network performance)
    log_info "Enabling BBR congestion control..."
    if modprobe tcp_bbr 2>/dev/null; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.d/99-bbr.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.d/99-bbr.conf
        sysctl -p /etc/sysctl.d/99-bbr.conf 2>/dev/null || true
    fi
    
    # Configure SSH server (if installed)
    if [[ -f /etc/ssh/sshd_config ]]; then
        log_info "Configuring SSH server..."
        systemctl enable ssh 2>/dev/null || systemctl enable sshd 2>/dev/null || true
        systemctl start ssh 2>/dev/null || systemctl start sshd 2>/dev/null || true
    fi
    
    log_success "System configuration completed"
}

# Setup Python development environment
setup_python_env() {
    log_section "Setting Up Python Development Environment"
    
    # Create global Python virtual environment directory
    local VENV_DIR="$REAL_HOME/.venvs"
    sudo -u "$REAL_USER" mkdir -p "$VENV_DIR"
    
    log_info "Python environment ready. Create virtual environments with:"
    log_info "  python3 -m venv ~/.venvs/myenv"
    log_info "  source ~/.venvs/myenv/bin/activate"
    
    log_success "Python development environment setup completed"
}

# Install Rust via rustup
install_rust() {
    log_section "Installing Rust (via rustup)"
    
    # Check if Rust is already installed for the user
    if sudo -u "$REAL_USER" bash -c 'source $HOME/.cargo/env 2>/dev/null && command -v rustc' &>/dev/null; then
        log_warning "Rust is already installed for $REAL_USER"
        sudo -u "$REAL_USER" bash -c 'source $HOME/.cargo/env && rustc --version'
        return 0
    fi
    
    log_info "Installing Rust for user $REAL_USER..."
    
    # Download and run rustup installer as the real user (non-interactive)
    sudo -u "$REAL_USER" bash -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y'
    
    # Verify installation
    if sudo -u "$REAL_USER" bash -c 'source $HOME/.cargo/env && rustc --version'; then
        log_success "Rust installed successfully"
        
        # Install common Rust tools
        log_info "Installing common Rust tools..."
        sudo -u "$REAL_USER" bash -c 'source $HOME/.cargo/env && rustup component add rustfmt clippy' || true
        
        log_info "Rust environment ready. Add to PATH with: source ~/.cargo/env"
    else
        log_error "Rust installation failed"
        return 1
    fi
}

# Install Go
install_go() {
    log_section "Installing Go"
    
    # Check if Go is already installed
    if command -v go &>/dev/null; then
        log_warning "Go is already installed"
        go version
        return 0
    fi
    
    # Get latest Go version
    local GO_VERSION
    GO_VERSION=$(curl -s https://go.dev/VERSION?m=text | head -1)
    
    if [[ -z "$GO_VERSION" ]]; then
        GO_VERSION="go1.22.0"
        log_warning "Could not fetch latest version, using $GO_VERSION"
    fi
    
    log_info "Installing $GO_VERSION..."
    
    # Download Go
    local GO_ARCHIVE="${GO_VERSION}.linux-amd64.tar.gz"
    cd /tmp
    wget -q "https://go.dev/dl/${GO_ARCHIVE}" -O go.tar.gz || {
        log_error "Failed to download Go"
        return 1
    }
    
    # Remove old installation and extract new one
    rm -rf /usr/local/go
    tar -C /usr/local -xzf go.tar.gz
    rm -f go.tar.gz
    
    # Add to system PATH
    cat > /etc/profile.d/go.sh <<'EOF'
export PATH=$PATH:/usr/local/go/bin
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin
EOF
    chmod +x /etc/profile.d/go.sh
    
    # Create GOPATH for user
    sudo -u "$REAL_USER" mkdir -p "$REAL_HOME/go/{bin,src,pkg}"
    
    # Verify installation
    export PATH=$PATH:/usr/local/go/bin
    if go version; then
        log_success "Go installed successfully"
        log_info "Go environment ready. Run 'source /etc/profile.d/go.sh' or log out/in"
    else
        log_error "Go installation failed"
        return 1
    fi
}

# Install Java (OpenJDK) - additional versions
install_java() {
    log_section "Installing Java Development Kit"
    
    # Check if Java is already installed
    if command -v java &>/dev/null; then
        log_warning "Java is already installed"
        java -version 2>&1 | head -1
        return 0
    fi
    
    log_info "Installing OpenJDK and build tools..."
    
    # Install multiple JDK versions
    apt-get install -y \
        openjdk-17-jdk \
        openjdk-21-jdk \
        maven \
        gradle \
        ant \
        2>/dev/null || {
            # Fallback to default-jdk if specific versions unavailable
            apt-get install -y default-jdk maven gradle || true
        }
    
    # Set JAVA_HOME
    local JAVA_HOME_PATH
    JAVA_HOME_PATH=$(dirname $(dirname $(readlink -f $(which java))))
    
    cat > /etc/profile.d/java.sh <<EOF
export JAVA_HOME=$JAVA_HOME_PATH
export PATH=\$PATH:\$JAVA_HOME/bin
EOF
    chmod +x /etc/profile.d/java.sh
    
    if java -version 2>&1 | head -1; then
        log_success "Java installed successfully"
        log_info "JAVA_HOME set to: $JAVA_HOME_PATH"
    else
        log_error "Java installation failed"
        return 1
    fi
}

# Build and install VirtualBox Secure Boot Manager
install_vbox_secureboot_manager() {
    log_section "Building VirtualBox Secure Boot Manager"
    
    # Check if already installed
    if command -v virtualbox-sb-manager &>/dev/null; then
        log_warning "VirtualBox Secure Boot Manager is already installed"
        virtualbox-sb-manager --version 2>/dev/null || true
        return 0
    fi
    
    # Check if Rust is available
    if ! sudo -u "$REAL_USER" bash -c 'source $HOME/.cargo/env 2>/dev/null && command -v cargo' &>/dev/null; then
        log_warning "Rust not installed, installing first..."
        install_rust
    fi
    
    # Get the script directory and project root
    local SCRIPT_DIR
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local PROJECT_ROOT
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    local VBOX_MANAGER_DIR="$PROJECT_ROOT/vbox-sb-manager"
    
    if [[ ! -f "$VBOX_MANAGER_DIR/Cargo.toml" ]]; then
        log_warning "Cargo.toml not found in $VBOX_MANAGER_DIR"
        log_info "VirtualBox Secure Boot Manager source not found, skipping build"
        return 0
    fi
    
    log_info "Building VirtualBox Secure Boot Manager from source..."
    log_info "Project location: $VBOX_MANAGER_DIR"
    
    # Build the project as the real user
    cd "$VBOX_MANAGER_DIR"
    if sudo -u "$REAL_USER" bash -c "source \$HOME/.cargo/env && cargo build --release"; then
        log_success "Build completed successfully"
        
        # Install the binary (binary name is virtualbox-sb-manager from Cargo.toml)
        if [[ -f "$VBOX_MANAGER_DIR/target/release/virtualbox-sb-manager" ]]; then
            cp "$VBOX_MANAGER_DIR/target/release/virtualbox-sb-manager" /usr/local/bin/
            chmod +x /usr/local/bin/virtualbox-sb-manager
            log_success "Installed virtualbox-sb-manager to /usr/local/bin/"
        else
            log_error "Binary not found after build"
            return 1
        fi
    else
        log_error "Build failed"
        return 1
    fi
}

# Configure VirtualBox for Secure Boot (optional)
configure_secureboot() {
    log_section "Configuring VirtualBox for Secure Boot"
    
    # Check if Secure Boot is enabled
    if ! mokutil --sb-state 2>/dev/null | grep -q "SecureBoot enabled"; then
        log_warning "Secure Boot is not enabled on this system"
        log_info "Skipping Secure Boot configuration"
        return 0
    fi
    
    log_info "Secure Boot is enabled, configuring VirtualBox module signing..."
    
    # Check if virtualbox-sb-manager is available
    if command -v virtualbox-sb-manager &>/dev/null; then
        log_info "Using VirtualBox Secure Boot Manager for configuration..."
        log_info "Run 'sudo virtualbox-sb-manager setup' to complete Secure Boot setup"
        log_info "This will:"
        log_info "  1. Generate signing keys (MOK)"
        log_info "  2. Sign VirtualBox kernel modules"
        log_info "  3. Enroll the key with MOK (requires reboot)"
        echo ""
        log_warning "Interactive setup required. Run manually after script completes:"
        log_warning "  sudo virtualbox-sb-manager setup"
    else
        log_warning "VirtualBox Secure Boot Manager not available"
        log_info "Install it with: --secureboot flag or manually build from source"
    fi
}

# Display system information
display_system_info() {
    log_section "System Information"
    
    # Run neofetch if available
    if command -v neofetch &>/dev/null; then
        neofetch
    fi
    
    echo ""
    log_info "Docker version: $(docker --version 2>/dev/null || echo 'Not installed')"
    log_info "Docker Compose version: $(docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || echo 'Not installed')"
    log_info "Apptainer version: $(apptainer --version 2>/dev/null || echo 'Not installed')"
    log_info "VS Code version: $(dpkg-query -W -f='${Version}' code 2>/dev/null || echo 'Not installed')"
    log_info "Chrome version: $(dpkg-query -W -f='${Version}' google-chrome-stable 2>/dev/null || echo 'Not installed')"
    log_info "Python version: $(python3 --version 2>/dev/null || echo 'Not installed')"
    log_info "Rust version: $(sudo -u "$REAL_USER" bash -c 'source $HOME/.cargo/env 2>/dev/null && rustc --version 2>/dev/null' || echo 'Not installed')"
    log_info "Go version: $(go version 2>/dev/null || echo 'Not installed')"
    log_info "Java version: $(java -version 2>&1 | head -1 || echo 'Not installed')"
    log_info "Git version: $(git --version 2>/dev/null || echo 'Not installed')"
    log_info "VBox SB Manager: $(virtualbox-sb-manager --version 2>/dev/null || echo 'Not installed')"
    
    echo ""
}

# Cleanup
cleanup() {
    log_section "Cleaning Up"
    
    apt-get autoremove -y
    apt-get autoclean -y
    
    log_success "Cleanup completed"
}

# Display completion message
display_completion_message() {
    log_section "Setup Complete!"
    
    echo -e "${GREEN}${BOLD}"
    echo "+==============================================================+"
    echo "|           Development Server Setup Complete!                 |"
    echo "+==============================================================+"
    echo -e "${NC}"
    
    echo -e "${YELLOW}Important Notes:${NC}"
    echo "  1. Log out and back in for group changes to take effect (docker, vboxusers)"
    echo "  2. Or run: newgrp docker && newgrp vboxusers"
    echo ""
    echo -e "${CYAN}Installed Components:${NC}"
    echo "  - Docker Engine + Docker Compose"
    echo "  - Apptainer (Singularity)"
    echo "  - Visual Studio Code"
    echo "  - Google Chrome (stable)"
    echo "  - Python 3 with venv support"
    echo "  - Build tools (gcc, g++, make, cmake)"
    echo "  - VirtualBox with extensions"
    echo "  - System monitoring tools (btop, htop)"
    echo "  - Various development utilities"
    echo ""
    echo -e "${CYAN}Programming Languages:${NC}"
    echo "  - Rust (via rustup) with rustfmt and clippy"
    echo "  - Go (system-wide installation)"
    echo "  - Java (OpenJDK 17/21) with Maven and Gradle"
    echo "  - Python 3 with pip and venv"
    echo ""
    echo -e "${CYAN}Quick Commands:${NC}"
    echo "  docker run hello-world          # Test Docker"
    echo "  apptainer --version             # Check Apptainer"
    echo "  code .                          # Open VS Code"
    echo "  google-chrome                   # Open Chrome"
    echo "  cargo new myproject             # Create Rust project"
    echo "  go mod init myproject           # Create Go project"
    echo "  mvn archetype:generate          # Create Maven project"
    echo "  python3 -m venv myenv           # Create Python venv"
    echo "  btop                            # System monitor"
    echo "  neofetch                        # System info"
    echo ""
    echo -e "${CYAN}User Groups:${NC}"
    echo "  User $REAL_USER added to: docker, vboxusers"
    echo ""
    echo -e "${CYAN}Environment Setup:${NC}"
    echo "  source ~/.cargo/env             # Load Rust environment"
    echo "  source /etc/profile.d/go.sh     # Load Go environment"
    echo "  source /etc/profile.d/java.sh   # Load Java environment"
    echo ""
}

# Main function
main() {
    local SETUP_SECUREBOOT=false
    
    # Parse arguments for main
    for arg in "$@"; do
        if [[ "$arg" == "--secureboot" ]]; then
            SETUP_SECUREBOOT=true
        fi
    done
    
    echo -e "${CYAN}${BOLD}"
    echo "+===============================================+"
    echo "|       Development Server Setup Script         |"
    echo "|   Docker - Apptainer - Rust - Go - Java       |"
    echo "+===============================================+"
    echo -e "${NC}"
    
    # Pre-flight checks
    check_root
    get_real_user
    
    # Run setup steps
    fix_apt_sandbox
    update_system
    install_essential_packages
    install_vscode
    install_chrome
    install_docker
    install_docker_compose
    install_apptainer
    install_container_tools
    add_user_to_groups
    configure_system
    setup_python_env
    
    # Install programming languages
    install_rust
    install_go
    install_java
    
    # Build and install VirtualBox Secure Boot Manager
    install_vbox_secureboot_manager
    
    # Configure Secure Boot if requested
    if [[ "$SETUP_SECUREBOOT" == true ]]; then
        configure_secureboot
    fi
    
    cleanup
    
    # Display results
    display_system_info
    display_completion_message
    
    # Show Secure Boot info if flag was used AND system supports it
    if [[ "$SETUP_SECUREBOOT" == true ]]; then
        if mokutil --sb-state 2>/dev/null | grep -q "SecureBoot enabled"; then
            log_section "Secure Boot Configuration"
            log_info "Secure Boot is enabled on this system."
            log_info "Run 'sudo virtualbox-sb-manager setup' to complete configuration."
        else
            log_section "Secure Boot Configuration"
            log_warning "Secure Boot is NOT enabled on this system."
            log_info "VirtualBox modules will work without signing."
            log_info "If you enable Secure Boot later, run: sudo virtualbox-sb-manager setup"
        fi
    fi
}

# Handle script arguments
case "${1:-}" in
    --docker-only)
        check_root
        get_real_user
        fix_apt_sandbox
        install_docker
        install_docker_compose
        ;;
    --apptainer-only)
        check_root
        get_real_user
        fix_apt_sandbox
        install_apptainer
        ;;
    --packages-only)
        check_root
        get_real_user
        fix_apt_sandbox
        install_essential_packages
        ;;
    --vscode-only)
        check_root
        get_real_user
        fix_apt_sandbox
        install_vscode
        ;;
    --chrome-only)
        check_root
        get_real_user
        fix_apt_sandbox
        install_chrome
        ;;
    --rust-only)
        check_root
        get_real_user
        fix_apt_sandbox
        install_rust
        ;;
    --go-only)
        check_root
        get_real_user
        fix_apt_sandbox
        install_go
        ;;
    --java-only)
        check_root
        get_real_user
        fix_apt_sandbox
        install_java
        ;;
    --langs-only)
        check_root
        get_real_user
        fix_apt_sandbox
        install_rust
        install_go
        install_java
        ;;
    --vbox-sb-manager-only)
        check_root
        get_real_user
        fix_apt_sandbox
        install_rust
        install_vbox_secureboot_manager
        ;;
    --secureboot)
        main --secureboot
        ;;
    --help|-h)
        echo "Usage: $0 [OPTION]"
        echo ""
        echo "Options:"
        echo "  --docker-only          Install only Docker and Docker Compose"
        echo "  --apptainer-only       Install only Apptainer"
        echo "  --packages-only        Install only essential packages"
        echo "  --vscode-only          Install only VS Code"
        echo "  --chrome-only          Install only Google Chrome"
        echo "  --rust-only            Install only Rust (via rustup)"
        echo "  --go-only              Install only Go"
        echo "  --java-only            Install only Java (OpenJDK)"
        echo "  --langs-only           Install Rust, Go, and Java only"
        echo "  --vbox-sb-manager-only Build and install VirtualBox Secure Boot Manager"
        echo "  --secureboot           Full setup + configure VirtualBox for Secure Boot"
        echo "  --help, -h             Display this help message"
        echo ""
        echo "Without options, the script will perform a full setup."
        echo ""
        echo "Examples:"
        echo "  sudo $0                   # Full development environment setup"
        echo "  sudo $0 --secureboot      # Full setup with Secure Boot configuration"
        echo "  sudo $0 --langs-only      # Install Rust, Go, Java only"
        echo "  sudo $0 --docker-only     # Install only Docker"
        exit 0
        ;;
    "")
        main
        ;;
    *)
        echo "Unknown option: $1"
        echo "Use --help for usage information."
        exit 1
        ;;
esac

exit 0
