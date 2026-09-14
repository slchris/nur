{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.snell;
  extraConfig = pkgs.writeText "snell-extra.conf" cfg.extraConfig;
in
{
  options.services.snell = {
    enable = lib.mkEnableOption "Surge snell-server";

    package = lib.mkOption {
      type = lib.types.package;
      # 使用方加载了本仓库的 overlay 时用 overlay 里的包，否则直接构建。snell-server 是 unfree，需要使用方允许。
      default = pkgs.snell-server or (pkgs.callPackage ../pkgs/snell-server { });
      defaultText = lib.literalExpression "pkgs.snell-server";
    };

    port = lib.mkOption {
      type = lib.types.port;
    };

    pskFile = lib.mkOption {
      type = lib.types.str;
      description = "只包含 PSK 的文件路径。PSK 在服务启动时读入，不进入 Nix store。";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "ipv6 = false";
      description = "追加到 `[snell-server]` 段的配置行。";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "在防火墙上放行该端口的 TCP 与 UDP。";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.snell = {
      description = "Surge snell-server";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      script = ''
        umask 077
        {
          echo '[snell-server]'
          echo 'listen = 0.0.0.0:${toString cfg.port}'
          printf 'psk = %s\n' "$(cat "$CREDENTIALS_DIRECTORY/psk")"
          cat ${extraConfig}
        } > "$RUNTIME_DIRECTORY/snell.conf"
        exec ${lib.getExe cfg.package} -c "$RUNTIME_DIRECTORY/snell.conf"
      '';

      serviceConfig = {
        DynamicUser = true;
        LoadCredential = "psk:${cfg.pskFile}";
        RuntimeDirectory = "snell";
        RuntimeDirectoryMode = "0700";
        Restart = "on-failure";
        RestartSec = 5;
        LimitNOFILE = 65535;

        CapabilityBoundingSet = "";
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
      };
    };

    # snell v5 在同一端口上还提供 QUIC 代理，所以 UDP 也要放行。
    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ];
      allowedUDPPorts = [ cfg.port ];
    };
  };
}
