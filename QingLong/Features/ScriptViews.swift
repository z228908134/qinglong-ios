import SwiftUI

// MARK: - 脚本目录浏览

struct ScriptBrowserView: View {

    var title: String = "脚本管理"
    var path: String = ""

    @EnvironmentObject private var store: PanelStore

    @State private var nodes: [FileNode] = []
    @State private var isLoading = true

    var body: some View {
        ZStack {
            Theme.groupedBackground.edgesIgnoringSafeArea(.all)

            if isLoading {
                LoadingOverlay(title: "正在读取脚本目录…")
            } else if nodes.isEmpty {
                EmptyStateView(
                    icon: "square.and.pencil",
                    title: "这个目录是空的",
                    message: "可以通过订阅拉取脚本仓库，或直接在面板网页端上传脚本文件。"
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
    }

    @ViewBuilder
    private func row(for node: FileNode) -> some View {
        if node.isDirectory {
            NavigationLink(destination: ScriptBrowserView(title: node.title, path: node.path)) {
                rowContent(node)
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            NavigationLink(destination: ScriptEditorView(path: path, node: node)) {
                rowContent(node)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private func rowContent(_ node: FileNode) -> some View {
        HStack(spacing: 10) {
            IconTile(
                icon: node.isDirectory ? "folder.fill" : "doc.plaintext",
                tint: node.isDirectory ? Theme.warning : scriptTint(node),
                size: 28
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(node.title)
                    .font(.system(size: 13.5))
                    .foregroundColor(Theme.primaryText)
                    .lineLimit(1)
                Text(node.isDirectory ? "目录" : node.fileExtension.uppercased())
                    .font(.system(size: 11))
                    .foregroundColor(Theme.tertiaryText)
            }

            Spacer(minLength: 6)

            if node.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.tertiaryText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func scriptTint(_ node: FileNode) -> Color {
        switch node.fileExtension {
        case "js": return Theme.accent
        case "py": return Theme.info
        case "sh": return Theme.warning
        case "ts": return Theme.warning
        default: return Theme.neutral
        }
    }

    private func load() {
        isLoading = true
        Task {
            nodes = await store.listScripts(path: path)
            isLoading = false
        }
    }
}

// MARK: - 脚本查看 / 编辑

struct ScriptEditorView: View {

    let path: String
    let node: FileNode

    @EnvironmentObject private var store: PanelStore

    @State private var text = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var savedHint = false

    var body: some View {
        ZStack {
            Theme.groupedBackground.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                if savedHint {
                    BannerView(text: "已保存。若任务已在运行中，改动会在下次执行时生效。", tone: .success)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                TextDetailView(
                    title: node.title,
                    subtitle: path.isEmpty ? "脚本根目录" : path,
                    text: text,
                    isLoading: isLoading,
                    onRefresh: { Task { await reload() } },
                    onSave: { edited in
                        save(edited)
                    }
                )
            }
        }
        .onAppear { Task { await reload() } }
    }

    private func reload() async {
        isLoading = true
        text = await store.readScript(path: path, file: node.title)
        isLoading = false
    }

    private func save(_ content: String) {
        isSaving = true
        Task {
            let ok = await store.saveScript(path: path, file: node.title, content: content)
            isSaving = false
            if ok {
                text = content
                savedHint = true
            }
        }
    }
}
