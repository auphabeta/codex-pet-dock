# Changelog

## 0.3.0-beta - 2026-07-28

### Added

- 托盘首行实时显示 `WAITING`、`CONNECTED`、额度加载、过期或错误状态。
- 首次运行显示一次轻量提示，说明 Pet Dock 常驻托盘并会在宠物出现后自动附着。
- 重复启动不再静默无响应；新进程通过本机命名事件唤醒已有实例并显示当前状态。
- 新增可视化 Theme Studio：导入透明 PNG，实时调整运行尺寸、落脚面、重叠、
  指标偏移、衬底强度、紧凑字号和强调色。
- Theme Studio 可以打开已有主题，采用原子写入保存，并通过命名事件通知主程序
  热重载，无需重启 Pet Dock。
- 主题菜单增加 `Create or edit custom base` 与 `Reload custom themes`。
- 新增英文与简体中文界面资源。托盘 `Language` 菜单可即时切换，默认英文；
  语言与底座主题共同持久化，Theme Studio 自动沿用主程序语言。
- 语言资源拆分为显式 UTF-8 JSON，兼容 Windows PowerShell 5.1，并方便社区
  在不修改业务脚本的情况下贡献更多语言。
- 新增可直接交给 Codex、Claude Code 等编码助手的 Vibe Coding 自定义主题
  提示词，覆盖素材生成、白名单清单、临时诊断、安全安装和热重载。

### Changed

- 额度详情新增 `LIVE`/`STALE DATA` 与距上次更新时间；超过两次刷新周期且至少
  10 分钟未更新的数据明确降级为过期状态。
- 本周 Token 在详情中更名为 `LOCAL WEEK TOKENS`，并注明是本机活动估算、
  不是账单数据。
- 主题图片改为内存解码，不再长期锁定用户 PNG，编辑当前主题后也能安全热重载。
- 中英文详情卡和 Theme Studio 均加入实际文字测量；按钮、底座标题、动态详情
  文本在两种语言下都必须通过无裁切、无重叠回归。
- 一键安装现在默认启用当前用户登录自启；仍可从托盘关闭，或使用
  `-DoNotLaunchAtSignIn` 安装参数显式禁用。

### Fixed

- 额度详情的 Token 区域改为固定像素字体、分层文本和实际高度测量；长 Token
  数值、高缓存比例及多会话说明不再被裁切或与 `LIVE` 状态行重叠。
- 安装器和托盘自启开关不再对已经存在的 Windows `Run` 注册表键重复执行
  `New-Item -Force`，避免部分系统出现“传给系统调用的数据区域太小”并中断安装。
- 切换宠物时若顶层窗口或 UI Automation 元素被替换，会立即清除旧落脚边界；
  切换阶段缩短重扫与旧边界宽限时间，并优先跟随新加入的同尺寸宠物节点。

## 0.2.0-themes - 2026-07-28

### Added

- 内置主题由 3 款扩展到 9 款。
- 使用内置 Image 2 生成并产品化六款新底座：
  Princess Cradle、Forest Rune、Clockwork Brass、Moon Lotus、Sakura Shrine、
  Iron Throne。
- Iron Throne 使用 224×96 特殊高背布局，让宠物遮挡中央座面、剑阵从两侧
  与肩后露出。
- 每款新主题均提供独立落脚高度、指标纵向偏移、接触阴影位置与进度强调色。
- 新增五款主题的 224×72 实际尺寸视觉验收图和自动化资源测试。
- 支持 `%LOCALAPPDATA%\CodexPetDock\themes` 下的本地自定义底座；每款由
  `theme.json` 与同目录透明 PNG 构成，并在托盘菜单标记为 `Custom`。
- 自定义主题采用字段白名单、路径限制、重解析点拒绝、文件/尺寸上限与指标
  可见性校验，不执行脚本、CSS、JavaScript、命令或网络资源。

### Changed

- 底座窗口裁剪区域改为从当前主题 PNG 的 Alpha 轮廓动态生成，切换不同
  外形时不再沿用科技平台的固定多边形。
- 所有主题继续共享 `WEEK LEFT` 与 `WEEK TOKENS` 两个核心指标的位置和语义。

## 0.1.0-prototype - 2026-07-28

### Added

- 产品正式定义为 **Codex Pet Dock**，以“让 Codex 额度一眼可见”为核心。
- `PRODUCT.md` 产品定位、指标层级、状态、交互和版本边界。
- 不修改 Codex 源码或安装包的宠物额度 Sidecar。
- 通过官方 `codex app-server` 读取账户套餐和限额窗口。
- 从本机 `token_count` 事件聚合本周 Token，不读取会话正文。
- 基于官方进程、顶层窗口和 UI Automation 的宠物发现。
- 宠物拖动、通知展开、快捷对话和切换宠物后的重新锚定。
- Per-Monitor DPI Awareness V2 与多显示器工作区限制。
- 点击底座展开英文额度详情卡。
- 立体承托盘、接触阴影和宠物/平台前后遮挡。
- 三款内置底座主题：
  - Holo Cyan 3D
  - Holo Amber 3D
  - Circuit Flat
- 托盘主题菜单和 `%LOCALAPPDATA%\CodexPetDock\config.json`
  持久化。
- 托盘 `Launch at sign-in` 开关；开启后低频等待 Codex 与宠物并自动附着。
- 独立的 Codex Pet Dock 多尺寸应用/托盘图标，不再使用系统信息图标。
- 单实例保护，重复启动不会生成第二块底座或重复额度探测。
- 每用户 Preview 安装/卸载脚本、开始菜单入口、发布 ZIP 与 SHA-256 构建脚本。
- 隐私、安全与非官方项目声明。

### Safety

- 不读取或复制 `auth.json`。
- 不输出账户邮箱、Access Token 或会话正文。
- 不注入 Codex 渲染进程，不修改 `app.asar`。
- 兼容失败时隐藏或显示错误，不附着到其他应用。

### Fixed

- 底座指标字体改为固定像素字号，不再随 Windows DPI 放大后被固定尺寸窗口裁切；
  九款主题的字体行高、绘制边界和 Alpha 覆盖均加入回归。
- 指标标题改为 9px Segoe UI Semibold，并增加灰阶抗锯齿、1px 深色阴影和
  按主题调节透明度的信息衬底；浅色与复杂纹理主题不再吞掉小标题。
- 为每款主题增加真实落脚面与视觉重叠参数；Forest Rune、Princess Cradle、
  Clockwork Brass、Moon Lotus、Sakura Shrine 不再因素材透明上边距与宠物分离。
- 新增主题 SHA-256 与感知相似度审计；九款素材无完全重复，Holo Cyan/Amber
  明确作为同轮廓的冷暖配色变体保留。
- 主题切换保存配置时不再向 `.NET File.Replace` 传入空备份路径，修复
  “路径的格式不合法”未处理异常。
- 主题切换改为暂停绘制、应用材质与 Alpha 轮廓、立即按缓存宠物坐标重定位，
  再一次性重绘，消除不同高度主题之间的中间帧跳动。
- 主题点击事件增加事务锁、失败回滚和 UI 线程异常兜底；单款失败不会弹出
  Microsoft .NET Framework 崩溃对话框。
- 隐藏官方宠物时，失效窗口句柄不再触发未处理的
  `Could not read the pet monitor work area` 异常。
- 只在真实拖动期间短暂保留不可见窗口；主动隐藏宠物时 Dock 立即隐藏。
- 跟踪帧异常会安全隐藏并记录到本地 `sidecar.log`，不会弹出 .NET 错误框。
- 无宠物或宠物隐藏时降为 1 秒轮询并终止额度探测；只有宠物可见时才按
  5 分钟周期刷新额度，避免登录后后台空转。
- 切换到较高的 Iron Throne 后立即同步内部绘图控件尺寸，再生成 Alpha
  裁剪区域，修复数值行被旧 72px 高度裁掉的问题。

### Known limitations

- 当前仍需要 PowerShell 与 Node.js 22。
- 尚无签名 `Setup.exe` 和自动更新；当前 Preview 安装器面向早期测试用户。
- UI Automation 类名不是 Codex 的公开插件 API，更新后需要重新验证。
