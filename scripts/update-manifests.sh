#!/usr/bin/env bash
# Regenerate Scoop bucket, Homebrew formula and Winget manifests from SHA256SUMS.
# Fails closed if any expected archive is missing from SHA256SUMS.
set -euo pipefail

REPO="${TAP_RELEASE_REPO:-TanCan1998/soxu-releases}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${TAP_OUT_DIR:-$ROOT}"
HOMEPAGE="https://github.com/$REPO"
DESC="Soxu — High-performance multi-agent desktop workbench & daemon"
REPO_URL="https://github.com/$REPO/releases/download"

die() { echo "update-manifests: $*" >&2; exit 1; }

sha() {
  local s
  s="$(awk -v f="$2" '$2 == f { print $1 }' <<<"$1")"
  [ -n "$s" ] || die "$2 has no checksum in SHA256SUMS"
  echo "$s"
}

render_manifests() {
  local version="$1"
  local sums="$2"

  local a_win="soxu-windows-amd64.zip"
  local a_linux="soxu-linux-amd64.tar.gz"
  local a_mac_arm="soxu-darwin-arm64.tar.gz"
  local a_mac_x64="soxu-darwin-amd64.tar.gz"

  local s_win s_linux s_mac_arm s_mac_x64
  s_win="$(sha "$sums" "$a_win")"
  s_linux="$(sha "$sums" "$a_linux")"
  s_mac_arm="$(sha "$sums" "$a_mac_arm")"
  s_mac_x64="$(sha "$sums" "$a_mac_x64")"

  mkdir -p "$OUT/bucket" "$OUT/Formula" "$OUT/winget/TanCan1998.Soxu"

  cat > "$OUT/bucket/soxu.json" <<JSON
{
    "version": "$version",
    "description": "$DESC",
    "homepage": "$HOMEPAGE",
    "license": "Proprietary",
    "architecture": {
        "64bit": {
            "url": "$REPO_URL/v$version/$a_win",
            "hash": "$s_win"
        }
    },
    "bin": [
        "soxu.exe",
        "soxu-daemon.exe"
    ],
    "checkver": "github",
    "autoupdate": {
        "architecture": {
            "64bit": {
                "url": "$REPO_URL/v\$version/$a_win"
            }
        },
        "hash": {
            "url": "$REPO_URL/v\$version/SHA256SUMS"
        }
    }
}
JSON

  cat > "$OUT/Formula/soxu.rb" <<RUBY
class Soxu < Formula
  desc "$DESC"
  homepage "$HOMEPAGE"
  version "$version"

  on_macos do
    on_arm do
      url "$REPO_URL/v#{version}/$a_mac_arm"
      sha256 "$s_mac_arm"
    end

    on_intel do
      url "$REPO_URL/v#{version}/$a_mac_x64"
      sha256 "$s_mac_x64"
    end
  end

  on_linux do
    on_intel do
      url "$REPO_URL/v#{version}/$a_linux"
      sha256 "$s_linux"
    end
  end

  def install
    bin.install "soxu"
    bin.install "soxu-daemon"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/soxu --version")
  end
end
RUBY

  local schema="1.10.0"
  local wdir="$OUT/winget/TanCan1998.Soxu"
  cat > "$wdir/TanCan1998.Soxu.yaml" <<YAML
# yaml-language-server: \$schema=https://aka.ms/winget-manifest.version.$schema.schema.json
PackageIdentifier: TanCan1998.Soxu
PackageVersion: $version
DefaultLocale: en-US
ManifestType: version
ManifestVersion: $schema
YAML

  cat > "$wdir/TanCan1998.Soxu.installer.yaml" <<YAML
# yaml-language-server: \$schema=https://aka.ms/winget-manifest.installer.$schema.schema.json
PackageIdentifier: TanCan1998.Soxu
PackageVersion: $version
InstallerType: zip
NestedInstallerType: portable
NestedInstallerFiles:
- RelativeFilePath: soxu.exe
  PortableCommandAlias: soxu
- RelativeFilePath: soxu-daemon.exe
  PortableCommandAlias: soxu-daemon
Installers:
- Architecture: x64
  InstallerUrl: $REPO_URL/v$version/$a_win
  InstallerSha256: $(tr '[:lower:]' '[:upper:]' <<<"$s_win")
ManifestType: installer
ManifestVersion: $schema
YAML

  cat > "$wdir/TanCan1998.Soxu.locale.en-US.yaml" <<YAML
# yaml-language-server: \$schema=https://aka.ms/winget-manifest.defaultLocale.$schema.schema.json
PackageIdentifier: TanCan1998.Soxu
PackageVersion: $version
PackageLocale: en-US
Publisher: TanCan1998
PackageName: Soxu
License: Proprietary
ShortDescription: $DESC
ManifestType: defaultLocale
ManifestVersion: $schema
YAML
}

self_check() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  local fake_sums
  fake_sums="$(cat <<'EOF'
1111111111111111111111111111111111111111111111111111111111111111  soxu-windows-amd64.zip
2222222222222222222222222222222222222222222222222222222222222222  soxu-linux-amd64.tar.gz
3333333333333333333333333333333333333333333333333333333333333333  soxu-darwin-arm64.tar.gz
4444444444444444444444444444444444444444444444444444444444444444  soxu-darwin-amd64.tar.gz
EOF
)"
  TAP_OUT_DIR="$tmp" render_manifests_dir "$tmp" "0.1.0" "$fake_sums"
}

render_manifests_dir() {
  OUT="$1"
  render_manifests "$2" "$3"
  grep -q '"version": "0.1.0"' "$OUT/bucket/soxu.json"
  grep -q '3333333333333333333333333333333333333333333333333333333333333333' "$OUT/Formula/soxu.rb"
  grep -q 'InstallerSha256: 1111111111111111111111111111111111111111111111111111111111111111' "$OUT/winget/TanCan1998.Soxu/TanCan1998.Soxu.installer.yaml"
  if command -v python3 >/dev/null 2>&1; then
    python3 -m json.tool "$OUT/bucket/soxu.json" >/dev/null
  fi
  echo "PASS: update-manifests self-check (Scoop, Homebrew, Winget) passed."
}

if [ "${1:-}" = "--self-check" ]; then
  self_check
  exit 0
fi

VERSION="${1:?usage: $0 <version> [sha256sums-file] | --self-check}"
SUMS_FILE="${2:-}"
if [ -n "$SUMS_FILE" ] && [ -f "$SUMS_FILE" ]; then
  SUMS="$(cat "$SUMS_FILE")"
else
  SUMS="$(curl -fsSL "$REPO_URL/v$VERSION/SHA256SUMS")"
fi

render_manifests "$VERSION" "$SUMS"
echo "Updated manifests for v$VERSION under $OUT"
