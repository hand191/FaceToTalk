import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    let settings: SettingsStore

    @Published private(set) var visualState: VisualState = .starting
    @Published private(set) var progress: FacingProgress = .idle
    @Published private(set) var voiceAssumption: VoiceAssumption = .unknown
    @Published private(set) var systemMicrophoneState: SystemMicrophoneState = .unknown
    @Published private(set) var cameraPermission: CameraPermissionState = .notDetermined
    @Published private(set) var keyboardPermissionGranted = false
    @Published private(set) var yaw: Double?
    @Published private(set) var pitch: Double?
    @Published private(set) var cameraStatus = "尚未启动"
    @Published private(set) var actionStatus = "请先确认当前语音输入为关闭状态"
    @Published private(set) var frontmostBundleIdentifier: String?
    @Published private(set) var actionInFlight = false

    private let camera = VisionCameraService()
    private let hotKey = HotKeyController()
    private let systemMicrophone = SystemMicrophoneController()
    private var stateMachine = FacingStateMachine()
    private var lifecycleTokens: [NSObjectProtocol] = []
    private var refreshTimer: Timer?
    private var lastLoggedVisualState: VisualState?
    private var systemMicrophoneArmed = false
    #if DEBUG
    private var diagnosticWindow: NSWindow?
    #endif

    init(settings: SettingsStore = SettingsStore()) {
        self.settings = settings
        camera.updateFacingAngleThresholds(settings.facingAngleThresholds)
        camera.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleCameraEvent(event)
            }
        }
        installLifecycleObservers()
        refreshEnvironment()
        debugTrace("keyboard post-event access = \(keyboardPermissionGranted ? "allowed" : "not allowed")")

        if settings.masterEnabled {
            if settings.controlMode == .systemMicrophone {
                beginFailClosedMicrophoneSession(
                    successMessage: "系统麦克风先保持禁用（静音）；确认正对屏幕后才启用"
                )
            }
            camera.start()
        } else {
            visualState = .interrupted
            cameraStatus = "总开关已关闭"
        }

        #if DEBUG
        if CommandLine.arguments.contains("--diagnostic-request-keyboard") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(800))
                self?.requestKeyboardPermission()
            }
        }
        if CommandLine.arguments.contains("--diagnostic-test-hold") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.refreshEnvironment()
                self.debugTrace("diagnostic target = \(self.frontmostBundleIdentifier ?? "none")")
                self.testHoldDown()
                try? await Task.sleep(for: .seconds(1))
                self.testHoldRelease()
                self.debugTrace("diagnostic hold result = \(self.actionStatus)")
            }
        }
        if CommandLine.arguments.contains("--diagnostic-window") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                self?.showDiagnosticWindow()
            }
        }
        #endif
    }

    var menuIcon: String {
        guard settings.masterEnabled else { return "face.dashed" }
        return switch visualState {
        case .facing: "face.smiling.inverse"
        case .away, .noFace: "face.dashed"
        case .starting, .uncertain: "face.smiling"
        case .interrupted, .unavailable: "exclamationmark.triangle"
        }
    }

    var angleDescription: String {
        guard let yaw, let pitch else { return "yaw / pitch：—" }
        return String(format: "yaw %.1f° · pitch %.1f°", yaw * 180 / .pi, pitch * 180 / .pi)
    }

    var progressDescription: String {
        switch progress.kind {
        case .idle:
            return "等待连续稳定状态"
        case .opening:
            return String(format: "朝向计时 %.1f / %.1f 秒", min(progress.elapsed, progress.target), progress.target)
        case .closing:
            return String(format: "转开计时 %.1f / %.1f 秒", min(progress.elapsed, progress.target), progress.target)
        }
    }

    var isTargetForeground: Bool {
        guard let frontmostBundleIdentifier else { return false }
        return TargetApplication.bundleIdentifiers.contains(frontmostBundleIdentifier)
    }

    var targetStatus: String {
        if settings.controlMode == .systemMicrophone {
            return "系统麦克风模式 · 不检查前台应用"
        }
        if !settings.restrictToTarget { return "已允许全局发送" }
        if isTargetForeground { return "Codex / ChatGPT 位于前台" }
        return "等待 Codex / ChatGPT 回到前台"
    }

    var voiceExplanation: String {
        if settings.controlMode == .systemMicrophone {
            return systemMicrophoneState.explanation
        }
        if voiceAssumption == .unknown, settings.hotKeyMode == .pressAndHold {
            return "当前 Codex 使用 key-down / key-up；状态仍无应用回执"
        }
        return voiceAssumption.explanation
    }

    var controlStatusTitle: String {
        settings.controlMode == .codexShortcut ? "Codex 语音状态" : "系统麦克风"
    }

    var controlStatusLabel: String {
        settings.controlMode == .codexShortcut ? voiceAssumption.label : systemMicrophoneState.label
    }

    var controlStatusNeedsAttention: Bool {
        if settings.controlMode == .codexShortcut {
            return voiceAssumption == .unknown
        }
        return !systemMicrophoneState.isAvailable
    }

    var headerSubtitle: String {
        settings.controlMode == .codexShortcut ? "只看朝向，只发快捷键" : "只看朝向，只控系统麦克风"
    }

    func setMasterEnabled(_ enabled: Bool) {
        guard settings.masterEnabled != enabled else { return }
        settings.masterEnabled = enabled
        resetTiming()

        if enabled {
            visualState = .starting
            cameraStatus = "正在启动摄像头"
            if settings.controlMode == .systemMicrophone {
                beginFailClosedMicrophoneSession(
                    successMessage: "自动控制已启用；麦克风先保持禁用（静音），确认正对后才启用"
                )
            } else {
                actionStatus = voiceAssumption == .unknown
                    ? "请先确认当前语音输入为关闭状态"
                    : "自动控制已启用"
            }
            camera.start()
        } else {
            systemMicrophoneArmed = false
            camera.stop()
            visualState = .interrupted
            cameraStatus = "总开关已关闭"
            enterSafetyState(reason: "总开关已关闭", attemptToggleClose: true)
        }
    }

    func timingSettingsChanged() {
        resetTiming()
        actionStatus = "计时设置已更新，连续计时已重置"
    }

    func facingAngleSettingsChanged() {
        camera.updateFacingAngleThresholds(settings.facingAngleThresholds)
        resetTiming()
        actionStatus = "头部角度设置已更新，连续计时已重置"
    }

    func updateShortcut(_ shortcut: KeyboardShortcut) {
        _ = hotKey.releaseHeldKey()
        settings.updateShortcut(shortcut)
        voiceAssumption = .unknown
        resetTiming()
        actionStatus = "快捷键已更改；请在 Codex 中测试后重新同步"
    }

    func hotKeyModeChanged() {
        _ = hotKey.releaseHeldKey()
        voiceAssumption = .unknown
        resetTiming()
        actionStatus = "快捷键语义已更改；请测试后重新同步"
    }

    func setControlMode(_ newMode: ControlMode) {
        guard newMode != settings.controlMode else { return }

        if settings.controlMode == .systemMicrophone {
            systemMicrophoneArmed = false
            let restore = systemMicrophone.restoreOriginalState()
            systemMicrophoneState = restore.state
            guard restore.succeeded else {
                actionStatus = "无法切换模式：\(restore.message)"
                return
            }
        }

        guard hotKey.releaseHeldKey() else {
            actionStatus = "无法切换模式：请先恢复键盘事件权限并释放按键"
            return
        }
        settings.controlMode = newMode
        resetTiming()

        if newMode == .systemMicrophone {
            if settings.masterEnabled {
                beginFailClosedMicrophoneSession(
                    successMessage: "已切换为系统麦克风模式；当前先保持禁用（静音），确认正对后才启用"
                )
            } else {
                systemMicrophoneState = systemMicrophone.currentState()
                actionStatus = "已切换为系统麦克风模式；打开总开关后开始控制"
            }
        } else {
            voiceAssumption = .unknown
            actionStatus = "已切换为 Codex 快捷键模式；请重新同步"
        }
        refreshEnvironment()
    }

    func targetRestrictionChanged() {
        resetTiming()
        refreshEnvironment()
        actionStatus = "前台限制已更新，连续计时已重置"
    }

    func confirmCurrentlyOff() {
        guard settings.controlMode == .codexShortcut else { return }
        _ = hotKey.releaseHeldKey()
        voiceAssumption = .assumedOff
        resetTiming()
        actionStatus = "已重新同步为关闭；等待连续 Facing"
    }

    func requestKeyboardPermission() {
        keyboardPermissionGranted = hotKey.requestPostEventAccess()
        refreshEnvironment()
        debugTrace("keyboard permission request result = \(keyboardPermissionGranted ? "allowed" : "not allowed")")
        actionStatus = keyboardPermissionGranted
            ? "键盘事件权限已允许"
            : "系统尚未授予键盘事件权限；请按系统提示完成设置"
    }

    func openCameraPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
        NSWorkspace.shared.open(url)
    }

    func openKeyboardPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func openSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        // SettingsLink requires macOS 14. These responder-chain actions keep
        // the SwiftUI Settings scene reachable on macOS 13.3 and newer.
        let selectors = ["showSettingsWindow:", "showPreferencesWindow:"]
        for selectorName in selectors {
            if NSApplication.shared.sendAction(
                NSSelectorFromString(selectorName),
                to: nil,
                from: nil
            ) {
                return
            }
        }

        actionStatus = "未能打开设置窗口，请退出并重新启动 FaceToTalk 后再试"
    }

    func testShortcutTap() {
        guard !actionInFlight else { return }
        refreshEnvironment()
        guard canPostToConfiguredTarget() else { return }

        actionInFlight = true
        actionStatus = "正在发送测试快捷键…"
        Task { @MainActor [weak self] in
            guard let self else { return }
            let posted = await self.hotKey.tap(self.settings.shortcut)
            self.actionInFlight = false
            self.keyboardPermissionGranted = self.hotKey.hasPostEventAccess
            if posted {
                switch self.voiceAssumption {
                case .assumedOff: self.voiceAssumption = .assumedOn
                case .assumedOn: self.voiceAssumption = .assumedOff
                case .unknown: break
                }
                self.actionStatus = "测试快捷键已发送；请观察 Codex 是否响应"
            } else {
                self.actionStatus = "快捷键未发送，请先授予键盘事件权限"
            }
        }
    }

    func testHoldDown() {
        refreshEnvironment()
        guard canPostToConfiguredTarget() else { return }
        if hotKey.press(settings.shortcut) {
            voiceAssumption = .assumedOn
            actionStatus = "已发送 key-down；说完后务必点“释放测试按键”"
            debugTrace("test key-down posted: \(settings.shortcut.displayName)")
        } else {
            actionStatus = "key-down 未发送；请检查权限或先释放上一次按键"
            debugTrace("test key-down blocked: \(actionStatus)")
        }
    }

    func testHoldRelease() {
        let posted = hotKey.releaseHeldKey()
        voiceAssumption = posted ? .assumedOff : .unknown
        actionStatus = posted
            ? "已发送 key-up；请确认 Codex 是否停止"
            : "key-up 未能确认发送，状态已设为未知"
        debugTrace("test key-up \(posted ? "posted" : "failed"): \(settings.shortcut.displayName)")
    }

    func setSystemMicrophoneMuted(_ muted: Bool) {
        guard settings.controlMode == .systemMicrophone else { return }
        let result = systemMicrophone.setMuted(muted)
        systemMicrophoneState = result.state
        if muted {
            systemMicrophoneArmed = result.succeeded && result.state == .muted
        }
        actionStatus = result.message
        resetTiming()
    }

    func quit() {
        systemMicrophoneArmed = false
        camera.stop()
        _ = hotKey.releaseHeldKey()
        let restore = systemMicrophone.restoreOriginalState()
        systemMicrophoneState = restore.state
        NSApplication.shared.terminate(nil)
    }

    private func handleCameraEvent(_ event: CameraEvent) {
        switch event {
        case .permission(let permission):
            cameraPermission = permission
            debugTrace("camera permission = \(permission.label)")
        case .starting:
            visualState = .starting
            cameraStatus = "正在启动低分辨率视频分析"
            resetTiming()
            debugTrace("camera session starting")
        case .running:
            cameraStatus = "本地分析中 · 约 8 次/秒"
            debugTrace("camera session running")
        case .sample(let sample):
            handleVisionSample(sample)
        case .interrupted(let reason):
            visualState = .interrupted
            cameraStatus = reason
            debugTrace("camera interrupted: \(reason)")
            enterSafetyState(
                reason: reason,
                attemptToggleClose: true,
                keepSystemMicrophoneMuted: true
            )
        case .failed(let message):
            visualState = .unavailable
            cameraStatus = message
            debugTrace("camera failed: \(message)")
            enterSafetyState(
                reason: message,
                attemptToggleClose: true,
                keepSystemMicrophoneMuted: true
            )
        }
    }

    private func handleVisionSample(_ sample: VisionSample) {
        guard settings.masterEnabled else { return }
        visualState = sample.state
        yaw = sample.yaw
        pitch = sample.pitch
        if sample.state != lastLoggedVisualState {
            lastLoggedVisualState = sample.state
            debugTrace("visual state = \(sample.state.label), \(angleDescription)")
        }
        refreshFrontmostApplication()

        if settings.controlMode == .codexShortcut,
           settings.restrictToTarget && !isTargetForeground {
            stateMachine.reset()
            progress = .idle
            return
        }

        let action = stateMachine.update(
            visualState: sample.state,
            now: sample.timestamp,
            openDelay: settings.openDelay,
            closeDelay: settings.closeDelay
        )
        progress = stateMachine.progress

        if let action {
            attemptAutomationAction(action)
        }
    }

    private func attemptAutomationAction(_ action: AutomationAction) {
        guard !actionInFlight else { return }

        if settings.controlMode == .systemMicrophone {
            attemptSystemMicrophoneAction(action)
            return
        }

        switch settings.hotKeyMode {
        case .toggle:
            attemptToggleAction(action)
        case .pressAndHold:
            attemptHoldAction(action)
        }
    }

    private func attemptSystemMicrophoneAction(_ action: AutomationAction) {
        let shouldMute = action == .close
        guard shouldMute || systemMicrophoneArmed else {
            actionStatus = "尚未确认麦克风已安全关闭，因此不会自动启用"
            return
        }
        let alreadyDesired = (shouldMute && systemMicrophoneState == .muted)
            || (!shouldMute && systemMicrophoneState == .unmuted)
        if alreadyDesired {
            if shouldMute {
                systemMicrophoneArmed = true
            }
            stateMachine.acknowledgeCurrentSegment()
            return
        }

        let result = systemMicrophone.setMuted(shouldMute)
        systemMicrophoneState = result.state
        if shouldMute {
            systemMicrophoneArmed = result.succeeded && result.state == .muted
        }
        actionStatus = result.message
        if result.succeeded {
            stateMachine.acknowledgeCurrentSegment()
        }
    }

    private func attemptToggleAction(_ action: AutomationAction) {
        let alreadyDesired = (action == .open && voiceAssumption == .assumedOn)
            || (action == .close && voiceAssumption == .assumedOff)
        if alreadyDesired {
            stateMachine.acknowledgeCurrentSegment()
            return
        }

        guard voiceAssumption != .unknown else {
            actionStatus = "状态未知：请点“我已确认当前关闭 / 重新同步”"
            return
        }
        guard canPostToConfiguredTarget() else { return }

        actionInFlight = true
        actionStatus = action == .open ? "正在发送打开快捷键…" : "正在发送关闭快捷键…"
        Task { @MainActor [weak self] in
            guard let self else { return }
            let posted = await self.hotKey.tap(self.settings.shortcut)
            self.actionInFlight = false
            self.keyboardPermissionGranted = self.hotKey.hasPostEventAccess
            guard posted else {
                self.voiceAssumption = .unknown
                self.actionStatus = "快捷键未发送，状态已设为未知"
                return
            }
            self.voiceAssumption = action == .open ? .assumedOn : .assumedOff
            self.stateMachine.acknowledgeCurrentSegment()
            self.actionStatus = action == .open
                ? "已发送打开快捷键（无 Codex 回执）"
                : "已发送关闭快捷键（无 Codex 回执）"
        }
    }

    private func attemptHoldAction(_ action: AutomationAction) {
        switch action {
        case .open:
            if voiceAssumption == .assumedOn, hotKey.heldShortcut != nil {
                stateMachine.acknowledgeCurrentSegment()
                return
            }
            guard canPostToConfiguredTarget() else { return }
            if hotKey.press(settings.shortcut) {
                voiceAssumption = .assumedOn
                stateMachine.acknowledgeCurrentSegment()
                actionStatus = "已发送 key-down（无 Codex 回执）"
            } else {
                voiceAssumption = .unknown
                actionStatus = "key-down 未发送，状态已设为未知"
            }
        case .close:
            let posted = hotKey.heldShortcut != nil
                ? hotKey.releaseHeldKey()
                : hotKey.sendKeyUp(settings.shortcut)
            voiceAssumption = posted ? .assumedOff : .unknown
            if posted {
                stateMachine.acknowledgeCurrentSegment()
                actionStatus = "已发送 key-up（无 Codex 回执）"
            } else {
                actionStatus = "key-up 未发送，状态已设为未知"
            }
        }
    }

    private func canPostToConfiguredTarget() -> Bool {
        keyboardPermissionGranted = hotKey.hasPostEventAccess
        guard keyboardPermissionGranted else {
            actionStatus = "缺少键盘事件权限，未发送快捷键"
            return false
        }
        guard !settings.restrictToTarget || isTargetForeground else {
            actionStatus = "Codex / ChatGPT 不在前台，未发送快捷键"
            return false
        }
        return true
    }

    private func enterSafetyState(
        reason: String,
        attemptToggleClose: Bool,
        keepSystemMicrophoneMuted: Bool = false
    ) {
        resetTiming()

        if settings.controlMode == .systemMicrophone {
            if keepSystemMicrophoneMuted, settings.masterEnabled {
                let result = systemMicrophone.setMuted(true)
                systemMicrophoneState = result.state
                systemMicrophoneArmed = result.succeeded && result.state == .muted
                actionStatus = result.succeeded
                    ? "安全关闭：检测不可用，系统麦克风已禁用（静音）"
                    : "无法确认安全静音：\(result.message)"
                return
            }
            systemMicrophoneArmed = false
            let restore = systemMicrophone.restoreOriginalState()
            systemMicrophoneState = restore.state
            actionStatus = restore.succeeded ? "安全重置：\(restore.message)" : restore.message
            return
        }

        if settings.hotKeyMode == .pressAndHold {
            let released = hotKey.releaseHeldKey()
            voiceAssumption = released ? .assumedOff : .unknown
            actionStatus = released ? "安全重置：已释放按键" : "安全重置：按键释放未确认"
            return
        }

        guard attemptToggleClose,
              voiceAssumption == .assumedOn,
              !actionInFlight,
              hotKey.hasPostEventAccess else {
            if voiceAssumption == .assumedOn {
                voiceAssumption = .unknown
            }
            actionStatus = "安全重置：\(reason)"
            return
        }

        refreshFrontmostApplication()
        guard !settings.restrictToTarget || isTargetForeground else {
            voiceAssumption = .unknown
            actionStatus = "安全重置：目标不在前台，语音状态改为未知"
            return
        }

        actionInFlight = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let posted = await self.hotKey.tap(self.settings.shortcut)
            self.actionInFlight = false
            self.voiceAssumption = posted ? .assumedOff : .unknown
            self.actionStatus = posted
                ? "安全重置：已发送关闭快捷键"
                : "安全重置：关闭快捷键未发送，状态未知"
        }
    }

    private func resetTiming() {
        stateMachine.reset()
        progress = .idle
        yaw = nil
        pitch = nil
    }

    private func installLifecycleObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        lifecycleTokens.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refreshFrontmostApplication()
                if self.settings.controlMode == .codexShortcut,
                   self.settings.restrictToTarget && !self.isTargetForeground {
                    self.stateMachine.reset()
                    self.progress = .idle
                }
            }
        })

        let safetyNotifications: [Notification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification
        ]
        for name in safetyNotifications {
            lifecycleTokens.append(workspaceCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.camera.stop()
                    self.visualState = .interrupted
                    self.cameraStatus = "系统睡眠、锁屏或会话停用"
                    self.enterSafetyState(
                        reason: "睡眠、锁屏或会话停用",
                        attemptToggleClose: false,
                        keepSystemMicrophoneMuted: true
                    )
                }
            })
        }

        let resumeNotifications: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ]
        for name in resumeNotifications {
            lifecycleTokens.append(workspaceCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.settings.masterEnabled else { return }
                    self.resetTiming()
                    if self.settings.controlMode == .systemMicrophone {
                        self.beginFailClosedMicrophoneSession(
                            successMessage: "系统已恢复；麦克风先保持禁用（静音），确认正对后才启用"
                        )
                    }
                    self.visualState = .starting
                    self.cameraStatus = "系统已恢复，正在重启摄像头"
                    self.camera.start()
                }
            })
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshEnvironment()
            }
        }

        lifecycleTokens.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                _ = self.hotKey.releaseHeldKey()
                _ = self.systemMicrophone.restoreOriginalState()
            }
        })
    }

    private func refreshEnvironment() {
        cameraPermission = camera.currentPermission()
        keyboardPermissionGranted = hotKey.hasPostEventAccess
        if settings.controlMode == .systemMicrophone {
            systemMicrophoneState = systemMicrophone.currentState()
        }
        refreshFrontmostApplication()
    }

    private func beginFailClosedMicrophoneSession(successMessage: String) {
        systemMicrophoneArmed = false
        let sessionState = systemMicrophone.beginSession()
        systemMicrophoneState = sessionState
        guard sessionState.isAvailable else {
            actionStatus = sessionState.explanation
            return
        }

        let result = systemMicrophone.setMuted(true)
        systemMicrophoneState = result.state
        systemMicrophoneArmed = result.succeeded && result.state == .muted
        actionStatus = result.succeeded
            ? successMessage
            : "无法进入默认静音状态：\(result.message)"
    }

    private func refreshFrontmostApplication() {
        frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        releaseHeldKeyIfSafetyRequiresIt()
    }

    private func releaseHeldKeyIfSafetyRequiresIt() {
        guard hotKey.heldShortcut != nil else { return }

        let targetUnavailable = settings.restrictToTarget && !isTargetForeground
        let shouldRelease = !settings.masterEnabled
            || settings.controlMode != .codexShortcut
            || settings.hotKeyMode != .pressAndHold
            || voiceAssumption != .assumedOn
            || targetUnavailable
        guard shouldRelease else { return }

        let released = hotKey.releaseHeldKey()
        voiceAssumption = released ? .assumedOff : .unknown
        stateMachine.reset()
        progress = .idle
        actionStatus = released
            ? "安全重置：目标离开前台，已释放按键"
            : "安全重置：等待权限恢复后重试释放按键"
    }

    private func debugTrace(_ message: String) {
        #if DEBUG
        print("[FaceToTalk] \(message)")
        #endif
    }

    #if DEBUG
    private func showDiagnosticWindow() {
        let panel = MenuPanel(model: self, settings: settings)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "FaceToTalk Diagnostics"
        window.contentView = NSHostingView(rootView: panel)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        diagnosticWindow = window
    }
    #endif
}
