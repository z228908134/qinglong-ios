import SwiftUI
import UIKit

@main
struct QingLongApp: App {

    @StateObject private var store = PanelStore.shared

    /// 外观模式（跟随系统 / 白天 / 深色）。
    /// 与设置页共用同一个 `@AppStorage` 键，改动后立即生效，不需要重启。
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw = AppearanceMode.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .accentColor(Theme.accent)
                .preferredColorScheme(AppearanceMode(rawValue: appearanceRaw)?.colorScheme)
                .onAppear(perform: applyAppearance)
        }
    }

    /// 让列表与卡片使用 iOS 原生分组背景，避免默认白底在深色模式下刺眼。
    private func applyAppearance() {
        UITableView.appearance().backgroundColor = .clear
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
