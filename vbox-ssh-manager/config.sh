#!/bin/bash
# config.sh - Interactive configuration for vbox-ssh-manager
# This script sets defaults and allows interactive updates before execution

set -euo pipefail

# ==============================================================================
# Colors for output
# ==============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# ==============================================================================
# Default Configuration - SSH Target
# ==============================================================================
TARGET_IP="${TARGET_IP:-192.168.50.89}"
TARGET_SSH_PORT="${TARGET_SSH_PORT:-22}"
TARGET_SSH_USER="${TARGET_SSH_USER:-skywalker}"
TARGET_HOSTNAME="${TARGET_HOSTNAME:-}"  # Optional: set hostname on remote

# ==============================================================================
# Default Configuration - SSH Key Generation (ssh-gen)
# ==============================================================================
SSH_KEY_DIR="${SSH_KEY_DIR:-$HOME/.ssh}"
SSH_KEY_NAME="${SSH_KEY_NAME:-id_rsa}"
SSH_KEY_PATH="${SSH_KEY_PATH:-$SSH_KEY_DIR/$SSH_KEY_NAME}"
SSH_KEY_TYPE="${SSH_KEY_TYPE:-ed25519}"           # ed25519, rsa, ecdsa
SSH_KEY_BITS="${SSH_KEY_BITS:-4096}"              # For RSA keys
SSH_KEY_COMMENT="${SSH_KEY_COMMENT:-$USER@$(hostname)}"
SSH_KEY_PASSPHRASE="${SSH_KEY_PASSPHRASE:-}"      # Empty = prompt, "none" = no passphrase

# ==============================================================================
# Default Configuration - SSH Remote Enrollment (ssh-remote-enroll)
# ==============================================================================
ENROLL_COPY_ID="${ENROLL_COPY_ID:-true}"          # Use ssh-copy-id if available
ENROLL_BACKUP_AUTHORIZED_KEYS="${ENROLL_BACKUP_AUTHORIZED_KEYS:-true}"
ENROLL_TEST_CONNECTION="${ENROLL_TEST_CONNECTION:-true}"
ENROLL_DISABLE_PASSWORD_AUTH="${ENROLL_DISABLE_PASSWORD_AUTH:-false}"  # Dangerous!
ENROLL_ADD_TO_SSH_CONFIG="${ENROLL_ADD_TO_SSH_CONFIG:-true}"
SSH_CONFIG_ALIAS="${SSH_CONFIG_ALIAS:-}"          # Alias for ~/.ssh/config entry

# ==============================================================================
# Runtime State (set during interactive configuration)
# ==============================================================================
CONFIG_CONFIRMED="false"

# ==============================================================================
# Logging Functions
# ==============================================================================
log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_section() { echo -e "\n${CYAN}${BOLD}=== $* ===${NC}\n"; }

# ==============================================================================
# Helper Functions
# ==============================================================================

# Prompt for input with default value
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local varname="$3"
    local input
    
    if [[ -n "$default" ]]; then
        read -rp "$(echo -e "${CYAN}$prompt${NC} [${GREEN}$default${NC}]: ")" input
        input="${input:-$default}"
    else
        read -rp "$(echo -e "${CYAN}$prompt${NC}: ")" input
    fi
    
    eval "$varname=\"$input\""
}

# Prompt for yes/no with default
prompt_yes_no() {
    local prompt="$1"
    local default="$2"  # "y" or "n"
    local varname="$3"
    local input
    
    local hint
    if [[ "$default" == "y" ]]; then
        hint="[Y/n]"
    else
        hint="[y/N]"
    fi
    
    read -rp "$(echo -e "${CYAN}$prompt${NC} $hint: ")" input
    input="${input:-$default}"
    
    if [[ "${input,,}" == "y" || "${input,,}" == "yes" ]]; then
        eval "$varname=\"true\""
    else
        eval "$varname=\"false\""
    fi
}

# Prompt for password (hidden input)
prompt_password() {
    local prompt="$1"
    local varname="$2"
    local input
    
    read -rsp "$(echo -e "${CYAN}$prompt${NC}: ")" input
    echo ""  # Newline after hidden input
    
    eval "$varname=\"$input\""
}

# Validate IP address format
validate_ip() {
    local ip="$1"
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    elif [[ "$ip" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*$ ]]; then
        # Allow hostnames too
        return 0
    else
        return 1
    fi
}

# Validate port number
validate_port() {
    local port="$1"
    if [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )); then
        return 0
    else
        return 1
    fi
}

# ==============================================================================
# Interactive Configuration Functions
# ==============================================================================

# Configure SSH target (used by ssh-remote-enroll)
configure_target() {
    log_section "SSH Target Configuration"
    
    echo -e "Configure the remote host you want to connect to.\n"
    
    # Target IP/Hostname
    while true; do
        prompt_with_default "Target IP or hostname" "$TARGET_IP" "TARGET_IP"
        if validate_ip "$TARGET_IP"; then
            break
        else
            log_error "Invalid IP address or hostname format"
        fi
    done
    
    # Target SSH Port
    while true; do
        prompt_with_default "SSH port" "$TARGET_SSH_PORT" "TARGET_SSH_PORT"
        if validate_port "$TARGET_SSH_PORT"; then
            break
        else
            log_error "Invalid port number (must be 1-65535)"
        fi
    done
    
    # Target SSH User
    prompt_with_default "SSH username" "$TARGET_SSH_USER" "TARGET_SSH_USER"
    
    # Optional hostname to set
    prompt_with_default "Set hostname on remote (leave empty to skip)" "$TARGET_HOSTNAME" "TARGET_HOSTNAME"
    
    # SSH config alias
    prompt_with_default "SSH config alias (for ~/.ssh/config)" "${SSH_CONFIG_ALIAS:-$TARGET_SSH_USER-vm}" "SSH_CONFIG_ALIAS"
}

# Configure SSH key generation (used by ssh-gen)
configure_keygen() {
    log_section "SSH Key Generation Configuration"
    
    echo -e "Configure SSH key generation settings.\n"
    
    # Key directory
    prompt_with_default "SSH key directory" "$SSH_KEY_DIR" "SSH_KEY_DIR"
    
    # Key name
    prompt_with_default "Key filename (without path)" "$SSH_KEY_NAME" "SSH_KEY_NAME"
    SSH_KEY_PATH="$SSH_KEY_DIR/$SSH_KEY_NAME"
    
    # Check if key already exists
    if [[ -f "$SSH_KEY_PATH" ]]; then
        log_warn "Key already exists at: $SSH_KEY_PATH"
        prompt_yes_no "Overwrite existing key?" "n" "OVERWRITE_KEY"
        if [[ "$OVERWRITE_KEY" != "true" ]]; then
            log_info "Using existing key"
            return 0
        fi
    fi
    
    # Key type
    echo -e "\nAvailable key types: ${GREEN}ed25519${NC} (recommended), ${YELLOW}rsa${NC}, ecdsa"
    prompt_with_default "Key type" "$SSH_KEY_TYPE" "SSH_KEY_TYPE"
    
    # Key bits (only for RSA)
    if [[ "$SSH_KEY_TYPE" == "rsa" ]]; then
        prompt_with_default "RSA key bits" "$SSH_KEY_BITS" "SSH_KEY_BITS"
    fi
    
    # Key comment
    prompt_with_default "Key comment" "$SSH_KEY_COMMENT" "SSH_KEY_COMMENT"
    
    # Passphrase
    echo -e "\n${YELLOW}Note:${NC} Empty passphrase = no encryption (less secure but convenient)"
    prompt_yes_no "Use passphrase for key?" "y" "USE_PASSPHRASE"
    
    if [[ "$USE_PASSPHRASE" == "true" ]]; then
        while true; do
            prompt_password "Enter passphrase" "SSH_KEY_PASSPHRASE"
            prompt_password "Confirm passphrase" "PASSPHRASE_CONFIRM"
            
            if [[ "$SSH_KEY_PASSPHRASE" == "$PASSPHRASE_CONFIRM" ]]; then
                break
            else
                log_error "Passphrases do not match, try again"
            fi
        done
    else
        SSH_KEY_PASSPHRASE=""
    fi
}

# Configure enrollment options (used by ssh-remote-enroll)
configure_enrollment() {
    log_section "SSH Key Enrollment Options"
    
    echo -e "Configure how the key will be enrolled on the remote host.\n"
    
    # Key to enroll
    prompt_with_default "Path to public key to enroll" "${SSH_KEY_PATH}.pub" "ENROLL_KEY_PATH"
    
    if [[ ! -f "$ENROLL_KEY_PATH" ]]; then
        log_warn "Public key not found at: $ENROLL_KEY_PATH"
        log_info "Run ssh-gen first to create a key pair"
    fi
    
    # Use ssh-copy-id
    prompt_yes_no "Use ssh-copy-id (if available)?" "y" "ENROLL_COPY_ID"
    
    # Backup authorized_keys
    prompt_yes_no "Backup remote authorized_keys before modifying?" "y" "ENROLL_BACKUP_AUTHORIZED_KEYS"
    
    # Test connection after enrollment
    prompt_yes_no "Test SSH connection after enrollment?" "y" "ENROLL_TEST_CONNECTION"
    
    # Add to SSH config
    prompt_yes_no "Add entry to ~/.ssh/config?" "y" "ENROLL_ADD_TO_SSH_CONFIG"
    
    # Disable password auth (dangerous)
    echo -e "\n${RED}WARNING:${NC} Disabling password auth locks you out if key auth fails!"
    prompt_yes_no "Disable password authentication on remote?" "n" "ENROLL_DISABLE_PASSWORD_AUTH"
}

# ==============================================================================
# Display Current Configuration
# ==============================================================================
display_config() {
    log_section "Current Configuration"
    
    echo -e "${BOLD}SSH Target:${NC}"
    echo -e "  Host:     ${GREEN}$TARGET_IP${NC}"
    echo -e "  Port:     ${GREEN}$TARGET_SSH_PORT${NC}"
    echo -e "  User:     ${GREEN}$TARGET_SSH_USER${NC}"
    [[ -n "$TARGET_HOSTNAME" ]] && echo -e "  Hostname: ${GREEN}$TARGET_HOSTNAME${NC}"
    [[ -n "$SSH_CONFIG_ALIAS" ]] && echo -e "  Alias:    ${GREEN}$SSH_CONFIG_ALIAS${NC}"
    
    echo -e "\n${BOLD}SSH Key:${NC}"
    echo -e "  Path:     ${GREEN}$SSH_KEY_PATH${NC}"
    echo -e "  Type:     ${GREEN}$SSH_KEY_TYPE${NC}"
    [[ "$SSH_KEY_TYPE" == "rsa" ]] && echo -e "  Bits:     ${GREEN}$SSH_KEY_BITS${NC}"
    echo -e "  Comment:  ${GREEN}$SSH_KEY_COMMENT${NC}"
    
    echo -e "\n${BOLD}Enrollment Options:${NC}"
    echo -e "  Use ssh-copy-id:      ${GREEN}$ENROLL_COPY_ID${NC}"
    echo -e "  Backup auth keys:     ${GREEN}$ENROLL_BACKUP_AUTHORIZED_KEYS${NC}"
    echo -e "  Test after enroll:    ${GREEN}$ENROLL_TEST_CONNECTION${NC}"
    echo -e "  Add to SSH config:    ${GREEN}$ENROLL_ADD_TO_SSH_CONFIG${NC}"
    echo -e "  Disable password:     ${GREEN}$ENROLL_DISABLE_PASSWORD_AUTH${NC}"
    
    echo ""
}

# ==============================================================================
# Main Interactive Configuration
# ==============================================================================
run_interactive_config() {
    local mode="${1:-all}"  # all, target, keygen, enroll
    
    echo -e "${CYAN}${BOLD}"
    echo "+============================================+"
    echo "|       VBox SSH Manager Configuration       |"
    echo "+============================================+"
    echo -e "${NC}"
    
    case "$mode" in
        all)
            configure_target
            configure_keygen
            configure_enrollment
            ;;
        target)
            configure_target
            ;;
        keygen)
            configure_keygen
            ;;
        enroll)
            configure_target
            configure_enrollment
            ;;
        *)
            log_error "Unknown configuration mode: $mode"
            return 1
            ;;
    esac
    
    display_config
    
    prompt_yes_no "Proceed with this configuration?" "y" "CONFIG_CONFIRMED"
    
    if [[ "$CONFIG_CONFIRMED" != "true" ]]; then
        log_warn "Configuration cancelled"
        return 1
    fi
    
    log_success "Configuration confirmed"
    return 0
}

# ==============================================================================
# Export Configuration (for sourcing by other scripts)
# ==============================================================================
export_config() {
    export TARGET_IP
    export TARGET_SSH_PORT
    export TARGET_SSH_USER
    export TARGET_HOSTNAME
    export SSH_KEY_DIR
    export SSH_KEY_NAME
    export SSH_KEY_PATH
    export SSH_KEY_TYPE
    export SSH_KEY_BITS
    export SSH_KEY_COMMENT
    export SSH_KEY_PASSPHRASE
    export ENROLL_COPY_ID
    export ENROLL_BACKUP_AUTHORIZED_KEYS
    export ENROLL_TEST_CONNECTION
    export ENROLL_DISABLE_PASSWORD_AUTH
    export ENROLL_ADD_TO_SSH_CONFIG
    export SSH_CONFIG_ALIAS
    export CONFIG_CONFIRMED
}

# If run directly (not sourced), run interactive configuration
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_interactive_config "${1:-all}"
    export_config
fi