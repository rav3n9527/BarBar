import Foundation
import CoreGraphics

/// CRT 复古飞机射击小场景。
///
/// - 一个主角（玩家飞机），位于屏幕下方
/// - 3~5 个敌机随机出现在屏幕上方，缓慢飘动并自动朝玩家开火
/// - 打字 = 开火：每次按键玩家发射一颗子弹向上，同时玩家飞机平滑
///   移动到按键位置（自由移动）
/// - 命中反馈：敌机被击中有爆炸；玩家被击中有受击闪烁与短暂无敌
///
/// 整个场景在 ParticleSystem.update 中随帧推进，不依赖持续按键，
/// 因此不打字时敌机也会继续运动、射击，画面始终"活着"。
final class ShooterScene {
    // MARK: - 实体

    struct Bullet {
        var x: CGFloat
        var y: CGFloat
        var vy: CGFloat       // 正 = 向上（玩家子弹）
        var active = true
    }

    struct Enemy {
        var x: CGFloat
        var y: CGFloat
        var baseY: CGFloat        // 垂直漂浮的中心高度
        var baseVx: CGFloat       // 水平基准速度
        var phase: CGFloat        // 漂浮相位
        var amp: CGFloat          // 上下漂浮幅度
        var wobbleSpeed: CGFloat  // 漂浮角速度
        var kind: Int             // 造型种类 0...2
        var fireCooldown: Float
        var alive = true
    }

    struct Explosion {
        var x: CGFloat
        var y: CGFloat
        var timer: Float
        var maxTimer: Float
    }

    // MARK: - 场景尺寸（逻辑点）
    private let width: CGFloat = 1085
    private let height: CGFloat = 30

    // 场上敌机数量目标
    private let minEnemies = 5
    private let maxEnemies = 8

    // MARK: - 玩家
    private(set) var playerX: CGFloat = 542
    private var playerTargetX: CGFloat = 542
    private let playerY: CGFloat = 5
    private var playerSpeed: CGFloat = 420
    private var hitFlash: Float = 0
    private var invincible: Float = 0
    private(set) var lives = 3

    // MARK: - 集合
    private(set) var bullets: [Bullet] = []
    private(set) var enemies: [Enemy] = []
    private(set) var explosions: [Explosion] = []
    private var spawnTimer: Float = 0

    private var time: Float = 0

    // MARK: - 生命值回调（由 ParticleSystem 注入，用于在 Touch Bar 上显示"信号"）
    var onLivesChanged: ((Int) -> Void)?

    init() {
        reset()
    }

    /// 重置整局（重新进入该模式时调用）
    func reset() {
        bullets.removeAll()
        enemies.removeAll()
        explosions.removeAll()
        playerX = 542
        playerTargetX = 542
        hitFlash = 0
        invincible = 0
        lives = 3
        spawnTimer = 0.3
        // 预先生成满场敌机
        for _ in 0 ..< maxEnemies {
            spawnEnemy()
        }
    }

    // MARK: - 按键（打字开火 + 移动）

    /// 每次按键调用：玩家向按键位置移动，并发射一颗子弹。
    func keyPress(at x: CGFloat) {
        playerTargetX = min(max(x, 20), width - 20)

        // 玩家子弹向上
        let b = Bullet(x: playerX, y: playerY + 3, vy: 340, active: true)
        bullets.append(b)
        // 限制玩家子弹总数，防止打字过快堆积
        if bullets.filter({ $0.vy > 0 && $0.active }).count > 6 {
            // 移除最早的玩家子弹
            if let idx = bullets.firstIndex(where: { $0.vy > 0 && $0.active }) {
                bullets[idx].active = false
            }
        }
    }

    // MARK: - 每帧推进

    func update(dt: Float) {
        time += dt

        // 玩家平滑移动
        let dx = playerTargetX - playerX
        let move = playerSpeed * CGFloat(dt)
        if abs(dx) <= move {
            playerX = playerTargetX
        } else {
            playerX += (dx > 0 ? move : -move)
        }

        // 受击/无敌计时
        if hitFlash > 0 { hitFlash -= dt }
        if invincible > 0 { invincible -= dt }

        // 敌机数量维持在 minEnemies ~ maxEnemies
        let aliveEnemies = enemies.filter { $0.alive }.count
        if aliveEnemies < minEnemies {
            spawnTimer -= dt
            if spawnTimer <= 0 {
                spawnEnemy()
                spawnTimer = Float.random(in: 0.3 ... 0.9)
            }
        }

        // 敌机运动 + 开火
        for i in enemies.indices where enemies[i].alive {
            // 水平移动 + 撞墙反弹
            enemies[i].x += enemies[i].baseVx * CGFloat(dt)
            if enemies[i].x < 14 || enemies[i].x > width - 14 {
                enemies[i].baseVx *= -1
                enemies[i].x = min(max(enemies[i].x, 14), width - 14)
            }

            // 垂直正弦漂浮：围绕 baseY 上下浮动
            enemies[i].phase += enemies[i].wobbleSpeed * CGFloat(dt)
            enemies[i].y = enemies[i].baseY
                + sin(enemies[i].phase) * enemies[i].amp

            // 敌机射击：瞄准玩家水平位置，略带回散
            enemies[i].fireCooldown -= dt
            if enemies[i].fireCooldown <= 0 {
                // 限制敌机子弹总数，防止堆积
                let enemyBullets = bullets.filter { $0.vy < 0 && $0.active }.count
                if enemyBullets < 12 {
                    let aimX = enemies[i].x + (playerX - enemies[i].x) * 0.05
                    bullets.append(Bullet(x: aimX + CGFloat.random(in: -5 ... 5),
                                          y: enemies[i].y - 2,
                                          vy: -170,
                                          active: true))
                }
                enemies[i].fireCooldown = Float.random(in: 0.9 ... 1.8)
            }
        }

        // 子弹移动 + 碰撞
        for i in bullets.indices where bullets[i].active {
            bullets[i].y += bullets[i].vy * CGFloat(dt)
            // 横向轻移（若有 vx 可扩展，这里略）
            if bullets[i].y > height + 4 || bullets[i].y < -4 {
                bullets[i].active = false
            }
        }

        // 玩家子弹命中敌机
        for bi in bullets.indices where bullets[bi].active && bullets[bi].vy > 0 {
            for ei in enemies.indices where enemies[ei].alive {
                if abs(bullets[bi].x - enemies[ei].x) < 8 && abs(bullets[bi].y - enemies[ei].y) < 8 {
                    bullets[bi].active = false
                    enemies[ei].alive = false
                    addExplosion(x: enemies[ei].x, y: enemies[ei].y)
                    break
                }
            }
        }

        // 敌机子弹命中玩家
        if invincible <= 0 {
            for bi in bullets.indices where bullets[bi].active && bullets[bi].vy < 0 {
                if abs(bullets[bi].x - playerX) < 7 && abs(bullets[bi].y - playerY) < 7 {
                    bullets[bi].active = false
                    lives -= 1
                    onLivesChanged?(lives)
                    hitFlash = 0.5
                    invincible = 1.2
                    addExplosion(x: playerX, y: playerY)
                    if lives <= 0 {
                        // 游戏结束：重置场景，重新开局
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                            self?.reset()
                        }
                    }
                    break
                }
            }
        }

        // 清理
        bullets.removeAll { !$0.active }
        enemies.removeAll { !$0.alive }

        // 爆炸动画推进
        for i in explosions.indices {
            explosions[i].timer -= dt
        }
        explosions.removeAll { $0.timer <= 0 }
    }

    // MARK: - 生成

    private func spawnEnemy() {
        let direction: CGFloat = Bool.random() ? -1 : 1
        // 在屏幕上部散开，避免重叠：尽量均匀分布
        let occupied = enemies.filter { $0.alive }.map { $0.x }
        var spawnX = CGFloat.random(in: 40 ... (width - 40))
        // 简单尝试避开已有敌机的 x
        for _ in 0 ..< 8 {
            let tooClose = occupied.contains { abs($0 - spawnX) < 70 }
            if !tooClose { break }
            spawnX = CGFloat.random(in: 40 ... (width - 40))
        }

        let e = Enemy(
            x: spawnX,
            y: CGFloat.random(in: 18 ... 26),
            baseY: CGFloat.random(in: 18 ... 26),
            baseVx: direction * CGFloat.random(in: 20 ... 45),
            phase: CGFloat.random(in: 0 ... (.pi * 2)),
            amp: CGFloat.random(in: 1.5 ... 3.5),
            wobbleSpeed: CGFloat.random(in: 1.5 ... 4.0),
            kind: Int.random(in: 0 ... 2),
            fireCooldown: Float.random(in: 0.6 ... 1.4),
            alive: true
        )
        enemies.append(e)
    }

    private func addExplosion(x: CGFloat, y: CGFloat) {
        let maxT: Float = 0.35
        explosions.append(Explosion(x: x, y: y, timer: maxT, maxTimer: maxT))
    }

    // MARK: - 状态查询（供绘制）

    func isHitFlashing() -> Bool { hitFlash > 0 }

    func visibleLives() -> Int { max(0, lives) }
}
