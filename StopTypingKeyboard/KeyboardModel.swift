import Foundation
import Observation
import StopTypingCore
import SwiftUI
import UIKit

/// Turns key presses into edits and counts, and decides when to nudge.
///
/// Each key press becomes `KeyCounts` the moment it's typed, and the text field's contents are
/// never read, so nothing here can tell what was written, only how much and of what kind.
@MainActor
@Observable
final class KeyboardModel {
    private(set) var input: KeyboardInput
    private(set) var isDimmed = false
    /// Bumped once per pulse toward the mic; the view animates on each change.
    private(set) var pulses = 0

    @ObservationIgnored private var detector = TypingDetector()
    @ObservationIgnored private let insertText: (String) -> Void
    @ObservationIgnored private let deleteBackward: () -> Void
    @ObservationIgnored private var undim: Task<Void, Never>?
    @ObservationIgnored private let stats = StatsStore()

    init(autocapitalizes: Bool, insertText: @escaping (String) -> Void, deleteBackward: @escaping () -> Void) {
        input = KeyboardInput(autocapitalizes: autocapitalizes)
        self.insertText = insertText
        self.deleteBackward = deleteBackward
    }

    /// The keyboard just appeared: pick up settings changed in the app and start a fresh burst,
    /// so typing in one field never carries over to the next.
    func refresh(autocapitalizes: Bool) {
        input = KeyboardInput(autocapitalizes: autocapitalizes)
        detector.configuration = SharedSettings.detection
        detector.reset()
    }

    func press(_ key: KeyboardInput.Key) {
        let now = ProcessInfo.processInfo.systemUptime
        for edit in input.press(key, at: now) {
            switch edit {
            case .insert(let text):
                insertText(text)
                count(KeyCounts(text), at: now)
            case .deleteBackward:
                deleteBackward()
            }
        }
    }

    private func count(_ counts: KeyCounts, at time: TimeInterval) {
        guard counts.total > 0 else { return }
        let outcome = detector.register(.text(counts), at: time)
        if outcome.newProseCharacters > 0 {
            stats.recordProse(outcome.newProseCharacters)
        }
        if let nudge = outcome.nudge {
            stats.recordNudge()
            self.nudge(nudge)
        }
    }

    /// Dims the keys for a moment (they stay tappable), pulses toward Apple's mic below the keyboard,
    /// and taps a haptic. Typing is never blocked.
    func nudge(_ nudge: Nudge) {
        if SharedSettings.hapticsEnabled {
            switch nudge {
            case .gentle: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            case .firm, .stop: UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        }
        UIAccessibility.post(notification: .announcement, argument: String(localized: "You're typing a lot. Dictate with the microphone below the keyboard."))

        withAnimation(.easeOut(duration: 0.15)) { isDimmed = true }
        pulses += nudge == .gentle ? 1 : 2
        undim?.cancel()
        undim = Task {
            try? await Task.sleep(for: nudge == .gentle ? .seconds(1.5) : .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.4)) { isDimmed = false }
        }
    }
}

/// Today's counts, kept in the keyboard's own container: without Full Access it can't share them.
@MainActor
private final class StatsStore {
    private let defaults = UserDefaults.standard
    private let key = "stats"

    private var stats: DailyStats {
        get {
            (defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(DailyStats.self, from: $0) }
                ?? DailyStats(day: .now)).on(.now)
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }

    func recordProse(_ characters: Int) {
        stats.recordProse(characters, at: .now)
    }

    func recordNudge() {
        stats.recordNudge(at: .now)
    }
}
