# Repository Guidelines

## 基本规则
- 总是用中文进行回复，保持专业且明确。
- 尽量避免编写兼容性补丁或历史平台分支，聚焦当前 macOS 目标环境的最佳解。
- 变更讨论以用户价值和系统稳定性为核心，不扩散无关信息。
- 当前最低支持版本为 macOS 12.4，所有交付需在该环境下可运行。
- 不要防御性编程。

## 项目定位
ReTagger 面向音乐制作与收藏场景，利用 AI 协助批量整理 MP3、FLAC、AAC / ALAC（M4A）、WAV、AIFF、Ogg、Opus 等主流音频格式的元数据。产品价值在于以最少的人工干预完成"发现 → 修正 → 应用"全链路，同时保持文件系统的安全落盘与可回滚。

本项目为前端 macOS 应用，对应的后端服务为独立的 Intelli-Sight 项目（闭源，未随本仓库发布）。前端通过后端 API 实现 AI 推理、元数据处理等功能，保持前后端职责分离；后端地址通过 `.env` / `.env.local` 配置。

## 结构地图
- `ReTagger/Features`：围绕具体任务的界面编排，负责状态协调与用户流程。
- `ReTagger/Views`：基础视觉组件与交互元素，实现统一设计语言。
- `ReTagger/Core`：业务支撑层，包含文件系统、AI 提供商、缓存、配置、设计系统等模块。
- `ReTaggerTests` 与 `ReTaggerUITests`：分别承载业务逻辑验证与端到端流程校验。
- 资源与样式统一维护在 `Assets.xcassets` 及 `DesignSystem` 目录，禁止在功能模块中散落私有样式。
- 左侧侧边栏顶部以"添加目录"图标按钮触发目录选择，旁侧"历史"菜单展示最近 50 条目录记录，列表仅显示完整路径并支持滚动，依赖 `AppCoordinator.recentDirectories` 同步状态。
- `Features/DirectorySelection` 中"选择目录"按钮下方仅展示最近 5 个访问记录（路径形式），数据持久化至 `AppSettings.recentDirectories`。
- **沙盒权限管理**：所有目录扫描统一由 `DirectorySelectionView.performScan` 执行，该方法内通过 `AppCoordinator.activateSecurityScope` 激活并持久化沙盒访问权限。权限持续保持至用户切换目录（调用 `reset` 释放旧权限），保证播放、元数据读写等后续操作具备沙盒授权。


## 架构原则
- **单向流程**：元数据采集、清洗、AI 推理、人工校验、写回文件，步骤不可跳跃，状态变更要可追溯。
- **协议驱动**：核心服务以协议暴露能力，具体实现可替换，便于引入新的 AI 渠道或文件策略。
- **数据可信**：所有外部输入在进入系统前完成标准化，保持统一编码、清晰来源以及失败时的回滚策略。
- **组合优先**：新增能力先评估现有组件是否可扩展，通过组合和配置扩张，而不是复制代码或新增平行结构。
- **体验一致**：界面反馈、文案语气、加载与错误状态必须遵循设计系统的约束。

## 编码原则
- **D.R.Y**：复用已有的批处理、校验和视图组件，避免在不同模块重复实现相似逻辑。
- **S.O.L.I.D**：以协议和小粒度对象划分职责，确保服务实现可互换，新增能力通过扩展而非修改既有代码。
- **显式状态**：清晰标识可变状态与持久化数据通道，预防隐式副作用。
- **防御性编程**：对外部输入和 AI 输出执行校验，失败时提供明确回退路径。

## 发布渠道
- **双渠道分发**：App Store（Xcode Archive 手动提交，应用内更新走 `AppUpdateService` 跳转商店）与 GitHub Release 直发（DMG + Sparkle 自动更新）。
- **渠道差异只通过 `SPARKLE_ENABLED` 编译条件表达**：日常 Debug/Release 构建与 App Store 流程完全不含 Sparkle；直发差异（编译条件、框架链接与嵌入、Info.plist 更新源、entitlements）全部由 `scripts/package_direct.sh` 在打包时注入，不修改 Xcode 工程。
- **发布流程**：`scripts/release.sh X.Y.Z` 更新版本并打 tag → 推送 tag 触发 `.github/workflows/release.yml` → 自动构建 arm64 / x86_64 双 DMG（Developer ID 签名 + 公证）、生成自动 changelog 的 GitHub Release，并将 `appcast-arm64.xml` / `appcast-x86_64.xml` 发布到 gh-pages 供 Sparkle 拉取。
- 直发版首启以授权气泡（`UpdatePermissionPromptView`）征询"自动检查更新"，选择由 Sparkle 持久化；直发版不含 Sign in with Apple（Apple 不支持 Developer ID 分发使用该受限权限），`LoginView` 在 `SPARKLE_ENABLED` 下隐藏 Apple 登录按钮，登录走邮箱 / Google。

## 研发流程
- 功能规划以“可交付场景”为单位，确保每次变更对用户流程有直接提升。
- 评审重点在于架构契合度、文件安全性、AI 结果校验机制以及性能边界。
- 质量保障覆盖真实文件目录、混合字符集和网络波动等场景，保证批处理的失败隔离与可恢复性。
- 版本冻结前复盘系统影响面，确认服务抽象、日志策略与用户沟通都已到位。

## 文档同步
- 若约束或技术栈发生变更，优先更新 `AGENTS.md`、`CLAUDE.md` 这两份文档，确保项目定位、架构原则与流程要求完全一致。
