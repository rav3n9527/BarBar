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
    private var lastActivityTime: TimeInterval = 0
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

    /// 每次按键时调用，用于重置空闲计时器
    func notifyActivity() {
        lastActivityTime = CFAbsoluteTimeGetCurrent()
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

    // MARK: - 渲染

    private func renderFrame() {
        let now = CFAbsoluteTimeGetCurrent()
        let dt: Float = lastTimestamp == 0 ? 1.0 / 60.0 : Float(now - lastTimestamp)
        lastTimestamp = now

        // 更新粒子物理（限制 dt 以避免“死亡螺旋”）
        particleSystem.update(dt: min(dt, 0.05))

        // 空闲淡出——长时间无操作后清除粒子
        if now - lastActivityTime > idleTimeout {
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

        // 环境中心光晕——bounce 模式跳过（该模式有自己的球），
        // 且受"背景彩条"开关控制
        if particleSystem.mode != .bounce && settings.showCenterGlow {
            drawCenterGlow(ctx: ctx, w: w, h: h)
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
            }
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
