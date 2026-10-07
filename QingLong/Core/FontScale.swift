import SwiftUI

/// 全局文字大小缩放档位。
///
/// App 里所有字号原本都是写死的 `.font(.system(size: 12.5))`，共 180 余处。
/// 这里不引入新的字体环境值（iOS 14 没有全局字体缩放），而是把每一处字号的
/// **基准值**抽出来：统一写成 `Theme.font(12.5)`，实际字号 = 基准值 × 缩放系数。
///
/// 缩放系数存在 `@AppStorage(FontScale.storageKey)`，由设置页写入；
/// App 入口读同一个键并挂 `.id(fontScaleRaw)`，值一变就重建视图树，
/// 因此拖动滑杆时全 App 字号立即联动，无需重启。
enum FontScale {

    /// `@AppStorage` 键名，设置页与读取方共用。
    static let storageKey = "font-scale"

    /// 可选档位（与设置页滑块的离散刻度一致）。
    static let steps: [Double] = [0.85, 0.925, 1.0, 1.1, 1.2, 1.35]

    /// 默认「标准」。
    static let `default`: Double = 1.0

    /// 把任意缩放值吸附到最接近的档位，保证设置页与全局一致。
    static func normalize(_ value: Double) -> Double {
        guard let hit = steps.min(by: { abs($0 - value) < abs($1 - value) }) else {
            return `default`
        }
        return hit
    }

    /// 档位的中文名，用于设置页展示当前值。
    static func title(for value: Double) -> String {
        switch normalize(value) {
        case 0.85:  return "较小"
        case 0.925: return "小"
        case 1.0:   return "标准"
        case 1.1:   return "大"
        case 1.2:   return "较大"
        default:    return "最大"
        }
    }

    /// 档位序号（0...5），用于分档选择。
    static func index(for value: Double) -> Int {
        let v = normalize(value)
        for (i, s) in steps.enumerated() where s == v { return i }
        return 2
    }
}

// MARK: - 读取缩放

/// 主题里提供当前缩放系数，供各页面计算实际字号。
///
/// 之所以不逐个页面注入 `@AppStorage`，是因为 `Theme` 已经是全局视觉常量入口，
/// 这里加一个可刷新的缩放值，改动面最小。
extension Theme {
    /// 当前文字缩放系数（1.0 = 标准）。
    static var fontScale: Double {
        let raw = UserDefaults.standard.double(forKey: FontScale.storageKey)
        // 没写过（0）或被写成非法值时回落到标准档
        guard raw > 0 else { return FontScale.default }
        return FontScale.normalize(raw)
    }

    /// 按全局缩放计算实际字号：`Theme.font(13)`。
    static func font(_ base: CGFloat) -> CGFloat {
        CGFloat(base * fontScale)
    }
}
