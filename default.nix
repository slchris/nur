# NUR 的入口：返回本仓库的包，以及保留名 lib、overlays、nixosModules。
# 不在这里导入 <nixpkgs>，由调用方传入 pkgs。
{
  pkgs ? import <nixpkgs> { },
  # openclaw 的打包脚本与 bundled acpx 复用官方 nix-openclaw；没有它就不暴露 openclaw。
  nix-openclaw ? null,
  system ? pkgs.stdenv.hostPlatform.system,
}:

let
  inherit (pkgs) lib;
in
{
  lib = import ./lib { inherit pkgs; };
  nixosModules = import ./nixos-modules;
  overlays = import ./overlays;

  claude-desktop = pkgs.callPackage ./pkgs/claude-desktop { };
  dae = pkgs.callPackage ./pkgs/dae { };
  deepseek-harness = pkgs.callPackage ./pkgs/deepseek-harness { };
  kixdns = pkgs.callPackage ./pkgs/kixdns { };
  kixparadigm = pkgs.callPackage ./pkgs/kixparadigm { };
  pi = pkgs.callPackage ./pkgs/pi { };
  snell-server = pkgs.callPackage ./pkgs/snell-server { };
}
// lib.optionalAttrs (nix-openclaw != null) {
  openclaw = pkgs.callPackage ./pkgs/openclaw { inherit nix-openclaw system; };
}
