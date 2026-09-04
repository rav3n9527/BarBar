import Cocoa

/// 捐赠窗口：展示支付宝收款码 + 两句幽默文案。
class DonationWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "投喂开发者"
        window.isReleasedWhenClosed = false
        self.init(window: window)
        buildUI()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        // 收款码
        let qrView = NSImageView()
        qrView.frame = NSRect(x: (340 - 220) / 2, y: 220, width: 220, height: 220)
        if let path = Bundle.main.path(forResource: "donation-qr", ofType: "jpg"),
           let qr = NSImage(contentsOfFile: path) {
            // 等比缩放显示
            qrView.image = qr
            qrView.imageScaling = .scaleProportionallyUpOrDown
        }
        content.addSubview(qrView)

        // 第一句文案
        let line1 = NSTextField(wrappingLabelWithString: "如果 BarBar 让你的 Touch Bar 没那么无聊，\n欢迎投喂——毕竟它是靠一个程序员的发际线换来的。")
        line1.frame = NSRect(x: 30, y: 166, width: 280, height: 36)
        line1.font = NSFont.systemFont(ofSize: 13)
        line1.alignment = .center
        line1.textColor = .secondaryLabelColor
        content.addSubview(line1)

        // 金句（醒目）
        let punchline = NSTextField(labelWithString: "这是投喂的一小步，却是人类的一大步。")
        punchline.frame = NSRect(x: 20, y: 138, width: 300, height: 20)
        punchline.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        punchline.alignment = .center
        punchline.textColor = .labelColor
        content.addSubview(punchline)

        // 第二句文案
        let line2 = NSTextField(wrappingLabelWithString: "每一笔打赏都会变成下一杯咖啡，\n每一杯咖啡都会变成下一条粒子效果。")
        line2.frame = NSRect(x: 30, y: 98, width: 280, height: 34)
        line2.font = NSFont.systemFont(ofSize: 13)
        line2.alignment = .center
        line2.textColor = .secondaryLabelColor
        content.addSubview(line2)

        // 底部提示
        let tip = NSTextField(labelWithString: "感谢每一位愿意投喂的善良人类 🫡")
        tip.frame = NSRect(x: 0, y: 52, width: 340, height: 18)
        tip.font = NSFont.systemFont(ofSize: 12)
        tip.textColor = .tertiaryLabelColor
        tip.alignment = .center
        content.addSubview(tip)

        // 关闭按钮
        let closeButton = NSButton(title: "关 闭", target: self, action: #selector(closeClicked))
        closeButton.setButtonType(.momentaryPushIn)
        closeButton.bezelStyle = .rounded
        closeButton.frame = NSRect(x: (340 - 100) / 2, y: 14, width: 100, height: 28)
        content.addSubview(closeButton)
    }

    @objc private func closeClicked() {
        window?.close()
    }
}
