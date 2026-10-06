import SwiftUI

/// 概览页：面板连接状态、今日执行数据、正在运行的任务、7 日趋势与面板运行环境。
struct DashboardView: View {

    @EnvironmentObject private var store: PanelStore

    var body: some View {
        NavigationView {
            ZStack {
                Theme.groupedBackground.edgesIgnoringSafeArea(.all)

                ScrollView {
                    VStack(spacing: 14) {
                        connectionCard
                        metricsGrid
                        runningCard
                        TrendChartCard(points: store.trend)
                        systemCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }

                if store.isLoading("dashboard") && store.overview == nil {
                    LoadingOverlay(title: "正在读取面板数据…")
                }
            }
            .navigationBarTitle("概览", displayMode: .large)
            .navigationBarItems(
                leading: connectionMenu,
                trailing: ToolbarIconButton(icon: "arrow.clockwise", isEnabled: !store.isLoading("dashboard")) {
                    Task { await store.refreshAll() }
                }
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            if store.overview == nil {
                Task { await store.loadDashboard() }
            }
        }
    }

    // MARK: - 连接状态

    private var connectionMenu: some View {
        Menu {
            Button("刷新全部数据") {
                Task { await store.refreshAll() }
            }
            Button("退出登录", action: store.signOut)
        } label: {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 17))
        }
    }

    private var connectionCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Theme.success.opacity(0.16))
                            .frame(width: 36, height: 36)
                        Circle()
                            .fill(Theme.success)
                            .frame(width: 9, height: 9)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("已连接面板")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.primaryText)
                        Text(store.connection?.baseURLString ?? "-")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundColor(Theme.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                Divider()

                HStack(spacing: 18) {
                    labeledValue("应用 ID", store.connection?.clientIDMasked ?? "-")
                    labeledValue("令牌状态", store.connection?.expirationText ?? "-")
                }

                if let system = store.systemStat, !system.platform.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 10))
                        Text("面板运行于 \(system.platform) · 已运行 \(system.uptimeText)")
                            .font(.system(size: 11.5))
                    }
                    .foregroundColor(Theme.tertiaryText)
                }
            }
        }
    }

    private func labeledValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(Theme.tertiaryText)
            Text(value)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(Theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 今日指标

    private var metricsGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                MetricTile(
                    title: "定时任务",
                    value: "\(store.overview?.total ?? store.crons.count)",
                    caption: "启用 \(store.overview?.enabled ?? store.crons.filter { !$0.isDisabledTask }.count) · 禁用 \(store.overview?.disabled ?? store.crons.filter { $0.isDisabledTask }.count)",
                    tint: Theme.accent
                )
                MetricTile(
                    title: "今日执行",
                    value: "\(store.overview?.todayRuns ?? 0)",
                    caption: "成功 \(store.overview?.todaySuccess ?? 0) · 失败 \(store.overview?.todayFail ?? 0)",
                    tint: Theme.info
                )
            }
            HStack(spacing: 10) {
                MetricTile(
                    title: "今日成功率",
                    value: "\(store.overview?.successRate ?? "0")%",
                    caption: "基于今日执行次数",
                    tint: Theme.success
                )
                MetricTile(
                    title: "平均耗时",
                    value: durationText(store.overview?.avgTime ?? 0),
                    caption: "今日单次平均",
                    tint: Theme.warning
                )
            }
        }
    }

    private func durationText(_ milliseconds: Int) -> String {
        if milliseconds <= 0 { return "—" }
        if milliseconds < 1000 { return "\(milliseconds) ms" }
        let seconds = Double(milliseconds) / 1000
        if seconds < 60 { return String(format: "%.1f s", seconds) }
        return String(format: "%.1f min", seconds / 60)
    }

    // MARK: - 正在运行

    private var runningCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("正在运行")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.secondaryText)
                    Spacer()
                    let active = store.runtime?.running.count ?? store.crons.filter { $0.runStatus.isActive }.count
                    Text("\(active) 个任务")
                        .font(.system(size: 11.5))
                        .foregroundColor(Theme.tertiaryText)
                }

                if let runtime = store.runtime, !runtime.running.isEmpty {
                    ForEach(runtime.running) { task in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Theme.info)
                                .frame(width: 7, height: 7)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.name)
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundColor(Theme.primaryText)
                                    .lineLimit(1)
                                Text("PID \(task.pid ?? 0) · 已运行 \(task.elapsedText)")
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.tertiaryText)
                            }

                            Spacer(minLength: 6)

                            InlineActionButton(title: "停止", icon: "stop.fill", tint: Theme.danger) {
                                Task { await store.stopCrons([task.id]) }
                            }
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.zzz")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.tertiaryText)
                        Text("当前没有正在运行的任务")
                            .font(.system(size: 12.5))
                            .foregroundColor(Theme.secondaryText)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: - 面板运行环境

    private var systemCard: some View {
        SectionCard("面板运行环境") {
            if let system = store.systemStat, system.memTotal > 0 {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("内存占用")
                                .font(.system(size: 12.5))
                                .foregroundColor(Theme.secondaryText)
                            Spacer()
                            Text(String(format: "%.1f / %.1f GB", system.memUsedGB, system.memTotalGB))
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(Theme.primaryText)
                        }
                        ThinProgressBar(progress: (Double(system.memUsagePercent) ?? 0) / 100)
                    }

                    Divider()

                    HStack(spacing: 0) {
                        statColumn("处理器", "\(system.cpus) 核")
                        statColumn("平台", system.platform.isEmpty ? "-" : system.platform)
                        statColumn("Node 堆", "\(system.heapUsed) MB")
                        statColumn("负载", system.loadAvg.first.map { String(format: "%.2f", $0) } ?? "-")
                    }
                }
            } else {
                Text("面板未返回运行环境数据，可稍后下拉重试。")
                    .font(.system(size: 12.5))
                    .foregroundColor(Theme.secondaryText)
            }
        }
    }

    private func statColumn(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: 10.5))
                .foregroundColor(Theme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 趋势图

struct TrendChartCard: View {
    let points: [DashboardTrendPoint]

    private var maxValue: Int {
        max(points.map { $0.total }.max() ?? 1, 1)
    }

    var body: some View {
        SectionCard("近 7 日执行趋势") {
            if points.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.tertiaryText)
                    Text("暂无统计数据，面板需要累积执行记录后才会展示")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.secondaryText)
                }
                .padding(.vertical, 6)
            } else {
                VStack(spacing: 10) {
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(points) { point in
                            bar(for: point)
                        }
                    }
                    .frame(height: 96)

                    HStack(spacing: 14) {
                        legend(color: Theme.accent, text: "成功")
                        legend(color: Theme.danger, text: "失败")
                    }
                }
            }
        }
    }

    private func bar(for point: DashboardTrendPoint) -> some View {
        let ratio = CGFloat(point.total) / CGFloat(maxValue)
        let height = max(point.total > 0 ? 6 : 3, ratio * 72)
        let hasFail = point.fail > 0

        return VStack(spacing: 5) {
            Text(point.total > 0 ? "\(point.total)" : "")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(Theme.tertiaryText)

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.fieldBackground)
                    .frame(height: 72)
                RoundedRectangle(cornerRadius: 4)
                    .fill(hasFail ? Theme.danger.opacity(0.85) : Theme.accent)
                    .frame(height: height)
            }

            Text(point.date)
                .font(.system(size: 9))
                .foregroundColor(Theme.tertiaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 9, height: 9)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(Theme.tertiaryText)
        }
    }
}
