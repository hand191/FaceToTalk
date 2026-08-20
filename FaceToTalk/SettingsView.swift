import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("控制方式") {
                Picker("自动控制", selection: Binding(
                    get: { settings.controlMode },
                    set: {
                        model.setControlMode($0)
                    }
                )) {
                    ForEach(ControlMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Text(settings.controlMode.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

            Section("头部朝向角度") {
                LabeledContent("实时判定") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(model.visualState.label)
                        Text(model.angleDescription)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                angleSlider(
                    "允许正对 · 左右",
                    value: Binding(
                        get: { settings.enterYawDegrees },
                        set: {
                            settings.updateEnterYawDegrees($0)
                            model.facingAngleSettingsChanged()
                        }
                    ),
                    range: FacingAngleSettings.enterYawRange
                )

                angleSlider(
                    "允许正对 · 上下",
                    value: Binding(
                        get: { settings.enterPitchDegrees },
                        set: {
                            settings.updateEnterPitchDegrees($0)
                            model.facingAngleSettingsChanged()
                        }
                    ),
                    range: FacingAngleSettings.enterPitchRange
                )

                angleSlider(
                    "判定转开 · 左右",
                    value: Binding(
                        get: { settings.exitYawDegrees },
                        set: {
                            settings.updateExitYawDegrees($0)
                            model.facingAngleSettingsChanged()
                        }
                    ),
                    range: ClosedRange(uncheckedBounds: (
                        lower: settings.enterYawDegrees + FacingAngleSettings.minimumHysteresis,
                        upper: FacingAngleSettings.exitYawRange.upperBound
                    ))
                )

                angleSlider(
                    "判定转开 · 上下",
                    value: Binding(
                        get: { settings.exitPitchDegrees },
                        set: {
                            settings.updateExitPitchDegrees($0)
                            model.facingAngleSettingsChanged()
                        }
                    ),
                    range: ClosedRange(uncheckedBounds: (
                        lower: settings.enterPitchDegrees + FacingAngleSettings.minimumHysteresis,
                        upper: FacingAngleSettings.exitPitchRange.upperBound
                    ))
                )

                Text("“允许正对”调大更容易启用；“判定转开”调小更容易禁用。左右角度对两侧同时生效，两组之间会保留至少 2° 防抖缓冲。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    Button("恢复标准角度 16° / 14° / 24° / 21°") {
                        settings.restoreFacingAngleDefaults()
                        model.facingAngleSettingsChanged()
                    }
                }
            }

            if settings.controlMode == .codexShortcut {
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
            } else {
                Section("系统麦克风") {
                    LabeledContent("当前状态", value: model.systemMicrophoneState.label)
                    Text(model.systemMicrophoneState.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("测试启用麦克风") { model.setSystemMicrophoneMuted(false) }
                        Button("测试禁用麦克风") { model.setSystemMicrophoneMuted(true) }
                    }

                    Text("此模式影响所有使用默认输入设备的应用。暂停、切换模式或退出 FaceToTalk 时会恢复启用本模式前的状态。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("权限") {
                LabeledContent("摄像头", value: model.cameraPermission.label)
                if settings.controlMode == .codexShortcut {
                    HStack {
                        LabeledContent("键盘事件", value: model.keyboardPermissionGranted ? "已允许" : "尚未允许")
                        Button("请求权限") { model.requestKeyboardPermission() }
                        Button("打开系统设置") { model.openKeyboardPrivacySettings() }
                    }
                } else {
                    LabeledContent("系统麦克风控制", value: model.systemMicrophoneState.label)
                }
                if model.cameraPermission == .denied || model.cameraPermission == .restricted {
                    Button("打开摄像头隐私设置") { model.openCameraPrivacySettings() }
                }
            }

            Section("本地隐私边界") {
                Text("摄像头画面只在本机由 Vision 分析。“系统麦克风”模式只修改默认输入设备的静音或输入音量，不读取音频样本、不录音，也不保存或上传声音。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 640, height: 780)
    }

    private func angleSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range, step: 1)
                    .frame(width: 220)
                Text(value.wrappedValue, format: .number.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .frame(width: 28, alignment: .trailing)
                Text("°")
            }
        }
    }
}
