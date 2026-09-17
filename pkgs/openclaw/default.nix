# openclaw 更新很快，nixpkgs 常年落后（nixpkgs 26.05 是 2026.5.7，unstable 是 2026.6.33，
# 上游已到 2026.9.4）。这里不重写整份 derivation，而是复用 nixpkgs 的 openclaw，
# 只覆盖 version、src 与 pnpmDepsHash，nixpkgs 那边改构建方式时能自动跟上。
#
# 两个 hash 都无法用标准库算（src 是 fetchFromGitHub 的 unpack 语义，
# pnpmDepsHash 需要跑 pnpm），所以不能像 claude-desktop 那样接到 scripts/update.py。
# 升级用 nix-update（见 README）。
{
  fetchFromGitHub,
  openclaw,
}:

let
  # 第一步只换版本。nixpkgs 那边 pnpmDeps 是用 finalAttrs 串的
  # （hash = finalAttrs.pnpmDepsHash，src 也 inherit 自 finalAttrs），
  # 所以这三项写在顶层就会传下去。
  bumped = openclaw.overrideAttrs (
    final: prev: {
      version = "2026.9.4";

      src = fetchFromGitHub {
        owner = "openclaw";
        repo = "openclaw";
        tag = "v${final.version}";
        hash = "sha256-xeUf0Emyhen4hnxjhbTI59d02QfB3YWTxhlqNkKuiUA=";
      };

      pnpmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

      meta = prev.meta // {
        # nixpkgs 给 openclaw 打了 knownVulnerabilities（LLM 解析不可信内容是提示注入面）。
        # 标记为 insecure 会让 Hydra 跳过构建（没有二进制缓存），消费方还得按版本号配
        # permittedInsecurePackages，每次升级都要改。自选的本地工具、风险已知，这里去掉。
        knownVulnerabilities = [ ];
      };
    }
  );
in
# 第二步再给 pnpmDeps 加抓取超时。必须分开写：overrideAttrs 里的 prev.pnpmDeps 是覆盖
# *之前* 那一份，在上面那层拿到的还是旧版本的 src 和 hash。
bumped.overrideAttrs (
  _: prev: {
    # 依赖里有一堆各平台的预编译二进制（node-llama-cpp 的 CUDA 版、各家的 win32/darwin
    # binding），单个几十上百 MB。链路慢的时候 pnpm 默认 60 秒的抓取超时不够，构建会以
    # "[23] The operation was aborted due to timeout" 结束。
    #
    # 开关只能用 pnpm_config_<设置名> 环境变量：nixpkgs 的 fetchPnpmDeps 是
    # pushd "$HOME" 之后才跑 pnpm，写进源码目录的 .npmrc 读不到；这个 fetcher 自己也是
    # 用这种变量设 side_effects_cache 的。NPM_CONFIG_* 是 npm 的前缀，pnpm 不认。
    pnpmDeps = prev.pnpmDeps.overrideAttrs (_: {
      pnpm_config_fetch_timeout = "1800000";
      pnpm_config_fetch_retries = "5";
      pnpm_config_fetch_retry_mintimeout = "20000";
      pnpm_config_fetch_retry_maxtimeout = "600000";
    });
  }
)
