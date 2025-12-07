#!/bin/bash

set -Eeuo pipefail

# Color Constants
RESET='\033[0m'
BOLD='\033[1m'
FG_GREEN='\033[32m'
FG_YELLOW='\033[33m'
FG_RED='\033[31m'
FG_BLUE='\033[34m'
FG_CYAN='\033[36m'
FG_MAGENTA='\033[35m'

# Default values
GITLAB_DOMAIN=""
GITLAB_EMAIL=""
GITLAB_CONFIG="/etc/gitlab/gitlab.rb"
DRY_RUN=false

print_banner() {
    echo -e "${RESET}################################################################################${RESET}"
    echo -e "${RESET}####### ${FG_BLUE}################################################################${RESET} #######"
    echo -e "${RESET}####### ${FG_BLUE}###################                          ###################${RESET} #######"
    echo -e "${RESET}####### ${FG_BLUE}##################  ${FG_RED}${BOLD}GitLab Let's Encrypt Setup${RESET}${FG_BLUE}  ##################${RESET} #######"
    echo -e "${RESET}####### ${FG_BLUE}###################                          ###################${RESET} #######"
    echo -e "${RESET}####### ${FG_BLUE}################################################################${RESET} #######"
    echo -e "${RESET}####### ${FG_YELLOW}${BOLD}    Interactive SSL/TLS Certificate Configuration for GitLab    ${RESET} #######"
    echo -e "${RESET}####### ${FG_BLUE}################################################################${RESET} #######"
    echo -e "${RESET}################################################################################${RESET}"
    echo ""
}

log() {
    local type=$1
    local message=$2
    local color

    case "$type" in
        "ERROR") color="${FG_RED}" ;;
        "SUCCESS") color="${FG_GREEN}" ;;
        "INFO") color="${FG_CYAN}" ;;
        "WARN") color="${FG_YELLOW}" ;;
        *) color="${RESET}" ;;
    esac

    echo -e "${BOLD}$(date '+%Y-%m-%d %H:%M:%S')${RESET} ${BOLD}${color}[$type]${RESET} ${FG_YELLOW}${message}${RESET}"
}

print_separator() {
    echo -e "${FG_BLUE}────────────────────────────────────────────────────────────────────────────────${RESET}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_gitlab_installed() {
    if ! command -v gitlab-ctl &>/dev/null; then
        log "ERROR" "GitLab does not appear to be installed (gitlab-ctl not found)"
        exit 1
    fi

    if [[ ! -f "$GITLAB_CONFIG" ]]; then
        log "ERROR" "GitLab configuration file not found at $GITLAB_CONFIG"
        exit 1
    fi

    log "SUCCESS" "GitLab installation detected"
}

get_current_config() {
    log "INFO" "Checking current GitLab configuration..."
    
    local current_url
    current_url=$(grep -E "^external_url" "$GITLAB_CONFIG" 2>/dev/null | head -1 || echo "")
    
    if [[ -n "$current_url" ]]; then
        echo -e "${FG_CYAN}Current external_url:${RESET} $current_url"
    else
        echo -e "${FG_YELLOW}No external_url currently configured${RESET}"
    fi
    
    local le_enabled
    le_enabled=$(grep -E "letsencrypt\['enable'\]" "$GITLAB_CONFIG" 2>/dev/null | head -1 || echo "")
    
    if [[ -n "$le_enabled" ]]; then
        echo -e "${FG_CYAN}Let's Encrypt setting:${RESET} $le_enabled"
    fi
    echo ""
}

prompt_domain() {
    print_separator
    echo -e "${FG_MAGENTA}${BOLD}Step 1: Domain Configuration${RESET}"
    print_separator
    
    echo -e "${FG_CYAN}Enter the fully qualified domain name (FQDN) for your GitLab instance.${RESET}"
    echo -e "${FG_YELLOW}Example: gitlab.example.com${RESET}"
    echo ""
    
    while true; do
        read -p $'\e[1m\e[36mGitLab Domain: \e[0m' GITLAB_DOMAIN
        
        if [[ -z "$GITLAB_DOMAIN" ]]; then
            log "WARN" "Domain cannot be empty. Please try again."
            continue
        fi
        
        # Basic domain validation
        if [[ ! "$GITLAB_DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?)*$ ]]; then
            log "WARN" "Invalid domain format. Please enter a valid FQDN."
            continue
        fi
        
        break
    done
    
    log "INFO" "Domain set to: $GITLAB_DOMAIN"
}

prompt_email() {
    print_separator
    echo -e "${FG_MAGENTA}${BOLD}Step 2: Contact Email${RESET}"
    print_separator
    
    echo -e "${FG_CYAN}Enter an email address for Let's Encrypt notifications.${RESET}"
    echo -e "${FG_YELLOW}This email will receive certificate expiry warnings.${RESET}"
    echo ""
    
    while true; do
        read -p $'\e[1m\e[36mEmail Address: \e[0m' GITLAB_EMAIL
        
        if [[ -z "$GITLAB_EMAIL" ]]; then
            log "WARN" "Email cannot be empty. Please try again."
            continue
        fi
        
        # Basic email validation
        if [[ ! "$GITLAB_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            log "WARN" "Invalid email format. Please enter a valid email address."
            continue
        fi
        
        break
    done
    
    log "INFO" "Email set to: $GITLAB_EMAIL"
}

confirm_settings() {
    print_separator
    echo -e "${FG_MAGENTA}${BOLD}Configuration Summary${RESET}"
    print_separator
    
    echo -e "${FG_CYAN}${BOLD}Domain:${RESET}         https://$GITLAB_DOMAIN"
    echo -e "${FG_CYAN}${BOLD}Email:${RESET}          $GITLAB_EMAIL"
    echo -e "${FG_CYAN}${BOLD}Config File:${RESET}    $GITLAB_CONFIG"
    echo ""
    
    echo -e "${FG_YELLOW}${BOLD}The following changes will be made to gitlab.rb:${RESET}"
    echo -e "  1. Set external_url to 'https://$GITLAB_DOMAIN'"
    echo -e "  2. Enable Let's Encrypt auto-renewal"
    echo -e "  3. Set Let's Encrypt contact email"
    echo -e "  4. Enable automatic HTTP to HTTPS redirect"
    echo ""
    
    while true; do
        read -p $'\e[1m\e[33mProceed with these settings? (yes/no): \e[0m' confirm
        case "$confirm" in
            yes|y|Y|Yes|YES)
                return 0
                ;;
            no|n|N|No|NO)
                log "INFO" "Configuration cancelled by user."
                exit 0
                ;;
            *)
                echo -e "${FG_YELLOW}Please answer yes or no.${RESET}"
                ;;
        esac
    done
}

backup_config() {
    local backup_file="${GITLAB_CONFIG}.backup.$(date +'%Y%m%d_%H%M%S')"
    
    log "INFO" "Creating backup of gitlab.rb..."
    
    if cp "$GITLAB_CONFIG" "$backup_file"; then
        log "SUCCESS" "Backup created: $backup_file"
    else
        log "ERROR" "Failed to create backup"
        exit 1
    fi
}

update_gitlab_config() {
    log "INFO" "Updating GitLab configuration..."
    
    # Create a temporary file for the new configuration
    local temp_config
    temp_config=$(mktemp)
    
    # Read existing config and update/add settings
    local external_url_set=false
    local le_enable_set=false
    local le_email_set=false
    local le_redirect_set=false
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Update external_url
        if [[ "$line" =~ ^[[:space:]]*external_url ]]; then
            echo "external_url 'https://$GITLAB_DOMAIN'" >> "$temp_config"
            external_url_set=true
            continue
        fi
        
        # Update/comment out existing Let's Encrypt settings (we'll add them at the end)
        if [[ "$line" =~ ^[[:space:]]*letsencrypt\[\'enable\'\] ]]; then
            le_enable_set=true
            continue
        fi
        
        if [[ "$line" =~ ^[[:space:]]*letsencrypt\[\'contact_emails\'\] ]]; then
            le_email_set=true
            continue
        fi
        
        if [[ "$line" =~ ^[[:space:]]*letsencrypt\[\'auto_renew\'\] ]]; then
            continue
        fi
        
        if [[ "$line" =~ ^[[:space:]]*nginx\[\'redirect_http_to_https\'\] ]]; then
            le_redirect_set=true
            continue
        fi
        
        echo "$line" >> "$temp_config"
    done < "$GITLAB_CONFIG"
    
    # Add external_url if not already set
    if [[ "$external_url_set" == false ]]; then
        echo "" >> "$temp_config"
        echo "# External URL - Updated by gitlab-letsencrypt-setup.sh" >> "$temp_config"
        echo "external_url 'https://$GITLAB_DOMAIN'" >> "$temp_config"
    fi
    
    # Add Let's Encrypt configuration block
    echo "" >> "$temp_config"
    echo "################################################################################" >> "$temp_config"
    echo "# Let's Encrypt Configuration - Added by gitlab-letsencrypt-setup.sh" >> "$temp_config"
    echo "# Generated on: $(date)" >> "$temp_config"
    echo "################################################################################" >> "$temp_config"
    echo "letsencrypt['enable'] = true" >> "$temp_config"
    echo "letsencrypt['contact_emails'] = ['$GITLAB_EMAIL']" >> "$temp_config"
    echo "letsencrypt['auto_renew'] = true" >> "$temp_config"
    echo "letsencrypt['auto_renew_hour'] = 3" >> "$temp_config"
    echo "letsencrypt['auto_renew_minute'] = 30" >> "$temp_config"
    echo "letsencrypt['auto_renew_day_of_month'] = \"*/7\"" >> "$temp_config"
    echo "nginx['redirect_http_to_https'] = true" >> "$temp_config"
    
    # Replace the original config
    if mv "$temp_config" "$GITLAB_CONFIG"; then
        chmod 600 "$GITLAB_CONFIG"
        log "SUCCESS" "GitLab configuration updated"
    else
        log "ERROR" "Failed to update configuration"
        rm -f "$temp_config"
        exit 1
    fi
}

check_dns() {
    log "INFO" "Checking DNS resolution for $GITLAB_DOMAIN..."
    
    if command -v dig &>/dev/null; then
        local dns_result
        dns_result=$(dig +short "$GITLAB_DOMAIN" 2>/dev/null | head -1)
        
        if [[ -n "$dns_result" ]]; then
            log "SUCCESS" "DNS resolves to: $dns_result"
        else
            log "WARN" "Could not resolve DNS for $GITLAB_DOMAIN"
            log "WARN" "Make sure DNS is properly configured before running gitlab-ctl reconfigure"
        fi
    elif command -v host &>/dev/null; then
        if host "$GITLAB_DOMAIN" &>/dev/null; then
            log "SUCCESS" "DNS resolution successful"
        else
            log "WARN" "Could not resolve DNS for $GITLAB_DOMAIN"
        fi
    else
        log "INFO" "DNS check skipped (dig/host not available)"
    fi
}

check_ports() {
    log "INFO" "Checking if ports 80 and 443 are available..."
    
    local port_80_used=false
    local port_443_used=false
    
    if ss -tlnp 2>/dev/null | grep -q ":80 "; then
        local process_80
        process_80=$(ss -tlnp 2>/dev/null | grep ":80 " | awk '{print $NF}' | head -1)
        log "INFO" "Port 80 is in use by: $process_80"
        port_80_used=true
    fi
    
    if ss -tlnp 2>/dev/null | grep -q ":443 "; then
        local process_443
        process_443=$(ss -tlnp 2>/dev/null | grep ":443 " | awk '{print $NF}' | head -1)
        log "INFO" "Port 443 is in use by: $process_443"
        port_443_used=true
    fi
    
    if [[ "$port_80_used" == false ]] && [[ "$port_443_used" == false ]]; then
        log "SUCCESS" "Ports 80 and 443 are available"
    else
        log "WARN" "Some ports are in use - this is expected if GitLab is already running"
    fi
}

prompt_reconfigure() {
    print_separator
    echo -e "${FG_MAGENTA}${BOLD}Apply Configuration${RESET}"
    print_separator
    
    echo -e "${FG_CYAN}Configuration has been updated. To apply the changes, GitLab needs to be reconfigured.${RESET}"
    echo -e "${FG_YELLOW}This will restart GitLab services and may take several minutes.${RESET}"
    echo ""
    
    while true; do
        read -p $'\e[1m\e[33mRun gitlab-ctl reconfigure now? (yes/no): \e[0m' confirm
        case "$confirm" in
            yes|y|Y|Yes|YES)
                return 0
                ;;
            no|n|N|No|NO)
                log "INFO" "Skipping reconfigure. Run 'sudo gitlab-ctl reconfigure' manually to apply changes."
                return 1
                ;;
            *)
                echo -e "${FG_YELLOW}Please answer yes or no.${RESET}"
                ;;
        esac
    done
}

run_reconfigure() {
    log "INFO" "Running gitlab-ctl reconfigure..."
    log "INFO" "This may take several minutes. Please wait..."
    echo ""
    
    if gitlab-ctl reconfigure; then
        log "SUCCESS" "GitLab reconfiguration completed successfully!"
    else
        log "ERROR" "GitLab reconfiguration failed"
        log "INFO" "Check /var/log/gitlab/reconfigure/ for detailed logs"
        exit 1
    fi
}

print_success() {
    print_separator
    echo -e "${FG_GREEN}${BOLD}🎉 Let's Encrypt SSL Configuration Complete! 🎉${RESET}"
    print_separator
    echo ""
    echo -e "${FG_CYAN}${BOLD}Your GitLab instance is now configured with:${RESET}"
    echo -e "  • URL: ${FG_GREEN}https://$GITLAB_DOMAIN${RESET}"
    echo -e "  • Let's Encrypt SSL certificate (auto-renewal enabled)"
    echo -e "  • HTTP to HTTPS redirect"
    echo ""
    echo -e "${FG_CYAN}${BOLD}Certificate Renewal:${RESET}"
    echo -e "  • Certificates auto-renew every 7 days at 3:30 AM"
    echo -e "  • Expiry warnings sent to: $GITLAB_EMAIL"
    echo ""
    echo -e "${FG_CYAN}${BOLD}Useful Commands:${RESET}"
    echo -e "  Check certificate:  ${FG_YELLOW}sudo gitlab-ctl ssl-check${RESET}"
    echo -e "  Renew certificate:  ${FG_YELLOW}sudo gitlab-ctl renew-le-certs${RESET}"
    echo -e "  View status:        ${FG_YELLOW}sudo gitlab-ctl status${RESET}"
    echo -e "  View logs:          ${FG_YELLOW}sudo gitlab-ctl tail nginx${RESET}"
    print_separator
}

print_manual_instructions() {
    print_separator
    echo -e "${FG_YELLOW}${BOLD}Configuration Saved - Manual Reconfigure Required${RESET}"
    print_separator
    echo ""
    echo -e "${FG_CYAN}To apply the Let's Encrypt configuration, run:${RESET}"
    echo -e "  ${FG_YELLOW}sudo gitlab-ctl reconfigure${RESET}"
    echo ""
    echo -e "${FG_CYAN}Before running reconfigure, ensure:${RESET}"
    echo -e "  1. DNS for ${FG_GREEN}$GITLAB_DOMAIN${RESET} points to this server"
    echo -e "  2. Ports 80 and 443 are accessible from the internet"
    echo -e "  3. No firewall blocking incoming HTTP/HTTPS traffic"
    print_separator
}

# Main execution
main() {
    print_banner
    check_root
    check_gitlab_installed
    get_current_config
    
    prompt_domain
    prompt_email
    confirm_settings
    
    check_dns
    check_ports
    
    backup_config
    update_gitlab_config
    
    if prompt_reconfigure; then
        run_reconfigure
        print_success
    else
        print_manual_instructions
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)
            GITLAB_DOMAIN="$2"
            shift 2
            ;;
        --email)
            GITLAB_EMAIL="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            print_banner
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --domain <fqdn>    GitLab domain (e.g., gitlab.example.com)"
            echo "  --email <email>    Contact email for Let's Encrypt"
            echo "  --dry-run          Show what would be done without making changes"
            echo "  --help, -h         Show this help message"
            echo ""
            echo "If no options are provided, the script runs in interactive mode."
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

main
