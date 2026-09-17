# olicesx/kixdns：Rust 写的非递归 DNS 转发器，配置是 JSON pipeline。
# 有 release，但这里从源码构建（Cargo.lock 在仓库里，cargoHash 稳定）。
{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

let
  version = "0.2.0";
in
rustPlatform.buildRustPackage {
  pname = "kixdns";
  inherit version;

  src = fetchFromGitHub {
    owner = "olicesx";
    repo = "kixdns";
    tag = "v${version}";
    hash = "sha256-wvgOrAWnA6RDKI8b5VHCUO/Ml6dlwoYes4GrSn6Db1Q=";
  };

  cargoHash = "sha256-4SUIjEgRk3WrkHpY10dTUNcUh76TVcrTC9IcBiut24s=";

  # 仓库自带的 config/pipeline.json 是示例；实际配置由部署方生成。
  meta = {
    description = "异步非递归 DNS 转发服务器（pipeline 规则、GeoIP/GeoSite、DoH/DoT/DoQ）";
    homepage = "https://github.com/olicesx/kixdns";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.unix;
    mainProgram = "kixdns";
  };
}
