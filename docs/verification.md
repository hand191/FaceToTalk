# Verification Report - FaceToTalk v0.1.0 - 2026-08-04

## Result

Status: **PARTIAL**

干净发布副本的 Debug 构建、7 项测试、Universal 2 Release、Mach-O 最低版本、签名、权限配置与归档完整性均已通过。最终补丁尚未在真实 macOS 13.3 机器完成一次完整的摄像头到 Codex Dictation 端到端确认，因此不标记为完全验证。

## Scope

- Intended：确认准备发布的源码副本可独立构建和测试，并生成可供后续 GitHub Pre-release 使用的本地安装包。
- Out of scope：创建 GitHub 远程仓库、推送代码、发布 Release、Developer ID 签名、公证和真实 macOS 13.3 端到端复测。

## Evidence Boundary

- Inspected：全部 Swift 源码、Xcode project、shared scheme、Info.plist、entitlements、测试、README、发布文档和最终 zip 内容。
- Verified locally：Debug build、XCTest、Universal 2 Release、二进制版本、签名、entitlements、XML/plist 格式与 zip 完整性。
- Not reverified：目标 macOS 13.3 机器上的最终补丁、辅助功能首次授权流程和 Codex 实际接收结果。
- Assumption：`CGEvent.post` 成功不等于 Codex 已接收快捷键。

## Environment

- macOS 27.0，Apple Silicon。
- Xcode 27.0 beta（27A5218g）。
- macOS 27.0 SDK。
- Swift language mode 6.0。
- Deployment Target：macOS 13.3。

## Commands

Debug build：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project FaceToTalk.xcodeproj \
  -scheme FaceToTalk \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Tests：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project FaceToTalk.xcodeproj \
  -scheme FaceToTalk \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Universal 2 Release：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project FaceToTalk.xcodeproj \
  -scheme FaceToTalk \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  build
```

## Automated Checks

- Debug app build：PASS。
- XCTest：PASS，7 / 7，0 failures。
- Release build：PASS。
- Architectures：PASS，`x86_64 arm64`。
- Mach-O minimum OS：PASS，两个 slice 均为 macOS 13.3。
- Bundle version：PASS，`0.1.0 (1)`。
- `codesign --verify --deep --strict`：PASS。
- Release entitlements：PASS，仅 App Sandbox 与 Camera。
- `NSCameraUsageDescription`：存在。
- `NSMicrophoneUsageDescription`：不存在。
- 麦克风 entitlement / audio input：不存在。
- Info.plist / entitlements lint：PASS。
- Shared scheme XML：PASS。
- Zip integrity：PASS。
- Zip metadata：PASS，不包含 `__MACOSX`。

## Release Asset

文件：`FaceToTalk-0.1.0-macOS13.3-universal.zip`

SHA-256：

```text
7df4a75e6f4a569a35190d0bd62dd1cd0aa825e0309379ef04b49f08288e4ae4
```

签名状态：本地临时签名，Hardened Runtime 开启，未做 Developer ID 签名或 Apple 公证。

## Release-only Configuration Adjustment

本地发布检查发现 Xcode 会向临时签名的 Release 自动注入 `get-task-allow`。发布副本已在 Release target 中设置 `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`，重新构建后实际签名 entitlements 只包含：

```text
com.apple.security.app-sandbox = true
com.apple.security.device.camera = true
```

该调整不改变应用功能或 Debug 开发体验。

## Manual Checks

- 旧兼容基线在真实 macOS 13.3 上可启动：由用户此前确认。
- 最终“转开/无人脸/角度不足后第二次完整快捷键”补丁：NOT RUN on target macOS 13.3 in this publication pass。
- 最终菜单栏截图：NOT RUN，留到确认公开发布前采集。
- Developer ID / notarization：NOT RUN，当前个人实验阶段不需要。

## Remaining Risks

- Codex 没有快捷键接收回执，Toggle 状态仍可能因手动操作而失步。
- 真实 macOS 13.3 上 Vision 返回角度的细节仍需要最终人工复测。
- 未公证安装包可能触发 Gatekeeper 提示。

## Next Step

在决定公开发布前，先在目标 macOS 13.3 机器用本报告对应 zip 做一次完整测试，并保存一张不含个人信息的菜单栏截图。通过后再创建 GitHub 远程仓库、推送 `main`、打 `v0.1.0` tag 并创建 Pre-release。
