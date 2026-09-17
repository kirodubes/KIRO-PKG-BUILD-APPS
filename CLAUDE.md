# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A collection of Arch Linux PKGBUILD directories used to build packages for Erik's `nemesis_repo` (`~/EDU/nemesis_repo/x86_64/`). Each subdirectory is one package. The repo contains orchestration scripts at the root that batch-build subsets of those packages.

## Structure

```
edu-pkgbuild/
├── 1-build-all-packages.sh       # build every subdirectory
├── 2-build-all-edu-packages.sh   # build edu-* subdirectories only
├── 3-build-all-edu-themes.sh     # build edu-neo-candy-* subdirectories only
├── build.sh                      # root template — copy this into new packages
├── setup.sh / up.sh              # git remote setup and push helpers
└── <package-name>/
    ├── PKGBUILD
    ├── build.sh                  # per-package build driver (copy of root template)
    ├── .current-version          # pkgver/pkgrel/epoch written after last build
    ├── .previous-version         # same values from the build before that
    └── readme.install            # optional pacman install hook message
```

## How building works

Each `build.sh` (inside a package dir) does in order:

1. `git pull` if `.git` exists
2. Bump `pkgver` to `YY.MM` (date), increment `pkgrel` (reset to `01` on new month)
3. Write `.current-version`, compare with `.previous-version` → set `BUILD_NEEDED`
4. If `BUILD_NEEDED=false`, exit early
5. Copy package dir to `/tmp/tempbuild/`, build there via:
   - `CHOICE=1` (default): `arch-nspawn` + `makechrootpkg -c -r ~/Documents/chroot-archlinux`
   - `CHOICE=2`: `makepkg -s` (set `makepkglist` to opt specific packages into this)
6. Copy `*.pkg.tar.zst` to `~/EDU/nemesis_repo/x86_64/`
7. Clean up `*.log`, `*.deb`, `*.tar.gz` from the source dir
8. Promote `.current-version` → `.previous-version`

After all packages build, the orchestration scripts call `~/EDU/nemesis_repo/up.sh` to publish.

## Running builds

```bash
# Build a single package (run from inside its directory)
bash build.sh

# Build all packages and publish
bash 1-build-all-packages.sh

# Build only edu-* packages
bash 2-build-all-edu-packages.sh

# Build only edu-neo-candy-* themes
bash 3-build-all-edu-themes.sh
```

## Adding a new package

1. Create a subdirectory named after the package (e.g. `edu-newpkg`)
2. Copy the root `build.sh` into it — that is the canonical template
3. Write a `PKGBUILD` — `pkgver` uses `YY.MM` format, `pkgrel` starts at `01`
4. On first run `build.sh` will create `.current-version`; `.previous-version` is created after the first successful build

## Version scheme

- `pkgver` = `YY.MM` (e.g. `26.05` for May 2026)
- `pkgrel` = two-digit zero-padded integer (`01`, `02`, …); resets to `01` when the month changes
- Both are updated automatically by `build.sh` before every build attempt

## Package naming conventions

| Prefix             | Purpose                          |
|--------------------|----------------------------------|
| `edu-*`            | General EDU project packages     |
| `edu-neo-candy-*`  | GTK/icon theme packages          |
| `edu-*-git`        | Packages built from a git source |
| `plymouth-theme-*` | Plymouth boot splash themes      |

## Bash script standard

All scripts in this repo follow this template:
`set -euo pipefail` → header block → `SCRIPT_DIR` → tput colors with TTY fallback → five log functions (`log_section` / `log_info` / `log_warn` / `log_error` / `log_success`) → `on_error` + trap → functions → `main()` ending with `log_success "$(basename "$0") done"` → `main "$@"`.

The per-package `build.sh` files in subdirectories already follow this template. Note that the root `build.sh` is currently *behind* them — it lacks the `git+` pkgver fix and the build-failure reporting block the package copies carry — so it is not a safe model to copy from, and `copy-files-to-all-folders.sh` would regress all 73 if run as-is.
