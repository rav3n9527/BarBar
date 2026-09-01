import Cocoa

/// 一个简单的“关于 BarBar”窗口，显示图标、版本和版权信息。
class AboutWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "关于 BarBar"
        window.isReleasedWhenClosed = false
        self.init(window: window)
        buildUI()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        // 应用图标
        let iconView = NSImageView()
        iconView.frame = NSRect(x: (320 - 96) / 2, y: 190, width: 96, height: 96)
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let icon = NSImage(contentsOfFile: path) {
            iconView.image = icon
        } else {
            iconView.image = NSImage(named: NSImage.applicationIconName)
        }
        content.addSubview(iconView)

        // 应用名称
        let nameLabel = NSTextField(labelWithString: "BarBar")
        nameLabel.frame = NSRect(x: 0, y: 155, width: 320, height: 24)
        nameLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        nameLabel.alignment = .center
        content.addSubview(nameLabel)

        // 版本
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let versionLabel = NSTextField(labelWithString: "版本 \(version) (\(build))")
        versionLabel.frame = NSRect(x: 0, y: 128, width: 320, height: 18)
        versionLabel.font = NSFont.systemFont(ofSize: 12)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        content.addSubview(versionLabel)

        // 标语
        let taglineLabel = NSTextField(wrappingLabelWithString: "老Bar的最后一舞")
        taglineLabel.frame = NSRect(x: 40, y: 60, width: 240, height: 50)
        taglineLabel.font = NSFont.systemFont(ofSize: 12)
        taglineLabel.alignment = .center
        taglineLabel.textColor = .secondaryLabelColor
        content.addSubview(taglineLabel)

        // 版权
        let copyright = "© 2026 Raven9527. MIT License."
        let copyLabel = NSTextField(labelWithString: copyright)
        copyLabel.frame = NSRect(x: 0, y: 24, width: 320, height: 16)
        copyLabel.font = NSFont.systemFont(ofSize: 10)
        copyLabel.textColor = .tertiaryLabelColor
        copyLabel.alignment = .center
        content.addSubview(copyLabel)
    }
}
