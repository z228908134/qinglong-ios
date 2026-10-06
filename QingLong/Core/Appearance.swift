import SwiftUI

/// 应用外观模式。
///
/// 实现依据：整套主题色（`Theme`）都建立在系统语义色之上
/// （`UIColor.label`、`systemGroupedBackground`、`tertiarySystemFill` 等），
/// 这些颜色本身就会随系统明暗自动切换。因此这里只需要控制 `preferredColorScheme`，
/// 界面就会整体跟随变化，无需为每种模式维护两套配色。
enum AppearanceMode: String, CaseIterable, Identifiable {

    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light:  return "白天"
        case .dark:   return "深色"
        }
    }

    var subtitle: String {
        switch self {
        case .system: return "随 iOS 的深色模式设置自动切换"
        case .light:  return "始终使用浅色界面"
        case .dark:   return "始终使用深色界面"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.fill"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    /// 传给 `preferredColorScheme`。`nil` 表示不做干预，交回系统决定。
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    /// `@AppStorage` 使用的键名，设置页与 App 入口共用。
    static let storageKey = "appearance-mode"
}
