import SwiftUI

// MARK: - 任务列表

struct CronListView: View {

    @EnvironmentObject private var store: PanelStore

    @State private var filter: CronFilter = .all
    @State private var showCreate = false
    @State private var pendingDelete: Cron?
    @State private var searchWorkItem: DispatchWorkItem?

    enum CronFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case active = "运行中"
        case disabled = "已禁用"
        case subscribed = "已订阅"

        var id: String { rawValue }
    }

    private var filtered: [Cron] {
        let base: [Cron]
        switch filter {
        case .all:
            base = store.crons
        case .active:
            base = store.crons.filter { $0.runStatus.isActive }
        case .disabled:
            base = store.crons.filter { $0.isDisabledTask }
        case .subscribed:
            base = store.crons.filter { $0.isSubscribed }
        }
        return base.sorted { lhs, rhs in
            if lhs.isPinnedTask != rhs.isPinnedTask { return lhs.isPinnedTask }
            return (lhs.lastExecutionTime ?? 0) > (rhs.lastExecutionTime ?? 0)
        }
    }

    private func count(for filter: CronFilter) -> Int {
        switch filter {
        case .all: return store.crons.count
        case .active: return store.crons.filter { $0.runStatus.isActive }.count
        case .disabled: return store.crons.filter { $0.isDisabledTask }.count
        case .subscribed: return store.crons.filter { $0.isSubscribed }.count
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Theme.groupedBackground.edgesIgnoringSafeArea(.all)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        SearchField(text: $store.cronSearch, placeholder: "搜索任务名称或命令")
                            .padding(.horizontal, 16)

                        filterRow

                        if store.isLoading("crons") && store.crons.isEmpty {
                            LoadingOverlay(title: "正在读取任务列表…")
                        } else if filtered.isEmpty {
                            EmptyStateView(
                                icon: "clock",
                                title: store.crons.isEmpty ? "还没有定时任务" : "没有符合条件的任务",
                                message: store.crons.isEmpty
                                    ? "点击右上角「新增」创建第一个定时任务，或先在面板的订阅管理里拉取脚本仓库。"
                                    : "换个筛选条件或搜索词试试。"
                            )
                        } else {
                            cardList
                        }
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
            }
            .navigationBarTitle("定时任务", displayMode: .large)
            .navigationBarItems(
                leading: ToolbarIconButton(icon: "arrow.clockwise", isEnabled: !store.isLoading("crons")) {
                    Task { await store.loadCrons() }
                },
                trailing: Button(action: { showCreate = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: Theme.font(17), weight: .medium))
                }
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showCreate) {
            CronEditView(cron: nil)
                .environmentObject(store)
        }
        .alert(item: $pendingDelete) { cron in
            Alert(
                title: Text("删除任务"),
                message: Text("确定要删除「\(cron.displayName)」吗？该操作不可撤销。"),
                primaryButton: .destructive(Text("删除")) {
                    Task { await store.deleteCrons([cron.id]) }
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .onAppear {
            if store.crons.isEmpty {
                Task { await store.loadCrons() }
            }
        }
        .onChange(of: store.cronSearch) { _ in
            scheduleSearch()
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CronFilter.allCases) { item in
                    FilterChip(
                        title: item.rawValue,
                        count: count(for: item),
                        isSelected: filter == item
                    ) {
                        filter = item
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
    }

    private var cardList: some View {
        VStack(spacing: 0) {
            let items = filtered
            ForEach(items.indices, id: \.self) { index in
                NavigationLink(destination: CronDetailView(cron: items[index])) {
                    CronRowView(cron: items[index])
                }
                .buttonStyle(PlainButtonStyle())

                if index < items.count - 1 {
                    Divider()
                        .background(Theme.separator)
                        .padding(.leading, 56)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.cardBorder, lineWidth: 1)
                )
        )
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 3)
        .padding(.horizontal, 16)
    }

    private func scheduleSearch() {
        searchWorkItem?.cancel()
        let item = DispatchWorkItem {
            Task { await store.loadCrons() }
        }
        searchWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: item)
    }
}

// MARK: - 任务行

struct CronRowView: View {
    let cron: Cron
    @EnvironmentObject private var store: PanelStore

    private var badge: (text: String, color: Color) {
        let command = cron.command.lowercased()
        if command.contains(".py") { return ("PY", Theme.info) }
        if command.contains(".ts") { return ("TS", Theme.warning) }
        if command.contains(".js") { return ("JS", Theme.accent) }
        if command.contains(".sh") { return ("SH", Theme.warning) }
        return ("--", Theme.neutral)
    }

    var body: some View {
        HStack(spacing: 10) {
            // 语言角标块：只显示 PY/JS/TS/SH 字样。
            // 原先在 terminal 图标上再叠文字，两个字形会互相压住，观感脏。
            RoundedRectangle(cornerRadius: 9)
                .fill(badge.color.opacity(0.15))
                .frame(width: 32, height: 32)
                .overlay(
                    Text(badge.text)
                        .font(.system(size: Theme.font(10.5), weight: .bold))
                        .foregroundColor(badge.color)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if cron.isPinnedTask {
                        Image(systemName: "pin.fill")
                            .font(.system(size: Theme.font(9)))
                            .foregroundColor(Theme.warning)
                    }
                    Text(cron.displayName)
                        .font(.system(size: Theme.font(14), weight: .medium))
                        .foregroundColor(cron.isDisabledTask ? Theme.secondaryText : Theme.primaryText)
                        .lineLimit(1)
                }

                Text(cron.command)
                    .font(.system(size: Theme.font(11), design: .monospaced))
                    .foregroundColor(Theme.tertiaryText)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(cron.lastRunText)
                    Text("·")
                    Text(cron.schedule ?? "未设置")
                        .lineLimit(1)
                }
                .font(.system(size: Theme.font(11)))
                .foregroundColor(Theme.tertiaryText)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 6) {
                StatusPill(title: cron.isDisabledTask ? "已禁用" : cron.runStatus.title,
                           tone: cron.isDisabledTask ? .muted : cron.runStatus.tone)

                if cron.runStatus.isActive {
                    InlineActionButton(title: "停止", icon: "stop.fill", tint: Theme.danger) {
                        Task { await store.stopCrons([cron.id]) }
                    }
                } else if !cron.isDisabledTask {
                    InlineActionButton(title: "运行", icon: "play.fill", tint: Theme.accent) {
                        Task { await store.runCrons([cron.id]) }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .contextMenu {
            if cron.runStatus.isActive {
                Button { Task { await store.stopCrons([cron.id]) } } label: {
                    Label("停止运行", systemImage: "stop.fill")
                }
            } else {
                Button { Task { await store.runCrons([cron.id]) } } label: {
                    Label("立即运行", systemImage: "play.fill")
                }
            }

            if cron.isDisabledTask {
                Button { Task { await store.enableCrons([cron.id]) } } label: {
                    Label("启用任务", systemImage: "checkmark.circle")
                }
            } else {
                Button { Task { await store.disableCrons([cron.id]) } } label: {
                    Label("禁用任务", systemImage: "pause.circle")
                }
            }

            if cron.isPinnedTask {
                Button { Task { await store.pinCrons([cron.id], pinned: false) } } label: {
                    Label("取消置顶", systemImage: "pin.slash")
                }
            } else {
                Button { Task { await store.pinCrons([cron.id], pinned: true) } } label: {
                    Label("置顶任务", systemImage: "pin")
                }
            }
        }
    }
}

// MARK: - 任务详情

struct CronDetailView: View {

    let cron: Cron

    @EnvironmentObject private var store: PanelStore
    @Environment(\.presentationMode) private var presentationMode

    @State private var showEdit = false
    @State private var showDeleteConfirm = false

    // 内嵌运行日志
    @State private var logText = ""
    @State private var logLoading = true
    @State private var logAutoRefresh = true
    @State private var logExpanded = false
    @State private var logPollTask: Task<Void, Never>?

    private var live: Cron {
        store.crons.first(where: { $0.id == cron.id }) ?? cron
    }

    var body: some View {
        ZStack {
            Theme.groupedBackground.edgesIgnoringSafeArea(.all)

            ScrollView {
                VStack(spacing: 12) {
                    headerCard
                    actionCard
                    scriptCard
                    logHistoryCard
                    logCard
                    if live.isSubscribed {
                        subscriptionCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
        }
        .navigationBarTitle("任务详情", displayMode: .inline)
        .navigationBarItems(trailing: Button("编辑") { showEdit = true })
        .onAppear {
            Task { await reloadLog() }
            Task { await loadLogFiles() }
            startLogPolling()
        }
        .onDisappear {
            logPollTask?.cancel()
            logPollTask = nil
        }
        .sheet(isPresented: $showEdit) {
            CronEditView(cron: live).environmentObject(store)
        }
        .alert(isPresented: $showDeleteConfirm) {
            Alert(
                title: Text("删除任务"),
                message: Text("确定要删除「\(live.displayName)」吗？该操作不可撤销。"),
                primaryButton: .destructive(Text("删除")) {
                    Task {
                        await store.deleteCrons([live.id])
                        presentationMode.wrappedValue.dismiss()
                    }
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    // MARK: - 内嵌运行日志

    /// 详情页内嵌的运行日志框。
    ///
    /// 刻意做成「固定高度 + 框内滚动」：日志动辄上千行，直接铺开会把整页撑爆，
    /// 小屏手机上尤其糟糕。具体做法：
    /// - 宽度跟随屏幕自适应（`maxWidth: .infinity`），不写死宽度；
    /// - 高度固定 148pt，内容超出在框内纵向滚动，页面本身长度不受日志影响；
    /// - 点「展开」临时加高到 340pt，便于看更多上下文；
    /// - 送入渲染的文本只取尾部若干行，避免超长文本拖慢滚动。
    private var logCard: some View {
        let boxHeight: CGFloat = logExpanded ? 340 : 148

        return SectionCard("运行日志") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Toggle(isOn: $logAutoRefresh) {
                        Text("自动刷新")
                            .font(.system(size: Theme.font(12.5)))
                            .foregroundColor(Theme.secondaryText)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Theme.accent))

                    Spacer(minLength: 0)

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) { logExpanded.toggle() }
                    }) {
                        Text(logExpanded ? "收起" : "展开")
                            .font(.system(size: Theme.font(12)))
                            .foregroundColor(Theme.accent)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: { Task { await reloadLog() } }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: Theme.font(12)))
                            .foregroundColor(Theme.accent)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                logBody(boxHeight: boxHeight)

                HStack(spacing: 0) {
                    Text(logSummary)
                        .font(.system(size: Theme.font(11)))
                        .foregroundColor(Theme.tertiaryText)

                    Spacer(minLength: 0)

                    NavigationLink(destination: CronLogView(cron: live)) {
                        HStack(spacing: 4) {
                            Text("完整日志")
                                .font(.system(size: Theme.font(12), weight: .medium))
                            Image(systemName: "chevron.right")
                                .font(.system(size: Theme.font(10)))
                        }
                        .foregroundColor(Theme.accent)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func logBody(boxHeight: CGFloat) -> some View {
        if logLoading && logText.isEmpty {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.75)
                Text("正在读取日志…")
                    .font(.system(size: Theme.font(12)))
                    .foregroundColor(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: boxHeight)
        } else if logText.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: Theme.font(16)))
                    .foregroundColor(Theme.tertiaryText)
                Text("暂无日志输出")
                    .font(.system(size: Theme.font(12)))
                    .foregroundColor(Theme.secondaryText)
                Text("任务执行后会自动显示在这里")
                    .font(.system(size: Theme.font(11)))
                    .foregroundColor(Theme.tertiaryText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: boxHeight)
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                Text(displayedLogText)
                    .font(.system(size: Theme.font(10.5), design: .monospaced))
                    .foregroundColor(Theme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            .frame(height: boxHeight)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.fieldBackground))
        }
    }

    /// 送入渲染的日志内容。
    ///
    /// 日志可能有上万行，全量交给 `Text` 会明显拖慢滚动，因此只保留尾部若干行；
    /// 需要看全部可以进「完整日志」页。
    private var displayedLogText: String {
        let lines = logText.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > Self.logTailLineLimit else { return logText }
        return "…（仅显示最后 \(Self.logTailLineLimit) 行）\n"
            + lines.suffix(Self.logTailLineLimit).joined(separator: "\n")
    }

    private var logSummary: String {
        guard !logText.isEmpty else { return "" }
        let count = logText.split(separator: "\n", omittingEmptySubsequences: false).count
        return "共 \(count) 行"
    }

    private func startLogPolling() {
        logPollTask?.cancel()
        logPollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { break }
                guard logAutoRefresh else { continue }
                await reloadLog(showSpinner: false)
            }
        }
    }

    private func reloadLog(showSpinner: Bool = true) async {
        if showSpinner && logText.isEmpty { logLoading = true }
        logText = await store.cronLog(id: cron.id, tail: true)
        logLoading = false
    }

    private static let logTailLineLimit = 200

    /// 运行时长格式化。
    /// 面板的 `last_running_time` 是毫秒数，不能当时间戳格式化成日期
    /// （否则会显示成 1970-01-01 08:00:10 这种 epoch 起点时间）。
    static func durationText(_ ms: Int) -> String {
        if ms < 1000 { return "\(ms) 毫秒" }
        let sec = Double(ms) / 1000
        if sec < 60 { return String(format: "%.1f 秒", sec) }
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        if m < 60 { return "\(m) 分 \(s) 秒" }
        return "\(m / 60) 小时 \(m % 60) 分"
    }

    private var headerCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    StatusPill(
                        title: live.isDisabledTask ? "已禁用" : live.runStatus.title,
                        tone: live.isDisabledTask ? .muted : live.runStatus.tone
                    )
                    if live.isPinnedTask {
                        StatusPill(title: "已置顶", tone: .warning)
                    }
                    if live.isSubscribed {
                        StatusPill(title: "来自订阅", tone: .info)
                    }
                    Spacer(minLength: 0)
                }

                Text(live.displayName)
                    .font(.system(size: Theme.font(17), weight: .semibold))
                    .foregroundColor(Theme.primaryText)

                Text(live.command)
                    .font(.system(size: Theme.font(12), design: .monospaced))
                    .foregroundColor(Theme.secondaryText)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.fieldBackground))
            }
        }
    }

    private var actionCard: some View {
        SectionCard("操作") {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    if live.runStatus.isActive {
                        actionButton("停止", "stop.fill", Theme.danger) {
                            Task { await store.stopCrons([live.id]) }
                        }
                    } else {
                        actionButton("立即运行", "play.fill", Theme.accent) {
                            Task { await store.runCrons([live.id]) }
                        }
                    }

                    if live.isDisabledTask {
                        actionButton("启用", "checkmark.circle.fill", Theme.success) {
                            Task { await store.enableCrons([live.id]) }
                        }
                    } else {
                        actionButton("禁用", "pause.circle.fill", Theme.warning) {
                            Task { await store.disableCrons([live.id]) }
                        }
                    }
                }

                HStack(spacing: 10) {
                    actionButton(live.isPinnedTask ? "取消置顶" : "置顶", "pin.fill", Theme.info) {
                        Task { await store.pinCrons([live.id], pinned: !live.isPinnedTask) }
                    }
                    actionButton("删除", "trash.fill", Theme.danger) {
                        showDeleteConfirm = true
                    }
                }

                NavigationLink(destination: CronLogView(cron: live)) {
                    HStack {
                        Image(systemName: "doc.plaintext")
                            .font(.system(size: Theme.font(13)))
                        Text("查看运行日志")
                            .font(.system(size: Theme.font(14), weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: Theme.font(12)))
                    }
                    .foregroundColor(Theme.accent)
                    .padding(.vertical, 11)
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.accent.opacity(0.10)))
                }
            }
        }
    }

    private func actionButton(_ title: String, _ icon: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: Theme.font(12), weight: .semibold))
                Text(title)
                    .font(.system(size: Theme.font(13), weight: .medium))
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 9).fill(tint.opacity(0.12)))
        }
    }

    // MARK: - 脚本 / 日志历史

    @State private var logFiles: [String] = []
    @State private var logFilesLoading = false

    /// 从命令里提取脚本相对路径：`task xxx/yyy.js` → `xxx/yyy.js`。
    private var scriptPath: String? {
        let cmd = live.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cmd.hasPrefix("task ") else { return nil }
        let rest = cmd.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : rest
    }

    private func loadLogFiles() async {
        logFilesLoading = true
        // 日志目录树可能很大（单任务 800+ 文件），放到后台线程解析，
        // 否则进详情页会卡住主线程几秒。目录名直接取自 log_path，面板自己写的最准。
        let id = cron.id
        let dir = live.latestLogDir
        let store = self.store
        let names = await Task.detached(priority: .utility) {
            await store.cronLogFileNames(id: id, logDir: dir)
        }.value
        logFiles = names
        logFilesLoading = false
    }

    private var scriptCard: some View {
        SectionCard("脚本") {
            if let path = scriptPath {
                let dir = path.contains("/")
                    ? String(path[..<path.range(of: "/", options: .backwards)!.lowerBound])
                    : ""
                let name = (path as NSString).lastPathComponent
                let node = FileNode(
                    id: "f:" + path,
                    title: name,
                    path: path,
                    parent: dir,
                    isDirectory: false,
                    children: []
                )
                    NavigationLink(destination: ScriptEditorView(path: dir, node: node)) {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: Theme.font(16)))
                                .foregroundColor(Theme.accent)
                            Text(path)
                                .font(.system(size: Theme.font(14), design: .monospaced))
                                .foregroundColor(Theme.info)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: Theme.font(12), weight: .semibold))
                                .foregroundColor(Theme.tertiaryText)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
            } else {
                Text("该任务的命令不包含脚本文件（如 task xxx.js），无法直接跳转编辑。")
                    .font(.system(size: Theme.font(12.5)))
                    .foregroundColor(Theme.secondaryText)
            }
        }
    }

    private var logHistoryCard: some View {
        SectionCard("日志") {
            VStack(alignment: .leading, spacing: 0) {
                historyRow(
                    title: "最新日志",
                    // 直接用 cron 自带的 log_path，进详情页立即可见，不等任何请求
                    value: live.latestLogName ?? "暂无日志",
                    destination: AnyView(CronLogView(cron: live))
                )
                Divider()
                    .background(Theme.separator)
                if logFilesLoading {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        Text("正在统计历史日志…")
                            .font(.system(size: Theme.font(12.5)))
                            .foregroundColor(Theme.secondaryText)
                        Spacer()
                    }
                    .padding(.vertical, 11)
                } else {
                    historyRow(
                        title: "日志历史",
                        value: logFiles.isEmpty ? "—" : "\(logFiles.count) 个文件",
                        destination: AnyView(CronLogHistoryView(cron: live, files: logFiles))
                    )
                }
            }
        }
    }

    private func historyRow(title: String, value: String, destination: AnyView) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: Theme.font(15), weight: .medium))
                    .foregroundColor(Theme.primaryText)
                Spacer(minLength: 8)
                Text(value)
                    .font(.system(size: Theme.font(15), weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.info)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .truncationMode(.middle)
                Image(systemName: "chevron.right")
                    .font(.system(size: Theme.font(12), weight: .semibold))
                    .foregroundColor(Theme.tertiaryText)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var detailCard: some View {
        SectionCard("任务信息") {
            VStack(spacing: 9) {
                InfoRow(label: "任务 ID", value: "\(live.id)", monospaced: true)
                InfoRow(label: "定时规则", value: live.schedule ?? "未设置", monospaced: true)
                InfoRow(label: "上次执行", value: live.lastRunText)

                if let running = live.lastRunningTime, running > 0 {
                    InfoRow(
                        label: "运行时长",
                        value: Self.durationText(running)
                    )
                }

                InfoRow(label: "日志名称", value: live.logName?.isEmpty == false ? live.logName! : "跟随任务名")
                InfoRow(label: "工作目录", value: live.workDir?.isEmpty == false ? live.workDir! : "默认", monospaced: true)
                InfoRow(label: "多实例", value: (live.allowMultipleInstances ?? 0) == 1 ? "允许" : "不允许")

                if !live.labels.isEmpty {
                    InfoRow(label: "标签", value: live.labels.joined(separator: "、"))
                }
                if let before = live.taskBefore, !before.isEmpty {
                    InfoRow(label: "前置命令", value: before, monospaced: true)
                }
                if let after = live.taskAfter, !after.isEmpty {
                    InfoRow(label: "后置命令", value: after, monospaced: true)
                }
            }
        }
    }

    private var subscriptionCard: some View {
        SectionCard("来源订阅") {
            HStack(spacing: 8) {
                IconTile(icon: "arrow.triangle.2.circlepath", tint: Theme.info, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("该任务由订阅自动创建")
                        .font(.system(size: Theme.font(13), weight: .medium))
                        .foregroundColor(Theme.primaryText)
                    Text("在面板上删除订阅时，此任务可能会一并移除")
                        .font(.system(size: Theme.font(11)))
                        .foregroundColor(Theme.tertiaryText)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - 任务日志

struct CronLogView: View {

    let cron: Cron

    @EnvironmentObject private var store: PanelStore
    @State private var text = ""
    @State private var isLoading = true
    @State private var autoRefresh = true
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Theme.groupedBackground.edgesIgnoringSafeArea(.all)

            VStack(spacing: 8) {
                HStack {
                    Toggle(isOn: $autoRefresh) {
                        Text("每 5 秒自动刷新")
                            .font(.system(size: Theme.font(13)))
                            .foregroundColor(Theme.secondaryText)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Theme.accent))
                }
                .padding(.horizontal, 16)

                TextDetailView(
                    title: cron.displayName,
                    subtitle: cron.command,
                    text: text,
                    isLoading: isLoading,
                    onRefresh: { Task { await reload() } },
                    onSave: nil
                )
            }
        }
        .onAppear {
            Task { await reload() }
            startPolling()
        }
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { break }
                guard autoRefresh else { continue }
                await reload(showSpinner: false)
            }
        }
    }

    private func reload(showSpinner: Bool = true) async {
        if showSpinner { isLoading = true }
        text = await store.cronLog(id: cron.id, tail: true)
        isLoading = false
    }
}

// MARK: - 新建 / 编辑任务

struct CronEditView: View {

    let cron: Cron?

    @EnvironmentObject private var store: PanelStore
    @Environment(\.presentationMode) private var presentationMode

    @State private var name = ""
    @State private var command = ""
    @State private var schedule = ""
    @State private var labels = ""
    @State private var logName = ""
    @State private var workDir = ""
    @State private var allowMultiple = false
    @State private var isSaving = false

    private var isNew: Bool { cron == nil }

    private struct SchedulePreset: Identifiable {
        let id = UUID()
        let title: String
        let value: String
    }

    private let schedulePresets: [SchedulePreset] = [
        SchedulePreset(title: "每小时", value: "0 0 * * * *"),
        SchedulePreset(title: "每天 8 点", value: "0 0 8 * * *"),
        SchedulePreset(title: "每天 0 点", value: "0 0 0 * * *"),
        SchedulePreset(title: "每 30 分钟", value: "0 */30 * * * *"),
        SchedulePreset(title: "每周一 9 点", value: "0 0 9 * * 1")
    ]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基本信息")) {
                    TextField("任务名称（可留空）", text: $name)
                    TextField("执行命令，例如 task jd_sign.js", text: $command)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("定时规则，例如 0 0 8 * * *", text: $schedule)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .font(.system(size: Theme.font(15), design: .monospaced))
                }

                Section(header: Text("常用定时规则"), footer: Text("支持 5 段或 6 段 cron 表达式，也支持 @once、@boot 等写法。")) {
                    ForEach(schedulePresets) { preset in
                        Button(action: { schedule = preset.value }) {
                            HStack {
                                Text(preset.title)
                                    .foregroundColor(Theme.primaryText)
                                Spacer()
                                Text(preset.value)
                                    .font(.system(size: Theme.font(12), design: .monospaced))
                                    .foregroundColor(Theme.tertiaryText)
                            }
                        }
                    }
                }

                Section(header: Text("高级选项")) {
                    TextField("标签，用英文逗号分隔", text: $labels)
                    TextField("日志名称（可留空）", text: $logName)
                    TextField("工作目录（可留空）", text: $workDir)
                    Toggle("允许多实例同时运行", isOn: $allowMultiple)
                }
            }
            .navigationBarTitle(isNew ? "新建任务" : "编辑任务", displayMode: .inline)
            .navigationBarItems(
                leading: Button("取消") { presentationMode.wrappedValue.dismiss() },
                trailing: Button(action: save) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("保存").bold()
                    }
                }
                .disabled(isSaving || command.isEmpty || schedule.isEmpty)
            )
            .onAppear(perform: fillFields)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func fillFields() {
        guard let cron = cron else { return }
        name = cron.name ?? ""
        command = cron.command
        schedule = cron.schedule ?? ""
        labels = cron.labels.joined(separator: ",")
        logName = cron.logName ?? ""
        workDir = cron.workDir ?? ""
        allowMultiple = (cron.allowMultipleInstances ?? 0) == 1
    }

    private func save() {
        let parsedLabels = labels
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let payload = CronPayload(
            id: cron?.id,
            name: name,
            command: command.trimmingCharacters(in: .whitespacesAndNewlines),
            schedule: schedule.trimmingCharacters(in: .whitespacesAndNewlines),
            labels: parsedLabels.isEmpty ? nil : parsedLabels,
            subId: cron?.subId,
            taskBefore: cron?.taskBefore,
            taskAfter: cron?.taskAfter,
            logName: logName,
            workDir: workDir,
            allowMultipleInstances: allowMultiple ? 1 : 0
        )

        isSaving = true
        Task {
            let ok = await store.saveCron(payload, isNew: isNew)
            isSaving = false
            if ok { presentationMode.wrappedValue.dismiss() }
        }
    }
}
