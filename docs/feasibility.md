# 可行性与架构判断

## 结论

“在宠物基础上增加额度查看功能”可以做，但需要把“宠物基础上”理解为视觉和交互上的附着，而不是修改宠物资源包本身。

最合适的第一版是独立 Sidecar：

- 不修改 Codex 源码、安装目录、签名或 `app.asar`
- 不读取认证文件
- 不要求 Codex 开启 CDP
- 不干扰宠物原有的拖动、语音、通知和菜单行为
- Codex 更新后重新发现当前 CLI 与宠物窗口

## 本机观察

### 宠物包

本机自定义宠物目录结构为：

```text
~/.codex/pets/starry/
  pet.json
  spritesheet.webp
```

清单字段为：

```json
{
  "id": "starry",
  "displayName": "starry",
  "description": "...",
  "spriteVersionNumber": 2,
  "spritesheetPath": "spritesheet.webp"
}
```

这套契约描述角色和动画，不承载任意代码，也没有声明点击动作或扩展菜单的字段。

### 宠物窗口

Codex 当前把浮动宠物放在一个独立顶层窗口里。实测窗口具有这些可组合识别的特征：

- 进程属于已注册的 `OpenAI.Codex` Store 包
- 类名为 `Chrome_WidgetWin_1`
- 窗口可见
- 尺寸明显小于主窗口
- 是置顶工具窗口
- 当前标题为 `Codex`

原型不只依赖标题；标题变化后仍可用进程身份、窗口类型、尺寸和扩展样式进行保守匹配。

透明窗口内部会根据通知卡片、快捷对话等状态重新排版宠物，因此不能把窗口底边当作宠物底边。当前实现通过 Windows UI Automation 查找类名以 `codex-avatar-button` 开头的“Codex 宠物”元素，使用它的实时屏幕边界作为底座锚点。UI Automation 不可用时才回退到窗口锚点。

### 额度接口

官方 app-server 文档把 `account/rateLimits/read` 列为稳定账户接口。标准流程是：

1. 启动 `codex app-server --listen stdio://`
2. 发送 `initialize`
3. 发送 `initialized` 通知
4. 调用 `account/read` 与 `account/rateLimits/read`

响应可包含：

- 当前套餐类型
- `primary` / `secondary` 限额窗口
- `usedPercent`
- `windowDurationMins`
- `resetsAt`
- 月度 `individualLimit`
- 可用额度重置次数

原型只保留展示需要的字段。

## 方案比较

| 方案 | 是否改官方文件 | 更新兼容 | 能否真挂到宠物 DOM | 安全与维护 |
|---|---:|---:|---:|---|
| 修改 `app.asar` | 是 | 差 | 是 | 签名、Store 更新和回滚成本高，不采用 |
| CDP 注入 | 否 | 中到差 | 是 | 需要调试端口；Windows 新版生产运行时可能不监听 |
| 全局鼠标钩子劫持宠物点击 | 否 | 中 | 视觉上是 | 容易与拖动、语音和右键菜单冲突，不作为默认 |
| 附着式 Sidecar 底座 | 否 | 较好 | 否 | 可独立卸载、失败安全，推荐 |
| 独立悬浮球 | 否 | 好 | 否 | 功能简单但与现有宠物重复，用户体验不佳 |

## 为什么不直接沿用 Dream Skin 的 CDP

Dream Skin 的核心优点值得保留：

- 动态发现 Store 包
- 不修改 `WindowsApps` 与 `app.asar`
- 可恢复
- 对连接身份和回环地址做校验

但它解决的是整个渲染器的样式注入。额度宠物扩展不需要承受同样大的控制面。

Dream Skin 当前 Windows 文档和变更记录还指出，部分较新的 Owl/Codex 生产运行时即使保留 `--remote-debugging-port` 参数，也可能不实际开放监听。把额度查看功能绑定到 CDP，会使原本可以独立稳定运行的小功能继承一个更脆弱的启动条件。

因此本原型只借鉴它“动态发现、旁路、可恢复”的原则，不复用注入机制。

## 交互设计

默认状态：

- 宠物脚下出现一个约 224×72、带中央悬浮承托盘的暗蓝色全息芯片平台
- 平台前脸显示周额度剩余百分比与本周 Token；顶部细光带同步表达剩余进度
- 宠物自带的会话通知和下拉入口保持原样
- 不抢键盘焦点

点击底座：

- 在宠物旁边展开卡片
- 展示 5 小时、每日、每周或其他实际返回的限额
- 展示重置时间
- 展示可用 reset 数量（如果服务端返回）
- 展示本周 Token 总量、非缓存输入、缓存比例、输出量与会话数

隐藏规则：

- 宠物窗口不存在或持续不可见：底座与卡片隐藏
- 拖动时短暂的窗口状态切换会保留底座，并继续按窗口句柄跟随
- 通知出现、消失、快捷对话展开或切换宠物导致宠物在透明窗口内移动时，底座会刷新 UI Automation 元素并按新边界重新定位
- app-server 查询失败：底座显示 `!`，卡片显示错误，不猜测额度
- Codex 更新导致匹配失效：安全隐藏，不附着到其他应用窗口

## 升级兼容策略

每次启动都重新发现：

1. `%LOCALAPPDATA%\OpenAI\Codex\bin\*\codex.exe` 中最新的桌面 CLI
2. 当前运行的官方 `OpenAI.Codex` 进程
3. 当前可见的小型置顶工具窗口

不保存版本化的 `WindowsApps` 路径，不修改包权限。

未来如果 Codex 官方为宠物增加 action/plugin manifest，应优先迁移到官方接口；Sidecar 可以保留为旧版本兼容层。

## 安全边界

- 不读取、打印或复制 `auth.json`
- 不输出账户邮箱
- Token 聚合只读取 `token_count`、事件时间戳和会话累计计数，不读取消息正文
- 不开放本地 HTTP/CDP 端口
- app-server 使用标准输入输出，查询完成后退出
- 不消费 reset，不调用写接口
- 不改变额度、账户、配置或宠物文件
- 只识别属于官方 Codex 包的窗口

## 本周 Token 口径

- 周期从本地时区周一 00:00 开始
- 对每个仍在本机的 session JSONL，按 `total_token_usage.total_tokens` 的正向差值求和
- 重复的 token 通知增量为零，不会重复计算
- 累计计数重启时把新计数作为新一段处理
- `total_tokens = input_tokens + output_tokens`，其中 `cached_input_tokens` 是输入量的子集
- 底座显示包含缓存输入的总处理量；详情层拆分非缓存输入、缓存比例和输出
- 这是本机活动统计，不是服务端计费或结算数据，也不能直接换算限额百分比

## 下一阶段建议

在原型得到实际使用反馈后再做以下工作：

1. 继续验证底座在更多 DPI、多显示器和宠物尺寸下的锚点
2. 增加浅色/深色主题与中文 UI
3. 改为长期 app-server 会话，订阅 `account/rateLimits/updated`
4. 打包为签名的单文件托盘程序
5. 增加启动项，但必须让用户显式选择
