//
//  Theme.swift
//  状态色、通用小组件。全部用系统语义色，自动适配浅色 / 深色模式。
//

import SwiftUI

// MARK: - 状态展示

extension CronStatus {
    var title: String {
        switch self {
        case .running: return "运行中"
        case .idle: return "空闲"
        case .disabled: return "已禁用"
        case .queued: return "排队中"
        }
    }

    var color: Color {
        switch self {
        case .running: return .green
        case .idle: return .blue
        case .disabled: return .gray
        case .queued: return .orange
        }
    }

    var symbol: String {
        switch self {
        case .running: return "play.circle.fill"
        case .idle: return "clock"
        case .disabled: return "pause.circle.fill"
        case .queued: return "hourglass"
        }
    }
}

extension EnvStatus {
    var title: String { self == .normal ? "已启用" : "已禁用" }
    var color: Color { self == .normal ? .green : .gray }
    var symbol: String { self == .normal ? "checkmark.circle.fill" : "pause.circle.fill" }
}

// MARK: - 小组件

struct StatusPill: View {
    let text: String
    let color: Color
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            }
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.15), in: Capsule())
    }
}

struct Card<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// 详情页里的「标签 + 值」一行
struct InfoRow: View {
    let label: String
    let value: String
    var mono: Bool = false
    var accent: Color?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: mono ? .regular : .medium))
                .fontDesign(mono ? .monospaced : .default)
                .foregroundStyle(accent ?? Color.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                Button("重试", action: retry)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
    }
}

struct ToastView: View {
    let toast: SessionStore.Toast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.isError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isError ? .red : .green)
            Text(toast.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 24)
    }
}

/// 常用小按钮
struct ActionChip: View {
    let title: String
    let symbol: String
    var tint: Color = .accentColor
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(tint.opacity(disabled ? 0.08 : 0.14),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(disabled ? Color.secondary : tint)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}
