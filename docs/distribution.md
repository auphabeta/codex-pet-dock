# Codex Pet Dock 面向普通用户的发布方案

## 结论

可以做成类似 Codex Dream Skin 的普通用户产品体验，但当前脚本原型不应
直接包装成“安装即用”的正式版本。

Dream Skin 当前为 Windows 用户提供 `Setup.exe`、托盘操作、主题切换和
覆盖升级，不要求用户克隆仓库或手动运行脚本。Codex Pet Dock 应达到
相同的分发门槛，同时继续保持“不注入、不修改官方安装包”的不同架构。

参考：

- <https://github.com/Fei-Away/Codex-Dream-Skin>

## 当前已经具备

- 不修改 Codex 安装目录和 `app.asar`；
- 自动发现官方宠物并跟随；
- 额度与本周 Token 展示；
- 托盘菜单；
- 九款内置底座主题；
- 主题选择持久化；
- 无需管理员权限的运行模型；
- 明确的失败安全和隐私边界。

## 正式发布前必须补齐

### 1. 改为 .NET 单文件 WinExe

推荐技术栈：

- .NET 8 WinForms；
- `PublishSingleFile=true`；
- `SelfContained=true`；
- `RuntimeIdentifier=win-x64`；
- `OutputType=WinExe`。

额度 JSONL app-server 客户端和 Token 聚合已经迁入
`CodexPetProbe.exe`，最终用户不再需要 Node.js。下一阶段继续将 PowerShell
中的窗口、UIA 与托盘逻辑迁入 `CodexPetDock.exe`，消除常驻 PowerShell
运行时；安装和 Theme Studio 仍可使用系统自带 PowerShell。

不要把 Node 或 PowerShell 运行时静默打包进安装器作为长期方案；那会增加体积、
安全软件误报和维护面。

### 2. 每用户安装器

首选安装位置：

```text
%LOCALAPPDATA%\Programs\CodexPetDock\
```

配置位置：

```text
%LOCALAPPDATA%\CodexPetDock\
```

安装器建议使用 Inno Setup 或 WiX，默认行为：

- 不要求管理员权限；
- 创建开始菜单快捷方式；
- 安装结束可选择立即启动；
- 登录自启默认开启，并在首次提示与托盘中提供清楚、可逆的关闭入口；
- 升级覆盖程序文件但保留配置；
- 卸载时询问是否同时删除用户配置。

### 3. 签名与校验

公开 Release 至少提供：

- 版本化 `Setup.exe`；
- 便携 ZIP；
- SHA-256；
- 变更日志；
- 安装/卸载说明；
- 非 OpenAI 官方产品声明；
- 主题素材许可说明。

正式面向大量普通用户时应进行 Authenticode 代码签名。未签名安装包会触发
SmartScreen，文档可以说明，但不能把“关闭安全软件”作为安装步骤。

### 4. 更新

第一阶段采用用户主动更新：

1. 托盘 `Check for updates` 只读取 GitHub Releases；
2. 显示版本、发布日期和校验值；
3. 用户确认后打开 Release 页面；
4. 用户下载并覆盖安装。

在具备代码签名和可靠回滚前，不实现静默自更新。

## 主题产品设计

### 内置主题

正式包内置并离线可用：

- Holo Cyan 3D；
- Holo Amber 3D；
- Circuit Flat；
- Princess Cradle；
- Forest Rune；
- Clockwork Brass；
- Moon Lotus；
- Sakura Shrine；
- Iron Throne。

首次启动默认 `Holo Cyan 3D`，托盘直接切换并保存。

### 第三方主题

Preview 已支持本地、纯素材主题目录：

```text
%LOCALAPPDATA%\CodexPetDock\themes\<theme-id>\
  theme.json
  platform.png
```

当前契约：

```json
{
  "schemaVersion": 1,
  "id": "author.theme-id",
  "name": "Theme name",
  "asset": "platform.png",
  "width": 224,
  "height": 72,
  "contactSurfaceY": 20,
  "contactOverlap": 7,
  "contentOffsetY": 0,
  "contactShadow": true,
  "contactShadowY": 18,
  "compactMetrics": false,
  "metricsScrimOpacity": 120,
  "accent": "#6FE8EF"
}
```

启动时验证：

- 只接受白名单 JSON 字段和同目录 PNG；
- 限制 manifest、PNG 文件大小和图片/运行时尺寸；
- 拒绝绝对路径、`..`、符号链接/重解析点和远程 URL；
- 校验落脚面、阴影、文字区域和颜色格式；
- 无效主题跳过并写本地日志，不影响内置主题；
- 切换失败自动回到上一主题。

不提供 CSS、PowerShell、JavaScript 或任意命令字段。这样第三方主题能力
不会扩大 Sidecar 的执行权限。

后续若增加 ZIP 导入器，再补充条目数、解压总大小、嵌套压缩包、SHA-256、
来源确认和导入预览；当前不会自动解压或下载第三方主题。

## 推荐发布阶段

### Preview 0.1

- 保留当前源码运行方式；
- 面向开发者；
- 九款内置主题；
- 收集 Codex 版本、DPI 和宠物切换兼容反馈。

### Beta 0.3

- 托盘连接状态、首次启动提示与重复启动唤醒；
- Theme Studio、自定义主题安全校验与热重载；
- 额度数据新鲜度和本机 Token 语义；
- 可重复执行的主题、交互、功耗和隐私回归。

### Beta 0.5

- .NET 8 单文件；
- 便携 ZIP；
- 无 Node/PowerShell 依赖；
- GitHub Actions 构建与 SHA-256；
- 10–20 名 Windows 用户测试。

### Stable 1.0

- 每用户 `Setup.exe`；
- Authenticode 签名；
- 完整卸载与升级保留配置；
- 兼容性自检；
- 主题导入安全校验；
- GitHub Releases 文档和问题模板。

## GitHub 仓库建议结构

```text
CodexPetDock/
  src/
    CodexPetDock.App/
    CodexPetDock.Core/
    CodexPetDock.Tests/
  themes/
    holo-cyan/
    holo-amber/
    circuit-flat/
  packaging/
    windows/
  docs/
    architecture.md
    distribution.md
    troubleshooting.md
  .github/
    workflows/release.yml
    ISSUE_TEMPLATE/
  README.md
  CHANGELOG.md
  LICENSE
  NOTICE.md
```

## 发布判断

当前版本适合“公开源码预览”，还不适合对普通用户宣传为正式安装版。完成
.NET 单文件迁移、安装器、签名和至少一轮多机器兼容测试后，就可以达到
类似 Dream Skin 的下载安装体验，而且本项目不依赖 CDP 注入，升级风险
和权限面会更小。
