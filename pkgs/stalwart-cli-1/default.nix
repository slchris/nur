{
  lib,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation {
  pname = "stalwart-cli";
  version = "1.0.12";

  src = fetchurl {
    url = "https://github.com/stalwartlabs/cli/releases/download/v1.0.12/stalwart-cli-x86_64-unknown-linux-musl.tar.xz";
    hash = "sha256-dvzXJQoQx77nBNxKCAALP6ymtaIoldQYMcDDfv2VrM4=";
  };

  sourceRoot = "stalwart-cli-x86_64-unknown-linux-musl";
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 stalwart-cli "$out/bin/stalwart-cli"
    runHook postInstall
  '';

  meta = {
    description = "Stalwart v0.16 management CLI";
    homepage = "https://github.com/stalwartlabs/cli";
    license = lib.licenses.agpl3Only;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "stalwart-cli";
  };
}
