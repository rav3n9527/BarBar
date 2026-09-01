import Foundation
import CoreGraphics

/// 从按键处向外扩展的环形波纹
struct Ripple {
    var center: CGPoint
    var radius: CGFloat
    var maxRadius: CGFloat
    var color: CGColor
    var alpha: CGFloat
    var lineWidth: CGFloat
    var life: Float
    var maxLife: Float

    /// 该圆环开始扩展前的可选延迟（秒）——
    /// 用于创建错开的多环水波纹。
    var delay: Float = 0
    /// 生成时的初始半径（使错开的圆环显得更大）
    var startRadius: CGFloat = 0

    var isAlive: Bool { life > 0 }

    var age: Float { 1.0 - (life / maxLife) }

    /// 考虑到延迟的扩展进度 0...1。
    /// 延迟结束前，进度为 0（圆环尚未显示）。
    var progress: Float {
        let elapsed = maxLife - life
        guard elapsed > delay else { return 0 }
        return min(1, (elapsed - delay) / (maxLife - delay))
    }

    mutating func update(dt: Float) {
        life -= dt
        let p = CGFloat(progress)
        radius = startRadius + p * maxRadius
        // 淡出并变细
        alpha = CGFloat(max(0, 1.0 - p * p)) * 0.8
        lineWidth = CGFloat(max(1.0, 3.0 * (1.0 - p)))
    }
}
