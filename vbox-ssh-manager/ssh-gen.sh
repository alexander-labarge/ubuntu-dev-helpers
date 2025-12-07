#!/bin/bash
# ssh-gen.sh - Interactive SSH key generation
# Part of vbox-ssh-manager

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# ==============================================================================
# SSH Key Generation
# ==============================================================================

generate_ssh_key() {
    log_section "Generating SSH Key"
    
    # Create SSH directory if it doesn't exist
    if [[ ! -d "$SSH_KEY_DIR" ]]; then
        log_info "Creating SSH directory: $SSH_KEY_DIR"
        mkdir -p "$SSH_KEY_DIR"
        chmod 700 "$SSH_KEY_DIR"
    fi
    
    # Check if key already exists
    if [[ -f "$SSH_KEY_PATH" ]]; then
        if [[ "${OVERWRITE_KEY:-false}" != "true" ]]; then
            log_warn "Key already exists at: $SSH_KEY_PATH"
            log_info "Skipping generation (use existing key)"
            return 0
        else
            log_warn "Overwriting existing key: $SSH_KEY_PATH"
            rm -f "$SSH_KEY_PATH" "${SSH_KEY_PATH}.pub"
        fi
    fi
    
    log_info "Generating $SSH_KEY_TYPE key..."
    log_info "  Path:    $SSH_KEY_PATH"
    log_info "  Comment: $SSH_KEY_COMMENT"
    
    # Build ssh-keygen command
    local keygen_args=(-t "$SSH_KEY_TYPE" -f "$SSH_KEY_PATH" -C "$SSH_KEY_COMMENT")
    
    # Add bits for RSA
    if [[ "$SSH_KEY_TYPE" == "rsa" ]]; then
        keygen_args+=(-b "$SSH_KEY_BITS")
        log_info "  Bits:    $SSH_KEY_BITS"
    fi
    
    # Handle passphrase
    if [[ -z "$SSH_KEY_PASSPHRASE" ]]; then
        keygen_args+=(-N "")
        log_warn "Generating key without passphrase"
    else
        keygen_args+=(-N "$SSH_KEY_PASSPHRASE")
        log_info "  Passphrase: (set)"
    fi
    
    # Generate the key
    if ssh-keygen "${keygen_args[@]}"; then
        log_success "SSH key generated successfully"
        
        # Set proper permissions
        chmod 600 "$SSH_KEY_PATH"
        chmod 644 "${SSH_KEY_PATH}.pub"
        
        # Display public key
        log_section "Public Key"
        echo -e "${GREEN}"
        cat "${SSH_KEY_PATH}.pub"
        echo -e "${NC}"
        
        # Show fingerprint
        log_info "Fingerprint:"
        ssh-keygen -lf "${SSH_KEY_PATH}.pub"
        
        return 0
    else
        log_error "Failed to generate SSH key"
        return 1
    fi
}

# Add key to SSH agent
add_to_agent() {
    log_section "SSH Agent"
    
    # Check if ssh-agent is running
    if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
        log_warn "SSH agent is not running"
        log_info "Start with: eval \$(ssh-agent -s)"
        return 1
    fi
    
    log_info "Adding key to SSH agent..."
    
    if ssh-add "$SSH_KEY_PATH"; then
        log_success "Key added to SSH agent"
        
        # List keys in agent
        log_info "Keys in agent:"
        ssh-add -l
        return 0
    else
        log_error "Failed to add key to SSH agent"
        return 1
    fi
}

# ==============================================================================
# Main
# ==============================================================================

main() {
    echo -e "${CYAN}${BOLD}"
    echo "+============================================+"
    echo "|         SSH Key Generator (ssh-gen)        |"
    echo "+============================================+"
    echo -e "${NC}"
    
    # Run interactive configuration for keygen
    if ! run_interactive_config "keygen"; then
        exit 1
    fi
    
    # Generate the key
    if ! generate_ssh_key; then
        exit 1
    fi
    
    # Offer to add to SSH agent
    echo ""
    prompt_yes_no "Add key to SSH agent?" "y" "ADD_TO_AGENT"
    
    if [[ "$ADD_TO_AGENT" == "true" ]]; then
        add_to_agent || true  # Don't fail if agent not running
    fi
    
    log_section "Done"
    log_success "SSH key is ready"
    echo ""
    echo -e "Public key location: ${GREEN}${SSH_KEY_PATH}.pub${NC}"
    echo -e "Private key location: ${GREEN}${SSH_KEY_PATH}${NC}"
    echo ""
    echo -e "Next step: Run ${CYAN}./ssh-remote-enroll.sh${NC} to enroll the key on a remote host"
}

main "$@"
