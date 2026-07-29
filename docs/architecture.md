# Codex Pet Dock 实现方案记录

本文记录 2026-07-28 完成的 Windows 原型方案，目标是在不修改 Codex
安装目录、`app.asar`、宠物包和登录凭证的前提下，为官方宠物增加额度与
本周 Token 状态底座。

## 1. 设计目标

- 继续使用 Codex 官方宠物，不创建第二个悬浮球。
- 不向 Codex 渲染进程注入 JavaScript、CSS 或 DLL。
- Codex 更新后尽量继续工作；结构不兼容时安全隐藏。
- 不读取、复制或输出 `auth.json`、Access Token、账户邮箱。
- 宠物关闭时底座一起隐藏，拖动和切换宠物时继续跟随。
- 用户通过托盘直接切换内置底座主题，选择跨升级保存。

## 2. 总体架构

```text
OpenAI.Codex 官方进程
  └─ 透明宠物顶层窗口
       └─ UI Automation: codex-avatar-button*
                    │ 只读屏幕边界
                    ▼
Codex Pet Dock Sidecar（独立进程）
  ├─ 宠物跟随窗口
  │   ├─ 立体底座
  │   ├─ 周额度剩余
  │   └─ 本周 Token
  ├─ 点击详情卡片
  ├─ 托盘菜单与主题切换
  ├─ codex app-server 子进程
  │   ├─ account/read
  │   └─ account/rateLimits/read
  └─ 本机会话 token_count 聚合
```

Sidecar 与 Codex 之间没有代码注入或文件覆盖。两者只通过官方
`app-server` 标准输入输出协议和 Windows 的只读窗口/UI Automation
接口发生联系。

## 3. 宠物发现与跟随

### 3.1 顶层窗口筛选

`Get-PetWindow` 只接受以下候选：

- 属于当前官方 `OpenAI.Codex` 包进程；
- 可见、置顶、工具窗口；
- 类名与 Codex Electron 窗口匹配；
- 尺寸在 120–1600 像素之间。

上限保留到 1600，是因为通知、快捷对话或选择宠物时，透明宿主窗口可能
临时扩展到 1000 像素以上。旧的 800 像素上限会在切换后错误丢失窗口。

### 3.2 宠物元素锚点

透明宿主窗口的底边不是宠物底边。实现通过 Windows UI Automation
遍历后代元素，选择：

- 类名以 `codex-avatar-button` 开头；
- `IsOffscreen = false`；
- 有有效屏幕边界；
- 多个候选中优先选择中心点最接近上次有效锚点的元素，距离相同时再比较面积。

宠物身份优先使用稳定的可访问名称，只有名称不可用时才回退到 RuntimeId。
因此 React 仅重建同一宠物节点时不会被误判为换宠物；选择器和主宠物同时
存在时，也不会把较晚出现的选择器候选当成屏幕主宠物。真正换宠物后，底座
使用一次原子贴合切换到新落脚面，后续拖动才继续采用阻尼跟随。

候选在静止时最多每 500ms、拖动或切换时最多每 80ms 重新发现一次。UI
Automation 暂时失败时，最后一次有效边界在普通状态最多保留 1.25 秒，快速
切换状态最多保留 0.35 秒；持续失败则回退到宿主窗口锚点或安全隐藏。

### 3.3 拖动与 DPI

- 宠物未发现或隐藏时每 1 秒进行一次轻量窗口发现，并停止额度探测；
- 宠物隐藏但宿主仍存在时每 1 秒等待恢复；
- 宠物可见且静止时边界跟踪周期约 64ms；
- 检测到鼠标拖动或位置变化后切换到约 16ms；
- 快速模式在移动停止后保留 850ms；
- 完整 UI Automation 后代树扫描在空闲时最多每 500ms 一次，拖动或切换时
  最多每 80ms 一次；其余帧只读取缓存元素边界；
- 使用原生 `SetWindowPos`，不销毁或重新创建窗口；
- 启动前请求 Per-Monitor DPI Awareness V2；
- 所有位置最终限制在宠物所在显示器工作区内。

### 3.4 三维接触关系

底座不是宠物 DOM 子节点，因此采用视觉遮挡建立关联：

1. 底座包含中央抬升承托盘；
2. 底座向宠物边界上移；
3. 底座窗口放在官方宠物窗口之后；
4. 宠物遮住承托盘后沿；
5. 承托盘绘制接触阴影和反射光；
6. 平台前脸仍位于宠物下方并可点击。

这样既形成“宠物站在平台上”的纵深关系，也不会覆盖宠物按钮。平台前脸
区域的窗口命中仍属于 Sidecar，可以展开详情。

## 4. 额度数据

`src/native/CodexPetProbe.exe` 启动 Codex 自带的可执行文件：

```text
codex.exe app-server --listen stdio://
```

然后使用 JSONL 请求：

- `initialize`
- `account/read`
- `account/rateLimits/read`

输出前进行脱敏，只保留套餐、额度桶、使用百分比、窗口长度、重置时间和
可用 reset 数量。账户邮箱和凭证不会进入 Sidecar 输出。

自动刷新默认每 5 分钟一次。打开详情且数据超过 5 分钟，或用户点击
`Refresh` 时立即查询。没有发现可见宠物时不启动 app-server 探测，避免
登录后台空转。

底座显示实际返回额度窗口中剩余百分比最低的一项。详情卡展示全部实际
返回的窗口；没有返回的 5 小时、每日或其他窗口不会被推测出来。

## 5. 本周 Token 口径

Token 统计从本地时区周一 00:00 开始，只扫描
`~/.codex/sessions/**/*.jsonl` 中的：

```text
type = event_msg
payload.type = token_count
payload.info.total_token_usage
```

不读取或输出消息正文。每个会话按累计计数的正向差值聚合，重复通知增量
为零，累计计数回退时按新段处理。

底座的 `WEEK TOKENS` 包含缓存输入；详情拆分：

- 非缓存输入；
- 缓存输入比例；
- 输出；
- 推理输出；
- 有 Token 的本机会话数。

首次统计会为本周会话建立本地增量索引。索引只保存经过 SHA-256 处理的文件
标识、文件大小、修改时间和数字汇总，不保存原始路径、会话正文、账号信息或
凭证。后续刷新复用未变化文件的汇总，只重新解析发生变化的会话文件。每周一
自动建立新索引；索引损坏或缺失时安全回退为全量重建。

这是本机模型处理量，不是账单，也不能直接换算服务端额度百分比。

## 6. 主题系统

当前内置主题：

| ID | 显示名 | 特点 |
|---|---|---|
| `holo-cyan` | Holo Cyan 3D | 默认，青色承托盘与接触光 |
| `holo-amber` | Holo Amber 3D | 暖金能量线路 |
| `circuit-flat` | Circuit Flat | 更薄、更克制的平面芯片 |
| `princess-cradle` | Princess Cradle | 象牙、粉色软垫、珍珠和香槟金 |
| `forest-rune` | Forest Rune | 古石、苔藓和青色符文 |
| `clockwork-brass` | Clockwork Brass | 黄铜、胡桃木和琥珀能量管 |
| `moon-lotus` | Moon Lotus | 月白瓷、青玉莲瓣和靛蓝仪表面 |
| `sakura-shrine` | Sakura Shrine | 朱漆、樱花和黄铜构件 |
| `iron-throne` | Iron Throne | 224×96 高背剑阵与黑石阶，宠物遮挡中央座面 |

主题定义包含：

- 素材相对路径；
- 窗口宽高；
- 素材中真实落脚面的纵坐标与期望视觉重叠量；
- 指标内容纵向偏移；
- 是否绘制接触阴影；
- 接触阴影纵向位置；
- 正常额度进度色。

运行时的附着高度由 `ContactSurfaceY + ContactOverlap` 计算，不再把 PNG
窗体顶边误当作可见承托面。内置主题默认让承托面与宠物边界重叠 7px；
Iron Throne 的高背结构使用 3px。指标字体使用固定像素单位，避免 Windows
DPI 缩放只放大字体而不放大底座窗口。

指标层在主题素材之上绘制统一的信息衬底和文字阴影。深色科技主题使用低透明度
衬底，浅色或高纹理主题使用更高透明度；因此主题仍保留材质特征，但核心数字
不会依赖素材自身的明暗对比。

窗口 Region 按当前主题 PNG 的透明轮廓在 224×72 实际尺寸生成，不再使用
单一科技平台多边形。因此森林石块、莲瓣、摇篮曲线和樱花边角不会在切换
主题后被旧轮廓裁掉。

托盘的 `Base theme` 菜单切换主题，选择写入：

```text
%LOCALAPPDATA%\CodexPetDock\config.json
```

配置不放在安装目录，因此覆盖升级时保留。命令行也可临时指定：

```powershell
.\src\Start-CodexPetQuota.ps1 -Theme holo-amber
```

用户主题位于 `%LOCALAPPDATA%\CodexPetDock\themes\<theme-id>\`，每个目录只
包含 `theme.json` 与一张 PNG。启动时先完成字段白名单、规范路径、重解析点、
文件大小、图片尺寸、布局范围和文字可见性校验，再加入主题目录；无效主题只写
本地日志，不影响内置主题和主循环。加载器不接受任何代码或远程资源。

Codex 主题 Skill 使用临时配置目录和运行时诊断契约校验素材与几何，通过后再
原子安装 PNG 与 JSON。保存完成后设置
`Local\CodexPetDock.ReloadThemes` 本机命名事件；主进程下一次 UI Tick
重载目录，但不增加轮询计时器或网络请求。重复启动入口通过
`Local\CodexPetDock.Activate` 唤醒现有实例并显示连接状态。

## 7. 生命周期和失败方式

- 宠物不存在：隐藏底座和详情卡，不附着其他应用。
- app-server 查询失败：底座进入 `OFFLINE`，详情显示错误。
- 查询超时：终止子进程，不留下后台 Codex app-server。
- 用户退出：停止计时器、关闭探测进程、释放图片和 WinForms 对象。
- Codex 更新导致窗口或 UIA 契约变化：回退或隐藏，不修改官方文件自救。

## 8. 升级验证清单

Codex 每次大版本更新后至少验证：

1. 官方进程包路径仍可识别；
2. 宠物宿主窗口仍属于官方进程；
3. UIA 类名仍以 `codex-avatar-button` 开头；
4. 普通、通知、快捷对话、宠物选择四种状态都能重新锚定；
5. 单显示器、混合 DPI、多显示器拖动正常；
6. `account/read` 与 `account/rateLimits/read` 响应字段仍兼容；
7. 九款内置主题都可点击、跟随和持久化；
8. 合法自定义主题可加载，包含可执行字段或越界资源的主题被拒绝；
9. 失败时只隐藏或报错，不读取凭证、不修改 Codex。

## 9. 当前限制

- 常驻界面仍由 Windows PowerShell + WinForms 承载；额度与 Token 探测已经
  迁移到原生 C# EXE，不再要求 Node.js。
- UI Automation 类名属于桌面 UI 结构，不是稳定的公开插件契约。
- 底座是独立顶层窗口，无法获得官方宠物 DOM 的原生事件和布局能力。
- 本周 Token 只包含仍保留在本机的会话记录。

公开发布的建议迁移路径见 [distribution.md](distribution.md)。
