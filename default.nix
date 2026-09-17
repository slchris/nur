# NUR 的入口：返回本仓库的包，以及保留名 lib、overlays、nixosModules。
# 不在这里导入 <nixpkgs>，由调用方传入 pkgs。
{
  pkgs ? import <nixpkgs> { },
}:

{
  lib = import ./lib { inherit pkgs; };
  nixosModules = import ./nixos-modules;
  overlays = import ./overlays;

  claude-desktop = pkgs.callPackage ./pkgs/claude-desktop { };
  dae = pkgs.callPackage ./pkgs/dae { };
  kixdns = pkgs.callPackage ./pkgs/kixdns { };
  openclaw = pkgs.callPackage ./pkgs/openclaw { };
  pi = pkgs.callPackage ./pkgs/pi { };
  snell-server = pkgs.callPackage ./pkgs/snell-server { };
  zcode = pkgs.callPackage ./pkgs/zcode { };
}
