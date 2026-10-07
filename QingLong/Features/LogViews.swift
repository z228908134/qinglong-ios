import SwiftUI

// MARK: - 日志目录浏览

/// 面板的 `/open/logs` 会一次性返回完整的递归目录树，因此这里只需请求一次，
/// 之后在本地逐层展开，不再产生额外的网络往返。
struct LogBrowserView: View {

    var title: String = "日志文件"
    var path: String = ""
    var presetNodes: [FileNode]? = nil

    @EnvironmentObject private var store: PanelStore

    @State private var nodes: [FileNode] = []
    @State private var isLoading = true

    var body: some View {
        ZStack {
            Theme.groupedBackground.edgesIgnoringSafeArea(.all)

            if isLoading {
                LoadingOverlay(title: "正在读取日志目录…")
            } else if nodes.isEmpty {
                EmptyStateView(
                    icon: "doc.text",
                    title: "这里还没有日志",
                    message: "任务执行后会按任务名生成日志文件，运行一次任务即可看到。"
                )
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        let items = nodes
                        ForEach(items.indices, id: \.self) { index in
                            row(for: items[index])

                            if index < items.count - 1 {
                                Divider()
                                    .background(Theme.separator)
                                    .padding(.leading, 52)
                            }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardBackground))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        .navigationBarTitle(title, displayMode: .inline)
        .onAppear(perform: load)
        .onChange(of: presetNodes) { _ in load() }
    }

    @ViewBuilder
    private func row(for node: FileNode) -> some View {
        if node.isDirectory {
            NavigationLink(destination: LogBrowserView(title: node.title, path: node.relativeFullPath, presetNodes: node.children)) {
                rowContent(node)
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            NavigationLink(destination: LogDetailView(path: node.directoryPath, node: node)) {
                rowContent(node)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private func rowContent(_ node: FileNode) -> some View {
        HStack(spacing: 10) {
            IconTile(
                icon: node.isDirectory ? "folder.fill" : "doc.text.fill",
                tint: node.isDirectory ? Theme.warning : Theme.info,
                size: 28
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(node.title)
                    .font(.system(size: Theme.font(13.5)))
                    .foregroundColor(Theme.primaryText)
                    .lineLimit(1)
                if node.isDirectory {
                    Text("\(node.children.count) 项")
                        .font(.system(size: Theme.font(11)))
                        .foregroundColor(Theme.tertiaryText)
                }
            }

            Spacer(minLength: 6)

            if node.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: Theme.font(12)))
                    .foregroundColor(Theme.tertiaryText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func load() {
        if let preset = presetNodes {
            nodes = preset
            isLoading = false
            return
        }
        isLoading = true
        Task {
            nodes = await store.listLogs()
            isLoading = false
        }
    }
}

// MARK: - 日志内容

struct LogDetailView: View {

    let path: String
    let node: FileNode

    @EnvironmentObject private var store: PanelStore

    @State private var text = ""
    @State private var isLoading = true

    var body: some View {
        ZStack {
            Theme.groupedBackground.edgesIgnoringSafeArea(.all)

            TextDetailView(
                title: node.title,
                subtitle: path.isEmpty ? "日志根目录" : path,
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
        text = await store.readLog(path: path, file: node.title)
        isLoading = false
    }
}
