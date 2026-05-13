#!/usr/bin/env bash
# nix-installer-download.sh — download Determinate nix-installer binary
# at image build time and stage it at /usr/libexec/nix-installer.
# Also creates the empty /nix directory needed for composefs compatibility
# (the systemd .mount unit will bind-mount /var/lib/nix over this).
set -euo pipefail

NIX_INSTALLER_URL="${NIX_INSTALLER_URL:-https://install.determinate.systems/nix/nix-installer-x86_64-linux}"
NIX_INSTALLER_DEST="/usr/libexec/nix-installer"

NH_VERSION="${NH_VERSION:-4.3.2}"
NH_ARCH="${NH_ARCH:-x86_64-linux}"
NH_URL="https://github.com/nix-community/nh/releases/download/v${NH_VERSION}/nh-${NH_ARCH}"
NH_DEST="/usr/libexec/nh"

log() { printf '\n\033[1;34m▶\033[0m %s\n' "$*"; }

log "Downloading nix-installer..."
curl -fsSL "$NIX_INSTALLER_URL" -o "$NIX_INSTALLER_DEST"
chmod +x "$NIX_INSTALLER_DEST"
ls -lh "$NIX_INSTALLER_DEST"

log "Downloading nh v${NH_VERSION}..."
curl -fsSL "$NH_URL" -o /tmp/nh.tar.zst
tar --zstd -xf /tmp/nh.tar.zst -C /tmp/
install -m 0755 /tmp/nh "${NH_DEST}"
rm -f /tmp/nh.tar.zst /tmp/nh
ls -lh "${NH_DEST}"

log "Creating empty /nix for composefs compatibility..."
mkdir -p /nix
