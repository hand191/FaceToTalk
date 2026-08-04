import Combine
import Foundation

enum TimingSettings {
    static let defaultOpenDelay = 1.0
    static let defaultCloseDelay = 3.0
    static let openDelayRange = 0.3...5.0
    static let closeDelayRange = 0.5...10.0

    static func sanitized(
        _ value: Double,
        fallback: Double,
        range: ClosedRange<Double>
    ) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    private enum Key {
        static let openDelay = "openDelay"
        static let closeDelay = "closeDelay"
        static let shortcut = "shortcut"
        static let mode = "hotKeyMode"
        static let restrictToTarget = "restrictToTarget"
        static let masterEnabled = "masterEnabled"
    }

    private let defaults: UserDefaults

    @Published var openDelay: Double {
        didSet { defaults.set(openDelay, forKey: Key.openDelay) }
    }

    @Published var closeDelay: Double {
        didSet { defaults.set(closeDelay, forKey: Key.closeDelay) }
    }

    @Published private(set) var shortcut: KeyboardShortcut

    @Published var hotKeyMode: HotKeyMode {
        didSet { defaults.set(hotKeyMode.rawValue, forKey: Key.mode) }
    }

    @Published var restrictToTarget: Bool {
        didSet { defaults.set(restrictToTarget, forKey: Key.restrictToTarget) }
    }

    @Published var masterEnabled: Bool {
        didSet { defaults.set(masterEnabled, forKey: Key.masterEnabled) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedOpenDelay = (defaults.object(forKey: Key.openDelay) as? NSNumber)?.doubleValue
            ?? TimingSettings.defaultOpenDelay
        let savedCloseDelay = (defaults.object(forKey: Key.closeDelay) as? NSNumber)?.doubleValue
            ?? TimingSettings.defaultCloseDelay
        openDelay = TimingSettings.sanitized(
            savedOpenDelay,
            fallback: TimingSettings.defaultOpenDelay,
            range: TimingSettings.openDelayRange
        )
        closeDelay = TimingSettings.sanitized(
            savedCloseDelay,
            fallback: TimingSettings.defaultCloseDelay,
            range: TimingSettings.closeDelayRange
        )
        hotKeyMode = HotKeyMode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .toggle
        restrictToTarget = defaults.object(forKey: Key.restrictToTarget) as? Bool ?? true
        masterEnabled = defaults.object(forKey: Key.masterEnabled) as? Bool ?? true

        if let data = defaults.data(forKey: Key.shortcut),
           let saved = try? JSONDecoder().decode(KeyboardShortcut.self, from: data),
           saved.isValidForAutomation {
            shortcut = saved
        } else {
            shortcut = .defaultDictation
        }

        // Heal values written by older builds so later launches stay in range.
        defaults.set(openDelay, forKey: Key.openDelay)
        defaults.set(closeDelay, forKey: Key.closeDelay)
        if let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: Key.shortcut)
        }
    }

    func updateShortcut(_ newShortcut: KeyboardShortcut) {
        guard newShortcut.isValidForAutomation else { return }
        shortcut = newShortcut
        if let data = try? JSONEncoder().encode(newShortcut) {
            defaults.set(data, forKey: Key.shortcut)
        }
    }

    func restoreTimingDefaults() {
        openDelay = TimingSettings.defaultOpenDelay
        closeDelay = TimingSettings.defaultCloseDelay
    }
}
