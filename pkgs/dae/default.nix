# 主线 daeuniverse/dae（不是个人 fork）。从 main 构建，eBPF 部分需要 clang。
# 没有跟 release tag，按 commit 钉住；升级时改 rev/srcHash/vendorHash。
{
  lib,
  clang,
  fetchFromGitHub,
  buildGoModule,
}:

buildGoModule (finalAttrs: {
  pname = "dae";
  version = "unstable-20260916";

  src = fetchFromGitHub {
    owner = "daeuniverse";
    repo = "dae";
    rev = "1ec85feddc721088ecdda73015bd78f652926b39";
    hash = "sha256-USiKI6QkpnK3wqcFppOMMvOezRyVJCaA5YKmQ6+XYLQ=";
    fetchSubmodules = true;
  };

  vendorHash = "sha256-g/V/VcU/OsCVHGz3msCN1oaYXT+agmnEdojhmdwOry4=";
  proxyVendor = true;

  nativeBuildInputs = [ clang ];

  hardeningDisable = [ "zerocallusedregs" ];

  # Makefile 的默认目标先编 eBPF（clang）再 go build，和 nixpkgs 里的 dae 一样。
  buildPhase = ''
    runHook preBuild

    make \
      CFLAGS="-D__REMOVE_BPF_PRINTK -fno-stack-protector -Wno-unused-command-line-argument" \
      NOSTRIP=y \
      VERSION=${finalAttrs.version} \
      OUTPUT=$out/bin/dae

    runHook postBuild
  '';

  # 构建过程要联网取 go module，不做检查。
  doCheck = false;

  postInstall = ''
    install -Dm444 install/dae.service $out/lib/systemd/system/dae.service
    substituteInPlace $out/lib/systemd/system/dae.service \
      --replace-fail "/usr/bin/dae" "$out/bin/dae"
  '';

  meta = {
    description = "基于 eBPF 的高性能透明代理（daeuniverse/dae 主线）";
    homepage = "https://github.com/daeuniverse/dae";
    license = lib.licenses.agpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "dae";
  };
})
