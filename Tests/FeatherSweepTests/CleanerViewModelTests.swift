import CleanerCore
import XCTest
@testable import FeatherSweep

final class CleanerViewModelTests: XCTestCase {
    @MainActor
    func testDemoRequiresExplicitSelectionBeforeCleaning() {
        let model = CleanerViewModel(isDemo: true)
        XCTAssertEqual(model.phase, .scanned)
        XCTAssertTrue(model.selectedIDs.isEmpty)
        XCTAssertEqual(model.selectedCount, 0)
        XCTAssertEqual(model.selectedBytes, 0)
        XCTAssertTrue(model.selectedReport?.candidates.isEmpty == true)
        XCTAssertFalse(model.canClean, "A completed scan must not authorize cleaning before the user selects items")
        model.clean()
        XCTAssertEqual(model.phase, .scanned)
        XCTAssertNil(model.result)
    }

    @MainActor
    func testUnknownIdentifiersAreRejected() throws {
        let model = CleanerViewModel(isDemo: true)
        let candidate = try XCTUnwrap(model.report?.candidates.first)
        model.setSelected(true, for: "/unknown/path")
        model.toggleSelection(for: "/unknown/path")
        XCTAssertTrue(model.selectedIDs.isEmpty)
        model.setSelected(true, for: candidate.id)
        model.setSelected(true, for: "/unknown/path")
        XCTAssertEqual(model.selectedIDs, [candidate.id])
        XCTAssertEqual(model.selectedReport?.candidates.map(\.id), [candidate.id])
    }

    @MainActor
    func testFileAndCategorySelectionShowPartialCounts() throws {
        let model = CleanerViewModel(isDemo: true)
        let aiItems = model.candidates(for: .cursor)
        XCTAssertGreaterThan(aiItems.count, 1, "Demo must illustrate a partially selected category")
        let first = try XCTUnwrap(aiItems.first)
        model.toggleSelection(for: first.id)
        XCTAssertTrue(model.isSelected(first.id))
        XCTAssertEqual(model.selectedCount(for: .cursor), 1)
        XCTAssertFalse(model.isCategorySelected(.cursor))
        XCTAssertEqual(model.selectedBytes, first.estimatedBytes)
        XCTAssertTrue(model.canClean)
        model.toggleSelection(for: .cursor)
        XCTAssertTrue(model.isCategorySelected(.cursor))
        XCTAssertEqual(model.selectedCount(for: .cursor), aiItems.count)
        XCTAssertEqual(model.selectedIDs, Set(aiItems.map(\.id)))
        XCTAssertEqual(model.selectedBytes, aiItems.reduce(0) { $0 + $1.estimatedBytes })
        model.setSelected(false, for: first.id)
        XCTAssertEqual(model.selectedCount(for: .cursor), aiItems.count - 1)
        model.setSelected(false, for: CleanupCategory.cursor)
        XCTAssertTrue(model.selectedIDs.isEmpty)
        XCTAssertFalse(model.canClean)
    }

    @MainActor
    func testDemoCleansOnlySelectedItemsAndIgnoresChangesWhileCleaning() async throws {
        let model = CleanerViewModel(isDemo: true)
        let all = try XCTUnwrap(model.report)
        let selected = try XCTUnwrap(all.candidates.first)
        let other = try XCTUnwrap(all.candidates.last)
        model.setSelected(true, for: selected.id)
        model.clean()
        XCTAssertEqual(model.phase, .cleaning)
        XCTAssertFalse(model.canSelect)
        XCTAssertFalse(model.canClean)
        model.setSelected(false, for: selected.id)
        model.setSelected(true, for: other.id)
        model.setSelected(true, for: other.category)
        model.toggleSelection(for: selected.category)
        model.clean()
        XCTAssertEqual(model.selectedIDs, [selected.id])
        try await wait(for: .completed, in: model)
        let result = try XCTUnwrap(model.result)
        XCTAssertEqual(result.removedCount, 1)
        XCTAssertEqual(result.removedBytes, selected.estimatedBytes)
        XCTAssertEqual(result.availableBytesBefore, all.availableBytes)
        XCTAssertEqual(result.availableBytesAfter, all.availableBytes + selected.estimatedBytes)
        XCTAssertLessThan(result.removedBytes, all.totalBytes)
        XCTAssertEqual(model.report?.candidates.count, all.candidates.count)
        XCTAssertEqual(model.status, "演示完成 · 未修改任何文件")
        XCTAssertFalse(model.canClean)
        model.setSelected(false, for: selected.id)
        model.clean()
        XCTAssertEqual(model.phase, .completed)
        XCTAssertEqual(model.selectedIDs, [selected.id])
        XCTAssertEqual(model.result?.removedCount, 1)
    }

    @MainActor
    func testRescanClearsSelectionAtStartAndFinish() async throws {
        let model = CleanerViewModel(isDemo: true)
        let candidate = try XCTUnwrap(model.report?.candidates.first)
        model.setSelected(true, for: candidate.id)
        model.scan()
        XCTAssertEqual(model.phase, .scanning)
        XCTAssertTrue(model.selectedIDs.isEmpty)
        XCTAssertNil(model.report)
        XCTAssertNil(model.selectedReport)
        XCTAssertFalse(model.canClean)
        model.setSelected(true, for: candidate.id)
        model.setSelected(true, for: candidate.category)
        model.toggleSelection(for: candidate.id)
        model.scan()
        XCTAssertTrue(model.selectedIDs.isEmpty)
        try await wait(for: .scanned, in: model)
        XCTAssertTrue(model.selectedIDs.isEmpty)
        XCTAssertEqual(model.selectedCount, 0)
        XCTAssertFalse(model.canClean)
        model.setSelected(true, for: candidate.id)
        model.clean()
        try await wait(for: .completed, in: model)
        model.scan()
        XCTAssertTrue(model.selectedIDs.isEmpty)
        XCTAssertNil(model.result)
        try await wait(for: .scanned, in: model)
        XCTAssertTrue(model.selectedIDs.isEmpty)
        XCTAssertFalse(model.canClean)
    }

    @MainActor
    func testIdleModelCannotSelectOrClean() {
        let model = CleanerViewModel(isDemo: false)
        model.setSelected(true, for: "/unknown")
        model.setSelected(true, for: CleanupCategory.daily)
        model.clean()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertFalse(model.canSelect)
        XCTAssertFalse(model.canClean)
        XCTAssertTrue(model.selectedIDs.isEmpty)
    }

    @MainActor
    func testCollapsedCategoryImpactPrioritizesIrreversibleHistoryLoss() {
        let model = CleanerViewModel(isDemo: true)
        XCTAssertTrue(model.categoryImpactSummary(for: .cursor).contains("恢复"))
        XCTAssertTrue(model.categoryImpactSummary(for: .daily).contains("诊断"))
        XCTAssertTrue(model.categoryImpactSummary(for: .blender).contains("恢复"))
        XCTAssertTrue(model.candidates(for: .cursor).contains { $0.kind == .aiCache })
        XCTAssertTrue(model.candidates(for: .cursor).contains { $0.kind == .claudeFileHistory })
        XCTAssertTrue(model.candidates(for: .daily).contains { $0.kind == .browserCache })
        XCTAssertTrue(model.candidates(for: .daily).contains { $0.kind == .diagnosticReport })
    }

    @MainActor
    private func wait(for phase: CleanerViewModel.Phase, in model: CleanerViewModel) async throws {
        let deadline = Date().addingTimeInterval(5)
        while model.phase != phase, Date() < deadline {
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTAssertEqual(model.phase, phase)
    }
}
