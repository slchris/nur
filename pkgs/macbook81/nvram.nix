# BCM4350（MacBook 12 英寸全系，PCIe 14e4:43a3）的板级 NVRAM 覆盖文件。
# brcmfmac 找不到它时用 ccode=0，5GHz 在多数管制域不可用；校准数据仍来自芯片 OTP，
# 这里只覆盖管制参数。参数取自 WiltonH/macbook12-wifi-driver 的最小覆盖（MIT）。
{
  runCommand,
  lib,
  ccode ? "CN",
  regrev ? "53",
}:
runCommand "brcmfmac4350-nvram" {
  meta = {
    description = "brcmfmac NVRAM override for Broadcom BCM4350 on Apple MacBook 12-inch";
    license = lib.licenses.mit;
  };
} ''
  mkdir -p $out/lib/firmware/brcm
  cat > $out/lib/firmware/brcm/brcmfmac4350-pcie.txt <<EOF
  # Apple MacBook 12-inch (BCM4350) NVRAM override: regulatory parameters only.
  ccode=${ccode}
  regrev=${regrev}
  EOF
  # 2017 款（MacBook10,1）的芯片是 BCM4350C2，核请求的文件名不同，内容一致。
  cp $out/lib/firmware/brcm/brcmfmac4350-pcie.txt $out/lib/firmware/brcm/brcmfmac4350c2-pcie.txt
''
