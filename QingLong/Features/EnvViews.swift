import SwiftUI
import UIKit

// MARK: - 环境变量列表

struct EnvListView: View {

    var body: some View {
        NavigationView {
            EnvListContent()
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

/// 环境变量列表内容。任务 Tab 与「更多」页共用。
struct EnvListContent: View {

    /// 「更多」页里以 inline 标题推入；Tab 里用大标题。
    var inlineTitle: Bool = false

    init(inlineTitle: Bool = false) {
        self.inlineTitle = inlineTitle
    }

    @EnvironmentObject private var store: PanelStore

    @State private var filter: EnvFilter = .all
    @State private var sheet: EnvSheet?
    @State private var pendingDelete: QLEnv?
    @State private var revealed: Set<String> = []
    @State private var searchWorkItem: DispatchWorkItem?

    /// 用一个枚举统一驱动弹窗，避免同一视图上挂多个 sheet 造成互相覆盖。
    enum EnvSheet: Identifiable {
        case create
        case edit(QLEnv)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let item): return "edit-\(item.id)"
            }
        }

        var item: QLEnv? {
            switch self {
            case .create: return nil
            case .edit(let item): return item
            }
        }
    }

    enum EnvFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case enabled = "已启用"
        case disabled = "已禁用"
        case pinned = "已置顶"

        var id: String { rawValue }
    }

    private var filtered: [QLEnv] {
        let base: [QLEnv]
        switch filter {
        case .all: base = store.envs
        case .enabled: base = store.envs.filter { !$0.isDisabledEnv }
        case .disabled: base = store.envs.filter { $0.isDisabledEnv }
        case .pinned: base = store.envs.filter { $0.isPinnedEnv }
        }
        return base.sorted { lhs, rhs in
            if lhs.isPinnedEnv != rhs.isPinnedEnv { return lhs.isPinnedEnv }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
    }

    private func count(for filter: EnvFilter) -> Int {
        switch filter {
        case .all: return store.envs.count
        case .enabled: return store.envs.filter { !$0.isDisabledEnv }.count
        case .disabled: return store.envs.filter { $0.isDisabledEnv }.count
        case .pinned: return store.envs.filter { $0.isPinnedEnv }.count
        }
    }

    var body: some View {
        ZStack {
                Theme.groupedBackground.edgesIgnoringSafeArea(.all)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        SearchField(text: $store.envSearch, placeholder: "搜索变量名或值")
                            .padding(.horizontal, 16)

                        filterRow

                        if store.isLoading("envs") && store.envs.isEmpty {
                            LoadingOverlay(title: "正在读取环境变量…")
                        } else if filtered.isEmpty {
                            EmptyStateView(
                                icon: "key",
                                title: store.envs.isEmpty ? "还没有环境变量" : "没有符合条件的变量",
                                message: store.envs.isEmpty
                                    ? "环境变量是脚本运行时的凭据来源，例如各平台的 Cookie 与 Token。"
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
            .navigationBarTitle("环境变量", displayMode: inlineTitle ? .inline : .large)
            .navigationBarItems(
                leading: ToolbarIconButton(icon: "arrow.clockwise", isEnabled: !store.isLoading("envs")) {
                    Task { await store.loadEnvs() }
                },
                trailing: Button(action: { sheet = .create }) {
                    Image(systemName: "plus")
                        .font(.system(size: Theme.font(17), weight: .medium))
                }
            )
        .sheet(item: $sheet) { target in
            EnvEditView(item: target.item).environmentObject(store)
        }
        .alert(item: $pendingDelete) { item in
            Alert(
                title: Text("删除变量"),
                message: Text("确定要删除「\(item.name)」吗？依赖它的脚本会立刻失去该凭据。"),
                primaryButton: .destructive(Text("删除")) {
                    Task { await store.deleteEnvs([item.id]) }
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .onAppear {
            if store.envs.isEmpty {
                Task { await store.loadEnvs() }
            }
        }
        .onChange(of: store.envSearch) { _ in
            searchWorkItem?.cancel()
            let item = DispatchWorkItem { Task { await store.loadEnvs() } }
            searchWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: item)
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EnvFilter.allCases) { item in
                    FilterChip(title: item.rawValue, count: count(for: item), isSelected: filter == item) {
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
                EnvRowView(
                    item: items[index],
                    isRevealed: revealed.contains(items[index].id),
                    onToggleReveal: { toggleReveal(items[index].id) },
                    onEdit: { sheet = .edit(items[index]) },
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

    private func toggleReveal(_ id: String) {
        if revealed.contains(id) {
            revealed.remove(id)
        } else {
            revealed.insert(id)
        }
    }
}

// MARK: - 环境变量行

struct EnvRowView: View {

    let item: QLEnv
    let isRevealed: Bool
    let onToggleReveal: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject private var store: PanelStore

    var body: some View {
        HStack(spacing: 10) {
            IconTile(
                icon: "key.fill",
                tint: item.isDisabledEnv ? Theme.neutral : Theme.accent,
                size: 28
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if item.isPinnedEnv {
                        Image(systemName: "pin.fill")
                            .font(.system(size: Theme.font(9)))
                            .foregroundColor(Theme.warning)
                    }
                    Text(item.name)
                        .font(.system(size: Theme.font(13), weight: .medium, design: .monospaced))
                        .foregroundColor(item.isDisabledEnv ? Theme.secondaryText : Theme.primaryText)
                        .lineLimit(1)
                }

                Button(action: onToggleReveal) {
                    Text(isRevealed ? item.value : maskedValue)
                        .font(.system(size: Theme.font(11.5), design: .monospaced))
                        .foregroundColor(Theme.secondaryText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !item.remarks.isEmpty {
                    Text(item.remarks)
                        .font(.system(size: Theme.font(11)))
                        .foregroundColor(Theme.tertiaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            StatusPill(title: item.statusTitle, tone: item.statusTone)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .contextMenu {
            if item.isDisabledEnv {
                Button { Task { await store.enableEnvs([item.id]) } } label: {
                    Label("启用变量", systemImage: "checkmark.circle")
                }
            } else {
                Button { Task { await store.disableEnvs([item.id]) } } label: {
                    Label("禁用变量", systemImage: "pause.circle")
                }
            }

            Button { onEdit() } label: {
                Label("编辑", systemImage: "square.and.pencil")
            }

            Button { Task { await store.pinEnvs([item.id], pinned: !item.isPinnedEnv) } } label: {
                Label(item.isPinnedEnv ? "取消置顶" : "置顶", systemImage: "pin")
            }

            Button {
                UIPasteboard.general.string = item.value
            } label: {
                Label("复制变量值", systemImage: "doc.on.doc")
            }

            Button { onDelete() } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    /// 敏感值默认打码，仅保留首尾少量字符便于辨认。
    private var maskedValue: String {
        guard item.value.count > 10 else {
            return String(repeating: "•", count: max(item.value.count, 6))
        }
        let head = item.value.prefix(4)
        let tail = item.value.suffix(4)
        return "\(head)••••••\(tail)（点按查看）"
    }
}

// MARK: - 环境变量编辑

struct EnvEditView: View {

    let item: QLEnv?

    @EnvironmentObject private var store: PanelStore
    @Environment(\.presentationMode) private var presentationMode

    @State private var name = ""
    @State private var value = ""
    @State private var remarks = ""
    @State private var isSaving = false

    private var isNew: Bool { item == nil }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("变量")) {
                    TextField("变量名，例如 JD_COOKIE", text: $name)
                        .autocapitalization(.allCharacters)
                        .disableAutocorrection(true)
                        .font(.system(size: Theme.font(15), design: .monospaced))
                    TextField("备注（可留空）", text: $remarks)
                }

                Section(header: Text("值"), footer: Text("变量名只能包含字母、数字与下划线，且不能以数字开头。")) {
                    TextEditor(text: $value)
                        .font(.system(size: Theme.font(13), design: .monospaced))
                        .frame(minHeight: 110)
                }
            }
            .navigationBarTitle(isNew ? "新建变量" : "编辑变量", displayMode: .inline)
            .navigationBarItems(
                leading: Button("取消") { presentationMode.wrappedValue.dismiss() },
                trailing: Button(action: save) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("保存").bold()
                    }
                }
                .disabled(isSaving || name.isEmpty || value.isEmpty)
            )
            .onAppear(perform: fill)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func fill() {
        guard let item = item else { return }
        name = item.name
        value = item.value
        remarks = item.remarks
    }

    private func save() {
        isSaving = true
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRemarks = remarks.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            let ok: Bool
            if let item = item {
                ok = await store.updateEnv(
                    id: item.id,
                    name: trimmedName,
                    value: value,
                    remarks: trimmedRemarks
                )
            } else {
                ok = await store.createEnv(
                    name: trimmedName,
                    value: value,
                    remarks: trimmedRemarks
                )
            }
            isSaving = false
            if ok { presentationMode.wrappedValue.dismiss() }
        }
    }
}
