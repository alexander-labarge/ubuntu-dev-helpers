#!/bin/bash
#===============================================================================
# GitLab EE Installation Script
# Installs GitLab Enterprise Edition on Ubuntu 24.04 (Noble)
# Reference: https://packages.gitlab.com/gitlab/gitlab-ee/packages/ubuntu/noble/gitlab-ee_18.4.5-ee.0_amd64.deb
#===============================================================================

set -euo pipefail

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
GITLAB_VERSION="18.4.5-ee.0"
GITLAB_PACKAGE="gitlab-ee_${GITLAB_VERSION}_amd64.deb"
GITLAB_URL="https://packages.gitlab.com/gitlab/gitlab-ee/packages/ubuntu/noble/${GITLAB_PACKAGE}/download.deb"
DOWNLOAD_DIR="/tmp/gitlab-install"

# Default external URL (can be overridden via environment variable)
EXTERNAL_URL="${GITLAB_EXTERNAL_URL:-http://$(hostname -f)}"

#-------------------------------------------------------------------------------
# Colors for output
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

#-------------------------------------------------------------------------------
# Logging functions
#-------------------------------------------------------------------------------
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${CYAN}${BOLD}=== $1 ===${NC}\n"; }

#-------------------------------------------------------------------------------
# Check if running as root
#-------------------------------------------------------------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# Check system requirements
#-------------------------------------------------------------------------------
check_requirements() {
    log_section "Checking System Requirements"

    # Check Ubuntu version
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        if [[ "$ID" != "ubuntu" ]]; then
            log_warning "This script is designed for Ubuntu. Detected: $ID"
        fi
        log_info "Detected OS: $PRETTY_NAME"
    fi

    # Check available memory (GitLab recommends at least 4GB)
    local total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_mem_gb=$((total_mem_kb / 1024 / 1024))
    
    if [[ $total_mem_gb -lt 4 ]]; then
        log_warning "GitLab recommends at least 4GB RAM. Detected: ${total_mem_gb}GB"
        log_warning "Installation will continue, but performance may be affected."
    else
        log_info "Memory check passed: ${total_mem_gb}GB available"
    fi

    # Check available disk space (GitLab recommends at least 10GB free)
    local free_space_gb=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [[ $free_space_gb -lt 10 ]]; then
        log_error "GitLab requires at least 10GB free disk space. Available: ${free_space_gb}GB"
        exit 1
    else
        log_info "Disk space check passed: ${free_space_gb}GB available"
    fi

    log_success "System requirements check completed"
}

#-------------------------------------------------------------------------------
# Install dependencies
#-------------------------------------------------------------------------------
install_dependencies() {
    log_section "Installing Dependencies"

    apt-get update -y

    # Install required packages
    apt-get install -y \
        curl \
        openssh-server \
        ca-certificates \
        tzdata \
        perl \
        postfix

    # Enable and start SSH
    systemctl enable ssh
    systemctl start ssh

    log_success "Dependencies installed"
}

#-------------------------------------------------------------------------------
# Configure Postfix for local mail
#-------------------------------------------------------------------------------
configure_postfix() {
    log_section "Configuring Postfix"

    # Configure postfix for local delivery only
    debconf-set-selections <<< "postfix postfix/mailname string $(hostname -f)"
    debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"

    # Reconfigure postfix non-interactively
    dpkg-reconfigure -f noninteractive postfix 2>/dev/null || true

    log_success "Postfix configured"
}

#-------------------------------------------------------------------------------
# Download GitLab package
#-------------------------------------------------------------------------------
download_gitlab() {
    log_section "Downloading GitLab EE ${GITLAB_VERSION}"

    mkdir -p "${DOWNLOAD_DIR}"
    cd "${DOWNLOAD_DIR}"

    if [[ -f "${GITLAB_PACKAGE}" ]]; then
        log_info "GitLab package already downloaded, verifying..."
        if dpkg-deb --info "${GITLAB_PACKAGE}" &>/dev/null; then
            log_success "Existing package is valid, skipping download"
            return 0
        else
            log_warning "Existing package is invalid, re-downloading..."
            rm -f "${GITLAB_PACKAGE}"
        fi
    fi

    log_info "Downloading from: ${GITLAB_URL}"
    curl -L -o "${GITLAB_PACKAGE}" "${GITLAB_URL}"

    # Verify download
    if [[ ! -f "${GITLAB_PACKAGE}" ]] || ! dpkg-deb --info "${GITLAB_PACKAGE}" &>/dev/null; then
        log_error "Failed to download GitLab package"
        exit 1
    fi

    log_success "GitLab package downloaded successfully"
}

#-------------------------------------------------------------------------------
# Install GitLab
#-------------------------------------------------------------------------------
install_gitlab() {
    log_section "Installing GitLab EE"

    cd "${DOWNLOAD_DIR}"

    # Set external URL environment variable for the installation
    export EXTERNAL_URL="${EXTERNAL_URL}"

    log_info "Installing with EXTERNAL_URL=${EXTERNAL_URL}"
    
    # Install the package
    dpkg -i "${GITLAB_PACKAGE}" || apt-get install -f -y

    log_success "GitLab package installed"
}

#-------------------------------------------------------------------------------
# Configure GitLab
#-------------------------------------------------------------------------------
configure_gitlab() {
    log_section "Configuring GitLab"

    # Update external URL in gitlab.rb if needed
    if [[ -f /etc/gitlab/gitlab.rb ]]; then
        # Backup original config
        cp /etc/gitlab/gitlab.rb /etc/gitlab/gitlab.rb.backup.$(date +%Y%m%d_%H%M%S)

        # Update external URL
        sed -i "s|^external_url.*|external_url '${EXTERNAL_URL}'|" /etc/gitlab/gitlab.rb

        # If external_url line doesn't exist, add it
        if ! grep -q "^external_url" /etc/gitlab/gitlab.rb; then
            echo "external_url '${EXTERNAL_URL}'" >> /etc/gitlab/gitlab.rb
        fi

        log_info "GitLab configuration updated"
    fi

    log_success "GitLab configured"
}

#-------------------------------------------------------------------------------
# Reconfigure GitLab
#-------------------------------------------------------------------------------
reconfigure_gitlab() {
    log_section "Running GitLab Reconfigure"

    log_info "This may take several minutes..."
    gitlab-ctl reconfigure

    log_success "GitLab reconfiguration completed"
}

#-------------------------------------------------------------------------------
# Get initial root password
#-------------------------------------------------------------------------------
get_root_password() {
    log_section "GitLab Initial Root Password"

    if [[ -f /etc/gitlab/initial_root_password ]]; then
        local password=$(grep "Password:" /etc/gitlab/initial_root_password | awk '{print $2}')
        echo ""
        log_info "Initial root password (valid for 24 hours):"
        echo -e "${YELLOW}${BOLD}${password}${NC}"
        echo ""
        log_warning "This password file will be automatically deleted after 24 hours."
        log_warning "Please change the root password after your first login!"
    else
        log_warning "Initial root password file not found."
        log_info "You may need to reset the root password using:"
        echo "    gitlab-rake 'gitlab:password:reset[root]'"
    fi
}

#-------------------------------------------------------------------------------
# Display post-installation information
#-------------------------------------------------------------------------------
show_post_install_info() {
    log_section "Installation Complete"

    echo -e "${GREEN}${BOLD}GitLab EE ${GITLAB_VERSION} has been successfully installed!${NC}"
    echo ""
    echo -e "${CYAN}Access GitLab:${NC}"
    echo "    URL: ${EXTERNAL_URL}"
    echo "    Username: root"
    echo ""
    echo -e "${CYAN}Useful Commands:${NC}"
    echo "    gitlab-ctl status        - Check service status"
    echo "    gitlab-ctl start         - Start all services"
    echo "    gitlab-ctl stop          - Stop all services"
    echo "    gitlab-ctl restart       - Restart all services"
    echo "    gitlab-ctl reconfigure   - Apply configuration changes"
    echo "    gitlab-ctl tail          - View all logs"
    echo ""
    echo -e "${CYAN}Configuration Files:${NC}"
    echo "    Main config: /etc/gitlab/gitlab.rb"
    echo "    After editing, run: gitlab-ctl reconfigure"
    echo ""
    echo -e "${CYAN}Data Locations:${NC}"
    echo "    Git repositories: /var/opt/gitlab/git-data"
    echo "    Database: /var/opt/gitlab/postgresql"
    echo "    Uploads: /var/opt/gitlab/gitlab-rails/uploads"
    echo ""
    
    # Show firewall hints
    echo -e "${CYAN}Firewall Configuration (if needed):${NC}"
    echo "    sudo ufw allow http"
    echo "    sudo ufw allow https"
    echo "    sudo ufw allow ssh"
    echo ""
}

#-------------------------------------------------------------------------------
# Cleanup
#-------------------------------------------------------------------------------
cleanup() {
    log_section "Cleaning Up"

    # Remove downloaded package to save space
    if [[ -d "${DOWNLOAD_DIR}" ]]; then
        rm -rf "${DOWNLOAD_DIR}"
        log_info "Removed temporary download directory"
    fi

    # Clean apt cache
    apt-get clean
    apt-get autoremove -y

    log_success "Cleanup completed"
}

#-------------------------------------------------------------------------------
# Main execution
#-------------------------------------------------------------------------------
main() {
    log_section "GitLab EE Installation Script"
    log_info "Version: ${GITLAB_VERSION}"
    log_info "Target URL: ${EXTERNAL_URL}"
    echo ""

    check_root
    check_requirements
    install_dependencies
    configure_postfix
    download_gitlab
    install_gitlab
    configure_gitlab
    reconfigure_gitlab
    get_root_password
    cleanup
    show_post_install_info

    log_success "GitLab installation completed successfully!"
}

# Run main function
main "$@"
