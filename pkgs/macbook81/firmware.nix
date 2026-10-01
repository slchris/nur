# MacBook 12 英寸（BCM4350 / BCM4350C2，14e4:43a3）的自有固件目录。
#
# 为什么不直接用 linux-firmware：关联失败的实测现象需要一份带完整校准数据的 NVRAM
# （最小覆盖只有 ccode/regrev；驱动把平台 txt 当完整 NVRAM 用时，缺 PA 校准会导致
# 能扫描但关联不上）。配套的 bin 与 linux-firmware 同版本（7.35.180.133），放在一起
# 是为了用 brcmfmac 的 alternative_fw_path 指向本目录，不覆盖 /lib/firmware 里的文件，
# 内核更新也不会动到它。
#
# 数据来源：WiltonH/macbook12-wifi-driver（MIT），完整 NVRAM 取自 Apple BootCamp 驱动。
{
  runCommand,
  lib,
  ccode ? "US",
  regrev ? "53",
}:
runCommand "macbook81-brcm-firmware" {
  meta = {
    description = "BCM4350 firmware + full NVRAM for MacBook 12-inch (MacBook8,1)";
    license = lib.licenses.mit;
  };
} ''
  mkdir -p $out

  # 驱动按芯片 rev 选 bin：MacBook8,1 实测加载的是 brcmfmac4350c2-pcie.bin。
  # 注意要显式给目标文件名：cp 一个 store 文件到目录会保留带哈希的源文件名。
  install -m 0444 ${./firmware/brcmfmac4350c2-pcie.bin} $out/brcmfmac4350c2-pcie.bin
  install -m 0444 ${./firmware/brcmfmac4350-pcie.bin} $out/brcmfmac4350-pcie.bin

  # 完整 NVRAM 覆盖：只改管制域两行，其余（boardtype、PA 校准等）保持原样。
  sed -e "s/^ccode=.*/ccode=${ccode}/" -e "s/^regrev=.*/regrev=${regrev}/" \
    ${./firmware/brcmfmac4350c2-pcie.full.txt} > $out/brcmfmac4350c2-pcie.txt
  cp $out/brcmfmac4350c2-pcie.txt $out/brcmfmac4350-pcie.txt
''
