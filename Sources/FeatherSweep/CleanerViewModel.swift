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
    var canClean: Bool { phase == .scanned && !(report?.candidates.isEmpty ?? true) }
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

    func scan() {
        guard !isBusy else { return }
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
        guard canClean, let report else { return }
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
        ScanReport(candidates: [
            .init(path: "~/Library/Caches/go-build", category: .compilation, kind: .goCache,
                  reason: "可重新生成的 Go 编译缓存（演示）", estimatedBytes: 51_600_000_000, fileCount: 1280),
            .init(path: "~/Library/Application Support/Cursor/User/History/old-snapshot", category: .cursor,
                  kind: .cursorSnapshots, reason: "超过保留期的旧快照（演示）", estimatedBytes: 8_200_000_000, fileCount: 216),
            .init(path: "/private/tmp/mac-cleaner-demo/package-staging", category: .temporary, kind: .stagingCopy,
                  reason: "已核验的打包临时副本（演示）", estimatedBytes: 3_400_000_000, fileCount: 48),
            .init(path: "~/Library/Caches/update-demo/old-download", category: .updates, kind: .obsoleteUpdate,
                  reason: "已由新版本替代的更新下载（演示）", estimatedBytes: 2_600_000_000, fileCount: 3)
        ], availableBytes: 102_400_000_000)
    }
}
