# home.just — `fox home <verb>` module. Loaded as `mod home` from
# sideral.justfile. v1 ships exactly one verb (factory-reset); v2 grows
# `sync` (declarative TOML manifests under ~/.config/sideral/manifests/).

# Hard-reset sideral-managed paths in $HOME from /etc/skel
factory-reset *args:
    /usr/libexec/sideral/home-factory-reset.sh {{args}}
