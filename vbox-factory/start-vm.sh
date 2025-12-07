#!/usr/bin/env bash
# start-vm.sh - Start a VM with automatic KVM conflict handling
# Usage: ./start-vm.sh <vm-name> [gui|headless]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vbox-lib.sh"

VM_NAME="${1:-}"
VM_TYPE="${2:-headless}"

if [ -z "$VM_NAME" ]; then
    log_error "VM name required"
    echo "Usage: $(basename "$0") <vm-name> [gui|headless]"
    exit 1
fi

if ! vm_exists "$VM_NAME"; then
    log_error "VM '$VM_NAME' does not exist"
    make vm-list 2>/dev/null || VBoxManage list vms
    exit 1
fi

vbox_start "$VM_NAME" "$VM_TYPE"
