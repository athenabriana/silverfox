# sideral.justfile — operator-CLI recipe surface, dispatched by /usr/bin/fox.
# Verbs: chsh, cheatsheet, update, upgrade, rollback, status, cleanup,
# changelog (top-level) + home::factory-reset (module).

default:
    @just -f {{ justfile() }} --list

# Switch login shell (no arg = interactive picker; allowlist: bash, zsh)
chsh shell="":
    /usr/libexec/sideral/chsh.sh {{shell}}

# Open the sideral cheatsheet manpage (man 7 sideral)
cheatsheet:
    exec man 7 sideral

# Update installed flatpaks
update *args:
    flatpak update {{args}}

# Stage rpm-ostree upgrade for the next boot
upgrade *args:
    rpm-ostree upgrade {{args}}
    @echo "Reboot to apply the staged deployment."

# Roll back to the previous rpm-ostree deployment
rollback *args:
    rpm-ostree rollback {{args}}
    @echo "Reboot to apply."

# Show rpm-ostree deployment status
status *args:
    rpm-ostree status {{args}}

# Clean rpm-ostree state (default: -prm = pending + repomd + metadata)
cleanup *args:
    rpm-ostree cleanup {{ if args == "" { "-prm" } else { args } }}

# Show RPM diff vs the pending or previous deployment
changelog *args:
    rpm-ostree db diff {{args}}

mod home
