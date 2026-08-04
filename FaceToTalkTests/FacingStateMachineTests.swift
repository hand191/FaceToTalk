import XCTest
@testable import FaceToTalk

final class FacingStateMachineTests: XCTestCase {
    func testDefaultDictationChordPostsPhysicalModifierTransitions() {
        let shortcut = KeyboardShortcut.defaultDictation
        let control = CGEventFlags.maskControl.rawValue
        let shift = CGEventFlags.maskShift.rawValue

        XCTAssertEqual(
            HotKeyChordBuilder.pressSteps(for: shortcut),
            [
                HotKeyEventStep(keyCode: 59, keyDown: true, flagsRawValue: control),
                HotKeyEventStep(keyCode: 56, keyDown: true, flagsRawValue: control | shift),
                HotKeyEventStep(keyCode: 2, keyDown: true, flagsRawValue: control | shift)
            ]
        )
        XCTAssertEqual(
            HotKeyChordBuilder.releaseSteps(for: shortcut),
            [
                HotKeyEventStep(keyCode: 2, keyDown: false, flagsRawValue: control | shift),
                HotKeyEventStep(keyCode: 56, keyDown: false, flagsRawValue: control),
                HotKeyEventStep(keyCode: 59, keyDown: false, flagsRawValue: 0)
            ]
        )
    }

    func testFacingTriggersOpenOnlyAfterContinuousDelay() {
        var machine = FacingStateMachine()

        XCTAssertNil(machine.update(visualState: .facing, now: 10.0, openDelay: 1.0, closeDelay: 3.0))
        XCTAssertNil(machine.update(visualState: .facing, now: 10.9, openDelay: 1.0, closeDelay: 3.0))
        XCTAssertEqual(machine.update(visualState: .facing, now: 11.0, openDelay: 1.0, closeDelay: 3.0), .open)

        machine.acknowledgeCurrentSegment()
        XCTAssertNil(machine.update(visualState: .facing, now: 12.0, openDelay: 1.0, closeDelay: 3.0))
    }

    func testAwayUncertainAndNoFaceShareOneContinuousCloseTimer() {
        var machine = FacingStateMachine()

        XCTAssertNil(machine.update(visualState: .away, now: 20.0, openDelay: 1.0, closeDelay: 3.0))
        XCTAssertNil(machine.update(visualState: .uncertain, now: 21.0, openDelay: 1.0, closeDelay: 3.0))
        XCTAssertNil(machine.update(visualState: .noFace, now: 22.9, openDelay: 1.0, closeDelay: 3.0))
        XCTAssertEqual(machine.update(visualState: .uncertain, now: 23.0, openDelay: 1.0, closeDelay: 3.0), .close)
    }

    func testUncertainCancelsOpeningAndStartsClosingTimer() {
        var machine = FacingStateMachine()

        XCTAssertNil(machine.update(visualState: .facing, now: 30.0, openDelay: 1.0, closeDelay: 3.0))
        XCTAssertNil(machine.update(visualState: .uncertain, now: 30.8, openDelay: 1.0, closeDelay: 3.0))
        XCTAssertEqual(machine.progress.kind, .closing)
        XCTAssertEqual(machine.progress.fraction, 0, accuracy: 0.0001)
        XCTAssertNil(machine.update(visualState: .facing, now: 31.0, openDelay: 1.0, closeDelay: 3.0))
        XCTAssertNil(machine.update(visualState: .facing, now: 31.9, openDelay: 1.0, closeDelay: 3.0))
        XCTAssertEqual(machine.update(visualState: .facing, now: 32.0, openDelay: 1.0, closeDelay: 3.0), .open)
    }

    func testProgressUsesMonotonicTimestampsAndClamps() {
        var machine = FacingStateMachine()

        _ = machine.update(visualState: .facing, now: 100.0, openDelay: 2.0, closeDelay: 3.0)
        _ = machine.update(visualState: .facing, now: 101.0, openDelay: 2.0, closeDelay: 3.0)
        XCTAssertEqual(machine.progress.kind, .opening)
        XCTAssertEqual(machine.progress.fraction, 0.5, accuracy: 0.0001)

        _ = machine.update(visualState: .facing, now: 99.0, openDelay: 2.0, closeDelay: 3.0)
        XCTAssertEqual(machine.progress.fraction, 0, accuracy: 0.0001)
    }

    func testShortcutRequiresModifierAndWarnsAboutCommandSpace() {
        let unsafe = KeyboardShortcut(keyCode: 0, modifiersRawValue: 0, keyLabel: "A")
        XCTAssertFalse(unsafe.isValidForAutomation)

        let optionSpace = KeyboardShortcut(
            keyCode: 49,
            modifiersRawValue: CGEventFlags.maskAlternate.rawValue,
            keyLabel: "Space"
        )
        XCTAssertTrue(optionSpace.isValidForAutomation)
        XCTAssertEqual(optionSpace.displayName, "⌥SPACE")
        XCTAssertNil(optionSpace.warningMessage)

        let commandSpace = KeyboardShortcut(
            keyCode: 49,
            modifiersRawValue: CGEventFlags.maskCommand.rawValue,
            keyLabel: "Space"
        )
        XCTAssertNotNil(commandSpace.warningMessage)
    }

    @MainActor
    func testSettingsDefaultsAndSanitizesPersistedValues() throws {
        let suiteName = "FaceToTalkTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.openDelay, 1.0)
        XCTAssertEqual(settings.closeDelay, 3.0)
        XCTAssertEqual(settings.hotKeyMode, .toggle)

        settings.openDelay = 2.4
        settings.closeDelay = 4.6
        settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.openDelay, 2.4)
        XCTAssertEqual(settings.closeDelay, 4.6)

        defaults.set(Double.nan, forKey: "openDelay")
        defaults.set(99.0, forKey: "closeDelay")
        settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.openDelay, 1.0)
        XCTAssertEqual(settings.closeDelay, 10.0)

        defaults.set(HotKeyMode.pressAndHold.rawValue, forKey: "hotKeyMode")
        settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.hotKeyMode, .pressAndHold)
    }
}
