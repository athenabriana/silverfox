{lib, ...}: {
  imports =
    [
      ./common.nix
      ../modules/nvidia
    ]
    # On installed systems, install.sh symlinks the calamares-generated
    # hardware-configuration.nix into the flake root so this picks it up.
    # On CI checkouts the file doesn't exist; the optional eats to [].
    ++ lib.optional (builtins.pathExists ../hardware-configuration.nix) ../hardware-configuration.nix;

  networking.hostName = "sideral";
  system.nixos.variant_id = "nvidia";
}
