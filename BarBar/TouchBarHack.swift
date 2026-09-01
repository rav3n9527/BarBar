import Cocoa

// 桥接到 TouchBarBridge.m 中的 Objective-C 实现。
// 使用 @_silgen_name 直接调用 C 函数（比从 Swift 中
// unsafeBitCast 私有 IMP 更安全，后者可能导致崩溃）。

@_silgen_name("BarBarPresent")
private func BarBarPresent(_ bar: NSTouchBar, _ identifier: NSString)

@_silgen_name("BarBarDismiss")
private func BarBarDismiss(_ bar: NSTouchBar)

/// 面向 Swift 的封装，用于私有 DFRFoundation 系统模态 API。
enum TouchBarHack {
    static var isAvailable: Bool { true }

    /// 接管整个 Touch Bar（placement = 1，完全接管）。
    static func present(_ touchBar: NSTouchBar, identifier: String) {
        BarBarPresent(touchBar, identifier as NSString)
    }

    /// 关闭系统模态 Touch Bar。
    static func dismiss(_ touchBar: NSTouchBar) {
        BarBarDismiss(touchBar)
    }
}
