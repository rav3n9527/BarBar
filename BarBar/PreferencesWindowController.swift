import Cocoa
import ServiceManagement
import Darwin

/// 一个用代码构建的正式设置窗口，包含弹出菜单、滑条和复选框。
class PreferencesWindowController: NSWindowController {
    private let settings = Settings.shared

    // 控件
    private let effectPopup = NSPopUpButton()
    private let soundPopup = NSPopUpButton()
    private let idlePopup = NSPopUpButton()
    private let launchCheckbox = NSButton(checkboxWithTitle: "登录时自动启动 BarBar", target: nil, action: nil)
    private let volumeSlider = NSSlider()
    private let volumeValueLabel = NSTextField(labelWithString: "70%")
    private let pitchSlider = NSSlider()
    private let pitchValueLabel = NSTextField(labelWithString: "1.0x")
    private let glowCheckbox = NSButton(checkboxWithTitle: "显示背景彩条", target: nil, action: nil)
    private let glowHueSlider = NSSlider()
    private let glowHueLabel = NSTextField(labelWithString: "颜色")

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 365),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "偏好设置"
        window.isReleasedWhenClosed = false
        self.init(window: window)
        buildUI()
    }

    private func buildUI() {
        guard let window = window, let content = window.contentView else { return }

        // --- 视觉效果模式 ---
        let effectLabel = makeLabel("视觉效果")
        effectPopup.frame = NSRect(x: 150, y: 325, width: 200, height: 26)
        for mode in EffectMode.allCases {
            effectPopup.addItem(withTitle: mode.displayName)
        }
        effectPopup.selectItem(at: settings.effectMode.rawValue)
        effectPopup.target = self
        effectPopup.action = #selector(effectChanged)

        // --- 音效模式 ---
        let soundLabel = makeLabel("音效")
        soundPopup.frame = NSRect(x: 150, y: 285, width: 200, height: 26)
        for mode in SoundMode.allCases {
            soundPopup.addItem(withTitle: mode.displayName)
        }
        soundPopup.selectItem(at: settings.soundMode.rawValue)
        soundPopup.target = self
        soundPopup.action = #selector(soundChanged)

        // --- 音量 ---
        let volumeLabel = makeLabel("音量")
        volumeSlider.frame = NSRect(x: 150, y: 245, width: 160, height: 20)
        volumeSlider.minValue = 0
        volumeSlider.maxValue = 1
        volumeSlider.isContinuous = true
        volumeSlider.doubleValue = Double(settings.soundVolume)
        volumeSlider.target = self
        volumeSlider.action = #selector(volumeChanged)
        volumeValueLabel.frame = NSRect(x: 315, y: 245, width: 45, height: 20)
        volumeValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        volumeValueLabel.alignment = .left

        // --- 音调 ---
        let pitchLabel = makeLabel("音调")
        pitchSlider.frame = NSRect(x: 150, y: 205, width: 160, height: 20)
        pitchSlider.minValue = 0.5
        pitchSlider.maxValue = 2.0
        pitchSlider.isContinuous = true
        pitchSlider.doubleValue = Double(settings.soundPitch)
        pitchSlider.target = self
        pitchSlider.action = #selector(pitchChanged)
        pitchValueLabel.frame = NSRect(x: 315, y: 205, width: 45, height: 20)
        pitchValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        pitchValueLabel.alignment = .left

        // --- 背景彩条 ---
        let glowLabel = makeLabel("背景彩条")
        glowCheckbox.frame = NSRect(x: 150, y: 168, width: 140, height: 20)
        glowCheckbox.state = settings.showCenterGlow ? .on : .off
        glowCheckbox.target = self
        glowCheckbox.action = #selector(glowToggled)
        glowHueSlider.frame = NSRect(x: 150, y: 135, width: 160, height: 20)
        glowHueSlider.minValue = 0
        glowHueSlider.maxValue = 1
        glowHueSlider.isContinuous = true
        glowHueSlider.doubleValue = Double(settings.glowHue)
        glowHueSlider.target = self
        glowHueSlider.action = #selector(glowHueChanged)
        glowHueLabel.frame = NSRect(x: 315, y: 135, width: 45, height: 20)
        glowHueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        glowHueLabel.alignment = .left

        // --- 空闲让出延时 ---
        let idleLabel = makeLabel("空闲让出")
        idlePopup.frame = NSRect(x: 150, y: 100, width: 200, height: 26)
        idlePopup.addItems(withTitles: ["1 秒", "3 秒", "5 秒", "10 秒", "永不"])
        let delay = settings.idleDismissDelay
        switch delay {
        case 1.0: idlePopup.selectItem(at: 0)
        case 3.0: idlePopup.selectItem(at: 1)
        case 5.0: idlePopup.selectItem(at: 2)
        case 10.0: idlePopup.selectItem(at: 3)
        default: idlePopup.selectItem(at: 4)
        }
        idlePopup.target = self
        idlePopup.action = #selector(idleChanged)

        // --- 登录时启动 ---
        let launchLabel = makeLabel("开机启动")
        launchCheckbox.frame = NSRect(x: 150, y: 62, width: 200, height: 20)
        launchCheckbox.state = settings.launchAtLogin ? .on : .off
        launchCheckbox.target = self
        launchCheckbox.action = #selector(launchToggled)

        // 布局标签
        positionLabel(effectLabel, above: effectPopup)
        positionLabel(soundLabel, above: soundPopup)
        positionLabel(volumeLabel, above: volumeSlider)
        positionLabel(pitchLabel, above: pitchSlider)
        positionLabel(glowLabel, above: glowCheckbox)
        positionLabel(idleLabel, above: idlePopup)
        positionLabel(launchLabel, above: launchCheckbox)

        // 添加所有视图
        for view in [effectLabel, effectPopup, soundLabel, soundPopup,
                     volumeLabel, volumeSlider, volumeValueLabel,
                     pitchLabel, pitchSlider, pitchValueLabel,
                     glowLabel, glowCheckbox, glowHueSlider, glowHueLabel,
                     idleLabel, idlePopup, launchLabel, launchCheckbox] {
            content.addSubview(view)
        }

        // 分隔线 + 提示
        let hint = makeLabel("按键停止后，让出 Touch Bar 给系统")
        hint.frame = NSRect(x: 20, y: 30, width: 340, height: 20)
        hint.font = NSFont.systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor
        content.addSubview(hint)
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13)
        label.alignment = .right
        return label
    }

    private func positionLabel(_ label: NSTextField, above control: NSView) {
        label.frame = NSRect(x: 20, y: control.frame.midY - 8, width: 120, height: 17)
    }

    // MARK: - 操作

    @objc private func effectChanged() {
        let idx = effectPopup.indexOfSelectedItem
        guard let mode = EffectMode(rawValue: idx) else { return }
        settings.effectMode = mode
        // 发布通知，让应用实时应用该设置
        NotificationCenter.default.post(name: .barBarEffectChanged, object: mode)
    }

    @objc private func soundChanged() {
        let idx = soundPopup.indexOfSelectedItem
        guard let mode = SoundMode(rawValue: idx) else { return }
        settings.soundMode = mode
        NotificationCenter.default.post(name: .barBarSoundChanged, object: mode)
    }

    @objc private func volumeChanged() {
        let v = Float(volumeSlider.doubleValue)
        settings.soundVolume = v
        volumeValueLabel.stringValue = "\(Int(v * 100))%"
        NotificationCenter.default.post(name: .barBarVolumeChanged, object: v)
    }

    @objc private func pitchChanged() {
        let p = Float(pitchSlider.doubleValue)
        settings.soundPitch = p
        pitchValueLabel.stringValue = String(format: "%.1fx", p)
        NotificationCenter.default.post(name: .barBarPitchChanged, object: p)
    }

    @objc private func glowToggled() {
        let show = glowCheckbox.state == .on
        settings.showCenterGlow = show
        NotificationCenter.default.post(name: .barBarGlowToggleChanged, object: show)
    }

    @objc private func glowHueChanged() {
        let hue = Float(glowHueSlider.doubleValue)
        settings.glowHue = hue
        glowHueLabel.stringValue = "颜色"
        NotificationCenter.default.post(name: .barBarGlowHueChanged, object: hue)
    }

    @objc private func idleChanged() {
        let delays: [TimeInterval] = [1, 3, 5, 10, -1]  // -1 = 永不
        let idx = idlePopup.indexOfSelectedItem
        guard idx < delays.count else { return }
        settings.idleDismissDelay = delays[idx]
        NotificationCenter.default.post(name: .barBarIdleChanged, object: delays[idx])
    }

    @objc private func launchToggled() {
        let enabled = launchCheckbox.state == .on
        if applyLaunchAtLogin(enabled) {
            settings.launchAtLogin = enabled
        } else {
            // 注册失败——回滚复选框状态
            launchCheckbox.state = enabled ? .off : .on
        }
    }

    /// 若“登录时启动”状态设置成功则返回 true。
    /// macOS 13+ 使用 SMAppService；未签名的构建回退到用户的
    /// LaunchAgent（SMAppService 会拒绝未签名构建）。
    private func applyLaunchAtLogin(_ enabled: Bool) -> Bool {
        // 关闭时始终清理 LaunchAgent 回退；启用时若使用了它则保留。
        if enabled {
            if #available(macOS 13.0, *) {
                do {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                    // 通过现代 API 成功——无需 LaunchAgent。
                    return true
                } catch {
                    // 未签名 / 不在“应用程序”文件夹 → 使用 LaunchAgent 回退。
                    return installLaunchAgent()
                }
            } else {
                return installLaunchAgent()
            }
        } else {
            // 关闭：先尝试 SMAppService，再移除 LaunchAgent。
            if #available(macOS 13.0, *) {
                do {
                    if SMAppService.mainApp.status != .notRegistered {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    // 忽略——下面仍会清理 LaunchAgent
                }
            }
            removeLaunchAgent()
            return true
        }
    }

    // MARK: - LaunchAgent 回退（无需代码签名即可工作）

    private var launchAgentPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/LaunchAgents/com.raven.barbar.plist"
    }

    private func installLaunchAgent() -> Bool {
        guard let exe = Bundle.main.executablePath, !exe.isEmpty else { return false }

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.raven.barbar</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(exe)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
        </dict>
        </plist>
        """

        do {
            try plist.write(toFile: launchAgentPath, atomically: true, encoding: .utf8)
        } catch {
            NSLog("BarBar: failed to write LaunchAgent: \(error.localizedDescription)")
            return false
        }

        // 用 launchctl 加载（用户域，无需管理员权限）
        let uid = getuid()
        let ok = runProcess("/bin/launchctl", ["bootstrap", "gui/\(uid)", launchAgentPath])
        if !ok {
            // bootstrap 在已加载时可能失败——尝试 kickstart 以确保生效
            _ = runProcess("/bin/launchctl", ["kickstart", "gui/\(uid)/com.raven.barbar"])
        }
        return true
    }

    private func removeLaunchAgent() {
        let uid = getuid()
        _ = runProcess("/bin/launchctl", ["bootout", "gui/\(uid)/com.raven.barbar"])
        try? FileManager.default.removeItem(atPath: launchAgentPath)
    }

    private func runProcess(_ path: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func showLaunchAtLoginFailure() {
        let alert = NSAlert()
        alert.messageText = "无法设置开机自启"
        alert.informativeText = """
        BarBar 未能注册开机启动项，且回退方案也未生效。

        请确认：
        1. 已将 BarBar.app 拖入「应用程序」文件夹
        2. 或者尝试手动在 系统设置 → 通用 → 登录项 中添加

        此功能不影响其他功能。
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好的")
        alert.runModal()
    }

    func syncFromSettings() {
        effectPopup.selectItem(at: settings.effectMode.rawValue)
        soundPopup.selectItem(at: settings.soundMode.rawValue)
        volumeSlider.doubleValue = Double(settings.soundVolume)
        volumeValueLabel.stringValue = "\(Int(settings.soundVolume * 100))%"
        pitchSlider.doubleValue = Double(settings.soundPitch)
        pitchValueLabel.stringValue = String(format: "%.1fx", settings.soundPitch)
        glowCheckbox.state = settings.showCenterGlow ? .on : .off
        glowHueSlider.doubleValue = Double(settings.glowHue)
        launchCheckbox.state = settings.launchAtLogin ? .on : .off
    }
}

// MARK: - 通知名称

extension Notification.Name {
    static let barBarEffectChanged = Notification.Name("barBarEffectChanged")
    static let barBarSoundChanged = Notification.Name("barBarSoundChanged")
    static let barBarIdleChanged = Notification.Name("barBarIdleChanged")
    static let barBarVolumeChanged = Notification.Name("barBarVolumeChanged")
    static let barBarPitchChanged = Notification.Name("barBarPitchChanged")
    static let barBarGlowToggleChanged = Notification.Name("barBarGlowToggleChanged")
    static let barBarGlowHueChanged = Notification.Name("barBarGlowHueChanged")
}
