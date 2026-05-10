# Nix on Host Context

**Gathered:** 2026-05-10
**Spec:** `.specs/features/nix/spec.md`
**Status:** Ready for design

---

## Feature Boundary

Ship nix on the sideral image so it's available system-wide after `rpm-ostree rebase` + reboot, with `/nix` state persisting across image upgrades. Multi-user (daemon) mode. No NixOS modules, no home-manager, no per-project (devbox) layer — just `nix` as a parallel package manager users can `nix profile install <pkg>` from. devbox is a separate follow-up feature.

---

## Implementation Decisions

### D-01 — Image-baked, not user-installed

- **Decision:** Sideral image ships nix as a built-in. User does NOT run any install command post-rebase.
- **Why:** User stated "queria que nix vinhesse na imagem" (2026-05-10). Avoids the manual flip-of-composefs + curl-of-installer dance the gist would otherwise require every user to perform.
- **Trade accepted:** Every sideral user gets nix whether they want it or not. Surface area of the image grows. Removable later via `rpm-ostree override remove` if a user opts out.

### D-02 — Multi-user (`nix-daemon`) mode

- **Decision:** Run `nix-daemon` as a systemd system service; `nixbld1..N` build users created at image build time. Single-user mode rejected.
- **Why:** User stated "pode ser global, n ligo pra qtd de users" (2026-05-10). Multi-user is the standard daemon shape and makes a second Linux user account "just work" without re-installing.
- **Trade accepted:** Slightly heavier — daemon process at boot, ~32 nixbld system users. Not material on a desktop.

### D-03 — Composefs + `root.transient`, not composefs disabled

- **Decision:** Image ships `/etc/ostree/prepare-root.conf` configured for composefs `enabled = yes` + root `transient = true`. Composefs is NOT disabled.
- **Why:** Keeps the tamper-evident root + immutable composefs benefits intact. Transient root means changes to `/` outside `/var`, `/etc`, `/opt` don't persist — which is fine because nix lives in `/var/lib/nix` (persistent) symlinked/bind-mounted to `/nix`. This is the more atomic-spirited of the two gist options.
- **Trade accepted:** Anything written ad-hoc to `/usr` or `/srv` etc. doesn't survive reboot. Sideral users shouldn't be writing there anyway on an atomic image.

### D-04 — `/nix` persistence at `/var/lib/nix`

- **Decision:** Use Determinate Systems' `nix-installer` `ostree` subcommand semantics with `--persistence=/var/lib/nix`. Nix store data lives in `/var/lib/nix`; `/nix` is the path nix tools see (via bind-mount or symlink, design phase decides which).
- **Why:** `/var` is preserved across rpm-ostree generations by design. Sideral image rebases don't touch user-installed nix packages. This addresses historic blocker [nix-installer#1383 / #1445](https://github.com/DeterminateSystems/nix-installer/issues) without the legacy bind-mount-by-hand pattern the gist deprecated.

### D-05 — No declarative state in the image (channels, profiles)

- **Decision:** Image ships nix + nix-daemon, period. No nixpkgs channel pinned, no flake registry preconfigured, no profile preinstalls.
- **Why:** Each user picks their own nixpkgs revision and packages. Image stays neutral; users own the policy.
- **Trade accepted:** First-time users hit a "what do I do now?" moment. The `ujust nix-doctor` recipe (P3) and a brief README section will point them at `nix-channel --add nixpkgs https://nixos.org/channels/nixpkgs-unstable && nix-channel --update`.

### D-06 — No coupling to existing sideral packaging

- **Decision:** Existing `sideral-cli-tools`, `sideral-flatpaks`, `sideral-stow-defaults` stay unchanged. Nix is purely additive — no tool migrates from rpm-ostree to nix as part of this feature.
- **Why:** Migration is a per-user choice (user might want to swap `helix` from RPM to nix profile, or might not). Forcing migrations would balloon scope and break the `command -v` guards in shell init.

### Agent's Discretion (design phase)

- Whether to install nix at OCI-image-build-time (Containerfile RUN step) vs. first-boot systemd oneshot. Both are valid; pick whichever produces a cleaner image + boot UX. Default lean: first-boot oneshot, because the DS installer is designed to run on a deployed atomic system, not inside a `podman build` sandbox.
- Whether `/nix` is implemented as a symlink to `/var/lib/nix` or a bind-mount via systemd `.mount` unit. Symlink is simpler; bind-mount is more transparent to tools that stat the path. Pick based on what works cleanly with the DS installer's `ostree` mode.
- Exact name and shape of the systemd oneshot unit (if used) — `sideral-nix-bootstrap.service`, `nix-installer-bootstrap.service`, etc. Cosmetic.
- Whether to ship a sudoers.d snippet that adds `/nix/var/nix/profiles/default/bin` to `secure_path` — yes per the gist's recommendation, but exact filename/path is design.
- Whether `ujust nix-doctor` lives in the existing `60-custom.just` or gets its own `61-nix.just`. Cosmetic; lean toward `60-custom.just` for consistency.

---

## Specific References

- The gist the user shared: https://gist.github.com/queeup/1666bc0a5558464817494037d612f094 — current method (DS installer `ostree` subcommand + `--persistence=/var/lib/nix`) is the reference implementation; legacy bind-mount method is explicitly obsolete.
- Determinate Systems `nix-installer`: https://github.com/DeterminateSystems/nix-installer — the `ostree` subcommand is the upstream-blessed atomic path.
- Historical retirement: `.specs/features/chezmoi-home/context.md` D-01 documents why `nix-home` retired (composefs vs ostree planner, SELinux mislabel, /nix-disappears-after-upgrade). Two of three are addressed by `--persistence` + `ostree` subcommand; SELinux is the remaining open question for verification (NIX-12, NIX-13).

---

## Deferred Ideas

- **devbox integration** — user explicitly deferred ("primeiro a spec do nix sozinho, depois adicionamos devbox"). Tracked as a follow-on spec under `.specs/features/devbox/` once `nix` ships and stabilizes.
- **Pinned/curated nixpkgs channel in the image** — deferred to a hypothetical future spec. The trade is reproducibility (pin → everyone gets the same nixpkgs surface) vs flexibility (no pin → users pick). For a personal image, no pin is fine; revisit if/when sideral becomes shareable.
- **Migration of `sideral-cli-tools` packages from rpm-ostree to nix profile** — out of scope; not a system goal. If specific tools later prove a better fit in nix (latest version pacing, niche packages), individual moves can be one-off PRs.
- **`nix-flatpak` for declarative flatpak management** — NixOS-only, will not work on rpm-ostree atomic. Not deferred — explicitly out of scope.
- **home-manager** — explicitly retired (see `.specs/features/nix-home/`). Not coming back as part of this feature.
