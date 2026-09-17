//
//  QingLongApp.swift
//  应用入口
//

import SwiftUI

@main
struct QingLongApp: App {
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        Group {
            switch session.phase {
            case .restoring:
                SplashView()
            case .loggedOut:
                LoginView()
            case .loggedIn:
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.22), value: session.phase)
        .task {
            await session.restore()
        }
        .overlay(alignment: .top) {
            if let toast = session.toast {
                ToastView(toast: toast)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast.id) {
                        try? await Task.sleep(nanoseconds: 2_600_000_000)
                        if session.toast?.id == toast.id {
                            withAnimation { session.toast = nil }
                        }
                    }
            }
        }
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.accentColor)
                Text("青龙管家")
                    .font(.system(size: 18, weight: .semibold))
                ProgressView()
            }
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { CronListView() }
                .tabItem { Label("任务", systemImage: "list.bullet.rectangle") }
                .tag(0)

            NavigationStack { EnvListView() }
                .tabItem { Label("变量", systemImage: "key.fill") }
                .tag(1)

            NavigationStack { LogFilesView() }
                .tabItem { Label("日志", systemImage: "doc.text") }
                .tag(2)

            NavigationStack { SettingsView() }
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
                .tag(3)
        }
    }
}
