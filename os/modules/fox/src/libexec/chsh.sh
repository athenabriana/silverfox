#!/usr/bin/env bash
# chsh.sh — switch login shell via `sudo usermod -s` (ublue strips
# setuid chsh). Allowlist: bash, zsh. No-arg opens `tv` picker if
# available, else falls back to `read -p`.
set -euo pipefail

target="${1:-}"

if [[ -z "$target" ]]; then
    if command -v tv >/dev/null 2>&1; then
        target=$(printf 'bash\nzsh\n' | tv --no-preview --height 30%)
    else
        read -r -p 'Switch login shell to (bash/zsh): ' target
    fi
fi

case "$target" in
    bash|zsh) ;;
    *) printf 'Unknown shell: %s (try: bash, zsh)\n' "$target" >&2; exit 1 ;;
esac

current=$(getent passwd "$USER" | cut -d: -f7)
if [[ "$current" == "/usr/bin/$target" ]]; then
    echo "Already on $target."
    exit 0
fi

sudo usermod -s "/usr/bin/$target" "$USER"
echo "Done. Log out and back in, or 'exec $target -l' to swap now."
