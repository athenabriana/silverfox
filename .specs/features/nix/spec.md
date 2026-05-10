# Nix on Host Specification

## Problem Statement

Sideral ships a curated CLI toolset (`sideral-cli-tools`) sourced from Fedora 44 main + Terra + a few third-party RPMs. Adding a new tool to that toolset requires editing the Containerfile and rebuilding the image — too much friction for personal/ad-hoc package needs (latest versions, niche utilities, anything outside the Fedora/Terra/Flathub surface). Nix as a parallel package manager fills this gap with low marginal cost per package via nixpkgs's much larger surface area.

The previous `nix-home` feature retired pre-VM-verification on 2026-05-01 because composefs + SELinux + `/nix`-disappears-after-`rpm-ostree-upgrade` on Fedora atomic 42+ made nix-on-atomic fragile. As of late 2026, the Determinate Systems `nix-installer` ships an `ostree` subcommand and `--persistence=/var/lib/nix` flag explicitly designed for this case — the previous blockers either fixed or have explicit workarounds. This spec re-opens the door using the new path.

## Goals

- [ ] After `rpm-ostree rebase` to a sideral image including this feature + reboot, `nix --version` resolves on every user shell without manual install steps
- [ ] Any user on the system can `nix profile install nixpkgs#<pkg>` and have the binary on their PATH
- [ ] `/nix/store` and per-user nix profiles survive `rpm-ostree upgrade` between sideral image rebases
- [ ] Existing sideral integrations (rpm-ostree, podman, mise, flatpak, stow seeds) coexist with nix without conflict

## Out of Scope

| Feature | Reason |
|---|---|
| home-manager | Retired with `nix-home` 2026-05-01. Stow + image-default seeds is the user-config layer. |
| NixOS modules | Sideral remains rpm-ostree atomic, not NixOS. |
| `nix-flatpak` flatpak management | NixOS-only module; sideral keeps `sideral-flatpaks` RPM as the flatpak management surface. |
| `devbox` | Tracked separately as a follow-on feature once nix is stable on the image (user request: "primeiro a spec do nix sozinho, depois adicionamos devbox"). |
| Pinned nixpkgs channel/flake in the image | Users manage channels themselves; image stays neutral on what nixpkgs revision they want. |
| User-level package preinstalls | Image ships nix functional + empty profile. What users install is per-user state, not image-default. |
| Migration tooling from rpm-ostree-layered tools to nix | If a user wants to move e.g. `helix` from `sideral-cli-tools` to a nix profile, that's a manual choice; no automation. |

---

## User Stories

### P1: Out-of-box nix availability ⭐ MVP

**User Story:** As a sideral user, I want `nix` to be available system-wide after `rpm-ostree rebase` + reboot, so I can install nixpkgs packages without going through any separate install procedure.

**Why P1:** This is the entire value proposition of "nix in the image" — eliminating the manual install step that the gist (and the prior `nix-home` feature) imposed.

**Acceptance Criteria:**

1. WHEN a user rebases to a sideral image including this feature and reboots THEN `nix --version` SHALL resolve on the first interactive shell (bash + zsh).
2. WHEN a non-sudo user runs `nix profile install nixpkgs#hello && hello` THEN the install SHALL succeed and `hello` SHALL print "Hello, world!".
3. WHEN multiple Linux user accounts on the same host install different nixpkgs packages THEN each user's profile SHALL be independent and isolated.
4. WHEN the system boots with composefs + `root.transient` THEN `/nix` SHALL be reachable as a real path without overlay interference.

**Independent Test:** `rpm-ostree rebase ostree-unverified-registry:ghcr.io/<owner>/sideral:latest && systemctl reboot`. After login: `nix profile install nixpkgs#hello && hello` returns "Hello, world!".

---

### P1: Persistence across rpm-ostree upgrade ⭐ MVP

**User Story:** As a user who installed nixpkgs packages, I want them to survive sideral image upgrades, so I don't lose state on every weekly rebase.

**Why P1:** Without persistence, nix is unusable in practice — every CI rebuild blows away every package the user installed.

**Acceptance Criteria:**

1. WHEN the sideral image is rebased to a new commit THEN `/nix/store` AND each user's `~/.local/state/nix` profile SHALL retain prior contents.
2. WHEN `rpm-ostree rollback` reverts to a previous deployment THEN nix profiles SHALL remain in the same state as before the rollback (state lives in `/var`, which is preserved across ostree generations).
3. WHEN a user runs `nix-collect-garbage -d` THEN unreferenced store paths SHALL be removed without affecting other users' profiles.

**Independent Test:** Install a package via `nix profile install`, force a sideral image bump (CI rerun), `rpm-ostree upgrade`, reboot, verify the package still resolves.

---

### P2: nix-daemon multi-user mode

**User Story:** As a host that may have multiple Linux user accounts, I want nix-daemon to run as a systemd service so users share a single `/nix/store` cleanly with proper privilege separation.

**Why P2:** Single-user mode works for personal use but blocks any second account from using nix. Multi-user mode is the standard daemon shape with minimal extra image weight; user explicitly accepted "pode ser global".

**Acceptance Criteria:**

1. WHEN the system boots THEN `nix-daemon.service` SHALL be active and enabled.
2. WHEN a non-privileged user runs `nix profile install <pkg>` THEN the daemon SHALL handle the build/copy via socket — no setuid required on the user-facing binaries.
3. WHEN nix-daemon crashes THEN systemd SHALL restart it within 5 seconds.
4. WHEN the image build creates the `nixbld1`..`nixbldN` build users THEN those UIDs SHALL be stable across image rebuilds (no UID churn).

**Independent Test:** `systemctl status nix-daemon.service` reports active. Create a second user with `useradd`; both users can `nix profile install` independently.

---

### P2: SELinux compatibility

**User Story:** As a sideral user on a default-enforcing system, I want nix operations to work without SELinux denials, so I don't have to switch to permissive mode or chase AVC errors.

**Why P2:** SELinux denials block nix transparently if /nix paths get mislabeled. Historically this was [nix-installer#1383](https://github.com/DeterminateSystems/nix-installer/issues/1383). Sideral should ship with correct contexts baked in or auto-relabeled.

**Acceptance Criteria:**

1. WHEN nix builds or installs a package THEN no AVC denials related to `/nix` SHALL appear in the audit log.
2. WHEN the image is rebased THEN `/nix` SHALL retain (or auto-restore) the correct SELinux file context.
3. WHEN the user runs `restorecon -RFv /nix` THEN no relabel SHALL occur (already correct).

**Independent Test:** `setenforce 1` (enforcing); `nix profile install nixpkgs#jq && jq --version`; `ausearch -m AVC -ts recent` returns no results referencing `/nix`.

---

### P3: Diagnostic `ujust nix-doctor` recipe

**User Story:** As a user troubleshooting a broken nix install, I want a `ujust nix-doctor` recipe that runs common sanity checks, so I don't have to remember the diagnostic commands.

**Why P3:** Nice-to-have. Not required for core function; just shortens the loop when something goes wrong (e.g., daemon stopped, SELinux relabel needed, channel out-of-date).

**Acceptance Criteria:**

1. WHEN a user runs `ujust nix-doctor` THEN the recipe SHALL print: nix version, `nix-daemon.service` status, `/nix` mount info, SELinux context of `/nix/store`, current channel list, current user's profile manifest count.
2. WHEN a check fails THEN the recipe SHALL print a one-line remediation hint (e.g., "Run `sudo restorecon -RFv /nix` to fix SELinux contexts").

**Independent Test:** Stop nix-daemon (`sudo systemctl stop nix-daemon.service`); run `ujust nix-doctor`; output flags daemon as inactive with a "run systemctl start nix-daemon" hint.

---

## Edge Cases

- WHEN a user rebases from an older sideral image (pre-nix) to the new one THEN `/var/lib/nix` SHALL be created cleanly on first boot — no migration logic needed since starting state is empty.
- WHEN `/etc/ostree/prepare-root.conf` was previously customized by the user THEN the sideral image SHALL NOT silently overwrite — the file is shipped with conflict-aware semantics so the user's version wins (user must reconcile manually if they want sideral's value).
- WHEN composefs is somehow disabled by a future Fedora update THEN nix SHALL still function — the persistence mechanism (`/var/lib/nix` bind/symlink to `/nix`) does not depend on composefs being on.
- WHEN `/var` fills up THEN nix operations SHALL fail with a clear "no space" error, not silently corrupt the store.
- WHEN the user runs `rpm-ostree rollback` to a deployment from before this feature shipped THEN nix-daemon SHALL be absent on the rolled-back deployment (the unit lived in the new image), but `/var/lib/nix` data SHALL remain — re-rolling-forward restores nix without data loss.

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
|---|---|---|---|
| NIX-01 | P1: Out-of-box availability — `nix --version` resolves on first shell | Design | Pending |
| NIX-02 | P1: Out-of-box availability — `nix profile install nixpkgs#hello` succeeds | Design | Pending |
| NIX-03 | P1: Out-of-box availability — multi-user profile isolation | Design | Pending |
| NIX-04 | P1: Out-of-box availability — composefs/root.transient compatibility | Design | Pending |
| NIX-05 | P1: Persistence — `/nix/store` + profiles survive rpm-ostree upgrade | Design | Pending |
| NIX-06 | P1: Persistence — rpm-ostree rollback preserves nix state | Design | Pending |
| NIX-07 | P1: Persistence — `nix-collect-garbage -d` works per-user | Design | Pending |
| NIX-08 | P2: Daemon — `nix-daemon.service` active + enabled at boot | Design | Pending |
| NIX-09 | P2: Daemon — non-privileged users install via socket, no setuid | Design | Pending |
| NIX-10 | P2: Daemon — systemd Restart= within 5s on crash | Design | Pending |
| NIX-11 | P2: Daemon — stable nixbld UIDs across image rebuilds | Design | Pending |
| NIX-12 | P2: SELinux — no AVC denials in default-enforcing mode | Design | Pending |
| NIX-13 | P2: SELinux — contexts retained / auto-restored on rebase | Design | Pending |
| NIX-14 | P3: ujust nix-doctor — sanity-check recipe | Design | Pending |
| NIX-15 | P3: ujust nix-doctor — remediation hints on failure | Design | Pending |

**ID format:** `NIX-NN`. **Status values:** Pending → In Design → In Tasks → Implementing → Verified.

**Coverage:** 15 total, 0 mapped to tasks (spec phase only).

---

## Success Criteria

- [ ] Fresh user account on a freshly-rebased sideral system can `nix profile install nixpkgs#hello && hello` without sudo, without manual setup, within ~3 minutes (channel pull + build).
- [ ] After 4 weekly rebases (sideral CI cuts new tags), the user's installed nix packages still resolve (no state loss).
- [ ] `nix-daemon.service` shows zero unit failures in `systemctl status`.
- [ ] `ausearch -m AVC -ts boot` shows zero AVC denials related to `/nix` after a representative day of nix usage.
