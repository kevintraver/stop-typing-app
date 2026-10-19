import Foundation
import Observation
import Sparkle

/// Sparkle's updater, with the state Settings shows mirrored so SwiftUI sees it change.
@MainActor
@Observable
final class Updater {
    /// Whether this build can update itself. Only release builds carry Sparkle's EdDSA public key
    /// (scripts/release.sh injects it); development builds leave `SUPublicEDKey` empty.
    let isAvailable: Bool

    /// Whether a check can start right now. Sparkle turns this off while a check or update is running.
    private(set) var canCheckForUpdates = false

    var automaticallyChecksForUpdates: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    init() {
        // Without a public key Sparkle either refuses to start and shows a "contact the developer" alert
        // a second after launch (empty or invalid key), or falls back to trusting Apple code signing
        // alone, which it deprecates. Neither is right for a development build, so the updater is
        // created but never started there, and every Sparkle entry point stays inert.
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        isAvailable = !publicKey.isEmpty
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        guard isAvailable else { return }

        // Override any older stored preference before the first possible request.
        controller.updater.sendsSystemProfile = false
        controller.startUpdater()
        // Sparkle changes this on the main thread, where its KVO notifications are delivered too.
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated {
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
