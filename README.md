# nur

个人的 [NUR](https://github.com/nix-community/NUR) 仓库，收录 nixpkgs 里没有的包和配套的 NixOS 模块。目录结构沿用 [nur-packages-template](https://github.com/nix-community/nur-packages-template)。

## 内容

| 名称 | 类型 | 说明 |
| --- | --- | --- |
| `snell-server` | 包 | Surge 的 snell 代理服务端，默认 5.0.1，另收录 4.1.1 |
| `snell` | NixOS 模块 | 以 `DynamicUser` 运行 snell-server，PSK 从文件读取，不进入 Nix store |

`snell-server` 是 unfree 的官方二进制，只支持 `x86_64-linux`。官方文件用 UPX 加壳，里面的程序动态链接 `/lib64/ld-linux-x86-64.so.2`，所以打包时先脱壳，再由 `autoPatchelfHook` 改写解释器和库路径。未经处理的官方文件在 NixOS 上会以 127 退出且没有任何输出。

## 在 flake 中使用

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nur-slchris = {
      url = "github:slchris/nur";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, nur-slchris, ... }:
    {
      nixosConfigurations.example = nixpkgs.lib.nixosSystem {
        modules = [
          nur-slchris.nixosModules.snell
          (
            { lib, ... }:
            {
              nixpkgs.hostPlatform = "x86_64-linux";
              nixpkgs.overlays = [ nur-slchris.overlays.default ];
              nixpkgs.config.allowUnfreePredicate = pkg: lib.getName pkg == "snell-server";

              services.snell = {
                enable = true;
                port = 6160;
                pskFile = "/run/secrets/snell-psk";
              };
            }
          )
        ];
      };
    };
}
```

`pskFile` 指向只包含 PSK 的文件，通常由 sops-nix 或 agenix 生成。模块默认放行该端口的 TCP 与 UDP，不需要时设 `openFirewall = false`。

使用 4.1.1：

```nix
services.snell.package = pkgs.snell-server.override { version = "4.1.1"; };
```

## 构建

```sh
nix build .#snell-server
```

通过本仓库的 flake 构建时已允许 `snell-server` 这个 unfree 包；经 overlay 使用时，要由使用方自己允许。新增版本时，用 `nix store prefetch-file` 取得官方 zip 的哈希，填进 `pkgs/snell-server/default.nix`。

## CI

`.github/workflows/build.yml` 包含两组任务：

- `flake check`：执行 `nix flake check`，构建 `snell-server`，并运行 `checks.x86_64-linux.snell-module`。这个 NixOS 虚拟机测试会真正启动 snell 服务，确认端口已经监听。
- `NUR eval`：按 NUR 收录时的方式，分别在 `nixos-26.05`、`nixos-unstable`、`nixpkgs-unstable` 上求值。

本地执行虚拟机测试需要 x86_64-linux 与 KVM：

```sh
nix build .#checks.x86_64-linux.snell-module -L
```

仓库尚未登记到 NUR。登记后，在 workflow 末尾加一步 `curl -XPOST "https://nur-update.nix-community.org/update?repo=<登记名>"`，通知 NUR 拉取更新。
