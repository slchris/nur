# nur

个人的 [NUR](https://github.com/nix-community/NUR) 仓库，收录 nixpkgs 里没有的包和配套的 NixOS 模块。目录结构沿用 [nur-packages-template](https://github.com/nix-community/nur-packages-template)。

## 内容

| 名称 | 类型 | 说明 |
| --- | --- | --- |
| `snell-server` | 包 | Surge 的 snell 代理服务端，默认 5.0.1，另收录 4.1.1 |
| `snell` | NixOS 模块 | 以 `DynamicUser` 运行 snell-server，PSK 从文件读取，不进入 Nix store |
| `derper` | NixOS 模块 | Tailscale/headscale 的 DERP 中继，使用 nixpkgs 的 `tailscale.derper`，支持 IP 模式自签证书与 headscale 准入 |

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

## derper

域名模式，证书由 `security.acme` 签发（DNS-01 不占用 80 和 443），并对接 headscale 准入：

```nix
{ config, ... }:
let
  domain = "derp.example.com";
  certDir = config.security.acme.certs.${domain}.directory;
in
{
  imports = [ nur-slchris.nixosModules.derper ];

  security.acme.certs.${domain}.reloadServices = [ "derper.service" ];

  services.derper = {
    enable = true;
    hostname = domain;
    address = ":12345";
    httpPort = -1;
    tlsCertFile = "${certDir}/fullchain.pem";
    tlsKeyFile = "${certDir}/key.pem";
    verifyClientUrl = "https://headscale.example.com/verify";
    acceptConnectionLimit = 20;
    acceptConnectionBurst = 100;
  };
}
```

设置 `tlsCertFile` 与 `tlsKeyFile` 后，derper 以 `manual` 模式运行，证书经 systemd `LoadCredential` 交给它，不需要额外的文件权限。证书续期后要重启 derper，上例用 `reloadServices` 完成。

不设置外部证书、`certMode = "manual"` 且 `hostname` 填 IP 时，derper 会自签带 IP SAN 的证书，客户端在 DERP map 里用 `certname` 钉扎指纹。此时证书保存在 `/var/lib/private/derper`，根目录是 tmpfs 的主机必须持久化这个目录，否则重启后指纹改变，所有客户端都会校验失败。

`verifyClientUrlFailOpen` 默认为 `false`，与上游相反：准入地址不可达时拒绝客户端，而不是变成公开中继。

## 构建

```sh
nix build .#snell-server
```

通过本仓库的 flake 构建时已允许 `snell-server` 这个 unfree 包；经 overlay 使用时，要由使用方自己允许。新增版本时，用 `nix store prefetch-file` 取得官方 zip 的哈希，填进 `pkgs/snell-server/default.nix`。

## CI

`.github/workflows/build.yml` 包含两组任务：

- `flake check`：执行 `nix flake check`，构建 `snell-server`，并运行 `snell-module`、`derper-module`（IP 模式自签证书）、`derper-external-cert`（域名证书）三个 NixOS 虚拟机测试，在虚拟机里真正启动服务并检查监听端口。
- `NUR eval`：按 NUR 收录时的方式，分别在 `nixos-26.05`、`nixos-unstable`、`nixpkgs-unstable` 上求值。

本地执行虚拟机测试需要 x86_64-linux 与 KVM：

```sh
nix build .#checks.x86_64-linux.snell-module -L
```

仓库尚未登记到 NUR。登记后，在 workflow 末尾加一步 `curl -XPOST "https://nur-update.nix-community.org/update?repo=<登记名>"`，通知 NUR 拉取更新。
