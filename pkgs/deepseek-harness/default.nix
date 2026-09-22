# DeepSeek Harness（dsh）CLI。上游暂无 flake，也还没进 nixpkgs，这里从官方的
# npm 包（@deepseek-ai/dsh）封装，走 buildNpmPackage。
#
# 依赖里的原生模块（node-pty、sharp、node-addon-require-builtin）都随 npm 包带了
# prebuild（node-pty 的 lib/utils.js 会依次找 build/Release、build/Debug、
# prebuilds/<platform>-<arch>），所以 npm 安装用 --ignore-scripts，不需要 node-gyp
# 和网络。dsh 的入口用 import.meta.main（Node >= 24.2 才有），因此固定 nodejs_24。
#
# 另外打了 kixparadigm 的官方补丁（kix-compaction-cap-patch.mjs）：给
# dsh-compaction-basic 加上 maxThresholdTokens / maxRetainTokens 两个绝对上限字段。
# kix 的 agent-preset 用了这两个字段，不打补丁上游 schema 会以
# BasicCompactionConfig: unknown key 拒绝挂载 preset。补丁是幂等的，锚点不匹配会
# 报错（DSH 升级后构建失败即提醒我们跟进）。补丁 rev 与 nur 的 pkgs/kixparadigm 一致。
#
# npm-wrapper/package-lock.json 由 node 24 的 npm 生成：
#   cd npm-wrapper && rm -rf node_modules package-lock.json \
#     && npm install --package-lock-only --ignore-scripts --omit=dev
{
  lib,
  buildNpmPackage,
  fetchurl,
  makeWrapper,
  nodejs_24,
}:

let
  wrapperSrc = ./npm-wrapper;
  lock = builtins.fromJSON (builtins.readFile "${wrapperSrc}/package-lock.json");
  version = lock.packages."node_modules/@deepseek-ai/dsh".version;

  kixCapPatch = fetchurl {
    url = "https://raw.githubusercontent.com/olicesx/kixparadigm/c3c31eb3268622358761cb2035ec84810a12ca11/scripts/context-budget/kix-compaction-cap-patch.mjs";
    hash = "sha256-yVJge4vDWpAz/0cByoGp3wFaQADc/gaGb8u3yMqj0Bk=";
  };

  compactionPkg = "$out/lib/node_modules/dsh-npm-wrapper/node_modules/@deepseek-ai/dsh-compaction-basic";
in
(buildNpmPackage.override { nodejs = nodejs_24; }) {
  pname = "deepseek-harness";
  inherit version;

  src = wrapperSrc;
  npmDepsHash = "sha256-mFAgdmYyDmHzmEEYx2rYE0bZ+vNWx011y8wB/9H4C8s=";

  dontNpmBuild = true;
  npmInstallFlags = [
    "--omit=dev"
    "--ignore-scripts"
  ];

  nativeBuildInputs = [ makeWrapper ];

  # wrapper 的 package.json 没有 bin 字段，nixpkgs 的 npmInstallHook 不会生成
  # $out/bin；这里显式包一个指向 nodejs_24 的启动器。web profile 的 HMR 插件
  # 要求 Node 带 --expose-internals（见 cordis-plugin-hmr）。
  postInstall = ''
    mkdir -p $out/bin
    makeWrapper ${lib.getExe nodejs_24} $out/bin/dsh \
      --add-flags "--expose-internals" \
      --add-flags "$out/lib/node_modules/dsh-npm-wrapper/node_modules/@deepseek-ai/dsh/lib/bin.js"

    DSH_COMPACTION_PKG=${compactionPkg} ${nodejs_24}/bin/node ${kixCapPatch}
    DSH_COMPACTION_PKG=${compactionPkg} ${nodejs_24}/bin/node ${kixCapPatch} --check
  '';

  meta = {
    description = "DeepSeek Harness (dsh) —— DeepSeek 官方的 agent harness CLI";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    changelog = "https://github.com/deepseek-ai/deepseek-harness/releases";
    license = lib.licenses.mit;
    # npmDepsHash 是按 aarch64-darwin 算的（npm 的可选平台依赖随系统不同），
    # 要上 Linux 需要在 Linux 上重新取 hash 并按平台分列。
    platforms = lib.platforms.darwin;
    mainProgram = "dsh";
  };
}
