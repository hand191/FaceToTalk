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

enum FacingAngleSettings {
    static let defaultEnterYawDegrees = 16.0
    static let defaultEnterPitchDegrees = 14.0
    static let defaultExitYawDegrees = 24.0
    static let defaultExitPitchDegrees = 21.0

    static let enterYawRange = 5.0...35.0
    static let enterPitchRange = 5.0...30.0
    static let exitYawRange = 8.0...50.0
    static let exitPitchRange = 8.0...45.0
    static let minimumHysteresis = 2.0

    static func sanitized(_ value: Double, fallback: Double, range: ClosedRange<Double>) -> Double {
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
        static let controlMode = "controlMode"
        static let restrictToTarget = "restrictToTarget"
        static let masterEnabled = "masterEnabled"
        static let enterYawDegrees = "enterYawDegrees"
        static let enterPitchDegrees = "enterPitchDegrees"
        static let exitYawDegrees = "exitYawDegrees"
        static let exitPitchDegrees = "exitPitchDegrees"
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

    @Published var controlMode: ControlMode {
        didSet { defaults.set(controlMode.rawValue, forKey: Key.controlMode) }
    }

    @Published var restrictToTarget: Bool {
        didSet { defaults.set(restrictToTarget, forKey: Key.restrictToTarget) }
    }

    @Published var masterEnabled: Bool {
        didSet { defaults.set(masterEnabled, forKey: Key.masterEnabled) }
    }

    @Published private(set) var enterYawDegrees: Double
    @Published private(set) var enterPitchDegrees: Double
    @Published private(set) var exitYawDegrees: Double
    @Published private(set) var exitPitchDegrees: Double

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
        controlMode = ControlMode(rawValue: defaults.string(forKey: Key.controlMode) ?? "") ?? .codexShortcut
        restrictToTarget = defaults.object(forKey: Key.restrictToTarget) as? Bool ?? true
        masterEnabled = defaults.object(forKey: Key.masterEnabled) as? Bool ?? true

        let savedEnterYaw = (defaults.object(forKey: Key.enterYawDegrees) as? NSNumber)?.doubleValue
            ?? FacingAngleSettings.defaultEnterYawDegrees
        let savedEnterPitch = (defaults.object(forKey: Key.enterPitchDegrees) as? NSNumber)?.doubleValue
            ?? FacingAngleSettings.defaultEnterPitchDegrees
        let savedExitYaw = (defaults.object(forKey: Key.exitYawDegrees) as? NSNumber)?.doubleValue
            ?? FacingAngleSettings.defaultExitYawDegrees
        let savedExitPitch = (defaults.object(forKey: Key.exitPitchDegrees) as? NSNumber)?.doubleValue
            ?? FacingAngleSettings.defaultExitPitchDegrees

        let normalizedEnterYaw = FacingAngleSettings.sanitized(
            savedEnterYaw,
            fallback: FacingAngleSettings.defaultEnterYawDegrees,
            range: FacingAngleSettings.enterYawRange
        )
        let normalizedEnterPitch = FacingAngleSettings.sanitized(
            savedEnterPitch,
            fallback: FacingAngleSettings.defaultEnterPitchDegrees,
            range: FacingAngleSettings.enterPitchRange
        )
        enterYawDegrees = normalizedEnterYaw
        enterPitchDegrees = normalizedEnterPitch
        exitYawDegrees = max(
            normalizedEnterYaw + FacingAngleSettings.minimumHysteresis,
            FacingAngleSettings.sanitized(
                savedExitYaw,
                fallback: FacingAngleSettings.defaultExitYawDegrees,
                range: FacingAngleSettings.exitYawRange
            )
        )
        exitPitchDegrees = max(
            normalizedEnterPitch + FacingAngleSettings.minimumHysteresis,
            FacingAngleSettings.sanitized(
                savedExitPitch,
                fallback: FacingAngleSettings.defaultExitPitchDegrees,
                range: FacingAngleSettings.exitPitchRange
            )
        )

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
        persistFacingAngles()
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

    var facingAngleThresholds: FacingAngleThresholds {
        FacingAngleThresholds(
            enterYawDegrees: enterYawDegrees,
            enterPitchDegrees: enterPitchDegrees,
            exitYawDegrees: exitYawDegrees,
            exitPitchDegrees: exitPitchDegrees
        )
    }

    func updateEnterYawDegrees(_ value: Double) {
        enterYawDegrees = FacingAngleSettings.sanitized(
            value,
            fallback: FacingAngleSettings.defaultEnterYawDegrees,
            range: FacingAngleSettings.enterYawRange
        )
        if exitYawDegrees < enterYawDegrees + FacingAngleSettings.minimumHysteresis {
            exitYawDegrees = enterYawDegrees + FacingAngleSettings.minimumHysteresis
        }
        persistFacingAngles()
    }

    func updateEnterPitchDegrees(_ value: Double) {
        enterPitchDegrees = FacingAngleSettings.sanitized(
            value,
            fallback: FacingAngleSettings.defaultEnterPitchDegrees,
            range: FacingAngleSettings.enterPitchRange
        )
        if exitPitchDegrees < enterPitchDegrees + FacingAngleSettings.minimumHysteresis {
            exitPitchDegrees = enterPitchDegrees + FacingAngleSettings.minimumHysteresis
        }
        persistFacingAngles()
    }

    func updateExitYawDegrees(_ value: Double) {
        let minimum = enterYawDegrees + FacingAngleSettings.minimumHysteresis
        exitYawDegrees = max(
            minimum,
            FacingAngleSettings.sanitized(
                value,
                fallback: FacingAngleSettings.defaultExitYawDegrees,
                range: FacingAngleSettings.exitYawRange
            )
        )
        persistFacingAngles()
    }

    func updateExitPitchDegrees(_ value: Double) {
        let minimum = enterPitchDegrees + FacingAngleSettings.minimumHysteresis
        exitPitchDegrees = max(
            minimum,
            FacingAngleSettings.sanitized(
                value,
                fallback: FacingAngleSettings.defaultExitPitchDegrees,
                range: FacingAngleSettings.exitPitchRange
            )
        )
        persistFacingAngles()
    }

    func restoreFacingAngleDefaults() {
        enterYawDegrees = FacingAngleSettings.defaultEnterYawDegrees
        enterPitchDegrees = FacingAngleSettings.defaultEnterPitchDegrees
        exitYawDegrees = FacingAngleSettings.defaultExitYawDegrees
        exitPitchDegrees = FacingAngleSettings.defaultExitPitchDegrees
        persistFacingAngles()
    }

    private func persistFacingAngles() {
        defaults.set(enterYawDegrees, forKey: Key.enterYawDegrees)
        defaults.set(enterPitchDegrees, forKey: Key.enterPitchDegrees)
        defaults.set(exitYawDegrees, forKey: Key.exitYawDegrees)
        defaults.set(exitPitchDegrees, forKey: Key.exitPitchDegrees)
    }
}
