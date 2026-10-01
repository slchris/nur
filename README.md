# nur

个人的 [NUR](https://github.com/nix-community/NUR) 仓库，放 nixpkgs 里没有的包和 NixOS 模块。

- `claude-desktop`：Anthropic 官方 Claude 桌面程序，由官方 deb 重新打包。Cowork 按 Debian 路径查找 QEMU 固件，在 NixOS 上用不了。
- `snell-server`：Surge 的 snell 服务端，默认 5.0.1，也有 4.1.1。unfree，只支持 x86_64-linux。
- `stalwart_0_16` / `stalwart-cli_1`：Stalwart 0.16.23 与配套 CLI 1.0.12 的官方 x86_64 Linux musl 静态发布包，固定 SHA-256；邮箱 NixOS 配置直接使用这些包，避免 nixpkgs 0.15 服务模块的旧配置格式。
- `sops_3_13`：SOPS 3.13.3 官方 x86_64 Linux 静态发布包，固定 SHA-256；邮件 VM 用它在运行时解密密文。
- `macbook81-firmware` / `macbook81-spi-resume`：Apple MacBook8,1（2015 款 12 英寸）的自有 Wi-Fi 固件目录（BCM4350 bin + 完整 NVRAM，取自 WiltonH/macbook12-wifi-driver）与 S3 唤醒后恢复 SPI 控制器的脚本。
- `nixosModules.snell`：运行 snell-server。
- `nixosModules.derper`：Tailscale/headscale 的 DERP 中继。
- `nixosModules.macbook81`：MacBook8,1 硬件支持。给内核打开 applespi 依赖的 SPI 控制器与 LEDS_CLASS（nixpkgs 默认没开，内置键盘/触控板靠它）；Wi-Fi 用 `alternative_fw_path` 指向自己的固件目录（完整 NVRAM 带校准，不覆盖 linux-firmware，内核升级不受影响）；另有唤醒修复、pci-stub 兜底与 s2idle 三个可选开关。

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

### macbook81

```nix
{
  imports = [ nur-slchris.nixosModules.macbook81 ];

  hardware.macbook81 = {
    enable = true;
    ccode = "US";                  # NVRAM 国家码，默认与 WiltonH 验证过的 US/rev53 一致
    # regrev = "53";
    # featureDisable = false;      # 默认给 brcmfmac 加 feature_disable=0x82000（Mac 机型已知修复）
    # deep S3 唤醒后内置键盘/触控板失效时，二选一打开：
    # spiResumeFix.enable = true;  # 唤醒时恢复 SPI 控制器寄存器并重绑（每次唤醒执行一次脚本）
    # sleepToIdle.enable = true;   # 改用 s2idle（简单，但待机耗电）
    # applespi 反复报 -110（SPI transfer timed out）时打开：
    # pciStub.enable = true;       # 用 pci-stub 占住 LPSS DMA 控制器，让 SPI 走 PIO
  };
}
```

`enable` 会重编内核：nixpkgs 的 `common-config` 只开了 `KEYBOARD_APPLESPI=m`，但它依赖的 `SPI_PXA2XX` / `SPI_PXA2XX_PCI` / `LEDS_CLASS` 没有开，选项会被 kconfig 静默丢掉。内核 Kconfig 明确写着 MacBook8,1 需要 `spi_pxa2xx_platform` + `spi_pxa2xx_pci`。

Wi-Fi 不放进 `hardware.firmware`（会和 linux-firmware 里的同名文件冲突），而是装进独立的 `macbook81-firmware` 目录，用 `boot.extraModprobeConfig` 的 `alternative_fw_path` 指过去：bin 与 linux-firmware 同版本，NVRAM 用带完整校准数据的版本（只覆盖 ccode/regrev 两行）。内核升级只需要重建系统，固件不受影响。

配置改了内核，内核不在二进制缓存里，使用方要在自己的 Linux 构建机上构建。`spiResumeFix` 依赖 `0000:00:15.4` 的物理地址与 `/dev/mem`，内核升级后要复验。

## 构建与测试

```sh
nix build .#snell-server
nix build .#checks.x86_64-linux.snell-module -L
```

虚拟机测试需要 x86_64-linux 和 KVM。CI 会执行 `nix flake check`，其中包括 snell 和 derper 的虚拟机测试，并在 nixos-26.05、nixos-unstable、nixpkgs-unstable 上按 NUR 的方式求值。

## 自动更新

`.github/workflows/update.yml` 每天执行 `scripts/update.py`，检查上游新版本：

- `claude-desktop`：Anthropic apt 仓库的软件包索引
- `snell-server`：Surge 知识库的 snell 发布说明，只收正式版

有新版本时改写包文件，`nix flake check` 通过后直接提交到 main。snell 的默认版本只在同一主版本内升级，新主版本只加入哈希表。本机也可以执行 `python3 scripts/update.py [包名…]`。

使用方的 flake 锁定了本仓库的版本，自动更新不会直接影响已部署的机器，要在使用方执行 `nix flake update nur-slchris` 才会用上新版本。

仓库还没有登记到 NUR。
