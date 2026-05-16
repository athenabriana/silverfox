# flatpak/default.nix — flatpak apps managed declaratively.
#
# Reads remotes and packages from flatpak.toml. Edit the TOML file
# and run `nh home switch` to sync.

{ pkgs, ... }:

{

  home.packages = [ pkgs.flatpak ];

  home.file.".config/flatpak.toml".source = ./flatpak.toml;

  home.activation.flatpakManagement =
    let
      toml = fromTOML (builtins.readFile ./flatpak.toml);
      flatpakBin = "${pkgs.flatpak}/bin/flatpak --user";

      remotesDecl = pkgs.lib.concatStringsSep "\n" (
        pkgs.lib.mapAttrsToList (name: url: "    [${name}]=${url}") (toml.remotes or { })
      );

      packagesDecl = pkgs.lib.concatStringsSep "\n" (
        pkgs.lib.mapAttrsToList (app: remote: "    [${app}]=${remote}") (toml.packages or { })
      );
    in
    ''
      declare -A remotes=(
        ${remotesDecl}
      )

      declare -A packages=(
        ${packagesDecl}
      )

      for name in "''${!remotes[@]}"; do
        $DRY_RUN_CMD ${flatpakBin} remote-add --if-not-exists "$name" "''${remotes[$name]}"
      done

      for pkg in $(${flatpakBin} list --app --columns=application); do
        if [[ -z "''${packages[$pkg]+x}" ]]; then
          $DRY_RUN_CMD ${flatpakBin} uninstall -y --noninteractive "$pkg"
        fi
      done

      for app in "''${!packages[@]}"; do
        $DRY_RUN_CMD ${flatpakBin} install -y --noninteractive "''${packages[$app]}" "$app"
      done

      $DRY_RUN_CMD ${flatpakBin} uninstall --unused -y
      $DRY_RUN_CMD ${flatpakBin} update -y
    '';

}
