# Contributing to Codex Pet Dock

感谢你愿意改进 Codex Pet Dock。项目优先接受能够保持以下边界的改动：

- 不修改 Codex 安装目录、`app.asar` 或官方宠物资源；
- 不读取、复制或上传 Codex 登录凭证与会话正文；
- 自定义底座保持为受限 JSON + 透明 PNG，不执行第三方脚本；
- 宠物隐藏时停止额度探测，后台刷新保持低频；
- Windows 11 上的拖动、切宠物、DPI 与多屏行为不退化。

## 提交 Issue

Bug 请附上：

- Windows 与 Codex 版本；
- Codex Pet Dock 版本和所选宠物/底座；
- 可重复步骤、预期行为和实际行为；
- `%LOCALAPPDATA%\CodexPetDock\sidecar.log` 中相关片段。

提交日志和截图前，请删除用户名、邮箱、访问令牌、会话正文、内部路径及其他
个人信息。额度百分比与 Token 数也可以按需打码。

功能建议请先说明读者遇到的问题，而不只是实现方式。涉及修改 Codex 文件、
注入进程、上传凭证或远程执行主题代码的方案不会接受。

## 本地开发

环境要求：

- Windows 11；
- Windows PowerShell 5.1；
- .NET Framework 4.8 或更新版本。

运行非 UI 回归：

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned `
  -File .\tests\Test-CodexPetDock.ps1 -SkipIntegration
```

构建并检查 Release ZIP：

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned `
  -File .\packaging\Build-Preview.ps1

powershell.exe -NoProfile -ExecutionPolicy RemoteSigned `
  -File .\tests\Test-ReleasePackage.ps1
```

涉及宠物跟随、拖动、窗口切换或 DPI 的改动，还应在真实 Codex 宠物窗口上运行
完整回归：

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned `
  -File .\tests\Test-CodexPetDock.ps1
```

## Pull Request

- 一次 PR 只解决一个清晰问题；
- 说明行为变化、验证方式和已知边界；
- UI 改动附脱敏前后截图；
- 新主题必须说明素材来源，并通过主题切换与透明度回归；
- 不提交 `dist/`、本机日志、额度缓存或个人配置。

提交即表示你有权贡献相关代码与素材，并同意按项目的
[MIT License](LICENSE) 发布。

