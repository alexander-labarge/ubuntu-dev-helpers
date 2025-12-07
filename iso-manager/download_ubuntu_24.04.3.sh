#!/usr/bin/env bash

# Ubuntu 24.04.3 LTS ISO Downloader
# Downloads server and desktop ISOs to $HOME/vms/isos (configurable via ISO_DIR)

set -euo pipefail

ISO_DIR="${ISO_DIR:-$HOME/vms/isos}"
UBUNTU_VERSION="${UBUNTU_VERSION:-24.04.3}"
BASE_URL="https://releases.ubuntu.com/${UBUNTU_VERSION}"

SERVER_ISO="ubuntu-${UBUNTU_VERSION}-live-server-amd64.iso"
DESKTOP_ISO="ubuntu-${UBUNTU_VERSION}-desktop-amd64.iso"

DOWNLOAD_SERVER="${DOWNLOAD_SERVER:-1}"
DOWNLOAD_DESKTOP="${DOWNLOAD_DESKTOP:-1}"

log_section() {
    printf "\n========================================\n%s\n========================================\n\n" "$1"
}

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: Required command '$cmd' not found. Install it and retry." >&2
        exit 1
    fi
}

# Check for curl and install if missing
ensure_curl() {
    if command -v curl >/dev/null 2>&1; then
        echo "curl is already installed."
        return
    fi

    echo "curl not found. Attempting to install..."
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y curl
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y curl
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --noconfirm curl
    else
        echo "ERROR: Unable to install curl. Please install it manually." >&2
        exit 1
    fi
}

# Create ISO directory if it doesn't exist
create_iso_dir() {
    if [ ! -d "$ISO_DIR" ]; then
        echo "Creating directory: $ISO_DIR"
        mkdir -p "$ISO_DIR"
    else
        echo "Directory exists: $ISO_DIR"
    fi
}

# Download a file with resume and retries
download_file() {
    local url="$1"
    local dest="$2"

    curl \
        --fail \
        --location \
        --continue-at - \
        --retry 3 \
        --retry-delay 3 \
        --progress-bar \
        --output "$dest" \
        "$url"
}

# Download ISO with resume support
download_iso() {
    local iso_name="$1"
    local url="${BASE_URL}/${iso_name}"
    local dest="${ISO_DIR}/${iso_name}"

    log_section "Downloading: $iso_name"
    echo "URL: $url"
    echo "Destination: $dest"

    if [ -f "$dest" ]; then
        echo "Existing file found, attempting to resume..."
    fi

    if download_file "$url" "$dest"; then
        echo "Download complete: $iso_name"
    else
        echo "ERROR: Failed to download $iso_name" >&2
        return 1
    fi
}

fetch_checksums() {
    local sums_path="${ISO_DIR}/SHA256SUMS"
    log_section "Fetching SHA256SUMS"
    download_file "${BASE_URL}/SHA256SUMS" "$sums_path"
    echo "Checksums saved to: $sums_path"
}

# Verify checksums
verify_checksums() {
    local sums_path="${ISO_DIR}/SHA256SUMS"

    if [ ! -f "$sums_path" ]; then
        echo "No checksum file found at $sums_path; skipping verification." >&2
        return
    fi

    log_section "Verifying checksums"
    (cd "$ISO_DIR" && sha256sum --quiet --check "$sums_path" --ignore-missing && echo "Checksum verification complete.") || {
        echo "WARNING: One or more checksum verifications failed." >&2
    }
}

main() {
    log_section "Ubuntu ${UBUNTU_VERSION} LTS ISO Downloader"

    ensure_curl
    require_cmd sha256sum
    create_iso_dir

    if [ "$DOWNLOAD_SERVER" = "1" ]; then
        download_iso "$SERVER_ISO"
    else
        echo "Skipping server ISO (DOWNLOAD_SERVER=${DOWNLOAD_SERVER})."
    fi

    if [ "$DOWNLOAD_DESKTOP" = "1" ]; then
        download_iso "$DESKTOP_ISO"
    else
        echo "Skipping desktop ISO (DOWNLOAD_DESKTOP=${DOWNLOAD_DESKTOP})."
    fi

    fetch_checksums
    verify_checksums

    log_section "All downloads complete"
    echo "ISOs saved to: $ISO_DIR"
    ls -lh "$ISO_DIR"/*.iso 2>/dev/null || true
}

main "$@"