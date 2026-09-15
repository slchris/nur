{
  lib,
  stdenv,
  fetchurl,
  unzip,
  upx,
  autoPatchelfHook,
  version ? "5.0.1",
}:
let
  # 官方 zip 的哈希，由 scripts/update.py 维护。
  hashes = {
    "5.0.1" = "sha256-m+ocK541tzsxY0hWwE0Yw5MHK55dzeajJ4HYuPkIxTk=";
    "4.1.1" = "sha256-zCJxt5x1BoiLNOZR6HQbOqf8fV9gqmXvi7CW8zE6GTs=";
  };
in
stdenv.mkDerivation {
  pname = "snell-server";
  inherit version;

  src = fetchurl {
    url = "https://dl.nssurge.com/snell/snell-server-v${version}-linux-amd64.zip";
    hash = hashes.${version} or (throw "snell-server: 未收录版本 ${version} 的哈希");
  };

  nativeBuildInputs = [
    unzip
    upx
    autoPatchelfHook
  ];
  # 脱壳后的程序依赖 libstdc++ 与 libgcc_s，其余是 glibc。
  buildInputs = [ stdenv.cc.cc.lib ];

  sourceRoot = ".";
  dontConfigure = true;

  # 官方二进制用 UPX 加壳：壳本身是静态的，ldd 因此显示“不是动态可执行文件”，
  # 但里面的程序动态链接 /lib64/ld-linux-x86-64.so.2。NixOS 上没有这个文件，直接运行会以 127 退出且没有任何输出。
  # 先脱壳，再由 autoPatchelfHook 改写解释器和库路径。
  buildPhase = ''
    runHook preBuild
    upx -d snell-server
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 snell-server $out/bin/snell-server
    runHook postInstall
  '';

  dontStrip = true;

  meta = {
    description = "Surge snell proxy server";
    homepage = "https://kb.nssurge.com/surge-knowledge-base/release-notes/snell";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "snell-server";
  };
}
