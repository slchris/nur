#!/usr/bin/env node
// 2026.9.5 版的 dist 适配补丁（nix-openclaw 的 patch-openclaw-npm-dist.mjs 只认它当时打包
// 的 2026.9.4 dist 结构，2026.9.5 把 hardlink-policy 拆成独立模块、ownership 检查扩散到
// 两个 bundle，旧的 contract 就全对不上了）。
//
// 这里只做 Nix 场景真正必需的一步：让 bundled / Nix store 里的插件跳过 ownership 检查
// （store 里的文件属主是 root/nixbld，uid 必然和运行用户不一致，不跳过插件就加载不了）。
// 上游 2026.9.5 的 hardlink-policy 已经用 pluginCacheRealpathSync 做真实路径判断，旧补丁的
// “重写 hardlink policy”那一步不再需要；missing-install 的自动装插件在 Nix 模式下本就不该跑，
// 但网关 wrapper 已设 OPENCLAW_DISABLE_PERSISTED_PLUGIN_REGISTRY=1，先不额外加护栏。
import fs from "node:fs";
import path from "node:path";

const root = process.env.OPENCLAW_PACKAGE_ROOT;
if (!root) {
  console.error("OPENCLAW_PACKAGE_ROOT is required");
  process.exit(1);
}
const distDir = path.join(root, "dist");
if (!fs.existsSync(distDir)) {
  console.error(`OpenClaw dist directory missing: ${distDir}`);
  process.exit(1);
}

const ownershipCheck =
  'params.origin !== "bundled" && params.uid !== null && typeof stat.uid === "number" && stat.uid !== params.uid && stat.uid !== 0';
const patchedCheck =
  'params.origin !== "bundled" && params.uid !== null && shouldRejectHardlinkedPluginFiles(params) && typeof stat.uid === "number" && stat.uid !== params.uid && stat.uid !== 0';

function walk(dir) {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walk(full));
    else if (entry.isFile() && /\.m?js$/.test(entry.name)) out.push(full);
  }
  return out;
}

let patched = 0;
for (const file of walk(distDir)) {
  const source = fs.readFileSync(file, "utf8");
  if (!source.includes(ownershipCheck)) continue;
  // 只有文件里已经能看到 shouldRejectHardlinkedPluginFiles（import 或本地定义）才敢插入调用，
  // 否则会引入未定义符号。
  if (!source.includes("shouldRejectHardlinkedPluginFiles")) continue;
  const count = source.split(ownershipCheck).length - 1;
  fs.writeFileSync(file, source.split(ownershipCheck).join(patchedCheck));
  console.log(`patched ${path.relative(distDir, file)} (${count} ownership check)`);
  patched += count;
}

if (patched === 0) {
  console.error("no ownership checks patched; upstream dist contract changed");
  process.exit(1);
}
console.log(`openclaw dist ownership patch applied to ${patched} check(s)`);
