# FaceToTalk v0.1.0

> Experimental pre-release. FaceToTalk is an unofficial project and is not affiliated with OpenAI.

## 主要功能

- 使用内建摄像头和 Apple Vision 在本机判断头部是否大致朝向屏幕。
- Facing 达到设定时间后发送一次完整快捷键。
- Away、无人脸或角度不足达到设定时间后再次发送一次完整快捷键。
- 支持自定义快捷键、1.0/3.0 秒默认延迟和本地设置持久化。
- 支持 Toggle 与 Press-and-Hold 两种快捷键语义。
- 不请求麦克风权限，不录音，不上传画面。

## 系统要求

- macOS 13.3 或更高版本。
- Apple Silicon 或 Intel Mac。
- 摄像头权限与辅助功能权限。
- Codex / ChatGPT 中已配置匹配的 Dictation 快捷键。

## 安装

1. 解压 `FaceToTalk-0.1.0-macOS13.3-universal.zip`。
2. 把 `FaceToTalk.app` 移到 `/Applications`。
3. 首次启动后允许摄像头权限。
4. 在“系统设置 -> 隐私与安全性 -> 辅助功能”中允许 FaceToTalk。
5. 确认 Codex Dictation 当前关闭，然后在 FaceToTalk 中重新同步。

## 验证摘要

- XCTest：7 / 7 通过。
- Release：Universal 2，包含 `arm64` 与 `x86_64`。
- 两个架构的最低系统版本：macOS 13.3。
- Entitlements：App Sandbox + Camera。
- 不包含麦克风用途说明或麦克风 entitlement。
- 本地代码签名校验通过。

## 注意

- 该预编译包使用本地临时签名，未做 Developer ID 公证。
- `CGEvent` 没有 Codex 接收回执；界面显示的是推测状态。
- 默认只在 Codex / ChatGPT 位于前台时发送快捷键。
- 最终补丁仍建议在目标 macOS 13.3 机器完成一次端到端人工确认。
