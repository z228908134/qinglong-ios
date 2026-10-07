import SwiftUI

// MARK: - 脚本浏览 / 搜索

/// 脚本管理页。
///
/// 关于搜索的实现依据：青龙的 `GET /open/scripts` **不接受搜索参数**（只认 `path`），
/// 但当 `path` 为空时它会走 `readDirs` **递归返回整棵脚本树**。
/// 因此根页面拿到的列表本身就是全量索引，搜索完全可以在本地完成，不需要额外接口。
struct ScriptBrowserView: View {

    var title: String = "脚本管理"
    var path: String = ""

    @EnvironmentObject private var store: PanelStore

    @State private var nodes: [FileNode] = []
    @State private var isLoading = true
    @State private var searchText = ""

    private var isRoot: Bool {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
    }

    private var keyword: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// 当前应显示的条目。
    ///
    /// - 有搜索词：在（根页面即全量的）列表里同时匹配文件名与所在路径，只保留文件；
    /// - 无搜索词：根页面只展示第一层，子目录展示该层全部。
    private var visibleNodes: [FileNode] {
        if !keyword.isEmpty {
            return nodes.filter { node in
                guard !node.isDirectory else { return false }
                return node.title.lowercased().contains(keyword)
                    || fullPath(node).lowercased().contains(keyword)
            }
        }
        guard isRoot else { return nodes }
        let firstLevel = nodes.filter { isFirstLevel($0) }
        // `path` 字段在不同面板版本里语义略有出入，判断失败时退回完整列表，避免页面空白
        return firstLevel.isEmpty ? nodes : firstLevel
    }

    /// 相对完整路径，例如 `jd_scripts/utils.js`。
    ///
    /// 面板返回的 `value` 字段是**父目录**，`title` 才是文件名，
    /// 所以打开文件时必须把两者拼起来当作 `path` 传回去。
    private func fullPath(_ node: FileNode) -> String {
        node.relativeFullPath
    }

    private func isFirstLevel(_ node: FileNode) -> Bool {
        node.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
    }

    var body: some View {
        ZStack {
            Theme.groupedBackground.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                SearchField(text: $searchText, placeholder: "搜索脚本，支持文件名与路径")
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                content
            }
        }
        .navigationBarTitle(title, displayMode: .inline)
        .onAppear(perform: load)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            LoadingOverlay(title: "正在读取脚本目录…")
        } else if visibleNodes.isEmpty {
            if keyword.isEmpty {
                EmptyStateView(
                    icon: "square.and.pencil",
                    title: "这个目录是空的",
                    message: "可以通过订阅拉取脚本仓库，或直接在面板网页端上传脚本文件。"
                )
            } else {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "没有匹配的脚本",
                    message: "换个关键词试试。搜索会同时匹配文件名和所在目录。"
                )
            }
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    let items = visibleNodes
                    ForEach(items.indices, id: \.self) { index in
                        row(for: items[index], showPath: !keyword.isEmpty)

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

    @ViewBuilder
    private func row(for node: FileNode, showPath: Bool) -> some View {
        if node.isDirectory {
            NavigationLink(destination: ScriptBrowserView(title: node.title, path: node.relativeFullPath)) {
                rowContent(node, showPath: false)
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            // 关键修复：path 传文件真实的父目录，而不是当前浏览目录。
            // 原先在根页面传空 path，导致子目录里的脚本读不出来。
            NavigationLink(destination: ScriptEditorView(path: node.directoryPath, node: node)) {
                rowContent(node, showPath: showPath)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private func rowContent(_ node: FileNode, showPath: Bool) -> some View {
        HStack(spacing: 10) {
            IconTile(
                icon: node.isDirectory ? "folder.fill" : "doc.plaintext",
                tint: node.isDirectory ? Theme.warning : scriptTint(node),
                size: 28
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(node.title)
                    .font(.system(size: Theme.font(13.5)))
                    .foregroundColor(Theme.primaryText)
                    .lineLimit(1)

                Text(showPath ? fullPath(node) : (node.isDirectory ? "目录" : node.fileExtension.uppercased()))
                    .font(.system(size: Theme.font(11)))
                    .foregroundColor(Theme.tertiaryText)
                    .lineLimit(1)
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

    /// 文件所在的父目录（面板 `GET /scripts/detail` 的 path 参数）
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
                    onSave: { edited in save(edited) },
                    // 用文字按钮取代小图标，避免用户找不到编辑入口
                    editLabel: "编辑"
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
