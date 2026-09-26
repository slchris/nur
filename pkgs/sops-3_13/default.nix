{
  lib,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation {
  pname = "sops";
  version = "3.13.3";

  src = fetchurl {
    url = "https://github.com/getsops/sops/releases/download/v3.13.3/sops-v3.13.3.linux.amd64";
    hash = "sha256-5b7DNGqHOukdhxVQ8+aYwarZYq/0YqCA5A8l/eF/72s=";
  };

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/sops"
    runHook postInstall
  '';

  meta = {
    description = "SOPS encrypted-file editor, official static binary";
    homepage = "https://getsops.io/";
    license = lib.licenses.mpl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "sops";
  };
}
