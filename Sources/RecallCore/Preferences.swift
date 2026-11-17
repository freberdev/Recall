import Foundation

/// The app's few stored settings.
public struct Preferences {
    private enum Key {
        static let shortcut = "shortcut"
        static let didAutoEnableLoginItem = "didAutoEnableLoginItem"
        static let hasShownWelcome = "hasShownWelcome"
        static let isPaused = "isPaused"
        static let maxCount = "maxCount"
        static let maxAgeDays = "maxAgeDays"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The shortcut that opens Recall. Falls back to the default if nothing usable is stored.
    public var shortcut: Shortcut {
        get {
            guard let data = defaults.data(forKey: Key.shortcut),
                  let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data),
                  shortcut.isValid
            else { return .default }
            return shortcut
        }
        nonmutating set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.shortcut)
        }
    }

    /// Set once Recall has turned on "open at login" by itself, so it never does so a second time.
    public var didAutoEnableLoginItem: Bool {
        get { defaults.bool(forKey: Key.didAutoEnableLoginItem) }
        nonmutating set { defaults.set(newValue, forKey: Key.didAutoEnableLoginItem) }
    }

    /// Set once the panel has introduced itself on first launch.
    public var hasShownWelcome: Bool {
        get { defaults.bool(forKey: Key.hasShownWelcome) }
        nonmutating set { defaults.set(newValue, forKey: Key.hasShownWelcome) }
    }

    /// Whether collecting is paused. Stays paused across restarts until the user resumes.
    public var isPaused: Bool {
        get { defaults.bool(forKey: Key.isPaused) }
        nonmutating set { defaults.set(newValue, forKey: Key.isPaused) }
    }

    /// How much history is kept. Stored values that are not among the choices fall back to the default.
    public var limits: Limits {
        get {
            var limits = Limits.default
            if let count = defaults.object(forKey: Key.maxCount) as? Int, Limits.countChoices.contains(count) {
                limits.maxCount = count
            }
            // Zero stands for "never remove by age".
            if let days = defaults.object(forKey: Key.maxAgeDays) as? Int {
                if days == 0 {
                    limits.maxAgeDays = nil
                } else if Limits.ageChoices.contains(days) {
                    limits.maxAgeDays = days
                }
            }
            return limits
        }
        nonmutating set {
            defaults.set(newValue.maxCount, forKey: Key.maxCount)
            defaults.set(newValue.maxAgeDays ?? 0, forKey: Key.maxAgeDays)
        }
    }
}
