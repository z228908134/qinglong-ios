import SwiftUI

// MARK: - 登录日志

/// 面板登录记录（`GET /api/user/login-log`）。
/// 面板侧的 `timestamp` 是**毫秒**，`status` 是 `success` / `fail` 枚举字符串，
/// 两者都在 `LoginLogEntry` 里做过归一化处理。
struct LoginLogView: View {

    /// 更多页等已有导航栈的场景传 true，直接作为子页推入。
    var inlineTitle: Bool = false

    @EnvironmentObject private var store: PanelStore

    @State private var loaded = false
    @State private var isLoading = false

    var body: some View {
        Group {
            if inlineTitle {
                list
            } else {
                NavigationView { list }
                    .navigationViewStyle(StackNavigationViewStyle())
            }
        }
    }

    private var list: some View {
        ZStack {
            Theme.groupedBackground.edgesIgnoringSafeArea(.all)

            if isLoading && store.loginLogs.isEmpty {
                LoadingOverlay(title: "正在读取登录日志…")
            } else if store.loginLogs.isEmpty {
                EmptyStateView(
                    icon: "clock.arrow.circlepath",
                    title: "没有登录记录",
                    message: "面板版本较低或权限不足时，可能无法使用该功能。"
                )
            } else {
                List {
                    ForEach(store.loginLogs) { entry in
                        row(entry)
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
        }
        .navigationBarTitle("登录日志", displayMode: .inline)
        .onAppear {
            if !loaded {
                loaded = true
                Task { await reload() }
            }
        }
    }

    private func reload() async {
        isLoading = true
        await store.loadLoginLogs()
        isLoading = false
    }

    private func row(_ entry: LoginLogEntry) -> some View {
        HStack(spacing: 12) {
            IconTile(
                icon: iconName(for: entry.platform),
                tint: entry.isSuccess ? Theme.success : Theme.danger,
                size: 32
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.dateText)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(Theme.primaryText)

                Text("\(entry.ip) · \(entry.address.isEmpty ? "未知归属地" : entry.address)")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if !entry.platform.isEmpty {
                    Text(entry.platform)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.tertiaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            statusBadge(entry.isSuccess)
        }
        .padding(.vertical, 6)
    }

    private func statusBadge(_ success: Bool) -> some View {
        Text(success ? "成功" : "失败")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(success ? Theme.success : Theme.danger)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill((success ? Theme.success : Theme.danger).opacity(0.14))
            )
    }

    /// 按 UA / 平台串猜一个图标；猜不出就用通用头像。
    private func iconName(for platform: String) -> String {
        let p = platform.lowercased()
        if p.contains("ios") || p.contains("iphone") { return "iphone" }
        if p.contains("android") { return "smartphone" }
        if p.contains("mac") { return "laptopcomputer" }
        if p.contains("win") { return "desktopcomputer" }
        if p.contains("linux") { return "terminal" }
        if p.contains("docker") { return "shippingbox" }
        return "person.crop.circle"
    }
}
