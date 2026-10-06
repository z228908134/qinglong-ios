import SwiftUI

// MARK: - 更多

struct MoreView: View {

    @EnvironmentObject private var store: PanelStore

    /// 与 App 入口共用同一个键，改动即时生效
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw = AppearanceMode.system.rawValue

    var body: some View {
        NavigationView {
            List {
                Section(
                    header: Text("外观"),
                    footer: Text("品牌色已为深色模式单独适配，切换后立即生效，不需要重启。")
                ) {
                    Picker("主题", selection: $appearanceRaw) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }

                Section(header: Text("面板管理")) {
                    MenuRow(
                        icon: "cube.box.fill",
                        title: "依赖管理",
                        subtitle: "安装 NodeJs / Python3 / Linux 依赖",
                        badge: store.dependencies.isEmpty ? nil : "\(store.dependencies.count)",
                        tint: Theme.warning,
                        destination: DependenceListView()
                    )
                    MenuRow(
                        icon: "doc.text.fill",
                        title: "日志文件",
                        subtitle: "浏览面板日志目录",
                        tint: Theme.info,
                        destination: LogBrowserView()
                    )
                    MenuRow(
                        icon: "square.and.pencil",
                        title: "脚本管理",
                        subtitle: "查看与编辑脚本文件",
                        tint: Theme.accent,
                        destination: ScriptBrowserView()
                    )
                    MenuRow(
                        icon: "wrench.and.screwdriver",
                        title: "配置文件",
                        subtitle: "查看与编辑 config.sh 等面板配置",
                        tint: Theme.info,
                        destination: ConfigListView(inlineTitle: true)
                    )
                    MenuRow(
                        icon: "clock.arrow.circlepath",
                        title: "登录日志",
                        subtitle: "查看面板登录记录与来源 IP",
                        tint: Theme.warning,
                        destination: LoginLogView(inlineTitle: true)
                    )
                }

                Section(header: Text("连接")) {
                    MenuRow(
                        icon: "gear",
                        title: "面板与账号",
                        subtitle: store.connection?.baseURLString ?? "未连接",
                        tint: Theme.neutral,
                        destination: PanelSettingsView()
                    )
                    MenuRow(
                        icon: "chart.bar.fill",
                        title: "面板运行环境",
                        subtitle: store.systemStat.map { "\($0.cpus) 核 · 负载 \($0.loadAvg.first.map { String(format: "%.2f", $0) } ?? "-")" } ?? "读取中",
                        tint: Theme.info,
                        destination: SystemInfoView()
                    )
                }

                Section {
                    Button(action: { Task { await store.refreshAll() } }) {
                        HStack(spacing: 12) {
                            IconTile(icon: "arrow.clockwise", tint: Theme.accent)
                            Text("刷新全部数据")
                                .font(.system(size: 15))
                                .foregroundColor(Theme.primaryText)
                            Spacer()
                            if store.isLoading("dashboard") || store.isLoading("crons") {
                                ProgressView()
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationBarTitle("更多", displayMode: .large)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

// MARK: - 依赖管理

struct DependenceListView: View {

    @EnvironmentObject private var store: PanelStore

    @State private var filter: DependenceFilter = .all
    @State private var showCreate = false
    @State private var pendingDelete: QLDependence?

    enum DependenceFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case nodejs = "NodeJs"
        case python3 = "Python3"
        case linux = "Linux"

        var id: String { rawValue }
    }

    private var filtered: [QLDependence] {
        let base: [QLDependence]
        switch filter {
        case .all: base = store.dependencies
        case .nodejs: base = store.dependencies.filter { $0.kind == .nodejs }
        case .python3: base = store.dependencies.filter { $0.kind == .python3 }
        case .linux: base = store.dependencies.filter { $0.kind == .linux }
        }
        return base.sorted { lhs, rhs in
            if lhs.runState.isBusy != rhs.runState.isBusy { return lhs.runState.isBusy }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        ZStack {
            Theme.groupedBackground.edgesIgnoringSafeArea(.all)

            ScrollView {
                LazyVStack(spacing: 10) {
                    SearchField(text: $store.dependenceSearch, placeholder: "搜索依赖名")
                        .padding(.horizontal, 16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(DependenceFilter.allCases) { item in
                                FilterChip(title: item.rawValue, isSelected: filter == item) {
                                    filter = item
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    if store.isLoading("dependencies") && store.dependencies.isEmpty {
                        LoadingOverlay(title: "正在读取依赖列表…")
                    } else if filtered.isEmpty {
                        EmptyStateView(
                            icon: "cube.box",
                            title: "没有依赖记录",
                            message: "脚本需要的第三方库可以在这里安装，支持 NodeJs、Python3 与 Linux 三类。",
                            actionTitle: "添加依赖",
                            action: { showCreate = true }
                        )
                    } else {
                        cardList
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 30)
            }
        }
        .navigationBarTitle("依赖管理", displayMode: .inline)
        .navigationBarItems(
            trailing: Button(action: { showCreate = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .medium))
            }
        )
        .sheet(isPresented: $showCreate) {
            DependenceCreateView().environmentObject(store)
        }
        .alert(item: $pendingDelete) { item in
            Alert(
                title: Text("删除依赖"),
                message: Text("确定要删除「\(item.name)」吗？正在使用它的脚本可能会运行失败。"),
                primaryButton: .destructive(Text("删除")) {
                    Task { await store.deleteDependencies([item.id], force: item.runState == .installFailed) }
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .onAppear {
            if store.dependencies.isEmpty {
                Task { await store.loadDependencies() }
            }
        }
    }

    private var cardList: some View {
        VStack(spacing: 0) {
            let items = filtered
            ForEach(items.indices, id: \.self) { index in
                DependenceRowView(
                    item: items[index],
                    onDelete: { pendingDelete = items[index] }
                )

                if index < items.count - 1 {
                    Divider()
                        .background(Theme.separator)
                        .padding(.leading, 52)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardBackground))
        .padding(.horizontal, 16)
    }
}

struct DependenceRowView: View {

    let item: QLDependence
    let onDelete: () -> Void

    @EnvironmentObject private var store: PanelStore

    var body: some View {
        HStack(spacing: 10) {
            IconTile(icon: "cube.box.fill", tint: tint, size: 28)
                .overlay(
                    Text(item.kind.shortTitle)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(tint)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.primaryText)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(item.kind.title)
                    if !item.remark.isEmpty {
                        Text("·")
                        Text(item.remark).lineLimit(1)
                    }
                }
                .font(.system(size: 11))
                .foregroundColor(Theme.tertiaryText)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 6) {
                StatusPill(title: item.runState.title, tone: item.runState.tone)

                NavigationLink(destination: DependenceLogView(dependence: item)) {
                    Text("日志")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.info)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.info.opacity(0.12)))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .contextMenu {
            if item.runState.isBusy {
                Button { Task { await store.cancelDependencies([item.id]) } } label: {
                    Label("取消操作", systemImage: "xmark.circle")
                }
            } else {
                Button { Task { await store.reinstallDependencies([item.id]) } } label: {
                    Label("重新安装", systemImage: "arrow.clockwise")
                }
            }
            Button { onDelete() } label: {
                Label("删除依赖", systemImage: "trash")
            }
        }
    }

    private var tint: Color {
        switch item.kind {
        case .nodejs: return Theme.accent
        case .python3: return Theme.info
        case .linux: return Theme.warning
        }
    }
}

struct DependenceLogView: View {

    let dependence: QLDependence

    @EnvironmentObject private var store: PanelStore
    @State private var lines: [String] = []
    @State private var isLoading = true

    var body: some View {
        ZStack {
            Theme.groupedBackground.edgesIgnoringSafeArea(.all)

            TextDetailView(
                title: dependence.name,
                subtitle: "\(dependence.kind.title) · \(dependence.runState.title)",
                text: lines.isEmpty ? "（暂无安装日志）" : lines.joined(separator: "\n"),
                isLoading: isLoading,
                onRefresh: { Task { await reload() } },
                onSave: nil
            )
        }
        .onAppear { Task { await reload() } }
    }

    private func reload() async {
        isLoading = true
        lines = await store.dependenceLog(id: dependence.id)
        isLoading = false
    }
}

struct DependenceCreateView: View {

    @EnvironmentObject private var store: PanelStore
    @Environment(\.presentationMode) private var presentationMode

    @State private var name = ""
    @State private var kind: DependenceKind = .nodejs
    @State private var remark = ""
    @State private var isSaving = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("依赖")) {
                    TextField("包名，例如 axios 或 requests", text: $name)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .font(.system(size: 15, design: .monospaced))
                    TextField("备注（可留空）", text: $remark)
                }

                Section(header: Text("类型")) {
                    Picker("类型", selection: $kind) {
                        Text("NodeJs").tag(DependenceKind.nodejs)
                        Text("Python3").tag(DependenceKind.python3)
                        Text("Linux").tag(DependenceKind.linux)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            }
            .navigationBarTitle("添加依赖", displayMode: .inline)
            .navigationBarItems(
                leading: Button("取消") { presentationMode.wrappedValue.dismiss() },
                trailing: Button(action: save) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("保存").bold()
                    }
                }
                .disabled(isSaving || name.isEmpty)
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func save() {
        isSaving = true
        Task {
            let ok = await store.createDependence(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: kind,
                remark: remark.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            isSaving = false
            if ok { presentationMode.wrappedValue.dismiss() }
        }
    }
}
