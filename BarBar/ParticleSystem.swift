import Foundation
import CoreGraphics
import Cocoa

/// 可从菜单切换的视觉效果模式。
enum EffectMode: Int, CaseIterable {
    case burst = 0
    case ripple = 1
    case rain = 2
    case bounce = 3
    case shockwave = 4
    case laser = 5
    case meteor = 6
    case spectrum = 7
    case fire = 8
    case laserReflect = 9
    case ecg = 10
    case shooter = 11

    var displayName: String {
        switch self {
        case .burst:        return "粒子爆炸"
        case .ripple:       return "水波纹"
        case .rain:         return "光雨"
        case .bounce:       return "弹跳球"
        case .shockwave:    return "冲击波"
        case .laser:        return "激光脉冲"
        case .meteor:       return "流星"
        case .spectrum:     return "频谱"
        case .fire:         return "火焰"
        case .laserReflect: return "折射激光"
        case .ecg:          return "心电图"
        case .shooter:      return "CRT 空战"
        }
    }
}

/// 管理所有活动的粒子与波纹，负责生成与物理更新
class ParticleSystem {
    // MARK: - 配置
    struct Config {
        /// 每次按键生成的粒子数
        var particlesPerKeypress: Int = 12
        /// 每次按键生成的波纹数
        var ripplesPerKeypress: Int = 1
        /// 粒子寿命范围（秒）
        var particleLife: ClosedRange<Float> = 0.6 ... 1.4
        /// 波纹寿命（秒）
        var rippleLife: Float = 0.8
        /// 粒子的初始速度范围
        var speedRange: ClosedRange<CGFloat> = 80 ... 220
        /// 粒子半径范围
        var radiusRange: ClosedRange<CGFloat> = 2 ... 5
        /// 波纹最大半径
        var maxRippleRadius: CGFloat = 60
        /// 全局粒子数上限（Touch Bar 性能有限）
        var maxParticles: Int = 80
        /// 全局波纹数上限
        var maxRipples: Int = 10
    }

    var config = Config()

    /// 当前视觉效果模式
    var mode: EffectMode = .burst {
        didSet {
            clear()   // 切换模式时清除旧效果
            // ECG 采样数组只在 ECG 模式使用；进出 ECG 模式时清掉，
            // 避免残留旧波形（ECG→ECG 重复赋值时保留现有波形）
            if oldValue != .ecg || mode != .ecg {
                ecgSamples.removeAll()
            }
            // 进入 CRT 空战模式时重置游戏
            if mode == .shooter && oldValue != .shooter {
                shooterScene.reset()
            }
        }
    }

    // MARK: - 状态
    private(set) var particles: [Particle] = []
    private(set) var ripples: [Ripple] = []

    /// 最近一次生成效果的时间戳（CFAbsoluteTime）。
    /// 供各视图共享的空闲清理判断——避免每个视图各自维护独立的
    /// 空闲时间戳，导致让出/重新接管后新视图（时间戳为 0）误清粒子。
    private(set) var lastSpawnTime: CFAbsoluteTime = 0

    // MARK: 心电图（ECG）数据
    /// 心电图采样线：按 Touch Bar 宽度固定的若干采样点，值域约 -1...1。
    /// 采样数组整体向左滚动，模拟心电监护仪。
    private(set) var ecgSamples: [CGFloat] = []
    /// ECG 采样点数量（按 Touch Bar 宽度）
    private let ecgSampleCount = 220
    /// 当前 ECG "心跳"相位进度（0...1），每次按键从 0 重启
    private var ecgPhase: Double = 0
    /// 正在流经屏幕的心跳脉冲（QRS 尖峰）——由最近按键激发
    private var ecgBeatIntensity: CGFloat = 0
    /// 上次按键是否产生了 ECG 脉冲的时间
    private var ecgBeatActive = false

    // MARK: CRT 空战场景
    /// 飞机射击小游戏场景（CRT 空战模式）
    let shooterScene = ShooterScene()

    /// 用于连击追踪的近期按键时间戳
    private var recentPresses: [TimeInterval] = []
    private let comboWindow: TimeInterval = 1.5

    /// 当前连击数
    var combo: Int { recentPresses.count }

    /// BPS（每秒节拍数）——连击窗口内的每秒按键数
    var keysPerSecond: Double {
        guard recentPresses.count >= 2 else { return 0 }
        let span = recentPresses.last! - recentPresses.first!
        return span > 0 ? Double(recentPresses.count - 1) / span : 0
    }

    // MARK: - 调色板（霓虹 / 合成波）
    static let baseColors: [CGColor] = [
        CGColor(red: 1.0, green: 0.2, blue: 0.4, alpha: 1),   // 荧光粉红
        CGColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 1),   // 电光蓝
        CGColor(red: 0.2, green: 1.0, blue: 0.6, alpha: 1),   // 霓虹绿
        CGColor(red: 1.0, green: 0.8, blue: 0.1, alpha: 1),   // 金色
        CGColor(red: 0.8, green: 0.3, blue: 1.0, alpha: 1),   // 紫色
        CGColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1),   // 橙色
    ]
    private var colorIndex = 0

    /// 从调色板中循环选取下一种颜色
    private func nextColor() -> CGColor {
        let c = Self.baseColors[colorIndex % Self.baseColors.count]
        colorIndex += 1
        return c
    }

    // MARK: - 生成

    /// 在触控栏的指定 x 位置生成对应的效果
    func spawn(at x: CGFloat, barHeight: CGFloat) {
        let now = Date().timeIntervalSince1970
        recentPresses.append(now)
        recentPresses = recentPresses.filter { now - $0 < comboWindow }

        // 记录本次生成时间（供视图的空闲清理判断）
        lastSpawnTime = CFAbsoluteTimeGetCurrent()

        switch mode {
        case .burst:        spawnBurst(at: x, barHeight: barHeight)
        case .ripple:       spawnRipple(at: x, barHeight: barHeight)
        case .rain:         spawnRain(at: x, barHeight: barHeight)
        case .bounce:       spawnBounce(at: x, barHeight: barHeight)
        case .shockwave:    spawnShockwave(at: x, barHeight: barHeight)
        case .laser:        spawnLaser(at: x, barHeight: barHeight)
        case .meteor:       spawnMeteor(at: x, barHeight: barHeight)
        case .spectrum:     spawnSpectrum(at: x, barHeight: barHeight)
        case .fire:         spawnFire(at: x, barHeight: barHeight)
        case .laserReflect: spawnLaserReflect(at: x, barHeight: barHeight)
        case .ecg:          spawnECG(at: x, barHeight: barHeight)
        case .shooter:      shooterScene.keyPress(at: x)
        }

        // 裁剪溢出：Touch Bar 性能有限，超过上限时丢弃最旧的
        if particles.count > config.maxParticles {
            particles.removeFirst(particles.count - config.maxParticles)
        }
        if ripples.count > config.maxRipples {
            ripples.removeFirst(ripples.count - config.maxRipples)
        }
    }

    /// 经典粒子爆炸 + 一个扩展圆环
    private func spawnBurst(at x: CGFloat, barHeight: CGFloat) {
        let color = nextColor()
        let centerY = barHeight * 0.5

        for _ in 0 ..< config.particlesPerKeypress {
            let angle = CGFloat.random(in: 0 ..< .pi * 2)
            let speed = CGFloat.random(in: config.speedRange)
            let life = Float.random(in: config.particleLife)
            let radius = CGFloat.random(in: config.radiusRange)

            var p = Particle(
                position: CGPoint(x: x, y: centerY),
                velocity: CGPoint(x: cos(angle) * speed, y: sin(angle) * speed),
                color: color,
                alpha: 1.0,
                radius: radius,
                life: life,
                maxLife: life,
                born: Date().timeIntervalSince1970
            )
            p.gravity = 40
            p.drag = 1.5
            particles.append(p)
        }

        ripples.append(Ripple(
            center: CGPoint(x: x, y: centerY),
            radius: 0,
            maxRadius: config.maxRippleRadius + CGFloat(combo) * 2,
            color: color,
            alpha: 0.8,
            lineWidth: 3,
            life: config.rippleLife,
            maxLife: config.rippleLife
        ))
    }

    /// 同心水波纹——多个宽度递减的圆环
    private func spawnRipple(at x: CGFloat, barHeight: CGFloat) {
        let color = nextColor()
        let centerY = barHeight * 0.5
        let now = Date().timeIntervalSince1970
        let baseLife: Float = 0.9
        let maxR = config.maxRippleRadius + CGFloat(combo) * 2

        // 3 个错开的圆环
        for i in 0 ..< 3 {
            let idx = CGFloat(i)
            ripples.append(Ripple(
                center: CGPoint(x: x, y: centerY),
                radius: 0,
                maxRadius: maxR + idx * 14,
                color: color,
                alpha: 0.75 - idx * 0.12,
                lineWidth: 3.2 - idx,
                life: baseLife + Float(i) * 0.15,
                maxLife: baseLife + Float(i) * 0.15,
                delay: Float(i) * 0.15,
                startRadius: 2 + idx * 4
            ))
        }

        // 从落点向上飘散的少量火花
        for _ in 0 ..< 4 {
            let life = Float.random(in: 0.4 ... 0.8)
            var p = Particle(
                position: CGPoint(x: x + CGFloat.random(in: -4 ... 4), y: centerY),
                velocity: CGPoint(x: CGFloat.random(in: -12 ... 12), y: CGFloat.random(in: 30 ... 70)),
                color: color,
                alpha: 0.9,
                radius: 1.5,
                life: life,
                maxLife: life,
                born: now
            )
            p.gravity = 0
            p.drag = 0.5
            particles.append(p)
        }
    }

    /// 发光雨滴——粒子从顶部沿按下列下落
    private func spawnRain(at x: CGFloat, barHeight: CGFloat) {
        let color = nextColor()
        let now = Date().timeIntervalSince1970

        let dropCount = 8 + min(combo, 8)
        for _ in 0 ..< dropCount {
            let life = Float.random(in: 0.7 ... 1.2)
            var p = Particle(
                position: CGPoint(x: x + CGFloat.random(in: -10 ... 10), y: barHeight + CGFloat.random(in: 2 ... 6)),
                velocity: CGPoint(x: CGFloat.random(in: -6 ... 6), y: CGFloat.random(in: -140 ... -60)),
                color: color,
                alpha: 0.9,
                radius: CGFloat.random(in: 1.5 ... 3),
                life: life,
                maxLife: life,
                born: now
            )
            p.gravity = 120   // 快速下落
            p.drag = 0.1
            p.growRate = 0
            particles.append(p)
        }
    }

    /// 弹跳发光球——在顶部生成，下落并在底面上弹跳
    private func spawnBounce(at x: CGFloat, barHeight: CGFloat) {
        let color = nextColor()
        let now = Date().timeIntervalSince1970
        let life = Float.random(in: 2.0 ... 3.0)

        var p = Particle(
            position: CGPoint(x: x, y: barHeight + CGFloat.random(in: 2 ... 6)),
            velocity: CGPoint(x: CGFloat.random(in: -15 ... 15), y: 0),
            color: color,
            alpha: 1.0,
            radius: CGFloat.random(in: 3.5 ... 5.5),
            life: life,
            maxLife: life,
            born: now
        )
        p.gravity = 180
        p.drag = 0.2
        p.growRate = 0.05
        p.bounces = true
        p.floorY = 3
        p.bounceRestitution = 0.8
        particles.append(p)
    }

    // MARK: - 冲击波
    /// 向外扩展的水平能量环——成对的波从按键处向左右扫过，
    /// 并伴随明亮的中心闪光。
    private func spawnShockwave(at x: CGFloat, barHeight: CGFloat) {
        let color = nextColor()
        let centerY = barHeight * 0.5
        let now = Date().timeIntervalSince1970

        // 向左和向右扩展的半环（用水平散开的粒子模拟）
        for direction: CGFloat in [-1, 1] {
            let life = Float.random(in: 0.5 ... 0.7)
            var p = Particle(
                position: CGPoint(x: x, y: centerY),
                velocity: CGPoint(x: direction * CGFloat.random(in: 250 ... 420),
                                  y: CGFloat.random(in: -6 ... 6)),
                color: color,
                alpha: 1.0,
                radius: CGFloat.random(in: 3 ... 6),
                life: life,
                maxLife: life,
                born: now
            )
            p.gravity = 0
            p.drag = 0.3
            p.growRate = 2.5   // 在移动过程中扩展
            p.tailLength = 40  // 水平拖尾
            particles.append(p)
        }

        // 明亮的中心闪光
        var core = Particle(
            position: CGPoint(x: x, y: centerY),
            velocity: .zero,
            color: color,
            alpha: 1.0,
            radius: 14,
            life: 0.25,
            maxLife: 0.25,
            born: now
        )
        core.gravity = 0
        core.drag = 0
        core.growRate = 8
        particles.append(core)

        // 少量火花
        for _ in 0 ..< 6 {
            let angle = CGFloat.random(in: -0.6 ... 0.6)
            let life = Float.random(in: 0.3 ... 0.5)
            var s = Particle(
                position: CGPoint(x: x, y: centerY),
                velocity: CGPoint(x: cos(angle) * CGFloat.random(in: 150 ... 300),
                                  y: sin(angle) * CGFloat.random(in: 30 ... 80)),
                color: color,
                alpha: 0.9,
                radius: 1.5,
                life: life,
                maxLife: life,
                born: now
            )
            s.gravity = 0
            s.drag = 1.0
            particles.append(s)
        }
    }

    // MARK: - 激光
    /// 垂直激光束——一束光从底部向上喷发，
    /// 如同科幻能量光束。连击时发射双光束。
    private func spawnLaser(at x: CGFloat, barHeight: CGFloat) {
        let color = nextColor()
        let now = Date().timeIntervalSince1970
        let beamCount = combo >= 10 ? 2 : 1

        for _ in 0 ..< beamCount {
            let life = Float.random(in: 0.35 ... 0.5)
            var p = Particle(
                position: CGPoint(x: x + CGFloat.random(in: -2 ... 2), y: 0),
                velocity: CGPoint(x: 0, y: CGFloat.random(in: 260 ... 380)),
                color: color,
                alpha: 1.0,
                radius: CGFloat.random(in: 2.5 ... 3.5),
                life: life,
                maxLife: life,
                born: now
            )
            p.gravity = -120   // 持续向上加速
            p.drag = 0.2
            p.growRate = 0
            p.tailIsVertical = true
            p.tailLength = barHeight * 2   // 光束从底部延伸到顶部之外
            particles.append(p)
        }

        // 地面撞击光晕
        var glow = Particle(
            position: CGPoint(x: x, y: 0),
            velocity: .zero,
            color: color,
            alpha: 0.8,
            radius: 10,
            life: 0.3,
            maxLife: 0.3,
            born: now
        )
        glow.gravity = 0
        glow.growRate = 5
        particles.append(glow)
    }

    // MARK: - 流星
    /// 一颗炽热的流星拖着长长的彗尾划过触控栏，
    /// 在按下列处生成。
    private func spawnMeteor(at x: CGFloat, barHeight: CGFloat) {
        let color = nextColor()
        let now = Date().timeIntervalSince1970
        let direction: CGFloat = Bool.random() ? 1 : -1
        let startX = direction > 0 ? x - 20 : x + 20

        for _ in 0 ..< 2 {
            let life = Float.random(in: 0.7 ... 1.1)
            var p = Particle(
                position: CGPoint(x: startX, y: barHeight * CGFloat.random(in: 0.3 ... 0.7)),
                velocity: CGPoint(x: direction * CGFloat.random(in: 300 ... 420),
                                  y: CGFloat.random(in: -10 ... 10)),
                color: color,
                alpha: 1.0,
                radius: CGFloat.random(in: 2.5 ... 4),
                life: life,
                maxLife: life,
                born: now
            )
            p.gravity = 0
            p.drag = 0.1
            p.growRate = 0
            p.tailLength = 90   // 长长的彗尾
            particles.append(p)
        }

        // 拖尾余烬
        for _ in 0 ..< 5 {
            let life = Float.random(in: 0.4 ... 0.7)
            var e = Particle(
                position: CGPoint(x: startX - direction * 30, y: barHeight * CGFloat.random(in: 0.3 ... 0.7)),
                velocity: CGPoint(x: direction * CGFloat.random(in: 200 ... 300),
                                  y: CGFloat.random(in: -15 ... 15)),
                color: color,
                alpha: 0.8,
                radius: CGFloat.random(in: 1 ... 2),
                life: life,
                maxLife: life,
                born: now
            )
            e.gravity = 0
            e.drag = 0.5
            e.tailLength = 40
            particles.append(e)
        }
    }

    // MARK: - 频谱
    /// 均衡器样式的垂直柱状条在按下列处喷发，每根都在闪烁，
    /// 如同频谱分析仪。连击会增加柱条数量。
    private func spawnSpectrum(at x: CGFloat, barHeight: CGFloat) {
        let color = nextColor()
        let now = Date().timeIntervalSince1970
        let barCount = 5 + min(combo, 6)

        for i in 0 ..< barCount {
            let offset = CGFloat(i) * 6 - CGFloat(barCount / 2) * 6
            let life = Float.random(in: 0.5 ... 0.8)
            var p = Particle(
                position: CGPoint(x: x + offset, y: 0),
                velocity: CGPoint(x: 0, y: 0),
                color: color,
                alpha: 0.9,
                radius: CGFloat.random(in: 1.5 ... 2.5),
                life: life,
                maxLife: life,
                born: now
            )
            p.gravity = 0
            p.drag = 0
            p.growRate = 0
            p.tailIsVertical = true
            p.tailLength = barHeight * CGFloat.random(in: 0.5 ... 1.0)
            particles.append(p)
        }
    }

    // MARK: - 火焰
    /// 熊熊火焰——粒子在按下列处点燃并向上飘升，
    /// 闪烁的橙/红/蓝三色，如同喷灯。
    private func spawnFire(at x: CGFloat, barHeight: CGFloat) {
        let now = Date().timeIntervalSince1970
        let flameCount = 14 + min(combo, 8)

        for _ in 0 ..< flameCount {
            let life = Float.random(in: 0.4 ... 0.8)
            let heat = CGFloat.random(in: 0 ... 1)

            // 火焰调色板：白热 → 黄色 → 橙色 → 红色 → 蓝色基底
            let color: CGColor
            if heat > 0.9 {
                color = CGColor(red: 1.0, green: 1.0, blue: 0.9, alpha: 1)
            } else if heat > 0.7 {
                color = CGColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 1)
            } else if heat > 0.4 {
                color = CGColor(red: 1.0, green: 0.5, blue: 0.1, alpha: 1)
            } else if heat > 0.2 {
                color = CGColor(red: 0.9, green: 0.2, blue: 0.05, alpha: 1)
            } else {
                color = CGColor(red: 0.2, green: 0.3, blue: 0.9, alpha: 1)
            }

            var p = Particle(
                position: CGPoint(x: x + CGFloat.random(in: -8 ... 8), y: 0),
                velocity: CGPoint(x: CGFloat.random(in: -12 ... 12),
                                  y: CGFloat.random(in: 80 ... 200)),
                color: color,
                alpha: 0.95,
                radius: CGFloat.random(in: 2 ... 4),
                life: life,
                maxLife: life,
                born: now
            )
            p.gravity = 30    // 轻微的浮力牵引
            p.drag = 1.8
            p.growRate = 0.6
            particles.append(p)
        }
    }

    // MARK: - 折射激光

    /// 星球大战风格的折射激光：激光束以斜角射入，在 Touch Bar 的
    /// 上下边缘不断反射弹跳，形成来回穿梭的光束。
    private func spawnLaserReflect(at x: CGFloat, barHeight: CGFloat) {
        let now = Date().timeIntervalSince1970

        // 荧光绿激光（单色）
        let color = CGColor(red: 0.2, green: 1.0, blue: 0.35, alpha: 1)

        // 限制折射激光总条数（最多 12 条），防止过多导致卡顿
        let activeLasers = particles.filter { $0.reflectsEdges }.count
        let remaining = 12 - activeLasers
        guard remaining > 0 else { return }

        // 每次按键发射 1~2 束激光（连击越高越多），但不超出上限
        let desired = combo >= 8 ? 2 : 1
        let beamCount = min(desired, remaining)
        for _ in 0 ..< beamCount {
            // 从按键位置的垂直范围内射出，斜角方向（向上或向下）
            let startY = CGFloat.random(in: barHeight * 0.2 ... barHeight * 0.8)
            // 斜角：与水平方向的夹角在 20°~60° 之间
            let angle = CGFloat.random(in: 0.35 ... 1.05) * (Bool.random() ? 1 : -1)
            let speed = CGFloat.random(in: 280 ... 420)

            var p = Particle(
                position: CGPoint(x: x, y: startY),
                velocity: CGPoint(x: cos(angle) * speed,
                                  y: sin(angle) * speed),
                color: color,
                alpha: 1.0,
                radius: CGFloat.random(in: 1.2 ... 1.8),
                life: Float.random(in: 0.8 ... 1.4),
                maxLife: Float.random(in: 0.8 ... 1.4),
                born: now
            )
            p.gravity = 0
            p.drag = 0
            p.growRate = 0
            p.reflectsEdges = true
            p.boundHeight = barHeight
            p.tailLength = 70   // 长长的激光拖尾
            particles.append(p)
        }

        // 发射口的闪光
        var muzzle = Particle(
            position: CGPoint(x: x, y: CGFloat.random(in: 0 ... barHeight)),
            velocity: .zero,
            color: color,
            alpha: 1.0,
            radius: 3.5,
            life: 0.15,
            maxLife: 0.15,
            born: now
        )
        muzzle.gravity = 0
        muzzle.growRate = 5
        particles.append(muzzle)
    }

    // MARK: - 心电图（ECG）

    /// 初始化心电图采样数组（切换/进入 ECG 模式时调用）
    private func ensureECGInitialized() {
        guard ecgSamples.isEmpty else { return }
        ecgSamples = Array(repeating: 0, count: ecgSampleCount)
        ecgPhase = 0
        ecgBeatIntensity = 0
        ecgBeatActive = false
    }

    /// ECG 模式：每次按键激发一次"心跳"，让完整 QRS 波形流经屏幕。
    private func spawnECG(at x: CGFloat, barHeight: CGFloat) {
        ensureECGInitialized()
        // 按键越快（combo 越高）心跳越强
        ecgBeatIntensity = min(1.0, 0.5 + CGFloat(combo) * 0.06)
        ecgBeatActive = true
    }

    /// ECG 采样线向右滚动：右端追加新采样，整体左移，模拟监护仪扫描。
    private func updateECG(dt: Float) {
        guard !ecgSamples.isEmpty else { return }

        // 相位持续推进（右端新采样对应"当前时刻"）
        ecgPhase += Double(dt) * 0.9

        // 若强度已衰减至静息，则放慢相位、清除活跃标记
        if ecgBeatIntensity <= 0.01 {
            ecgBeatActive = false
        }
        // 心搏结束后（相位过一圈）强度自然回落，回归平静基线
        if ecgBeatActive && ecgPhase >= 1.0 {
            ecgBeatActive = false
            ecgPhase = 0
            ecgBeatIntensity = 0
        }

        // 新采样 = 平静基线 + （活跃时）完整心搏波形
        let p = CGFloat(ecgPhase.truncatingRemainder(dividingBy: 1.0))
        var newValue = baseWaveform()
        if ecgBeatActive && ecgBeatIntensity > 0.01 {
            newValue += ecgBeatWaveform(p) * ecgBeatIntensity
        }
        // 心搏结束后的一小段让强度平滑衰减
        ecgBeatIntensity *= CGFloat(1.0 - 0.5 * dt)
        if ecgBeatIntensity < 0.02 { ecgBeatIntensity = 0 }

        // 将新值压入右端，移除左端 → 整条线向左滚动
        ecgSamples.removeFirst()
        ecgSamples.append(newValue)
    }

    /// 一个完整心搏周期的波形（相位 p ∈ 0...1）：P 波 → QRS → T 波
    private func ecgBeatWaveform(_ p: CGFloat) -> CGFloat {
        let pWave = gaussian(p, center: 0.08, width: 0.045) * 0.25
        // QRS：Q 小下冲 → R 高大尖峰 → S 下冲
        let qWave = -gaussian(p, center: 0.22, width: 0.018) * 0.5
        let rWave = gaussian(p, center: 0.25, width: 0.028) * 1.6
        let sWave = -gaussian(p, center: 0.30, width: 0.02) * 0.45
        let tWave = gaussian(p, center: 0.55, width: 0.07) * 0.55
        return pWave + qWave + rWave + sWave + tWave
    }

    /// 平静基线：小幅上下呼吸，让心电图看起来"活着"
    private func baseWaveform() -> CGFloat {
        let t = CFAbsoluteTimeGetCurrent()
        return CGFloat(sin(t * 1.8) * 0.05 + sin(t * 3.1) * 0.03)
    }

    /// 归一化高斯，用于生成 P/QRS/T 波形状
    private func gaussian(_ x: CGFloat, center: CGFloat, width: CGFloat) -> CGFloat {
        let d = (x - center) / width
        return exp(-d * d)
    }

    // MARK: - 更新

    /// 将所有粒子与波纹推进 dt 秒，移除已消亡的对象
    func update(dt: Float) {
        // 更新粒子
        for i in particles.indices {
            particles[i].update(dt: dt)
        }
        particles.removeAll { !$0.isAlive }

        // 更新波纹
        for i in ripples.indices {
            ripples[i].update(dt: dt)
        }
        ripples.removeAll { !$0.isAlive }

        // 清理过期的连击按键记录
        let now = Date().timeIntervalSince1970
        recentPresses = recentPresses.filter { now - $0 < comboWindow }

        // 心电图模式：推进滚动采样线
        if mode == .ecg {
            if ecgSamples.isEmpty {
                ensureECGInitialized()
            }
            updateECG(dt: dt)
        }

        // CRT 空战模式：推进游戏场景
        if mode == .shooter {
            shooterScene.update(dt: dt)
        }
    }

    /// 移除所有效果（空闲时使用）
    func clear() {
        particles.removeAll()
        ripples.removeAll()
        recentPresses.removeAll()
        lastSpawnTime = CFAbsoluteTimeGetCurrent()  // 重置，避免刚清空又被判空闲
    }
}
