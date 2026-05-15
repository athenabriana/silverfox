# silverfox.justfile — operator-CLI recipe surface, dispatched by /usr/bin/fox.
# Verbs: chsh, clean, dotfiles-edit, dotfiles-link, dotfiles-reset,
# firmware-upgrade, home-diff, home-doctor, home-sync, motd-toggle,
# os-changelog, os-rollback, os-status, os-upgrade,
# theme-apply, theme-current, theme-update (top-level).

default:
    @just -f {{ justfile() }} --list

# Switch login shell (no arg = gum choose; allowlist: bash, zsh)
chsh shell="":
    #!/usr/bin/bash
    set -euo pipefail
    target="{{shell}}"
    if [[ -z "$target" ]]; then
        target=$(gum choose bash zsh)
    fi
    case "$target" in
        bash|zsh) ;;
        *) echo "Unknown shell: $target (try: bash, zsh)" >&2; exit 1 ;;
    esac
    current=$(getent passwd "$USER" | cut -d: -f7)
    if [[ "$current" == "/usr/bin/$target" ]]; then
        echo "Already on $target."
        exit 0
    fi
    sudo usermod -s "/usr/bin/$target" "$USER"
    echo "Done. Log out and back in, or 'exec $target -l' to swap now."

# Clean podman images, rpm-ostree metadata, and nix store;
# with explicit args, passes through to rpm-ostree cleanup
clean *args:
    #!/usr/bin/bash
    if [ $# -eq 0 ]; then
      gum confirm "Limpar imagens podman, cache rpm-ostree e nix store?" || exit 0
      podman image prune -af
      rpm-ostree cleanup -prm
      command -v nh >/dev/null 2>&1 && nh clean || echo "nh not installed, skipping nix cleanup"
    else
      rpm-ostree cleanup "$@"
    fi

# Open ~/Dotfiles in $EDITOR
dotfiles-edit:
    exec $EDITOR ~/Dotfiles

# Aplica symlinks de ~/Dotfiles em $HOME via stow
dotfiles-link:
    #!/usr/bin/bash
    set -euo pipefail
    command -v stow >/dev/null 2>&1 || { echo "stow não encontrado" >&2; exit 1; }
    [ -d "$HOME/Dotfiles" ] || { echo "~/Dotfiles não existe" >&2; exit 1; }
    find "$HOME/Dotfiles" -mindepth 1 -maxdepth 1 -type d -print0 \
      | while IFS= read -r -d '' pkg; do
          stow -R -d "$HOME/Dotfiles" -t "$HOME" --no-folding "${pkg##*/}"
        done
    echo "dotfiles: symlinks aplicados."

# Destroi ~/Dotfiles e recopia de /etc/skel/Dotfiles, depois reaplica stow
dotfiles-reset:
    #!/usr/bin/bash
    set -euo pipefail
    gum confirm "Destruir ~/Dotfiles e restaurar do /etc/skel?" || exit 0
    SKEL_DOTFILES="/etc/skel/Dotfiles"
    HOME_DOTFILES="$HOME/Dotfiles"
    [ -d "$SKEL_DOTFILES" ] || { echo "/etc/skel/Dotfiles não encontrado" >&2; exit 1; }
    echo "Removendo $HOME_DOTFILES..."
    rm -rf "$HOME_DOTFILES"
    echo "Copiando de $SKEL_DOTFILES..."
    cp -a "$SKEL_DOTFILES" "$HOME_DOTFILES"
    echo "Aplicando symlinks via stow..."
    command -v stow >/dev/null 2>&1 || { echo "stow não encontrado" >&2; exit 1; }
    find "$HOME_DOTFILES" -mindepth 1 -maxdepth 1 -type d -print0 \
      | while IFS= read -r -d '' pkg; do
          stow -R -d "$HOME_DOTFILES" -t "$HOME" --no-folding "${pkg##*/}"
        done
    echo "dotfiles reset: concluído."

# Atualiza firmware do dispositivo (fwupdmgr)
firmware-upgrade:
    fwupdmgr refresh --force
    fwupdmgr get-updates
    fwupdmgr update

# Mostra pending nix config changes (dry-run)
home-diff:
    #!/usr/bin/bash
    nh home switch --impure --dry 2>/dev/null \
      || echo "Dry-run not available. Run 'fox home-sync' to apply."

# Diagnose nix + nh health — version, daemon, mount, SELinux, flake
home-doctor:
    #!/usr/bin/bash
    echo "=== nix version ==="
    nix --version 2>&1 || echo "NOT FOUND"
    echo "=== nix-daemon ==="
    if systemctl is-active nix-daemon >/dev/null 2>&1; then
      echo "active"
    else
      echo "NOT ACTIVE (try: sudo systemctl start nix-daemon)"
    fi
    echo "=== /nix mount ==="
    if findmnt /nix >/dev/null 2>&1; then
      echo "$(findmnt -n -o SOURCE /nix) → /nix"
    else
      echo "NOT MOUNTED (nix bootstrap may not have run yet)"
    fi
    echo "=== SELinux /nix/store ==="
    if [ -d /nix/store ]; then
      ls -Z /nix/store 2>&1 | head -1
    else
      echo "NOT ACCESSIBLE — /nix/store does not exist"
    fi
    echo "=== nh version ==="
    nh --version 2>&1 || echo "NOT INSTALLED (run 'fox home-sync')"
    echo "=== NH_FLAKE ==="
    echo "${NH_FLAKE:-<unset>}"
    echo "=== flake symlink ==="
    if [ -L "$HOME/.config/nix/flake.nix" ]; then
      echo "symlink: $(readlink -f "$HOME/.config/nix/flake.nix")"
      nix flake check "$HOME/.config/nix" 2>&1 || echo "flake check FAILED — run 'fox home-sync' to update"
    else
      echo "~/.config/nix/flake.nix not found or not a symlink"
      echo "Run 'fox home-sync' to set up the starter flake."
    fi

# Sync nix config (dotfiles + pacotes + flatpaks declarativos)
home-sync *args:
    #!/usr/bin/bash
    just -f {{ justfile() }} dotfiles-link
    command -v nh >/dev/null 2>&1 && nh home switch --impure

# Toggle display of the login banner
motd-toggle:
    #!/usr/bin/bash
    if test -e "${HOME}/.config/no-show-user-motd"; then
      rm -f "${HOME}/.config/no-show-user-motd"
      echo "Banner enabled on next login."
    else
      mkdir -p "${HOME}/.config"
      touch "${HOME}/.config/no-show-user-motd"
      echo "Banner disabled."
    fi

# Show RPM diff vs the pending or previous deployment
os-changelog *args:
    rpm-ostree db diff {{args}}

# Roll back to the previous rpm-ostree deployment
os-rollback *args:
    #!/usr/bin/bash
    gum confirm "Fazer rollback para o deployment anterior?" || exit 0
    rpm-ostree rollback {{args}}
    echo "Reboot to apply."

# Show rpm-ostree deployment status
os-status *args:
    rpm-ostree status {{args}}

# Stage rpm-ostree upgrade
os-upgrade *args:
    rpm-ostree upgrade
    @echo "Reboot to apply the staged deployment."

# Aplica um tema base16 (sem arg: seleção interativa via gum filter)
theme-apply theme="":
    #!/usr/bin/bash
    set -euo pipefail
    theme="{{theme}}"
    if [[ -z "$theme" ]]; then
        theme=$(flavours list | gum filter --placeholder "buscar tema…")
    fi
    gum spin --spinner dot --title "Aplicando $theme…" -- flavours apply "$theme"

# Mostra o tema base16 ativo no momento
theme-current:
    flavours current

# Atualiza a lista de temas base16
theme-update:
    flavours update
