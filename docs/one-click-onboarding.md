# Codex Pet Dock 一键接入设计

## 结论

可以实现，而且核心接入应当是**安装后自动附着**，不是让用户复制 Token、
选择 Codex 路径或执行脚本。

用户唯一需要主动完成的动作是安装并启动 Codex Pet Dock。如果官方 Codex
已经运行、完成登录并打开宠物，Dock 应自动出现。严格来说，这是
“一次安装、零次绑定”。

## 用户流程

### 正常路径

```text
下载 Setup.exe
  → 双击安装
  → 勾选“立即启动”
  → 首次启动自检
  → 自动发现 Codex
  → 自动读取官方额度
  → 自动发现宠物
  → Dock 出现在宠物脚下
```

用户不需要：

- 输入 OpenAI/Codex 账户；
- 粘贴 Access Token 或 API Key；
- 选择 Codex 安装目录；
- 安装 Node.js、PowerShell 模块或 .NET Runtime；
- 修改 Codex 启动参数；
- 重启或重新安装 Codex；
- 手动绑定某一只宠物。

## 首次启动界面

首次启动只显示一个紧凑的原生状态窗口。

### 标题

`CODEx PET DOCK`

### 主文案

`Make Codex usage visible at a glance.`

### 三项自检

| 检查 | 成功 | 失败动作 |
|---|---|---|
| Codex desktop | `Detected` | `Install / Open Codex` |
| Account limits | `Connected` | `Open Codex to sign in` |
| Desktop pet | `Ready` | `Show your pet in Codex` |

三项全部成功后不再要求用户点击 `Connect`，直接进入 Dock。按钮只保留：

- `Choose appearance`
- `Open Dock`

`Open Dock` 是完成引导，不是授权或绑定动作。

## 为什么不设计“Connect account”

Codex Pet Dock 使用 Codex 自己的 `app-server` 登录状态。额外提供账户连接
按钮会制造错误心智：

- 用户可能以为要再次输入 OpenAI 密码；
- 用户可能担心工具保存 Token；
- 多一套 OAuth/凭证会扩大安全边界；
- 实际上没有第二个账户需要连接。

正确表达是：

> Uses the account already signed in to the official Codex desktop app.

## 失败引导

### 未安装 Codex

显示：

`Codex desktop was not found.`

动作：

- `Get Codex`
- `Check again`

不能要求用户浏览文件系统选择一个不可信的 `codex.exe`。

### Codex 未运行

显示：

`Open Codex to continue.`

动作：

- `Open Codex`
- `Wait in tray`

用户选择等待后关闭引导窗口，Dock 留在托盘自动重试。

### 未登录

显示：

`Sign in using the official Codex app.`

只打开官方 Codex，不在 Dock 内收集账号密码。

### 宠物未打开

显示一张小型示意图和一句：

`Show a desktop pet in Codex. The Dock will attach automatically.`

动作：

- `Show me how`
- `Wait in tray`

在官方没有稳定深链之前，不模拟点击或修改 Codex 设置来强行打开宠物。

### 接口不兼容

显示：

`This Codex version needs a compatibility update.`

动作：

- `Copy diagnostics`
- `Check for updates`
- `Exit`

诊断内容必须脱敏。

## 安装体验

### 产物

- `CodexPetDock-Setup-x.y.z.exe`
- `CodexPetDock-x.y.z-win-x64.zip`
- `SHA256SUMS.txt`

### 安装范围

默认每用户安装：

```text
%LOCALAPPDATA%\Programs\CodexPetDock\
```

不要求管理员权限。

### 安装选项

- 创建开始菜单快捷方式：默认开启；
- 安装完成立即启动：默认开启；
- 登录 Windows 时启动：默认关闭，并说明开启后会自动等待 Codex；
- 创建桌面快捷方式：默认关闭。

用户以后可以在托盘中切换 `Launch at sign-in`。开启一次后，Pet Dock
随 Windows 登录在托盘低频等待；用户每次打开 Codex 和宠物时会自动附着，
不需要使用特殊的“Codex + Dock”快捷方式。

### 升级

新版本覆盖程序目录，保留：

```text
%LOCALAPPDATA%\CodexPetDock\
```

其中包含主题选择、设置和本地错误日志。

## 免依赖实现

正式客户端迁移为 `.NET 8 WinForms`：

```xml
<PropertyGroup>
  <OutputType>WinExe</OutputType>
  <TargetFramework>net8.0-windows</TargetFramework>
  <UseWindowsForms>true</UseWindowsForms>
  <RuntimeIdentifier>win-x64</RuntimeIdentifier>
  <SelfContained>true</SelfContained>
  <PublishSingleFile>true</PublishSingleFile>
  <IncludeNativeLibrariesForSelfExtract>true</IncludeNativeLibrariesForSelfExtract>
</PropertyGroup>
```

需要迁移进同一个可执行文件：

- Win32 窗口发现；
- UI Automation 宠物定位；
- Dock、详情、托盘和设置；
- app-server JSONL 客户端；
- 本地 `token_count` 聚合；
- 主题目录与配置；
- 本地诊断日志。

正式安装包内不携带 PowerShell 脚本执行入口，也不要求用户安装 Node.js。

## 自动发现顺序

1. 从当前运行进程确认官方 `OpenAI.Codex`；
2. 从官方包目录发现同版本 `codex.exe`；
3. 启动 `codex.exe app-server --listen stdio://`；
4. 读取当前官方登录状态；
5. 枚举属于官方进程的宠物窗口；
6. 使用 UI Automation 定位当前可见宠物；
7. 创建 Dock 并附着；
8. 后续 Codex 更新或切换宠物时重新发现。

不把版本化的 WindowsApps/Codex 路径永久写入配置。

## 网站“一键安装”边界

第一版网站按钮只跳转到 GitHub Release 的签名安装包，不注册自定义协议。

后续如果支持 `codexpetdock://theme?id=...`，只用于主题：

- URL 只能携带固定格式的主题 ID；
- 不允许任意 URL、文件路径或命令；
- 客户端只访问固定官方 API；
- 下载后验证大小与 SHA-256；
- 应用前弹出原生确认；
- 失败回滚上一主题。

核心 Codex 接入不需要自定义协议。

## 验收标准

- 全新 Windows 用户从下载到看到 Dock 不超过 2 分钟；
- 不出现命令行窗口；
- 不要求管理员权限；
- 不要求安装运行时；
- 不要求输入账号或凭证；
- Codex 与宠物已经打开时无需手动绑定；
- 宠物未打开时引导明确且可留在托盘等待；
- 卸载后不修改或破坏 Codex；
- 覆盖升级保留设置；
- 失败时提供可理解的下一步，而不是堆栈或 .NET 弹框。
