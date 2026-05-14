# home.just — subcomandos `fox home <verb>`.
# O dispatcher (fox home <verb>) roteia para home::<verb>.

# Destroi ~/Dotfiles/ e recopia do /etc/skel/Dotfiles, depois reaplica stow
reset:
    #!/usr/bin/bash
    set -euo pipefail
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
