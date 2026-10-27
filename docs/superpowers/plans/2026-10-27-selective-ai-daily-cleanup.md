# Selective AI and Daily Cleanup Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development and test-driven-development. Complete the requested implementation and publication without further permission gates; source and public releases are already authorized by the user.

**Goal:** Add verified AI/daily cache rules, impact descriptions and explicit user selection, then publish 1.1.0.

**Architecture:** Extend CleanerCore with focused AI and Daily rules files, computed kind-specific impacts and a report selection function. Keep native UI/model behavior in FeatherSweep. Preserve all existing filesystem and occupation protections.

**Tech Stack:** Swift 5.10+, SwiftUI, AppKit, XCTest, native DMG tools.

## Task 1 — Core rules and selection
Files: Sources/CleanerCore/Models.swift, AI tool rules in a new AIToolRules.swift, DailyRules.swift, Rules.swift, CleaningEngine.swift and FileSystem.swift. New fixture tests in Tests/CleanerCoreTests.
- [x] Add failing fixtures: known AI cache candidates and dynamic installed Doubao/Qianwen aliases; preserved credentials, sessions, models and source; snapshot age/latest retention; daily exact cache paths and log age; occupied/forged/changed paths; selecting only requested candidate IDs.
- [x] Run `swift test --scratch-path /private/tmp/feathersweep-test-build` and confirm behavior failures before implementation.
- [x] Add `.daily` category; change cursor category display title to AI caches and snapshots. Keep existing `.cursor` case for compatibility. Add explicit AI/daily candidate kinds. Expose computed `impactTitle: String` and `impactDetail: String` on CleanupCandidate. Add `ScanReport.selecting(_ ids: Set<String>) -> ScanReport` by filtering candidates while preserving timestamp, warnings, space and retained backups.
- [x] Implement exact catalog paths and dynamic safe app aliases, process guards, snapshot age/latest revalidation and user diagnostic age checks. Call scans with progress between current rules. Reuse existing add/snapshot/delete checks.
- [x] Run full tests, self-review; get spec review followed by quality review and repair all important issues.

## Task 2 — Native selection UI
Files: Sources/FeatherSweep/CleanerView.swift, CleanerViewModel.swift, FeatherSweepMain.swift.
- [x] Add `@Published private(set) var selectedIDs = Set<String>()`; `selectedReport` calls `report.selecting(selectedIDs)`; `setSelected(_:for:)` and category toggle accept IDs only during `.scanned`.
- [x] `canClean` requires nonempty selected candidates. `scan()` and `finishScan()` reset selection. `clean()` captures only selectedReport; demo uses its totals. Tray cleaning uses the same method.
- [x] Add category and file checkboxes, selected count and amount, visible impact title/detail in each expanded candidate. Keep native window size, animation and busy guards. Add daily icon and AI label. Update demo examples for selection and new categories.
- [x] Compile and run native component assertions: no initial selection, unknown IDs rejected, per-file and category toggles, only selected demo totals, busy mutation blocked, scan reset, tray enabled state mirrors selection. Capture/inspect demo screenshot.
- [x] Get spec review followed by quality review, repair, run full tests and release build.

## Task 3 — Release
Files: bilingual READMEs, changelog, screenshot, verification JSON, scripts/build.sh and native About version.
- [x] Document actual supported patterns and impacts, default empty selection, model/auth/history preservation, version/size/download links and architecture/signing limits.
- [x] Build 1.1.0 DMG, verify codesign + hdiutil + read-only mount + checksum. Run only read-only scan on the real Mac.
- [x] Review staged paths and secrets, commit, fast-forward main and push. Publish v1.1.0 with DMG and SHA256SUMS. Verify remote commit, public assets and downloaded byte hashes.
