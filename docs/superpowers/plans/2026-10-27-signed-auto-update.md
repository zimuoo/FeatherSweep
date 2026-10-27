# FeatherSweep Signed Auto-update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Continue without extra user approval: the user explicitly requested Intel packaging and automatic GitHub download/installation.

**Goal:** Publish FeatherSweep 1.2.0 for Intel and Apple Silicon with signed automatic GitHub updates that never interrupt cleanup.

**Architecture:** Use the fixed Sparkle 2.10.1 native updater with two architecture-specific signed release feeds. A small main-actor installation gate defers Sparkle's install and relaunch callbacks while CleanerViewModel is busy; Sparkle owns networking, signature checks and application replacement.

**Tech Stack:** Swift 5.10 language / macOS 14+, AppKit / Combine / Sparkle 2.10.1, SwiftPM, Bash, Python release tooling.

---

### Task 1: Native update controller and behavior tests

Files: create `Sources/FeatherSweep/AppUpdater.swift`, `Tests/FeatherSweepTests/AppUpdaterTests.swift`; modify `Package.swift` to depend exactly on `https://github.com/sparkle-project/Sparkle` version `2.10.1` and link product `Sparkle` to FeatherSweep.

- [ ] Add failing tests using disposable UserDefaults and real callback counters for the installation gate: busy pending callback stays unexecuted; idle drains it exactly once; disabling automatic updates prevents automatic restart; manual relaunch remains deferred until idle. Test accepted feed/asset URL policy and demo/development activation policy.
- [ ] Run focused tests with `swift test --disable-sandbox --scratch-path /private/tmp/feathersweep-update-tests --filter AppUpdaterTests`, confirm new behavior fails before implementation.
- [ ] Implement `@MainActor final class AppUpdater: NSObject, SPUUpdaterDelegate` initialized with CleanerViewModel and isDemo; retain standard updater controller. Expose `start()`, `checkForUpdates()`, `toggleAutomaticUpdates()`, `automaticUpdatesEnabled`, `canCheckForUpdates`. Respect persisted Sparkle preferences. Only initialize/start in a real app bundle with expected identity and valid production HTTPS feed/public key; demo and non-app remain disabled.
- [ ] Hook `willInstallUpdateOnQuit:immediateInstallationBlock:` and `shouldPostponeRelaunchForUpdate:untilInvokingBlock:`. Schedule automatic handler only after delegate returns; defer while busy and resume on model phase changes. Do not create a custom installer or restart helper.
- [ ] Reject update item download URLs outside `https://github.com/zimuoo/FeatherSweep/releases/download/`; do not fetch remote release-note HTML or system profiles. Run tests to green; report evidence and exact interface to parent.

### Task 2: Menu integration

Files: modify `Sources/FeatherSweep/FeatherSweepMain.swift`, native integration tests.

- [ ] Retain AppUpdater in app delegate; start only on actual app launch and never in demo or scan CLI. Add application/menu-bar check action and automatic download/install toggle. Derive menu availability and state from updater in `validateMenuItem`.
- [ ] Add meaningful native tests that demo update actions are disabled, existing menu/selection remains valid, and automatic toggle persists with injected test preferences. Keep window content size unchanged.
- [ ] Use dynamic bundle version in About panel. Run native test suite with `FEATHERSWEEP_NATIVE_UI_TESTS=1` on arm64 and x86_64 (run Swift/xctest under Rosetta for x86_64).

### Task 3: Dual architecture packaging and release signing

Files: modify `scripts/build.sh`, create release and Sparkle-tool scripts; add public signing key resource and third-party notices.

- [ ] Set app version 1.2.0/build 3. Preserve validated `[arm64|x86_64]` build selection and actual Mach-O check. Locate SwiftPM Sparkle framework, copy with preserved symlinks into Contents/Frameworks, add loader rpath, sign outer bundle after embedding. Keep the complete official framework unless official documentation supports removing optional XPC services.
- [ ] Set `SUFeedURL` to latest-release appcast for target architecture, `SUPublicEDKey` to saved public key, `SUEnableAutomaticChecks=true`, `SUAutomaticallyUpdate=true`, `SUScheduledCheckInterval=21600`, `SUSendProfileInfo=false`, `SUVerifyUpdateBeforeExtraction=true`, `SURequireSignedFeed=true`. Do not enable hardened runtime/library validation for the current ad hoc signing distribution.
- [ ] Use official generate_keys tool with a FeatherSweep-specific Keychain account. Never print/export/store the private key. Public key only is tracked.
- [ ] Generate and verify both signed appcasts using official tooling after both DMGs exist. Each feed contains only the correct architecture; release metadata and checksums match both actual files. Provide one reproducible local release command and docs for future releases.
- [ ] Build both architectures; verify hdiutil, codesign, rpath and framework loader, Info.plist, demo launch and signature tamper rejection; exercise installation with disposable app copies.

### Task 4: Review, documentation and publication

Files: `README.md`, `README.en.md`, `CHANGELOG.md`, release notes and release validation document.

- [ ] Update installer links, actual sizes, updater behavior/default/disable control, automatic network use, initial manual upgrade from 1.1.0, system requirements and honest Rosetta-only Intel verification. Keep private keys and unrelated promo files uncommitted.
- [ ] Independent spec review, then quality/security review. Fix blocking findings and rerun affected checks.
- [ ] Run `git diff --check`, confirm only authorized files staged; commit, push to existing public repository, create v1.2.0 with both DMGs, checksums and feeds. Verify public download sizes/hashes and signed feed URLs after publication. Do not modify old release assets or move old tags.
