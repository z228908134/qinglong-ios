import SwiftUI
import UIKit

@main
struct QingLongApp: App {

    @StateObject private var store = PanelStore.shared

    /// 外观模式（跟随系统 / 白天 / 深色）。
    /// 与设置页共用同一个 `@AppStorage` 键，改动后立即生效，不需要重启。
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw = AppearanceMode.system.rawValue

    /// 文字缩放档位。
    ///
    /// 各处字号写成 `Theme.font(基准值)`，实际值 = 基准值 × 该缩放。
    /// 这里读同一个键并写进窗口的 `id`，缩放一变就重建视图树，
    /// 用户在设置页拖动滑杆能立刻看到全 App 字号变化。
    @AppStorage(FontScale.storageKey) private var fontScaleRaw = FontScale.default

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(fontScaleRaw)
                .environmentObject(store)
                .accentColor(Theme.accent)
                .preferredColorScheme(AppearanceMode(rawValue: appearanceRaw)?.colorScheme)
                .onAppear(perform: applyAppearance)
        }
    }

    /// 让导航栏、Tab 栏与页面背景融为一体，避免深色模式下
    /// 顶部/底部出现一截突兀的纯黑条（截图里「大黑框」观感的主要来源之一）。
    private func applyAppearance() {
        UITableView.appearance().backgroundColor = .clear

        let page = Theme.uiPageBackground

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = page
        nav.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = page
        tab.shadowColor = .clear
        UITabBar.appearance().standardAppearance = tab
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = tab
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: PanelStore

    var body: some View {
        Group {
            if store.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .alert(item: $store.alert) { message in
            Alert(
                title: Text(message.title),
                message: Text(message.message),
                dismissButton: .default(Text("知道了"))
            )
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var store: PanelStore

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("概览", systemImage: "square.grid.2x2.fill") }

            CronListView()
                .tabItem { Label("任务", systemImage: "clock.fill") }

            EnvListView()
                .tabItem { Label("变量", systemImage: "key.fill") }

            SubscriptionListView()
                .tabItem { Label("订阅", systemImage: "arrow.triangle.2.circlepath") }

            MoreView()
                .tabItem { Label("更多", systemImage: "ellipsis.circle.fill") }
        }
    }
}
