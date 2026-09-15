{
  lib,
  appimageTools,
  fetchurl,
}:

let
  pname = "zcode";
  version = "3.11.2";

  src = fetchurl {
    url = "https://cdn-zcode.z.ai/zcode/electron/releases/${version}/linux-x64/ZCode-${version}-linux-x64.AppImage";
    hash = "sha256-/EzIUShqQOqAkM6/qsGp+b3ETqs0njbu8NOzIZ85MD8=";
  };

  contents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  passthru = { inherit contents; };

  # 桌面入口沿用上游的 --no-sandbox：AppImage 里的 chrome-sandbox 不是 setuid 程序。
  extraInstallCommands = ''
    install -Dm444 ${contents}/*.desktop $out/share/applications/zcode.desktop
    substituteInPlace $out/share/applications/zcode.desktop \
      --replace-fail "Exec=AppRun" "Exec=zcode"
    cp -r ${contents}/usr/share/icons $out/share/
  '';

  meta = {
    description = "Z.ai 的桌面编程智能体 ZCode（官方 AppImage）";
    homepage = "https://zcode.z.ai";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "zcode";
  };
}
