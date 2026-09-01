import Cocoa
import CoreGraphics
import ApplicationServices

/// 通过 CGEvent 事件点监听全局键盘事件。
/// 每次按下按键时回调，携带按键码和映射后的 x 位置。
class KeyboardMonitor {
    typealias KeyHandler = (_ keyCode: UInt16, _ character: String?) -> Void

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    var onKeyPress: KeyHandler?

    /// 是否静音系统按键警告音（"咚咚咚"）。
    /// 开启后，当焦点不在文本输入框时按下纯字符键，
    /// 会消费该事件以阻止系统播放警告音，但 BarBar 效果照常触发。
    var suppressSystemBeeps = true

    /// 尝试创建并启用全局事件点。
    /// 如果未授予辅助功能权限，则返回 false。
    func start() -> Bool {
        // 我们需要监听 keyDown 事件
        let mask = (1 << CGEventType.keyDown.rawValue)

        // 创建事件点——`self` 指针作为 userInfo 传入
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,          // 在 HID 层级创建事件点
            place: .headInsertEventTap,    // 插入到事件链头部
            options: .defaultTap,          // 活动事件点（可修改/拦截事件）
            eventsOfInterest: CGEventMask(mask),
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                // 只处理 keyDown
                guard type == .keyDown, let refcon = refcon else {
                    return Unmanaged.passUnretained(event)
                }

                let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(refcon).takeUnretainedValue()
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let character = monitor.characterForKeyCode(UInt16(keyCode))

                // 在主线程上触发回调
                DispatchQueue.main.async {
                    monitor.onKeyPress?(UInt16(keyCode), character)
                }

                // 静音系统警告音：消费"无输入焦点时的纯字符键"事件
                if monitor.suppressSystemBeeps,
                   monitor.shouldConsumeForBeepSuppression(event, keyCode: UInt16(keyCode)) {
                    return nil   // 消费事件，系统不再播放"咚"
                }

                // 放行事件（不消费它）
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else {
            print("KeyboardMonitor: failed to create event tap. Is Accessibility enabled?")
            return false
        }

        self.eventTap = tap

        // 添加到当前 run loop
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)

        // 启用事件点
        CGEvent.tapEnable(tap: tap, enable: true)

        print("KeyboardMonitor: event tap started successfully")
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    /// 尽可能为常见按键码（US 布局）做字符映射
    private func characterForKeyCode(_ keyCode: UInt16) -> String? {
        let keyMap: [UInt16: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
            8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
            16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 36: "↵",
            37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "n", 46: "m", 47: ".", 49: " ", 50: "`",
        ]
        return keyMap[keyCode]
    }

    // MARK: - 系统警告音静音

    /// 判断是否应消费该 keyDown 事件以阻止系统播放警告音。
    /// 采用"保守优先"策略：只有在**明确**确认焦点位于普通 UI 控件
    /// （按钮、复选框等，而非文本输入）时才消费事件；
    /// 任何查询失败、角色未知、或疑似文本输入的情况都放行，
    /// 确保绝不吞掉用户的正常输入。
    private func shouldConsumeForBeepSuppression(_ event: CGEvent, keyCode: UInt16) -> Bool {
        // 有 Command/Ctrl/Option 修饰的按键（快捷键）不消费
        let flags = event.flags
        let hasShortcutModifier = flags.intersection([.maskCommand, .maskControl, .maskAlternate]).rawValue != 0
        if hasShortcutModifier { return false }

        // 导航/功能/修饰键不消费（可能仍承载其他功能）
        let specialKeys: Set<UInt16> = [
            36, 48, 49, 51, 53,                    // Return, Tab, Space, Delete, Esc
            123, 124, 125, 126, 117,               // 方向键, 前向删除
            96, 97, 98, 99, 100, 101, 103, 109, 111, 118, 120, 122,  // F1–F12
        ]
        if specialKeys.contains(keyCode) { return false }

        // 修饰键自身（Shift/Ctrl/Option/Cmd/Caps/Fn）不消费
        if (54...63).contains(Int(keyCode)) { return false }

        // 只有明确判定为非输入控件的普通 UI 控件时才消费
        switch focusedElementClass() {
        case .plainUIControl:   return true    // 确定是按钮等普通控件 → 消费警告音
        case .textInput:        return false   // 文本输入 → 放行
        case .unknown:          return false   // 不确定 → 放行（绝不吞输入）
        }
    }

    /// 焦点元素的分类：文本输入 / 普通 UI 控件 / 未知。
    /// 查询失败、角色缺失、通用容器等一律归为 unknown（放行）。
    private enum FocusedElementClass {
        case textInput
        case plainUIControl
        case unknown
    }

    /// 通过辅助功能 API 判断当前前台焦点元素的类别。
    private func focusedElementClass() -> FocusedElementClass {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedAppRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide,
                                            kAXFocusedApplicationAttribute as CFString,
                                            &focusedAppRef) == .success,
              let focusedApp = focusedAppRef else {
            return .unknown
        }
        let appElement = focusedApp as! AXUIElement

        var focusedElementRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement,
                                            kAXFocusedUIElementAttribute as CFString,
                                            &focusedElementRef) == .success,
              let focusedElement = focusedElementRef else {
            return .unknown
        }
        let focused = focusedElement as! AXUIElement

        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused,
                                            kAXRoleAttribute as CFString,
                                            &roleRef) == .success,
              let role = roleRef as? String else {
            return .unknown
        }

        // 明确的文本输入控件角色 → 放行
        let textRoles: Set<String> = [
            "AXTextField", "AXTextArea", "AXComboBox",
            "AXSearchField", "AXSecureTextField",
            "AXTextView", "AXWebArea", "AXUnknown",
        ]
        if textRoles.contains(role) { return .textInput }

        // 明确的普通 UI 控件角色（非文本输入）→ 可安全消费警告音
        let plainRoles: Set<String> = [
            "AXButton", "AXCheckBox", "AXRadioButton",
            "AXPopUpButton", "AXSlider", "AXStepper",
            "AXColorWell", "AXDisclosureTriangle",
            "AXMenuBarItem", "AXToolbarButton",
        ]
        if plainRoles.contains(role) { return .plainUIControl }

        // 其他所有角色（AXGroup、AXWindow、AXScrollArea、AXCell 等）
        // 都可能是容器或未知结构 → 保守放行
        return .unknown
    }
}

