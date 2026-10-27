import AppKit
import CleanerCore
import SwiftUI
import XCTest
@testable import FeatherSweep

/// Opt-in: uses only this test process's native window and synthetic demo data.
final class NativeComponentTests: XCTestCase {
    @MainActor
    func testTrayUsesSelectionAndCloseReopenPreservesMenuBar() async throws {
        try requireNativeTests()
        let application = NSApplication.shared
        _ = application.setActivationPolicy(.regular)
        let delegate = CleanerAppDelegate(options: try LaunchOptions(arguments: ["--demo"]))
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            delegate.window.orderOut(nil)
            NSStatusBar.system.removeStatusItem(delegate.statusItem)
        }
        let menu = try XCTUnwrap(delegate.statusItem.menu)
        let clean = try XCTUnwrap(menu.items.first { $0.action == NSSelectorFromString("clean") })
        XCTAssertFalse(delegate.validateMenuItem(clean))
        XCTAssertFalse(clean.isEnabled)
        XCTAssertEqual(clean.title, "清理垃圾（请先勾选）")
        let candidate = try XCTUnwrap(delegate.model.report?.candidates.first)
        delegate.model.setSelected(true, for: candidate.id)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(delegate.validateMenuItem(clean))
        XCTAssertTrue(clean.isEnabled)
        XCTAssertEqual(clean.title, "清理已选 1 项")
        XCTAssertTrue(delegate.statusItem.button?.toolTip?.contains(delegate.model.selectionSummary) == true)
        XCTAssertFalse(delegate.windowShouldClose(delegate.window))
        XCTAssertEqual(application.activationPolicy(), .accessory)
        XCTAssertFalse(delegate.window.isVisible)
        XCTAssertNotNil(delegate.statusItem.menu)
        XCTAssertTrue(delegate.validateMenuItem(clean))
        XCTAssertTrue(delegate.applicationShouldHandleReopen(application, hasVisibleWindows: false))
        XCTAssertEqual(application.activationPolicy(), .regular)
        XCTAssertTrue(delegate.window.isVisible)
        // Reopening an ordinary, non-miniaturized window must remain safe.
        XCTAssertFalse(delegate.window.isMiniaturized)
        XCTAssertTrue(delegate.applicationShouldHandleReopen(application, hasVisibleWindows: true))
        delegate.window.miniaturize(nil)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(delegate.window.isMiniaturized)
        XCTAssertTrue(delegate.applicationShouldHandleReopen(application, hasVisibleWindows: false))
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(delegate.window.isMiniaturized)
        XCTAssertTrue(application.sendAction(try XCTUnwrap(clean.action), to: clean.target, from: clean))
        XCTAssertEqual(delegate.model.phase, .cleaning)
        XCTAssertFalse(delegate.validateMenuItem(clean))
        let deadline = Date().addingTimeInterval(5)
        while delegate.model.phase != .completed, Date() < deadline {
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTAssertEqual(delegate.model.phase, .completed)
        XCTAssertEqual(delegate.model.result?.removedCount, 1)
        XCTAssertEqual(delegate.model.result?.removedBytes, candidate.estimatedBytes)
        XCTAssertFalse(delegate.validateMenuItem(clean))
        XCTAssertTrue(application.sendAction(try XCTUnwrap(clean.action), to: clean.target, from: clean))
        XCTAssertEqual(delegate.model.phase, .completed)
        XCTAssertEqual(delegate.model.result?.removedCount, 1)
    }

    @MainActor
    func testEmptyCategoriesRenderUncheckedAndDisabled() async throws {
        try requireNativeTests()
        let model = CleanerViewModel(isDemo: false)
        let view = NSHostingView(rootView: CleanerView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 592),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = view
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(600))
        view.layoutSubtreeIfNeeded()
        // In the idle root view the seven category checkboxes are its only disabled NSButtons.
        let checkboxes = nativeButtons(in: view).filter { !$0.isEnabled }
        XCTAssertEqual(checkboxes.count, CleanupCategory.allCases.count)
        for checkbox in checkboxes {
            XCTAssertEqual(checkbox.state, .off, "An empty category must not look selected")
            XCTAssertFalse(checkbox.isEnabled)
        }
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: "/private/tmp/feathersweep-1.1-idle.png"), options: .atomic)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(model.selectedIDs.isEmpty)
        XCTAssertFalse(model.canSelect)
        XCTAssertFalse(model.canClean)
    }

    @MainActor
    func testMixedCategoryCheckboxAndSyntheticSelectionPreview() async throws {
        try requireNativeTests()
        let path = ProcessInfo.processInfo.environment["FEATHERSWEEP_DETAIL_PREVIEW"] ?? "/private/tmp/feathersweep-1.1-details.png"
        let model = CleanerViewModel(isDemo: true)
        let history = try XCTUnwrap(model.candidates(for: .cursor).first { $0.kind == .claudeFileHistory })
        model.setSelected(true, for: history.id)
        let view = NSHostingView(rootView: CleanerView(model: model, initiallyExpandedCategories: [.cursor]))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 592),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = view
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(600))
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        XCTAssertEqual(model.selectedCount, 1)
        XCTAssertEqual(model.selectedCount(for: .cursor), 1)
        XCTAssertTrue(model.canClean)
        XCTAssertEqual(view.bounds.size, NSSize(width: 460, height: 592))
        let mixedCategory = try XCTUnwrap(nativeButtons(in: view).first { $0.state == .mixed })
        XCTAssertTrue(mixedCategory.isEnabled)
        model.setSelected(true, for: CleanupCategory.cursor)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(mixedCategory.state, .on)
        model.setSelected(false, for: CleanupCategory.cursor)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(mixedCategory.state, .off)
        XCTAssertTrue(model.selectedIDs.isEmpty)
        XCTAssertFalse(model.canClean)
    }

    @MainActor
    private func nativeButtons(in parent: NSView) -> [NSButton] {
        parent.subviews.flatMap { child in
            (child as? NSButton).map { [$0] } ?? nativeButtons(in: child)
        }
    }

    private func requireNativeTests() throws {
        guard ProcessInfo.processInfo.environment["FEATHERSWEEP_NATIVE_UI_TESTS"] == "1" else {
            throw XCTSkip("Set FEATHERSWEEP_NATIVE_UI_TESTS=1 with WindowServer access for the native component checks")
        }
    }
}
