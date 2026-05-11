#!/usr/bin/env bash
# factory-reset.test.sh — end-to-end tests against
# libexec/home-factory-reset.sh with tmpfs fixtures.
set -euo pipefail

export SUITE=factory-reset
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib.sh disable=SC1091
source "$HERE/lib.sh"

SCRIPT="$HERE/../libexec/home-factory-reset.sh"
[[ -x "$SCRIPT" ]] || chmod +x "$SCRIPT"

# Build a deterministic skel fixture each test case borrows from.
build_skel() {
    local dir="$1"
    mkdir -p "$dir/.config/sideral/stow/bash" "$dir/.config/sideral/stow/zsh" \
             "$dir/.config/mise" "$dir/.config/ghostty" "$dir/.config/zed"
    echo "# bashrc image default" >"$dir/.config/sideral/stow/bash/.bashrc"
    echo "# zshrc image default"  >"$dir/.config/sideral/stow/zsh/.zshrc"
    echo 'node = "lts"'            >"$dir/.config/mise/config.toml"
    echo "ghostty default"         >"$dir/.config/ghostty/config"
    echo '{}'                      >"$dir/.config/zed/settings.json"
    ln -sf .config/sideral/stow/bash/.bashrc "$dir/.bashrc"
    ln -sf .config/sideral/stow/zsh/.zshrc   "$dir/.zshrc"
}

echo "── factory-reset.test.sh ──"

# 1. --yes anywhere: applies non-interactively.
SKEL=$(mktmpdir); HOME_F=$(mktmpdir)
build_skel "$SKEL"
mkdir -p "$HOME_F/.config/firefox"; echo "user-firefox" >"$HOME_F/.config/firefox/profile.ini"
mkdir -p "$HOME_F/.config/sideral/stow/bash"
echo "user edit" >"$HOME_F/.config/sideral/stow/bash/custom.sh"
SKEL_DIR="$SKEL" HOME="$HOME_F" bash "$SCRIPT" --yes >/dev/null 2>&1
[[ -e "$HOME_F/.config/sideral/stow/bash/.bashrc" ]] && actual=1 || actual=0
assert_eq "yes_applies" "1" "$actual"
[[ -e "$HOME_F/.config/sideral/stow/bash/custom.sh" ]] && actual=1 || actual=0
assert_eq "yes_wipes_user_addition" "0" "$actual"
[[ -e "$HOME_F/.config/firefox/profile.ini" ]] && actual=1 || actual=0
assert_eq "yes_preserves_non_sideral" "1" "$actual"
rm -rf "$SKEL" "$HOME_F"

# 2. --yes mid-argv (not just $1) also accepted.
SKEL=$(mktmpdir); HOME_F=$(mktmpdir); build_skel "$SKEL"
set +e
SKEL_DIR="$SKEL" HOME="$HOME_F" bash "$SCRIPT" -y >/dev/null 2>&1
rc=$?
set -e
assert_exit "short_yes_flag" "0" "$rc"
rm -rf "$SKEL" "$HOME_F"

# 3. Unknown flag → exit 1, error in stderr.
SKEL=$(mktmpdir); HOME_F=$(mktmpdir); build_skel "$SKEL"
set +e
err=$(SKEL_DIR="$SKEL" HOME="$HOME_F" bash "$SCRIPT" --banana 2>&1 >/dev/null)
rc=$?
set -e
assert_exit "unknown_flag_exit" "1" "$rc"
assert_contains "unknown_flag_msg" "unknown flag: --banana" "$err"
rm -rf "$SKEL" "$HOME_F"

# 4. Non-TTY without --yes → exit 1, "no TTY" in stderr.
SKEL=$(mktmpdir); HOME_F=$(mktmpdir); build_skel "$SKEL"
set +e
err=$(SKEL_DIR="$SKEL" HOME="$HOME_F" bash "$SCRIPT" </dev/null 2>&1 >/dev/null)
rc=$?
set -e
assert_exit "no_tty_exit" "1" "$rc"
assert_contains "no_tty_msg" "no TTY available" "$err"
rm -rf "$SKEL" "$HOME_F"

# 5. PTY + "y\n" applies; PTY + "n\n" cancels.
if command -v script >/dev/null 2>&1; then
    SKEL=$(mktmpdir); HOME_F=$(mktmpdir); build_skel "$SKEL"
    out=$(SKEL_DIR="$SKEL" HOME="$HOME_F" run_with_pty $'y\n' -- "bash $SCRIPT" 2>&1)
    [[ -e "$HOME_F/.config/sideral/stow/bash/.bashrc" ]] && actual=1 || actual=0
    assert_eq "pty_y_applies" "1" "$actual"
    assert_contains "pty_y_summary" "Reset" "$out"
    rm -rf "$SKEL" "$HOME_F"

    SKEL=$(mktmpdir); HOME_F=$(mktmpdir); build_skel "$SKEL"
    out=$(SKEL_DIR="$SKEL" HOME="$HOME_F" run_with_pty $'n\n' -- "bash $SCRIPT" 2>&1)
    [[ -e "$HOME_F/.config/sideral/stow/bash/.bashrc" ]] && actual=1 || actual=0
    assert_eq "pty_n_skips" "0" "$actual"
    assert_contains "pty_n_cancelled" "Cancelled" "$out"
    rm -rf "$SKEL" "$HOME_F"
else
    echo "  skip pty_* tests (script(1) not available)"
fi

summary
