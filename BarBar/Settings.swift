import Foundation

/// 使用 UserDefaults 持久化用户偏好（视觉动效、音效模式、空闲延时、登录时启动）。
final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let effectMode = "effectMode"
        static let soundMode = "soundMode"
        static let idleDismissDelay = "idleDismissDelay"
        static let launchAtLogin = "launchAtLogin"
        static let soundVolume = "soundVolume"
        static let soundPitch = "soundPitch"
        static let backgroundMode = "backgroundMode"
        static let glowHue = "glowHue"
    }

    private init() {}

    /// 当前视觉动效模式
    var effectMode: EffectMode {
        get {
            let raw = defaults.integer(forKey: Keys.effectMode)
            // 首次安装默认「折射激光」
            return EffectMode(rawValue: raw) ?? .laserReflect
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.effectMode)
        }
    }

    /// 当前音效模式
    var soundMode: SoundMode {
        get {
            let raw = defaults.integer(forKey: Keys.soundMode)
            // 首次安装默认「激光枪」
            return SoundMode(rawValue: raw) ?? .blaster
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.soundMode)
        }
    }

    /// 空闲多少秒后将 Touch Bar 交还给系统。
    var idleDismissDelay: TimeInterval {
        get {
            let stored = defaults.double(forKey: Keys.idleDismissDelay)
            return stored > 0 ? stored : 1.0
        }
        set {
            defaults.set(newValue, forKey: Keys.idleDismissDelay)
        }
    }

    /// 应用是否应在登录时启动。
    var launchAtLogin: Bool {
        get {
            defaults.bool(forKey: Keys.launchAtLogin)
        }
        set {
            defaults.set(newValue, forKey: Keys.launchAtLogin)
        }
    }

    /// 音效总音量（0.0 ~ 1.0，默认 0.7）
    var soundVolume: Float {
        get {
            let stored = defaults.float(forKey: Keys.soundVolume)
            return stored > 0 ? stored : 0.7
        }
        set {
            defaults.set(min(max(newValue, 0), 1), forKey: Keys.soundVolume)
        }
    }

    /// 音调倍率（0.5 ~ 2.0，默认 1.0，1.0 = 标准音高）
    var soundPitch: Float {
        get {
            let stored = defaults.float(forKey: Keys.soundPitch)
            return stored > 0 ? stored : 1.0
        }
        set {
            defaults.set(min(max(newValue, 0.5), 2.0), forKey: Keys.soundPitch)
        }
    }

    /// 当前背景光效模式（首次安装默认「边框呼吸灯」）
    var backgroundMode: BackgroundMode {
        get {
            // 从未设置过：迁移旧开关或给首次安装一个默认
            if defaults.object(forKey: Keys.backgroundMode) == nil {
                // 老版本用户：有 showCenterGlow 键 → 迁移
                if defaults.object(forKey: "showCenterGlow") != nil {
                    let legacyOff = !defaults.bool(forKey: "showCenterGlow")
                    let migrated: BackgroundMode = legacyOff ? .none : .centerGlow
                    defaults.set(migrated.rawValue, forKey: Keys.backgroundMode)
                    defaults.removeObject(forKey: "showCenterGlow")
                    return migrated
                }
                // 首次安装：默认边框呼吸灯
                defaults.set(BackgroundMode.breathingBorder.rawValue, forKey: Keys.backgroundMode)
                return .breathingBorder
            }
            let raw = defaults.integer(forKey: Keys.backgroundMode)
            return BackgroundMode(rawValue: raw) ?? .breathingBorder
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.backgroundMode)
        }
    }

    /// 背景光效的色相（0.0 ~ 1.0，默认 0.58 偏蓝）
    var glowHue: Float {
        get {
            let stored = defaults.float(forKey: Keys.glowHue)
            return stored >= 0 ? stored : 0.58
        }
        set {
            defaults.set(min(max(newValue, 0), 1), forKey: Keys.glowHue)
        }
    }
}
