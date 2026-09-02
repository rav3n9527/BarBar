import Foundation

/// 背景光效模式，可从设置中选择。
/// 背景光效常驻在粒子下方，为 Touch Bar 提供氛围灯光。
enum BackgroundMode: Int, CaseIterable {
    case none = 0
    case centerGlow = 1
    case breathingBorder = 2

    var displayName: String {
        switch self {
        case .none:            return "无"
        case .centerGlow:      return "中心彩条"
        case .breathingBorder: return "边框呼吸灯"
        }
    }
}
