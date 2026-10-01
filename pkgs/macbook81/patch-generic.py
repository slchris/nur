#!/usr/bin/env python3
# 给 sound/hda/codecs/generic.c 打 MacBook8,1（CS4208）补丁：
# 跳过会打断 EFI 锁定的 PLL 时钟的输入通路/数字通路初始化，
# 否则 codec 时钟锁死（coef 0x1f 变成 0x400），内放无声。
# 逻辑照搬 omnidecker/macbook8.1-speaker-driver 的 install.generic.driver.sh。
import sys

src, dst = sys.argv[1], sys.argv[2]
s = open(src).read()

fn = "int snd_hda_gen_init(struct hda_codec *codec)\n{"
fn_new = (
    "/* MacBook8,1 Cirrus CS4208 codec vendor id (see HDA_CODEC_ENTRY in patch_cirrus.c). */\n"
    "#define MB81_CS4208_VENDOR_ID 0x10134208\n"
    "\n"
    "int snd_hda_gen_init(struct hda_codec *codec)\n"
    "{"
)
assert s.count(fn) == 1, "snd_hda_gen_init definition anchor count != 1"
s = s.replace(fn, fn_new, 1)

old = (
    "\tinit_multi_out(codec);\n"
    "\tinit_extra_out(codec);\n"
    "\tinit_multi_io(codec);\n"
    "\tinit_aamix_paths(codec);\n"
    "\tinit_analog_input(codec);\n"
    "\tinit_input_src(codec);\n"
    "\tinit_digital(codec);\n"
)
new = (
    "\tinit_multi_out(codec);\n"
    "\tinit_extra_out(codec);\n"
    "\tinit_multi_io(codec);\n"
    "\t/* MB81 FIX: on the CS4208 the ADC/loopback input paths share the PLL clock\n"
    "\t * domain with the TDM speaker DAC; bringing these (unused on this\n"
    "\t * speaker-out-only machine) up knocks the EFI-locked PLL out of lock and\n"
    "\t * latches coef 0x1f bit10 -> silent speakers. Skip them. */\n"
    "\tif (codec->core.vendor_id != MB81_CS4208_VENDOR_ID) {\n"
    "\t\tinit_aamix_paths(codec);\n"
    "\t\tinit_analog_input(codec);\n"
    "\t\tinit_input_src(codec);\n"
    "\t}\n"
    "\t/* MB81 FIX: init_digital sends SET_DIGI_CONVERT to the SHARED converter\n"
    "\t * 0x0a (auto-parser registered it as SPDIF). Rewriting 0x0a's digital-\n"
    "\t * converter config during bring-up glitches the TDM serializer with no\n"
    "\t * register trace -> speakers silent. efi_chime_play (which PLAYS) never\n"
    "\t * touches dig1, so leave 0x0a in EFI's chime state for the CS4208. */\n"
    "\tif (codec->core.vendor_id != MB81_CS4208_VENDOR_ID)\n"
    "\t\tinit_digital(codec);\n"
)
assert s.count(old) == 1, "snd_hda_gen_init body anchor count != 1"
s = s.replace(old, new, 1)

open(dst, "w").write(s)
print("patched generic.c written:", dst)
