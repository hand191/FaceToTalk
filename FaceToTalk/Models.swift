import AppKit
import CoreGraphics
import Foundation

enum VisualState: Equatable, Sendable {
    case starting
    case facing
    case away
    case noFace
    case uncertain
    case interrupted
    case unavailable

    var label: String {
        switch self {
        case .starting: "正在启动摄像头"
        case .facing: "Facing · 正朝向屏幕"
        case .away: "Away · 已转开"
        case .noFace: "未检测到人脸"
        case .uncertain: "角度数据不足 · 按转开处理"
        case .interrupted: "摄像头已中断"
        case .unavailable: "摄像头不可用"
        }
    }

    var symbolName: String {
        switch self {
        case .facing: "face.smiling"
        case .away: "person.crop.circle.badge.xmark"
        case .noFace: "person.slash"
        case .uncertain: "questionmark.circle"
        case .starting: "camera"
        case .interrupted: "pause.circle"
        case .unavailable: "camera.fill.badge.xmark"
        }
    }
}

struct VisionSample: Sendable {
    let state: VisualState
    let yaw: Double?
    let pitch: Double?
    let timestamp: TimeInterval
}

enum CameraPermissionState: Equatable, Sendable {
    case notDetermined
    case allowed
    case denied
    case restricted

    var label: String {
        switch self {
        case .notDetermined: "尚未请求"
        case .allowed: "已允许"
        case .denied: "已拒绝"
        case .restricted: "受系统限制"
        }
    }
}

enum CameraEvent: Sendable {
    case permission(CameraPermissionState)
    case starting
    case running
    case sample(VisionSample)
    case interrupted(String)
    case failed(String)
}

enum AutomationAction: Equatable, Sendable {
    case open
    case close
}

enum ControlMode: String, CaseIterable, Identifiable, Sendable {
    case codexShortcut
    case systemMicrophone

    var id: String { rawValue }

    var label: String {
        switch self {
        case .codexShortcut: "Codex 快捷键"
        case .systemMicrophone: "系统麦克风"
        }
    }

    var explanation: String {
        switch self {
        case .codexShortcut:
            "正对和转开时发送配置的快捷键，不改变系统麦克风。"
        case .systemMicrophone:
            "正对屏幕时启用系统麦克风，转开、侧脸或无人脸时禁用；不会发送快捷键。"
        }
    }
}

enum SystemMicrophoneState: Equatable, Sendable {
    case unknown
    case muted
    case unmuted
    case unavailable(String)

    var label: String {
        switch self {
        case .unknown: "尚未读取"
        case .muted: "已禁用（静音）"
        case .unmuted: "已启用"
        case .unavailable: "不可用"
        }
    }

    var explanation: String {
        switch self {
        case .unknown: "尚未读取默认输入设备状态"
        case .muted: "默认输入设备当前已禁用（静音）"
        case .unmuted: "默认输入设备当前可接收声音"
        case .unavailable(let reason): reason
        }
    }

    var isAvailable: Bool {
        if case .unavailable = self { return false }
        return self != .unknown
    }
}

enum ProgressKind: Equatable, Sendable {
    case idle
    case opening
    case closing
}

struct FacingProgress: Equatable, Sendable {
    let kind: ProgressKind
    let fraction: Double
    let elapsed: TimeInterval
    let target: TimeInterval

    static let idle = FacingProgress(kind: .idle, fraction: 0, elapsed: 0, target: 0)
}

enum VoiceAssumption: String, Sendable {
    case assumedOff
    case assumedOn
    case unknown

    var label: String {
        switch self {
        case .assumedOff: "推测关闭"
        case .assumedOn: "推测开启"
        case .unknown: "未知"
        }
    }

    var explanation: String {
        switch self {
        case .assumedOff: "基于你最近一次确认或本应用发送的快捷键"
        case .assumedOn: "快捷键已发送，但 Codex 没有提供接收回执"
        case .unknown: "Toggle 模式下不会自动猜测；请先重新同步"
        }
    }
}

enum HotKeyMode: String, CaseIterable, Identifiable, Sendable {
    case toggle
    case pressAndHold

    var id: String { rawValue }

    var label: String {
        switch self {
        case .toggle: "按一下切换（双向各触发一次）"
        case .pressAndHold: "按住说话（key-down / key-up）"
        }
    }
}

struct KeyboardShortcut: Codable, Equatable, Sendable {
    var keyCode: UInt16
    var modifiersRawValue: UInt64
    var keyLabel: String

    static let defaultDictation = KeyboardShortcut(
        keyCode: 2,
        modifiersRawValue: CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue,
        keyLabel: "D"
    )

    var eventFlags: CGEventFlags {
        CGEventFlags(rawValue: modifiersRawValue)
    }

    static let supportedModifierFlags: CGEventFlags = [
        .maskControl,
        .maskAlternate,
        .maskShift,
        .maskCommand
    ]

    var hasSupportedModifier: Bool {
        !eventFlags.intersection(Self.supportedModifierFlags).isEmpty
    }

    var isValidForAutomation: Bool {
        hasSupportedModifier && keyCode != 53 && !keyLabel.isEmpty
    }

    var warningMessage: String? {
        guard keyCode == 49 else { return nil }
        let modifiers = eventFlags.intersection(Self.supportedModifierFlags)
        if modifiers == .maskCommand {
            return "⌘Space 通常会被 Spotlight 拦截，建议改用 ⌥Space 或 ⌃⇧D。"
        }
        if modifiers == .maskControl {
            return "⌃Space 常用于切换输入法，可能无法送达 Codex。"
        }
        return nil
    }

    var displayName: String {
        modifierGlyphs + keyLabel.uppercased()
    }

    private var modifierGlyphs: String {
        let flags = eventFlags
        var result = ""
        if flags.contains(.maskControl) { result += "⌃" }
        if flags.contains(.maskAlternate) { result += "⌥" }
        if flags.contains(.maskShift) { result += "⇧" }
        if flags.contains(.maskCommand) { result += "⌘" }
        return result
    }

    static func modifiers(from flags: NSEvent.ModifierFlags) -> UInt64 {
        var result: UInt64 = 0
        if flags.contains(.control) { result |= CGEventFlags.maskControl.rawValue }
        if flags.contains(.option) { result |= CGEventFlags.maskAlternate.rawValue }
        if flags.contains(.shift) { result |= CGEventFlags.maskShift.rawValue }
        if flags.contains(.command) { result |= CGEventFlags.maskCommand.rawValue }
        return result
    }

    static func keyLabel(for event: NSEvent) -> String {
        switch event.keyCode {
        case 36: return "Return"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Delete"
        case 117: return "Forward Delete"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            let characters = event.charactersIgnoringModifiers?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (characters?.isEmpty == false ? characters! : "Key \(event.keyCode)").uppercased()
        }
    }
}

enum TargetApplication {
    static let bundleIdentifiers: Set<String> = [
        "com.openai.codex",
        "com.openai.chat",
        "com.openai.chatgpt"
    ]
}
