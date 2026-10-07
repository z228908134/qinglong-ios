import SwiftUI

// MARK: - 设置字体大小

/// 文字大小设置页。
///
/// 布局参照系统「设置 → 辅助功能 → 显示与文字大小 → 更大字体」：
/// 顶部实时预览列表，中间显示当前档位，底部是 A / 标准 / A 三段式滑杆。
/// 改动即时生效并写入 `@AppStorage`，不需要重启。
struct FontSizeSettingsView: View {

    @AppStorage(FontScale.storageKey) private var scaleRaw = FontScale.default

    /// 未落盘的临时值：拖动过程中用它驱动预览，松手才写入存储。
    @State private var draft: Double = FontScale.default
    @State private var loaded = false

    private var scale: Double { loaded ? FontScale.normalize(draft) : scaleRaw }

    var body: some View {
        List {
            Section {
                previewCard
                    .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            Section {
                currentValueRow
            }

            Section {
                sliderCard
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            }
        }
        .listStyle(GroupedListStyle())
        .navigationTitle("设置字体大小")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            draft = scaleRaw > 0 ? FontScale.normalize(scaleRaw) : FontScale.default
            loaded = true
        }
    }

    // MARK: 预览

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("测试任务")
                    .font(.system(size: Theme.font(15.5), weight: .semibold))
                    .foregroundColor(Theme.primaryText)
                Spacer()
                Text(previewTime)
                    .font(.system(size: Theme.font(11.5)))
                    .foregroundColor(Theme.tertiaryText)
            }

            Text("10 1-23/3 ****")
                .font(.system(size: Theme.font(14.5)))
                .foregroundColor(Theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text("task test/test.js")
                .font(.system(size: Theme.font(13), design: .monospaced))
                .foregroundColor(Theme.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }

    private var previewTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: Date())
    }

    // MARK: 当前档位

    private var currentValueRow: some View {
        HStack {
            Text("当前大小")
                .font(.system(size: 15))
                .foregroundColor(Theme.primaryText)
            Spacer()
            Text(FontScale.title(for: scale))
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Theme.accent)
        }
    }

    // MARK: 滑杆

    private var sliderCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text("A")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.tertiaryText)
                Spacer()
                Text(FontScale.title(for: scale))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.accent)
                Spacer()
                Text("A")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Theme.primaryText)
            }

            // 滑杆走「档位序号」，值域 0...(档数-1)，每档一格
            Slider(
                value: Binding(
                    get: { Double(FontScale.index(for: scale)) },
                    set: { draft = FontScale.steps[Int($0.rounded())] }
                ),
                in: 0...Double(FontScale.steps.count - 1),
                step: 1
            )

            HStack {
                Text("较小")
                Spacer()
                Text("最大")
            }
            .font(.system(size: 11.5))
            .foregroundColor(Theme.tertiaryText)
        }
        .onChange(of: draft) { value in
            scaleRaw = value
        }
    }
}
