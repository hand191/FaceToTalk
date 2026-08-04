import SwiftUI

struct MenuPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            visionSection
            voiceSection
            permissionSection
            Divider()
            actions
            footer
        }
        .padding(16)
        .frame(width: 360)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("FaceToTalk")
                    .font(.headline)
                Text("只看朝向，只发快捷键")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { settings.masterEnabled },
                set: { model.setMasterEnabled($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .accessibilityLabel("总开关")
        }
    }

    private var visionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.visualState.label, systemImage: model.visualState.symbolName)
                .font(.system(.body, design: .rounded).weight(.medium))
            Text(model.angleDescription)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            ProgressView(value: model.progress.fraction)
            HStack {
                Text(model.progressDescription)
                Spacer()
                Text("\(Int(model.progress.fraction * 100))%")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            Text(model.cameraStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("语音状态")
                Spacer()
                Text(model.voiceAssumption.label)
                    .foregroundStyle(model.voiceAssumption == .unknown ? .orange : .primary)
            }
            Text(model.voiceExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(model.actionStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.targetStatus)
                .font(.caption)
                .foregroundStyle(model.settings.restrictToTarget && !model.isTargetForeground ? .orange : .secondary)
        }
    }

    private var permissionSection: some View {
        VStack(spacing: 5) {
            permissionRow(
                title: "摄像头",
                allowed: model.cameraPermission == .allowed,
                detail: model.cameraPermission.label
            )
            permissionRow(
                title: "键盘事件",
                allowed: model.keyboardPermissionGranted,
                detail: model.keyboardPermissionGranted ? "已允许" : "尚未允许"
            )
        }
    }

    private func permissionRow(title: String, allowed: Bool, detail: String) -> some View {
        HStack {
            Image(systemName: allowed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(allowed ? .green : .orange)
            Text(title)
            Spacer()
            Text(detail)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button {
                model.confirmCurrentlyOff()
            } label: {
                Label("我已确认当前关闭 / 重新同步", systemImage: "checkmark.shield")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            HStack {
                if settings.hotKeyMode == .pressAndHold {
                    Button("测试 key-down") {
                        model.testHoldDown()
                    }
                    Button("释放 key-up") {
                        model.testHoldRelease()
                    }
                } else {
                    Button("测试快捷键") {
                        model.testShortcutTap()
                    }
                }
                Button("请求键盘权限") {
                    model.requestKeyboardPermission()
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                model.openSettings()
            } label: {
                Label("设置", systemImage: "gear")
            }
            Spacer()
            Button("退出") {
                model.quit()
            }
        }
        .buttonStyle(.plain)
        .font(.caption)
    }
}
