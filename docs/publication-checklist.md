# GitHub Publication Checklist

## Local preparation

- [x] 从原工程复制独立、干净的源码快照。
- [x] 排除 DerivedData、`work/`、用户状态、zip 和系统元数据。
- [x] 添加 `.gitignore` 与 `.gitattributes`。
- [x] 添加 MIT License。
- [x] 更新 README、架构经验、验证报告、Changelog 和 Release Notes。
- [x] 删除文档中的个人主目录绝对路径。
- [x] Debug build 通过。
- [x] 7 / 7 XCTest 通过。
- [x] Universal 2 Release 构建通过。
- [x] 两个架构的最低系统版本均为 macOS 13.3。
- [x] Release 签名与 entitlements 校验通过。
- [x] 生成不含 `__MACOSX` 的 zip。
- [x] 生成 SHA-256 校验文件。
- [x] 初始化本地 Git 并提交首个快照。

## Before public release

- [ ] 在真实 macOS 13.3 机器验证最终补丁。
- [ ] 确认 Facing 达标时发送一次完整快捷键。
- [ ] 确认 Away、无人脸和角度不足达标时发送第二次完整快捷键。
- [ ] 确认暂停、退出和目标离开前台时不会留下按键按下状态。
- [ ] 添加一张不含个人信息的菜单栏截图。
- [ ] 最终选择 GitHub 可见性；当前建议 Public。
- [ ] 最终确认 MIT License。
- [ ] 确认仓库名；当前建议 `FaceToTalk`。

## GitHub actions - do not run until approved

- [ ] 创建 GitHub 远程仓库。
- [ ] 添加 `origin`。
- [ ] 推送 `main`。
- [ ] 创建 `v0.1.0` tag。
- [ ] 创建 GitHub Pre-release。
- [ ] 上传 zip、`SHA256SUMS.txt` 和 Release Notes。

## Optional later

- [ ] Developer ID 签名与 Apple 公证。
- [ ] 稳定 Xcode 版本兼容验证。
- [ ] CI build/test workflow。
