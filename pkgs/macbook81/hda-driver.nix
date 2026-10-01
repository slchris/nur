# MacBook8,1（CS4208）内放（TDM 功放）驱动。
#
# 三个打过补丁的 HDA 模块，构建方式照搬 omnidecker/macbook8.1-speaker-driver
# （thomas-shirley 的 fork，pin 在修了 7.2 内核功放系数块的提交）：
#   - snd-hda-codec-generic：CS4208 跳过会打断 EFI 锁定 PLL 的输入/数字通路初始化；
#   - snd-hda-codec-cs420x：replay EFI 的 codec 初始化 + 新增 TDM 扬声器 PCM；
#   - snd-hda-intel：PCH 控制器不打 link reset，直接挂到 EFI 正在跑的链路上。
#
# cs420x 从 patched generic 导入 snd_hda_gen_* 符号，必须用 KBUILD_EXTRA_SYMBOLS
# 重链接，否则 modversion CRC 不一致：内核拒绝加载 cs420x，in-tree 的 generic 抢走
# codec（绑成 "Cirrus Logic Generic"），内放永远无声。
#
# 需要配合：
#   - /etc/modprobe.d：options snd_hda_intel single_cmd=1 power_save=0
#     + softdep snd_hda_intel pre: snd_hda_codec_cs420x（保证 cs420x 先于 intel 加载）；
#   - NVRAM 的开机铃声不能静音（固件只在放铃声时给功放上电）；
#   - PipeWire/WirePlumber 配置（本包 share/macbook81 下）与 jack-switch 服务。
{
  lib,
  stdenv,
  fetchgit,
  python3,
  makeWrapper,
  alsa-utils,
  pipewire,
  gawk,
  gnugrep,
  coreutils,
  systemd,
  kernel,
}:
let
  rev = "e4134fb272ba3be29aa71ad7aa6eae8b0ebddf1a";
  src = fetchgit {
    url = "https://github.com/omnidecker/macbook8.1-speaker-driver.git";
    inherit rev;
    hash = "sha256-lK0TK6a9+Vugt+ozQMQwY4e3btRAFbv97INhf6XSusE=";
  };
in
stdenv.mkDerivation {
  pname = "macbook81-hda";
  version = "0.1+e4134fb-${kernel.version}";

  inherit src;

  nativeBuildInputs = [ python3 makeWrapper ] ++ kernel.moduleBuildDependencies;

  # out-of-tree 模块构建用的内核 build 目录。
  kbuild = "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build";

  buildPhase = ''
    runHook preBuild

    mkdir -p build
    # 从内核 tarball 里取 sound/hda（6.17+ 布局）；顶层目录名直接探测，不硬编码。
    # 不用 tar | head 管道：stdenv 开着 pipefail，head 提前退出会让 tar 收到 SIGPIPE（141）。
    tar -tf ${kernel.src} > tarlist.txt
    topdir=$(head -n1 tarlist.txt | cut -d/ -f1)
    tar --strip-components=2 -xf ${kernel.src} --directory=build "$topdir/sound/hda"

    # ---- cs420x（cirrus codec）：整文件替换 ----
    cirrus=build/hda/codecs/cirrus
    cp patch_cirrus/cs420x.c \
       patch_cirrus/patch_cirrus_macbook81_setup.h \
       patch_cirrus/patch_cirrus_a1534_setup.h \
       patch_cirrus/patch_cirrus_a1534_pcm.h \
       "$cirrus/"
    cp patch_cirrus/Makefile_cs420x "$cirrus/Makefile"
    # 6.17+ 把 .free 回调改名为 .remove。
    sed -i 's/\.free/.remove/' "$cirrus/patch_cirrus_a1534_pcm.h"

    # ---- generic codec：跳时钟打断的初始化 ----
    mkdir -p build/hda/genmod
    cp build/hda/codecs/generic.h build/hda/genmod/
    python3 ${./patch-generic.py} build/hda/codecs/generic.c build/hda/genmod/generic.c
    cat > build/hda/genmod/Kbuild <<'EOF'
    ccflags-y += -I$(src)/../common
    obj-m := snd-hda-codec-generic.o
    snd-hda-codec-generic-y := generic.o
    EOF

    # ---- 先编 patched generic，再用它的 Module.symvers 编 cs420x ----
    make -C "$kbuild" M=$PWD/build/hda/genmod modules
    make -C "$kbuild" M=$PWD/build/hda/codecs/cirrus clean
    KBUILD_EXTRA_SYMBOLS=$PWD/build/hda/genmod/Module.symvers \
      make -C "$kbuild" M=$PWD/build/hda/codecs/cirrus modules

    # ---- snd-hda-intel：no-reset 挂载 ----
    python3 ${./patch-intel.py} build/hda/controllers/intel.c
    cp patch_cirrus/Makefile_azx build/hda/controllers/Makefile
    make -C "$kbuild" M=$PWD/build/hda/controllers modules

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    moddir=$out/lib/modules/${kernel.modDirVersion}/extra
    mkdir -p "$moddir"
    cp build/hda/genmod/snd-hda-codec-generic.ko "$moddir/"
    cp build/hda/codecs/cirrus/snd-hda-codec-cs420x.ko "$moddir/"
    cp build/hda/controllers/snd-hda-intel.ko "$moddir/"

    install -Dm755 ${src}/mb81-jack-switch.sh $out/libexec/mb81-jack-switch
    makeWrapper $out/libexec/mb81-jack-switch $out/bin/mb81-jack-switch \
      --prefix PATH : ${
        lib.makeBinPath [
          alsa-utils
          pipewire
          gawk
          gnugrep
          coreutils
          systemd
        ]
      }

    # 标准位置，由 NixOS 的 services.pipewire(.wireplumber).configPackages 收走。
    install -Dm644 ${src}/51-macbook81-speaker.conf \
      $out/share/pipewire/pipewire.conf.d/51-macbook81-speaker.conf
    install -Dm644 ${src}/51-mb81-rawpcm-speaker.conf \
      $out/share/wireplumber/wireplumber.conf.d/51-mb81-rawpcm-speaker.conf

    runHook postInstall
  '';

  meta = {
    description = "MacBook8,1 CS4208 internal-speaker (TDM amp) HDA driver modules";
    homepage = "https://github.com/omnidecker/macbook8.1-speaker-driver";
    # 内核模块派生自 GPL 的内核源码与 davidjo 的逆向工作。
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
  };
}
