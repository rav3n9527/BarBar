#!/bin/bash
# BarBar 编译脚本
# 用法：./build.sh
#
# 将源码编译为标准的 macOS .app 应用包。
# 需要 Xcode 命令行工具（xcode-select --install）

set -euo pipefail

APP_NAME="BarBar"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
SRC_DIR="${APP_NAME}"

echo "🎵 正在编译 ${APP_NAME}..."

# 清理旧的构建产物
rm -rf "${BUILD_DIR}"
mkdir -p "${MACOS}" "${RESOURCES}"

# 编译 Swift 源码
SOURCES=(
    "${SRC_DIR}/main.swift"
    "${SRC_DIR}/Particle.swift"
    "${SRC_DIR}/Ripple.swift"
    "${SRC_DIR}/ParticleSystem.swift"
    "${SRC_DIR}/AudioEngine.swift"
    "${SRC_DIR}/KeyboardMonitor.swift"
    "${SRC_DIR}/KeyPosition.swift"
    "${SRC_DIR}/Settings.swift"
    "${SRC_DIR}/BackgroundMode.swift"
    "${SRC_DIR}/ShooterScene.swift"
    "${SRC_DIR}/BarBarView.swift"
    "${SRC_DIR}/TouchBarHack.swift"
    "${SRC_DIR}/StatusPanelViewController.swift"
    "${SRC_DIR}/AboutWindowController.swift"
    "${SRC_DIR}/DonationWindowController.swift"
    "${SRC_DIR}/AppDelegate.swift"
)

# 编译 Objective-C 桥接层（私有 DFRFoundation API）
clang -c -fobjc-arc "${SRC_DIR}/TouchBarBridge.m" -o "TouchBarBridge.o" \
    -I "${SRC_DIR}"

swiftc \
    -o "${MACOS}/${APP_NAME}" \
    -framework Cocoa \
    -framework AVFoundation \
    -framework CoreGraphics \
    -framework ApplicationServices \
    -framework ServiceManagement \
    -O \
    "${SOURCES[@]}" \
    "TouchBarBridge.o"

# 复制 Info.plist
cp "${SRC_DIR}/Info.plist" "${CONTENTS}/Info.plist"

# 生成应用图标：将 AppIcon.png 转换为 AppIcon.icns（若存在）
if [ -f "${SRC_DIR}/AppIcon.png" ]; then
    ICONSET="${BUILD_DIR}/AppIcon.iconset"
    rm -rf "${ICONSET}"
    mkdir -p "${ICONSET}"

    # 生成所有必需的图标尺寸（标准 + Retina）
    sips -z 16 16     "${SRC_DIR}/AppIcon.png" --out "${ICONSET}/icon_16x16.png" >/dev/null 2>&1
    sips -z 32 32     "${SRC_DIR}/AppIcon.png" --out "${ICONSET}/icon_16x16@2x.png" >/dev/null 2>&1
    sips -z 32 32     "${SRC_DIR}/AppIcon.png" --out "${ICONSET}/icon_32x32.png" >/dev/null 2>&1
    sips -z 64 64     "${SRC_DIR}/AppIcon.png" --out "${ICONSET}/icon_32x32@2x.png" >/dev/null 2>&1
    sips -z 128 128   "${SRC_DIR}/AppIcon.png" --out "${ICONSET}/icon_128x128.png" >/dev/null 2>&1
    sips -z 256 256   "${SRC_DIR}/AppIcon.png" --out "${ICONSET}/icon_128x128@2x.png" >/dev/null 2>&1
    sips -z 256 256   "${SRC_DIR}/AppIcon.png" --out "${ICONSET}/icon_256x256.png" >/dev/null 2>&1
    sips -z 512 512   "${SRC_DIR}/AppIcon.png" --out "${ICONSET}/icon_256x256@2x.png" >/dev/null 2>&1
    sips -z 512 512   "${SRC_DIR}/AppIcon.png" --out "${ICONSET}/icon_512x512.png" >/dev/null 2>&1
    sips -z 1024 1024 "${SRC_DIR}/AppIcon.png" --out "${ICONSET}/icon_512x512@2x.png" >/dev/null 2>&1

    # 打包为 .icns
    iconutil -c icns "${ICONSET}" -o "${RESOURCES}/AppIcon.icns"
    rm -rf "${ICONSET}"
    echo "✅ 图标：已生成 AppIcon.icns"
else
    # 回退：若存在预先构建好的 .icns 则直接复制
    if [ -f "${SRC_DIR}/AppIcon.icns" ]; then
        cp "${SRC_DIR}/AppIcon.icns" "${RESOURCES}/AppIcon.icns"
    fi
fi

# 复制捐赠二维码资源（若存在）
if [ -f "${SRC_DIR}/donation-qr.jpg" ]; then
    cp "${SRC_DIR}/donation-qr.jpg" "${RESOURCES}/donation-qr.jpg"
    echo "✅ 资源：已复制捐赠二维码"
fi

echo "✅ 编译完成：${APP_BUNDLE}"
echo ""
echo "运行方式："
echo "  open ${APP_BUNDLE}"
echo ""
echo "⚠️  首次运行：macOS 会请求辅助功能权限。"
echo "   前往：系统设置 → 隐私与安全 → 辅助功能 → 允许 BarBar"
