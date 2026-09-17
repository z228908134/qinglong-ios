//
//  EnvListView.swift
//  环境变量：查看（默认打码）、搜索、增删改、启用/禁用
//

import SwiftUI

struct EnvListView: View {

    @EnvironmentObject private var session: SessionStore

    @State private var items: [EnvVar] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasLoadedOnce = false
    @State private var revealed: Set<Int> = []
    @State private var editing: EnvVar?
    @State private var creating = false
    @State private var pendingDelete: EnvVar?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    ErrorBanner(message: errorMessage) { Task { await load() } }
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            Section {
                ForEach(items) { item in
                    row(item)
                        .contentShape(Rectangle())
                        .onTapGesture { editing = item }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDelete = item
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                let enable = item.isDisabledVar
                                act(enable ? "已启用" : "已禁用") { client in
                                    if enable {
                                        try await client.enableEnvs([item.id])
                                    } else {
                                        try await client.disableEnvs([item.id])
                                    }
                                }
                            } label: {
                                Label(item.isDisabledVar ? "启用" : "禁用",
                                      systemImage: item.isDisabledVar ? "play.circle" : "pause.circle")
                            }
                            .tint(item.isDisabledVar ? .blue : .gray)
                        }
                        .contextMenu {
                            Button { editing = item } label: { Label("编辑", systemImage: "square.and.pencil") }
                            Button {
                                UIPasteboard.general.string = item.value ?? ""
                                session.show("已复制变量值")
                            } label: {
                                Label("复制值", systemImage: "doc.on.doc")
                            }
                            Button {
                                UIPasteboard.general.string = item.name ?? ""
                                session.show("已复制变量名")
                            } label: {
                                Label("复制名称", systemImage: "textformat")
                            }
                        }
                }
            } header: {
                Text("共 \(items.count) 个变量")
            } footer: {
                Text("变量值默认打码显示，点眼睛图标可临时查看。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("环境变量")
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "搜索变量名 / 备注")
        .refreshable { await load() }
        .overlay {
            if items.isEmpty && !isLoading {
                EmptyStateView(symbol: "key",
                               title: searchText.isEmpty ? "还没有环境变量" : "没有匹配的变量",
                               message: searchText.isEmpty ? "点右上角 + 新建" : "换个关键词试试")
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { creating = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $creating) {
            EnvEditSheet(item: nil) { Task { await load() } }
        }
        .sheet(item: $editing) { item in
            EnvEditSheet(item: item) { Task { await load() } }
        }
        .confirmationDialog("确认删除变量？",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible,
                            presenting: pendingDelete) { item in
            Button("删除「\(item.displayName)」", role: .destructive) {
                pendingDelete = nil
                act("已删除") { try await $0.deleteEnvs([item.id]) }
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("依赖这个变量的任务会受影响，请谨慎操作。")
        }
        .task(id: searchText) {
            if hasLoadedOnce {
                try? await Task.sleep(nanoseconds: 350_000_000)
                if Task.isCancelled { return }
            }
            await load()
        }
    }

    // MARK: 行

    private func row(_ item: EnvVar) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                if item.isPinned == 1 {
                    Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.orange)
                }
                Text(item.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 6)
                let status = item.status ?? .normal
                StatusPill(text: status.title, color: status.color, symbol: status.symbol)
            }

            HStack(alignment: .top, spacing: 6) {
                Text(isRevealed(item) ? (item.value ?? "") : maskedValue(item.value))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(isRevealed(item) ? 5 : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    toggleReveal(item)
                } label: {
                    Image(systemName: isRevealed(item) ? "eye.slash" : "eye")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if let remarks = item.remarks, !remarks.isEmpty {
                Text(remarks)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            if let labels = item.labels, !labels.isEmpty {
                HStack(spacing: 4) {
                    ForEach(labels, id: \.self) { label in
                        Text(label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func isRevealed(_ item: EnvVar) -> Bool { revealed.contains(item.id) }

    private func toggleReveal(_ item: EnvVar) {
        if revealed.contains(item.id) {
            revealed.remove(item.id)
        } else {
            revealed.insert(item.id)
        }
    }

    private func maskedValue(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "（空值）" }
        let dots = String(repeating: "•", count: min(max(value.count, 8), 24))
        return "\(dots)  共 \(value.count) 字符"
    }

    // MARK: 数据

    private func load() async {
        guard let client = session.client else { return }
        if items.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            items = try await client.envs(search: searchText)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        hasLoadedOnce = true
    }

    private func act(_ label: String, _ action: @escaping (APIClient) async throws -> Void) {
        Task {
            guard let client = session.client else { return }
            do {
                try await action(client)
                session.show(label)
                await load()
            } catch {
                session.handle(error, context: label)
            }
        }
    }
}

// MARK: - 新建 / 编辑

struct EnvEditSheet: View {

    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    private let original: EnvVar?
    private let onSaved: () -> Void

    @State private var name = ""
    @State private var value = ""
    @State private var remarks = ""
    @State private var labelsText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(item: EnvVar?, onSaved: @escaping () -> Void = {}) {
        self.original = item
        self.onSaved = onSaved
    }

    private var isEditing: Bool { original != nil }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 后端 Joi 规则：^[a-zA-Z_][0-9a-zA-Z_]*$
    private var nameIsValid: Bool {
        trimmedName.range(of: "^[a-zA-Z_][0-9a-zA-Z_]*$", options: .regularExpression) != nil
    }

    private var canSave: Bool {
        nameIsValid && !value.isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("变量名，如 JD_COOKIE", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 14, design: .monospaced))
                    if !trimmedName.isEmpty && !nameIsValid {
                        Text("变量名只能由字母、数字、下划线组成，且不能以数字开头")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("变量名")
                }

                Section("变量值") {
                    TextEditor(text: $value)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 110)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("备注 / 标签") {
                    TextField("备注", text: $remarks)
                    TextField("标签，用英文逗号分隔", text: $labelsText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).font(.system(size: 12)).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isEditing ? "编辑变量" : "新建变量")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("保存").bold()
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                guard let original else { return }
                name = original.name ?? ""
                value = original.value ?? ""
                remarks = original.remarks ?? ""
                labelsText = (original.labels ?? []).joined(separator: ",")
            }
        }
    }

    private func save() async {
        guard let client = session.client, canSave else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let labels = labelsText
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let payload = EnvPayload(
            id: original?.id,
            name: trimmedName,
            value: value,
            remarks: remarks.isEmpty ? nil : remarks,
            labels: labels.isEmpty ? nil : labels
        )

        do {
            if isEditing {
                try await client.updateEnv(payload)
            } else {
                try await client.createEnvs([payload])
            }
            session.show(isEditing ? "变量已保存" : "变量已创建")
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
