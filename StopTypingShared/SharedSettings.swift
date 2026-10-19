import Foundation
import StopTypingCore

/// Settings the iPhone app writes and its keyboard reads, through the App Group they share.
/// Without Full Access the keyboard can read this container but not write to it, which is all it needs.
enum SharedSettings {
    static let appGroup = "group.com.kevintraver.StopTyping"

    private static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    private enum Key {
        static let detection = "detection"
        static let hapticsEnabled = "hapticsEnabled"
    }

    static var detection: DetectorConfiguration {
        get {
            defaults.data(forKey: Key.detection)
                .flatMap { try? JSONDecoder().decode(DetectorConfiguration.self, from: $0) }
                ?? DetectorConfiguration()
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.detection) }
    }

    static var hapticsEnabled: Bool {
        get { defaults.object(forKey: Key.hapticsEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.hapticsEnabled) }
    }
}
