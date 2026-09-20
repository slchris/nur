{
  description = "slchris 的 NUR 仓库";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  # openclaw 的打包脚本与 bundled acpx 复用官方 nix-openclaw（它自带 nixpkgs，不 follows）。
  inputs.nix-openclaw.url = "github:openclaw/nix-openclaw";

  outputs =
    { self, nixpkgs, nix-openclaw }:
    let
      inherit (nixpkgs) lib;
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;

      # 本仓库里的 unfree 包。通过本 flake 直接构建时默认允许，经 overlay 使用时由使用方自行允许。
      unfreeNames = [
        "claude-desktop"
        "snell-server"
      ];

      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) unfreeNames;
        };
    in
    {
      legacyPackages = forAllSystems (system: import ./default.nix {
        pkgs = pkgsFor system;
        inherit nix-openclaw;
      });

      packages = forAllSystems (
        system:
        lib.filterAttrs (
          _: v: lib.isDerivation v && lib.meta.availableOn (pkgsFor system).stdenv.hostPlatform v
        ) self.legacyPackages.${system}
      );

      overlays.default = import ./overlay.nix;

      nixosModules = import ./nixos-modules;

      checks.x86_64-linux = {
        # 二进制重新打包的包：构建时 autoPatchelfHook 会检查所有依赖库都能找到。
        inherit (self.packages.x86_64-linux) claude-desktop snell-server;

        # 在虚拟机里真正启动服务：只构建包发现不了运行期问题，例如 UPX 壳导致的 127 退出。
        snell-module = (pkgsFor "x86_64-linux").testers.runNixOSTest {
          name = "snell";
          nodes.machine = {
            imports = [ self.nixosModules.snell ];
            environment.etc."snell-psk".text = "ci-test-only-psk";
            services.snell = {
              enable = true;
              port = 6160;
              pskFile = "/etc/snell-psk";
            };
          };
          testScript = ''
            machine.wait_for_unit("snell.service")
            machine.wait_for_open_port(6160)
          '';
        };

        # IP 模式：derper 需要自签带 IP SAN 的证书，并在非 443 端口上提供 HTTPS。
        derper-module = (pkgsFor "x86_64-linux").testers.runNixOSTest {
          name = "derper";
          nodes.machine =
            { pkgs, ... }:
            {
              imports = [ self.nixosModules.derper ];
              environment.systemPackages = [ pkgs.curl ];
              services.derper = {
                enable = true;
                hostname = "127.0.0.1";
                certMode = "manual";
                address = ":12345";
                httpPort = -1;
              };
            };
          testScript = ''
            machine.wait_for_unit("derper.service")
            machine.wait_for_open_port(12345)
            machine.succeed("curl -sk https://127.0.0.1:12345/ | grep '<h1>DERP</h1>'")
            machine.succeed("test -s /var/lib/private/derper/certs/127.0.0.1.crt")
            machine.succeed("ss -lun | grep -q ':3478 '")
          '';
        };

        # 域名模式：证书来自外部文件（实际部署时是 ACME），客户端按域名严格校验证书。
        derper-external-cert =
          let
            pkgs = pkgsFor "x86_64-linux";
            cert = pkgs.runCommand "derper-test-cert" { nativeBuildInputs = [ pkgs.openssl ]; } ''
              mkdir $out
              openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650 \
                -subj /CN=derp.test -addext subjectAltName=DNS:derp.test \
                -keyout $out/key.pem -out $out/cert.pem
            '';
          in
          pkgs.testers.runNixOSTest {
            name = "derper-external-cert";
            nodes.machine =
              { pkgs, ... }:
              {
                imports = [ self.nixosModules.derper ];
                environment.systemPackages = [ pkgs.curl ];
                services.derper = {
                  enable = true;
                  hostname = "derp.test";
                  address = ":12345";
                  httpPort = -1;
                  tlsCertFile = "${cert}/cert.pem";
                  tlsKeyFile = "${cert}/key.pem";
                };
              };
            testScript = ''
              machine.wait_for_unit("derper.service")
              machine.wait_for_open_port(12345)
              machine.succeed(
                "curl -sf --cacert ${cert}/cert.pem --resolve derp.test:12345:127.0.0.1 https://derp.test:12345/ | grep '<h1>DERP</h1>'"
              )
            '';
          };
      };
    };
}
