import SwiftUI

/// 全局文字大小缩放档位。
///
/// App 里所有字号都是写死的 `.font(.system(size: 12.5))`，共 180 余处，
/// 逐个改成动态值不现实。SwiftUI 在 iOS 14 没有全局字体环境值，
/// 但可以用 `.environment(\.dynamicTypeSize, ...)` 之外的办法——
/// 这里采用**自绘字体**方案：给 `View` 加一个 `qlFont` 修饰符，
/// 读 `@AppStorage` 里的缩放系数后乘到基准字号上。
///
/// 用法：把 `.font(.system(size: 13))` 换成 `.qlFont(size: 13)`，
/// 字号即随全局缩放联动。为了不改动 180 多处调用点，
/// 缩放通过 `Theme.fontScale` 提供，各页面读取 `Theme.fontScale` 自行计算——
/// 因此真正的落点在设置页 + App 入口的 `environment`。
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

// MARK: - 便捷修饰符

extension View {
    /// 随全局缩放联动的等宽字体。
    ///
    /// `Text(...).qlFont(size: 12.5, design: .monospaced)`
    func qlFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design? = nil
    ) -> some View {
        font(.system(size: Theme.font(size), weight: weight, design: design))
    }

    /// 随全局缩放联动的系统字体。
    func qlSystemFont(
        _ style: Font.TextStyle,
        weight: Font.Weight = .regular,
        design: Font.Design? = nil
    ) -> some View {
        font(.system(style, design: design).weight(weight))
    }
}
