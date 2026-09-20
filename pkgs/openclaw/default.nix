# openclaw 更新很快：nixpkgs 26.05 停在 2026.5.7（recipe 用 pnpm_10 / node 22），
# 上游 2026.9.x 已经换到 pnpm 12 + node >=24，直接复用 nixpkgs 的 recipe 已经吃不下
# （pnpmDeps 的 lockfile/patchedDependencies 对不上、新扩展的 optional 原生依赖也补不齐）。
#
# 所以这里复刻 nix-openclaw 的 npm 打包路径：它把 openclaw 的 **npm 包**用 node 24 的
# buildNpmPackage 装出来，再跑它自己的脚本把 runtime/扩展/bundled acpx 摆好。
# 只把版本与 wrapper lock 换成 2026.9.5，其余构建脚本与 bundled acpx 都复用 nix-openclaw。
#
# wrapper lock 由 node 24 的 npm 从零生成：
#   cd npm-wrapper && rm -rf node_modules package-lock.json \
#     && npm install --package-lock-only --ignore-scripts --omit=dev --legacy-peer-deps
# 生成后必须能通过 nix-openclaw 的 check-openclaw-npm-wrapper-lock.sh（离线可复现）。
{
  lib,
  nix-openclaw,
  system,
}:

let
  noPkgs = nix-openclaw.inputs.nixpkgs.legacyPackages.${system};
  noPath = nix-openclaw.outPath;

  # bundled acpx：用 nix-openclaw 生成的 lock + 它的打包脚本，hash 才与它的 nixpkgs 对得上。
  runtimePluginLocks = import (noPath + "/nix/generated/openclaw-runtime-plugins");
  bundledAcpx = noPkgs.callPackage (noPath + "/nix/lib/openclaw-runtime-plugin.nix") {
    linkOpenClawPeer = false;
  } runtimePluginLocks.acpx;

  wrapperSrc = ./npm-wrapper;
  lock = builtins.fromJSON (builtins.readFile "${wrapperSrc}/package-lock.json");
  version = lock.packages."node_modules/openclaw".version;

  buildNpmPackageForOpenClaw = noPkgs.buildNpmPackage.override {
    nodejs = noPkgs.nodejs_24;
  };
in
buildNpmPackageForOpenClaw {
  pname = "openclaw-gateway";
  inherit version;

  src = wrapperSrc;
  npmDepsHash = "sha256-CJ7ZPapmz3+4vMaWyIi9jCrw2RUWnkdHOAzo9pXPp28=";

  dontNpmBuild = true;
  makeCacheWritable = true;

  npmInstallFlags = [
    "--omit=dev"
    "--ignore-scripts"
    "--legacy-peer-deps"
  ];

  nativeBuildInputs = [ noPkgs.makeWrapper ];

  env = {
    NODE_BIN = "${noPkgs.nodejs_24}/bin/node";
    OPENCLAW_NPM_WRAPPER_DIR = baseNameOf (toString wrapperSrc);
    OPENCLAW_RUNTIME_LAYOUT_SH = "${noPath}/nix/scripts/openclaw-stage-runtime.sh";
    OPENCLAW_BUNDLED_ACPX = "${bundledAcpx}";
    OPENCLAW_NPM_PACKAGE_ROOT = "node_modules/openclaw";
    # 2026.9.5 的 dist 结构变了，nix-openclaw 那份补丁的 contract 对不上；用我们适配过的。
    OPENCLAW_PATCH_NPM_DIST_SCRIPT = "${./patch-openclaw-npm-dist.mjs}";
    STDENV_SETUP = "${noPkgs.stdenv}/setup";
  };

  postUnpack = "${noPath}/nix/scripts/check-openclaw-npm-wrapper-lock.sh";
  installPhase = "${noPath}/nix/scripts/openclaw-gateway-npm-install.sh";

  dontFixup = true;
  dontStrip = true;
  dontPatchShebangs = true;

  meta = {
    description = "Telegram-first AI gateway (OpenClaw)";
    homepage = "https://github.com/openclaw/openclaw";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin ++ lib.platforms.linux;
    mainProgram = "openclaw";
  };
}
