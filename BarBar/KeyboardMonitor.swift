import Cocoa
import CoreGraphics

/// 通过 CGEvent 事件点监听全局键盘事件。
/// 每次按下按键时回调，携带按键码和映射后的 x 位置。
class KeyboardMonitor {
    typealias KeyHandler = (_ keyCode: UInt16, _ character: String?) -> Void

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    var onKeyPress: KeyHandler?

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
}
