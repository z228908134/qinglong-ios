import SwiftUI
import UIKit

// MARK: - 筛选胶囊

struct FilterChip: View {
    let title: String
    var count: Int? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                if let count = count {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium))
                        .opacity(0.75)
                }
            }
            .foregroundColor(isSelected ? .white : Theme.secondaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isSelected ? Theme.accent : Theme.fieldBackground)
            )
        }
    }
}

// MARK: - 图标方块

/// 列表行左侧的圆角图标块，统一尺寸让整列视觉对齐。
struct IconTile: View {
    let icon: String
    var tint: Color = Theme.accent
    var size: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.29)
            .fill(tint.opacity(0.14))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundColor(tint)
            )
    }
}

// MARK: - 分组列表行

/// 「更多」页里使用的导航行。
struct MenuRow<Destination: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var badge: String? = nil
    var tint: Color = Theme.accent
    let destination: Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                IconTile(icon: icon, tint: tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15))
                        .foregroundColor(Theme.primaryText)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 11.5))
                            .foregroundColor(Theme.tertiaryText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.secondaryText)
                }
            }
            .padding(.vertical, 5)
        }
    }
}

// MARK: - 进度条

struct ThinProgressBar: View {
    var progress: Double
    var tint: Color = Theme.accent
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fieldBackground)
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, progress)) * geometry.size.width)
            }
        }
        .frame(height: height)
    }
}

// MARK: - 动作按钮（列表内联）

struct InlineActionButton: View {
    let title: String
    let icon: String
    var tint: Color = Theme.accent
    var isBusy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isBusy {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(tint.opacity(0.12)))
        }
        .disabled(isBusy)
    }
}

// MARK: - 长文本查看器

/// 只读文本查看页：日志、脚本源码、依赖安装日志都复用它。
struct TextDetailView: View {
    let title: String
    let subtitle: String?
    let text: String
    var isLoading: Bool = false
    var onRefresh: (() -> Void)? = nil
    var onSave: ((String) -> Void)? = nil
    /// 传入后，导航栏用文字按钮（「编辑」/「保存」）代替铅笔图标。
    /// 小图标太不起眼，用户容易以为页面只能看。
    var editLabel: String? = nil

    @State private var editableText: String = ""
    @State private var isEditing = false
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        ZStack {
            Theme.groupedBackground.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                if let subtitle = subtitle {
                    HStack {
                        Text(subtitle)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundColor(Theme.tertiaryText)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }

                if isLoading {
                    LoadingOverlay(title: "正在加载…")
                    Spacer()
                } else if isEditing {
                    TextEditor(text: $editableText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Theme.primaryText)
                        .padding(8)
                        .background(Theme.cardBackground)
                        .cornerRadius(10)
                        .padding(.horizontal, 14)
                } else {
                    LogTextView(text: text, isPlaceholder: text.isEmpty)
                        .padding(.horizontal, 14)
                }
            }
            .padding(.bottom, 10)
        }
        .navigationBarTitle(title, displayMode: .inline)
        .navigationBarItems(trailing: trailingItems)
        .onAppear {
            if editableText.isEmpty { editableText = text }
        }
    }

    private var trailingItems: some View {
        HStack(spacing: 16) {
            Button(action: copyToPasteboard) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 15))
            }

            // 刷新与编辑现在可以并存：原先是 else-if，只要有保存回调就把刷新挤掉了；
            // 编辑过程中隐藏刷新，避免刷新把未保存的改动冲掉。
            if !isEditing, let onRefresh = onRefresh {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15))
                }
            }

            if onSave != nil {
                Button(action: toggleEditing) {
                    if let editLabel = editLabel {
                        Text(isEditing ? "保存" : editLabel)
                            .font(.system(size: 14, weight: .medium))
                    } else {
                        Image(systemName: isEditing ? "checkmark.circle.fill" : "square.and.pencil")
                            .font(.system(size: 15))
                    }
                }
            }
        }
    }

    private func toggleEditing() {
        if isEditing, let onSave = onSave {
            onSave(editableText)
        }
        isEditing.toggle()
    }

    private func copyToPasteboard() {
        UIPasteboard.general.string = isEditing ? editableText : text
    }
}
