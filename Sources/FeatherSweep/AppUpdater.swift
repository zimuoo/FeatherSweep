import AppKit
import Combine
import Foundation
import Sparkle

/// Owns callbacks, never the installer. A callback is removed before invocation to prevent reentrancy.
@MainActor
final class UpdateInstallationGate {
    private var automatic: (() -> Void)?
    private var manual: (() -> Void)?

    func enqueueAutomatic(_ callback: @escaping () -> Void) { automatic = callback }
    func enqueueManual(_ callback: @escaping () -> Void) { manual = callback }
    func drain(isBusy: Bool, automaticEnabled: Bool) {
        guard !isBusy else { return }
        if let callback = manual {
            manual = nil
            automatic = nil
            callback()
        } else if automaticEnabled, let callback = automatic {
            automatic = nil
            callback()
        }
    }
}

enum UpdatePolicy {
    static var productionFeed: String {
        #if arch(arm64)
        return "https://github.com/zimuoo/FeatherSweep/releases/latest/download/appcast-arm64.xml"
        #else
        return "https://github.com/zimuoo/FeatherSweep/releases/latest/download/appcast-x86_64.xml"
        #endif
    }

    static func automaticUpdatesAllowed(defaults: UserDefaults) -> Bool {
        ["SUEnableAutomaticChecks", "SUAutomaticallyUpdate"].allSatisfy {
            (defaults.object(forKey: $0) as? Bool) != false
        }
    }

    static func allowsAsset(_ url: URL) -> Bool {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme == "https", c.host == "github.com", c.port == nil,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              c.percentEncodedPath == c.path,
              c.path.hasPrefix("/zimuoo/FeatherSweep/releases/download/") else { return false }
        let parts = c.path.split(separator: "/", omittingEmptySubsequences: false)
        return !parts.contains("..") && !parts.contains(".") && !c.path.contains("\\") && parts.count >= 7 && !parts.last!.isEmpty
    }

    static func canActivate(isDemo: Bool, bundleURL: URL, identifier: String?, feed: String?, publicKey: String?) -> Bool {
        !isDemo && bundleURL.pathExtension == "app" && identifier == "io.github.zimuoo.FeatherSweep"
            && feed == productionFeed && publicKey.flatMap { Data(base64Encoded: $0) }?.count == 32
    }
}

@MainActor
protocol UpdateActivity: AnyObject {
    var isDemo: Bool { get }
    var isBusy: Bool { get }
    var phaseChanges: AnyPublisher<Void, Never> { get }
}

extension CleanerViewModel: UpdateActivity {
    var phaseChanges: AnyPublisher<Void, Never> { $phase.map { _ in () }.eraseToAnyPublisher() }
}

@MainActor
protocol UpdateDriver: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    var sendsSystemProfile: Bool { get set }
    var canCheckForUpdates: Bool { get }
    func start() throws
    func checkInBackground()
    func checkManually()
}

/// Sparkle remains responsible for networking, signature verification and installation.
@MainActor
private final class SparkleUpdateDriver: UpdateDriver {
    private let controller: SPUStandardUpdaterController
    init(delegate: SPUUpdaterDelegate) {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: delegate, userDriverDelegate: nil)
    }
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
    var automaticallyDownloadsUpdates: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { controller.updater.automaticallyDownloadsUpdates = newValue }
    }
    var sendsSystemProfile: Bool {
        get { controller.updater.sendsSystemProfile }
        set { controller.updater.sendsSystemProfile = newValue }
    }
    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }
    func start() throws { try controller.updater.start() }
    func checkInBackground() { controller.updater.checkForUpdatesInBackground() }
    func checkManually() { controller.checkForUpdates(nil) }
}

@MainActor
final class AppUpdater: NSObject, SPUUpdaterDelegate {
    private let activity: any UpdateActivity
    private let defaults: UserDefaults
    private let gate = UpdateInstallationGate()
    private var driver: (any UpdateDriver)?
    private var phaseSubscription: AnyCancellable?
    private var started = false
    let isAvailable: Bool

    convenience init(model: CleanerViewModel, isDemo: Bool, defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.init(activity: model, isDemo: isDemo, defaults: defaults, bundle: bundle) { SparkleUpdateDriver(delegate: $0) }
    }

    init(activity: any UpdateActivity, isDemo: Bool, defaults: UserDefaults, bundle: Bundle,
         makeDriver: (SPUUpdaterDelegate) -> any UpdateDriver) {
        self.activity = activity
        self.defaults = defaults
        isAvailable = UpdatePolicy.canActivate(isDemo: isDemo || activity.isDemo, bundleURL: bundle.bundleURL,
            identifier: bundle.bundleIdentifier, feed: bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            publicKey: bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)
        super.init()
        guard isAvailable else { return }
        driver = makeDriver(self)
        // Honor explicit persisted opt-outs before starting a driver, including its startup check.
        if defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool == false {
            driver?.automaticallyChecksForUpdates = false
        }
        if defaults.object(forKey: "SUAutomaticallyUpdate") as? Bool == false {
            driver?.automaticallyDownloadsUpdates = false
        }
        phaseSubscription = activity.phaseChanges.sink { [weak self] _ in self?.scheduleDrain() }
    }

    var automaticUpdatesEnabled: Bool {
        guard isAvailable, UpdatePolicy.automaticUpdatesAllowed(defaults: defaults) else { return false }
        if let updater = driver {
            return updater.automaticallyChecksForUpdates && updater.automaticallyDownloadsUpdates
        }
        return false
    }
    var canCheckForUpdates: Bool { !activity.isBusy && started && driver?.canCheckForUpdates == true }

    func start() {
        guard isAvailable, !started, let updater = driver else { return }
        updater.sendsSystemProfile = false
        // Sparkle reads its persisted settings itself; never overwrite a saved opt-out here.
        do {
            try updater.start()
            started = true
            if updater.automaticallyChecksForUpdates {
                updater.checkInBackground()
            }
        }
        catch { NSLog("FeatherSweep updater could not start: %@", error.localizedDescription) }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        driver?.checkManually()
    }

    func toggleAutomaticUpdates() {
        guard isAvailable, let updater = driver else { return }
        let enabled = !automaticUpdatesEnabled
        defaults.set(enabled, forKey: "SUEnableAutomaticChecks")
        defaults.set(enabled, forKey: "SUAutomaticallyUpdate")
        updater.automaticallyChecksForUpdates = enabled
        updater.automaticallyDownloadsUpdates = enabled
        scheduleDrain()
    }

    private func scheduleDrain() {
        // Sparkle must receive the delegate's Bool before invoking its handler. Published phases
        // also emit before assignment, so drain on the following main run-loop turn.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.gate.drain(isBusy: self.activity.isBusy, automaticEnabled: self.automaticUpdatesEnabled)
        }
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        guard automaticUpdatesEnabled else { return false }
        gate.enqueueAutomatic(immediateInstallHandler)
        scheduleDrain()
        return true
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard activity.isBusy else { return false }
        gate.enqueueManual(installHandler)
        scheduleDrain()
        return true
    }

    func feedURLString(for updater: SPUUpdater) -> String? { UpdatePolicy.productionFeed }
    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }
    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate updateItem: SUAppcastItem) -> Bool { false }
    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        guard let url = updateItem.fileURL, UpdatePolicy.allowsAsset(url) else {
            throw NSError(domain: "FeatherSweep.UpdatePolicy", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Update download is outside the official FeatherSweep release repository."])
        }
    }
}
