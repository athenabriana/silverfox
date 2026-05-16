# home/default.nix — user identity + globally-installed packages.
#
# username/homeDirectory use the __USER__ placeholder and stateVersion
# uses __STATE_VERSION__; both are substituted at first-login by
# silverfox-home-sync.sh (which delegates to `fox dotfiles-sync`).
# To customize, edit this file and run `fox sync`.

{ pkgs, ... }:
{
  home = {
    username = "__USER__";
    homeDirectory = "/home/__USER__";
    stateVersion = "__STATE_VERSION__";
    packages = [
      pkgs.atuin
      pkgs.fzf
      pkgs.bat
      pkgs.eza
      pkgs.ripgrep
      pkgs.zoxide
      pkgs.gh
      pkgs.git-lfs
      pkgs.gcc
      pkgs.gnumake
      pkgs.cmake
    ];
  };
}
