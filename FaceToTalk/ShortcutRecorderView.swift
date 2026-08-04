import AppKit
import SwiftUI

@MainActor
private final class ShortcutCaptureController: ObservableObject {
    @Published var isRecording = false
    @Published var validationMessage: String?
    private var monitor: Any?

    func begin(onCapture: @escaping (KeyboardShortcut) -> Void) {
        stop()
        validationMessage = nil
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                self.validationMessage = "已取消录制"
                self.stop()
                return nil
            }
            guard !event.isARepeat else { return nil }

            let rawModifiers = KeyboardShortcut.modifiers(from: event.modifierFlags)
            guard rawModifiers != 0 else {
                self.validationMessage = "请至少按住 ⌃、⌥、⇧、⌘ 中的一个，避免误触单键。"
                return nil
            }

            let shortcut = KeyboardShortcut(
                keyCode: event.keyCode,
                modifiersRawValue: rawModifiers,
                keyLabel: KeyboardShortcut.keyLabel(for: event)
            )
            self.validationMessage = nil
            onCapture(shortcut)
            self.stop()
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
    }

}

struct ShortcutRecorderView: View {
    let shortcut: KeyboardShortcut
    let onCapture: (KeyboardShortcut) -> Void
    @StateObject private var controller = ShortcutCaptureController()

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button(controller.isRecording ? "请按新的组合键（Esc 取消）" : shortcut.displayName) {
                controller.begin(onCapture: onCapture)
            }
            .buttonStyle(.bordered)

            if let validationMessage = controller.validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear {
            controller.stop()
        }
    }
}
