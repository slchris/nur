# kixparadigm 的 DSH agent-preset（认知层 + kixpower 编排）。
# npm 安装器（npm i -g kixparadigm）做的事，就是把仓库里的 dsh/preset 与
# dsh/preset-classic 拷进 ~/.dsh/.agent-presets/；这里从 GitHub 源码装成同样的两份：
#   $out/presets/kixparadigm          默认激励面
#   $out/presets/kixparadigm-classic  经典版（全文编曲说明书 + agents/instructions）
# dsh/preset 里的 skills、agents 是指向 preset-classic 的符号链接，上游安装器会在
# 安装时物化成真目录，所以这里用 cp -rL 跟随符号链接，否则铺到 ~/.dsh 后相对链接会断。
#
# 升级：改 version/rev 后重新取 hash：
#   nix store prefetch-file --unpack --json \
#     https://github.com/olicesx/kixparadigm/archive/<rev>.tar.gz
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:

stdenvNoCC.mkDerivation {
  pname = "kixparadigm";
  version = "1.3.16";

  src = fetchFromGitHub {
    owner = "olicesx";
    repo = "kixparadigm";
    rev = "c3c31eb3268622358761cb2035ec84810a12ca11";
    hash = "sha256-QK0dQOKQalene13Gd9RsuZhqvZbPb9mzfvJgSYW3AZY=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/presets
    cp -rL dsh/preset $out/presets/kixparadigm
    cp -rL dsh/preset-classic $out/presets/kixparadigm-classic
    runHook postInstall
  '';

  meta = {
    description = "kixparadigm 的 DeepSeek Harness agent-preset";
    homepage = "https://github.com/olicesx/kixparadigm";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
