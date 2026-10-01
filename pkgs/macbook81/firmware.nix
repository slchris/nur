# MacBook 12 英寸（BCM4350 / BCM4350C2，14e4:43a3）的自有固件与 NVRAM。
#
# 为什么不用 linux-firmware 的默认 NVRAM：只有 ccode/regrev 的最小覆盖实测会出现
# “能扫描、关联不上”；这里放 Apple BootCamp 驱动逆向出来的完整 NVRAM（含 PA 校准），
# 只覆盖 ccode/regrev 两行，其余原样保留。
#
# 文件放在 lib/firmware/brcm/ 下：
#   - 两个 .txt 在 linux-firmware 里不存在，不会冲突；
#   - 未压缩的 .bin 与 linux-firmware 的 .bin.zst 同名不同后缀，固件加载器先找 .bin，
#     因此会优先用我们这份，等于把固件版本也钉住。
# 数据来源：WiltonH/macbook12-wifi-driver（MIT）。
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
  mkdir -p $out/lib/firmware/brcm

  # 显式给目标文件名：cp 一个 store 文件到目录会保留带哈希的源文件名。
  install -m 0444 ${./firmware/brcmfmac4350c2-pcie.bin} $out/lib/firmware/brcm/brcmfmac4350c2-pcie.bin
  install -m 0444 ${./firmware/brcmfmac4350-pcie.bin} $out/lib/firmware/brcm/brcmfmac4350-pcie.bin

  sed -e "s/^ccode=.*/ccode=${ccode}/" -e "s/^regrev=.*/regrev=${regrev}/" \
    ${./firmware/brcmfmac4350c2-pcie.full.txt} > $out/lib/firmware/brcm/brcmfmac4350c2-pcie.txt
  cp $out/lib/firmware/brcm/brcmfmac4350c2-pcie.txt $out/lib/firmware/brcm/brcmfmac4350-pcie.txt
''
