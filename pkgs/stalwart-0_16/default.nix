{
  lib,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation {
  pname = "stalwart";
  version = "0.16.23";

  src = fetchurl {
    url = "https://github.com/stalwartlabs/stalwart/releases/download/v0.16.23/stalwart-x86_64-unknown-linux-musl.tar.gz";
    hash = "sha256-xbeANes1ShwStC8WZOr1e1ilqN+zt62SbvMp+H14Y8I=";
  };

  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 stalwart "$out/bin/stalwart"
    runHook postInstall
  '';

  meta = {
    description = "Stalwart mail and collaboration server, v0.16 API";
    homepage = "https://stalw.art/";
    license = lib.licenses.agpl3Only;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "stalwart";
  };
}
