#!/bin/bash

# Ubuntu 24.04.3 LTS ISO Downloader
# Downloads server and desktop ISOs to $HOME/vms/isos

set -e

ISO_DIR="$HOME/vms/isos"
UBUNTU_VERSION="24.04.3"
BASE_URL="https://releases.ubuntu.com/${UBUNTU_VERSION}"

SERVER_ISO="ubuntu-${UBUNTU_VERSION}-live-server-amd64.iso"
DESKTOP_ISO="ubuntu-${UBUNTU_VERSION}-desktop-amd64.iso"

# Check for curl and install if missing
check_curl() {
    if ! command -v curl &> /dev/null; then
        echo "curl not found. Installing..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y curl
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y curl
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm curl
        else
            echo "ERROR: Unable to install curl. Please install manually."
            exit 1
        fi
    else
        echo "curl is already installed."
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

# Download ISO with resume support
download_iso() {
    local iso_name="$1"
    local url="${BASE_URL}/${iso_name}"
    local dest="${ISO_DIR}/${iso_name}"

    echo "----------------------------------------"
    echo "Downloading: $iso_name"
    echo "URL: $url"
    echo "Destination: $dest"
    echo "----------------------------------------"

    if [ -f "$dest" ]; then
        echo "File exists, attempting to resume or verify..."
    fi

    curl -L -C - -o "$dest" --progress-bar "$url"

    if [ $? -eq 0 ]; then
        echo "Download complete: $iso_name"
    else
        echo "ERROR: Failed to download $iso_name"
        return 1
    fi
}

# Verify checksums
verify_checksums() {
    echo "----------------------------------------"
    echo "Downloading SHA256SUMS for verification..."
    echo "----------------------------------------"

    curl -sL -o "${ISO_DIR}/SHA256SUMS" "${BASE_URL}/SHA256SUMS"

    cd "$ISO_DIR"

    echo "Verifying checksums..."
    for iso in "$SERVER_ISO" "$DESKTOP_ISO"; do
        if [ -f "$iso" ]; then
            expected=$(grep "$iso" SHA256SUMS | awk '{print $1}')
            if [ -n "$expected" ]; then
                actual=$(sha256sum "$iso" | awk '{print $1}')
                if [ "$expected" = "$actual" ]; then
                    echo "PASS: $iso"
                else
                    echo "FAIL: $iso (checksum mismatch)"
                fi
            else
                echo "SKIP: No checksum found for $iso"
            fi
        fi
    done
}

main() {
    echo "========================================"
    echo "Ubuntu ${UBUNTU_VERSION} LTS ISO Downloader"
    echo "========================================"
    echo ""

    check_curl
    create_iso_dir

    echo ""
    download_iso "$SERVER_ISO"

    echo ""
    download_iso "$DESKTOP_ISO"

    echo ""
    verify_checksums

    echo ""
    echo "========================================"
    echo "All downloads complete."
    echo "ISOs saved to: $ISO_DIR"
    echo "========================================"
    ls -lh "$ISO_DIR"/*.iso 2>/dev/null || true
}

main "$@"