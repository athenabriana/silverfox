# silverfox-skel-merge.sh — bootstrap Dotfiles do skel no primeiro login.
#
# Se ~/Dotfiles/ não existe, copia a árvore de /etc/skel/Dotfiles.
# Symlinks são gerenciados manualmente via `fox dotfiles link`.

if [ -z "${BASH_VERSION-}" ] && [ -z "${ZSH_VERSION-}" ]; then
    return
fi

[ -n "${SILVERFOX_SKEL_MERGE_RAN:-}" ] && return
SILVERFOX_SKEL_MERGE_RAN=1

SKEL_DOTFILES="${SKEL_DIR:-/etc/skel}/Dotfiles"
HOME_DOTFILES="$HOME/Dotfiles"
: "${HOME:?HOME must be set}"

[ -d "$SKEL_DOTFILES" ] || return

# Bootstrap único: ~/Dotfiles ainda não existe → copia a árvore inteira do skel
if [ ! -d "$HOME_DOTFILES" ]; then
    cp -a "$SKEL_DOTFILES" "$HOME_DOTFILES"
fi
