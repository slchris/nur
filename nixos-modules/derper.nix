{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.derper;
  inherit (lib) mkOption types;

  stateDir = "/var/lib/derper";
  listenPort = lib.toInt (lib.last (lib.splitString ":" cfg.address));

  # 使用外部证书时，证书经 LoadCredential 放进凭据目录（%d），derper 按 <hostname>.crt/.key 读取。
  externalCert = cfg.tlsCertFile != null;

  args = [
    "-a=${cfg.address}"
    "-hostname=${cfg.hostname}"
    "-certmode=${if externalCert then "manual" else cfg.certMode}"
    "-certdir=${if externalCert then "%d" else "${stateDir}/certs"}"
    "-c=${stateDir}/derper.key"
    "-http-port=${toString cfg.httpPort}"
    "-stun=${lib.boolToString cfg.stun}"
    "-stun-port=${toString cfg.stunPort}"
    "-verify-clients=${lib.boolToString cfg.verifyClients}"
  ]
  ++ lib.optionals (cfg.verifyClientUrl != null) [
    "-verify-client-url=${cfg.verifyClientUrl}"
    "-verify-client-url-fail-open=${lib.boolToString cfg.verifyClientUrlFailOpen}"
  ]
  ++ lib.optional (
    cfg.acceptConnectionLimit != null
  ) "-accept-connection-limit=${toString cfg.acceptConnectionLimit}"
  ++ lib.optional (
    cfg.acceptConnectionBurst != null
  ) "-accept-connection-burst=${toString cfg.acceptConnectionBurst}"
  ++ cfg.extraArgs;
in
{
  options.services.derper = {
    enable = lib.mkEnableOption "Tailscale DERP 中继（derper）";

    package = mkOption {
      type = types.package;
      default = pkgs.tailscale.derper;
      defaultText = lib.literalExpression "pkgs.tailscale.derper";
    };

    hostname = mkOption {
      type = types.str;
      example = "203.0.113.10";
      description = ''
        TLS 证书对应的主机名。`certMode = "manual"` 时可以填 IP：derper 会自动生成带 IP SAN 的自签证书，
        客户端通过 DERP map 里的 `certname`（`sha256-raw:` 指纹）校验，不需要域名。
      '';
    };

    certMode = mkOption {
      type = types.enum [
        "letsencrypt"
        "manual"
      ];
      default = "letsencrypt";
      description = "`letsencrypt` 自动申请证书，需要 80 端口可达；`manual` 读取或自签 `certs/<hostname>.crt`。";
    };

    tlsCertFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/var/lib/acme/derp.example.com/fullchain.pem";
      description = ''
        外部证书（完整链）。设置后按 `manual` 模式运行，不再自签或申请证书，适合与 `security.acme` 配合：
        证书续期后要重启 derper，例如 `security.acme.certs.<name>.reloadServices = [ "derper.service" ]`。
      '';
    };

    tlsKeyFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/var/lib/acme/derp.example.com/key.pem";
    };

    address = mkOption {
      type = types.str;
      default = ":443";
      example = ":12345";
      description = "DERP 的 HTTPS 监听地址，形如 `:端口` 或 `IP:端口`。";
    };

    httpPort = mkOption {
      type = types.int;
      default = 80;
      description = "HTTP 端口，`-1` 表示关闭。Let's Encrypt 模式需要它。";
    };

    stun = mkOption {
      type = types.bool;
      default = true;
    };

    stunPort = mkOption {
      type = types.port;
      default = 3478;
    };

    verifyClients = mkOption {
      type = types.bool;
      default = false;
      description = "通过本机的 tailscaled 校验客户端。使用 headscale 时通常改用 `verifyClientUrl`。";
    };

    verifyClientUrl = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "https://headscale.example.com/verify";
      description = "准入控制地址，derper 把每个客户端的 node key 交给它判定，只有已注册节点可以中继。";
    };

    verifyClientUrlFailOpen = mkOption {
      type = types.bool;
      default = false;
      description = ''
        准入地址不可达时是否放行。上游默认放行，这里默认拒绝：协调服务器故障期间，
        放行等于把这台 DERP 变成公开中继；代价是故障期间所有客户端都无法中继。
      '';
    };

    acceptConnectionLimit = mkOption {
      type = types.nullOr types.int;
      default = null;
      example = 20;
      description = "每秒接受新连接的速率上限。";
    };

    acceptConnectionBurst = mkOption {
      type = types.nullOr types.int;
      default = null;
      example = 100;
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "放行 DERP 的 HTTPS 端口、启用时的 HTTP 端口，以及 STUN 的 UDP 端口。";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = (cfg.tlsCertFile == null) == (cfg.tlsKeyFile == null);
        message = "services.derper: tlsCertFile 与 tlsKeyFile 必须同时设置。";
      }
      {
        # derper 用去掉非法字符后的 hostname 作文件名，这里要求它本身合法，凭据名才能对上。
        assertion = !externalCert || builtins.match "[A-Za-z0-9.-]+" cfg.hostname != null;
        message = "services.derper: 使用外部证书时 hostname 只能包含字母、数字、点和连字符。";
      }
    ];

    systemd.services.derper = {
      description = "Tailscale DERP relay";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      serviceConfig = {
        ExecStart = lib.escapeShellArgs ([ (lib.getExe' cfg.package "derper") ] ++ args);
        Restart = "always";
        RestartSec = 5;

        # 节点私钥和证书保存在这里（DynamicUser 下实际路径是 /var/lib/private/derper）。
        # 使用 tmpfs 根的主机必须持久化该目录：IP 模式的证书指纹被客户端钉扎，重新生成后
        # 所有客户端都会校验失败，直到 DERP map 里的 certname 同步更新。
        DynamicUser = true;
        StateDirectory = "derper";
        StateDirectoryMode = "0700";
        WorkingDirectory = stateDir;
        LoadCredential = lib.optionals externalCert [
          "${cfg.hostname}.crt:${cfg.tlsCertFile}"
          "${cfg.hostname}.key:${cfg.tlsKeyFile}"
        ];

        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
        CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
        LimitNOFILE = 1048576;

        LockPersonality = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_NETLINK"
          "AF_UNIX"
        ];
        SystemCallArchitectures = "native";
      };
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ listenPort ] ++ lib.optional (cfg.httpPort > 0) cfg.httpPort;
      allowedUDPPorts = lib.optional cfg.stun cfg.stunPort;
    };
  };
}
