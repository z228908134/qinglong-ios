//
//  CronDetailView.swift
//  任务详情：状态、操作、日志（运行中自动刷新）
//

import SwiftUI

@MainActor
final class CronDetailViewModel: ObservableObject {

    @Published var task: CronTask
    @Published var logText = ""
    @Published var logStatus: String?
    @Published var isLoadingLog = false
    @Published var autoRefresh = true
    @Published var isActing = false
    @Published var errorMessage: String?

    private var loop: Task<Void, Never>?

    init(task: CronTask) {
        self.task = task
    }

    var nextRun: String? {
        CronSchedule.nextRunDescription(for: task.schedule)
    }

    var logStatusText: String? {
        switch logStatus {
        case "running": return "运行中"
        case "completed": return "已完成"
        case "ignored": return "已忽略日志"
        case "empty", "notFound": return "暂无日志"
        default: return nil
        }
    }

    // MARK: 加载

    func reloadTask(client: APIClient) async {
        if let fresh = try? await client.cron(id: task.id) {
            task = fresh
        }
    }

    func loadLog(client: APIClient, silent: Bool = false) async {
        if !silent { isLoadingLog = true }
        defer { isLoadingLog = false }
        do {
            let result = try await client.cronLog(id: task.id)
            logText = result.content.strippingANSI
            logStatus = result.status
            errorMessage = nil
        } catch {
            if !silent { errorMessage = error.localizedDescription }
        }
    }

    func load(client: APIClient) async {
        isLoadingLog = true
        await reloadTask(client: client)
        await loadLog(client: client, silent: true)
        isLoadingLog = false
        beginLoop(client: client)
    }

    func beginLoop(client: APIClient) {
        endLoop()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self, !Task.isCancelled else { return }
                guard self.autoRefresh else { continue }
                await self.reloadTask(client: client)
                if self.task.isBusy {
                    await self.loadLog(client: client, silent: true)
                }
            }
        }
    }

    func endLoop() {
        loop?.cancel()
        loop = nil
    }

    // MARK: 动作

    func run(client: APIClient) async throws {
        try await client.runCrons([task.id])
        try? await Task.sleep(nanoseconds: 500_000_000)
        await reloadTask(client: client)
        await loadLog(client: client, silent: true)
    }

    func stop(client: APIClient) async throws {
        try await client.stopCrons([task.id])
        try? await Task.sleep(nanoseconds: 500_000_000)
        await reloadTask(client: client)
    }

    func setEnabled(_ enabled: Bool, client: APIClient) async throws {
        if enabled {
            try await client.enableCrons([task.id])
        } else {
            try await client.disableCrons([task.id])
        }
        await reloadTask(client: client)
    }

    func setPinned(_ pinned: Bool, client: APIClient) async throws {
        if pinned {
            try await client.pinCrons([task.id])
        } else {
            try await client.unpinCrons([task.id])
        }
        await reloadTask(client: client)
    }

    func delete(client: APIClient) async throws {
        try await client.deleteCrons([task.id])
    }
}

// MARK: - 页面

struct CronDetailView: View {

    @EnvironmentObject private var session: SessionStore
    @StateObject private var vm: CronDetailViewModel

    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var showFullLog = false

    private let logPreviewLines = 400

    init(task: CronTask) {
        _vm = StateObject(wrappedValue: CronDetailViewModel(task: task))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                headerCard
                actionCard
                if !vm.logText.isEmpty { logCard }
                metaCard
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(vm.task.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { editing = true } label: { Label("编辑任务", systemImage: "square.and.pencil") }
                    Button {
                        UIPasteboard.general.string = vm.task.command ?? ""
                        session.show("已复制命令")
                    } label: {
                        Label("复制命令", systemImage: "doc.on.doc")
                    }
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Label("删除任务", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            guard let client = session.client else { return }
            await vm.load(client: client)
        }
        .onDisappear { vm.endLoop() }
        .sheet(isPresented: $editing) {
            CronEditView(task: vm.task) {
                Task {
                    if let client = session.client { await vm.reloadTask(client: client) }
                }
            }
        }
        .sheet(isPresented: $showFullLog) {
            NavigationStack {
                LogTextDetailView(title: "\(vm.task.displayName) · 日志",
                                  content: vm.logText,
                                  subtitle: vm.logStatusText)
            }
        }
        .alert("确认删除任务？", isPresented: $confirmingDelete) {
            Button("删除", role: .destructive) {
                Task {
                    guard let client = session.client else { return }
                    do {
                        try await vm.delete(client: client)
                        session.show("已删除")
                    } catch {
                        session.handle(error, context: "删除失败")
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复。")
        }
    }

    // MARK: 卡片

    private var headerCard: some View {
        Card {
            HStack(alignment: .top, spacing: 8) {
                Text(vm.task.displayName)
                    .font(.system(size: 17, weight: .bold))
                    .lineLimit(2)
                Spacer(minLength: 4)
                StatusPill(text: vm.task.effectiveStatus.title,
                           color: vm.task.effectiveStatus.color,
                           symbol: vm.task.effectiveStatus.symbol)
            }

            if let labels = vm.task.labels, !labels.isEmpty {
                HStack(spacing: 5) {
                    ForEach(labels, id: \.self) { label in
                        Text(label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    }
                }
            }

            Divider()

            InfoRow(label: "定时规则", value: vm.task.schedule ?? "—", mono: true, accent: .accentColor)
            if let next = vm.nextRun {
                InfoRow(label: "下次执行", value: next, accent: .green)
            }
            InfoRow(label: "上次执行", value: QLFormat.relative(millis: vm.task.lastExecutionTime))
            if let running = vm.task.lastRunningTime, running > 0 {
                InfoRow(label: "上次开始", value: QLFormat.absolute(Date(timeIntervalSince1970: running / 1000)))
            }
            if let pid = vm.task.pid, vm.task.isBusy {
                InfoRow(label: "进程号", value: String(pid), mono: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("执行命令")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(vm.task.command ?? "—")
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(.tertiarySystemFill),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var actionCard: some View {
        Card {
            HStack(spacing: 10) {
                if vm.task.isBusy {
                    ActionChip(title: "停止", symbol: "stop.fill", tint: .orange) {
                        act("已停止") { try await vm.stop(client: $0) }
                    }
                } else {
                    ActionChip(title: "立即运行", symbol: "play.fill", tint: .green) {
                        act("已启动") { try await vm.run(client: $0) }
                    }
                }

                ActionChip(title: vm.task.isDisabledTask ? "启用" : "禁用",
                           symbol: vm.task.isDisabledTask ? "play.circle" : "pause.circle",
                           tint: vm.task.isDisabledTask ? .blue : .gray) {
                    let enabled = vm.task.isDisabledTask
                    act(enabled ? "已启用" : "已禁用") { try await vm.setEnabled(enabled, client: $0) }
                }

                ActionChip(title: vm.task.isPinnedTask ? "取消置顶" : "置顶",
                           symbol: "pin",
                           tint: .orange) {
                    let pinned = !vm.task.isPinnedTask
                    act(pinned ? "已置顶" : "已取消置顶") { try await vm.setPinned(pinned, client: $0) }
                }
            }
        }
    }

    private var logCard: some View {
        Card {
            HStack(spacing: 8) {
                Text("运行日志")
                    .font(.system(size: 14, weight: .semibold))
                if let status = vm.logStatusText {
                    StatusPill(text: status,
                               color: status == "运行中" ? .green : .secondary)
                }
                Spacer()
                if vm.isLoadingLog {
                    ProgressView().scaleEffect(0.7)
                }
                Toggle("自动刷新", isOn: $vm.autoRefresh)
                    .labelsHidden()
                    .scaleEffect(0.8)
                    .frame(width: 44)
            }

            let preview = vm.logText.tailLines(logPreviewLines)

            Text(preview.text)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(.tertiarySystemFill),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(spacing: 14) {
                Button {
                    showFullLog = true
                } label: {
                    Label("查看完整日志", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                Button {
                    UIPasteboard.general.string = vm.logText
                    session.show("日志已复制")
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                Spacer()
            }
            .font(.system(size: 12, weight: .medium))
        }
    }

    private var metaCard: some View {
        Card {
            Text("其他信息")
                .font(.system(size: 14, weight: .semibold))
            InfoRow(label: "任务 ID", value: String(vm.task.id), mono: true)
            InfoRow(label: "日志名", value: vm.task.logName?.isEmpty == false ? vm.task.logName! : "默认")
            if let workDir = vm.task.workDir, !workDir.isEmpty {
                InfoRow(label: "工作目录", value: workDir, mono: true)
            }
            if let before = vm.task.taskBefore, !before.isEmpty {
                InfoRow(label: "前置脚本", value: before, mono: true)
            }
            if let after = vm.task.taskAfter, !after.isEmpty {
                InfoRow(label: "后置脚本", value: after, mono: true)
            }
            InfoRow(label: "多实例", value: (vm.task.allowMultipleInstances ?? 0) == 1 ? "允许" : "不允许")
            if let extras = vm.task.extraSchedules, !extras.isEmpty {
                InfoRow(label: "附加规则",
                        value: extras.compactMap { $0.schedule }.joined(separator: "\n"),
                        mono: true)
            }
            if vm.task.isSystemTask {
                InfoRow(label: "类型", value: "系统任务")
            }
        }
    }

    // MARK: 动作

    private func act(_ label: String, _ action: @escaping (APIClient) async throws -> Void) {
        guard !vm.isActing else { return }
        Task {
            guard let client = session.client else { return }
            vm.isActing = true
            defer { vm.isActing = false }
            do {
                try await action(client)
                session.show(label)
            } catch {
                session.handle(error, context: label)
            }
        }
    }
}
