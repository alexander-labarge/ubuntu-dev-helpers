# ISO Manager

Utility for downloading Ubuntu ISOs. Run through the repository Makefile so you get the right defaults.

## Usage

```bash
# From the repo root
make iso-download
```

This downloads Ubuntu 24.04.3 LTS ISOs (server and desktop) to `$HOME/vms/isos/` by default.

### Customization via env vars

These can be set inline with `make iso-download`:

- `UBUNTU_VERSION` (default `24.04.3`)
- `ISO_DIR` (default `$HOME/vms/isos`)
- `DOWNLOAD_SERVER` (default `1`)
- `DOWNLOAD_DESKTOP` (default `1`)

## What it downloads

- Ubuntu 24.04.3 Server (live-server-amd64.iso)
- Ubuntu 24.04.3 Desktop (desktop-amd64.iso)

The script also verifies checksums to ensure integrity.
