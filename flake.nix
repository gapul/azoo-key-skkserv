{
  description = "azoo-key-skkserv: an skkserv backed by AzooKeyKanaKanjiConverter (Linux / NixOS)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      # Only the x86_64 Linux binary is released (see nix/package.nix).
      forPackageSystems =
        f: nixpkgs.lib.genAttrs [ "x86_64-linux" ] (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forPackageSystems (pkgs: {
        default = pkgs.callPackage ./nix/package.nix { };
      });

      overlays.default = final: _prev: {
        azoo-key-skkserv = final.callPackage ./nix/package.nix { };
      };

      homeManagerModules.default = import ./nix/home-module.nix self;

      # For `swift build` from source. With nixpkgs' Swift 6.2.4 this currently stops on the C++
      # interop headers (see nix/package.nix); the shell is kept for when that is fixed upstream.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell.override { stdenv = pkgs.swift.stdenv; } {
          packages = with pkgs; [
            swift
            swiftpm
            git
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
