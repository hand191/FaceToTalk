# FaceToTalk

FaceToTalk 是一个非官方、纯本地的 macOS 菜单栏实验应用：使用内建摄像头和 Apple Vision 判断头部是否大致朝向屏幕，再向当前前台的 Codex / ChatGPT 发送用户配置的 Dictation 快捷键。

FaceToTalk is an unofficial, local-only macOS menu bar experiment. It is not affiliated with or endorsed by OpenAI.

## 功能

- 连续朝向屏幕达到设定时间后，发送一次快捷键。
- 连续转开、未检测到人脸或角度数据不足达到设定时间后，再发送一次快捷键。
- 默认打开延迟为 1.0 秒，关闭延迟为 3.0 秒。
- 支持录制自定义组合键，并保存到本机 `UserDefaults`。
- 支持“按一下切换”和“按住说话”两种快捷键语义。
- 默认只在 Codex / ChatGPT 位于前台时发送事件。
- 菜单栏显示实时姿态、计时进度、权限状态和推测的语音状态。
- 支持 Apple Silicon 与 Intel，Deployment Target 为 macOS 13.3。

## 工作方式

```text
内建摄像头
  -> AVFoundation 低分辨率视频帧
  -> Vision 最大人脸 yaw / pitch
  -> Facing / Away / No Face / Uncertain
  -> 单调时间连续状态机
  -> CGEvent 完整组合键按下与释放
```

FaceToTalk 只判断头部大致方向，不做眼球追踪，也不识别人脸身份。

## 默认行为

- Facing 连续 1.0 秒：发送一次完整快捷键（key-down + key-up）。
- Away、无人脸或角度不足连续 3.0 秒：再次发送一次完整快捷键。
- 默认快捷键：`Ctrl+Shift+D`。
- 默认快捷键语义：按一下切换。
- 初始语音状态为 `unknown`；请先确认 Codex Dictation 当前关闭，再点击“我已确认当前关闭 / 重新同步”。

如果目标快捷键要求按住开始、松开停止，请在设置中改用“按住说话”。

## 系统要求

- macOS 13.3 或更高版本。
- 带有内建摄像头的 Mac。
- 摄像头权限。
- “隐私与安全性 -> 辅助功能”中的键盘事件权限。
- Codex / ChatGPT 中已配置对应的 Dictation 快捷键。

## 从源码运行

1. 使用 Xcode 打开 `FaceToTalk.xcodeproj`。
2. 选择 `FaceToTalk` scheme。
3. 构建并运行。
4. 应用不会显示 Dock 图标；请从菜单栏打开。

命令行测试：

```bash
xcodebuild -project FaceToTalk.xcodeproj \
  -scheme FaceToTalk \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

构建 Universal 2 Release：

```bash
xcodebuild -project FaceToTalk.xcodeproj \
  -scheme FaceToTalk \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  build
```

当前版本使用 Xcode 27 beta 验证。其他 Xcode 版本尚未逐一测试；如果全局 `xcode-select` 指向 Command Line Tools，请通过 `DEVELOPER_DIR` 显式选择完整 Xcode。

## 首次使用

1. 启动 FaceToTalk 并允许摄像头权限。
2. 点击菜单中的“请求键盘权限”，在系统设置中允许 FaceToTalk 使用辅助功能。
3. 在 Codex / ChatGPT 中设置相同的 Dictation 快捷键。
4. 确认 Dictation 当前关闭。
5. 点击“我已确认当前关闭 / 重新同步”。
6. 保持 Codex / ChatGPT 在前台，直视屏幕后再转开进行测试。

建议把应用固定放在 `/Applications/FaceToTalk.app`。从不同 DerivedData 路径运行多个同名副本，可能产生多条难以区分的辅助功能授权记录。

## 可调设置

- 朝向后打开：0.3-5.0 秒，默认 1.0 秒。
- 转开、角度不足或无人脸后关闭：0.5-10.0 秒，默认 3.0 秒。
- 快捷键必须至少包含一个修饰键。
- `Command+Space` 通常会与 Spotlight 冲突。
- 更改快捷键、计时或快捷键语义会重置当前连续计时。

## 隐私边界

- 捕获会话只添加 `.video` 输入。
- 不请求麦克风权限，不创建音频输入，也不改变系统麦克风状态。
- 不保存或上传照片、视频或人脸特征。
- 不包含网络请求或云端模型。
- 不做人脸身份识别。
- App entitlements 仅包含 App Sandbox 与 Camera。

## 已知限制

- `CGEvent.post` 没有 Codex 接收回执，因此界面显示的是推测状态，不是确定状态。
- 用户手动操作 Codex Dictation 后，Toggle 状态可能失步，需要重新同步。
- 默认只控制前台的 Codex / ChatGPT。
- 当前只选择画面中面积最大的人脸。
- 最终 macOS 13.3 最小补丁仍建议在目标机器完成一次完整端到端确认。
- 预编译测试包使用本地临时签名，未做 Developer ID 公证。

## 项目文档

- [架构与开发经验](docs/architecture-and-lessons.md)
- [验证报告](docs/verification.md)
- [v0.1.0 发布说明草案](docs/release-notes-v0.1.0.md)
- [发布前检查表](docs/publication-checklist.md)

## License

MIT License。详见 [LICENSE](LICENSE)。
