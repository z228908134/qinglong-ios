import SwiftUI
import UIKit

// MARK: - 面板与账号

struct PanelSettingsView: View {

    @EnvironmentObject private var store: PanelStore

    @State private var showSignOutConfirm = false
    @State private var copiedHint = false

    private var connection: PanelConnection? { store.connection }

    var body: some View {
        ZStack {
            Theme.groupedBackground.edgesIgnoringSafeArea(.all)

            ScrollView {
                VStack(spacing: 12) {
                    SectionCard("连接信息") {
                        VStack(spacing: 9) {
                            InfoRow(label: "面板地址", value: connection?.baseURLString ?? "-", monospaced: true)
                            InfoRow(label: "登录账号", value: connection?.accountName ?? "-")
                            InfoRow(
                                label: "令牌状态",
                                value: connection?.expirationText ?? "-",
                                valueColor: (connection?.isExpired ?? false) ? Theme.danger : Theme.success
                            )
                            if let date = connection?.expirationDate {
                                InfoRow(label: "到期时间", value: date.qlFullText)
                            }
                        }
                    }

                    SectionCard("操作") {
                        VStack(spacing: 0) {
                            actionRow(icon: "safari", title: "在浏览器打开面板", tint: Theme.info) {
                                openInBrowser()
                            }
                            Divider().background(Theme.separator).padding(.leading, 46)
                            actionRow(icon: "doc.on.doc", title: copiedHint ? "地址已复制" : "复制面板地址", tint: Theme.accent) {
                                UIPasteboard.general.string = connection?.baseURLString
                                copiedHint = true
                            }
                            Divider().background(Theme.separator).padding(.leading, 46)
                            actionRow(icon: "arrow.clockwise", title: "重新登录并刷新令牌", tint: Theme.accent) {
                                Task { await store.reSignInAndRefresh() }
                            }
                            Divider().background(Theme.separator).padding(.leading, 46)
                            actionRow(icon: "rectangle.portrait.and.arrow.right", title: "退出登录", tint: Theme.danger) {
                                showSignOutConfirm = true
                            }
                        }
                    }

                    SectionCard("关于") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("青龙面板 · 原生 iOS 客户端")
                                .font(.system(size: Theme.font(13), weight: .medium))
                                .foregroundColor(Theme.primaryText)
                            Text("这是社区实现的原生客户端，需要你已经在服务器 / NAS / Docker 上部署好青龙面板。它使用面板账号密码登录（与网页端同一套凭据），令牌失效时会自动续期。凭据只保存在本机钥匙串，不会上传到任何第三方服务器。")
                                .font(.system(size: Theme.font(11.5)))
                                .foregroundColor(Theme.secondaryText)
                                .lineSpacing(3)
                            Text("凭据与令牌存放在系统钥匙串中。退出登录会同时清除本地保存的凭据。")
                                .font(.system(size: Theme.font(11.5)))
                                .foregroundColor(Theme.tertiaryText)
                                .lineSpacing(3)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .navigationBarTitle("面板与账号", displayMode: .inline)
        .alert(isPresented: $showSignOutConfirm) {
            Alert(
                title: Text("退出登录"),
                message: Text("将清除本机保存的账号密码与访问令牌，下次打开需要重新登录。面板上的数据不受影响。"),
                primaryButton: .destructive(Text("退出")) { store.signOut() },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    private func actionRow(icon: String, title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: Theme.font(14)))
                    .foregroundColor(tint)
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: Theme.font(14)))
                    .foregroundColor(Theme.primaryText)
                Spacer()
            }
            .padding(.vertical, 12)
        }
    }

    private func openInBrowser() {
        guard let url = connection?.baseURL else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}

// MARK: - 面板运行环境

struct SystemInfoView: View {

    @EnvironmentObject private var store: PanelStore

    var body: some View {
        ZStack {
            Theme.groupedBackground.edgesIgnoringSafeArea(.all)

            ScrollView {
                VStack(spacing: 12) {
                    if let system = store.systemStat, system.memTotal > 0 {
                        SectionCard("内存") {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("已用 \(String(format: "%.1f", system.memUsedGB)) GB")
                                        .font(.system(size: Theme.font(13), weight: .medium))
                                        .foregroundColor(Theme.primaryText)
                                    Spacer()
                                    Text("共 \(String(format: "%.1f", system.memTotalGB)) GB")
                                        .font(.system(size: Theme.font(12)))
                                        .foregroundColor(Theme.secondaryText)
                                }
                                ThinProgressBar(progress: (Double(system.memUsagePercent) ?? 0) / 100)
                                Text("占用率 \(system.memUsagePercent)%")
                                    .font(.system(size: Theme.font(11)))
                                    .foregroundColor(Theme.tertiaryText)
                            }
                        }

                        SectionCard("处理器与运行状态") {
                            VStack(spacing: 9) {
                                InfoRow(label: "平台", value: system.platform.isEmpty ? "-" : system.platform)
                                InfoRow(label: "CPU 核心", value: "\(system.cpus) 核")
                                InfoRow(label: "已运行", value: system.uptimeText)
                                InfoRow(label: "Node 堆内存", value: "\(system.heapUsed) MB")
                                InfoRow(
                                    label: "系统负载",
                                    value: system.loadAvg.isEmpty
                                        ? "-"
                                        : system.loadAvg.map { String(format: "%.2f", $0) }.joined(separator: "  /  ")
                                )
                            }
                        }
                    } else {
                        EmptyStateView(
                            icon: "cpu",
                            title: "暂时读不到运行环境数据",
                            message: "部分面板版本未开放该接口，或当前应用未获得 system 模块权限。",
                            actionTitle: "重新读取",
                            action: { Task { await store.loadDashboard() } }
                        )
                    }

                    SectionCard("任务统计") {
                        VStack(spacing: 9) {
                            InfoRow(label: "任务总数", value: "\(store.overview?.total ?? store.crons.count)")
                            InfoRow(label: "启用中", value: "\(store.overview?.enabled ?? 0)")
                            InfoRow(label: "已禁用", value: "\(store.overview?.disabled ?? 0)")
                            InfoRow(label: "今日执行", value: "\(store.overview?.todayRuns ?? 0)")
                            InfoRow(
                                label: "今日成功",
                                value: "\(store.overview?.todaySuccess ?? 0)",
                                valueColor: Theme.success
                            )
                            InfoRow(
                                label: "今日失败",
                                value: "\(store.overview?.todayFail ?? 0)",
                                valueColor: (store.overview?.todayFail ?? 0) > 0 ? Theme.danger : Theme.secondaryText
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .navigationBarTitle("面板运行环境", displayMode: .inline)
        .navigationBarItems(trailing: ToolbarIconButton(icon: "arrow.clockwise") {
            Task { await store.loadDashboard() }
        })
        .onAppear {
            if store.systemStat == nil {
                Task { await store.loadDashboard() }
            }
        }
    }
}
