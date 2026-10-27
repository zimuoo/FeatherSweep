import XCTest
@testable import FeatherSweep

final class AppUpdaterTests: XCTestCase {
    @MainActor func testBusyAutomaticInstallDrainsExactlyOnceWhenIdle() {
        let gate = UpdateInstallationGate()
        var calls = 0
        gate.enqueueAutomatic { calls += 1 }
        gate.drain(isBusy: true, automaticEnabled: true)
        XCTAssertEqual(calls, 0)
        gate.drain(isBusy: false, automaticEnabled: true)
        gate.drain(isBusy: false, automaticEnabled: true)
        XCTAssertEqual(calls, 1)
    }
    @MainActor func testDisabledAutomaticInstallRetainsPendingUntilEnabled() {
        let gate = UpdateInstallationGate()
        var calls = 0
        gate.enqueueAutomatic { calls += 1 }
        gate.drain(isBusy: false, automaticEnabled: false)
        XCTAssertEqual(calls, 0)
        gate.drain(isBusy: false, automaticEnabled: true)
        XCTAssertEqual(calls, 1)
    }
    @MainActor func testManualRelaunchWaitsForIdleEvenWithAutomaticUpdatesOff() {
        let gate = UpdateInstallationGate()
        var calls = 0
        gate.enqueueManual { calls += 1 }
        gate.drain(isBusy: true, automaticEnabled: false)
        XCTAssertEqual(calls, 0)
        gate.drain(isBusy: false, automaticEnabled: false)
        gate.drain(isBusy: false, automaticEnabled: false)
        XCTAssertEqual(calls, 1)
    }
    func testAssetURLPolicy() {
        XCTAssertTrue(UpdatePolicy.allowsAsset(URL(string: "https://github.com/zimuoo/FeatherSweep/releases/download/v1.2.0/FeatherSweep-arm64.dmg")!))
        for value in ["http://github.com/zimuoo/FeatherSweep/releases/download/v1/a.dmg", "https://evil.com/zimuoo/FeatherSweep/releases/download/v1/a.dmg", "https://user@github.com/zimuoo/FeatherSweep/releases/download/v1/a.dmg", "https://github.com/zimuoo/FeatherSweep/releases/download/v1/a.dmg?x=1", "https://github.com/zimuoo/FeatherSweep/releases/download/../bad", "https://github.com/zimuoo/FeatherSweep/releases/download/v1/a.dmg#fragment", "https://github.com:444/zimuoo/FeatherSweep/releases/download/v1/a.dmg"] {
            XCTAssertFalse(UpdatePolicy.allowsAsset(URL(string: value)!), value)
        }
    }
    func testActivationRequiresRealIdentityFeedAndKey() {
        let feed = UpdatePolicy.productionFeed
        let key = Data(repeating: 1, count: 32).base64EncodedString()
        XCTAssertTrue(UpdatePolicy.canActivate(isDemo: false, bundleURL: URL(fileURLWithPath: "/tmp/FeatherSweep.app"), identifier: "io.github.zimuoo.FeatherSweep", feed: feed, publicKey: key))
        for (demo, path, identity, url, signingKey) in [(true, "/tmp/F.app", "io.github.zimuoo.FeatherSweep", feed, key), (false, "/tmp/FeatherSweep", "io.github.zimuoo.FeatherSweep", feed, key), (false, "/tmp/F.app", "other", feed, key), (false, "/tmp/F.app", "io.github.zimuoo.FeatherSweep", "https://evil.com/feed.xml", key), (false, "/tmp/F.app", "io.github.zimuoo.FeatherSweep", feed, "invalid")] {
            XCTAssertFalse(UpdatePolicy.canActivate(isDemo: demo, bundleURL: URL(fileURLWithPath: path), identifier: identity, feed: url, publicKey: signingKey))
        }
    }
    func testStoredOptOutOverridesAutomaticDefaults() {
        let name = "FeatherSweep.UpdatePreferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertTrue(UpdatePolicy.automaticUpdatesAllowed(defaults: defaults))
        defaults.set(false, forKey: "SUAutomaticallyUpdate")
        XCTAssertFalse(UpdatePolicy.automaticUpdatesAllowed(defaults: defaults))
        defaults.set(true, forKey: "SUAutomaticallyUpdate")
        defaults.set(false, forKey: "SUEnableAutomaticChecks")
        XCTAssertFalse(UpdatePolicy.automaticUpdatesAllowed(defaults: defaults))
    }
    @MainActor func testPersistedOffSurvivesUpdaterConstructionInDeveloperMode() {
        let name = "FeatherSweep.UpdateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: "SUAutomaticallyUpdate")
        defaults.set(false, forKey: "SUEnableAutomaticChecks")
        let updater = AppUpdater(model: CleanerViewModel(isDemo: true), isDemo: true, defaults: defaults)
        updater.start()
        updater.toggleAutomaticUpdates()
        XCTAssertFalse(updater.canCheckForUpdates)
        XCTAssertFalse(updater.automaticUpdatesEnabled)
        XCTAssertFalse(defaults.bool(forKey: "SUAutomaticallyUpdate"))
    }
}

import Combine
import Sparkle

@MainActor
private final class TestUpdateActivity: UpdateActivity {
    var isDemo = false
    var isBusy = false
    let changes = PassthroughSubject<Void, Never>()
    var phaseChanges: AnyPublisher<Void, Never> { changes.eraseToAnyPublisher() }
    func setBusy(_ value: Bool) { isBusy = value; changes.send(()) }
}

@MainActor
private final class TestUpdateDriver: UpdateDriver {
    var automaticallyChecksForUpdates = true
    var automaticallyDownloadsUpdates = true
    var sendsSystemProfile = true
    var canCheckForUpdates = true
    var starts = 0
    var backgroundChecks = 0
    var manualChecks = 0
    weak var delegate: SPUUpdaterDelegate?
    let inertController: SPUStandardUpdaterController
    init(delegate: SPUUpdaterDelegate) {
        self.delegate = delegate
        inertController = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    }
    func start() throws { starts += 1 }
    func checkInBackground() { backgroundChecks += 1 }
    func checkManually() { manualChecks += 1 }
}

extension AppUpdaterTests {
    @MainActor private func fixture() throws -> (Bundle, UserDefaults, URL, String) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let contents = root.appendingPathComponent("FeatherSweep.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "io.github.zimuoo.FeatherSweep", "CFBundlePackageType": "APPL", "CFBundleVersion": "3", "SUFeedURL": UpdatePolicy.productionFeed, "SUPublicEDKey": Data(repeating: 1, count: 32).base64EncodedString()]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        let name = "FeatherSweep.Integration.\(UUID().uuidString)"
        return (try XCTUnwrap(Bundle(url: contents.deletingLastPathComponent())), UserDefaults(suiteName: name)!, root, name)
    }
    @MainActor private func settle() async {
        // A main-queue sentinel follows the delegate's queued drain without waiting on wall time.
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }

    @MainActor func testProductionTogglePersistsAndStartupHonorsStoredOff() async throws {
        let (bundle, defaults, root, name) = try fixture()
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: root) }
        let activity = TestUpdateActivity()
        var driver: TestUpdateDriver!
        let updater = AppUpdater(activity: activity, isDemo: false, defaults: defaults, bundle: bundle) {
            driver = TestUpdateDriver(delegate: $0); return driver
        }
        XCTAssertTrue(updater.isAvailable)
        updater.start()
        XCTAssertEqual(driver.starts, 1)
        XCTAssertEqual(driver.backgroundChecks, 1)
        XCTAssertFalse(driver.sendsSystemProfile)
        updater.checkForUpdates()
        XCTAssertEqual(driver.manualChecks, 1)
        updater.toggleAutomaticUpdates()
        XCTAssertFalse(updater.automaticUpdatesEnabled)
        XCTAssertFalse(defaults.bool(forKey: "SUAutomaticallyUpdate"))
        XCTAssertFalse(defaults.bool(forKey: "SUEnableAutomaticChecks"))
        var second: TestUpdateDriver!
        let restored = AppUpdater(activity: activity, isDemo: false, defaults: defaults, bundle: bundle) {
            second = TestUpdateDriver(delegate: $0); return second
        }
        restored.start()
        XCTAssertFalse(restored.automaticUpdatesEnabled)
        XCTAssertFalse(second.automaticallyChecksForUpdates)
        XCTAssertFalse(second.automaticallyDownloadsUpdates)
        XCTAssertEqual(second.backgroundChecks, 0)
    }

    @MainActor func testProductionDelegatesResumeOnceAfterScanAndCleanupAndRespectOptOut() async throws {
        let (bundle, defaults, root, name) = try fixture()
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: root) }
        let activity = TestUpdateActivity()
        var driver: TestUpdateDriver!
        let updater = AppUpdater(activity: activity, isDemo: false, defaults: defaults, bundle: bundle) {
            driver = TestUpdateDriver(delegate: $0); return driver
        }
        updater.start()
        let item = SUAppcastItem.empty()
        var automatic = 0
        activity.setBusy(true) // scan begins
        XCTAssertTrue(driver.delegate!.updater!(driver.inertController.updater, willInstallUpdateOnQuit: item, immediateInstallationBlock: { automatic += 1 }))
        XCTAssertEqual(automatic, 0, "Handler must not run before the delegate returns")
        await settle()
        XCTAssertEqual(automatic, 0)
        updater.toggleAutomaticUpdates()
        activity.setBusy(false)
        await settle()
        XCTAssertEqual(automatic, 0, "Disabling automatic updates must suppress the pending automatic restart")
        updater.toggleAutomaticUpdates()
        await settle()
        XCTAssertEqual(automatic, 1)
        activity.setBusy(false)
        await settle()
        XCTAssertEqual(automatic, 1)
        updater.toggleAutomaticUpdates()
        activity.setBusy(true) // cleanup begins
        var manual = 0
        XCTAssertTrue(driver.delegate!.updater!(driver.inertController.updater, shouldPostponeRelaunchForUpdate: item, untilInvokingBlock: { manual += 1 }))
        await settle()
        XCTAssertEqual(manual, 0)
        activity.setBusy(false)
        await settle()
        XCTAssertEqual(manual, 1, "A manual restart may resume with automatic updates off")
        activity.setBusy(false)
        await settle()
        XCTAssertEqual(manual, 1)
    }
}
