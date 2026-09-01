import Cocoa
import ApplicationServices
import ServiceManagement

/// 应用主代理。负责装配键盘监听、粒子系统、音频引擎和 Touch Bar 呈现。
class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - 组件
    private let particleSystem = ParticleSystem()
    private let audioEngine = AudioEngine()
    private let keyboardMonitor = KeyboardMonitor()
    private let settings = Settings.shared

    // MARK: - 界面
    private var statusItem: NSStatusItem?
    private var touchBarView: BarBarView?
    private var aboutController: AboutWindowController?
    private var preferencesController: PreferencesWindowController?
    private var toggleMenuItem: NSMenuItem?

    // MARK: - 触摸栏
    private var touchBar: NSTouchBar?
    private let touchBarItemIdentifier = NSTouchBarItem.Identifier("com.barbar.main")
    private let systemModalIdentifier = NSTouchBarItem.Identifier("com.barbar.systemmodal")

    // MARK: - 状态
    private var isMonitoring = false
    private var isPresented = false
    private var idleDismissTimer: Timer?
    private var accessibilityCheckTimer: Timer?

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 通过 `open` 启动的菜单栏应用（LSUIElement）不会被自动激活。
        // 系统模态 Touch Bar 只有在应用处于活跃状态时才会呈现，
        // 否则会被静默忽略，因此这里主动激活自身。
        activateApp()

        // 加载已保存的偏好设置
        particleSystem.mode = settings.effectMode
        audioEngine.mode = settings.soundMode
        audioEngine.masterVolume = settings.soundVolume
        audioEngine.pitchShift = settings.soundPitch

        // 监听设置窗口中的偏好变化
        observePreferenceChanges()

        // 应用已保存的“登录时启动”设置
        applySavedLaunchAtLogin()

        setupStatusBar()
        setupTouchBarHost()

        // 延迟尝试自动启动监听，给系统 TCC 权限检测留出时间。
        // 直接同步调用时，新安装（路径变化）后权限可能还没就绪，
        // 导致 AXIsProcessTrusted() 误判为未授权。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.startMonitoring()
        }

        // 监听辅助功能权限变化——用户在系统设置里授权后，
        // 自动启动监听，无需手动点击。
        observeAccessibilityPermissionChanges()
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboardMonitor.stop()
        audioEngine.stop()
        idleDismissTimer?.invalidate()
        accessibilityCheckTimer?.invalidate()
        if isPresented, let bar = touchBar {
            TouchBarHack.dismiss(bar)
        }
    }

    // MARK: - 状态栏

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            // 使用应用图标（AppIcon.icns）作为状态栏图标，并按菜单栏大小缩放。
            // 若不可用则回退到 🎵 emoji。
            if let icon = loadMenuBarIcon() {
                button.image = icon
                button.title = ""
            } else {
                button.title = "🎵"
            }
            button.toolTip = "BarBar — 点击切换开关"
        }

        let menu = NSMenu()
        menu.autoenablesItems = false

        // 标准应用菜单项
        let aboutItem = NSMenuItem(title: "关于 BarBar", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let prefsItem = NSMenuItem(title: "偏好设置…", action: #selector(showPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        let helpItem = NSMenuItem(title: "帮助", action: #selector(showHelp), keyEquivalent: "?")
        helpItem.target = self
        menu.addItem(helpItem)

        menu.addItem(NSMenuItem.separator())

        let toggleItem = NSMenuItem(title: isMonitoring ? "停止监听" : "启动监听",
                                    action: #selector(toggleMonitoring), keyEquivalent: "")
        toggleItem.target = self
        toggleMenuItem = toggleItem
        menu.addItem(toggleItem)
        menu.addItem(NSMenuItem.separator())

        // 扁平菜单（无子菜单）——LSUIElement 菜单栏应用中的 AppKit 子菜单
        // 存在一个 bug：首次悬停在子菜单项上会关闭整个菜单。
        // 因此我们使用禁用的“分区标题”项，后接各选项。
        let effectHeader = NSMenuItem(title: "视觉效果", action: nil, keyEquivalent: "")
        effectHeader.isEnabled = false
        menu.addItem(effectHeader)
        for mode in EffectMode.allCases {
            let item = NSMenuItem(title: mode.displayName, action: #selector(selectEffectMode(_:)), keyEquivalent: "")
            item.target = self
            item.tag = mode.rawValue
            item.state = (mode == settings.effectMode) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())
        let soundHeader = NSMenuItem(title: "音效", action: nil, keyEquivalent: "")
        soundHeader.isEnabled = false
        menu.addItem(soundHeader)
        for mode in SoundMode.allCases {
            let item = NSMenuItem(title: mode.displayName, action: #selector(selectSoundMode(_:)), keyEquivalent: "")
            item.target = self
            item.tag = mode.rawValue
            item.state = (mode == settings.soundMode) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    // MARK: - 标准菜单操作

    @objc private func showAbout() {
        if aboutController == nil {
            aboutController = AboutWindowController()
        }
        aboutController?.showWindow(nil)
        activateApp()
    }

    @objc private func showPreferences() {
        if preferencesController == nil {
            preferencesController = PreferencesWindowController()
        }
        preferencesController?.showWindow(nil)
        activateApp()
    }

    @objc private func showHelp() {
        let alert = NSAlert()
        alert.messageText = "BarBar 帮助"
        alert.informativeText = """
        BarBar 通过监听键盘输入，在 Touch Bar 上触发粒子动效和音效。

        • 视觉效果：9 种可切换的粒子/波纹/光束动效
        • 音效：7 种合成音色，随按键触发
        • 空闲让出：停止打字一段时间后自动让出 Touch Bar

        需要「辅助功能」权限才能监听全局键盘。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好的")
        alert.runModal()
    }

    // MARK: - 偏好变化处理

    private func observePreferenceChanges() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(effectPreferenceChanged(_:)),
                           name: .barBarEffectChanged, object: nil)
        center.addObserver(self, selector: #selector(soundPreferenceChanged(_:)),
                           name: .barBarSoundChanged, object: nil)
        center.addObserver(self, selector: #selector(idlePreferenceChanged(_:)),
                           name: .barBarIdleChanged, object: nil)
        center.addObserver(self, selector: #selector(volumePreferenceChanged(_:)),
                           name: .barBarVolumeChanged, object: nil)
        center.addObserver(self, selector: #selector(pitchPreferenceChanged(_:)),
                           name: .barBarPitchChanged, object: nil)
    }

    // MARK: - 辅助功能权限变化监听

    /// 监听系统辅助功能权限变化。当用户在系统设置中授权 BarBar 后，
    /// 系统会发出分布式通知，这里收到后自动启动监听。
    private func observeAccessibilityPermissionChanges() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(accessibilityPermissionDidChange),
            name: NSNotification.Name("com.apple.accessibility.api"),
            object: nil
        )
    }

    @objc private func accessibilityPermissionDidChange() {
        // 权限可能刚被授予——如果当前未在监听且权限已就绪，则自动启动。
        guard !isMonitoring else { return }
        if AXIsProcessTrusted() {
            accessibilityCheckTimer?.invalidate()
            accessibilityCheckTimer = nil
            beginMonitoring()
        }
    }

    @objc private func effectPreferenceChanged(_ note: Notification) {
        if let mode = note.object as? EffectMode {
            particleSystem.mode = mode
            updateMenuStates()
        }
    }

    @objc private func soundPreferenceChanged(_ note: Notification) {
        if let mode = note.object as? SoundMode {
            audioEngine.mode = mode
            updateMenuStates()
        }
    }

    @objc private func idlePreferenceChanged(_ note: Notification) {
        // 设置窗口已保存延时，这里只需重新调度。
        if isPresented {
            scheduleIdleDismiss()
        }
    }

    @objc private func volumePreferenceChanged(_ note: Notification) {
        if let volume = note.object as? Float {
            audioEngine.masterVolume = volume
        }
    }

    @objc private func pitchPreferenceChanged(_ note: Notification) {
        if let pitch = note.object as? Float {
            audioEngine.pitchShift = pitch
        }
    }

    // MARK: - 登录时启动

    /// 启动时重新应用已保存的“登录时启动”偏好。
    /// 仅在未注册时才注册。未签名的开发构建无法注册，
    /// 因此这里静默忽略失败。
    private func applySavedLaunchAtLogin() {
        guard settings.launchAtLogin else { return }

        if #available(macOS 13.0, *) {
            // 已注册？无需操作。
            if SMAppService.mainApp.status == .enabled { return }
            do {
                try SMAppService.mainApp.register()
            } catch {
                // 未签名的开发构建——忽略。签名并安装后即可生效。
            }
        }
        // macOS <13：SMAppService 不可用；未签名应用无法可靠处理，
        // 因此静默跳过。
    }

    // MARK: - 设置操作

    /// 加载应用图标（AppIcon.icns）并缩放到菜单栏大小。
    /// 若图标找不到或无法缩放则返回 nil。
    private func loadMenuBarIcon() -> NSImage? {
        // 在应用包资源中查找 AppIcon.icns
        guard let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
              let icon = NSImage(contentsOfFile: path) else {
            return nil
        }
        let menuBarSize = NSSize(width: 18, height: 18)
        let resized = icon.resized(to: menuBarSize)
        resized.isTemplate = false
        return resized
    }

    @objc private func toggleMonitoring() {
        if isMonitoring {
            stopMonitoring()
        } else {
            startMonitoring()
        }
        updateMonitoringMenuTitle()
    }

    /// 根据当前监听状态更新菜单按钮的标题
    private func updateMonitoringMenuTitle() {
        toggleMenuItem?.title = isMonitoring ? "停止监听" : "启动监听"
    }

    @objc private func selectEffectMode(_ sender: NSMenuItem) {
        guard let mode = EffectMode(rawValue: sender.tag) else { return }
        settings.effectMode = mode
        particleSystem.mode = mode
        updateMenuStates()
    }

    @objc private func selectSoundMode(_ sender: NSMenuItem) {
        guard let mode = SoundMode(rawValue: sender.tag) else { return }
        settings.soundMode = mode
        audioEngine.mode = mode
        updateMenuStates()
    }

    /// 刷新所有模式项上的勾选标记
    private func updateMenuStates() {
        guard let menu = statusItem?.menu else { return }

        for item in menu.items {
            if item.action == #selector(selectEffectMode(_:)) {
                item.state = (item.tag == settings.effectMode.rawValue) ? .on : .off
            } else if item.action == #selector(selectSoundMode(_:)) {
                item.state = (item.tag == settings.soundMode.rawValue) ? .on : .off
            }
        }
    }

    // MARK: - 监听

    /// 尝试启动监听。若辅助功能权限未授权，则触发系统原生授权弹窗，
    /// 并轮询等待授权——授权成功后自动开始监听。
    private func startMonitoring() {
        if AXIsProcessTrusted() {
            beginMonitoring()
        } else {
            requestAccessibilityPermission()
        }
    }

    /// 真正启动键盘监听。
    private func beginMonitoring() {
        let success = keyboardMonitor.start()
        isMonitoring = success
        if !success {
            updateMonitoringMenuTitle()
            return
        }
        keyboardMonitor.onKeyPress = { [weak self] keyCode, character in
            self?.handleKeyPress(keyCode: keyCode, character: character)
        }
        updateMonitoringMenuTitle()
    }

    private func stopMonitoring() {
        keyboardMonitor.stop()
        isMonitoring = false
        updateMonitoringMenuTitle()
    }

    // MARK: - 辅助功能授权

    /// 触发系统原生的辅助功能授权弹窗（自动打开系统设置），
    /// 同时启动轮询，授权成功后自动开始监听。
    private func requestAccessibilityPermission() {
        // 系统原生弹窗："BarBar" would like to control this computer using
        // accessibility features. 会自动打开系统设置辅助功能面板。
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        updateMonitoringMenuTitle()
        startAccessibilityPolling()
    }

    /// 轮询辅助功能权限，一旦授权即自动开始监听。
    private func startAccessibilityPolling() {
        accessibilityCheckTimer?.invalidate()
        accessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            if AXIsProcessTrusted() {
                timer.invalidate()
                self.accessibilityCheckTimer = nil
                self.beginMonitoring()
            }
        }
    }

    // MARK: - 按键处理

    private func handleKeyPress(keyCode: UInt16, character: String?) {
        // 将按键映射到键盘上的物理位置 → Touch Bar 的 x 坐标。
        // 修饰键（Shift/Ctrl/Option/Cmd/Caps/Fn）返回 nil——忽略它们。
        guard let normalizedX = KeyPosition.normalizedX(for: keyCode) else { return }

        // 缩放到 Touch Bar 宽度（2170 px / 2x Retina = 1085 pt）
        let barWidth: CGFloat = 1085
        // 加入微小抖动，避免重复按键堆积在同一位置
        let jitter = CGFloat.random(in: -0.008 ... 0.008)
        let spawnX = min(max(normalizedX + jitter, 0), 1) * barWidth

        // 生成粒子
        particleSystem.spawn(at: spawnX, barHeight: 30)

        // 播放音效（音量随连击数略微增大）
        let volume: Float = min(0.5, 0.2 + Float(particleSystem.combo) * 0.01)
        audioEngine.playNote(forKeyCode: keyCode, volume: volume)

        // 通知 Touch Bar 视图有按键活动
        touchBarView?.notifyActivity()

        // 若 Touch Bar 已被让出则重新接管，并重置空闲计时器
        if !isPresented {
            // 稍微延迟，给系统时间释放上一个模态栏——
            // 在让出后立即重新呈现，私有 API 可能会静默失败。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.presentTouchBar()
            }
        }
        scheduleIdleDismiss()
    }

    // MARK: - 触摸栏

    /// 使用私有的系统模态 API 呈现 Touch Bar，该 API 会接管
    /// 整个 Touch Bar（隐藏控制条、ESC 和其他应用的内容），
    /// 因此在其他应用中打字时也能显示动效。
    private func setupTouchBarHost() {
        // 稍作延迟，确保应用完成启动后再呈现
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            self.presentTouchBar()
            // 空闲后自动让出，就像在其他应用中打字那样
            self.scheduleIdleDismiss()
        }
    }

    /// 接管整个 Touch Bar。
    ///
    /// 注意：私有的系统模态 API 只允许同一个 NSTouchBar 实例呈现一次。
    /// 一旦让出后便无法再次呈现，因此每次都要重新创建栏（及其 item）。
    private func presentTouchBar() {
        guard !isPresented else { return }

        // 确保在呈现前我们是活跃应用——应用不活跃时
        // 系统模态 Touch Bar API 可能被忽略。
        activateApp()

        // 每次都重新创建栏和视图——已让出的实例无法再次呈现
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [touchBarItemIdentifier]
        self.touchBar = bar

        if TouchBarHack.isAvailable {
            TouchBarHack.present(bar, identifier: systemModalIdentifier.rawValue)
            isPresented = true
        } else {
            print("TouchBarHack unavailable — DFRFoundation not loaded")
        }
    }

    /// 将 Touch Bar 交还给系统（显示默认控制条）。
    private func dismissTouchBar() {
        guard isPresented, let bar = touchBar else { return }
        TouchBarHack.dismiss(bar)
        isPresented = false
    }

    /// 重置空闲计时器：在设定的空闲延时（来自设置）后
    /// 让出接管。负延时 = 永不让出。
    private func scheduleIdleDismiss() {
        idleDismissTimer?.invalidate()
        idleDismissTimer = nil

        let delay = settings.idleDismissDelay
        guard delay > 0 else { return }  // "永不"——保持 Touch Bar 接管状态

        idleDismissTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.dismissTouchBar()
            self?.idleDismissTimer = nil
        }
    }

    // MARK: - 辅助

    /// 激活应用，macOS 14+ 使用非废弃 API。
    private func activateApp() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - NSTouchBarDelegate

extension AppDelegate: NSTouchBarDelegate {
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == touchBarItemIdentifier else { return nil }

        let item = NSCustomTouchBarItem(identifier: identifier)
        let view = BarBarView(frame: NSRect(x: 0, y: 0, width: 1085, height: 30), particleSystem: particleSystem)
        // 点击 Touch Bar 时让出接管，恢复系统控制条
        view.onTouch = { [weak self] in
            self?.dismissTouchBar()
        }
        self.touchBarView = view
        item.view = view
        return item
    }
}

// MARK: - NSImage 缩放辅助

extension NSImage {
    /// 返回按给定像素大小缩放的新 NSImage。
    func resized(to newSize: NSSize) -> NSImage {
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(origin: .zero, size: newSize),
             from: NSRect(origin: .zero, size: size),
             operation: .sourceOver,
             fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
}
