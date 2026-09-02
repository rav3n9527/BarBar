import Cocoa
import ServiceManagement
import Darwin

/// 状态栏点击后弹出的完整设置面板。
/// 用 NSPopover 承载，集成了效果/音效/背景光效选择、音量/音调/颜色调节、
/// 空闲让出、开机启动、监听开关等全部功能。
/// 面板不随单项选择而关闭，可连续调整多个设置；点面板外部才收起。
class StatusPanelViewController: NSViewController {
    // MARK: - 回调（由 AppDelegate 注入）
    var onToggleMonitoring: (() -> Void)?
    var onOpenAbout: (() -> Void)?
    var onQuit: (() -> Void)?

    private let settings = Settings.shared

    // MARK: - 控件
    private let iconView = NSImageView()
    private let monitorButton = NSButton()
    private let effectPopup = NSPopUpButton()
    private let soundPopup = NSPopUpButton()
    private let backgroundPopup = NSPopUpButton()
    private let volumeSlider = NSSlider()
    private let volumeValueLabel = NSTextField(labelWithString: "70%")
    private let pitchSlider = NSSlider()
    private let pitchValueLabel = NSTextField(labelWithString: "1.0x")
    private let glowHueSlider = NSSlider()
    private let glowHueValueLabel = NSTextField(labelWithString: "—")
    private let idlePopup = NSPopUpButton()
    private let launchCheckbox = NSButton(checkboxWithTitle: "开机自动启动", target: nil, action: nil)
    private let aboutButton = NSButton(title: "关于", target: nil, action: nil)
    private let quitButton = NSButton(title: "退出", target: nil, action: nil)

    private var isMonitoring = false

    // MARK: - 生命周期

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        buildUI()
    }

    private func buildUI() {
        // 顶部：App logo + 标题
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let icon = NSImage(contentsOfFile: path) {
            iconView.image = icon.resized(to: NSSize(width: 20, height: 20))
        }
        iconView.frame = NSRect(x: 16, y: 368, width: 20, height: 20)
        view.addSubview(iconView)

        let titleLabel = NSTextField(labelWithString: "BarBar")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 15)
        titleLabel.frame = NSRect(x: 42, y: 367, width: 120, height: 22)
        view.addSubview(titleLabel)

        // 监听开关
        monitorButton.setButtonType(.momentaryPushIn)
        monitorButton.bezelStyle = .rounded
        monitorButton.frame = NSRect(x: 16, y: 328, width: 268, height: 30)
        monitorButton.target = self
        monitorButton.action = #selector(monitorClicked)
        view.addSubview(monitorButton)

        // 分隔线
        let sep1 = NSBox()
        sep1.boxType = .separator
        sep1.frame = NSRect(x: 16, y: 318, width: 268, height: 1)
        view.addSubview(sep1)

        // 视觉效果
        let effectLabel = makeRowLabel("视觉效果")
        effectPopup.frame = NSRect(x: 96, y: 288, width: 188, height: 26)
        for mode in EffectMode.allCases {
            effectPopup.addItem(withTitle: mode.displayName)
        }
        effectPopup.selectItem(at: Self.index(of: settings.effectMode, in: EffectMode.allCases))
        effectPopup.target = self
        effectPopup.action = #selector(effectChanged)
        placeLabel(effectLabel, atY: 288)
        view.addSubview(effectLabel)
        view.addSubview(effectPopup)

        // 音效
        let soundLabel = makeRowLabel("音效")
        soundPopup.frame = NSRect(x: 96, y: 258, width: 188, height: 26)
        for mode in SoundMode.allCases {
            soundPopup.addItem(withTitle: mode.displayName)
        }
        soundPopup.selectItem(at: Self.index(of: settings.soundMode, in: SoundMode.allCases))
        soundPopup.target = self
        soundPopup.action = #selector(soundChanged)
        placeLabel(soundLabel, atY: 258)
        view.addSubview(soundLabel)
        view.addSubview(soundPopup)

        // 背景光效
        let backgroundLabel = makeRowLabel("背景光效")
        backgroundPopup.frame = NSRect(x: 96, y: 228, width: 188, height: 26)
        for bg in BackgroundMode.allCases {
            backgroundPopup.addItem(withTitle: bg.displayName)
        }
        backgroundPopup.selectItem(at: Self.index(of: settings.backgroundMode, in: BackgroundMode.allCases))
        backgroundPopup.target = self
        backgroundPopup.action = #selector(backgroundChanged)
        placeLabel(backgroundLabel, atY: 228)
        view.addSubview(backgroundLabel)
        view.addSubview(backgroundPopup)

        // 音量
        let volumeLabel = makeRowLabel("音量")
        configureSlider(volumeSlider, y: 200, min: 0, max: 1, value: Double(settings.soundVolume))
        volumeSlider.action = #selector(volumeChanged)
        configureValueLabel(volumeValueLabel, y: 200, text: "\(Int(settings.soundVolume * 100))%")
        placeLabel(volumeLabel, atY: 200)
        view.addSubview(volumeLabel)
        view.addSubview(volumeSlider)
        view.addSubview(volumeValueLabel)

        // 音调
        let pitchLabel = makeRowLabel("音调")
        configureSlider(pitchSlider, y: 174, min: 0.5, max: 2.0, value: Double(settings.soundPitch))
        pitchSlider.action = #selector(pitchChanged)
        configureValueLabel(pitchValueLabel, y: 174, text: String(format: "%.1fx", settings.soundPitch))
        placeLabel(pitchLabel, atY: 174)
        view.addSubview(pitchLabel)
        view.addSubview(pitchSlider)
        view.addSubview(pitchValueLabel)

        // 背景光颜色（色相）
        let glowColorLabel = makeRowLabel("光颜色")
        configureSlider(glowHueSlider, y: 148, min: 0, max: 1, value: Double(settings.glowHue))
        glowHueSlider.action = #selector(glowHueChanged)
        configureValueLabel(glowHueValueLabel, y: 148, text: "蓝")
        placeLabel(glowColorLabel, atY: 148)
        view.addSubview(glowColorLabel)
        view.addSubview(glowHueSlider)
        view.addSubview(glowHueValueLabel)

        // 空闲让出延时
        let idleLabel = makeRowLabel("空闲让出")
        idlePopup.frame = NSRect(x: 96, y: 118, width: 188, height: 26)
        idlePopup.addItems(withTitles: ["1 秒", "3 秒", "5 秒", "10 秒", "永不"])
        switch settings.idleDismissDelay {
        case 1.0: idlePopup.selectItem(at: 0)
        case 3.0: idlePopup.selectItem(at: 1)
        case 5.0: idlePopup.selectItem(at: 2)
        case 10.0: idlePopup.selectItem(at: 3)
        default: idlePopup.selectItem(at: 4)
        }
        idlePopup.target = self
        idlePopup.action = #selector(idleChanged)
        placeLabel(idleLabel, atY: 118)
        view.addSubview(idleLabel)
        view.addSubview(idlePopup)

        // 开机自动启动
        launchCheckbox.frame = NSRect(x: 96, y: 92, width: 190, height: 20)
        launchCheckbox.state = settings.launchAtLogin ? .on : .off
        launchCheckbox.target = self
        launchCheckbox.action = #selector(launchToggled)
        view.addSubview(launchCheckbox)

        // 分隔线
        let sep2 = NSBox()
        sep2.boxType = .separator
        sep2.frame = NSRect(x: 16, y: 74, width: 268, height: 1)
        view.addSubview(sep2)

        // 底部按钮行
        aboutButton.setButtonType(.momentaryPushIn)
        aboutButton.bezelStyle = .rounded
        aboutButton.frame = NSRect(x: 16, y: 36, width: 128, height: 28)
        aboutButton.target = self
        aboutButton.action = #selector(aboutClicked)
        view.addSubview(aboutButton)

        quitButton.setButtonType(.momentaryPushIn)
        quitButton.bezelStyle = .rounded
        quitButton.frame = NSRect(x: 156, y: 36, width: 128, height: 28)
        quitButton.target = self
        quitButton.action = #selector(quitClicked)
        view.addSubview(quitButton)

        updateMonitoringButton()
    }

    // MARK: - UI 辅助

    private func makeRowLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13)
        label.alignment = .right
        label.frame = NSRect(x: 16, y: 0, width: 70, height: 20)
        return label
    }

    private func placeLabel(_ label: NSTextField, atY y: CGFloat) {
        label.frame = NSRect(x: 16, y: y + 2, width: 70, height: 20)
    }

    private func configureSlider(_ slider: NSSlider, y: CGFloat, min: Double, max: Double, value: Double) {
        slider.frame = NSRect(x: 96, y: y, width: 160, height: 20)
        slider.minValue = min
        slider.maxValue = max
        slider.isContinuous = true
        slider.doubleValue = value
        slider.target = self
    }

    private func configureValueLabel(_ label: NSTextField, y: CGFloat, text: String) {
        label.stringValue = text
        label.frame = NSRect(x: 260, y: y, width: 30, height: 20)
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.alignment = .left
    }

    // MARK: - 对外同步

    func setMonitoring(_ monitoring: Bool) {
        isMonitoring = monitoring
        updateMonitoringButton()
    }

    func syncFromSettings() {
        effectPopup.selectItem(at: Self.index(of: settings.effectMode, in: EffectMode.allCases))
        soundPopup.selectItem(at: Self.index(of: settings.soundMode, in: SoundMode.allCases))
        backgroundPopup.selectItem(at: Self.index(of: settings.backgroundMode, in: BackgroundMode.allCases))
        volumeSlider.doubleValue = Double(settings.soundVolume)
        volumeValueLabel.stringValue = "\(Int(settings.soundVolume * 100))%"
        pitchSlider.doubleValue = Double(settings.soundPitch)
        pitchValueLabel.stringValue = String(format: "%.1fx", settings.soundPitch)
        glowHueSlider.doubleValue = Double(settings.glowHue)
        glowHueValueLabel.stringValue = hueName(settings.glowHue)
        idlePopup.selectItem(at: idleIndex(for: settings.idleDismissDelay))
        launchCheckbox.state = settings.launchAtLogin ? .on : .off
    }

    private func idleIndex(for delay: TimeInterval) -> Int {
        switch delay {
        case 1.0: return 0
        case 3.0: return 1
        case 5.0: return 2
        case 10.0: return 3
        default: return 4
        }
    }

    private func hueName(_ hue: Float) -> String {
        switch hue {
        case ..<0.1: return "红"
        case ..<0.2: return "橙"
        case ..<0.35: return "黄"
        case ..<0.5: return "绿"
        case ..<0.65: return "青"
        case ..<0.8: return "蓝"
        default: return "紫"
        }
    }

    private func updateMonitoringButton() {
        monitorButton.title = isMonitoring ? "■ 停止监听" : "▶ 启动监听"
    }

    /// 返回枚举值在 allCases 中的下标；找不到返回 0（安全兜底）。
    private static func index<T: Equatable>(of value: T, in cases: [T]) -> Int {
        cases.firstIndex(of: value) ?? 0
    }

    // MARK: - 操作

    @objc private func monitorClicked() {
        onToggleMonitoring?()
    }

    @objc private func effectChanged() {
        let idx = effectPopup.indexOfSelectedItem
        guard EffectMode.allCases.indices.contains(idx) else { return }
        let mode = EffectMode.allCases[idx]
        settings.effectMode = mode
        NotificationCenter.default.post(name: .barBarEffectChanged, object: mode)
    }

    @objc private func soundChanged() {
        let idx = soundPopup.indexOfSelectedItem
        guard SoundMode.allCases.indices.contains(idx) else { return }
        let mode = SoundMode.allCases[idx]
        settings.soundMode = mode
        NotificationCenter.default.post(name: .barBarSoundChanged, object: mode)
    }

    @objc private func backgroundChanged() {
        let idx = backgroundPopup.indexOfSelectedItem
        guard BackgroundMode.allCases.indices.contains(idx) else { return }
        let mode = BackgroundMode.allCases[idx]
        settings.backgroundMode = mode
        NotificationCenter.default.post(name: .barBarGlowModeChanged, object: mode)
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

    @objc private func glowHueChanged() {
        let hue = Float(glowHueSlider.doubleValue)
        settings.glowHue = hue
        glowHueValueLabel.stringValue = hueName(hue)
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
            showLaunchAtLoginFailure()
        }
    }

    // MARK: - 开机自启（SMAppService + LaunchAgent 回退）

    /// 若“登录时启动”状态设置成功则返回 true。
    private func applyLaunchAtLogin(_ enabled: Bool) -> Bool {
        if enabled {
            if #available(macOS 13.0, *) {
                do {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                    return true
                } catch {
                    return installLaunchAgent()
                }
            } else {
                return installLaunchAgent()
            }
        } else {
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

        let uid = getuid()
        let ok = runProcess("/bin/launchctl", ["bootstrap", "gui/\(uid)", launchAgentPath])
        if !ok {
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

    @objc private func aboutClicked() {
        onOpenAbout?()
    }

    @objc private func quitClicked() {
        onQuit?()
    }
}

// MARK: - 通知名称

extension Notification.Name {
    static let barBarEffectChanged = Notification.Name("barBarEffectChanged")
    static let barBarSoundChanged = Notification.Name("barBarSoundChanged")
    static let barBarIdleChanged = Notification.Name("barBarIdleChanged")
    static let barBarVolumeChanged = Notification.Name("barBarVolumeChanged")
    static let barBarPitchChanged = Notification.Name("barBarPitchChanged")
    static let barBarGlowModeChanged = Notification.Name("barBarGlowModeChanged")
    static let barBarGlowHueChanged = Notification.Name("barBarGlowHueChanged")
}
