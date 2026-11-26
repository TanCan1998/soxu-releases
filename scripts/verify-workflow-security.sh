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
    for forbidden in ["rust-cache", "cache: 'pnpm'", 'cache: "pnpm"', "pull_request_target", "macos-latest", "ubuntu-22.04", "windows-latest"]:
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

  echo "PASS: workflow security negative regression tests passed."
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit 0
fi

check_workflows "$ROOT/.github/workflows"
