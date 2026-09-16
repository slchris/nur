{
  lib,
  stdenv,
  fetchurl,
  addDriverRunpath,
  autoPatchelfHook,
  dpkg,
  makeWrapper,
  wrapGAppsHook3,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gtk3,
  libayatana-appindicator,
  libcap_ng,
  libdrm,
  libgbm,
  libGL,
  libnotify,
  libpulseaudio,
  libseccomp,
  libsecret,
  libuuid,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  libxshmfence,
  libxtst,
  nspr,
  nss,
  pango,
  systemd,
  xdg-utils,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "claude-desktop";
  version = "2.110.0";

  # Anthropic 官方 apt 仓库里的 deb，版本和哈希取自
  # https://downloads.claude.ai/claude-desktop/apt/stable/dists/stable/main/binary-amd64/Packages
  src = fetchurl {
    url = "https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_${finalAttrs.version}_amd64.deb";
    hash = "sha256-9Ey4tS9ukXGsLmfLzIBwxJdKLwqbnxQbQwsytP9UEQk=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    dpkg
    makeWrapper
    wrapGAppsHook3
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libdrm
    libgbm
    libnotify
    # Cowork 自带的 virtiofsd 需要。
    libcap_ng
    libseccomp
    libsecret
    libuuid
    libxkbcommon
    nspr
    nss
    pango
    stdenv.cc.cc.lib
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxshmfence
    libxtst
  ];

  # Electron 运行时用 dlopen 加载的库。
  runtimeDependencies = [
    (lib.getLib systemd)
    libGL
    libayatana-appindicator
    libnotify
    libpulseaudio
    libsecret
  ];

  dontWrapGApps = true;

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb --fsys-tarfile $src | tar -x --no-same-permissions --no-same-owner
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/bin
    cp -r usr/lib/claude-desktop $out/lib/
    cp -r usr/share $out/
    rm -r $out/share/lintian

    makeWrapper $out/lib/claude-desktop/claude-desktop $out/bin/claude-desktop \
      "''${gappsWrapperArgs[@]}" \
      --prefix LD_LIBRARY_PATH : ${addDriverRunpath.driverLink}/lib \
      --prefix PATH : ${lib.makeBinPath [ xdg-utils ]}

    runHook postInstall
  '';

  meta = {
    description = "Anthropic 官方的 Claude 桌面程序（Linux 测试版）";
    homepage = "https://claude.com/download";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "claude-desktop";
  };
})
