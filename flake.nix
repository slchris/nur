{
  description = "slchris 的 NUR 仓库";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;

      # 本仓库里的 unfree 包。通过本 flake 直接构建时默认允许，经 overlay 使用时由使用方自行允许。
      unfreeNames = [ "snell-server" ];

      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) unfreeNames;
        };
    in
    {
      legacyPackages = forAllSystems (system: import ./default.nix { pkgs = pkgsFor system; });

      packages = forAllSystems (
        system:
        lib.filterAttrs (
          _: v: lib.isDerivation v && lib.meta.availableOn (pkgsFor system).stdenv.hostPlatform v
        ) self.legacyPackages.${system}
      );

      overlays.default = import ./overlay.nix;

      nixosModules = import ./nixos-modules;
    };
}
