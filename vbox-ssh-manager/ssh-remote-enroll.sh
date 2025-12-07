#!/bin/bash
# ssh-remote-enroll.sh - Enroll SSH key on remote host
# Part of vbox-ssh-manager

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# ==============================================================================
# SSH Key Enrollment Functions
# ==============================================================================

# Test SSH connection with password
test_password_connection() {
    log_info "Testing SSH connection to $TARGET_SSH_USER@$TARGET_IP:$TARGET_SSH_PORT..."
    
    if ssh -o BatchMode=no \
           -o ConnectTimeout=10 \
           -o StrictHostKeyChecking=accept-new \
           -p "$TARGET_SSH_PORT" \
           "$TARGET_SSH_USER@$TARGET_IP" \
           "echo 'Connection successful'" 2>/dev/null; then
        log_success "Password authentication works"
        return 0
    else
        log_error "Failed to connect with password"
        return 1
    fi
}

# Test SSH connection with key
test_key_connection() {
    local key_path="${1:-$SSH_KEY_PATH}"
    
    log_info "Testing SSH key authentication..."
    
    if ssh -o BatchMode=yes \
           -o ConnectTimeout=10 \
           -o StrictHostKeyChecking=accept-new \
           -i "$key_path" \
           -p "$TARGET_SSH_PORT" \
           "$TARGET_SSH_USER@$TARGET_IP" \
           "echo 'Key authentication successful'" 2>/dev/null; then
        log_success "Key authentication works"
        return 0
    else
        log_warn "Key authentication failed (may not be enrolled yet)"
        return 1
    fi
}

# Enroll key using ssh-copy-id
enroll_with_copy_id() {
    log_section "Enrolling Key (ssh-copy-id)"
    
    local pub_key="${ENROLL_KEY_PATH:-${SSH_KEY_PATH}.pub}"
    
    if [[ ! -f "$pub_key" ]]; then
        log_error "Public key not found: $pub_key"
        log_info "Run ./ssh-gen.sh first to create a key pair"
        return 1
    fi
    
    log_info "Enrolling public key: $pub_key"
    log_info "Target: $TARGET_SSH_USER@$TARGET_IP:$TARGET_SSH_PORT"
    echo ""
    log_warn "You will be prompted for the remote user's password"
    echo ""
    
    if ssh-copy-id -i "$pub_key" \
                   -p "$TARGET_SSH_PORT" \
                   "$TARGET_SSH_USER@$TARGET_IP"; then
        log_success "Key enrolled successfully via ssh-copy-id"
        return 0
    else
        log_error "ssh-copy-id failed"
        return 1
    fi
}

# Enroll key manually (fallback if ssh-copy-id not available)
enroll_manually() {
    log_section "Enrolling Key (Manual)"
    
    local pub_key="${ENROLL_KEY_PATH:-${SSH_KEY_PATH}.pub}"
    
    if [[ ! -f "$pub_key" ]]; then
        log_error "Public key not found: $pub_key"
        return 1
    fi
    
    local pub_key_content
    pub_key_content=$(cat "$pub_key")
    
    log_info "Enrolling public key manually..."
    log_warn "You will be prompted for the remote user's password"
    echo ""
    
    # Backup existing authorized_keys if requested
    local backup_cmd=""
    if [[ "$ENROLL_BACKUP_AUTHORIZED_KEYS" == "true" ]]; then
        backup_cmd="cp ~/.ssh/authorized_keys ~/.ssh/authorized_keys.backup.\$(date +%Y%m%d_%H%M%S) 2>/dev/null || true; "
    fi
    
    # Create .ssh dir and append key
    local enroll_cmd="${backup_cmd}mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$pub_key_content' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    
    if ssh -p "$TARGET_SSH_PORT" \
           "$TARGET_SSH_USER@$TARGET_IP" \
           "$enroll_cmd"; then
        log_success "Key enrolled successfully"
        return 0
    else
        log_error "Manual enrollment failed"
        return 1
    fi
}

# Add entry to local SSH config
add_ssh_config_entry() {
    log_section "SSH Config"
    
    local ssh_config="$HOME/.ssh/config"
    local alias="${SSH_CONFIG_ALIAS:-${TARGET_SSH_USER}-vm}"
    
    # Check if entry already exists
    if [[ -f "$ssh_config" ]] && grep -q "^Host $alias\$" "$ssh_config"; then
        log_warn "SSH config entry '$alias' already exists"
        prompt_yes_no "Update existing entry?" "n" "UPDATE_CONFIG"
        
        if [[ "$UPDATE_CONFIG" != "true" ]]; then
            log_info "Keeping existing SSH config entry"
            return 0
        fi
        
        # Remove existing entry (including all lines until next Host or EOF)
        log_info "Removing existing entry..."
        sed -i "/^Host $alias\$/,/^Host /{ /^Host $alias\$/d; /^Host /!d; }" "$ssh_config"
    fi
    
    log_info "Adding SSH config entry: $alias"
    
    # Create config if it doesn't exist
    if [[ ! -f "$ssh_config" ]]; then
        touch "$ssh_config"
        chmod 600 "$ssh_config"
    fi
    
    # Add entry
    cat >> "$ssh_config" <<EOF

# Added by vbox-ssh-manager on $(date +%Y-%m-%d)
Host $alias
    HostName $TARGET_IP
    Port $TARGET_SSH_PORT
    User $TARGET_SSH_USER
    IdentityFile $SSH_KEY_PATH
    IdentitiesOnly yes
EOF
    
    log_success "SSH config entry added"
    echo ""
    echo -e "You can now connect with: ${GREEN}ssh $alias${NC}"
}

# Set hostname on remote (optional)
set_remote_hostname() {
    if [[ -z "$TARGET_HOSTNAME" ]]; then
        return 0
    fi
    
    log_section "Setting Remote Hostname"
    
    log_info "Setting hostname to: $TARGET_HOSTNAME"
    
    # Use -t to allocate TTY for sudo
    if ssh -t -i "$SSH_KEY_PATH" \
           -p "$TARGET_SSH_PORT" \
           "$TARGET_SSH_USER@$TARGET_IP" \
           "sudo hostnamectl set-hostname '$TARGET_HOSTNAME' && echo 'Hostname set to: \$(hostname)'"; then
        log_success "Hostname set successfully"
        return 0
    else
        log_warn "Failed to set hostname (may need sudo access)"
        return 1
    fi
}

# Disable password authentication (dangerous!)
disable_password_auth() {
    log_section "Disabling Password Authentication"
    
    log_warn "This will disable password authentication on the remote host!"
    log_warn "Make sure key authentication is working before proceeding!"
    
    prompt_yes_no "Are you SURE you want to disable password auth?" "n" "CONFIRM_DISABLE"
    
    if [[ "$CONFIRM_DISABLE" != "true" ]]; then
        log_info "Skipping password auth disable"
        return 0
    fi
    
    # First verify key auth works
    if ! test_key_connection; then
        log_error "Key authentication not working - refusing to disable password auth"
        return 1
    fi
    
    log_info "Disabling password authentication..."
    log_warn "You may be prompted for the remote sudo password"
    
    local disable_cmd="sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config && sudo systemctl restart sshd"
    
    # Use -t to allocate TTY for sudo password prompt
    if ssh -t -i "$SSH_KEY_PATH" \
           -p "$TARGET_SSH_PORT" \
           "$TARGET_SSH_USER@$TARGET_IP" \
           "$disable_cmd"; then
        log_success "Password authentication disabled"
        return 0
    else
        log_error "Failed to disable password authentication"
        return 1
    fi
}

# ==============================================================================
# Main
# ==============================================================================

main() {
    echo -e "${CYAN}${BOLD}"
    echo "+============================================+"
    echo "|    SSH Key Remote Enrollment               |"
    echo "+============================================+"
    echo -e "${NC}"
    
    # Run interactive configuration for enrollment
    if ! run_interactive_config "enroll"; then
        exit 1
    fi
    
    # Check if public key exists
    local pub_key="${ENROLL_KEY_PATH:-${SSH_KEY_PATH}.pub}"
    if [[ ! -f "$pub_key" ]]; then
        log_error "Public key not found: $pub_key"
        echo ""
        prompt_yes_no "Generate a new key pair now?" "y" "GEN_KEY"
        
        if [[ "$GEN_KEY" == "true" ]]; then
            "$SCRIPT_DIR/ssh-gen.sh"
        else
            log_error "Cannot proceed without a public key"
            exit 1
        fi
    fi
    
    # Check if already enrolled
    echo ""
    log_info "Checking if key is already enrolled..."
    if test_key_connection "$SSH_KEY_PATH"; then
        log_success "Key is already enrolled and working"
        
        prompt_yes_no "Re-enroll anyway?" "n" "REENROLL"
        if [[ "$REENROLL" != "true" ]]; then
            # Still offer to add SSH config
            if [[ "$ENROLL_ADD_TO_SSH_CONFIG" == "true" ]]; then
                add_ssh_config_entry || true
            fi
            exit 0
        fi
    fi
    
    # Enroll the key
    if [[ "$ENROLL_COPY_ID" == "true" ]] && command -v ssh-copy-id &>/dev/null; then
        enroll_with_copy_id || enroll_manually
    else
        enroll_manually
    fi
    
    # Test the connection
    if [[ "$ENROLL_TEST_CONNECTION" == "true" ]]; then
        echo ""
        if test_key_connection; then
            log_success "Key enrollment verified"
        else
            log_error "Key enrollment verification failed"
            exit 1
        fi
    fi
    
    # Add SSH config entry
    if [[ "$ENROLL_ADD_TO_SSH_CONFIG" == "true" ]]; then
        add_ssh_config_entry || true
    fi
    
    # Set hostname if specified
    set_remote_hostname || true
    
    # Disable password auth if requested
    if [[ "$ENROLL_DISABLE_PASSWORD_AUTH" == "true" ]]; then
        disable_password_auth || true
    fi
    
    log_section "Enrollment Complete"
    
    local alias="${SSH_CONFIG_ALIAS:-${TARGET_SSH_USER}-vm}"
    
    echo -e "${GREEN}${BOLD}Success!${NC} SSH key enrolled on $TARGET_IP"
    echo ""
    echo -e "Connect with:"
    echo -e "  ${CYAN}ssh $alias${NC}                    (using SSH config alias)"
    echo -e "  ${CYAN}ssh -i $SSH_KEY_PATH -p $TARGET_SSH_PORT $TARGET_SSH_USER@$TARGET_IP${NC}"
    echo ""
}

main "$@"
