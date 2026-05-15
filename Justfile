# Silverfox OS — local build + rebase recipes.
#   list:    `just`
#   build:   `just build`
#   rebase:  `just rebase`

image_name := "silverfox"
image_tag  := "dev"
registry   := env_var_or_default("REGISTRY", "localhost")

default:
    @just --list --unsorted

# Build image locally with podman
build:
    podman build \
        --tag {{registry}}/{{image_name}}:{{image_tag}} \
        --file os/Containerfile \
        os

# Shellcheck every build script (chains fox-lint after the OS lib/modules sweep)
lint: fox-lint
    shellcheck os/lib/*.sh os/modules/*/*.sh

# Shellcheck + bash syntax for fox dispatcher / tests
fox-lint:
    bash -n os/modules/fox/src/bin/fox
    shellcheck -x \
        os/modules/fox/src/bin/fox \
        os/modules/fox/src/tests/lib.sh \
        os/modules/fox/src/tests/fox.test.sh

# Run fox integration tests
fox-test:
    bash os/modules/fox/src/tests/fox.test.sh

    @echo "Preview: man -l /tmp/silverfox.7"

# Rebase host to the locally-built image (requires reboot after)
rebase:
    sudo rpm-ostree rebase \
        ostree-unverified-image:containers-storage:{{registry}}/{{image_name}}:{{image_tag}}
    @echo "Now run: systemctl reboot"

# Pull the CI-built image and rebase to it
rebase-latest gh_user:
    sudo rpm-ostree rebase \
        ostree-unverified-registry:ghcr.io/{{gh_user}}/{{image_name}}:latest
    @echo "Now run: systemctl reboot"

# Remove the local dev image
clean:
    -podman rmi {{registry}}/{{image_name}}:{{image_tag}}

# Show RPM-level diff vs the current deployment
diff:
    sudo rpm-ostree db diff

# Rollback to the previous deployment
rollback:
    sudo rpm-ostree rollback
    @echo "Now run: systemctl reboot"
