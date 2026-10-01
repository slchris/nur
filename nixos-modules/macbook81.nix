# Apple MacBook8,1（2015 款 12 英寸 MacBook）的硬件支持。
#
# 为什么要动内核：applespi 在 mainline，nixpkgs 也开了 KEYBOARD_APPLESPI=m，但它依赖的
# SPI 控制器（SPI_PXA2XX / SPI_PXA2XX_PCI）和 LEDS_CLASS 在 nixpkgs 的 common-config 里
# 都没开，applespi 会被 kconfig 静默丢掉。内核 Kconfig 明确写着 MacBook8,1 需要
# spi_pxa2xx_platform + spi_pxa2xx_pci。所以这里用 boot.kernelPatches 重编内核——
# 安装 ISO 和装好的系统 import 同一个模块，内置键盘在两边都能用。
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.macbook81;

  # 键盘/触控板（applespi）与它依赖的 SPI 控制器。放进 initrd：LUKS 口令要在
  # stage-1 用内置键盘输入。
  spiModules = [
    "spi_pxa2xx_platform"
    "spi_pxa2xx_pci"
    "applespi"
  ];
in
{
  options.hardware.macbook81 = {
    enable = lib.mkEnableOption "Apple MacBook8,1（2015 款 12 英寸）硬件支持";

    ccode = lib.mkOption {
      type = lib.types.str;
      default = "CN";
      description = "写进 brcmfmac NVRAM 的国家码，决定 5GHz 可用信道。";
    };

    pciStub.enable = lib.mkEnableOption ''
      MacBook8,1 的 LPSS DMA 控制器（8086:9ce0）中断不工作时，用 pci-stub 占住它，
      让 spi-pxa2xx 退回 PIO。NixOS 的内核默认没有编 dw_dmac，通常用不到；只在 applespi
      反复报 -110 超时时打开
    '';

    spiResumeFix.enable = lib.mkEnableOption ''
      deep S3 唤醒后恢复 SPI 控制器寄存器并重新绑定。唤醒后内置键盘/触控板失效时打开，
      或改用 sleepToIdle（代价是待机耗电）
    '';

    sleepToIdle.enable = lib.mkEnableOption ''
      用 s2idle 代替 deep S3，绕开 SPI 控制器的唤醒问题，但待机时更耗电
    '';
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      hardware.enableRedistributableFirmware = true;

      # BCM4350 的板级 NVRAM：缺它时 brcmfmac 用 ccode=0，5GHz 基本不可用。
      hardware.firmware = [
        (pkgs.callPackage ../pkgs/macbook81/nvram.nix { inherit (cfg) ccode; })
      ];

      boot.kernelPatches = [
        {
          name = "macbook81-applespi";
          patch = null;
          structuredExtraConfig = with lib.kernel; {
            NEW_LEDS = yes;
            LEDS_CLASS = yes;
            KEYBOARD_APPLESPI = module;
            SPI_PXA2XX = module;
            SPI_PXA2XX_PCI = module;
          } // lib.optionalAttrs cfg.pciStub.enable {
            PCI_STUB = yes;
          };
        }
      ];

      boot.kernelParams =
        lib.optional cfg.pciStub.enable "pci-stub.ids=8086:9ce0"
        ++ lib.optional cfg.sleepToIdle.enable "mem_sleep_default=s2idle";

      boot.kernelModules = spiModules;
      boot.initrd.kernelModules = spiModules;
    })

    (lib.mkIf (cfg.enable && cfg.spiResumeFix.enable) {
      powerManagement.resumeCommands = lib.getExe (
        pkgs.callPackage ../pkgs/macbook81/spi-resume.nix { }
      );
    })
  ];
}
