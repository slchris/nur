#!/usr/bin/env python3
"""检查上游新版本并改写包文件。

只用标准库，本机与 CI 都能直接执行。改动过的包名写到 GITHUB_OUTPUT 的 changed，
提交信息写到 .git/UPDATE_MSG。任一上游检查失败时退出码为 1，其余包照常更新。
"""

import base64
import hashlib
import os
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) slchris-nur-updater"


def get(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=120) as resp:
        return resp.read()


def sha256_sri_of_url(url: str) -> str:
    digest = hashlib.sha256()
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=600) as resp:
        while chunk := resp.read(1 << 20):
            digest.update(chunk)
    return "sha256-" + base64.b64encode(digest.digest()).decode()


def hex_to_sri(hex_digest: str) -> str:
    return "sha256-" + base64.b64encode(bytes.fromhex(hex_digest)).decode()


def vkey(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in version.split("."))


def replace_once(text: str, old: str, new: str) -> str:
    if text.count(old) != 1:
        raise RuntimeError(f"在包文件里找不到唯一的 {old!r}")
    return text.replace(old, new)


def update_claude_desktop() -> str | None:
    path = ROOT / "pkgs/claude-desktop/default.nix"
    text = path.read_text()
    current = re.search(r'version = "([0-9.]+)";', text).group(1)

    index = get(
        "https://downloads.claude.ai/claude-desktop/apt/stable/dists/stable/main/binary-amd64/Packages"
    ).decode()
    entries = {}
    for stanza in index.split("\n\n"):
        fields = dict(
            line.split(": ", 1) for line in stanza.splitlines() if ": " in line and not line.startswith(" ")
        )
        if fields.get("Package") == "claude-desktop" and re.fullmatch(r"[0-9.]+", fields.get("Version", "")):
            entries[fields["Version"]] = fields["SHA256"]
    latest = max(entries, key=vkey)
    if vkey(latest) <= vkey(current):
        return None

    old_hash = re.search(r'hash = "(sha256-[^"]+)";', text).group(1)
    text = replace_once(text, f'version = "{current}";', f'version = "{latest}";')
    text = replace_once(text, old_hash, hex_to_sri(entries[latest]))
    path.write_text(text)
    return f"claude-desktop {current} -> {latest}"


def update_zcode() -> str | None:
    path = ROOT / "pkgs/zcode/default.nix"
    text = path.read_text()
    current = re.search(r'version = "([0-9.]+)";', text).group(1)

    # 官方没有公开的更新清单，下载页里写的就是当前版本的 AppImage 地址。
    page = get("https://zcode.z.ai/en/docs/install").decode("utf-8", "replace")
    versions = set(re.findall(r"releases/([0-9]+\.[0-9]+\.[0-9]+)/linux-x64/ZCode-\1-linux-x64\.AppImage", page))
    if not versions:
        raise RuntimeError("下载页里找不到 Linux AppImage 的地址，页面结构可能变了")
    latest = max(versions, key=vkey)
    if vkey(latest) <= vkey(current):
        return None

    url = f"https://cdn-zcode.z.ai/zcode/electron/releases/{latest}/linux-x64/ZCode-{latest}-linux-x64.AppImage"
    old_hash = re.search(r'hash = "(sha256-[^"]+)";', text).group(1)
    text = replace_once(text, f'version = "{current}";', f'version = "{latest}";')
    text = replace_once(text, old_hash, sha256_sri_of_url(url))
    path.write_text(text)
    return f"zcode {current} -> {latest}"


def update_snell_server() -> str | None:
    path = ROOT / "pkgs/snell-server/default.nix"
    text = path.read_text()
    default = re.search(r'version \? "([0-9.]+)"', text).group(1)
    known = dict(re.findall(r'"([0-9.]+)" = "(sha256-[^"]+)";', text))

    # 只收正式版，跳过 6.0.0rc 这类测试版。
    page = get("https://kb.nssurge.com/surge-knowledge-base/release-notes/snell").decode("utf-8", "replace")
    stable = set(re.findall(r"snell-server-v([0-9]+\.[0-9]+\.[0-9]+)-linux-amd64\.zip", page))
    new = sorted((v for v in stable if v not in known), key=vkey)
    if not new:
        return None

    for version in new:
        known[version] = sha256_sri_of_url(f"https://dl.nssurge.com/snell/snell-server-v{version}-linux-amd64.zip")

    # 默认版本只在同一主版本内升级：主版本变化要求客户端同时升级，所以新主版本只加入哈希表，由使用方手动切换。
    same_major = [v for v in known if vkey(v)[0] == vkey(default)[0]]
    new_default = max(same_major, key=vkey)

    table = "".join(f'    "{v}" = "{known[v]}";\n' for v in sorted(known, key=vkey, reverse=True))
    text = re.sub(r"(  hashes = \{\n)(?:    \"[0-9.]+\" = \"sha256-[^\"]+\";\n)+", lambda m: m.group(1) + table, text)
    text = replace_once(text, f'version ? "{default}"', f'version ? "{new_default}"')
    path.write_text(text)

    added = ", ".join(new)
    if new_default != default:
        return f"snell-server {default} -> {new_default}（新增 {added}）"
    return f"snell-server 新增 {added}，默认仍为 {default}"


def main() -> int:
    updaters = {
        "claude-desktop": update_claude_desktop,
        "snell-server": update_snell_server,
        "zcode": update_zcode,
    }
    only = set(sys.argv[1:])
    changes = {}
    failed = []
    for name, updater in updaters.items():
        if only and name not in only:
            continue
        try:
            result = updater()
        except Exception as exc:  # 一个上游出问题不影响其他包
            print(f"{name}: 检查失败：{exc}", file=sys.stderr)
            failed.append(name)
            continue
        print(result or f"{name} 已是最新")
        if result:
            changes[name] = result

    if output := os.environ.get("GITHUB_OUTPUT"):
        with open(output, "a") as fh:
            fh.write(f"changed={' '.join(changes)}\n")
    if changes:
        message = ROOT / ".git" / "UPDATE_MSG"
        lines = list(changes.values())
        if len(lines) == 1:
            text = f"chore: {lines[0]}\n"
        else:
            text = "chore: 更新 " + "、".join(changes) + "\n\n" + "\n".join(f"- {line}" for line in lines) + "\n"
        message.write_text(text)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
