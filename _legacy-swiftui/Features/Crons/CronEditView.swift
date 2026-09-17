//
//  CronEditView.swift
//  新建 / 编辑定时任务。字段严格对齐后端 commonCronSchema，避免 Joi 拒绝未知字段。
//

import SwiftUI

struct CronEditView: View {

    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    private let original: CronTask?
    private let onSaved: () -> Void

    @State private var name = ""
    @State private var schedule = "0 0 * * *"
    @State private var command = ""
    @State private var labelsText = ""
    @State private var taskBefore = ""
    @State private var taskAfter = ""
    @State private var logName = ""
    @State private var workDir = ""
    @State private var allowMultiple = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(task: CronTask?, onSaved: @escaping () -> Void = {}) {
        self.original = task
        self.onSaved = onSaved
    }

    private var isEditing: Bool { original != nil }

    private var trimmedCommand: String {
        command.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedSchedule: String {
        schedule.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nextRunPreview: String? {
        guard !trimmedSchedule.isEmpty else { return nil }
        guard let next = CronSchedule(trimmedSchedule)?.nextFireDate() else {
            return "无法解析这条规则，请检查格式（面板同样会校验）"
        }
        return "\(QLFormat.absolute(next))（\(QLFormat.countdown(to: next))）"
    }

    private var canSave: Bool {
        !trimmedCommand.isEmpty && !trimmedSchedule.isEmpty && !isSaving
    }

    private let presets: [(label: String, expression: String)] = [
        ("每分钟", "* * * * *"),
        ("每 5 分钟", "*/5 * * * *"),
        ("每 15 分钟", "*/15 * * * *"),
        ("每 30 分钟", "*/30 * * * *"),
        ("每小时整点", "0 * * * *"),
        ("每天 0 点", "0 0 * * *"),
        ("每天 8 点", "0 8 * * *"),
        ("每周一 9 点", "0 9 * * 1"),
        ("每月 1 号 0 点", "0 0 1 * *"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("任务名称", text: $name)
                    HStack {
                        TextField("定时规则，如 0 8 * * *", text: $schedule)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(size: 14, design: .monospaced))
                        Menu {
                            ForEach(presets.indices, id: \.self) { index in
                                Button(presets[index].label) { schedule = presets[index].expression }
                            }
                        } label: {
                            Image(systemName: "wand.and.stars")
                        }
                    }
                    if let nextRunPreview {
                        Text(nextRunPreview)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("基本信息")
                } footer: {
                    Text("支持标准 5 段 cron；也支持面板的 @once / @boot 写法。")
                }

                Section("执行命令") {
                    TextEditor(text: $command)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(minHeight: 96)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("标签") {
                    TextField("用英文逗号分隔，例如 日常,签到", text: $labelsText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    TextField("前置脚本（可选）", text: $taskBefore, axis: .vertical)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(2...5)
                    TextField("后置脚本（可选）", text: $taskAfter, axis: .vertical)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(2...5)
                    TextField("日志名（可选，留空用默认）", text: $logName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("工作目录（可选）", text: $workDir)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("允许同时运行多个实例", isOn: $allowMultiple)
                } header: {
                    Text("高级选项")
                } footer: {
                    Text("日志名不要填 /dev/null 以外的绝对路径，面板只允许日志目录内的路径。")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isEditing ? "编辑任务" : "新建任务")
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
            .onAppear(perform: fillFromOriginal)
        }
    }

    private func fillFromOriginal() {
        guard let original else { return }
        name = original.name ?? ""
        schedule = original.schedule ?? ""
        command = original.command ?? ""
        labelsText = (original.labels ?? []).joined(separator: ",")
        taskBefore = original.taskBefore ?? ""
        taskAfter = original.taskAfter ?? ""
        logName = original.logName ?? ""
        workDir = original.workDir ?? ""
        allowMultiple = (original.allowMultipleInstances ?? 0) == 1
    }

    private func save() async {
        guard let client = session.client else { return }
        guard canSave else { return }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let labels = labelsText
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let payload = CronPayload(
            id: original?.id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : name.trimmingCharacters(in: .whitespacesAndNewlines),
            command: trimmedCommand,
            schedule: trimmedSchedule,
            labels: labels.isEmpty ? nil : labels,
            taskBefore: taskBefore.isEmpty ? nil : taskBefore,
            taskAfter: taskAfter.isEmpty ? nil : taskAfter,
            logName: logName.isEmpty ? nil : logName,
            workDir: workDir.isEmpty ? nil : workDir,
            allowMultipleInstances: allowMultiple ? 1 : 0
        )

        do {
            if isEditing {
                try await client.updateCron(payload)
            } else {
                try await client.createCron(payload)
            }
            session.show(isEditing ? "任务已保存" : "任务已创建")
            onSaved()
            dismiss()
        } catch {
            if let apiError = error as? QLAPIError {
                errorMessage = apiError.localizedDescription
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }
}
