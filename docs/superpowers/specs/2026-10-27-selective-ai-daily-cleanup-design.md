# Selective AI and daily cleanup — 1.1.0

The user requested mainstream AI tool caches and unnecessary old snapshots, ordinary daily caches, explicit selection after scanning, and a description of each deletion’s impact. Passwords, cookies, website sessions, settings, skills, models, source and active work remain protected. No real user cleanup is performed during development.

## Interaction
Keep the 460 × 592 native window, menu bar and two main buttons. Rename the Cursor row to AI caches and snapshots and add a daily caches row. Start every scan with an empty selection. Each category and candidate has a checkbox, size, path, reason and a plain-language impact. Changes are disabled during work. Cleaning is enabled only for selected candidates from the current scan. The menu bar uses the same selection. A fresh scan clears previous selection; cleanup operates on an immutable filtered report. Preview totals show available and selected amounts separately.

## Rules
Use exact paths inside the current user home. Electron/Chromium AI clients: Claude, Codex, ChatGPT, Doubao, Qianwen/Qwen, Cursor, Trae, Windsurf, Gemini, Cherry Studio, Ollama and LM Studio. A known product alias may expose only explicit HTTP / code / GPU shader caches; additional aliases and bundle IDs come from installed, recognized app Info.plist values. Never delete an entire Application Support or generic Caches root, profiles, Service Workers, cookie/session/credential stores, chat DBs, runtimes, plugins, downloaded models, worktrees or generated artifacts. Skip a tool’s candidates while its processes run. Unknown layouts are skipped rather than guessed.

Claude: old file-history UUID session trees older than 30 days in every descendant, retaining the most recent session; old shell snapshots older than 7 days. Codex: recognized UUID shell snapshot scripts older than 7 days, retaining the latest per session. Known regenerable CLI cache entries only, not the whole dot directory. Every snapshot rule and retained-file condition is reevaluated during cleaning. Old checkpoints reduce rewind history; this impact must be visible.

Daily: exact browser HTTP/code/GPU cache directories for Chrome/Edge/Brave plus Firefox cache2, recognized QuickLook thumbnail cache, help cache and user DiagnosticReports with approved extensions older than 7 days. Preserve browser persistent storage and user Downloads/Trash. Do not traverse arbitrary /private or system data. Skip active browser/cache processes and all changed, unsafe, or inaccessible paths.

## Safety and testing
Reuse descriptor-relative O_NOFOLLOW deletion, metadata fingerprint, fail-closed occupancy, stale scan protection and partial accounting. Selection is filtered by IDs from the current report; arbitrary unknown IDs do nothing. Add real fixture tests for credential/session/model preservation, mainstream/dynamic paths, age/latest snapshot boundaries, activity checks, forged report paths, changed contents and selective cleaning. Add native component checks for empty selection, category and individual toggles, repeat scan reset, busy guards and tray parity. Publish a new version with updated bilingual README, screenshot, checksum and public download verification.

Sources: https://code.claude.com/docs/en/claude-directory ; https://github.com/openai/codex/blob/main/codex-rs/core/src/shell_snapshot.rs ; https://www.electronjs.org/docs/latest/api/session ; installed app metadata inspected read-only.
