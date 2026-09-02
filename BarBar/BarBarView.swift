import Cocoa
import QuartzCore

/// 自定义 NSView，在 Touch Bar 上渲染粒子/涟漪效果。
/// 使用 Timer 驱动的渲染循环，以 60fps 运行以保持动画流畅。
class BarBarView: NSView {
    // MARK: - 依赖
    let particleSystem: ParticleSystem

    /// 点击 Touch Bar 时回调（用于让出接管）
    var onTouch: (() -> Void)?

    // MARK: - 渲染循环
    private var renderTimer: Timer?
    private var lastTimestamp: TimeInterval = 0

    // MARK: - 空闲检测
    private let idleTimeout: TimeInterval = 5.0

    // MARK: - 背景渐变
    private var bgHue: CGFloat = 0.58 // 初始偏蓝
    private let settings = Settings.shared

    init(frame frameRect: NSRect, particleSystem: ParticleSystem) {
        self.particleSystem = particleSystem
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        startRenderLoop()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    deinit {
        stopRenderLoop()
    }

    // MARK: - 活动

    /// 每次按键时调用（保留接口；空闲判断已由粒子系统共享时间戳驱动）
    func notifyActivity() {
        // 空闲清理由 particleSystem.lastSpawnTime 统一判断
    }

    // MARK: - 触摸事件

    /// 用户点击/触摸 Touch Bar 时触发 onTouch 回调，
    /// 由 AppDelegate 负责让出 Touch Bar 接管。
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        onTouch?()
    }

    // MARK: - 渲染循环

    private func startRenderLoop() {
        guard renderTimer == nil else { return }
        // 60fps 全速渲染。性能安全靠「视图生命周期管理」保障——
        // 任意时刻只有一个活动渲染循环（旧视图会被 deactivate 停掉），
        // 不会累积多个计时器压垮主线程。
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.renderFrame()
        }
        RunLoop.main.add(timer, forMode: .common)
        renderTimer = timer
    }

    private func stopRenderLoop() {
        renderTimer?.invalidate()
        renderTimer = nil
    }

    /// 手动停用该视图：停止渲染循环。
    /// 在视图被替换或 Touch Bar 让出时调用，防止残留的渲染计时器
    /// 继续占用主线程并重复驱动共享的粒子系统（导致性能累积性卡死）。
    func deactivate() {
        stopRenderLoop()
    }

    // MARK: - 渲染

    private func renderFrame() {
        let now = CFAbsoluteTimeGetCurrent()
        let dt: Float = lastTimestamp == 0 ? 1.0 / 60.0 : Float(now - lastTimestamp)
        lastTimestamp = now

        // 更新粒子物理（限制 dt 以避免“死亡螺旋”）
        particleSystem.update(dt: min(dt, 0.05))

        // 空闲淡出——长时间无操作后清除粒子。
        // 用粒子系统共享的 lastSpawnTime 判断，而不是本视图自己的
        // 时间戳：让出/重新接管时新视图刚创建（时间戳为 0），
        // 若按自身时间戳判断会立刻清空所有粒子。
        if now - particleSystem.lastSpawnTime > idleTimeout {
            particleSystem.clear()
        }

        // 缓慢改变背景色相
        bgHue += CGFloat(dt * 0.01)
        if bgHue > 1.0 { bgHue -= 1.0 }

        setNeedsDisplay(bounds)
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let w = bounds.width
        let h = bounds.height

        // 用深色渐变背景清屏
        ctx.setFillColor(NSColor(calibratedHue: bgHue, saturation: 0.3, brightness: 0.08, alpha: 1).cgColor)
        ctx.fill(bounds)

        // 背景光效（粒子下方）——bounce 模式跳过（该模式有自己的球）
        if particleSystem.mode != .bounce {
            switch settings.backgroundMode {
            case .none:
                break
            case .centerGlow:
                drawCenterGlow(ctx: ctx, w: w, h: h)
            case .breathingBorder:
                drawBreathingBorder(ctx: ctx, w: w, h: h)
            }
        }

        // 绘制涟漪（位于粒子后方）
        for ripple in particleSystem.ripples {
            drawRipple(ctx: ctx, ripple: ripple)
        }

        // 绘制粒子——样式取决于特效模式
        for particle in particleSystem.particles {
            switch particleSystem.mode {
            case .rain:
                drawRainParticle(ctx: ctx, particle: particle)
            case .bounce:
                drawBounceBall(ctx: ctx, particle: particle)
            case .shockwave:
                drawStreakParticle(ctx: ctx, particle: particle)
            case .laser:
                drawBeamParticle(ctx: ctx, particle: particle)
            case .meteor:
                drawStreakParticle(ctx: ctx, particle: particle)
            case .spectrum:
                drawBeamParticle(ctx: ctx, particle: particle)
            case .fire:
                drawParticle(ctx: ctx, particle: particle)
            case .laserReflect:
                drawLaserBeam(ctx: ctx, particle: particle)
            case .burst, .ripple:
                drawParticle(ctx: ctx, particle: particle)
            case .ecg:
                break   // ECG 模式没有粒子，由 drawECG 绘制滚动线
            case .shooter:
                break   // 空战模式没有粒子，由 drawShooterScene 绘制
            }
        }

        // 心电图模式：绘制绿色滚动监护线
        if particleSystem.mode == .ecg {
            drawECG(ctx: ctx, w: w, h: h)
        }

        // CRT 空战模式：绘制游戏场景（覆盖粒子之上，自带 CRT 背景）
        if particleSystem.mode == .shooter {
            drawShooterScene(ctx: ctx, w: w, h: h)
        }

        // 如果连击数有效则绘制连击计数
        let combo = particleSystem.combo
        if combo > 1 {
            drawCombo(ctx: ctx, combo: combo, w: w, h: h)
        }
    }

    private func drawCenterGlow(ctx: CGContext, w: CGFloat, h: CGFloat) {
        let centerY = h * 0.5
        let intensity = min(1.0, CGFloat(particleSystem.combo) / 20.0)
        let glowRadius: CGFloat = 4 + intensity * 12

        // 使用用户设置的彩条颜色（色相），默认偏蓝
        let hue = CGFloat(settings.glowHue)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let locations: [CGFloat] = [0, 1]
        let colors = [
            NSColor(calibratedHue: hue, saturation: 0.8, brightness: 0.3 + intensity * 0.4, alpha: 0.6 + intensity * 0.3).cgColor,
            NSColor(calibratedHue: hue, saturation: 0.5, brightness: 0.1, alpha: 0).cgColor,
        ] as CFArray

        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) else { return }

        // 水平光晕线
        ctx.saveGState()
        ctx.addRect(CGRect(x: 0, y: centerY - glowRadius, width: w, height: glowRadius * 2))
        ctx.clip()
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: centerY - glowRadius),
                               end: CGPoint(x: 0, y: centerY + glowRadius),
                               options: [])
        ctx.restoreGState()
    }

    // MARK: - 边框呼吸灯
    /// 霓虹灯管沿 Touch Bar 边框呼吸闪烁。打字越快，颜色越深、
    /// 光晕越浓，仿佛霓虹灯管悬浮在雾气中。
    /// 光晕只朝屏幕外侧扩散（内部被裁掉），不会显得屏幕变小；
    /// 边框为直角矩形。
    private func drawBreathingBorder(ctx: CGContext, w: CGFloat, h: CGFloat) {
        let t = CACurrentMediaTime()
        let intensity = min(1.0, CGFloat(particleSystem.combo) / 12.0)

        // 呼吸节律：速度随连击加快
        let breatheHz = 0.8 + intensity * 1.6
        let breathe = 0.5 + 0.5 * sin(t * breatheHz * 2.0 * .pi)

        // 连击越多颜色越深（色相向蓝紫深端略微偏移并提饱和）
        let hue = CGFloat(settings.glowHue) - intensity * 0.08
        let baseBright = 0.35 + breathe * 0.3 + intensity * 0.2

        // 内边距（越小灯管越贴边）
        let inset: CGFloat = 1.0
        let borderRect = bounds.insetBy(dx: inset, dy: inset)

        ctx.saveGState()

        // 关键：只保留 borderRect 外侧区域（even-odd 挖空内部）。
        // 这样光晕无论多宽都只朝外扩散，完全不影响屏幕内容。
        ctx.addPath(CGPath(rect: bounds, transform: nil))
        ctx.addPath(CGPath(rect: borderRect, transform: nil))
        ctx.clip(using: .evenOdd)

        // 直角边框路径（无圆角）
        let path = CGPath(rect: borderRect, transform: nil)

        // 雾中弥散光晕：逐层加宽、降低不透明度；描边居中于路径，
        // 但因内部被裁掉，实际只显示朝外的一半宽度。
        let fogLayers: [(width: CGFloat, alphaMul: CGFloat)] = [
            (12, 0.07),   // 最外层雾气
            (7, 0.12),
            (3.6, 0.20),  // 中层光晕
            (1.8, 0.38),  // 内层亮晕
        ]
        for layer in fogLayers {
            let glowA = layer.alphaMul * (0.5 + intensity * 0.7) * (0.6 + breathe * 0.8)
            let glowColor = NSColor(calibratedHue: hue,
                                    saturation: 0.95,
                                    brightness: baseBright,
                                    alpha: min(1, glowA)).cgColor
            ctx.setStrokeColor(glowColor)
            ctx.setLineWidth(layer.width)
            ctx.addPath(path)
            ctx.strokePath()
        }

        // 灯管主体：高饱和、较亮
        let tubeA = 0.75 + intensity * 0.25
        let tubeColor = NSColor(calibratedHue: hue,
                                saturation: 1.0,
                                brightness: min(1, baseBright + 0.35),
                                alpha: tubeA).cgColor
        ctx.setStrokeColor(tubeColor)
        ctx.setLineWidth(1.4)
        ctx.addPath(path)
        ctx.strokePath()

        // 灯管芯：最亮的一条白线，模拟霓虹管内部的高亮
        let coreA = (0.4 + breathe * 0.5) * (0.6 + intensity * 0.4)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(min(1, coreA)).cgColor)
        ctx.setLineWidth(0.7)
        ctx.addPath(path)
        ctx.strokePath()

        ctx.restoreGState()
    }

    // MARK: - 标准粒子（burst / ripple 模式）

    private func drawParticle(ctx: CGContext, particle: Particle) {
        let pos = particle.position
        let r = particle.radius
        let alpha = particle.alpha

        guard alpha > 0.01 else { return }

        ctx.saveGState()

        // 光晕效果：在后方绘制一个更大、更柔和的圆
        if let glowColor = particle.color.copy(alpha: alpha * 0.3) {
            ctx.setFillColor(glowColor)
            ctx.fillEllipse(in: CGRect(x: pos.x - r * 2.5, y: pos.y - r * 2.5, width: r * 5, height: r * 5))
        }

        // 粒子主体
        if let coreColor = particle.color.copy(alpha: alpha) {
            ctx.setFillColor(coreColor)
            ctx.fillEllipse(in: CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2))
        }

        // 高亮中心
        ctx.setFillColor(NSColor.white.withAlphaComponent(alpha * 0.6).cgColor)
        let coreR = r * 0.4
        ctx.fillEllipse(in: CGRect(x: pos.x - coreR, y: pos.y - coreR, width: coreR * 2, height: coreR * 2))

        ctx.restoreGState()
    }

    // MARK: - 雨滴粒子（带垂直拖尾）

    private func drawRainParticle(ctx: CGContext, particle: Particle) {
        let pos = particle.position
        let alpha = particle.alpha
        guard alpha > 0.01 else { return }

        ctx.saveGState()

        // 拖尾：雨滴后方一条垂直的线，向上渐隐
        let streakLen: CGFloat = 14
        let tailColor = particle.color.copy(alpha: alpha * 0.35) ?? particle.color
        ctx.setStrokeColor(tailColor)
        ctx.setLineWidth(particle.radius * 0.8)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: pos.x, y: pos.y))
        ctx.addLine(to: CGPoint(x: pos.x, y: pos.y + streakLen))
        ctx.strokePath()

        // 高亮雨滴头部
        ctx.setFillColor(particle.color.copy(alpha: alpha) ?? particle.color)
        ctx.fillEllipse(in: CGRect(x: pos.x - particle.radius,
                                   y: pos.y - particle.radius,
                                   width: particle.radius * 2,
                                   height: particle.radius * 2))

        // 白色闪光
        ctx.setFillColor(NSColor.white.withAlphaComponent(alpha * 0.7).cgColor)
        let coreR = particle.radius * 0.4
        ctx.fillEllipse(in: CGRect(x: pos.x - coreR, y: pos.y - coreR, width: coreR * 2, height: coreR * 2))

        ctx.restoreGState()
    }

    // MARK: - 弹跳球（更大、更强的光晕，轻微压扁效果）

    private func drawBounceBall(ctx: CGContext, particle: Particle) {
        let pos = particle.position
        let r = particle.radius
        let alpha = particle.alpha
        guard alpha > 0.01 else { return }

        ctx.saveGState()

        // 大而柔和的光环
        if let halo = particle.color.copy(alpha: alpha * 0.25) {
            ctx.setFillColor(halo)
            ctx.fillEllipse(in: CGRect(x: pos.x - r * 3, y: pos.y - r * 3, width: r * 6, height: r * 6))
        }

        // 球体
        ctx.setFillColor(particle.color.copy(alpha: alpha) ?? particle.color)
        ctx.fillEllipse(in: CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2))

        // 高亮中心
        ctx.setFillColor(NSColor.white.withAlphaComponent(alpha * 0.8).cgColor)
        let coreR = r * 0.5
        ctx.fillEllipse(in: CGRect(x: pos.x - coreR, y: pos.y - coreR, width: coreR * 2, height: coreR * 2))

        ctx.restoreGState()
    }

    // MARK: - 拖尾粒子（shockwave / meteor）
    /// 从粒子后方延伸出的水平发光拖尾，类似
    /// 彗尾或能量波前。
    private func drawStreakParticle(ctx: CGContext, particle: Particle) {
        let pos = particle.position
        let alpha = particle.alpha
        let tail = particle.tailLength
        guard alpha > 0.01, tail > 1 else {
            drawParticle(ctx: ctx, particle: particle)
            return
        }

        ctx.saveGState()

        // 拖尾方向：与速度方向相反，默认朝左
        let vx = particle.velocity.x
        let tailDir: CGFloat = vx >= 0 ? -1 : 1

        // 后方宽而柔和的光晕
        ctx.setLineCap(.round)
        if let glowColor = particle.color.copy(alpha: alpha * 0.25) {
            ctx.setStrokeColor(glowColor)
            ctx.setLineWidth(particle.radius * 2.2)
            ctx.move(to: CGPoint(x: pos.x, y: pos.y))
            ctx.addLine(to: CGPoint(x: pos.x + tailDir * tail, y: pos.y))
            ctx.strokePath()
        }

        // 高亮核心拖尾
        if let tailColor = particle.color.copy(alpha: alpha) {
            ctx.setStrokeColor(tailColor)
            ctx.setLineWidth(particle.radius)
            ctx.move(to: CGPoint(x: pos.x, y: pos.y))
            ctx.addLine(to: CGPoint(x: pos.x + tailDir * tail * 0.7, y: pos.y))
            ctx.strokePath()
        }

        // 高亮头部
        ctx.setFillColor(NSColor.white.withAlphaComponent(alpha * 0.9).cgColor)
        ctx.fillEllipse(in: CGRect(x: pos.x - particle.radius,
                                   y: pos.y - particle.radius,
                                   width: particle.radius * 2,
                                   height: particle.radius * 2))

        ctx.restoreGState()
    }

    // MARK: - 光束粒子（laser / spectrum）
    /// 从 Touch Bar 底部升起的垂直光束。
    private func drawBeamParticle(ctx: CGContext, particle: Particle) {
        let pos = particle.position
        let alpha = particle.alpha
        let beamLen = particle.tailLength
        guard alpha > 0.01 else { return }

        ctx.saveGState()
        ctx.setLineCap(.round)

        // 柔和的外层光晕
        if let glowColor = particle.color.copy(alpha: alpha * 0.2) {
            ctx.setStrokeColor(glowColor)
            ctx.setLineWidth(particle.radius * 3.5)
            ctx.move(to: CGPoint(x: pos.x, y: 0))
            ctx.addLine(to: CGPoint(x: pos.x, y: pos.y + beamLen * 0.8))
            ctx.strokePath()
        }

        // 主光束
        if let beamColor = particle.color.copy(alpha: alpha) {
            ctx.setStrokeColor(beamColor)
            ctx.setLineWidth(particle.radius)
            ctx.move(to: CGPoint(x: pos.x, y: 0))
            ctx.addLine(to: CGPoint(x: pos.x, y: pos.y + beamLen))
            ctx.strokePath()
        }

        // 高亮顶端
        ctx.setFillColor(NSColor.white.withAlphaComponent(alpha * 0.9).cgColor)
        ctx.fillEllipse(in: CGRect(x: pos.x - particle.radius,
                                   y: pos.y - particle.radius,
                                   width: particle.radius * 2,
                                   height: particle.radius * 2))

        ctx.restoreGState()
    }

    // MARK: - 折射激光渲染
    /// 星球大战风格的激光束：沿着速度方向画一条粗亮的射线，
    /// 前后端有辉光，营造光束在 Touch Bar 内折射穿梭的动感。
    private func drawLaserBeam(ctx: CGContext, particle: Particle) {
        let pos = particle.position
        let alpha = particle.alpha
        guard alpha > 0.01 else { return }

        // 光束方向 = 速度方向，拖尾沿反方向延伸
        let vx = particle.velocity.x
        let vy = particle.velocity.y
        let speed = max(1, sqrt(vx * vx + vy * vy))
        let tail = particle.tailLength

        // 拖尾起点（粒子后方）
        let tx = pos.x - (vx / speed) * tail
        let ty = pos.y - (vy / speed) * tail

        ctx.saveGState()
        ctx.setLineCap(.round)

        // 宽大的外层光晕
        if let glowColor = particle.color.copy(alpha: alpha * 0.3) {
            ctx.setStrokeColor(glowColor)
            ctx.setLineWidth(particle.radius * 5)
            ctx.move(to: CGPoint(x: tx, y: ty))
            ctx.addLine(to: CGPoint(x: pos.x, y: pos.y))
            ctx.strokePath()
        }

        // 主光束
        if let beamColor = particle.color.copy(alpha: alpha) {
            ctx.setStrokeColor(beamColor)
            ctx.setLineWidth(particle.radius * 2)
            ctx.move(to: CGPoint(x: tx, y: ty))
            ctx.addLine(to: CGPoint(x: pos.x, y: pos.y))
            ctx.strokePath()
        }

        // 高亮核心
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(alpha * 0.9).cgColor)
        ctx.setLineWidth(particle.radius)
        ctx.move(to: CGPoint(x: tx, y: ty))
        ctx.addLine(to: CGPoint(x: pos.x, y: pos.y))
        ctx.strokePath()

        // 前端亮点
        ctx.setFillColor(NSColor.white.withAlphaComponent(alpha).cgColor)
        let headR = particle.radius * 1.6
        ctx.fillEllipse(in: CGRect(x: pos.x - headR, y: pos.y - headR,
                                   width: headR * 2, height: headR * 2))

        ctx.restoreGState()
    }

    private func drawRipple(ctx: CGContext, ripple: Ripple) {
        guard ripple.alpha > 0.01, ripple.radius > 1 else { return }

        ctx.saveGState()
        if let strokeColor = ripple.color.copy(alpha: ripple.alpha) {
            ctx.setStrokeColor(strokeColor)
        }
        ctx.setLineWidth(ripple.lineWidth)
        ctx.addEllipse(in: CGRect(
            x: ripple.center.x - ripple.radius,
            y: ripple.center.y - ripple.radius,
            width: ripple.radius * 2,
            height: ripple.radius * 2
        ))
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - 心电图（ECG）渲染
    /// 绿色监护仪风格：把采样数组画成一条辉光滚动线，
    /// 心搏时出现 P-QRS-T 波形。
    private func drawECG(ctx: CGContext, w: CGFloat, h: CGFloat) {
        let samples = particleSystem.ecgSamples
        guard samples.count > 2 else { return }

        let midY = h * 0.5
        let ampScale: CGFloat = h * 0.34   // 波形纵向幅度（已加大）

        ctx.saveGState()
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)

        // 外层柔和辉光
        ctx.setStrokeColor(NSColor(calibratedRed: 0.2, green: 1.0, blue: 0.4, alpha: 0.25).cgColor)
        ctx.setLineWidth(4.0)
        drawECGPath(ctx: ctx, w: w, h: h, midY: midY, amp: ampScale, samples: samples)
        ctx.strokePath()

        // 主体亮线
        ctx.setStrokeColor(NSColor(calibratedRed: 0.3, green: 1.0, blue: 0.5, alpha: 0.95).cgColor)
        ctx.setLineWidth(1.5)
        drawECGPath(ctx: ctx, w: w, h: h, midY: midY, amp: ampScale, samples: samples)
        ctx.strokePath()

        ctx.restoreGState()
    }

    private func drawECGPath(ctx: CGContext, w: CGFloat, h: CGFloat, midY: CGFloat, amp: CGFloat, samples: [CGFloat]) {
        let n = samples.count
        let stepX = w / CGFloat(n - 1)
        ctx.beginPath()
        for i in 0 ..< n {
            let x = CGFloat(i) * stepX
            // 采样值映射到屏幕（正值向上），并钳制在可视范围内
            let y = max(1.5, min(h - 1.5, midY - samples[i] * amp))
            if i == 0 {
                ctx.move(to: CGPoint(x: x, y: y))
            } else {
                ctx.addLine(to: CGPoint(x: x, y: y))
            }
        }
    }

    // MARK: - CRT 空战场景渲染
    /// 绘制复古 CRT 风格的游戏画面：深色荧光屏底色 + 扫描线 +
    /// 玩家飞机 / 敌机 / 子弹 / 爆炸，全部用荧光绿像素块。
    private func drawShooterScene(ctx: CGContext, w: CGFloat, h: CGFloat) {
        let scene = particleSystem.shooterScene

        // 荧光屏底色（深绿黑）
        ctx.setFillColor(NSColor(calibratedRed: 0.02, green: 0.07, blue: 0.03, alpha: 1).cgColor)
        ctx.fill(bounds)

        // 像素化坐标比例：场景逻辑宽 1085 → 实际宽度 w
        let sx = w / 1085.0

        // 扫描线：每 3pt 一条暗线
        ctx.setStrokeColor(NSColor(calibratedRed: 0, green: 0.25, blue: 0.1, alpha: 0.35).cgColor)
        ctx.setLineWidth(1)
        var scanY: CGFloat = 1
        while scanY < h {
            ctx.beginPath()
            ctx.move(to: CGPoint(x: 0, y: scanY))
            ctx.addLine(to: CGPoint(x: w, y: scanY))
            ctx.strokePath()
            scanY += 3
        }

        // 辉光色函数
        func glow(_ alpha: CGFloat) -> CGColor {
            NSColor(calibratedRed: 0.3, green: 1.0, blue: 0.5, alpha: alpha).cgColor
        }
        func core(_ alpha: CGFloat) -> CGColor {
            NSColor(calibratedRed: 0.75, green: 1.0, blue: 0.85, alpha: alpha).cgColor
        }

        // 敌机：三种像素造型，按 kind 切换
        let enemySprites: [[String]] = [
            // 0: UFO / 圆碟
            [".XX.",
             "XXXX",
             "XXXX",
             ".XX."],
            // 1: 俯冲式战斗机
            [".X.",
             "XXX",
             "XXX",
             "X.X"],
            // 2: 炮台式轰炸机
            ["XXXX",
             "X..X",
             "XXXX",
             ".XX."],
        ]
        for enemy in scene.enemies {
            let ex = enemy.x * sx
            let ey = h - enemy.y  // 逻辑 y 向上，绘图 y 向下
            let kind = min(max(enemy.kind, 0), enemySprites.count - 1)
            drawSprite(enemySprites[kind],
                       centerX: ex, bottomY: ey, cell: 2.0,
                       body: core(0.95), glow: glow(0.5))
        }

        // 子弹
        for bullet in scene.bullets {
            let bx = bullet.x * sx
            let by = h - bullet.y
            // 玩家子弹短粗亮，敌弹细长暗
            if bullet.vy > 0 {
                ctx.setFillColor(NSColor(calibratedRed: 0.9, green: 1.0, blue: 0.85, alpha: 1).cgColor)
                ctx.fill(CGRect(x: bx - 2, y: by - 2, width: 4, height: 6))
            } else {
                ctx.setFillColor(NSColor(calibratedRed: 1.0, green: 0.5, blue: 0.4, alpha: 0.95).cgColor)
                ctx.fill(CGRect(x: bx - 1, y: by - 1, width: 2, height: 5))
            }
        }

        // 爆炸：向外扩散的十字 + 粒子光点
        for boom in scene.explosions {
            let bx = boom.x * sx
            let by = h - boom.y
            let progress = 1.0 - CGFloat(boom.timer / boom.maxTimer)
            let r = 2 + progress * 8
            let alpha = CGFloat(max(0, 1 - progress))
            ctx.setFillColor(glow(alpha * 0.8))
            ctx.fill(CGRect(x: bx - r, y: by - 1.5, width: r * 2, height: 3))
            ctx.fill(CGRect(x: bx - 1.5, y: by - r, width: 3, height: r * 2))
            // 中心亮斑
            ctx.setFillColor(core(alpha))
            let cr = max(1, 4 * (1 - progress))
            ctx.fill(CGRect(x: bx - cr, y: by - cr, width: cr * 2, height: cr * 2))
        }

        // 玩家飞机（底部向上飞，受击闪烁时半透明）
        let flashOn = scene.isHitFlashing()
        let alpha: CGFloat = flashOn ? 0.4 : 1.0
        let px = scene.playerX * sx
        let py = h - 5
        // 尾焰：闪烁的倒三角
        if !flashOn {
            let flicker = 0.5 + 0.5 * sin(CACurrentMediaTime() * 20)
            let fl = 2 + flicker * 3
            ctx.setFillColor(NSColor(calibratedRed: 0.3, green: 1.0, blue: 0.4, alpha: 0.7 * alpha).cgColor)
            ctx.fill(CGRect(x: px - 1, y: py - fl, width: 2, height: fl))
        }
        // 玩家战机像素造型（向上）
        drawSprite([".X.",
                    "XXX",
                    "XXX",
                    "X.X"],
                   centerX: px, bottomY: py, cell: 2.0,
                   body: NSColor(calibratedRed: 0.6, green: 1.0, blue: 0.7, alpha: alpha).cgColor,
                   glow: NSColor(calibratedRed: 0.3, green: 1.0, blue: 0.5, alpha: 0.5 * alpha).cgColor)

        // 生命值指示（左下角小方块）
        let lives = scene.visibleLives()
        for i in 0 ..< lives {
            ctx.setFillColor(glow(0.9))
            ctx.fill(CGRect(x: 6 + CGFloat(i) * 7, y: h - 6, width: 4, height: 4))
        }
    }

    /// 按字符矩阵绘制像素小飞机。'X'=实体，'.'=空。以 bottomY 为底边。
    private func drawSprite(_ pattern: [String], centerX: CGFloat, bottomY: CGFloat,
                            cell: CGFloat, body: CGColor, glow: CGColor) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let rows = pattern.count
        guard rows > 0 else { return }
        let cols = pattern[0].count
        let totalW = CGFloat(cols) * cell
        let totalH = CGFloat(rows) * cell
        let startX = centerX - totalW / 2
        let startY = bottomY - totalH  // 顶部

        // 先画柔和辉光（扩大一格的同造型）
        ctx.setFillColor(glow)
        for (r, row) in pattern.enumerated() {
            for (c, ch) in row.enumerated() where ch == "X" {
                ctx.fill(CGRect(x: startX + CGFloat(c) * cell - 0.8,
                                y: startY + CGFloat(r) * cell - 0.8,
                                width: cell + 1.6,
                                height: cell + 1.6))
            }
        }
        // 再画实体
        ctx.setFillColor(body)
        for (r, row) in pattern.enumerated() {
            for (c, ch) in row.enumerated() where ch == "X" {
                ctx.fill(CGRect(x: startX + CGFloat(c) * cell,
                                y: startY + CGFloat(r) * cell,
                                width: cell,
                                height: cell))
            }
        }
    }

    private func drawCombo(ctx: CGContext, combo: Int, w: CGFloat, h: CGFloat) {
        let text = "x\(combo)"
        let fontSize: CGFloat = min(14, h * 0.45)
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(min(1, CGFloat(combo) / 10.0)),
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let point = CGPoint(x: w - size.width - 6, y: (h - size.height) / 2)
        (text as NSString).draw(at: point, withAttributes: attrs)
    }

    // MARK: - Touch Bar 固有尺寸

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 30)
    }
}
