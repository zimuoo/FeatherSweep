<div align="center">
  <img src="Resources/AppLogo.png" width="96" alt="FeatherSweep logo" />
  <h1>FeatherSweep · 轻扫</h1>
  <p><strong>A small native window for a carefully scoped Mac cleanup.</strong></p>
  <p>macOS 14+ · Apple Silicon · SwiftUI + AppKit · Menu bar support</p>
  <p><a href="https://github.com/zimuoo/FeatherSweep/releases/latest/download/FeatherSweep-1.1.0-arm64.dmg"><strong>Download DMG</strong></a> · <a href="README.md">简体中文</a></p>
</div>

<p align="center"><img src="docs/images/overview.png" width="460" alt="Native FeatherSweep window with example cleanup data" /><br /><sub>Actual native UI using demo data, not a live disk measurement.</sub></p>

<details><summary><strong>Selection and impact details</strong></summary>
<p align="center"><img src="docs/images/selection.png" width="460" alt="Native mixed checkbox and per-item restore-history impact using demo data" /></p>
</details>

## What it does

**View garbage**, inspect paths and impacts, select the items you want, then **clean garbage**. Every scan starts with nothing selected. Closing the window leaves FeatherSweep available in the menu bar. Scanning rings, numeric transitions, cleanup particles and completion feedback respect Reduce Motion.

The app runs locally, requires no account, and makes no network requests. There is no third-party runtime, privileged helper, launch agent or automatic startup cleanup.

## Install

Download `FeatherSweep-1.1.0-arm64.dmg` from [Releases](https://github.com/zimuoo/FeatherSweep/releases/latest), open it, and drag **轻扫.app** into **Applications**.

Requires an Apple Silicon Mac running macOS 14 or newer. The current build is locally ad hoc signed, **not Apple notarized**. Use only this repository's release assets. FeatherSweep does not ask you to disable Gatekeeper.

If macOS asks to verify the source, compare the checksum and follow [Apple’s instructions](https://support.apple.com/guide/mac-help/mh40616/mac) in System Settings → Privacy & Security.

```sh
shasum -a 256 -c SHA256SUMS.txt
```

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
# On a logged-in Mac desktop: enable the 3 native WindowServer integration tests
FEATHERSWEEP_NATIVE_UI_TESTS=1 swift test --disable-sandbox --scratch-path /private/tmp/feathersweep-test-build
bash scripts/build.sh
```

The build uses system Swift, AppKit, iconutil, codesign and hdiutil, downloads no dependencies, and removes its private per-run build directory. Output: `dist/FeatherSweep-1.1.0-arm64.dmg`.

```sh
# Safe example UI: no real cleanup
"/Applications/轻扫.app/Contents/MacOS/FeatherSweep" --demo

# Real read-only scan, JSON to stdout
"/Applications/轻扫.app/Contents/MacOS/FeatherSweep" --scan-json
```

All 70 tests passed locally with no skips, including the native selection and menu-bar checks. The default command explicitly skips the 3 WindowServer tests; the environment variable above enables them. Safety tests use disposable fixtures. They cover credential/source retention, symlinks, changed files, active files and mid-clean opens, Cargo locks, Blender naming edges, clone retention, duplicate references, static-resource parsing and partial cleanup accounting. An Intel release has not been built or verified.
