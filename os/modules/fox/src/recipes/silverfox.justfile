# silverfox.justfile — operator-CLI recipe surface, dispatched by /usr/bin/fox.
# Verbs: chsh, clean, dotfiles-edit, dotfiles-link, dotfiles-reset,
# firmware-upgrade, home-diff, home-doctor, home-sync, home-theme, motd-toggle,
# os-changelog, os-rollback, os-status, os-upgrade (top-level).

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
    echo "=== flake ==="
    _flake_dir="${NH_FLAKE:-$HOME/.config/nix}"
    if [ -e "$_flake_dir/flake.nix" ]; then
      echo "found: $_flake_dir/flake.nix"
      [ -f "$_flake_dir/flake.lock" ] && echo "lock: ok" || echo "lock: ausente (run 'nix flake update' para gerar)"
    elif [ -L "$HOME/.config/nix/flake.nix" ]; then
      _resolved=$(readlink -f "$HOME/.config/nix/flake.nix")
      echo "symlink: $_resolved"
      _lock_dir=$(dirname "$_resolved")
      [ -f "$_lock_dir/flake.lock" ] && echo "lock: ok" || echo "lock: ausente"
    else
      echo "flake não encontrado em $_flake_dir nem em ~/.config/nix"
      echo "Run 'fox home-sync' to set up the starter flake."
    fi

# Sync nix config (dotfiles + pacotes + flatpaks declarativos)
home-sync *args:
    #!/usr/bin/bash
    just -f {{ justfile() }} dotfiles-link
    if command -v nh >/dev/null 2>&1; then
        echo "nix/home-manager: aplicando configuração…"
        nh home switch --impure
    else
        echo "nh não encontrado — pulando sincronização nix."
    fi
    if command -v flavours >/dev/null 2>&1; then
        _data="${XDG_DATA_HOME:-$HOME/.local/share}/flavours"
        if [ ! -d "$_data/base16/schemes" ]; then
            echo "flavours: baixando temas…"
            flavours update all 2>&1 || echo "flavours: aviso — alguns temas não puderam ser baixados."
        fi
        if ! flavours current >/dev/null 2>&1; then
            echo "flavours: aplicando tema padrão…"
            flavours apply onedark
        fi
        _cosmic_theme="$HOME/.cache/silverfox/cosmic-theme.ron"
        if command -v cosmic-settings >/dev/null 2>&1 && [ -f "$_cosmic_theme" ]; then
            cosmic-settings appearance import "$_cosmic_theme" >/dev/null 2>&1 \
                && echo "cosmic: tema importado." \
                || echo "cosmic: aviso — import falhou."
        fi
        # Reload ghostty config (SIGUSR2 via systemd or pkill fallback)
        if pgrep -x ghostty >/dev/null 2>&1; then
            gdbus call --session --dest com.mitchellh.ghostty \
                --object-path /com/mitchellh/ghostty \
                --method org.gtk.Actions.Activate reload-config '[]' '{}' >/dev/null 2>&1 \
                || pkill -USR2 ghostty 2>/dev/null \
                || true
        fi
    fi

# Mostra padrão da distro e tema atual; oferece lista para escolher e aplicar
home-theme:
    #!/usr/bin/bash
    set -euo pipefail
    _default_dark="onedark"
    _default_light="one-light"
    _actual_current=$(flavours current 2>/dev/null || true)
    echo "padrão da distro : $_default_dark / $_default_light"
    echo "tema atual       : ${_actual_current:-(nenhum)}"
    echo ""
    _data="${XDG_DATA_HOME:-$HOME/.local/share}/flavours"
    if [ ! -d "$_data/base16/schemes" ]; then
        gum confirm "Temas não baixados. Baixar agora?" || exit 0
        flavours update all 2>&1 || echo "aviso: alguns temas não puderam ser baixados."
    fi
    _chosen=$(
        {
            if [ -n "$_actual_current" ] \
                && [ "$_actual_current" != "$_default_dark" ] \
                && [ "$_actual_current" != "$_default_light" ]; then
                echo "$_actual_current"
            fi
            echo "$_default_dark"
            echo "$_default_light"
            flavours list | tr ' ' '\n' \
                | grep -vxF "$_default_dark" \
                | grep -vxF "$_default_light" \
                | grep -vxF "${_actual_current:-__none__}"
        } | gum filter --placeholder "buscar tema…"
    ) || exit 0
    if [ -z "$_chosen" ]; then exit 0; fi
    gum spin --spinner dot --title "Aplicando $_chosen…" -- flavours apply "$_chosen"
    _cosmic_theme="$HOME/.cache/silverfox/cosmic-theme.ron"
    if command -v cosmic-settings >/dev/null 2>&1 && [ -f "$_cosmic_theme" ]; then
        cosmic-settings appearance import "$_cosmic_theme" >/dev/null 2>&1 || true
    fi
    if pgrep -x ghostty >/dev/null 2>&1; then
        gdbus call --session --dest com.mitchellh.ghostty \
            --object-path /com/mitchellh/ghostty \
            --method org.gtk.Actions.Activate reload-config '[]' '{}' >/dev/null 2>&1 \
            || pkill -USR2 ghostty 2>/dev/null \
            || true
    fi
    echo "tema aplicado: $_chosen"

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

