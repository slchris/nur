# nur

个人的 [NUR](https://github.com/nix-community/NUR) 仓库，放 nixpkgs 里没有的包和 NixOS 模块。

- `claude-desktop`：Anthropic 官方 Claude 桌面程序，由官方 deb 重新打包。Cowork 按 Debian 路径查找 QEMU 固件，在 NixOS 上用不了。
- `zcode`：Z.ai 的桌面编程智能体 ZCode，官方 AppImage 封装。
- `snell-server`：Surge 的 snell 服务端，默认 5.0.1，也有 4.1.1。unfree，只支持 x86_64-linux。
- `nixosModules.snell`：运行 snell-server。
- `nixosModules.derper`：Tailscale/headscale 的 DERP 中继。

## 使用

```nix
inputs.nur-slchris = {
  url = "github:slchris/nur";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### snell

```nix
{ lib, ... }:
{
  imports = [ nur-slchris.nixosModules.snell ];
  nixpkgs.overlays = [ nur-slchris.overlays.default ];
  nixpkgs.config.allowUnfreePredicate = pkg: lib.getName pkg == "snell-server";

  services.snell = {
    enable = true;
    port = 6160;
    pskFile = "/run/secrets/snell-psk";
  };
}
```

`pskFile` 里只放 PSK，一般由 sops-nix 或 agenix 生成。模块默认放行端口，不需要时设置 `openFirewall = false`。

使用 4.1.1：

```nix
services.snell.package = pkgs.snell-server.override { version = "4.1.1"; };
```

官方二进制加了 UPX 壳，在 NixOS 上直接运行会返回 127 且没有输出，所以打包时先脱壳，再用 `autoPatchelfHook` 处理。

### derper

使用 ACME 证书，并接入 headscale 的客户端验证：

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
  };
}
```

没有域名时，`hostname` 填 IP，`certMode` 设为 `"manual"`，derper 会生成自签证书，客户端在 DERP map 里用 `certname` 固定证书指纹。证书保存在 `/var/lib/private/derper`。根目录是 tmpfs 的主机要持久化这个目录，否则重启后指纹会变。

`verifyClientUrlFailOpen` 默认是 `false`，和上游相反：验证地址不可达时拒绝客户端。

## 构建与测试

```sh
nix build .#snell-server
nix build .#checks.x86_64-linux.snell-module -L
```

虚拟机测试需要 x86_64-linux 和 KVM。CI 会执行 `nix flake check`，其中包括 snell 和 derper 的虚拟机测试，并在 nixos-26.05、nixos-unstable、nixpkgs-unstable 上按 NUR 的方式求值。

仓库还没有登记到 NUR。
