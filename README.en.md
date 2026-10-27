<div align="center">
  <img src="Resources/AppLogo.png" width="96" alt="FeatherSweep logo" />
  <h1>FeatherSweep · 轻扫</h1>
  <p><strong>A small native window for a carefully scoped Mac cleanup.</strong></p>
  <p>macOS 14+ · Apple Silicon + Intel · SwiftUI + AppKit · Menu bar support</p>
  <p><a href="https://github.com/zimuoo/FeatherSweep/releases/download/v1.2.0/FeatherSweep-1.2.0-arm64.dmg"><strong>Download Apple Silicon</strong></a> · <a href="https://github.com/zimuoo/FeatherSweep/releases/download/v1.2.0/FeatherSweep-1.2.0-x86_64.dmg"><strong>Download Intel</strong></a> · <a href="README.md">简体中文</a></p>
</div>

<p align="center"><img src="docs/images/overview.png" width="460" alt="Native FeatherSweep window with example cleanup data" /><br /><sub>Actual native UI using demo data, not a live disk measurement.</sub></p>

<details><summary><strong>Selection and impact details</strong></summary>
<p align="center"><img src="docs/images/selection.png" width="460" alt="Native mixed checkbox and per-item restore-history impact using demo data" /></p>
</details>

## What it does

**View garbage**, inspect paths and impacts, select the items you want, then **clean garbage**. Every scan starts with nothing selected. Closing the window leaves FeatherSweep available in the menu bar. Scanning rings, numeric transitions, cleanup particles and completion feedback respect Reduce Motion.

Cleanup runs locally and requires no account. Update checks contact GitHub and its download services; scan data, file contents and credentials are never uploaded. Sparkle 2.10.1 provides the native update mechanism. There is no automatic startup cleanup.

## Install

Choose the native build matching your Mac’s chip in Apple menu → About This Mac:

| Chip | Installer | Size |
|---|---|---|
| Apple Silicon (M series) | [FeatherSweep-1.2.0-arm64.dmg](https://github.com/zimuoo/FeatherSweep/releases/download/v1.2.0/FeatherSweep-1.2.0-arm64.dmg) | ~2.4 MB |
| Intel | [FeatherSweep-1.2.0-x86_64.dmg](https://github.com/zimuoo/FeatherSweep/releases/download/v1.2.0/FeatherSweep-1.2.0-x86_64.dmg) | ~2.4 MB |

Open the DMG and drag **轻扫.app** into **Applications**. Both installers provide the same app features.

Requires an Apple Silicon or Intel Mac running macOS 14 or newer. The current build is locally ad hoc signed, **not Apple notarized**. Use only this repository's release assets. FeatherSweep does not ask you to disable Gatekeeper.

If macOS asks to verify the source, compare the checksum and follow [Apple’s instructions](https://support.apple.com/guide/mac-help/mh40616/mac) in System Settings → Privacy & Security.

```sh
# If you downloaded only the Intel installer, compare this hash with its entry in SHA256SUMS:
shasum -a 256 FeatherSweep-1.2.0-x86_64.dmg
# If both installers are present:
shasum -a 256 -c SHA256SUMS
```

## Automatic GitHub updates

Starting with **1.2.0**, automatic updates are enabled by default. FeatherSweep checks at launch and every **6 hours**, downloads the native package for its architecture, verifies its Ed25519 signature, then waits for scanning or cleanup to finish before installing and restarting.

Use **检查更新…** (Check for Updates) or toggle **自动下载安装更新** (Automatically Download and Install Updates) in the menu bar. Preferences persist. The feed and archive are signed; failed validation prevents installation. The private release key remains in the publisher’s login Keychain. System profiling is disabled.

**Versions 1.1.0 and earlier need one manual upgrade to 1.2.0.** Later signed releases published through this repository’s release workflow are discovered automatically. Run the app from Applications, not a read-only disk image. macOS may request administrator authorization when needed. Demo, screenshot and read-only scan modes do not start update checks.

## Carefully defined cleanup scope

| Category | Scope | Preserved |
|---|---|---|
| Compilation | Recognized Go caches and designated Rust intermediates | Source, fuzz corpora and runnable binaries |
| AI tools | Recognized client HTTP/code/GPU caches, expired Claude/Codex snapshots and Cursor snapshots/search index | Accounts, settings, skills, plugins, chat DBs, models, recent restore points and worktrees |
| Packaging | Recognized staging copies and SHA-256-identical extra packages; idle browser signing clones | Formal releases, validation records, active/newest clones |
| Updates | Obsolete Cursor and redundant/outdated Telegram downloads | Installed apps and newest pending download |
| Static web cache | Recognized Feishu/Cloudflare static assets in Chrome | Passwords, cookies, sessions, IndexedDB and Local Storage |
| Daily caches | Recognized browser HTTP/code/GPU caches, approved thumbnail/help caches and user diagnostics older than 7 days | Browser credentials and sessions, recent diagnostics, Downloads and Trash |
| Blender | Recognized Agent Bridge checkpoints | **Latest modified backup for each scene** |

Rules derive from manually verified folders. Some project-specific rules refer to `Desktop/docker/yijun_project` under the current home; absent paths are skipped. The app does not empty Downloads, delete all DMGs, remove model/SDK installations, or wipe browser profiles.

## Choose what to remove

Nothing is selected automatically. Check categories or expand them to select individual paths. Each item explains its practical impact; the selected count and bytes are visible. The menu-bar action uses the same selection. Rescanning clears selections, and unselected paths never enter the cleanup task.

- Rebuildable caches: the next launch, page load or build may take longer and resources may download again.
- Old checkpoints: fewer historical undo/restore points remain. Recent/latest backup retention still applies.
- Old diagnostics: those past troubleshooting records are lost; regular operation is unaffected.
- Verified package copies or obsolete updates: you may need to rebuild or download them again.

The catalog recognizes cache layouts for Claude, Codex, ChatGPT, Doubao, Qianwen/Qwen, Cursor, Trae, Windsurf, Gemini, Cherry Studio, Ollama and LM Studio. Installed bundle metadata helps identify actual local aliases. Unknown layouts and inaccessible folders are skipped. Local models and runtimes are preserved. This release does not purge AI conversation databases. Claude file-history groups require every descendant to be older than 30 days, retaining the most recently changed group. Claude shell snapshots require 7 days and retain the latest snapshot; Codex shell snapshots use the same cutoff and retain the latest per session. Unidentified Node/Bun processes conservatively protect CLI snapshots and metadata caches, with an explanation.

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
# On a logged-in Mac desktop: enable the 6 native WindowServer integration tests
FEATHERSWEEP_NATIVE_UI_TESTS=1 swift test --disable-sandbox --scratch-path /private/tmp/feathersweep-test-build
# Defaults to the host architecture:
bash scripts/build.sh
# Explicit targets; Apple Silicon hosts can cross-compile the Intel build:
bash scripts/build.sh arm64
bash scripts/build.sh x86_64
```

The build uses system Swift, AppKit, iconutil, codesign and hdiutil, downloads and verifies the pinned Sparkle dependency/SDK on first build, and removes its private per-run build directory. The icon renderer targets the host, the app targets the requested architecture, and the actual Mach-O architecture is verified before packaging. Output: `dist/FeatherSweep-1.2.0-{arm64|x86_64}.dmg`.

To build both signed update feeds and installers, run `bash scripts/release-updates.sh`. See [Release instructions](scripts/RELEASING.md) and [Third-party notices](THIRD_PARTY_NOTICES.md). Project source is publicly available; no project license has been added.

```sh
# Safe example UI: no real cleanup
"/Applications/轻扫.app/Contents/MacOS/FeatherSweep" --demo

# Real read-only scan, JSON to stdout
"/Applications/轻扫.app/Contents/MacOS/FeatherSweep" --scan-json
```

All 82 tests passed locally with no skips, including the native selection and menu-bar checks. The default command explicitly skips the 6 WindowServer tests; the environment variable above enables them. Safety tests use disposable fixtures. They cover credential/source retention, symlinks, changed files, active files and mid-clean opens, Cargo locks, Blender naming edges, clone retention, duplicate references, static-resource parsing and partial cleanup accounting. The Intel release is cross-compiled on Apple Silicon and its launch and native UI are checked under Rosetta 2. It has not been tested on physical Intel hardware.
