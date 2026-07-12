#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────
#  scripts/package_direct.sh — 直发渠道（GitHub Release）单架构 DMG 打包
#
#  用法（按架构各调用一次）：
#    ARCH=arm64  ./scripts/package_direct.sh
#    ARCH=x86_64 ./scripts/package_direct.sh
#
#  环境变量：
#    ARCH                 必填，arm64 | x86_64
#    CODESIGN_IDENTITY    Developer ID Application 签名身份；缺省 "-"（本地 ad-hoc 冒烟）
#    SPARKLE_DIST_DIR     已解压的 Sparkle 发行目录（含 Sparkle.framework）；
#                         缺省自动下载到 build/sparkle-dist
#    APPLE_API_KEY_PATH / APPLE_API_KEY_ID / APPLE_API_ISSUER_ID
#                         App Store Connect API Key，三者齐备才执行公证
#
#  流程：xcodebuild（SPARKLE_ENABLED 编译条件 + 链接 Sparkle）
#      → 嵌入 Sparkle.framework → 注入 Info.plist 更新源配置
#      → Developer ID 内向外签名（直发 entitlements）→ DMG → 公证装订
#
#  版本号与构建号直接读取 project.pbxproj（由 scripts/release.sh 维护），
#  保证与 App Store 渠道同版本完全一致。
# ──────────────────────────────────────────────────────────
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PBXPROJ="${ROOT_DIR}/ReTagger.xcodeproj/project.pbxproj"
DIST_DIR="${ROOT_DIR}/dist"
ENTITLEMENTS="${ROOT_DIR}/ReTagger/Support/Distribution/ReTagger-Direct.entitlements"

SPARKLE_VERSION="2.9.4"
SPARKLE_PUBLIC_ED_KEY="+LI1alzpb3qC3FratMxA0qd+C4cDw4ElhV0NPh1U/+4="
FEED_BASE_URL="https://beautare.github.io/ReTagger"

ARCH="${ARCH:?请设置 ARCH=arm64 或 ARCH=x86_64}"
case "${ARCH}" in arm64|x86_64) ;; *) echo "不支持的架构: ${ARCH}" >&2; exit 1 ;; esac
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

# ── 版本信息（与 release.sh 相同的读取方式）──
VERSION=$(grep 'MARKETING_VERSION = ' "${PBXPROJ}" | grep -v '= 1.0;' | head -1 | sed 's/.*= //;s/;.*//' | tr -d '[:space:]')
BUILD_NUMBER=$(grep 'CURRENT_PROJECT_VERSION = ' "${PBXPROJ}" | grep -v '= 1;' | head -1 | sed 's/.*= //;s/;.*//' | tr -d '[:space:]')
echo "打包 ReTagger ${VERSION} (${BUILD_NUMBER}) [${ARCH}]"

# ── Sparkle 发行包（框架 + 工具）──
SPARKLE_DIST_DIR="${SPARKLE_DIST_DIR:-${ROOT_DIR}/build/sparkle-dist}"
if [[ ! -d "${SPARKLE_DIST_DIR}/Sparkle.framework" ]]; then
  echo "下载 Sparkle ${SPARKLE_VERSION} ..."
  mkdir -p "${SPARKLE_DIST_DIR}"
  curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
    | tar -xJ -C "${SPARKLE_DIST_DIR}"
fi

# ── 构建（App Store 渠道的 Release 配置 + 直发差异全部通过命令行注入）──
DERIVED="${ROOT_DIR}/build/direct-${ARCH}"
rm -rf "${DERIVED}"
xcodebuild \
  -project "${ROOT_DIR}/ReTagger.xcodeproj" \
  -scheme ReTagger \
  -configuration Release \
  -derivedDataPath "${DERIVED}" \
  -destination "generic/platform=macOS" \
  ARCHS="${ARCH}" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) SPARKLE_ENABLED' \
  OTHER_LDFLAGS='$(inherited) -framework Sparkle' \
  FRAMEWORK_SEARCH_PATHS="\$(inherited) ${SPARKLE_DIST_DIR}" \
  build

APP="${DERIVED}/Build/Products/Release/ReTagger.app"
[[ -d "${APP}" ]] || { echo "构建产物缺失: ${APP}" >&2; exit 1; }

# ── 嵌入 Sparkle.framework ──
cp -R "${SPARKLE_DIST_DIR}/Sparkle.framework" "${APP}/Contents/Frameworks/"

# ── 注入直发渠道更新源配置（App Store 渠道的 Info.plist 不含这些键）──
INFO_PLIST="${APP}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :SUFeedURL string ${FEED_BASE_URL}/appcast-${ARCH}.xml" "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string ${SPARKLE_PUBLIC_ED_KEY}" "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c "Add :SUEnableInstallerLauncherService bool true" "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c "Add :SUScheduledCheckInterval integer 86400" "${INFO_PLIST}"

# ── 签名：由内向外 ──
SPARKLE_FW="${APP}/Contents/Frameworks/Sparkle.framework"
if [[ "${CODESIGN_IDENTITY}" == "-" ]]; then
  # 本地冒烟：ad-hoc 深度签名，可直接运行验证，不可分发
  codesign --force --deep --sign - --options runtime --entitlements "${ENTITLEMENTS}" "${APP}"
else
  # TagLib 动态库（构建时 CODE_SIGNING_ALLOWED=NO，此处补签）
  for dylib in "${APP}/Contents/Frameworks/"libtag*.2.1.1.dylib; do
    codesign --force --options runtime --timestamp --sign "${CODESIGN_IDENTITY}" "${dylib}"
  done
  # Sparkle 内部组件（顺序与官方沙盒分发指引一致）
  codesign --force --options runtime --timestamp --preserve-metadata=entitlements \
    --sign "${CODESIGN_IDENTITY}" "${SPARKLE_FW}/Versions/B/XPCServices/Downloader.xpc"
  codesign --force --options runtime --timestamp \
    --sign "${CODESIGN_IDENTITY}" "${SPARKLE_FW}/Versions/B/XPCServices/Installer.xpc"
  codesign --force --options runtime --timestamp \
    --sign "${CODESIGN_IDENTITY}" "${SPARKLE_FW}/Versions/B/Autoupdate"
  codesign --force --options runtime --timestamp \
    --sign "${CODESIGN_IDENTITY}" "${SPARKLE_FW}/Versions/B/Updater.app"
  codesign --force --options runtime --timestamp \
    --sign "${CODESIGN_IDENTITY}" "${SPARKLE_FW}"
  # 主应用（直发 entitlements：沙盒 + Sparkle mach-lookup 例外）
  codesign --force --options runtime --timestamp \
    --entitlements "${ENTITLEMENTS}" --sign "${CODESIGN_IDENTITY}" "${APP}"
fi
codesign --verify --strict --verbose=2 "${APP}"

# ── DMG ──
STAGING="${DERIVED}/staging"
mkdir -p "${STAGING}" "${DIST_DIR}"
cp -R "${APP}" "${STAGING}/ReTagger.app"
ln -s /Applications "${STAGING}/Applications"

DMG_PATH="${DIST_DIR}/ReTagger-v${VERSION}-${ARCH}.dmg"
rm -f "${DMG_PATH}"
hdiutil create \
  -srcfolder "${STAGING}" \
  -volname "ReTagger ${VERSION}" \
  -fs HFS+ \
  -format UDZO \
  "${DMG_PATH}"

if [[ "${CODESIGN_IDENTITY}" != "-" ]]; then
  codesign --force --options runtime --timestamp --sign "${CODESIGN_IDENTITY}" "${DMG_PATH}"

  # 公证：三个 App Store Connect API Key 变量齐备才执行，本地打包可跳过
  if [[ -n "${APPLE_API_KEY_PATH:-}" && -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_API_ISSUER_ID:-}" ]]; then
    echo "提交公证..."
    xcrun notarytool submit "${DMG_PATH}" \
      --key "${APPLE_API_KEY_PATH}" \
      --key-id "${APPLE_API_KEY_ID}" \
      --issuer "${APPLE_API_ISSUER_ID}" \
      --wait
    xcrun stapler staple "${DMG_PATH}"
    xcrun stapler validate "${DMG_PATH}"
  else
    echo "跳过公证（未设置 APPLE_API_KEY_PATH/APPLE_API_KEY_ID/APPLE_API_ISSUER_ID）"
  fi
fi

echo "DMG: ${DMG_PATH}"
