import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("连续计时") {
                LabeledContent("朝向后打开") {
                    HStack {
                        Slider(value: Binding(
                            get: { settings.openDelay },
                            set: {
                                settings.openDelay = $0
                                model.timingSettingsChanged()
                            }
                        ), in: TimingSettings.openDelayRange, step: 0.1)
                        .frame(width: 220)
                        Text(settings.openDelay, format: .number.precision(.fractionLength(1)))
                            .monospacedDigit()
                        Text("秒")
                    }
                }

                LabeledContent("转开、角度不足或无人脸后关闭") {
                    HStack {
                        Slider(value: Binding(
                            get: { settings.closeDelay },
                            set: {
                                settings.closeDelay = $0
                                model.timingSettingsChanged()
                            }
                        ), in: TimingSettings.closeDelayRange, step: 0.1)
                        .frame(width: 220)
                        Text(settings.closeDelay, format: .number.precision(.fractionLength(1)))
                            .monospacedDigit()
                        Text("秒")
                    }
                }

                HStack {
                    Spacer()
                    Button("恢复默认 1.0 秒 / 3.0 秒") {
                        settings.restoreTimingDefaults()
                        model.timingSettingsChanged()
                    }
                }
            }

            Section("Dictation 快捷键") {
                LabeledContent("组合键") {
                    ShortcutRecorderView(shortcut: settings.shortcut) {
                        model.updateShortcut($0)
                    }
                }

                Text("点击当前组合键，再按下新的组合键。为避免误触，必须包含至少一个修饰键。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let warningMessage = settings.shortcut.warningMessage {
                    Text(warningMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                HStack {
                    Spacer()
                    Button("恢复推荐快捷键 ⌃⇧D") {
                        model.updateShortcut(.defaultDictation)
                    }
                }

                Picker("快捷键语义", selection: Binding(
                    get: { settings.hotKeyMode },
                    set: {
                        settings.hotKeyMode = $0
                        model.hotKeyModeChanged()
                    }
                )) {
                    ForEach(HotKeyMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Toggle("仅当 Codex / ChatGPT 位于前台时自动发送", isOn: Binding(
                    get: { settings.restrictToTarget },
                    set: {
                        settings.restrictToTarget = $0
                        model.targetRestrictionChanged()
                    }
                ))

                Text("如果正对和转开时都要各发送一次完整快捷键，请选“按一下切换”（默认）。只有目标快捷键要求按住开始、松开停止时，才选“按住说话”。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("测试按一下") { model.testShortcutTap() }
                    Button("测试 key-down") { model.testHoldDown() }
                    Button("释放测试按键") { model.testHoldRelease() }
                }
            }

            Section("权限") {
                LabeledContent("摄像头", value: model.cameraPermission.label)
                HStack {
                    LabeledContent("键盘事件", value: model.keyboardPermissionGranted ? "已允许" : "尚未允许")
                    Button("请求权限") { model.requestKeyboardPermission() }
                    Button("打开系统设置") { model.openKeyboardPrivacySettings() }
                }
                if model.cameraPermission == .denied || model.cameraPermission == .restricted {
                    Button("打开摄像头隐私设置") { model.openCameraPrivacySettings() }
                }
            }

            Section("本地隐私边界") {
                Text("仅使用 AVFoundation 视频输入与 Vision 人脸矩形的 yaw / pitch。不会保存、上传或识别人脸身份；不请求麦克风权限、不创建音频输入、不录音。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 620, height: 590)
    }
}
