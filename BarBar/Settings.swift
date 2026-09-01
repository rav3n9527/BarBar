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
    }

    private init() {}

    /// 当前视觉动效模式
    var effectMode: EffectMode {
        get {
            let raw = defaults.integer(forKey: Keys.effectMode)
            return EffectMode(rawValue: raw) ?? .burst
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.effectMode)
        }
    }

    /// 当前音效模式
    var soundMode: SoundMode {
        get {
            let raw = defaults.integer(forKey: Keys.soundMode)
            return SoundMode(rawValue: raw) ?? .pentatonic
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.soundMode)
        }
    }

    /// 空闲多少秒后将 Touch Bar 交还给系统。
    /// 以十分之一秒存储，便于使用整数。
    var idleDismissDelay: TimeInterval {
        get {
            let stored = defaults.double(forKey: Keys.idleDismissDelay)
            return stored > 0 ? stored : 3.0
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
}
