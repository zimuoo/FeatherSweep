# FeatherSweep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deliver a compact native Mac cleaner app with the approved UI, original logo, menu bar operation and a verified DMG.

**Architecture:** CleanerCore owns read-only discovery, exact allowlists, filesystem identity checks and guarded deletion. A SwiftUI view model runs the engine off the main thread; AppKit owns the compact window and persistent status item. Packaging uses the system Swift compiler, iconutil, codesign and hdiutil.

**Tech Stack:** Swift 5 language mode on the installed Swift 6 toolchain, SwiftUI, AppKit, Foundation, CryptoKit, Darwin; no downloaded dependencies.

## Task 1 — Contract and safety regression tests

Files: `Sources/CleanerCore/Models.swift`, `Tests/CleanerCoreTests/CleanerCoreTests.swift`.

- [x] Define category, candidate, scan report and cleanup result values.
- [x] Create real fixture homes under the system temp directory.
- [x] Verify a stub scanner fails to discover a valid Go cache before implementing discovery.
- [x] Test source/credential preservation, read-only scanning, unknown cache rejection, per-scene backup retention, changed-file skipping, symlink rejection, duplicate package reference protection, static-resource-only parsing and actual fixture cleanup.

Command: `swift test --package-path . --scratch-path /private/tmp/mac-cleaner-build`.

## Task 2 — Discovery and bounded cleanup

Files: `Configuration.swift`, `FileSystem.swift`, `Rules.swift`, `WebCache.swift`, `CleaningEngine.swift`.

- [x] Discover only explicitly recognized roots and formats; missing paths are normal, unreadable paths become warnings.
- [x] Snapshot metadata/fingerprints without loading file contents except bounded cache headers and package duplicate SHA-256 checks.
- [x] Capture process/open-file state, reject live caches and stale scan reports.
- [x] Delete with no-follow directory descriptors and inode checks; reject all unrecognized paths even for constructed candidates.
- [x] Recompute Blender retention and verify duplicate reference content immediately before mutation.
- [x] Run all fixture tests and perform a real `--scan-json` run without deleting user data.

## Task 3 — Approved UI, icon and menu bar

Files: `Sources/FeatherSweep/FeatherSweepMain.swift`, `CleanerViewModel.swift`, `CleanerView.swift`, `Branding.swift`.

- [x] Implement a 460-point native window and six category rows with expandable details.
- [x] Two main controls: view garbage, clean garbage; disable destructive action before a valid scan or while busy.
- [x] Add scan-ring, numeric transition, restrained particles and completion check; honor reduced motion.
- [x] Keep NSStatusItem alive after closing the window; reopen correctly from the menu.
- [x] Support `--demo` for safe UI verification and `--scan-json` for read-only diagnostics.

## Task 4 — Packaging

Files: `scripts/build.sh`, `scripts/render-icon.swift`, `Resources/AppLogo.svg`, `README.md`.

- [x] Generate a native multi-resolution ICNS and use matching logo geometry in the app.
- [x] Compile a release arm64 executable, assemble the bundle, perform ad hoc signing and build a compressed drag-to-install DMG.
- [x] Keep caches in `/private/tmp/mac-cleaner-build`; final products go to `dist/`.

## Task 5 — Review and delivery

- [x] Separate spec compliance review from safety/code quality review; fix important findings.
- [x] Verify tests, signature, DMG checksum, mounted bundle and real UI/menu bar behavior.
- [x] Capture actual screenshots, measure application and DMG sizes and document any signing limitation.
- [x] Deliver the DMG and source path without changing existing business files or running real cleanup during QA.
