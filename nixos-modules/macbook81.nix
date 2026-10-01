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
      default = "US";
      description = ''
        写进 brcmfmac NVRAM 的国家码。默认 US，与 WiltonH 项目在 Ubuntu 上验证过的
        NVRAM（ccode=US、regrev=53）一致；确认能连之后再按需改成 CN 复验。
      '';
    };

    regrev = lib.mkOption {
      type = lib.types.str;
      default = "53";
      description = "NVRAM 的 regulatory revision，与 ccode 配套。";
    };

    featureDisable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        给 brcmfmac 加 feature_disable=0x82000。Arch 上 Mac 机型 brcmfmac
        “association took too long”的已知修复；不需要时关掉。
      '';
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
    (lib.mkIf cfg.enable (
      let
        # 自己的固件目录（bin + 完整 NVRAM）。用 alternative_fw_path 指向它，不覆盖
        # linux-firmware，内核更新不受影响。
        firmware = pkgs.callPackage ../pkgs/macbook81/firmware.nix {
          inherit (cfg) ccode regrev;
        };
      in
      {
        hardware.enableRedistributableFirmware = true;

        boot.extraModprobeConfig = ''
          options brcmfmac alternative_fw_path=${firmware}${
            lib.optionalString cfg.featureDisable " feature_disable=0x82000"
          }
        '';

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
      }
    ))

    (lib.mkIf (cfg.enable && cfg.spiResumeFix.enable) {
      powerManagement.resumeCommands = lib.getExe (
        pkgs.callPackage ../pkgs/macbook81/spi-resume.nix { }
      );
    })
  ];
}
