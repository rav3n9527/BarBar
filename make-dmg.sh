#!/bin/bash
# 为 BarBar 制作带自定义 Finder 布局的精美 DMG 安装包。
# 用法：./make-dmg.sh
#
# 生成 BarBar-1.0.dmg。打开后，Finder 会展示 BarBar.app 和「应用程序」
# 快捷方式，配合背景图排列整齐，如同专业的安装包。
#
# 需先编译应用（./build.sh）。

set -euo pipefail

# ---- 配置 ---------------------------------------------------------------
APP_NAME="BarBar"
VERSION="1.0"
APP_BUNDLE="build/${APP_NAME}.app"
STAGING_DIR="dmg-staging"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
VOLUME_NAME="${APP_NAME} ${VERSION}"
MOUNT_POINT="/Volumes/${VOLUME_NAME}"

# 可选背景图（建议 660x400 的 PNG）。放到
# BarBar/dmg-background.png，或删除本行以跳过背景。
BACKGROUND_IMG="BarBar/dmg-background.png"

echo "📦 正在为 ${APP_NAME} ${VERSION} 制作 DMG..."

# ---- 前置检查 -----------------------------------------------------------
if [ ! -d "${APP_BUNDLE}" ]; then
    echo "❌ 未找到 ${APP_BUNDLE}。请先运行 ./build.sh。"
    exit 1
fi

# ---- 准备打包内容 ---------------------------------------------------
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"

# 复制应用
cp -R "${APP_BUNDLE}" "${STAGING_DIR}/"

# 创建「应用程序」快捷方式
ln -s /Applications "${STAGING_DIR}/Applications"

# 若存在背景图则复制
if [ -f "${BACKGROUND_IMG}" ]; then
    mkdir -p "${STAGING_DIR}/.background"
    cp "${BACKGROUND_IMG}" "${STAGING_DIR}/.background/background.png"
fi

# ---- 创建原始（未压缩）DMG --------------------------------------
RAW_DMG="${APP_NAME}-raw.dmg"
rm -f "${RAW_DMG}" "${DMG_NAME}"

hdiutil create \
    -volname "${VOLUME_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDRW \
    "${RAW_DMG}" >/dev/null

# ---- 配置 Finder 布局 ------------------------------------------
# 挂载、重新排列图标、设置背景，然后卸载。
hdiutil attach "${RAW_DMG}" -readonly -noverify >/dev/null

# 通过 AppleScript 排列图标：应用约在 25% 处，「应用程序」约在 75% 宽度处。
osascript <<EOF
tell application "Finder"
    tell disk "${VOLUME_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 100, 1060, 500}
        set arrangement of icon view options of container window to not arranged
        set icon size of icon view options of container window to 96
        set text size of icon view options of container window to 13
        set position of item "${APP_NAME}.app" of container window to {150, 180}
        set position of item "Applications" of container window to {510, 180}
        if exists file ".background:background.png" of container window then
            set background picture of icon view options of container window to file ".background:background.png" of container window
        end if
        close
    end tell
end tell
EOF

# 同步以确保布局元数据写入，然后卸载
sync
hdiutil detach "${MOUNT_POINT}" >/dev/null

# ---- 转换为压缩 DMG --------------------------------------------
hdiutil convert "${RAW_DMG}" -format UDZO -o "${DMG_NAME}" >/dev/null
rm -f "${RAW_DMG}"

# ---- 清理临时目录 -----------------------------------------------------
rm -rf "${STAGING_DIR}"

echo "✅ DMG 已创建：${DMG_NAME}"
echo ""
echo "分享此文件即可——用户双击打开后，把"
echo "BarBar.app 拖入「应用程序」文件夹即可完成安装。"
