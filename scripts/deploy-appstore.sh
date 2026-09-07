#!/bin/bash
set -euo pipefail

# ──────────────────────────────────────────────────────────
#  scripts/deploy-appstore.sh — ReTagger (macOS) 一键 App Store 发布
#
#  用法:
#    npm run deploy:appstore
#
#  执行流程:
#    1. 读取当前版本号 (package.json)
#    2. 校验/准备元数据 (./metadata/version/<version>)
#    3. 自动更新时间戳构建号 (project.pbxproj)
#    4. 执行 asc publish appstore (自动 archive, export, upload, apply metadata, submit)
#    5. 打印发布状态看板 (asc status)
# ──────────────────────────────────────────────────────────

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

APP_ID="6757285866"
TEAM_ID="L2GSNW7RA2"
PROJECT="ReTagger.xcodeproj"
SCHEME="ReTagger"
METADATA_DIR="./metadata"

# 0. 检查前置工具
if ! command -v asc &> /dev/null; then
  echo "❌ 未检测到 asc CLI，请先安装: https://asccli.sh"
  exit 1
fi

# 1. 获取当前版本号
VERSION=$(node -p "require('./package.json').version")
echo "🚀 开始发布 ReTagger (macOS) v${VERSION} 到 Mac App Store..."

# 2. 检查并确保当前版本的元数据目录存在
if [ ! -d "$METADATA_DIR/version/$VERSION" ]; then
  echo "⚠️  未检测到 $METADATA_DIR/version/$VERSION，正在尝试从已有元数据复制初始化..."
  LATEST_EXISTING_V=$(ls -1 "$METADATA_DIR/version" 2>/dev/null | sort -V | tail -n 1 || true)
  if [ -n "$LATEST_EXISTING_V" ]; then
    mkdir -p "$METADATA_DIR/version/$VERSION"
    cp "$METADATA_DIR/version/$LATEST_EXISTING_V"/*.json "$METADATA_DIR/version/$VERSION/"
    echo "💡 已从 $LATEST_EXISTING_V 复制元数据模板，请确认 whatsNew 是否需调整。"
  fi
fi

# 3. 递增并同步当前时间戳构建号到 project.pbxproj
BUILD_NUMBER=$(date +"%y%m%d%H%M")
echo "🔢 更新构建号: ${BUILD_NUMBER}..."
sed -i '' -E "s/(CURRENT_PROJECT_VERSION = )([0-9]+)(;)/\1${BUILD_NUMBER}\3/g" "$PROJECT/project.pbxproj"

# 4. 执行全自动流水线：编译归档 -> 导出 -> 上传 -> 挂接版本与元数据 -> 提交审核
echo "📦 正在执行打包、上传与提审流程..."
asc publish appstore \
  --app "$APP_ID" \
  --project "$PROJECT" \
  --scheme "$SCHEME" \
  --platform MAC_OS \
  --version "$VERSION" \
  --build-number "$BUILD_NUMBER" \
  --metadata-dir "$METADATA_DIR" \
  --team-id "$TEAM_ID" \
  --archive-xcodebuild-flag=-allowProvisioningUpdates \
  --export-xcodebuild-flag=-allowProvisioningUpdates \
  --wait \
  --submit \
  --confirm

echo "🎉 发布与提审已完成！当前状态如下："
asc status --app "$APP_ID"
