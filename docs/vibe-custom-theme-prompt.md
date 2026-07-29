# 用 Vibe Coding 创建自定义底座

不想自己研究 PNG 尺寸和 `theme.json`？把下面的提示词交给 Codex、Claude Code
或其他能读写本机文件的编码助手，它会根据你的想法创建、校验并安装一个
Codex Pet Dock 底座。

## 使用方法

1. 确认 Codex Pet Dock 已安装；
2. 复制下面整段提示词；
3. 替换开头方括号中的主题设定；
4. 粘贴给编码助手，并允许它只在 Pet Dock 主题目录中写入文件；
5. 完成后从托盘 `Base theme` 菜单选择新主题。

如果已经有透明 PNG，把完整路径填进“现有图片”。没有图片则保留“无”，让具备
图像生成能力的助手创作；如果助手不能生成图片，它应停在素材准备步骤，不会用
带棋盘格或纯色背景的假透明图片蒙混过关。

## 一次完成提示词

```text
请为我创建并安装一个 Codex Pet Dock 自定义底座主题。

【我的设定】
- 主题概念：[例如：淡金色东方祥云，轻盈、帅气、有层次，不要俗艳]
- 主色与强调色：[例如：象牙白、淡金、少量青蓝光]
- 主题显示名：[例如：Golden Nimbus]
- 稳定主题 ID：[例如：your-name.golden-nimbus]
- 现有透明 PNG：[填写绝对路径；没有则写“无”]

【先确认环境】
1. 查找 Codex Pet Dock。优先使用当前仓库；否则检查
   %LOCALAPPDATA%\Programs\CodexPetDock。
2. 阅读 docs/custom-themes.md，以及自定义主题目录中的
   theme.example.json（如果存在），以实际项目契约为准。
3. 如果找不到完整的 Pet Dock 安装或主题规范，停止并告诉我缺少什么，不要猜测。

【严格边界】
1. 不得修改 Codex 安装目录、app.asar、官方宠物资源、Codex 配置或快捷方式。
2. 不得修改 Pet Dock 的业务源码。只创建一个纯数据主题：
   %LOCALAPPDATA%\CodexPetDock\themes\<theme-id>\
     theme.json
     platform.png
3. 主题不得包含脚本、CSS、JavaScript、命令、URL、外部依赖、绝对路径或
   theme.json 白名单之外的字段。
4. 不读取或输出 auth.json、Access Token、会话正文或其他凭证。
5. 如果目标主题目录已经存在，先展示将被替换的文件并征得我的确认；不要静默覆盖。

【图片要求】
1. platform.png 必须是真实透明背景的 PNG，只画底座，不画宠物。
2. 普通底座建议按 896×288 创作，对应运行时 224×72；需要高背结构时可以增高，
   但必须按项目允许的尺寸和预览结果设置。
3. 顶部要有清晰、连续的宠物落脚面；宠物脚部应与底座略微重叠，不能悬空。
4. 正面保留两个清楚的指标区域，并确保浅色文字在深色或半透明衬底上可读。
5. 图片内不得写入 WEEK LEFT、WEEK TOKENS、数字、Logo 或水印；这些由程序实时绘制。
6. 不得用棋盘格、白底或色键假装透明。检查 Alpha 通道和四角透明度。
7. 如果我提供现有 PNG，先检查格式、像素尺寸、文件大小、Alpha 通道和安全路径。
8. 如果你有图像生成/编辑工具，按我的设定生成并迭代素材；如果没有，明确告诉我
   需要提供什么样的透明 PNG，然后停止，不要生成低质量占位图。

【清单格式】
只使用 schemaVersion 1 和下面这些字段。先以此为起点，再根据图片实际接触面校准：

{
  "schemaVersion": 1,
  "id": "[稳定主题 ID]",
  "name": "[主题显示名]",
  "asset": "platform.png",
  "width": 224,
  "height": 72,
  "contactSurfaceY": 20,
  "contactOverlap": 7,
  "contentOffsetY": 0,
  "contactShadow": true,
  "contactShadowY": 20,
  "compactMetrics": false,
  "metricsScrimOpacity": 120,
  "accent": "#6FE8EF"
}

【实现与验证】
1. 先在临时目录完成素材和 theme.json，不要边试边覆盖正式主题。
2. 校验主题 ID 为 3–64 位小写字母、数字、点、短横线或下划线，且不与内置主题冲突；
   名称为 1–40 个显示字符。
3. 校验 platform.png 小于等于 10 MB，尺寸在 64×32 到 4096×4096 之间，
   不是符号链接/重解析点，并且与 theme.json 位于同一主题目录。
4. 校验 contactSurfaceY + contactOverlap 不超过运行时高度，指标文字不越界；
   落脚间隙应在项目诊断允许范围内。
5. 将候选主题复制到一个临时 ConfigDirectoryOverride 的 themes 子目录，运行
   src/Start-CodexPetQuota.ps1 -ThemeSwitchDiagnostics -AllowMultipleInstances
   做无界面的切换、持久化、字号、Alpha 覆盖和接触面验证。不得使用正式配置目录
   运行会改写用户当前主题的诊断。
6. 只有诊断通过后，才把 theme.json 和 platform.png 安装到正式主题目录。
7. 如果 Pet Dock 正在运行，尝试通过它的 Local\CodexPetDock.ReloadThemes
   命名事件请求热重载；事件不存在时，只告诉我从托盘点击
   Reload custom themes，不要模拟鼠标操作。
8. 最后报告：
   - 安装目录和两个文件的完整路径；
   - PNG 尺寸、大小和 Alpha 检查结果；
   - manifest 白名单、安全路径和布局诊断结果；
   - 如何在 Base theme 菜单选择它；
   - 任何仍需人工确认的视觉问题。

请先简短复述主题目标和写入边界，然后直接执行；只在覆盖已有主题或缺少图片能力时
暂停询问。
```

## 适合继续迭代的短提示词

主题安装后，如果只是觉得宠物悬空、文字不清楚或装饰遮挡指标，不必重新开始。把
截图和下面这段话交给同一个编码助手：

```text
请根据这张截图继续校准已安装的 Codex Pet Dock 主题 [主题 ID]。
只允许修改该主题目录中的 platform.png 和 theme.json，不得修改 Codex 或
Pet Dock 源码。先判断问题属于落脚面、重叠量、运行时高度、指标偏移、文字衬底还是
素材本身，再做最小修改。使用临时配置目录运行 ThemeSwitchDiagnostics；通过后才
更新正式主题，并报告修改前后参数与验证结果。
```

## 为什么提示词限制这么多

自定义主题是视觉素材，不是插件。把能力限制为一张本地 PNG 和一份白名单 JSON，
既能让编码助手完成大部分创作和校准工作，也不会把任意代码执行、远程资源或 Codex
安装修改带进主题系统。
