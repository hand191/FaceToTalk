# FaceToTalk 架构与开发经验

## 项目目标

FaceToTalk 的目标是使用 Mac 内建摄像头在本机判断头部是否大致朝向屏幕，并只通过用户配置的快捷键控制 Codex / ChatGPT Dictation。它不改变系统麦克风状态，不录音，也不上传画面。

## 模块结构

- `FaceToTalkApp.swift`：SwiftUI 入口、`MenuBarExtra` 与 Settings scene。
- `VisionCameraService.swift`：摄像头权限、video-only 捕获、Vision 分析、姿态迟滞与中断通知。
- `FacingStateMachine.swift`：以单调时间计算 Facing/Away 连续时长，并保证每个连续区间只触发一次。
- `HotKeyController.swift`：构造并发送真实的修饰键按下、主键按下、主键释放、修饰键反向释放序列。
- `AppModel.swift`：整合视觉事件、状态机、快捷键、前台应用、权限与生命周期安全处理。
- `SettingsStore.swift`：使用 `UserDefaults` 保存计时、快捷键、语义、前台限制和总开关。
- `MenuPanel.swift`、`SettingsView.swift`、`ShortcutRecorderView.swift`：菜单栏状态、设置和快捷键录入。
- `FacingStateMachineTests.swift`：状态机、快捷键事件、设置边界与持久化测试。

## 关键设计决定

### 1. Toggle 与 Press-and-Hold 必须分开

按住型快捷键需要 Facing 时发送 key-down、Away 时发送 key-up；Toggle 快捷键则需要两边各发送一次完整 key-down + key-up。两者看似都是“快捷键控制”，实际状态模型完全不同。

### 2. 不能把 CGEvent 当成应用回执

系统接受合成事件，不代表 Codex 已处理。因此应用使用 `assumedOff`、`assumedOn`、`unknown` 三态，并提供“重新同步为关闭”。

### 3. 角度不足按 Away 计时

在 macOS 13.3 的实际使用中，Vision 可能检测到侧脸，但没有同时返回 yaw 和 pitch。如果把这种情况持续重置，就无法完成转开触发。当前实现将 `.uncertain`、`.away` 和 `.noFace` 合并为同一个关闭区间。

### 4. 使用单调时间而不是帧数

状态机使用 `ProcessInfo.processInfo.systemUptime`。帧率变化或系统时间调整不会改变连续时长逻辑；倒退的时间差会被夹到零。

### 5. 姿态判定使用迟滞

进入 Facing 的 yaw/pitch 阈值比离开 Facing 更严格，减少临界角度抖动造成的反复切换。

### 6. 权限稳定依赖固定的应用身份和路径

多个 DerivedData 产物虽然名称相同，但系统辅助功能列表可能把它们视作不同应用。测试和日常使用都应固定 `/Applications/FaceToTalk.app`，并避免同时运行多个副本。

## 开发过程中的经验

1. 先验证目标应用快捷键的真实语义，再写自动控制状态机。
2. 用已在目标系统运行的版本作为兼容基线，最小补丁优于同时调整多个默认值。
3. Deployment Target 编译成功还不等于真机端到端成功；仍要验证摄像头、权限和目标应用响应。
4. 发布前要分别检查两个架构的 Mach-O 最低系统版本。
5. 构建缓存必须从第一天就进入 `.gitignore`；本项目源码很小，但多轮 DerivedData 曾增长到数 GB。
6. 测试报告应与当前代码一起更新，避免旧版本报告成为错误的“事实来源”。
7. 不需要为个人实验项目引入额外服务或生产级组件；清晰的权限说明、可恢复状态和可复现测试更重要。

## 后续适合的小步迭代

- 在真实 macOS 13.3 机器完成最终端到端检查并记录结果。
- 添加一张不包含个人信息的菜单栏截图。
- 若准备面向陌生用户分发，再考虑 Developer ID 签名与公证。
- 如果 Codex 将来提供独立的开始/停止命令，优先改用幂等命令，消除 Toggle 失步风险。
