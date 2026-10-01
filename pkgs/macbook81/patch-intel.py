#!/usr/bin/env python3
# 给 sound/hda/controllers/intel.c 打 MacBook8,1 补丁：
# PCH 控制器（8086:9ca0 / ssid 8086:7270）在 probe 时不做 link reset（CRST），
# 直接挂到 EFI 正在跑的链路上，保住 codec 的时钟锁定；否则 reset 会把
# CS4208 的时钟打成故障锁死（coef 0x1f -> 0x400），任何寄存器 replay 都救不回。
# 逻辑照搬 omnidecker/macbook8.1-speaker-driver 的 install.azx.driver.sh。
import sys

p = sys.argv[1]
s = open(p).read()

marker = "MacBook8,1: attaching to running EFI link"
if marker in s:
    print("already patched, skipping")
    sys.exit(0)

old = "\thda_intel_init_chip(chip, (probe_only[dev] & 2) == 0);"
if old not in s:
    sys.exit("ERROR: anchor line not found in intel.c — kernel layout changed")

new = (
    "\t/*\n"
    "\t * MacBook8,1 quirk: PCH HD-audio controller 8086:9ca0, ssid 8086:7270,\n"
    "\t * hosting the CS4208 + class-D speaker amp. EFI leaves the codec in a\n"
    "\t * clock-locked state (vendor coef 0x1f == 0); the link reset (CRST)\n"
    "\t * normally pulsed at probe wipes it and latches a codec clock fault\n"
    "\t * (coef 0x1f -> 0x400) that no register replay clears. Attach to the\n"
    "\t * still-running EFI link WITHOUT a full reset so the init survives.\n"
    "\t */\n"
    "\tif (pci->subsystem_vendor == 0x8086 &&\n"
    "\t    pci->subsystem_device == 0x7270 && pci->device == 0x9ca0) {\n"
    "\t\tdev_info(card->dev,\n"
    "\t\t\t \"MacBook8,1: attaching to running EFI link without reset\\n\");\n"
    "\t\thda_intel_init_chip(chip, false);\n"
    "\t\tif (!azx_bus(chip)->codec_mask)\n"
    "\t\t\tazx_bus(chip)->codec_mask = 1; /* CS4208 is codec 0 */\n"
    "\t} else {\n"
    "\t\thda_intel_init_chip(chip, (probe_only[dev] & 2) == 0);\n"
    "\t}"
)
s = s.replace(old, new, 1)
open(p, "w").write(s)
print("patched intel.c")
