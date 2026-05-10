{
  description = "sideral — niri compositor + Noctalia shell on NixOS.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    # noctalia-shell + noctalia-qs landed in nixos-unstable but haven't
    # made it to the 25.11 release yet. Cherry-pick from unstable via
    # an overlay; the rest of the system stays on the stable channel.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-flatpak.url = "github:gmodena/nix-flatpak";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    nixpkgs-unstable,
    home-manager,
    nix-flatpak,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    unstable = nixpkgs-unstable.legacyPackages.${system};

    overlay-unstable = _final: _prev: {
      inherit (unstable) noctalia-shell noctalia-qs;
    };

    mkSystem = host:
      nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          host
          {nixpkgs.overlays = [overlay-unstable];}
        ];
        specialArgs = {inherit inputs self;};
      };
  in {
    nixosConfigurations = {
      sideral = mkSystem ./hosts/sideral.nix;
      sideral-nvidia = mkSystem ./hosts/sideral-nvidia.nix;
    };

    formatter.${system} = pkgs.alejandra;
  };
}
