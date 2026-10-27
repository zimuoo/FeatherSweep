<div align="center">
  <img src="Resources/AppLogo.png" width="96" alt="FeatherSweep logo" />
  <h1>FeatherSweep · 轻扫</h1>
  <p><strong>A small native window for a carefully scoped Mac cleanup.</strong></p>
  <p>macOS 14+ · Apple Silicon · SwiftUI + AppKit · Menu bar support</p>
  <p><a href="https://github.com/zimuoo/FeatherSweep/releases/latest/download/FeatherSweep-1.0.0-arm64.dmg"><strong>Download DMG</strong></a> · <a href="README.md">简体中文</a></p>
</div>

<p align="center"><img src="docs/images/overview.png" width="460" alt="Native FeatherSweep window with example cleanup data" /><br /><sub>Actual native UI using demo data, not a live disk measurement.</sub></p>

## What it does

**View garbage**, inspect the paths and reasons, then **clean garbage**. Closing the window leaves FeatherSweep available in the menu bar. Scanning rings, numeric transitions, cleanup particles and completion feedback respect Reduce Motion.

The app runs locally, requires no account, and makes no network requests. There is no third-party runtime, privileged helper, launch agent or automatic startup cleanup.

## Install

Download `FeatherSweep-1.0.0-arm64.dmg` from [Releases](https://github.com/zimuoo/FeatherSweep/releases/latest), open it, and drag **轻扫.app** into **Applications**.

Requires an Apple Silicon Mac running macOS 14 or newer. The current build is locally ad hoc signed, **not Apple notarized**. Use only this repository's release assets. FeatherSweep does not ask you to disable Gatekeeper.

```sh
shasum -a 256 -c SHA256SUMS.txt
```

## Carefully defined cleanup scope

| Category | Scope | Preserved |
|---|---|---|
| Compilation | Recognized Go caches and designated Rust intermediates | Source, fuzz corpora and runnable binaries |
| Cursor | Historical snapshots and rebuildable conversation-search index | Settings, extensions, main state DB and login data |
| Packaging | Recognized staging copies and SHA-256-identical extra packages; idle browser signing clones | Formal releases, validation records, active/newest clones |
| Updates | Obsolete Cursor and redundant/outdated Telegram downloads | Installed apps and newest pending download |
| Static web cache | Recognized Feishu/Cloudflare static assets in Chrome | Passwords, cookies, sessions, IndexedDB and Local Storage |
| Blender | Recognized Agent Bridge checkpoints | **Latest modified backup for each scene** |

Rules derive from manually verified folders. Some project-specific rules refer to `Desktop/docker/yijun_project` under the current home; absent paths are skipped. The app does not empty Downloads, delete all DMGs, remove model/SDK installations, or wipe browser profiles.

## Safety behavior

- Scanning is read-only; cleanup requires a recent scan and a user action.
- Open files, running builds, Cargo build locks, changed identities or changed directory metadata cause skips.
- Descriptor-relative deletion with `O_NOFOLLOW` prevents symlink traversal.
- Formal package references are SHA-256 verified and revalidated immediately before removing duplicate copies.
- Incomplete occupancy checks stop cleanup. Partial results are explicitly counted.
- Shared signing-clone storage is not presented as reclaimable terabytes.
- Only the latest 20 cleanup count summaries are stored locally, without file contents.

**Cleanup permanently removes validated candidates rather than moving them to Trash. Inspect the details first.** Permission-denied paths are skipped with an explanation; root access is not required.

## Build and test

```sh
git clone https://github.com/zimuoo/FeatherSweep.git
cd FeatherSweep
swift test --scratch-path /private/tmp/feathersweep-test-build
bash scripts/build.sh
```

The build uses system Swift, AppKit, iconutil, codesign and hdiutil, downloads no dependencies, and removes its private per-run build directory. Output: `dist/FeatherSweep-1.0.0-arm64.dmg`.

```sh
# Safe example UI: no real cleanup
"/Applications/轻扫.app/Contents/MacOS/FeatherSweep" --demo

# Real read-only scan, JSON to stdout
"/Applications/轻扫.app/Contents/MacOS/FeatherSweep" --scan-json
```

The 32 local safety tests use disposable fixtures. They cover credential/source retention, symlinks, changed files, active files and mid-clean opens, Cargo locks, Blender naming edges, clone retention, duplicate references, static-resource parsing and partial cleanup accounting. An Intel release has not been built or verified.
