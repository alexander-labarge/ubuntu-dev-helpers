# ISO Manager

Utility script for downloading Ubuntu ISOs.

## Usage

```bash
cd iso-manager
./download_ubuntu_24.04.3.sh
```

This will download Ubuntu 24.04.3 LTS ISOs (server and desktop) to `$HOME/vms/isos/`.

## What it downloads

- Ubuntu 24.04.3 Server (live-server-amd64.iso)
- Ubuntu 24.04.3 Desktop (desktop-amd64.iso)

The script also verifies checksums to ensure integrity.
