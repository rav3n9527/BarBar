#!/bin/bash
# 一键推送代码到 GitHub。
# 用法：
#   ./git-push.sh                      # 自动提交所有改动并推送（默认提交信息）
#   ./git-push.sh "修复了按键定位"      # 用自定义提交信息
#
# 凭据处理（按顺序尝试）：
#   1. 使用系统钥匙串 / 已保存的凭据（推荐，无需 token）
#   2. 使用环境变量 GITHUB_TOKEN（安全，不进脚本、不进 git 配置）
#
# 安全提示：
#   - 切勿把 token 硬编码进本脚本
#   - 建议用 `git config credential.helper osxkeychain` 让 macOS 记住凭据

set -euo pipefail

# ---- 配置 ---------------------------------------------------------------
REMOTE="origin"
BRANCH="main"
# 仓库地址（不含 token，token 只从环境变量读取）
REPO_URL="https://github.com/rav3n9527/BarBar.git"

# ---- 默认提交信息 ---------------------------------------------------------
COMMIT_MSG="${1:-}"
if [ -z "$COMMIT_MSG" ]; then
    COMMIT_MSG="更新：$(date '+%Y-%m-%d %H:%M')"
fi

echo "🚀 BarBar 一键推送脚本"

# ---- 检查是否在仓库中 -----------------------------------------------------
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "❌ 当前目录不是 git 仓库。请在 BarBar 目录下运行。"
    exit 1
fi

# ---- 检查是否有改动 -------------------------------------------------------
CHANGES=$(git status --porcelain)
if [ -z "$CHANGES" ]; then
    echo "✅ 没有需要提交的改动，跳过提交。"
else
    echo "📝 暂存并提交以下改动："
    git status --short | head -30
    git add -A
    git commit -m "$COMMIT_MSG"
    echo "✅ 已提交：$COMMIT_MSG"
fi

# ---- 确保远程地址正确（不带 token）---------------------------------------
CURRENT_REMOTE=$(git remote get-url "$REMOTE" 2>/dev/null || true)
if [ "$CURRENT_REMOTE" != "$REPO_URL" ]; then
    git remote set-url "$REMOTE" "$REPO_URL"
    echo "🔗 已重置远程地址：$REPO_URL"
fi

# ---- 推送 --------------------------------------------------------------
echo "⬆️  正在推送到 GitHub（分支 ${BRANCH}）..."

# 组装带 token 的推送 URL（仅当设置了 GITHUB_TOKEN 环境变量时）
PUSH_URL="$REPO_URL"
if [ -n "${GITHUB_TOKEN:-}" ]; then
    PUSH_URL="https://x-access-token:${GITHUB_TOKEN}@github.com/rav3n9527/BarBar.git"
    echo "🔑 使用环境变量中的 GITHUB_TOKEN 认证"
fi

if git push "$PUSH_URL" "$BRANCH" 2>/tmp/barbar_push_err.txt; then
    echo "✅ 推送成功！"
    rm -f /tmp/barbar_push_err.txt
else
    echo "❌ 推送失败："
    cat /tmp/barbar_push_err.txt
    rm -f /tmp/barbar_push_err.txt
    echo ""
    echo "可能的原因与解决方法："
    echo "  1. 未登录 GitHub → 运行: git config --global credential.helper osxkeychain"
    echo "     （macOS 钥匙串会记住凭据，之后就不用重复输入）"
    echo "  2. 需要 token → 设置环境变量后重试:"
    echo "     export GITHUB_TOKEN='你的token'"
    echo "  3. token 无写入权限 → 在 GitHub 确认 token 已勾选 Contents: Read and write"
    exit 1
fi
