# ReTagger

ReTagger 是一款面向音乐制作与收藏场景的 macOS 原生应用程序。它利用 AI 协助用户批量整理 MP3、FLAC、AAC / ALAC (M4A)、WAV、AIFF、Ogg、Opus 等主流音频格式的元数据。该产品以最少的人工干预完成“发现 → 修正 → 应用”的全链路，同时确保文件系统的安全落盘与可回滚性。

本项目仅包含前端 macOS 应用。该应用通过与后端服务通信来进行 AI 推理和元数据处理。

## 运行环境与依赖项

- **系统要求**：macOS 12.4 或更高版本。
- **开发工具**：Xcode 14 或以上版本。
- **后端服务**：需要配合 Intelli-Sight 后端服务运行，应用支持连接本地或者线上环境。

## 本地编译与运行指南

要在本地克隆和运行本项目，你需要完成以下几个简单的配置步骤：

### 1. 签名与开发者团队 (Signing & Capabilities)

为了成功编译运行本项目，你需要将 Xcode 中的开发者团队修改为你自己的账号：

1. 在 Xcode 中打开 `ReTagger.xcodeproj`。
2. 在左侧导航栏中选中顶部的 `ReTagger` 项目。
3. 选择 `ReTagger` Target，并点击上方的 **Signing & Capabilities** 标签。
4. 在 **Team** 下拉菜单中，选择你自己的 Apple ID 或你的 Apple Developer Team。如果你没有加入付费开发者计划，可以选择 Personal Team 并在本地运行即可。

### 2. Google OAuth 登录配置 (Client ID)

本项目包含通过 Google OAuth 登录的功能。出于安全考虑，公开的代码中使用了环境变量进行隔离，你需要填入自己的：

1. 前往 [Google Cloud Console](https://console.cloud.google.com/)。
2. 创建一个新的 OAuth 2.0 客户端 ID，类型选择 **Desktop app** (桌面应用)。
3. 获取你的 Client ID，例如 `123456789-abc.apps.googleusercontent.com`。
4. 在**仓库根目录**下创建或修改 `.env.local` 文件（可参考 `ReTagger/.env.example` 模板），加入以下内容：

```env
GOOGLE_CLIENT_ID=你的_CLIENT_ID
```

未配置时应用可正常编译运行，仅 Google 登录不可用。发布构建时，`EmbedDotEnvLocal` 构建阶段会把仓库根目录的 `.env.local` 拷入 App 包，使分发出去的应用也能读取到该配置。

### 3. 后端服务地址配置

应用默认通过 `AppConfiguration.swift` 文件管理后端 URL 配置。
- 在 **Debug（开发）模式** 下，它会默认指向本地后端服务 `http://localhost:8009`。
- 如果你有需要，可以在仓库根目录的 `.env.local` 文件中指定自定义的后端地址：

```env
BACKEND_URL=http://localhost:8009
```

### 4. AI 提供商 API Keys 配置

为了调用各大 AI 提供商（如 Gemini、ChatGPT、Grok 等）的能力，相关的 API 密钥**不应**直接写在代码中。
- 当你在本地成功运行 ReTagger 应用后，请前往应用内的 **“设置”** 界面。
- 在设置中找到 AI 提供商选项卡，并填入你自己的 API Key。密钥会由应用在本地安全存储。

## 版本管理

项目版本号统一由 Xcode 项目配置（`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`）作为唯一来源，运行时通过 `AppConfiguration.InfoPlist` 动态读取，所有视图和服务自动跟随，无需手动同步。

### 一键发布

使用 `scripts/release.sh` 自动完成版本号更新、构建验证和 Git 标签：

```bash
# 查看当前版本
./scripts/release.sh --current

# 预览发布流程（不实际执行）
./scripts/release.sh 1.6.0 --dry-run

# 执行发布
./scripts/release.sh 1.6.0
```

脚本执行流程：
1. 校验语义化版本格式（`X.Y.Z`）
2. 更新 `project.pbxproj` 中的 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`（自动生成 `YYMMDDHHMM` 时间戳）
3. `xcodebuild` 构建验证（失败则中止）
4. `git commit` + `git tag vX.Y.Z`

### 版本号命名规范

| 场景 | 版本号规则 | 示例 |
|---|---|---|
| 新功能发布 | minor +1 | `1.5.18` → `1.6.0` |
| Bug 修复 | patch +1 | `1.5.18` → `1.5.19` |
| 重大重构 | major +1 | `1.5.18` → `2.0.0` |
| 审核被拒重新提交 | 版本号不变，构建号自动递增 | — |

## 架构说明

- **ReTagger/Features**：业务功能的界面编排，包括状态协调与用户流程（如目录选择、元数据审核等）。
- **ReTagger/Views**：基础视觉组件与交互元素，实现统一的 Design System。
- **ReTagger/Core**：业务支撑层，包含文件系统操作、AI 提供商服务接口、缓存处理、配置以及鉴权相关模块。
- **scripts/**：自动化工具链，包括版本发布脚本等。

## 贡献指南

1. Fork 本仓库。
2. 创建你的 Feature 分支 (`git checkout -b feature/AmazingFeature`)。
3. 遵循现有的设计语言与架构原则。确保新增功能具有完善的容错处理，尤其是在处理本地文件写入时。
4. 提交你的改动 (`git commit -m 'feat: 增加了一些新特性'`)。请使用中文提交信息并遵循 `<类型>: <描述>` 规范。
5. 如需发布新版本，使用 `./scripts/release.sh <版本号>` 一键完成版本号更新、构建验证和 Git 标签。
6. 推送到分支 (`git push origin feature/AmazingFeature`)。
7. 开启一个 Pull Request。

## 开源协议

本项目基于 [MIT License](LICENSE) 开源。

第三方组件的许可信息见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)：

- **TagLib 2.1.1**（LGPL-2.1 / MPL-1.1 双许可）：以动态库形式随 App 分发，许可证全文见 `ReTagger/Support/TagLib/Licenses/`。
- **Google "G" 徽标**：Google LLC 商标，仅按其品牌规范用于"使用 Google 登录"按钮。
