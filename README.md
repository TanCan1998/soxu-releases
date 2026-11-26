# soxu-releases

Verified cross-platform release builds, Scoop bucket, Homebrew tap and Winget manifests for **Soxu**.

## Verification & Provenance

Every release includes:
- Live binary smoke checks (`soxu --version`, `soxu-daemon` live `/api/health` + `soxu status --json`) on its target OS before publishing
- `SHA256SUMS` checksum manifest
- GitHub SLSA Build Provenance attestations (`gh attestation verify <archive> -R TanCan1998/soxu-releases`)

## Installation

### Scoop (Windows)

```powershell
scoop bucket add soxu https://github.com/TanCan1998/soxu-releases
scoop install soxu/soxu
```

### Homebrew (macOS / Linux)

```sh
brew tap TanCan1998/soxu-releases https://github.com/TanCan1998/soxu-releases
brew install soxu
```

### Winget (Windows)

Manifests are maintained under `winget/TanCan1998.Soxu/` on every tagged release.
