#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

check_workflows() {
  local dir="$1"
  python3 - "$dir" <<'PY'
import pathlib, re, sys

wf_dir = pathlib.Path(sys.argv[1])
release = (wf_dir / "release.yml").read_text(encoding="utf-8")
selfcheck = (wf_dir / "self-check.yml").read_text(encoding="utf-8")

errors = []

for name, text in [("release.yml", release), ("self-check.yml", selfcheck)]:
    # CI-D：发布链路禁止任何持久依赖缓存。主仓 CI 与发布仓共用 Actions 缓存服务，
    # 一旦发布作业也挂载 Cargo/pnpm 缓存，遵循同一锁定键的构建就可能拿到不同源码树的
    # 指纹产物。发布要么不缓存（本仓选择），要么使用可区分命名空间的 provider，
    # 不得与主仓 CI 的 action 缓存混用。
    for forbidden in ["rust-cache", "actions/cache", "cache: 'pnpm'", 'cache: "pnpm"', "SCCACHE", "sccache", "pull_request_target", "macos-latest", "ubuntu-22.04", "windows-latest"]:
        if forbidden in text:
            errors.append(f"{name}: forbidden pattern found: {forbidden}")

    # Every actions/checkout block must declare persist-credentials: false
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if "uses: actions/checkout@" in line:
            block = "\n".join(lines[i:min(i+12, len(lines))])
            if "persist-credentials: false" not in block:
                errors.append(f"{name}:{i+1}: actions/checkout missing persist-credentials: false")
        if "uses: actions/upload-artifact@" in line:
            block = "\n".join(lines[i:min(i+10, len(lines))])
            if "retention-days: 1" not in block:
                errors.append(f"{name}:{i+1}: actions/upload-artifact missing retention-days: 1")

if not re.search(r"(?m)^permissions:\s*\n\s+contents:\s*read\b", release):
    errors.append("release.yml: missing top-level permissions: contents: read")

for required in [
    "expected_ref=\"refs/tags/$expected_tag\"",
    "commit_sha=$(git -C upstream rev-parse",
    "soxu-linux-amd64.tar.gz",
    "soxu-windows-amd64.zip",
    "soxu-darwin-arm64.tar.gz",
    "soxu-darwin-amd64.tar.gz",
    "sha256sum -c SHA256SUMS",
]:
    if required not in release:
        errors.append(f"release.yml: missing security/contract requirement: {required}")

# CI-D：工具链版本只能来自已核验源提交的 mise.toml。
# 本仓不得存在任何版本常量：一旦出现稳定版或大版本号，发布树与 mise.toml 就会静默漂移。
for forbidden_hardcoded in ["toolchain: stable", "toolchain: beta", "node-version: '26'", 'node-version: "26"']:
    if forbidden_hardcoded in release:
        errors.append(f"release.yml: hardcoded toolchain version: {forbidden_hardcoded}")
if re.search(r"(?m)^\s+version:\s*\d+\s*$", release):
    errors.append("release.yml: hardcoded pnpm version: version: <number>")

for required_toolchain in [
    "upstream/scripts/read-mise-versions.ps1",
    "-GitHubOutput",
    "-AssertInstalled",
    "needs.resolve.outputs.rust_version",
    "needs.resolve.outputs.node_version",
    "needs.resolve.outputs.pnpm_version",
    "mise_toml_sha256",
    # 正式发布的 darwin-amd64 必须跑在原生 Intel Runner 上并做二进制冒烟
    "runner: macos-15-intel",
]:
    if required_toolchain not in release:
        errors.append(f"release.yml: missing toolchain source wiring: {required_toolchain}")

# 三个构建作业各自消费 rust 版本并各自做实测比对，少一个就是漏接。
if len(re.findall(r"toolchain: \$\{\{ needs\.resolve\.outputs\.rust_version \}\}", release)) < 3:
    errors.append("release.yml: rust_version must be consumed by linux/windows/macos jobs")
if release.count("-AssertInstalled") < 3:
    errors.append("release.yml: every build job must assert installed toolchain versions")
if "sparse-checkout: mise.toml" in release:
    errors.append("release.yml: sparse checkout must include scripts/ for the version reader")

if errors:
    for e in errors:
        print("FAIL:", e, file=sys.stderr)
    sys.exit(1)

print("PASS: workflow security contract checks passed.")
PY
}

self_test() {
  check_workflows "$ROOT/.github/workflows"

  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  cp "$ROOT/.github/workflows/self-check.yml" "$tmp/self-check.yml"

  # Negative 1: re-introduced rust-cache
  sed 's/dtolnay\/rust-toolchain@v1/Swatinem\/rust-cache@v2/' "$ROOT/.github/workflows/release.yml" > "$tmp/release.yml"
  if check_workflows "$tmp" >/dev/null 2>&1; then
    echo "FAIL: negative test rust-cache should have failed" >&2
    exit 1
  fi

  # Negative 2: missing persist-credentials: false
  grep -v 'persist-credentials: false' "$ROOT/.github/workflows/release.yml" > "$tmp/release.yml"
  if check_workflows "$tmp" >/dev/null 2>&1; then
    echo "FAIL: negative test missing persist-credentials should have failed" >&2
    exit 1
  fi

  # Negative 3: drifting runner macos-latest
  sed 's/macos-15/macos-latest/g' "$ROOT/.github/workflows/release.yml" > "$tmp/release.yml"
  if check_workflows "$tmp" >/dev/null 2>&1; then
    echo "FAIL: negative test macos-latest should have failed" >&2
    exit 1
  fi

  # Negative 4: hardcoded toolchain version re-introduced
  python3 - "$ROOT/.github/workflows/release.yml" "$tmp/release.yml" \
    'toolchain: ${{ needs.resolve.outputs.rust_version }}' 'toolchain: stable' <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
text = open(src, encoding="utf-8").read()
if old not in text:
    sys.exit(3)
open(dst, "w", encoding="utf-8").write(text.replace(old, new))
PY
  if out=$(check_workflows "$tmp" 2>&1 || true); printf '%s' "$out" | grep -q 'hardcoded toolchain version: toolchain: stable'; then
    :
  else
    echo "FAIL: negative test hardcoded toolchain should have failed" >&2
    exit 1
  fi

  # Negative 5: toolchain source reader replaced by a non-existent path
  python3 - "$ROOT/.github/workflows/release.yml" "$tmp/release.yml" \
    'upstream/scripts/read-mise-versions.ps1' 'upstream/scripts/nonexistent.ps1' <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
text = open(src, encoding="utf-8").read()
if old not in text:
    sys.exit(3)
open(dst, "w", encoding="utf-8").write(text.replace(old, new))
PY
  if out=$(check_workflows "$tmp" 2>&1 || true); printf '%s' "$out" | grep -q 'missing toolchain source wiring: upstream/scripts/read-mise-versions.ps1'; then
    :
  else
    echo "FAIL: negative test missing toolchain source should have failed" >&2
    exit 1
  fi

  # Negative 6: darwin-amd64 silently falls back to the arm64 runner
  sed 's/runner: macos-15-intel/runner: macos-15/' "$ROOT/.github/workflows/release.yml" > "$tmp/release.yml"
  if out=$(check_workflows "$tmp" 2>&1 || true); printf '%s' "$out" | grep -q 'missing toolchain source wiring: runner: macos-15-intel'; then
    :
  else
    echo "FAIL: negative test non-native Intel runner should have failed" >&2
    exit 1
  fi

  echo "PASS: workflow security negative regression tests passed."
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit 0
fi

check_workflows "$ROOT/.github/workflows"
