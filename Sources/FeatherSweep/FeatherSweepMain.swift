import AppKit
import CleanerCore
import Combine
import Darwin
import SwiftUI

@main
struct FeatherSweepApplication {
    @MainActor
    static func main() {
        do {
            let options = try LaunchOptions(arguments: Array(CommandLine.arguments.dropFirst()))
            if options.showHelp {
                print("FeatherSweep [--demo] [--capture-preview /absolute/path.png]\nFeatherSweep --scan-json\n扫描仅输出 JSON，不会清理文件。--demo 只使用示例数据。")
                return
            }
            if options.scanJSON {
                // This diagnostic entry point does not create NSApplication or call clean.
                let report = try CleaningEngine().scan()
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                encoder.dateEncodingStrategy = .iso8601
                FileHandle.standardOutput.write(try encoder.encode(report))
                FileHandle.standardOutput.write(Data("\n".utf8))
                return
            }
            let application = NSApplication.shared
            application.setActivationPolicy(.regular)
            let delegate = CleanerAppDelegate(options: options)
            application.delegate = delegate
            withExtendedLifetime(delegate) { application.run() }
        } catch {
            FileHandle.standardError.write(Data("FeatherSweep: \(error.localizedDescription)\n".utf8))
            Darwin.exit(1)
        }
    }
}

private struct LaunchOptions {
    var isDemo = false
    var scanJSON = false
    var showHelp = false
    var capturePath: String?

    init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--demo": isDemo = true
            case "--scan-json": scanJSON = true
            case "--help", "-h": showHelp = true
            case "--capture-preview":
                index += 1
                guard index < arguments.count, arguments[index].hasPrefix("/") else {
                    throw LaunchError("--capture-preview 需要绝对 PNG 路径")
                }
                capturePath = arguments[index]
            case let value where value.hasPrefix("-psn_"): break
            default: throw LaunchError("无法识别的参数：\(arguments[index])")
            }
            index += 1
        }
        if capturePath != nil && !isDemo { throw LaunchError("--capture-preview 仅可与 --demo 一起使用") }
        if scanJSON && (isDemo || capturePath != nil) { throw LaunchError("--scan-json 不可与演示参数一起使用") }
    }
}

private struct LaunchError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@MainActor
private final class CleanerAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    private let options: LaunchOptions
    private let model: CleanerViewModel
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var scanItem: NSMenuItem!
    private var cleanItem: NSMenuItem!
    private var statusTextItem: NSMenuItem!
    private var observation: AnyCancellable?

    init(options: LaunchOptions) {
        self.options = options
        model = CleanerViewModel(isDemo: options.isDemo)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .aqua)
        NSApp.applicationIconImage = Branding.image(size: 512)
        installApplicationMenu()
        installStatusItem()
        let view = NSHostingView(rootView: CleanerView(model: model))
        view.setAccessibilityLabel("轻扫主窗口")
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 592),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "轻扫"
        window.contentView = view
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.backgroundColor = .white
        window.center()
        observation = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshMenu() }
        }
        refreshMenu()
        showWindow()
        if let capturePath = options.capturePath {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.capturePreview(path: capturePath)
            }
        }
    }

    private func installApplicationMenu() {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        menu.addItem(applicationItem)
        let applicationMenu = NSMenu(title: "轻扫")
        applicationMenu.addItem(withTitle: "关于 轻扫", action: #selector(showAbout), keyEquivalent: "")
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "隐藏 轻扫", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "退出 轻扫", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        let editItem = NSMenuItem()
        menu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        NSApp.mainMenu = menu
    }

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Branding.image(size: 20, template: true)
        statusItem.button?.setAccessibilityLabel("轻扫菜单栏")
        let menu = NSMenu()
        let open = NSMenuItem(title: "打开 轻扫", action: #selector(showWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        statusTextItem = NSMenuItem(title: model.status, action: nil, keyEquivalent: "")
        menu.addItem(statusTextItem)
        menu.addItem(.separator())
        scanItem = NSMenuItem(title: "查看垃圾", action: #selector(scan), keyEquivalent: "")
        scanItem.target = self
        menu.addItem(scanItem)
        cleanItem = NSMenuItem(title: "清理垃圾", action: #selector(clean), keyEquivalent: "")
        cleanItem.target = self
        menu.addItem(cleanItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 轻扫", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func refreshMenu() {
        statusTextItem?.title = model.status
        scanItem?.isEnabled = !model.isBusy
        cleanItem?.isEnabled = model.canClean
        statusItem?.button?.toolTip = "轻扫 · \(model.status)"
    }

    @objc private func showWindow() {
        NSApp.setActivationPolicy(.regular)
        if window?.isMiniaturized == true {
            window?.deminiaturize(nil)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func scan() {
        showWindow()
        model.scan()
    }

    @objc private func clean() {
        showWindow()
        model.clean()
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "轻扫", .applicationVersion: "1.0.0",
            .applicationIcon: Branding.image(size: 128)
        ])
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(scan) { return !model.isBusy }
        if menuItem.action == #selector(clean) { return model.canClean }
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    private func capturePreview(path: String) {
        guard options.isDemo, let contentView = window.contentView else { return }
        contentView.layoutSubtreeIfNeeded()
        guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else {
            captureFailed("无法创建预览位图")
            return
        }
        contentView.cacheDisplay(in: contentView.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            captureFailed("无法编码 PNG")
            return
        }
        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            print(path)
            NSApp.terminate(nil)
        } catch { captureFailed(error.localizedDescription) }
    }

    private func captureFailed(_ message: String) {
        FileHandle.standardError.write(Data("FeatherSweep: \(message)\n".utf8))
        Darwin.exit(1)
    }
}
