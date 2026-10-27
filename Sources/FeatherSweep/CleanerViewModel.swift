import AppKit
import CleanerCore
import Combine
import Foundation

@MainActor
final class CleanerViewModel: ObservableObject {
    enum Phase: Equatable { case idle, scanning, scanned, cleaning, completed, failed }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var report: ScanReport?
    @Published private(set) var result: CleanupResult?
    @Published private(set) var selectedIDs: Set<String> = []
    @Published private(set) var progress = 0.0
    @Published private(set) var status = "查看可安全清理的文件"
    @Published private(set) var errorMessage: String?
    let isDemo: Bool
    private let worker = DispatchQueue(label: "app.mac-cleaner.operations", qos: .utility)

    init(isDemo: Bool) {
        self.isDemo = isDemo
        if isDemo {
            report = Self.exampleReport()
            phase = .scanned
            status = "扫描完成 · 示例数据"
        }
    }

    var isBusy: Bool { phase == .scanning || phase == .cleaning }
    var canSelect: Bool { phase == .scanned }
    var selectedReport: ScanReport? { report?.selecting(selectedIDs) }
    var selectedCount: Int { selectedReport?.candidates.count ?? 0 }
    var selectedBytes: Int64 { selectedReport?.totalBytes ?? 0 }
    var selectionSummary: String { "已选 \(selectedCount) 项 · \(Self.bytes(selectedBytes))" }
    var canClean: Bool { canSelect && selectedCount > 0 }
    var displayedBytes: Int64 { result?.removedBytes ?? report?.totalBytes ?? 0 }
    var summaryTitle: String { result == nil ? "可清理空间" : "已移除文件" }
    var categoryCaption: String { result == nil ? "清理项目" : "本次扫描项目" }
    var summaryAmount: (number: String, unit: String) {
        guard report != nil || result != nil else { return ("—", "GB") }
        return Self.amount(displayedBytes)
    }
    var details: [(title: String, messages: [String])] {
        var groups: [(String, [String])] = []
        if let warnings = report?.warnings, !warnings.isEmpty { groups.append(("扫描提示", warnings)) }
        if let result {
            if !result.skipped.isEmpty { groups.append(("已跳过", result.skipped)) }
            if !result.failed.isEmpty { groups.append(("未能清理", result.failed)) }
        }
        if let errorMessage { groups.append(("操作未完成", [errorMessage])) }
        return groups
    }
    var completionDescription: String? {
        guard let result else { return nil }
        let partial = result.partialCount > 0 ? " · 部分清理 \(result.partialCount) 项" : ""
        return "完整清理 \(result.removedCount) 项\(partial) · 文件大小 \(Self.bytes(result.removedBytes))\n磁盘可用空间增加 \(Self.bytes(result.freedBytes))"
    }

    func candidates(for category: CleanupCategory) -> [CleanupCandidate] {
        report?.candidates.filter { $0.category == category } ?? []
    }

    func isSelected(_ id: String) -> Bool { selectedIDs.contains(id) }

    func setSelected(_ selected: Bool, for id: String) {
        guard canSelect, report?.candidates.contains(where: { $0.id == id }) == true else { return }
        if selected { selectedIDs.insert(id) } else { selectedIDs.remove(id) }
    }

    func toggleSelection(for id: String) { setSelected(!isSelected(id), for: id) }

    func selectedCount(for category: CleanupCategory) -> Int {
        candidates(for: category).filter { isSelected($0.id) }.count
    }

    func isCategorySelected(_ category: CleanupCategory) -> Bool {
        let items = candidates(for: category)
        return !items.isEmpty && items.allSatisfy { isSelected($0.id) }
    }

    func setSelected(_ selected: Bool, for category: CleanupCategory) {
        guard canSelect else { return }
        let ids = Set(candidates(for: category).map(\.id))
        if selected { selectedIDs.formUnion(ids) } else { selectedIDs.subtract(ids) }
    }

    func toggleSelection(for category: CleanupCategory) {
        setSelected(!isCategorySelected(category), for: category)
    }

    func categoryImpactSummary(for category: CleanupCategory) -> String {
        let items = candidates(for: category)
        // Show irreversible losses before rebuildable-cache effects, even when collapsed.
        if items.contains(where: { $0.kind == .cursorSnapshots || $0.kind == .claudeFileHistory }) {
            return items.contains(where: { $0.kind == .claudeShellSnapshot || $0.kind == .codexShellSnapshot })
                ? "旧代码与终端快照无法恢复；缓存会重建" : "旧代码历史删除后无法恢复；缓存会重建"
        }
        if items.contains(where: { $0.kind == .claudeShellSnapshot || $0.kind == .codexShellSnapshot }) {
            return "旧终端环境快照删除后无法恢复"
        }
        if items.contains(where: { $0.kind == .blenderBackup }) {
            return "旧备份无法恢复；每个场景保留最新 1 份"
        }
        if items.contains(where: { $0.kind == .diagnosticReport }) {
            return "旧诊断报告将删除；缓存会重建"
        }
        return items.first?.impactTitle ?? (report == nil ? "扫描后查看影响与路径" : "暂无可清理项目")
    }

    func scan() {
        guard !isBusy else { return }
        selectedIDs.removeAll()
        phase = .scanning
        report = nil
        result = nil
        errorMessage = nil
        progress = 0
        status = "正在查看垃圾…"
        if isDemo {
            simulate { [weak self] in
                guard let self else { return }
                self.finishScan(Self.exampleReport())
            }
            return
        }
        worker.async { [weak self] in
            do {
                let report = try CleaningEngine().scan { fraction, message in
                    DispatchQueue.main.async { self?.updateProgress(fraction, message) }
                }
                DispatchQueue.main.async { self?.finishScan(report) }
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async { self?.finishWithError(message) }
            }
        }
    }

    func clean() {
        guard canClean, let report = selectedReport else { return }
        phase = .cleaning
        progress = 0
        errorMessage = nil
        status = "正在重新核验并清理…"
        if isDemo {
            simulate { [weak self] in
                self?.finishClean(CleanupResult(removedBytes: report.totalBytes,
                                               availableBytesBefore: report.availableBytes,
                                               availableBytesAfter: report.availableBytes + report.totalBytes,
                                               removedCount: report.candidates.count))
            }
            return
        }
        worker.async { [weak self] in
            do {
                let result = try CleaningEngine().clean(report) { fraction, message in
                    DispatchQueue.main.async { self?.updateProgress(fraction, message) }
                }
                DispatchQueue.main.async { self?.finishClean(result) }
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async { self?.finishWithError(message) }
            }
        }
    }

    private func simulate(completion: @escaping @MainActor () -> Void) {
        for step in 1...12 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.10) { [weak self] in
                guard let self else { return }
                self.progress = Double(step) / 12
                self.status = self.phase == .cleaning ? "演示清理中… \(step * 100 / 12)%" : "演示扫描中… \(step * 100 / 12)%"
                if step == 12 { completion() }
            }
        }
    }

    private func updateProgress(_ fraction: Double, _ message: String) {
        progress = min(1, max(0, fraction.isFinite ? fraction : 0))
        status = message
    }

    private func finishScan(_ report: ScanReport) {
        selectedIDs.removeAll()
        self.report = report
        progress = 1
        phase = .scanned
        status = report.candidates.isEmpty ? "扫描完成 · 暂无可清理项目" : "扫描完成"
        if isDemo { status += " · 示例数据" }
    }

    private func finishClean(_ result: CleanupResult) {
        self.result = result
        progress = 1
        phase = .completed
        status = result.failed.isEmpty && result.skipped.isEmpty ? "清理完成" : "清理完成 · 部分项目已保留"
        if isDemo { status = "演示完成 · 未修改任何文件" }
    }

    private func finishWithError(_ message: String) {
        errorMessage = message
        phase = .failed
        status = "操作未完成 · 请查看详情"
    }

    static func amount(_ bytes: Int64) -> (number: String, unit: String) {
        let value = max(0, Double(bytes))
        if value >= 1_000_000_000 { return (String(format: "%.1f", value / 1_000_000_000), "GB") }
        if value >= 1_000_000 { return (String(format: "%.1f", value / 1_000_000), "MB") }
        if value >= 1_000 { return (String(format: "%.1f", value / 1_000), "KB") }
        return (String(Int64(value)), "B")
    }

    static func bytes(_ value: Int64) -> String {
        let amount = amount(value)
        return "\(amount.number) \(amount.unit)"
    }

    private static func exampleReport() -> ScanReport {
        let newestHistory = "~/.claude/file-history/22222222-2222-4222-8222-222222222222"
        let newestShell = "~/.codex/shell_snapshots/demo-session-newest.sh"
        let newestScene = "~/Demo/Scenes/scene.blend1"
        return ScanReport(candidates: [
            .init(path: "~/Library/Caches/go-build", category: .compilation, kind: .goCache,
                  reason: "可重新生成的 Go 编译缓存（示例）", estimatedBytes: 51_600_000_000, fileCount: 1280),
            .init(path: "~/.claude/file-history/11111111-1111-4111-8111-111111111111", category: .cursor,
                  kind: .claudeFileHistory, reason: "超过 30 天的旧文件历史组（示例）", estimatedBytes: 180_000_000, fileCount: 36,
                  retainedPath: newestHistory),
            .init(path: "~/Library/Application Support/Codex/Cache", category: .cursor,
                  kind: .aiCache, reason: "可重新下载的 AI 应用资源缓存（示例）", estimatedBytes: 720_000_000, fileCount: 216),
            .init(path: "~/.codex/shell_snapshots/demo-session-old.sh", category: .cursor,
                  kind: .codexShellSnapshot, reason: "超过 7 天的旧终端快照（示例）", estimatedBytes: 8_000_000, fileCount: 1,
                  retainedPath: newestShell),
            .init(path: "/private/tmp/mac-cleaner-demo/package-staging", category: .temporary, kind: .stagingCopy,
                  reason: "已核验的打包临时副本（示例）", estimatedBytes: 3_400_000_000, fileCount: 48),
            .init(path: "~/Library/Caches/update-demo/old-download", category: .updates, kind: .obsoleteUpdate,
                  reason: "已由新版本替代的更新下载（示例）", estimatedBytes: 2_600_000_000, fileCount: 3),
            .init(path: "~/Library/Caches/demo-static-resource", category: .webCache, kind: .staticWebEntry,
                  reason: "已验证的静态资源缓存（示例）", estimatedBytes: 160_000_000, fileCount: 20),
            .init(path: "~/Demo/Scenes/scene.blend2", category: .blender, kind: .blenderBackup,
                  reason: "同场景有较新的备份（示例）", estimatedBytes: 1_200_000_000, fileCount: 1,
                  retainedPath: newestScene),
            .init(path: "~/Library/Caches/com.google.Chrome/Default/Cache/Cache_Data", category: .daily,
                  kind: .browserCache, reason: "超过保留期的浏览器资源缓存（示例）", estimatedBytes: 680_000_000, fileCount: 162),
            .init(path: "~/Library/Logs/DiagnosticReports/DemoApp-old.ips", category: .daily,
                  kind: .diagnosticReport, reason: "超过 7 天的旧诊断报告（示例）", estimatedBytes: 14_000_000, fileCount: 1)
        ], availableBytes: 102_400_000_000, retainedBackups: [newestHistory, newestShell, newestScene])
    }
}
