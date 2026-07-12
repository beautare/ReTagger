#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────
#  scripts/update_appcast.sh — 向 Sparkle appcast 插入一个新版本条目
#
#  直发渠道按架构维护独立 feed（appcast-arm64.xml / appcast-x86_64.xml），
#  打包时已把对应架构的 SUFeedURL 写入 Info.plist，客户端各取所需。
#  不存在的 appcast 会从模板新建；最新条目始终插在最前。
#
#  所有参数通过环境变量传入（见 .github/workflows/release.yml）：
#    APPCAST_PATH, ARCH, VERSION, BUILD_NUMBER, MIN_OS,
#    DMG_URL, EDSIGNATURE, DMG_LENGTH, RELEASE_NOTES_URL
# ──────────────────────────────────────────────────────────
set -euo pipefail

: "${APPCAST_PATH:?}" "${ARCH:?}" "${VERSION:?}" "${BUILD_NUMBER:?}" "${MIN_OS:?}" \
  "${DMG_URL:?}" "${EDSIGNATURE:?}" "${DMG_LENGTH:?}" "${RELEASE_NOTES_URL:?}"

if [[ ! -f "${APPCAST_PATH}" ]]; then
  cat > "${APPCAST_PATH}" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <title>ReTagger Updates (${ARCH})</title>
    <link>https://beautare.github.io/ReTagger/appcast-${ARCH}.xml</link>
    <description>ReTagger for macOS release feed (${ARCH})</description>
    <language>zh</language>
    <!-- ITEMS -->
  </channel>
</rss>
EOF
fi

PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
ITEM_FILE=$(mktemp)
cat > "${ITEM_FILE}" <<EOF
    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${BUILD_NUMBER}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${MIN_OS}</sparkle:minimumSystemVersion>
      <description><![CDATA[<p><a href="${RELEASE_NOTES_URL}">在 GitHub 查看更新说明 / View release notes on GitHub</a></p>]]></description>
      <enclosure url="${DMG_URL}" sparkle:edSignature="${EDSIGNATURE}" length="${DMG_LENGTH}" type="application/octet-stream" />
    </item>
EOF

# 插入到 <!-- ITEMS --> 标记之后，最新版本始终排在最前面
sed -i '' -e "/<!-- ITEMS -->/r ${ITEM_FILE}" "${APPCAST_PATH}"
rm -f "${ITEM_FILE}"

echo "已更新 ${APPCAST_PATH}: ${VERSION} (build ${BUILD_NUMBER}, ${ARCH})"
