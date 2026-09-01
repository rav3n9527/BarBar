#!/bin/bash
# 直接运行 BarBar（绕过 LaunchServices / `open` 的激活问题）。
# 推荐使用此方式启动——`open` 可能导致菜单栏应用（LSUIElement）
# 的 Touch Bar 接管被静默忽略。
set -euo pipefail

APP_BUNDLE="build/BarBar.app"

if [ ! -f "${APP_BUNDLE}/Contents/MacOS/BarBar" ]; then
    echo "❌ 尚未编译。请先运行 ./build.sh。"
    exit 1
fi

# 结束已有的实例，避免同时运行两个
pkill -x BarBar 2>/dev/null || true

echo "🎵 正在启动 BarBar（按 Ctrl+C 退出）..."
exec "${APP_BUNDLE}/Contents/MacOS/BarBar"
