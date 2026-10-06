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
                        if !store.dashboardIssues.isEmpty {
                            diagnosticCard
                        }
                        heroCard
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
                    labeledValue("登录账号", store.connection?.accountName ?? "-")
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

    // MARK: - 诊断提示

    /// 概览接口失败时的提示条。
    ///
    /// 面板把概览数据归在独立的 `dashboard` 权限 scope 下，创建应用时很容易漏勾；
    /// 一旦漏勾，接口返回 403，界面上就只剩一排 0。这里把失败原因直接摆出来，
    /// 并给出可操作的修复路径，避免用户误以为"任务全失败了"。
    private var diagnosticCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.warning)
                    Text(store.dashboardScopeDenied ? "当前应用缺少「面板概览」权限" : "部分概览数据未能加载")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.primaryText)
                    Spacer(minLength: 0)
                }

                if store.dashboardScopeDenied {
                    Text("概览统计、执行趋势、运行实例属于独立的 dashboard 权限，与任务列表的权限是分开授予的。请到面板「系统设置 → 应用设置」编辑当前应用，勾上「面板概览 / dashboard」并保存，然后回到本页刷新即可。")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(store.dashboardIssues, id: \.self) { issue in
                    Text("· \(issue)")
                        .font(.system(size: 11.5))
                        .foregroundColor(Theme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - 今日指标

    /// 面板是否真的返回了今日统计。
    ///
    /// 值为 nil 表示 `/dashboard/overview` 不可用（典型原因是应用未授予
    /// `dashboard` 权限）。此时显示 "0%" 会造成误导——用户会以为任务全部失败，
    /// 实际上只是没有数据。所以这种情况统一显示为未知。
    private var hasStats: Bool { store.overview != nil }

    /// 主视觉卡：品牌绿渐变底 + 成功率圆环 + 今日执行大数字。
    private var heroCard: some View {
        let rateText = hasStats ? (store.overview?.successRate ?? "0") : nil
        let rate = rateText.flatMap { Double($0) }.map { max(0, min(1, $0 / 100)) }

        return HStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.28), lineWidth: 8)
                if let rate = rate {
                    Circle()
                        .trim(from: 0, to: CGFloat(rate))
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.6), value: rate)
                }
                VStack(spacing: 1) {
                    Text(rateText.map { "\($0)%" } ?? "—")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                    Text("成功率")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 5) {
                Text("今日执行")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                Text(hasStats ? "\(store.overview?.todayRuns ?? 0)" : "—")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(hasStats
                        ? "成功 \(store.overview?.todaySuccess ?? 0) · 失败 \(store.overview?.todayFail ?? 0)"
                        : "面板未返回统计数据")
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Theme.heroGradient)
                .shadow(color: Theme.heroBottom.opacity(0.35), radius: 12, x: 0, y: 5)
        )
    }

    private var metricsGrid: some View {
        HStack(spacing: 10) {
            MetricTile(
                title: "定时任务",
                value: "\(store.overview?.total ?? store.crons.count)",
                caption: "启用 \(store.overview?.enabled ?? store.crons.filter { !$0.isDisabledTask }.count) · 禁用 \(store.overview?.disabled ?? store.crons.filter { $0.isDisabledTask }.count)",
                tint: Theme.accent
            )
            MetricTile(
                title: "平均耗时",
                value: hasStats ? durationText(store.overview?.avgTime ?? 0) : "—",
                caption: hasStats ? "今日单次平均" : "面板未返回统计数据",
                tint: Theme.warning
            )
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

    /// 正在运行的任务列表。
    ///
    /// 优先采用 `/dashboard/runtime`（带真实 PID 与精确运行时长）；当该接口不可用时
    /// （例如应用未授予 `dashboard` 权限），退回用任务列表的 `status == running(0)`
    /// 自行推导，并把 `last_running_time` 换算成已运行时长。这样即便概览接口被拒，
    /// 这块信息也不会凭空消失。
    private var runningTasks: [RunningTask] {
        if let runtime = store.runtime, !runtime.running.isEmpty {
            return runtime.running
        }
        let now = Int(Date().timeIntervalSince1970)
        return store.crons
            .filter { !$0.isDisabledTask && $0.runStatus.isActive }
            .map { cron -> RunningTask in
                // last_running_time 为 0 / nil 时不能拿当前时间当起点，
                // 否则会算出「已运行 49 万小时」这种荒唐数字
                let elapsed: Int
                if let stamp = cron.lastRunningTime, stamp > 0 {
                    elapsed = max(0, now - stamp)
                } else {
                    elapsed = 0
                }
                return RunningTask(cron: cron, elapsed: elapsed)
            }
    }

    /// 运行中任务的副标题：有 PID 显示 PID，有时长显示时长，都没有则说明状态。
    private func runningSubtitle(_ task: RunningTask) -> String {
        var parts: [String] = []
        if let pid = task.pid, pid > 0 { parts.append("PID \(pid)") }
        if task.elapsed > 0 { parts.append("已运行 \(task.elapsedText)") }
        return parts.isEmpty ? "运行中" : parts.joined(separator: " · ")
    }

    /// 概览「正在运行」行点击后进入对应的任务详情。
    private func detailCron(for task: RunningTask) -> Cron {
        if let match = store.crons.first(where: { $0.id == task.id }) {
            return match
        }
        // 任务列表还没加载时兜底：只带 id / 名称 / PID，详情页会按 id 拉日志
        var fallback = Cron()
        fallback.id = task.id
        fallback.name = task.name
        fallback.pid = task.pid
        fallback.logPath = task.logPath
        return fallback
    }

    private var runningCard: some View {
        let running = runningTasks

        return SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("正在运行")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.secondaryText)
                    Spacer()
                    Text("\(running.count) 个任务")
                        .font(.system(size: 11.5))
                        .foregroundColor(Theme.tertiaryText)
                }

                if running.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.zzz")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.tertiaryText)
                        Text("当前没有正在运行的任务")
                            .font(.system(size: 12.5))
                            .foregroundColor(Theme.secondaryText)
                    }
                    .padding(.vertical, 6)
                } else {
                    ForEach(running) { task in
                        NavigationLink(destination: CronDetailView(cron: detailCron(for: task))) {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Theme.info)
                                    .frame(width: 7, height: 7)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.name)
                                        .font(.system(size: 13.5, weight: .medium))
                                        .foregroundColor(Theme.primaryText)
                                        .lineLimit(1)
                                    Text(runningSubtitle(task))
                                        .font(.system(size: 11))
                                        .foregroundColor(Theme.tertiaryText)
                                }

                                Spacer(minLength: 6)

                                InlineActionButton(title: "停止", icon: "stop.fill", tint: Theme.danger) {
                                    Task { await store.stopCrons([task.id]) }
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
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
                    .fill(LinearGradient(
                        gradient: Gradient(colors: hasFail
                            ? [Theme.danger, Theme.danger.opacity(0.55)]
                            : [Theme.heroTop, Theme.heroBottom]),
                        startPoint: .top, endPoint: .bottom))
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
