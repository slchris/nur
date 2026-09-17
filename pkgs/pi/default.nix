# Pi Agent Harness 的 CLI（@earendil-works/pi-coding-agent）。
# 上游 release 直接提供各平台独立二进制，含运行时资源，这里只做重新打包，不从源码构建。
# 升级时改 version 与下面各平台的 hash（hash 取自 GitHub release API 的 digest 字段）。
{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "0.85.1";

  # 国内直连 GitHub 很慢（~13–27 KiB/s）。走镜像直连；海外可改成 https://github.com。
  # release 文件内容不变，hash 不受镜像影响。
  mirror = "https://gh-proxy.com";

  assets = {
    aarch64-darwin = {
      file = "pi-darwin-arm64.tar.gz";
      hash = "sha256-1fcOPAz3OY6sI5/QJh7gdNmLe6f2tD/jYX8FLtW3nQY=";
    };
    x86_64-darwin = {
      file = "pi-darwin-x64.tar.gz";
      hash = "sha256-rbkYuEViXxhNi+pAjVXqyvIaqHI4eTwPW087lze85is=";
    };
    aarch64-linux = {
      file = "pi-linux-arm64.tar.gz";
      hash = "sha256-BC0grohe5POxAoFfMoC5YsN3sun7RN5AN5CMxTDq5NQ=";
    };
    x86_64-linux = {
      file = "pi-linux-x64.tar.gz";
      hash = "sha256-SU5Jj0fXTSH0CzOG9qXpIaPUlTGhacq1W72soOof4lo=";
    };
  };

  system = stdenvNoCC.hostPlatform.system;
  asset =
    assets.${system} or (throw "pi: 没有 ${system} 的预编译产物，请到 release 页面确认");
in
stdenvNoCC.mkDerivation {
  pname = "pi";
  inherit version;

  src = fetchurl {
    url = "${mirror}/https://github.com/earendil-works/pi/releases/download/v${version}/${asset.file}";
    inherit (asset) hash;
  };

  # 压缩包结构：pi/pi
  sourceRoot = "pi";
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    install -m755 pi $out/bin/pi
    runHook postInstall
  '';

  meta = {
    description = "Pi Agent Harness 的交互式编程 agent CLI（上游预编译二进制）";
    homepage = "https://pi.dev";
    changelog = "https://github.com/earendil-works/pi/releases/tag/v${version}";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = builtins.attrNames assets;
    mainProgram = "pi";
  };
}
