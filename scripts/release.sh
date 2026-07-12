#!/bin/bash
# ──────────────────────────────────────────────────────────
#  scripts/release.sh — ReTagger 一键版本发布
#
#  用法:
#    ./scripts/release.sh 1.6.0          # 指定新版本号
#    ./scripts/release.sh 1.6.0 --dry-run # 仅预览变更，不执行
#    ./scripts/release.sh --current       # 查看当前版本号
#
#  执行流程:
#    1. 校验版本格式（语义化版本 X.Y.Z）
#    2. 更新 project.pbxproj 中的 MARKETING_VERSION
#    3. 自动生成 CURRENT_PROJECT_VERSION（YYMMDDHHMM 时间戳）
#    4. xcodebuild 构建验证
#    5. Git commit + tag
# ──────────────────────────────────────────────────────────

set -euo pipefail

# ── 常量 ──
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PBXPROJ="${PROJECT_ROOT}/ReTagger.xcodeproj/project.pbxproj"
SCHEME="ReTagger"
CONFIGURATION="Debug"

# ── 颜色输出 ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()  { echo -e "${CYAN}ℹ ${RESET}$1"; }
ok()    { echo -e "${GREEN}✓ ${RESET}$1"; }
warn()  { echo -e "${YELLOW}⚠ ${RESET}$1"; }
fail()  { echo -e "${RED}✗ ${RESET}$1"; exit 1; }

# ── 读取当前版本号 ──
# 主 Target 的 MARKETING_VERSION（排除测试 Target 的 1.0）
read_current_version() {
    grep 'MARKETING_VERSION = ' "$PBXPROJ" \
        | grep -v '= 1.0;' \
        | head -1 \
        | sed 's/.*= //' \
        | sed 's/;.*//' \
        | tr -d '[:space:]'
}

read_current_build() {
    grep 'CURRENT_PROJECT_VERSION = ' "$PBXPROJ" \
        | grep -v '= 1;' \
        | head -1 \
        | sed 's/.*= //' \
        | sed 's/;.*//' \
        | tr -d '[:space:]'
}

# ── 参数处理 ──
DRY_RUN=false
NEW_VERSION=""

for arg in "$@"; do
    case "$arg" in
        --dry-run)  DRY_RUN=true ;;
        --current)
            echo -e "${BOLD}ReTagger 当前版本${RESET}"
            echo "  MARKETING_VERSION:        $(read_current_version)"
            echo "  CURRENT_PROJECT_VERSION:  $(read_current_build)"
            exit 0
            ;;
        --help|-h)
            echo "用法: $0 <version> [--dry-run]"
            echo ""
            echo "  <version>    新版本号，格式 X.Y.Z（如 1.6.0）"
            echo "  --dry-run    仅预览变更，不执行修改"
            echo "  --current    查看当前版本号"
            echo ""
            echo "示例:"
            echo "  $0 1.6.0"
            echo "  $0 1.5.19 --dry-run"
            exit 0
            ;;
        *)
            if [[ -z "$NEW_VERSION" ]]; then
                NEW_VERSION="$arg"
            else
                fail "未知参数: $arg（使用 --help 查看帮助）"
            fi
            ;;
    esac
done

[[ -z "$NEW_VERSION" ]] && fail "请指定版本号，如: $0 1.6.0"

# ── 校验版本格式 ──
if ! echo "$NEW_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    fail "版本号格式不正确: '$NEW_VERSION'（应为 X.Y.Z，如 1.6.0）"
fi

# ── 校验项目文件 ──
[[ -f "$PBXPROJ" ]] || fail "找不到项目文件: $PBXPROJ"

# ── 读取当前版本 ──
CURRENT_VERSION=$(read_current_version)
CURRENT_BUILD=$(read_current_build)
NEW_BUILD=$(date +"%y%m%d%H%M")

[[ -z "$CURRENT_VERSION" ]] && fail "无法从 project.pbxproj 中读取当前版本号"

if [[ "$NEW_VERSION" == "$CURRENT_VERSION" ]]; then
    fail "新版本号 ($NEW_VERSION) 与当前版本相同，无需更新"
fi

# ── 检查 Git 工作区 ──
cd "$PROJECT_ROOT"
if ! git diff --quiet HEAD 2>/dev/null; then
    warn "Git 工作区有未提交的修改，建议先 commit 或 stash"
    if [[ "$DRY_RUN" == false ]]; then
        read -p "是否继续？(y/N) " -n 1 -r
        echo
        [[ $REPLY =~ ^[Yy]$ ]] || exit 1
    fi
fi

# ── 预览变更 ──
echo ""
echo -e "${BOLD}═══════════════════════════════════════${RESET}"
echo -e "${BOLD}  ReTagger 版本发布${RESET}"
echo -e "${BOLD}═══════════════════════════════════════${RESET}"
echo ""
echo -e "  版本号:   ${RED}${CURRENT_VERSION}${RESET} → ${GREEN}${NEW_VERSION}${RESET}"
echo -e "  构建号:   ${RED}${CURRENT_BUILD}${RESET} → ${GREEN}${NEW_BUILD}${RESET}"
echo -e "  Git Tag:  ${CYAN}v${NEW_VERSION}${RESET}"
echo ""

if [[ "$DRY_RUN" == true ]]; then
    info "Dry-run 模式，以下变更不会实际执行"
    echo ""
    echo "  将执行的操作:"
    echo "    1. 更新 project.pbxproj 中 MARKETING_VERSION: $CURRENT_VERSION → $NEW_VERSION"
    echo "    2. 更新 project.pbxproj 中 CURRENT_PROJECT_VERSION: $CURRENT_BUILD → $NEW_BUILD"
    echo "    3. xcodebuild -scheme $SCHEME -configuration $CONFIGURATION build"
    echo "    4. git add + commit + tag v${NEW_VERSION}"
    echo ""
    ok "Dry-run 完成"
    exit 0
fi

# ── 确认执行 ──
read -p "确认发布？(y/N) " -n 1 -r
echo
[[ $REPLY =~ ^[Yy]$ ]] || { info "已取消"; exit 0; }

echo ""

# ── Step 1: 更新版本号 ──
info "Step 1/4: 更新版本号..."

sed -i '' "s/MARKETING_VERSION = ${CURRENT_VERSION};/MARKETING_VERSION = ${NEW_VERSION};/g" "$PBXPROJ"
sed -i '' "s/CURRENT_PROJECT_VERSION = ${CURRENT_BUILD};/CURRENT_PROJECT_VERSION = ${NEW_BUILD};/g" "$PBXPROJ"

# 验证更新结果
VERIFY_VERSION=$(read_current_version)
VERIFY_BUILD=$(read_current_build)

if [[ "$VERIFY_VERSION" != "$NEW_VERSION" ]]; then
    fail "版本号更新失败（期望 $NEW_VERSION，实际 $VERIFY_VERSION）"
fi
if [[ "$VERIFY_BUILD" != "$NEW_BUILD" ]]; then
    fail "构建号更新失败（期望 $NEW_BUILD，实际 $VERIFY_BUILD）"
fi

ok "版本号已更新: $NEW_VERSION ($NEW_BUILD)"

# ── Step 2: 构建验证 ──
info "Step 2/4: 构建验证..."

BUILD_LOG="${PROJECT_ROOT}/build_release.log"

if xcodebuild \
    -project "${PROJECT_ROOT}/ReTagger.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    build \
    > "$BUILD_LOG" 2>&1; then
    ok "构建成功"
    rm -f "$BUILD_LOG"
else
    fail "构建失败，详见 $BUILD_LOG"
fi

# ── Step 3: Git commit ──
info "Step 3/4: Git commit..."

git add "$PBXPROJ"
git commit -m "release: 发布 v${NEW_VERSION}"

ok "已提交: release: 发布 v${NEW_VERSION}"

# ── Step 4: Git tag ──
info "Step 4/4: 打 Git tag..."

TAG_NAME="v${NEW_VERSION}"

if git tag -l "$TAG_NAME" | grep -q "$TAG_NAME"; then
    warn "Tag $TAG_NAME 已存在，跳过"
else
    git tag -a "$TAG_NAME" -m "Release ${NEW_VERSION}"
    ok "已创建 tag: $TAG_NAME"
fi

# ── 完成 ──
echo ""
echo -e "${BOLD}═══════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  ✓ 发布完成！${RESET}"
echo -e "${BOLD}═══════════════════════════════════════${RESET}"
echo ""
echo "  版本:  $NEW_VERSION ($NEW_BUILD)"
echo "  Tag:   $TAG_NAME"
echo ""
echo "  后续操作:"
echo "    git push origin main          # 推送代码"
echo "    git push origin $TAG_NAME     # 推送 tag（自动触发 GitHub Actions：双架构 DMG + changelog + appcast）"
echo "    在 Xcode 中 Archive → App Store 提交"
echo ""
