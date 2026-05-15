# silverfox-home-sync.sh — bootstrap e sync do home do usuário em todo login.
#
# Roda uma vez por sessão:
#   1. Se ~/Dotfiles/ não existe, copia de /etc/skel/Dotfiles (primeiro login)
#   2. Aplica symlinks via stow em cada pacote de ~/Dotfiles
#   3. Sincroniza configuração nix via nh home switch (background)
#   4. Garante tema base16 padrão se nenhum foi aplicado ainda

if [ -z "${BASH_VERSION-}" ] && [ -z "${ZSH_VERSION-}" ]; then
    return
fi

[ -n "${SILVERFOX_HOME_SYNC_RAN:-}" ] && return
SILVERFOX_HOME_SYNC_RAN=1

SKEL_DOTFILES="${SKEL_DIR:-/etc/skel}/Dotfiles"
HOME_DOTFILES="$HOME/Dotfiles"
: "${HOME:?HOME must be set}"

[ -d "$SKEL_DOTFILES" ] || return

# Bootstrap único: ~/Dotfiles ainda não existe → copia a árvore inteira do skel
if [ ! -d "$HOME_DOTFILES" ]; then
    cp -a "$SKEL_DOTFILES" "$HOME_DOTFILES"
fi

# Aplica symlinks via stow para cada pacote
if command -v stow >/dev/null 2>&1 && [ -d "$HOME_DOTFILES" ]; then
    while IFS= read -r -d '' pkg; do
        stow -d "$HOME_DOTFILES" -t "$HOME" --no-folding "${pkg##*/}" 2>/dev/null || true
    done < <(find "$HOME_DOTFILES" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
fi

# Sincroniza home-manager nix em background para não travar o login
if command -v nh >/dev/null 2>&1; then
    nh home switch --impure >"$HOME/.cache/silverfox-home-sync.log" 2>&1 & disown
fi

# Garante tema base16 padrão se nenhum foi aplicado ainda
if command -v flavours >/dev/null 2>&1; then
    if ! flavours current >/dev/null 2>&1; then
        flavours apply onedark >/dev/null 2>&1 || true
    fi
    # Sempre importa o tema atual no COSMIC (single source of truth)
    _cosmic_theme="$HOME/.cache/silverfox/cosmic-theme.ron"
    if command -v cosmic-settings >/dev/null 2>&1 && [ -f "$_cosmic_theme" ]; then
        cosmic-settings appearance import "$_cosmic_theme" >/dev/null 2>&1 || true
    fi
    # Reload ghostty config (no-op se não tiver janela aberta)
    if pgrep -x ghostty >/dev/null 2>&1; then
        gdbus call --session --dest com.mitchellh.ghostty \
            --object-path /com/mitchellh/ghostty \
            --method org.gtk.Actions.Activate reload-config '[]' '{}' >/dev/null 2>&1 \
            || pkill -USR2 ghostty 2>/dev/null \
            || true
    fi
fi
