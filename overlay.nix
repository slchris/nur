# 把本仓库的包直接加进 pkgs，不经过 NUR 的命名空间。取自 nur-packages-template。
final: prev:
let
  isReserved =
    n:
    n == "lib"
    || n == "overlays"
    || n == "nixosModules"
    || n == "homeModules"
    || n == "darwinModules"
    || n == "flakeModules";
  nurAttrs = import ./default.nix { pkgs = prev; };
in
builtins.listToAttrs (
  map (n: {
    name = n;
    value = nurAttrs.${n};
  }) (builtins.filter (n: !isReserved n) (builtins.attrNames nurAttrs))
)
