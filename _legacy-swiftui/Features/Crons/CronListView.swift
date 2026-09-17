//
//  CronListView.swift
//  定时任务列表
//

import SwiftUI

struct CronListView: View {

    @EnvironmentObject private var session: SessionStore
    @StateObject private var vm = CronListViewModel()

    @State private var creating = false
    @State private var editing: CronTask?
    @State private var pendingDelete: CronTask?

    var body: some View {
        List {
            if let error = vm.errorMessage {
                Section {
                    ErrorBanner(message: error) {
                        Task { await refresh() }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }

            Section {
                ForEach(vm.tasks) { task in
                    NavigationLink {
                        CronDetailView(task: task)
                    } label: {
                        CronRowView(task: task)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if task.isBusy {
                            Button {
                                perform("已停止") { try await vm.stop(task, client: $0) }
                            } label: {
                                Label("停止", systemImage: "stop.fill")
                            }
                            .tint(.orange)
                        } else {
                            Button {
                                perform("已启动") { try await vm.run(task, client: $0) }
                            } label: {
                                Label("运行", systemImage: "play.fill")
                            }
                            .tint(.green)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDelete = task
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        Button {
                            let enabled = task.isDisabledTask
                            perform(enabled ? "已启用" : "已禁用") {
                                try await vm.setEnabled(task, enabled: enabled, client: $0)
                            }
                        } label: {
                            Label(task.isDisabledTask ? "启用" : "禁用",
                                  systemImage: task.isDisabledTask ? "play.circle" : "pause.circle")
                        }
                        .tint(task.isDisabledTask ? .blue : .gray)
                    }
                    .contextMenu {
                        Button {
                            perform(task.isBusy ? "已停止" : "已启动") { client in
                                if task.isBusy {
                                    try await vm.stop(task, client: client)
                                } else {
                                    try await vm.run(task, client: client)
                                }
                            }
                        } label: {
                            Label(task.isBusy ? "停止任务" : "立即运行",
                                  systemImage: task.isBusy ? "stop.fill" : "play.fill")
                        }

                        Button {
                            editing = task
                        } label: {
                            Label("编辑任务", systemImage: "square.and.pencil")
                        }

                        Button {
                            perform(task.isPinnedTask ? "已取消置顶" : "已置顶") {
                                try await vm.setPinned(task, pinned: !task.isPinnedTask, client: $0)
                            }
                        } label: {
                            Label(task.isPinnedTask ? "取消置顶" : "置顶",
                                  systemImage: task.isPinnedTask ? "pin.slash" : "pin")
                        }

                        Button {
                            UIPasteboard.general.string = task.command ?? ""
                            session.show("已复制命令")
                        } label: {
                            Label("复制命令", systemImage: "doc.on.doc")
                        }
                    }
                    .task {
                        guard let client = session.client else { return }
                        await vm.loadMoreIfNeeded(current: task, client: client)
                    }
                }

                if vm.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView().scaleEffect(0.9)
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }
            } header: {
                Text(vm.summary)
            } footer: {
                if !vm.tasks.isEmpty && vm.tasks.count < vm.total {
                    Text("已加载 \(vm.tasks.count) / \(vm.total)，继续下拉可加载更多")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("定时任务")
        .searchable(text: $vm.searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "搜索任务名 / 命令 / 标签")
        .refreshable { await refresh() }
        .overlay {
            if vm.tasks.isEmpty && !vm.isLoading {
                EmptyStateView(symbol: "tray",
                               title: vm.searchText.isEmpty ? "还没有定时任务" : "没有匹配的任务",
                               message: vm.searchText.isEmpty ? "点右上角 + 新建，或先在面板里导入订阅" : "换个关键词试试")
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    creating = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $creating) {
            CronEditView(task: nil) { Task { await refresh() } }
        }
        .sheet(item: $editing) { task in
            CronEditView(task: task) { Task { await refresh() } }
        }
        .confirmationDialog("确认删除任务？",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible,
                            presenting: pendingDelete) { task in
            Button("删除「\(task.displayName)」", role: .destructive) {
                pendingDelete = nil
                perform("已删除") { try await vm.delete(task, client: $0) }
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("删除后无法恢复，已产生的日志文件会保留在面板上。")
        }
        .task(id: vm.searchText) {
            if vm.hasLoadedOnce {
                try? await Task.sleep(nanoseconds: 350_000_000)
                if Task.isCancelled { return }
            }
            await refresh()
        }
    }

    // MARK: 辅助

    private func refresh() async {
        guard let client = session.client else { return }
        await vm.refresh(client: client)
    }

    private func perform(_ label: String, _ action: @escaping (APIClient) async throws -> Void) {
        Task {
            guard let client = session.client else { return }
            do {
                try await action(client)
                session.show(label)
                try? await Task.sleep(nanoseconds: 450_000_000)
                await vm.reloadCurrentWindow(client: client)
            } catch {
                session.handle(error, context: label)
            }
        }
    }
}

// MARK: - 单行

struct CronRowView: View {
    let task: CronTask

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if task.isPinnedTask {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
                Text(task.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 6)
                StatusPill(text: task.effectiveStatus.title,
                           color: task.effectiveStatus.color,
                           symbol: task.effectiveStatus.symbol)
            }

            HStack(spacing: 5) {
                miniTag(task.schedule ?? "—", symbol: "clock")
                if let labels = task.labels, !labels.isEmpty {
                    miniTag(labels.prefix(2).joined(separator: " · "), symbol: "tag")
                }
                if task.isSystemTask {
                    miniTag("系统", symbol: "gearshape")
                }
            }

            HStack(spacing: 12) {
                Label(QLFormat.relative(millis: task.lastExecutionTime), systemImage: "clock.arrow.circlepath")
                if let pid = task.pid, task.isBusy {
                    Label("PID \(pid)", systemImage: "cpu")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private func miniTag(_ text: String, symbol: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 8, weight: .semibold))
            Text(text).font(.system(size: 10, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color(.tertiarySystemFill), in: Capsule())
    }
}
