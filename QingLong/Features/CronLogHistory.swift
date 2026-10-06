import SwiftUI

// MARK: - 任务日志历史

/// 列出某任务的历史日志文件（面板 `GET /api/crons/:id/logs`，最新在前）。
struct CronLogHistoryView: View {

    let cron: Cron
    let files: [String]

    var body: some View {
        ZStack {
            Theme.groupedBackground.edgesIgnoringSafeArea(.all)

            if files.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(Theme.tertiaryText)
                    Text("没有历史日志")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.primaryText)
                    Text("任务每次执行都会在面板上留下一份日志文件。")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.secondaryText)
                }
                .padding(.horizontal, 32)
            } else {
                List {
                    ForEach(files, id: \.self) { name in
                        NavigationLink(
                            destination: CronLogFileView(
                                cron: cron,
                                fileName: name,
                                logPath: cron.logPath ?? ""
                            )
                        ) {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 14))
                                    .foregroundColor(Theme.info)
                                Text(name)
                                    .font(.system(size: 12.5, design: .monospaced))
                                    .foregroundColor(Theme.primaryText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
        }
        .navigationTitle("日志历史")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 单个历史日志

/// 读取单个历史日志文件（面板 `GET /api/logs/detail?path=<目录>&file=<文件名>`）。
struct CronLogFileView: View {

    let cron: Cron
    let fileName: String
    let logPath: String

    @State private var text = ""
    @State private var isLoading = true
    @State private var errorText = ""

    var body: some View {
        ZStack {
            Theme.groupedBackground.edgesIgnoringSafeArea(.all)

            if isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("正在读取日志…")
                        .font(.system(size: 12.5))
                        .foregroundColor(Theme.secondaryText)
                }
            } else if !errorText.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 26))
                        .foregroundColor(Theme.warning)
                    Text(errorText)
                        .font(.system(size: 12.5))
                        .foregroundColor(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    Text(text.isEmpty ? "（日志为空）" : text)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(Theme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
            }
        }
        .navigationTitle(fileName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Task { await load() } }
    }

    private func load() async {
        isLoading = true
        errorText = ""
        do {
            let response = try await APIClient.shared.send(
                .get,
                "logs/detail",
                query: [("path", logPath), ("file", fileName), ("tail", "true")],
                as: String.self
            )
            text = LogText.cleanAnsi(response.data ?? "（日志为空）")
        } catch {
            errorText = "读取失败：该日志文件可能已被面板清理。"
        }
        isLoading = false
    }
}
