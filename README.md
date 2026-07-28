# Codex Pet Dock

> 让 Codex 额度一眼可见。

Codex 宠物用量底座：一个不修改 Codex 安装目录、`app.asar` 或宠物资源包
的 Windows 旁路工具。

它做三件事：

1. 通过 Codex 官方 `app-server` 的稳定账户方法读取套餐类型与额度；
2. 从本机 Codex 会话日志的 `token_count` 事件聚合本周 Token 数，只读取计数与时间戳；
3. 找到 Codex 自带宠物的独立窗口，再通过 Windows UI Automation 读取宠物元素的实时边界，在宠物脚下附着一个状态底座，点击后展开额度卡片。

这不是皮肤，也不会再创建一个独立悬浮球。宠物可以站在科技、童话、
自然、机械与东方幻想等九款底座上；每款都有独立承托面、接触阴影和统一的
双指标前脸。底座会跟随宠物移动、切换和内部布局变化；拖动时自动切换到
约 60 FPS 跟随，静止后降频；宠物关闭或隐藏后，底座与卡片也会隐藏。

## 当前结论

可行，但不能只改 `~/.codex/pets/<pet>/pet.json` 实现。

Codex 的自定义宠物契约目前只包含显示信息、精灵表路径和精灵版本，负责动画表现，不包含点击处理、菜单项或插件脚本。要给宠物增加业务功能，必须由宠物包之外的代码完成。

推荐的兼容路径是：

```text
Codex 宠物窗口
      │ UI Automation 只读获取“Codex 宠物”元素边界
      ▼
附着式状态底座 ──点击──> 额度卡片
      │
      ▼
独立 codex app-server 进程
      │ account/read + account/rateLimits/read
      ▼
ChatGPT/Codex 额度快照
```

原型不会读取 `auth.json`，不会复制 Access Token，也不会解析会话消息正文。Codex 自己启动的 `app-server` 负责使用和刷新现有登录状态。

## 运行

要求：

- Windows 11
- 已安装并登录 Codex 桌面客户端
- Node.js 22 或更新版本
- Codex 宠物已经打开

先做无界面诊断：

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned `
  -File .\src\Start-CodexPetQuota.ps1 -Diagnostics
```

启动底座和额度卡：

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned `
  -File .\src\Start-CodexPetQuota.ps1
```

关闭方式：右下角托盘图标菜单选择 `Exit`。

如果希望每次打开 Codex 宠物时自动出现，在托盘菜单勾选
`Launch at sign-in`。Pet Dock 会随 Windows 登录在托盘低频等待；Codex
和宠物出现后自动附着，二者关闭或隐藏后回到等待状态。该选项默认关闭，
不需要管理员权限，也不会修改 Codex 快捷方式。

托盘第一行会显示当前生命周期：`WAITING`、`CONNECTED`、额度加载中、
额度过期或额度暂不可用。重复双击启动入口不会创建第二个实例，而会让已有
实例弹出当前状态，因此不再出现“到底有没有启动”的疑问。

后台节流策略：未发现宠物或宠物隐藏时每 1 秒轻量检查一次，宠物显示后静止跟随
为 64ms、拖动期间短暂提升到 16ms；宠物元素的完整 UI Automation 扫描另行节流。
恢复；额度和本周 Token 默认每 5 分钟刷新，打开详情或选择 `Refresh`
时即时更新。没有可见宠物时不会启动额度探测进程。

### 内置底座主题

托盘菜单 `Base theme` 可以直接切换：

- `Holo Cyan 3D`：默认的青色立体承托平台
- `Holo Amber 3D`：暖金色能量线路
- `Circuit Flat`：更薄的平面芯片样式
- `Princess Cradle`：象牙白、粉色软垫和香槟金的公主摇篮
- `Forest Rune`：苔藓古石与青色符文的森林祭坛
- `Clockwork Brass`：黄铜、胡桃木和琥珀能量管的机械台
- `Moon Lotus`：月白瓷、青玉莲瓣和靛蓝仪表面的月光莲台
- `Sakura Shrine`：朱漆、樱花与黄铜构件组成的神社舞台
- `Iron Throne`：黑石阶、锻铁剑阵与暗红进度光组成的特殊高背王座

选择会保存到 `%LOCALAPPDATA%\CodexPetDock\config.json`，覆盖更新项目文件
不会丢失。也可以用命令行临时指定：

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned `
  -File .\src\Start-CodexPetQuota.ps1 `
  -Theme holo-amber
```

### 自定义底座

项目支持本地、纯数据自定义底座。普通用户可直接选择
`Base theme` → `Create or edit custom base...` 打开 Theme Studio：导入一张
透明 PNG，在实时预览中调整宠物落脚线、尺寸、文字位置和颜色，然后
`Save & reload`，无需重启 Pet Dock。

开发者也可以选择 `Open custom themes folder`，手动建立包含 `theme.json`
与透明 PNG 的主题目录，再点击 `Reload custom themes`。

加载器只接受固定白名单字段和同目录 PNG；脚本、CSS、JavaScript、命令、
URL、绝对路径、目录穿越、符号链接、超大文件与不安全尺寸都会被拒绝。
完整格式和设计建议见 [`docs/custom-themes.md`](docs/custom-themes.md)。

如果底座和宠物贴合位置不理想，可以调整相对宠物窗口底部中心的偏移：

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned `
  -File .\src\Start-CodexPetQuota.ps1 `
  -BaseOffsetX 0 -BaseOffsetY 4
```

## 已验证环境

- Windows 11
- Codex Store `26.721.4979.0`
- Codex CLI `0.146.0-alpha.3.1`
- 宠物窗口可被识别为同一官方进程下的小型、置顶 `Chrome_WidgetWin_1` 窗口
- Windows UI Automation 可读取 `codex-avatar-button` 元素边界，底座不依赖透明窗口底边
- `account/rateLimits/read` 返回了使用比例、窗口分钟数和重置时间
- `account/read` 返回的账户数据只保留 `planType`，不会输出邮箱
- 本周 Token 按周一 00:00 起的会话累计计数差值统计，重复通知不会重复相加；总量包含缓存输入

## 文件

- `PRODUCT.md`：产品定位、指标层级、交互、视觉原则和版本边界
- `src/quota-probe.mjs`：最小 app-server JSONL 客户端，只输出脱敏后的额度数据
- `src/Start-CodexPetQuota.ps1`：窗口识别、附着底座、卡片与托盘生命周期
- `src/Start-CodexPetThemeStudio.ps1`：自定义底座可视化编辑、校验与热重载
- `assets/tech-platform-v2.png`：Image 2 生成并去除色键背景的立体全息芯片平台
- `assets/themes/*.png`：Image 2 生成的六款世界观主题；常规款 896×288，
  Iron Throne 高背款 896×384
- `assets/branding/codex-pet-dock.ico`：Pet Dock 多尺寸 Windows 与托盘图标
- `docs/architecture.md`：完整数据流、窗口跟随、宠物切换、DPI、主题与安全方案
- `docs/theme-generation-prompts.md`：六款 Image 2 主题的最终提示词与透明化流程
- `docs/custom-themes.md`：自定义底座目录、JSON 契约、视觉建议和安全限制
- `docs/media/screenshots/`：README、文章和发布帖可复用的原始效果截图与校验清单
- `docs/distribution.md`：普通用户安装包、单文件迁移、更新和主题包路线
- `docs/one-click-onboarding.md`：一次安装、零次绑定的首次启动和失败引导
- `docs/feasibility.md`：方案比较、升级兼容性和安全边界
- `CHANGELOG.md`：已完成功能和已知限制

## 参考

- [OpenAI Codex app-server 文档](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md)
- [Codex Dream Skin](https://github.com/Fei-Away/Codex-Dream-Skin)

## Preview 安装

开发者 Preview 可解压发布 ZIP 后双击 `Install-Preview.cmd`。它会进行每用户
安装、创建带自定义图标的开始菜单入口并立即启动；不会申请管理员权限，开机
启动默认关闭。当前 Preview 仍要求 Node.js 22，安装器会在写入任何文件前检查。

构建可分发 ZIP 与 SHA-256：

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned `
  -File .\packaging\Build-Preview.ps1
```

## 当前 Preview 的边界

- 已有每用户 Preview 安装器、单实例保护和开机启动开关，但还没有签名的
  `Setup.exe` 或自动更新。
- 宠物窗口识别依赖 Windows 顶层窗口特征；精确贴合还依赖宠物元素的 UI Automation 类名。升级后若任一结构改变，会回退到窗口锚点或安全隐藏，不会注入官方进程。
- 底座是独立窗口，因此不能真正成为 Codex 宠物 DOM 的子节点；这是换取不注入、不改包和更好升级兼容性的代价。
- 当前只显示官方接口实际返回的限额窗口。若 5 小时窗口暂未出现，就只显示周窗口。
- 本周 Token 是本机“模型处理量”统计，包含缓存输入，不等同于 OpenAI 服务端账单，也不会包含已从本机删除的会话。点击底座可查看非缓存输入、缓存比例和输出量。

## 给其他用户使用

当前版本适合公开源码预览，开发者可按上面的命令运行。若要达到普通用户
双击 `Setup.exe`、无需 Node.js/PowerShell 的体验，推荐迁移为 .NET 8
WinForms 单文件程序，再提供每用户安装器、SHA-256、代码签名和 GitHub
Releases。详细阶段与主题包安全契约见
[`docs/distribution.md`](docs/distribution.md)。
