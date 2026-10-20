# Vercel CLI。nixpkgs 里只有 vercel-pkg（那是 Vercel 的 pkg 打包器，不是 CLI），
# 所以这里从官方 npm 包 vercel 封装，走 buildNpmPackage。
#
# 包结构：npm 包只带 dist/（12MB，284 个文件），依赖不进包，必须装 node_modules。
# 入口 dist/vc.js 会按平台 trampoline 到 @vercel/vc-native-<platform> 包里那份
# 163MB 的原生二进制；macOS 默认就走原生（vc.js 里写死 darwin 无条件 opt-in），
# 用 --disable-binary 或 VERCEL_CLI_USE_NATIVE_BINARY=0 才回退到 JS。
# 原生包是 optionalDependencies，npm 默认会装，所以安装时不能加 --no-optional。
#
# npm-wrapper/package-lock.json 由 npm 生成：
#   cd npm-wrapper && rm -rf node_modules package-lock.json \
#     && npm install --package-lock-only --ignore-scripts --omit=dev
{
  lib,
  buildNpmPackage,
  makeWrapper,
  nodejs_24,
}:

let
  wrapperSrc = ./npm-wrapper;
  # 不能写 "${wrapperSrc}/package-lock.json"：路径插值成带 context 的字符串后，
  # restrict-eval（NUR 收录检查）下会先拷进 store 再读，报 "path is not valid"。
  lock = builtins.fromJSON (builtins.readFile ./npm-wrapper/package-lock.json);
  version = lock.packages."node_modules/vercel".version;

  vercelPkg = "$out/lib/node_modules/vercel-npm-wrapper/node_modules/vercel";
in
(buildNpmPackage.override { nodejs = nodejs_24; }) {
  pname = "vercel";
  inherit version;

  src = wrapperSrc;
  npmDepsHash = "sha256-hbWZOVGMFjRcJhkA9ULyq2/a6hX0wKijOuQh9DD69Bk=";

  dontNpmBuild = true;
  # --ignore-scripts：依赖里没有需要编译的原生模块，esbuild 也走 @esbuild/<platform>
  # 的可选包。--omit=dev 之外不要加 --no-optional，否则原生二进制不会被装上。
  npmInstallFlags = [
    "--omit=dev"
    "--ignore-scripts"
  ];

  nativeBuildInputs = [ makeWrapper ];

  # wrapper 的 package.json 没有 bin 字段，npmInstallHook 不会生成 $out/bin；
  # 这里显式包两个名字（上游 bin 同时提供 vc 与 vercel）。
  postInstall = ''
    mkdir -p $out/bin
    makeWrapper ${lib.getExe nodejs_24} $out/bin/vercel \
      --add-flags "${vercelPkg}/dist/vc.js"
    ln -s vercel $out/bin/vc
  '';

  meta = {
    description = "Vercel CLI";
    homepage = "https://github.com/vercel/vercel";
    changelog = "https://github.com/vercel/vercel/releases";
    license = lib.licenses.asl20;
    # npmDepsHash 按 aarch64-darwin 算的（可选平台依赖随系统不同），
    # 要上 Linux 得在 Linux 上重新取 hash 并按平台分列。
    platforms = lib.platforms.darwin;
    mainProgram = "vercel";
  };
}
