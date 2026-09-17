# Changelog

## 2026.09.17

### What Changed
- **A failing package took the whole batch down, and a failed build reported itself as a success.**
  Two halves of the same hole. `1-build-all-packages.sh` ran `(cd "$dir" && sh ./build*)` bare under
  `set -euo pipefail`, so the first package whose build script died — typically `arch-nspawn ...
  pacman -Syu`, run once per package, on a mirror desync — aborted every remaining package. And the
  per-package `build.sh` swallowed build failures entirely: `makechrootpkg` failing left
  `success="false"`, but the script still promoted `.current-version` → `.previous-version`, still
  printed `Build done for <pkg>`, and still exited `0`. The only honest record of what shipped was
  the contents of `nemesis_repo/x86_64/`. Now a failed package is recorded and the batch continues,
  and the run ends with an explicit list of what did **not** build.
- **`change-version-100.sh` pinned to a hardcoded `26.06`, which turns the cutoff into a downgrade.**
  The script exists to out-rank every installed package so a `pacman -Syu` re-pulls the whole set.
  With `FORCE_PKGVER="26.06"` frozen in place, running it after the packages had moved on to a later
  month would have written a *lower* `pkgver` — `26.06-100` loses to `26.09-01` because `vercmp`
  compares `pkgver` before `pkgrel` — so `-Syu` would have refused the "cutoff" entirely. Now
  `FORCE_PKGVER="$(date +%y.%m)"`, matching what `build.sh` already does.
- **Two dead GitHub remotes hung the whole batch for ~an hour, silently.**
  `kiro-surfn-numixs-blue` and `plymouth-theme-kiro` pointed at repos that no longer exist. `git
  clone` got `Repository not found` and, because the URL is HTTPS, fell back to an **interactive
  credential prompt** inside the chroot — so it blocked forever at zero bytes transferred rather
  than failing. 47 minutes on the first, 12 on the second, each ended only by killing the clone by
  hand. From the outside a blocked prompt is indistinguishable from a slow build. Both packages are
  removed, and root plus 72 per-package `build.sh` now export `GIT_TERMINAL_PROMPT=0`. That covers
  git calls the script makes in its own shell; it most likely does **not** reach the
  `makepkg --verifysource` clone that actually hung, which sits behind two `sudo` hops — see
  Technical Details before assuming this hang cannot recur.

### Technical Details
- `build.sh` (75 packages): on `success != true` the script logs the failure to `/tmp/failed` and
  exits `1`. `.previous-version` is deliberately **not** promoted on failure — it must never claim a
  version shipped when the build produced nothing. Harmless for the next run, since `bump_version`
  re-bumps `pkgrel` before the comparison, so `BUILD_NEEDED` would be true regardless.
- `kiro-plasma-meta/build.sh` needed no change: it is a meta package with none of the version
  machinery, and its `(cd /tmp/tempbuild && makepkg -df)` is already bare under `set -e`.
- `1-build-all-packages.sh`: the per-package call is wrapped in `if ... ; then continue; fi` (a
  failing command in an `if` condition triggers neither `set -e` nor the `ERR` trap), failures
  accumulate in a `FAILED` array, and a new `report_failures` prints the summary after publishing.
  `/tmp/failed` is truncated at the start of a run so it reflects that run only — a manually invoked
  `build.sh` still appends to it.
- `sh ./build*` → `bash ./build*`. Every build script is `#!/bin/bash` with `set -euo pipefail`,
  `[[ ]]` and `BASH_SOURCE`; invoking them through `sh` was relying on Arch's `/bin/sh` → bash
  symlink for no benefit.
- Verified against stub packages: a failing package is reported, the following packages still build,
  publishing still runs, and the summary lists both the failure and the no-build-script skip.
- `change-version-100.sh`: `pkgrel=100` stays hardcoded on purpose — within a single `pkgver` it
  still out-ranks any release in the repo, which is the whole point of the cutoff. Only the `pkgver`
  half needed to follow the clock. Purpose header updated to read `pkgver=<current YY.MM>`.

- The same abort bug lived in the two other batch drivers and is fixed the same way.
  `build-skel-hint-packages.sh` and `build-twm-xfce-plasma-hyprland-packages.sh` both ran
  `(cd "$dir" && sh ./build.sh)` bare, and their "directory not found" / "no build.sh" skips were
  silent — a package could vanish from the batch with nothing but a scrolled-past warning. Both now
  record every skip and failure and print the summary at the end. In the twm script the
  `push_sources` loop gets the same treatment: a repo that will not push no longer stops the other
  pushes or the builds, and push failures are labelled as such in the summary.
- **Four new packages tracked in git.** `fish-tweak-tool`, `kiro-dusk`, `kiro-hlwm` and
  `kiro-starship` existed on disk but had never been committed, so the build-driver fix above would
  have lived only in Erik's working copy for those four.

- **`mir`, `miracle-wm-git` and `wasmedge` moved out to KIRO-PKG-BUILD-3PARTY.** All three were AUR
  clones with their own nested `.git` pointing at `aur.archlinux.org`, carrying upstream versions
  instead of this repo's `YY.MM` scheme, and they were the only three dirs here without a
  `build.sh` — so every batch run listed them as `(no build script)`. The 3PARTY repo already
  classifies packages by their real upstream signal and syncs the AUR tree itself, which is exactly
  what they need. This repo is now 75 dirs, all 75 buildable, with an empty failure list.
- `export GIT_TERMINAL_PROMPT=0` sits directly after `SCRIPT_DIR=` in root `build.sh` and in 72 of
  the 73 package copies. `kiro-plasma-meta/build.sh` is deliberately excluded: its PKGBUILD has
  `source=()` and the script contains no `git` call at all, so the export would be dead code.
- **Honest limitation:** `makechrootpkg` is reached through two `sudo` layers, and neither
  `--preserve-env` allowlist includes `GIT_TERMINAL_PROMPT` (the inner
  `sudo -u erik --preserve-env=GNUPGHOME,SSH_AUTH_SOCK env ... makepkg --verifysource` is devtools'
  own code). So the export reliably protects git calls `build.sh` makes in its *own* shell, but
  probably does **not** reach the `--verifysource` clone that actually hung. This could not be
  tested: `sudo -n` on this box is NOPASSWD for `dmesg` only. The guaranteed fix, if the hang
  recurs, is a pre-flight `GIT_TERMINAL_PROMPT=0 timeout 30 git ls-remote "$url" HEAD` in
  `build.sh`'s own shell before the `makechrootpkg` call.
- Diagnosis method worth keeping: a hung clone shows a frozen `rchar` in `/proc/<pid>/io` across a
  10s sample, no socket in `ss -tnp`, and `wchan` of `wait_woken` — while `git ls-remote` against
  the same URL from a normal shell returns the real error immediately.
- The 73 package `build.sh` copies are **not** uniform: 69 are current, `kiro-arc-kde`,
  `kiro-assistant` and `kiro-keybindings` still lack the `git+` pkgver fix, and `kiro-plasma-meta`
  is a separate meta-package script. Root `build.sh` is older than all of them, so
  `copy-files-to-all-folders.sh` would currently regress every package copy if run.
- `CLAUDE.md` documented a `build-data.sh` that does not exist — the driver is `build.sh` — and
  claimed the package copies were "still on the old style" when they already follow the standard
  template and are in fact ahead of root. Both corrected.

### Files Modified
- `1-build-all-packages.sh`
- `build-skel-hint-packages.sh`
- `build-twm-xfce-plasma-hyprland-packages.sh`
- `change-version-100.sh`
- `*/build.sh` (75 packages; `kiro-plasma-meta` unchanged)
- `build.sh` + `*/build.sh` (72 package copies; `kiro-plasma-meta` excluded — no git usage)
- `CLAUDE.md`
- Removed (dead upstream repos): `kiro-surfn-numixs-blue/`, `plymouth-theme-kiro/` — repo now 75 dirs
- Added: `fish-tweak-tool/`, `kiro-dusk/`, `kiro-hlwm/`, `kiro-starship/`
- Moved to KIRO-PKG-BUILD-3PARTY: `mir/`, `miracle-wm-git/`, `wasmedge/`

## 2026.09.12

### What Changed
- **`kiro-polybar` — `pkgdesc` still carried the pre-rename EDU branding.** It read
  `"Polybar configuration for edu"`; now `"Polybar configuration for Kiro"`. Leftover from the
  `edu-polybar-git` → `kiro-polybar` rename (the `replaces`/`conflicts` entries for the old name are
  intentional and were left in place).

### Technical Details
- `pkgver`/`pkgrel` were **not** touched — `build.sh` auto-bumps them (`pkgver=$(date +%y.%m)`,
  `pkgrel` reset to `01` on a version change), so a manual edit would be overwritten at build time.
  The description change reaches users on the next rebuild.

### Files Modified
- `kiro-polybar/PKGBUILD`

## 2026.08.23

### What Changed
- **`ohmychadwm/readme.install` — the "already built?" guard tested a binary name that never
  exists.** `post_install()` skipped the local build only when `command -v chadwm` succeeded, but
  the Makefile under `etc/skel/.config/ohmychadwm/chadwm/` produces a binary called **`ohmychadwm`**
  (`cp -f ohmychadwm ${DESTDIR}${PREFIX}/bin`, `PREFIX = /usr/local`). Nothing on a Kiro system
  provides a `chadwm` binary, so the guard never matched: every install and every upgrade of the
  package recompiled from `/etc/skel` and `make install`-ed an **unowned** `/usr/local/bin/ohmychadwm`
  that shadows the packaged `/usr/bin/ohmychadwm` on `PATH`. Found on the v26.08.23 VM, where both
  copies are byte-identical (md5 `2ded2091…`) and `pacman -Qo` reports no owner.
- **`kiro-chadwm/readme.install` — the last `arco-chadwm` path, three months after the rename.**
  `SKEL_DIR` still pointed at `/etc/skel/.config/arco-chadwm`, but the folder was renamed to
  `.config/chadwm` on 2026-05-24 as part of the Kiro de-brand ("path token `arco-chadwm` →
  `chadwm` rewritten across all 10 referencing files in one pass"). That pass covered the
  `kiro-chadwm` **source** repo; this file lives in `KIRO-PKG-BUILD-APPS`, so it was missed.
  Effect: `post_install()` tested a directory that no longer exists, printed
  `WARNING: … does not exist. Skipping chadwm setup.` and returned early — never copying the
  config to the user and never building chadwm. Latent rather than shipping-broken:
  `kiro-chadwm` is commented out in the ISO's `packages.x86_64`.

### Technical Details
- The guard now tests `command -v ohmychadwm`, so the local build runs once at most and a machine
  that already has the packaged binary is left alone.
- The three sibling messages that name the *binary* were corrected with it; the ones naming the
  **source directory** (`chadwm build folder not found`, the `make` step messages, `CHADWM_DIR`)
  are left as-is — that directory really is called `chadwm`.
- The `slstatus` half of the same script was checked and is correct: its Makefile installs
  `slstatus`, which is the name its guard tests. Note `slstatus` is packaged nowhere else, so
  `/usr/local/bin/slstatus` is load-bearing — it must keep being built here.
- `kiro-chadwm`: `SKEL_DIR` and `USER_CONFIG_DIR` now use `chadwm`; `BUILD_DIR` was already
  correct (`$SKEL_DIR/chadwm` — the inner build dir really is called `chadwm`), as was the
  `[ ! -f /usr/local/bin/chadwm ]` guard, since that Makefile does install a `chadwm` binary.
- The two user-visible `** Building / Installing ArcoLinux Chadwm **` banners in the same file
  became `Kiro Chadwm`, finishing the brand sweep the 2026-05-24 entry set out to do.
- Takes effect on the next `ohmychadwm` rebuild; existing installs keep the shadowing copy until
  it is removed by hand.

### Files Modified
- `ohmychadwm/readme.install`
- `kiro-chadwm/readme.install`

## 2026.06.29

### What Changed
- **Added `build-twm-xfce-packages.sh`** — batch push+build+publish for all Kiro
  tiling window managers (`ohmychadwm`, `kiro-chadwm`, `kiro-awesome`,
  `kiro-bspwm`, `kiro-i3`, `kiro-leftwm`, `kiro-qtile`) plus `kiro-xfce`. In
  order it (1) pushes each source repo `~/KIRO/<name>` to GitHub via its own
  `up.sh`, (2) builds each package from its `build.sh` here, (3) publishes once
  with `~/EDU/nemesis_repo/up.sh`. The push step is required because the build
  dirs pull `kirodubes/<name>` as a `git+` source — without it the chroot builds
  stale config. Modelled on `build-skel-hint-packages.sh`. Use after a
  cross-environment change such as propagating ohmychadwm's keybindings to every
  other TWM + XFCE.

### Files Modified
- `build-twm-xfce-packages.sh` (new)

## 2026.06.28

### What Changed
- **Added `kiro-starship`** — new package build dir for the default Starship
  prompt configuration. Builds from `kirodubes/kiro-starship` into `nemesis_repo`
  and ships `etc/skel/.config/starship.toml` to `/etc/skel` (new users inherit it
  automatically). `depends=('starship')`. PKGBUILD models the `kiro-fish-config`
  recipe (git+ source, GPL3, `provides`, `.install` post-install hint). build.sh
  copied from `kiro-fish-config`.

### Files Modified
- `kiro-starship/PKGBUILD` (new)
- `kiro-starship/kiro-starship.install` (new)
- `kiro-starship/build.sh` (new)

## 2026.06.20

### What Changed
- **Added `kiro-plasma-window-management`** (renamed from `kiro-plasma-kwin-rules`) —
  new package build dir for KWin window-management config. Builds from
  `kirodubes/kiro-plasma-window-management`, ships `/etc/xdg/kwinrc` (4 virtual
  desktops, effects, titlebar-wheel maximize, flipswitch, ShowDesktop edge). The
  `kwinrc` was consolidated here out of `kiro-plasma-system-settings` so only one
  package owns `/etc/xdg/kwinrc`. Ready to build. Window rules (`kwinrulesrc`) to come.
- **`kiro-plasma-servicemenus`** — `depends=('kdialog')` (the only hard requirement —
  used by the Checksum popup); the other helpers are `optdepends` left to the user
  (`imagemagick`, `meld`, `kdesu`, `mintstick`, `gittyup`, `code`, `alacritty`).
  De-branded the `pkgdesc` ("Servicemenu files for edu" → "KDE Plasma Dolphin
  service-menu actions for Kiro").
- **Added `kiro-plasma-dolphin`** — new package build dir for the default Dolphin
  configuration. Builds from `kirodubes/kiro-plasma-dolphin` into `nemesis_repo` and
  ships a minimal `dolphinrc` to `/etc/xdg` (XDG cascade; menubar off + file-dialog
  places sizing). Same recipe shape as `kiro-plasma-system-settings`.
- **Added `kiro-plasma-konsole`** — new package build dir for the default Konsole
  configuration. Builds from `kirodubes/kiro-plasma-konsole` into `nemesis_repo` and
  ships the Kiro profile, ArcDark colour scheme, and `konsolerc` to `/etc/skel`.
  PKGBUILD models the `kiro-plasma-system-settings` recipe (`_destname="/etc"`, git+
  source, GPL3, license under `/usr/share/kiro/licenses/`, `build.sh` md5 `ff42d7d4`).
- **Added `kiro-plasma-system-settings`** — new package build dir for the default
  KDE Plasma System Settings configuration. Builds from
  `kirodubes/kiro-plasma-system-settings` into `nemesis_repo` and ships behavioural
  defaults (lock screen, logout/session, hot corner, power timeouts) to `/etc/xdg/`.

### Technical Details
- PKGBUILD modelled on `kiro-plasma-keybindings` but ships `/etc` only (no `/usr`):
  `_destname="/etc"`, git+ source, `GPL3`, license copied under
  `/usr/share/kiro/licenses/`. `build.sh` is the generic per-package builder
  (copied from `kiro-plasma-keybindings`, md5 `ff42d7d4`).
- Delivery is `/etc/xdg/` (XDG cascade defaults) rather than `/etc/skel/` —
  verified on a Plasma 6 box that all four files are honored by the cascade.
- `pkgrel` starts at `01`; version files are created on first build.

### Files Modified
- `kiro-plasma-system-settings/PKGBUILD`, `kiro-plasma-system-settings/build.sh`,
  `kiro-plasma-system-settings/readme.install`

## 2026.06.19

### What Changed
- **Added `kiro-grub-theme`** — a new package build dir for the Kiro-branded
  GRUB2 boot theme. Builds from `kirodubes/kiro-grub-theme` into `nemesis_repo`
  and installs the theme to `/boot/grub/themes/kiro/`.

### Technical Details
- PKGBUILD modelled on `kiro-rofi-themes` (git+ source, `GPL3` license, ships a
  copy of `LICENSE` under `/usr/share/kiro/licenses/`); `build.sh` is the generic
  per-package builder copied from `kiro-bootloader-grub`.
- No `-nemesis` twin (matches `kiro-rofi-themes`, the closest theme-content
  analog). Add one only if a `kiro_repo` edition is needed.

### Files Modified
- `kiro-grub-theme/PKGBUILD`, `kiro-grub-theme/build.sh`,
  `kiro-grub-theme/readme.install`

## 2026.06.17

### What Changed
- **Deleted 28 superseded `edu-*` package build dirs.** Each had a live `kiro-*`
  replacement already building and shipping to `nemesis_repo`, so the legacy EDU
  recipe was dead weight. Kept **`edu-sddm-simplicity-qt6`** — the only EDU
  package with no Kiro equivalent yet (`kiro-sddm-simplicity-qt6` does not exist).
- This also clears the stale dependency references the EDU recipes carried (e.g.
  `edu-chadwm` depended on the non-existent `edu-rofi-git` / `edu-rofi-themes-git`;
  the live `ohmychadwm` recipe already uses `kiro-rofi` / `kiro-rofi-themes`).

### Technical Details
- Removed dirs (28): edu-arc-dawn, edu-awesome, edu-bspwm, edu-chadwm,
  edu-dot-files, edu-i3-git, edu-leftwm-git, edu-neo-candy-arc,
  edu-neo-candy-arc-mint-grey, edu-neo-candy-arc-mint-red, edu-neo-candy-qogir,
  edu-neo-candy-tela, edu-papirus-dark-tela, edu-papirus-dark-tela-grey,
  edu-plasma-keybindings-git, edu-plasma-servicemenus-git, edu-polybar-git,
  edu-powermenu, edu-qtile-git, edu-rofi-git, edu-rofi-themes,
  edu-sddm-simplicity, edu-shells, edu-surfn-numixs-blue, edu-system-files,
  edu-variety-config, edu-vimix-dark-tela, edu-xfce.
- Kept: edu-sddm-simplicity-qt6.
- `kiro-system-files/PKGBUILD` intentionally retains
  `conflicts/replaces=('edu-system-files-git')` as the upgrade path — left as-is.

### Files Modified
- Deleted 28 `edu-*/` build directories (133 files)
- Created `CHANGELOG.md`
