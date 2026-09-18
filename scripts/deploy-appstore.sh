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
#    4. 编译生成 Release 归档 (.xcarchive)
#    5. 导出 Mac App Store PKG 安装包
#    6. 上传 PKG、应用元数据并提交审核 (asc publish appstore)
#    7. 打印发布状态看板 (asc status)
# ──────────────────────────────────────────────────────────

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

APP_ID="6757285866"
TEAM_ID="L2GSNW7RA2"
PROJECT="ReTagger.xcodeproj"
SCHEME="ReTagger"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/ReTagger.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
METADATA_DIR="./metadata"

# 0. 检查前置工具
if ! command -v asc &> /dev/null; then
  echo "❌ 未检测到 asc CLI，请先安装: https://asccli.sh"
  exit 1
fi

# 1. 获取当前版本号（以 Xcode 工程 project.pbxproj 为真实依据，并自动同步 package.json）
PBXPROJ="$PROJECT/project.pbxproj"
if [ -f "$PBXPROJ" ]; then
  VERSION=$(grep 'MARKETING_VERSION = ' "$PBXPROJ" | grep -v '= 1.0;' | head -1 | sed 's/.*= //' | sed 's/;.*//' | tr -d '[:space:]')
fi

if [ -z "${VERSION:-}" ] && [ -f "package.json" ]; then
  VERSION=$(node -p "require('./package.json').version")
fi

if [ -z "${VERSION:-}" ]; then
  echo "❌ 无法从 project.pbxproj 或 package.json 中解析版本号！"
  exit 1
fi

# 确保 package.json 与工程版本号保持完全一致
if [ -f "package.json" ]; then
  node -e "const fs=require('fs'); const p=require('./package.json'); if(p.version!=='$VERSION'){p.version='$VERSION'; fs.writeFileSync('package.json', JSON.stringify(p, null, 2)+'\n');}" 2>/dev/null || true
fi

echo "🚀 开始发布 ReTagger (macOS) v${VERSION} 到 Mac App Store..."

# 2. 检查并确保当前版本的元数据目录存在且包含 json 文件
VERSION_META_DIR="$METADATA_DIR/version/$VERSION"
HAS_JSON=false
if [ -d "$VERSION_META_DIR" ] && compgen -G "$VERSION_META_DIR/*.json" > /dev/null; then
  HAS_JSON=true
fi

if [ "$HAS_JSON" = false ]; then
  echo "⚠️  未在 $VERSION_META_DIR 中检测到元数据 JSON，正在从已有版本复制模板..."
  LATEST_EXISTING_V=$(find "$METADATA_DIR/version" -mindepth 1 -maxdepth 1 -type d ! -name "$VERSION" 2>/dev/null | while read -r d; do
    if compgen -G "$d/*.json" > /dev/null; then
      echo "$d"
    fi
  done | sort -V | tail -n 1)

  if [ -n "$LATEST_EXISTING_V" ]; then
    mkdir -p "$VERSION_META_DIR"
    cp "$LATEST_EXISTING_V"/*.json "$VERSION_META_DIR/"
    echo "💡 已从 $(basename "$LATEST_EXISTING_V") 复制元数据模板，请按需修改 whatsNew。"
  else
    echo "❌ 无法找到基线元数据模板，请先运行: asc metadata pull --app $APP_ID --platform MAC_OS --version <已有版本> --dir $METADATA_DIR"
    exit 1
  fi
fi

# 3. 递增并同步当前时间戳构建号到 project.pbxproj
BUILD_NUMBER=$(date +"%y%m%d%H%M")
echo "🔢 1/5 更新构建号: ${BUILD_NUMBER}..."
sed -i '' -E "s/(CURRENT_PROJECT_VERSION = )([0-9]+)(;)/\1${BUILD_NUMBER}\3/g" "$PROJECT/project.pbxproj"

# 4. 编译生成 macOS Release 归档 (.xcarchive)
echo "📦 2/5 正在生成 macOS Release 归档 (.xcarchive)..."
mkdir -p "$BUILD_DIR"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  archive

# 5. 检查并修复 Beta 系统构建号（如果以字母结尾）
APP_INFO_PLIST="$ARCHIVE_PATH/Products/Applications/${SCHEME}.app/Contents/Info.plist"
if [ -f "$APP_INFO_PLIST" ]; then
  CURRENT_OS_BUILD=$(plutil -extract BuildMachineOSBuild raw "$APP_INFO_PLIST" 2>/dev/null || true)
  if [[ "$CURRENT_OS_BUILD" =~ [a-zA-Z]$ ]]; then
    CLEANED_OS_BUILD="${CURRENT_OS_BUILD%?}"
    echo "🔧 剥离 Beta 系统构建号后缀: $CURRENT_OS_BUILD → $CLEANED_OS_BUILD"
    plutil -replace BuildMachineOSBuild -string "$CLEANED_OS_BUILD" "$APP_INFO_PLIST"
  fi
fi

# 6. 导出符合 Mac App Store 规范的 PKG 安装包
echo "📤 3/5 正在导出 Mac App Store PKG 安装包..."
cat <<EOF > "$BUILD_DIR/ExportOptions.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>destination</key>
	<string>export</string>
	<key>method</key>
	<string>app-store-connect</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>teamID</key>
	<string>$TEAM_ID</string>
</dict>
</plist>
EOF

rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -allowProvisioningUpdates

PKG_PATH="$EXPORT_DIR/${SCHEME}.pkg"
if [ ! -f "$PKG_PATH" ]; then
  PKG_PATH=$(find "$EXPORT_DIR" -name "*.pkg" | head -n 1)
fi

if [ -z "$PKG_PATH" ] || [ ! -f "$PKG_PATH" ]; then
  echo "❌ 未在 $EXPORT_DIR 找到导出的 .pkg 文件！"
  exit 1
fi

echo "✅ PKG 导出成功: $PKG_PATH"

# 7. 上传 PKG、挂接元数据并提交审核
echo "☁️  4/5 上传到 App Store Connect 并提交审核..."
asc publish appstore \
  --app "$APP_ID" \
  --ipa "$PKG_PATH" \
  --build-number "$BUILD_NUMBER" \
  --platform MAC_OS \
  --version "$VERSION" \
  --metadata-dir "$METADATA_DIR" \
  --wait \
  --submit \
  --confirm

echo "🎉 5/5 发布与提审已完成！当前状态如下："
asc status --app "$APP_ID"
