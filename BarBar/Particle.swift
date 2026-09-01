import Foundation
import CoreGraphics

/// 水波纹效果中的单个粒子
struct Particle {
    var position: CGPoint
    var velocity: CGPoint
    var color: CGColor
    var alpha: CGFloat
    var radius: CGFloat
    var life: Float        // 剩余寿命（秒）
    var maxLife: Float     // 初始寿命（用于淡出计算）
    var born: TimeInterval // 生成时的时间戳

    // 物理参数调节
    var gravity: CGFloat = 40.0   // 向下加速度
    var drag: CGFloat = 1.5       // 速度阻尼系数
    var growRate: CGFloat = 0.3   // 每秒半径增长率

    // 弹跳行为（用于"弹跳球"模式）
    var bounces = false
    var floorY: CGFloat = 0       // 弹跳的地面高度
    var bounceRestitution: CGFloat = 0.75  // 弹跳后保留的能量比例

    // 拖尾/光束渲染（用于流星 / 激光 / 频谱模式）
    var tailLength: CGFloat = 0   // 发光拖尾向后延伸的长度
    var tailIsVertical = false    // true = 垂直光束，false = 水平拖尾

    /// 该粒子是否仍然存活
    var isAlive: Bool { life > 0 }

    /// 归一化年龄 0...1
    var age: Float { 1.0 - (life / maxLife) }

    /// 更新一帧的位置与衰减
    mutating func update(dt: Float) {
        position.x += velocity.x * CGFloat(dt)
        position.y += velocity.y * CGFloat(dt)

        // 重力
        velocity.y -= gravity * CGFloat(dt)

        // 阻尼
        velocity.x *= CGFloat(1.0 - drag * CGFloat(dt))
        velocity.y *= CGFloat(1.0 - drag * CGFloat(dt))

        // 在地面上弹跳
        if bounces && position.y < floorY {
            position.y = floorY
            velocity.y = abs(velocity.y) * bounceRestitution
            // 如果弹跳太弱则使其消亡
            if velocity.y < 20 {
                life = 0
            }
        }

        // 淡出
        life -= dt
        alpha = CGFloat(max(0, life / maxLife))
        radius *= CGFloat(1.0 + growRate * CGFloat(dt))
    }
}
