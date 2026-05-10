#!/usr/bin/env bash
# sideral install bootstrap.
#
# Run from a fresh vanilla NixOS install (after the official calamares
# installer finishes and you've logged into the new system):
#
#     curl -fsSL https://raw.githubusercontent.com/athenabriana/sideral/main/install.sh | sudo bash
#
# What it does:
#   1. Detects NVIDIA GPU via lspci → picks `sideral` or `sideral-nvidia`.
#   2. Clones the sideral flake into /etc/nixos/sideral (or pulls latest
#      if already cloned).
#   3. Generates /etc/nixos/hardware-configuration.nix if missing,
#      then symlinks it into the flake root so the host imports it.
#   4. Runs `nixos-rebuild switch` against the local flake clone with
#      experimental-features enabled inline.
#
# Idempotent — safe to re-run for upgrades. Subsequent rebuilds can use
# `sudo nixos-rebuild switch --flake /etc/nixos/sideral#<host>` directly
# (sideral's common.nix enables flakes permanently after the first run).

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Must run as root." >&2
    echo "Try: curl -fsSL https://raw.githubusercontent.com/athenabriana/sideral/main/install.sh | sudo bash" >&2
    exit 1
fi

B=$'\e[1m'; G=$'\e[32m'; Y=$'\e[33m'; D=$'\e[2m'; N=$'\e[0m'

echo
echo "${B}sideral install bootstrap${N}"
echo

# ── 1. Detect GPU variant ─────────────────────────────────────────────
if command -v lspci >/dev/null 2>&1 && \
   lspci 2>/dev/null | grep -qiE 'vga.*nvidia|3d.*nvidia|display.*nvidia'; then
    HOST="sideral-nvidia"
    echo "${G}✓${N} NVIDIA GPU detected → variant: ${B}${HOST}${N}"
else
    HOST="sideral"
    echo "${G}✓${N} no NVIDIA detected → variant: ${B}${HOST}${N}"
fi

# ── 2. Clone or update the flake ──────────────────────────────────────
FLAKE_DIR="/etc/nixos/sideral"
if [ -d "$FLAKE_DIR/.git" ]; then
    echo "${D}flake already cloned at $FLAKE_DIR — pulling latest…${N}"
    git -C "$FLAKE_DIR" pull --ff-only
else
    echo "${D}cloning flake into $FLAKE_DIR…${N}"
    git clone --depth 1 https://github.com/athenabriana/sideral "$FLAKE_DIR"
fi

# ── 3. Hardware config ────────────────────────────────────────────────
if [ ! -f /etc/nixos/hardware-configuration.nix ]; then
    echo "${D}generating /etc/nixos/hardware-configuration.nix…${N}"
    nixos-generate-config --no-filesystems
fi

# Symlink into the flake root so hosts/sideral{,-nvidia}.nix can pick it up
ln -sf /etc/nixos/hardware-configuration.nix "$FLAKE_DIR/hardware-configuration.nix"

# ── 4. Rebuild ────────────────────────────────────────────────────────
echo
echo "${B}running nixos-rebuild switch --flake $FLAKE_DIR#$HOST${N}"
echo "${D}(this can take 10-30 min on first run — a lot to fetch + build)${N}"
echo

nixos-rebuild switch \
    --flake "$FLAKE_DIR#$HOST" \
    --extra-experimental-features 'nix-command flakes'

echo
echo "${G}✓ sideral installed.${N}"
echo "${Y}Reboot to start using niri+noctalia.${N}"
echo
echo "Future updates: ${B}sudo nixos-rebuild switch --flake /etc/nixos/sideral#$HOST${N}"
echo "(sideral now has flakes enabled by default — no flag needed)"
echo
