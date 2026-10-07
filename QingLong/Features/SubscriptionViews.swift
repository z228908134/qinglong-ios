import SwiftUI

/// 订阅新建请求体。面板要求 `type` / `url` / `alias` / `schedule_type` 四个字段必填。
struct SubscriptionCreatePayload: Encodable {
    var type: String
    var url: String
    var alias: String
    var scheduleType: String
    var schedule: String?
    var branch: String?
    var whitelist: String?
    var blacklist: String?
    var dependences: String?
    var autoAddCron: Int?
    var autoDelCron: Int?

    enum CodingKeys: String, CodingKey {
        case type, url, alias, schedule, branch, whitelist, blacklist, dependences
        case scheduleType = "schedule_type"
        case autoAddCron
        case autoDelCron
    }
}

// MARK: - 订阅列表

struct SubscriptionListView: View {

    @EnvironmentObject private var store: PanelStore

    @State private var showCreate = false
    @State private var pendingDelete: QLSubscription?
    @State private var searchWorkItem: DispatchWorkItem?

    private var sorted: [QLSubscription] {
        store.subscriptions.sorted { lhs, rhs in
            if lhs.isDisabled != rhs.isDisabled { return (lhs.isDisabled ?? 0) < (rhs.isDisabled ?? 0) }
            return lhs.displayName.localizedCompare(rhs.displayName) == .orderedAscending
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Theme.groupedBackground.edgesIgnoringSafeArea(.all)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        SearchField(text: $store.subscriptionSearch, placeholder: "搜索订阅名称或仓库地址")
                            .padding(.horizontal, 16)

                        if store.isLoading("subscriptions") && store.subscriptions.isEmpty {
                            LoadingOverlay(title: "正在读取订阅…")
                        } else if sorted.isEmpty {
                            EmptyStateView(
                                icon: "arrow.triangle.2.circlepath",
                                title: "还没有订阅",
                                message: "订阅用于从 Git 仓库批量拉取脚本，并在仓库更新时自动同步。",
                                actionTitle: "新建订阅",
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
            .navigationBarTitle("订阅管理", displayMode: .large)
            .navigationBarItems(
                leading: ToolbarIconButton(icon: "arrow.clockwise", isEnabled: !store.isLoading("subscriptions")) {
                    Task { await store.loadSubscriptions() }
                },
                trailing: Button(action: { showCreate = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: Theme.font(17), weight: .medium))
                }
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showCreate) {
            SubscriptionCreateView().environmentObject(store)
        }
        .alert(item: $pendingDelete) { item in
            Alert(
                title: Text("删除订阅"),
                message: Text("确定要删除「\(item.displayName)」吗？由它创建的任务可能需要手动清理。"),
                primaryButton: .destructive(Text("删除")) {
                    Task { await store.deleteSubscriptions([item.id]) }
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .onAppear {
            if store.subscriptions.isEmpty {
                Task { await store.loadSubscriptions() }
            }
        }
        .onChange(of: store.subscriptionSearch) { _ in
            searchWorkItem?.cancel()
            let item = DispatchWorkItem { Task { await store.loadSubscriptions() } }
            searchWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: item)
        }
    }

    private var cardList: some View {
        VStack(spacing: 0) {
            let items = sorted
            ForEach(items.indices, id: \.self) { index in
                SubscriptionRowView(
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

// MARK: - 订阅行

struct SubscriptionRowView: View {

    let item: QLSubscription
    let onDelete: () -> Void

    @EnvironmentObject private var store: PanelStore

    private var isDisabled: Bool { (item.isDisabled ?? 0) == 1 }

    var body: some View {
        HStack(spacing: 10) {
            IconTile(
                icon: "arrow.triangle.2.circlepath",
                tint: isDisabled ? Theme.neutral : Theme.info,
                size: 28
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .font(.system(size: Theme.font(13.5), weight: .medium))
                    .foregroundColor(isDisabled ? Theme.secondaryText : Theme.primaryText)
                    .lineLimit(1)

                if let url = item.url, !url.isEmpty {
                    Text(url)
                        .font(.system(size: Theme.font(11), design: .monospaced))
                        .foregroundColor(Theme.tertiaryText)
                        .lineLimit(1)
                }

                HStack(spacing: 5) {
                    Text(item.typeTitle)
                    Text("·")
                    Text(item.scheduleDescription)
                }
                .font(.system(size: Theme.font(11)))
                .foregroundColor(Theme.tertiaryText)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 6) {
                StatusPill(
                    title: isDisabled ? "已禁用" : item.runStatus.title,
                    tone: isDisabled ? .muted : item.runStatus.tone
                )

                HStack(spacing: 6) {
                    // 运行 / 停止做成常驻按钮直接放在行上。
                    // 原先这几个操作只存在于长按菜单（contextMenu）里，
                    // iOS 上必须长按才弹出，极易被当成"这个页面只能看"。
                    Button(action: {
                        Task {
                            if item.runStatus.isActive {
                                await store.stopSubscriptions([item.id])
                            } else {
                                await store.runSubscriptions([item.id])
                            }
                        }
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: item.runStatus.isActive ? "stop.fill" : "play.fill")
                                .font(.system(size: Theme.font(9)))
                            Text(item.runStatus.isActive ? "停止" : "拉取")
                                .font(.system(size: Theme.font(11), weight: .medium))
                        }
                        .foregroundColor(item.runStatus.isActive ? Theme.danger : Theme.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(
                                (item.runStatus.isActive ? Theme.danger : Theme.accent).opacity(0.12)
                            )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())

                    NavigationLink(destination: SubscriptionLogView(subscription: item)) {
                        Text("日志")
                            .font(.system(size: Theme.font(11), weight: .medium))
                            .foregroundColor(Theme.info)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Theme.info.opacity(0.12)))
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .contextMenu {
            if item.runStatus.isActive {
                Button { Task { await store.stopSubscriptions([item.id]) } } label: {
                    Label("停止运行", systemImage: "stop.fill")
                }
            } else {
                Button { Task { await store.runSubscriptions([item.id]) } } label: {
                    Label("立即拉取", systemImage: "play.fill")
                }
            }

            if isDisabled {
                Button { Task { await store.enableSubscriptions([item.id]) } } label: {
                    Label("启用订阅", systemImage: "checkmark.circle")
                }
            } else {
                Button { Task { await store.disableSubscriptions([item.id]) } } label: {
                    Label("禁用订阅", systemImage: "pause.circle")
                }
            }

            Button { onDelete() } label: {
                Label("删除订阅", systemImage: "trash")
            }
        }
    }
}

// MARK: - 订阅日志

struct SubscriptionLogView: View {

    let subscription: QLSubscription

    @EnvironmentObject private var store: PanelStore
    @State private var text = ""
    @State private var isLoading = true

    var body: some View {
        ZStack {
            Theme.groupedBackground.edgesIgnoringSafeArea(.all)

            TextDetailView(
                title: subscription.displayName,
                subtitle: subscription.url,
                text: text,
                isLoading: isLoading,
                onRefresh: { Task { await reload() } },
                onSave: nil
            )
        }
        .onAppear { Task { await reload() } }
    }

    private func reload() async {
        isLoading = true
        text = await store.subscriptionLog(id: subscription.id)
        isLoading = false
    }
}

// MARK: - 新建订阅

struct SubscriptionCreateView: View {

    @EnvironmentObject private var store: PanelStore
    @Environment(\.presentationMode) private var presentationMode

    @State private var url = ""
    @State private var alias = ""
    @State private var branch = ""
    @State private var schedule = "0 0 0 * * *"
    @State private var whitelist = ""
    @State private var autoAddCron = true
    @State private var isSaving = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("仓库"), footer: Text("目前支持公开仓库（Git 地址）。公开仓库无需凭据，私有仓库请在面板网页端配置。")) {
                    TextField("仓库地址，例如 https://github.com/user/repo.git", text: $url)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .font(.system(size: Theme.font(13), design: .monospaced))
                    TextField("别名，例如 jd_scripts", text: $alias)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("分支（可留空，默认跟随仓库默认分支）", text: $branch)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Section(header: Text("拉取设置")) {
                    TextField("定时规则", text: $schedule)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .font(.system(size: Theme.font(15), design: .monospaced))
                    TextField("白名单文件名（可留空，逗号分隔）", text: $whitelist)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Toggle("拉取后自动创建任务", isOn: $autoAddCron)
                }
            }
            .navigationBarTitle("新建订阅", displayMode: .inline)
            .navigationBarItems(
                leading: Button("取消") { presentationMode.wrappedValue.dismiss() },
                trailing: Button(action: save) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("保存").bold()
                    }
                }
                .disabled(isSaving || url.isEmpty || alias.isEmpty)
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func save() {
        isSaving = true

        let payload = SubscriptionCreatePayload(
            type: "public-repo",
            url: url.trimmingCharacters(in: .whitespacesAndNewlines),
            alias: alias.trimmingCharacters(in: .whitespacesAndNewlines),
            scheduleType: "crontab",
            schedule: schedule.trimmingCharacters(in: .whitespacesAndNewlines),
            branch: branch.isEmpty ? nil : branch,
            whitelist: whitelist.isEmpty ? nil : whitelist,
            blacklist: nil,
            dependences: nil,
            autoAddCron: autoAddCron ? 1 : 0,
            autoDelCron: 0
        )

        Task {
            let ok = await store.createSubscription(payload)
            isSaving = false
            if ok { presentationMode.wrappedValue.dismiss() }
        }
    }
}
