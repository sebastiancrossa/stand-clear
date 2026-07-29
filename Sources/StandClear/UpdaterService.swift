import AppKit
import Foundation
import Sparkle

enum SoftwareUpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(version: String)
    case failed(String)
}

@MainActor
protocol SoftwareUpdating: AnyObject {
    var state: SoftwareUpdateState { get }
    var lastCheckDate: Date? { get }
    var automaticallyChecksForUpdates: Bool { get }
    var canCheckForUpdates: Bool { get }
    /// Invoked whenever `state` / `lastCheckDate` change so the host can republish.
    var onStateChange: (() -> Void)? { get set }
    func start()
    func setAutomaticallyChecksForUpdates(_ enabled: Bool)
    func checkForUpdates()
    func refreshUpdateInformation()
}

/// Wraps Sparkle for Stand Clear. Automatic-check preference is owned by Sparkle
/// (`automaticallyChecksForUpdates`); do not mirror it in `UserDefaults`.
@MainActor
final class SparkleUpdaterService: NSObject, SoftwareUpdating {
    private(set) var state: SoftwareUpdateState = .idle {
        didSet { onStateChange?() }
    }
    private(set) var lastCheckDate: Date? {
        didSet { onStateChange?() }
    }
    var onStateChange: (() -> Void)?

    private var controller: SPUStandardUpdaterController!
    private var hasStarted = false
    private var didPromoteActivationPolicy = false

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }

    var automaticallyChecksForUpdates: Bool {
        controller.updater.automaticallyChecksForUpdates
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        controller.startUpdater()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard controller.updater.automaticallyChecksForUpdates != enabled else { return }
        controller.updater.automaticallyChecksForUpdates = enabled
    }

    func checkForUpdates() {
        state = .checking
        controller.checkForUpdates(nil)
    }

    func refreshUpdateInformation() {
        state = .checking
        controller.updater.checkForUpdateInformation()
    }

    private func promoteActivationPolicyIfNeeded() {
        guard NSApp.activationPolicy() == .accessory else { return }
        NSApp.setActivationPolicy(.regular)
        didPromoteActivationPolicy = true
        NSApp.activate(ignoringOtherApps: true)
    }

    private func restoreActivationPolicyIfNeeded() {
        guard didPromoteActivationPolicy else { return }
        didPromoteActivationPolicy = false
        NSApp.setActivationPolicy(.accessory)
    }
}

extension SparkleUpdaterService: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in
            lastCheckDate = Date()
            state = .available(version: item.displayVersionString)
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            lastCheckDate = Date()
            state = .upToDate
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        Task { @MainActor in
            switch SparkleAbortReason(error) {
            case .noUpdateFound:
                lastCheckDate = Date()
                state = .upToDate
            case .userDeclinedInstall:
                // An update we already found stays found; declining to install it now is
                // not a reason to forget it.
                if case .available = state { return }
                state = .idle
            case let .checkFailed(message):
                lastCheckDate = Date()
                state = .failed(message)
            }
        }
    }
}

/// Why Sparkle tore an update session down.
///
/// Sparkle ends *every* session — including the happy ones — by aborting the update driver
/// with an error, so `didAbortWithError` cannot be read as "something went wrong". A check
/// that finds nothing aborts with `SUNoUpdateError`, whose `localizedDescription` is
/// "You're up to date!"; surfacing that verbatim is how a good outcome ends up phrased and
/// coloured like a failure. The code has to be classified before the state can be trusted.
enum SparkleAbortReason: Equatable {
    /// The check completed and the running version is current.
    case noUpdateFound
    /// The rider dismissed or deferred an install they had been offered.
    case userDeclinedInstall
    /// The check genuinely did not complete — offline, unreachable feed, bad appcast.
    case checkFailed(String)

    init(_ error: any Error) {
        let error = error as NSError
        guard error.domain == SUSparkleErrorDomain else {
            self = .checkFailed(error.localizedDescription)
            return
        }
        switch error.code {
        case Int(SUError.noUpdateError.rawValue):
            self = .noUpdateFound
        case Int(SUError.installationCanceledError.rawValue),
             Int(SUError.installationAuthorizeLaterError.rawValue):
            self = .userDeclinedInstall
        default:
            self = .checkFailed(error.localizedDescription)
        }
    }
}

extension SparkleUpdaterService: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Keep background finds quiet; Settings + menu footer surface them.
        false
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        Task { @MainActor in
            self.state = .available(version: update.displayVersionString)
            if handleShowingUpdate {
                promoteActivationPolicyIfNeeded()
            }
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in
            restoreActivationPolicyIfNeeded()
        }
    }
}

/// Test double that keeps update state in memory.
@MainActor
final class PreviewUpdaterService: SoftwareUpdating {
    private(set) var state: SoftwareUpdateState {
        didSet { onStateChange?() }
    }
    private(set) var lastCheckDate: Date? {
        didSet { onStateChange?() }
    }
    private(set) var automaticallyChecksForUpdates: Bool
    private(set) var canCheckForUpdates: Bool
    var onStateChange: (() -> Void)?
    private(set) var didStart = false
    private(set) var checkForUpdatesCallCount = 0
    private(set) var refreshUpdateInformationCallCount = 0

    /// When set, the next `checkForUpdates` / `refreshUpdateInformation` adopts this state.
    var nextCheckResult: SoftwareUpdateState = .upToDate

    init(
        state: SoftwareUpdateState = .idle,
        automaticallyChecksForUpdates: Bool = true,
        canCheckForUpdates: Bool = true,
        lastCheckDate: Date? = nil
    ) {
        self.state = state
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        self.canCheckForUpdates = canCheckForUpdates
        self.lastCheckDate = lastCheckDate
    }

    func start() {
        didStart = true
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        automaticallyChecksForUpdates = enabled
    }

    func checkForUpdates() {
        checkForUpdatesCallCount += 1
        state = .checking
        lastCheckDate = Date()
        state = nextCheckResult
    }

    func refreshUpdateInformation() {
        refreshUpdateInformationCallCount += 1
        state = .checking
        lastCheckDate = Date()
        state = nextCheckResult
    }

    func seedState(_ state: SoftwareUpdateState) {
        self.state = state
    }
}
