import ApplicationServices
import Carbon.HIToolbox
import Foundation

struct HotKeyEventStep: Equatable, Sendable {
    let keyCode: UInt16
    let keyDown: Bool
    let flagsRawValue: UInt64
}

enum HotKeyChordBuilder {
    private struct ModifierKey {
        let flag: CGEventFlags
        let keyCode: UInt16
    }

    // Use the left-side physical modifier keys in a stable order.
    private static let modifierKeys: [ModifierKey] = [
        ModifierKey(flag: .maskControl, keyCode: UInt16(kVK_Control)),
        ModifierKey(flag: .maskAlternate, keyCode: UInt16(kVK_Option)),
        ModifierKey(flag: .maskShift, keyCode: UInt16(kVK_Shift)),
        ModifierKey(flag: .maskCommand, keyCode: UInt16(kVK_Command))
    ]

    static func pressSteps(for shortcut: KeyboardShortcut) -> [HotKeyEventStep] {
        let selectedModifiers = modifierKeys.filter { shortcut.eventFlags.contains($0.flag) }
        var activeFlags: CGEventFlags = []
        var steps: [HotKeyEventStep] = []

        for modifier in selectedModifiers {
            activeFlags.insert(modifier.flag)
            steps.append(HotKeyEventStep(
                keyCode: modifier.keyCode,
                keyDown: true,
                flagsRawValue: activeFlags.rawValue
            ))
        }

        steps.append(HotKeyEventStep(
            keyCode: shortcut.keyCode,
            keyDown: true,
            flagsRawValue: activeFlags.rawValue
        ))
        return steps
    }

    static func releaseSteps(for shortcut: KeyboardShortcut) -> [HotKeyEventStep] {
        let selectedModifiers = modifierKeys.filter { shortcut.eventFlags.contains($0.flag) }
        var activeFlags = selectedModifiers.reduce(into: CGEventFlags()) { flags, modifier in
            flags.insert(modifier.flag)
        }
        var steps: [HotKeyEventStep] = [
            HotKeyEventStep(
                keyCode: shortcut.keyCode,
                keyDown: false,
                flagsRawValue: activeFlags.rawValue
            )
        ]

        for modifier in selectedModifiers.reversed() {
            activeFlags.remove(modifier.flag)
            steps.append(HotKeyEventStep(
                keyCode: modifier.keyCode,
                keyDown: false,
                flagsRawValue: activeFlags.rawValue
            ))
        }
        return steps
    }
}

@MainActor
final class HotKeyController {
    private(set) var heldShortcut: KeyboardShortcut?

    var hasPostEventAccess: Bool {
        CGPreflightPostEventAccess()
    }

    @discardableResult
    func requestPostEventAccess() -> Bool {
        CGRequestPostEventAccess()
    }

    func tap(_ shortcut: KeyboardShortcut) async -> Bool {
        guard hasPostEventAccess,
              let downEvents = makeEvents(HotKeyChordBuilder.pressSteps(for: shortcut)),
              let upEvents = makeEvents(HotKeyChordBuilder.releaseSteps(for: shortcut)) else {
            return false
        }

        post(downEvents)
        try? await Task.sleep(for: .milliseconds(45))
        post(upEvents)
        return true
    }

    func press(_ shortcut: KeyboardShortcut) -> Bool {
        guard heldShortcut == nil,
              hasPostEventAccess,
              let events = makeEvents(HotKeyChordBuilder.pressSteps(for: shortcut)) else {
            return false
        }
        post(events)
        heldShortcut = shortcut
        return true
    }

    func releaseHeldKey() -> Bool {
        guard let heldShortcut else { return true }
        guard hasPostEventAccess,
              let events = makeEvents(HotKeyChordBuilder.releaseSteps(for: heldShortcut)) else {
            // Keep the original chord so permission recovery can retry key-up.
            return false
        }
        post(events)
        self.heldShortcut = nil
        return true
    }

    func sendKeyUp(_ shortcut: KeyboardShortcut) -> Bool {
        guard hasPostEventAccess,
              let events = makeEvents(HotKeyChordBuilder.releaseSteps(for: shortcut)) else {
            return false
        }
        post(events)
        if heldShortcut == shortcut {
            heldShortcut = nil
        }
        return true
    }

    private func makeEvents(_ steps: [HotKeyEventStep]) -> [CGEvent]? {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return nil }
        var events: [CGEvent] = []
        events.reserveCapacity(steps.count)

        for step in steps {
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(step.keyCode),
                keyDown: step.keyDown
            ) else {
                return nil
            }
            event.flags = CGEventFlags(rawValue: step.flagsRawValue)
            events.append(event)
        }
        return events
    }

    private func post(_ events: [CGEvent]) {
        for event in events {
            event.post(tap: .cghidEventTap)
        }
    }
}
