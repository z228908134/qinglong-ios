import SwiftUI
import UIKit

/// 全局配色与视觉常量。
///
/// 颜色全部走系统语义色，因此在浅色 / 深色模式下自动适配，
/// 只有品牌主色（青龙绿）是固定值。
enum Theme {
    /// 构造「浅色 / 深色」两套取值的自适应颜色。
    ///
    /// 背景与文字色本来就取自系统语义色，会自动跟随明暗；但品牌色是写死的 RGB，
    /// 若深色模式下沿用浅色那一套，会显得发闷、对比度不足，因此单独各配一套更亮的变体。
    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    static let accent = adaptive(
        light: UIColor(red: 0.09, green: 0.63, blue: 0.44, alpha: 1),
        dark: UIColor(red: 0.22, green: 0.80, blue: 0.58, alpha: 1)
    )
    static let success = adaptive(
        light: UIColor(red: 0.09, green: 0.63, blue: 0.44, alpha: 1),
        dark: UIColor(red: 0.26, green: 0.83, blue: 0.60, alpha: 1)
    )
    static let info = adaptive(
        light: UIColor(red: 0.15, green: 0.49, blue: 0.86, alpha: 1),
        dark: UIColor(red: 0.37, green: 0.65, blue: 1.00, alpha: 1)
    )
    static let warning = adaptive(
        light: UIColor(red: 0.89, green: 0.60, blue: 0.11, alpha: 1),
        dark: UIColor(red: 1.00, green: 0.73, blue: 0.28, alpha: 1)
    )
    static let danger = adaptive(
        light: UIColor(red: 0.84, green: 0.26, blue: 0.24, alpha: 1),
        dark: UIColor(red: 1.00, green: 0.44, blue: 0.40, alpha: 1)
    )
    static let neutral = Color(UIColor.systemGray)

    static let primaryText = Color(UIColor.label)
    static let secondaryText = Color(UIColor.secondaryLabel)
    static let tertiaryText = Color(UIColor.tertiaryLabel)
    static let separator = Color(UIColor.separator)

    /// 页面底色：浅色用微冷灰，深色用带蓝调的深石墨——
    /// 不再直接用系统纯黑分组背景，卡片与底色的层次立刻拉开。
    static let groupedBackground = adaptive(
        light: UIColor(red: 0.949, green: 0.957, blue: 0.969, alpha: 1),
        dark: UIColor(red: 0.063, green: 0.075, blue: 0.094, alpha: 1)
    )
    /// 卡片底色：深色模式抬升为蓝灰面，浅色模式纯白。
    static let cardBackground = adaptive(
        light: UIColor.white,
        dark: UIColor(red: 0.098, green: 0.118, blue: 0.149, alpha: 1)
    )
    /// 卡片描边：极淡的 1px 勾边，让卡片边界在纯色底上更清晰。
    static let cardBorder = adaptive(
        light: UIColor(white: 0, alpha: 0.06),
        dark: UIColor(white: 1, alpha: 0.07)
    )
    /// 主指标卡的投影色。深色模式下用纯黑（不透明黑在深底上会显脏），
    /// 浅色模式下用低透明黑，仅够把卡片从页面上「抬」起来。
    static let cardShadow = adaptive(
        light: UIColor(white: 0, alpha: 0.10),
        dark: UIColor(white: 0, alpha: 0.45)
    )
    static let fieldBackground = Color(UIColor.tertiarySystemFill)

    /// 主视觉渐变（品牌绿 → 深翠绿），用于概览主卡与主按钮。
    static let heroTop = adaptive(
        light: UIColor(red: 0.063, green: 0.725, blue: 0.506, alpha: 1),
        dark: UIColor(red: 0.086, green: 0.796, blue: 0.557, alpha: 1)
    )
    static let heroBottom = adaptive(
        light: UIColor(red: 0.016, green: 0.588, blue: 0.396, alpha: 1),
        dark: UIColor(red: 0.031, green: 0.545, blue: 0.373, alpha: 1)
    )
    static var heroGradient: LinearGradient {
        LinearGradient(gradient: Gradient(colors: [heroTop, heroBottom]),
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 给 UIKit 外观代理用的页面底色（导航栏 / Tab 栏与页面融为一体）。
    static let uiPageBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.063, green: 0.075, blue: 0.094, alpha: 1)
            : UIColor(red: 0.949, green: 0.957, blue: 0.969, alpha: 1)
    }

    static func tone(_ value: StatusTone) -> Color {
        switch value {
        case .success: return success
        case .info: return info
        case .warning: return warning
        case .danger: return danger
        case .muted: return neutral
        }
    }
}

// MARK: - 状态徽章

struct StatusPill: View {
    let title: String
    let tone: StatusTone

    var body: some View {
        Text(title)
            .font(.system(size: Theme.font(11), weight: .semibold))
            .foregroundColor(Theme.tone(tone))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.tone(tone).opacity(0.14)))
    }
}

// MARK: - 空状态

struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: Theme.font(34), weight: .light))
                .foregroundColor(Theme.tertiaryText)
            Text(title)
                .font(.system(size: Theme.font(15), weight: .medium))
                .foregroundColor(Theme.primaryText)
            if let message = message {
                Text(message)
                    .font(.system(size: Theme.font(12.5)))
                    .foregroundColor(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: Theme.font(13), weight: .medium))
                        .foregroundColor(Theme.accent)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

// MARK: - 搜索框

struct SearchField: View {
    @Binding var text: String
    var placeholder: String = "搜索"

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: Theme.font(13)))
                .foregroundColor(Theme.tertiaryText)

            TextField(placeholder, text: $text)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: Theme.font(14)))
                .foregroundColor(Theme.primaryText)
                .autocapitalization(.none)
                .disableAutocorrection(true)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: Theme.font(14)))
                        .foregroundColor(Theme.tertiaryText)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.fieldBackground))
    }
}

// MARK: - 卡片容器

struct SectionCard<Content: View>: View {
    private let title: String?
    private let content: Content
    /// 卡片层级：`true` = 主卡（描边 + 投影，用于概览指标这类重点信息），
    /// `false` = 次级卡（只留底色，不描边不投影）。
    ///
    /// 之前所有卡片都带同样的描边与投影，一屏里权重完全一致、没有视觉重心；
    /// 分出主次后眼睛才知道该看哪一块。
    private let elevated: Bool

    init(
        _ title: String? = nil,
        elevated: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.elevated = elevated
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = title {
                Text(title)
                    .font(.system(size: Theme.font(12), weight: .semibold))
                    .foregroundColor(Theme.secondaryText)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.cardBackground)
                .overlay(
                    Group {
                        if elevated {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Theme.cardBorder, lineWidth: 1)
                        }
                    }
                )
        )
        .compositingGroup()
        .shadow(
            color: elevated ? Theme.cardShadow : Color.clear,
            radius: elevated ? 10 : 0,
            x: 0,
            y: elevated ? 4 : 0
        )
    }
}

// MARK: - 指标块

struct MetricTile: View {
    let title: String
    let value: String
    var caption: String? = nil
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: Theme.font(11.5)))
                    .foregroundColor(Theme.secondaryText)
            }
            Text(value)
                .font(.system(size: Theme.font(22), weight: .bold))
                .foregroundColor(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption = caption {
                Text(caption)
                    .font(.system(size: Theme.font(11)))
                    .foregroundColor(Theme.tertiaryText)
                    .lineLimit(1)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Theme.cardBorder, lineWidth: 1)
                )
        )
    }
}

// MARK: - 键值行

struct InfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = Theme.primaryText
    var monospaced: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: Theme.font(13)))
                .foregroundColor(Theme.secondaryText)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(monospaced
                      ? .system(size: Theme.font(12.5), design: .monospaced)
                      : .system(size: Theme.font(13)))
                .foregroundColor(valueColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 主按钮

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: Theme.font(14), weight: .semibold))
                }
                Text(title)
                    .font(.system(size: Theme.font(15), weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                Group {
                    if isEnabled && !isLoading {
                        RoundedRectangle(cornerRadius: 13)
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [Theme.heroTop, Theme.heroBottom]),
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            .shadow(color: Theme.heroBottom.opacity(0.35), radius: 8, x: 0, y: 3)
                    } else {
                        RoundedRectangle(cornerRadius: 13)
                            .fill(Theme.accent.opacity(0.4))
                    }
                }
            )
        }
        .disabled(!isEnabled || isLoading)
    }
}

// MARK: - 日志文本视图

struct LogTextView: View {
    let text: String
    var isPlaceholder: Bool = false

    var body: some View {
        // 只保留纵向滚动：横向滚动会给 Text 无限宽度，长行不换行，
        // 在手机上表现为日志被屏幕右缘截断（「边框不自适应」的根因）。
        ScrollView(.vertical) {
            Text(text.isEmpty ? "（暂无内容）" : text)
                .font(.system(size: Theme.font(11.5), design: .monospaced))
                .foregroundColor(isPlaceholder ? Theme.secondaryText : Theme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.cardBackground))
    }
}

// MARK: - 加载遮罩

struct LoadingOverlay: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(title)
                .font(.system(size: Theme.font(13)))
                .foregroundColor(Theme.secondaryText)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 工具栏按钮

struct ToolbarIconButton: View {
    let icon: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: Theme.font(16)))
        }
        .disabled(!isEnabled)
    }
}

// MARK: - 提示条

struct BannerView: View {
    let text: String
    var tone: StatusTone = .warning

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: Theme.font(13)))
                .foregroundColor(Theme.tone(tone))
            Text(text)
                .font(.system(size: Theme.font(12)))
                .foregroundColor(Theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.tone(tone).opacity(0.10)))
    }
}
