//
//  LogFilesView.swift
//  面板日志文件浏览：目录 → 文件 → 内容
//

import SwiftUI

extension LogNode {
    /// 文件所在目录的相对路径（用于 /api/logs/detail 的 path 参数）
    var directoryPath: String {
        let parts = key.split(separator: "/")
        guard parts.count > 1 else { return "" }
        return parts.dropLast().joined(separator: "/")
    }
}

struct LogFilesView: View {

    @EnvironmentObject private var session: SessionStore

    @State private var nodes: [LogNode] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && nodes.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if nodes.isEmpty {
                ScrollView {
                    if let errorMessage {
                        ErrorBanner(message: errorMessage) { Task { await load() } }
                            .padding(.top, 12)
                    }
                    EmptyStateView(symbol: "doc.text.magnifyingglass",
                                   title: "还没有日志文件",
                                   message: "任务运行一次之后，这里会出现日志")
                }
            } else {
                LogDirectoryList(title: "日志文件", nodes: nodes)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("日志文件")
        .refreshable { await load() }
        .task {
            if nodes.isEmpty { await load() }
        }
    }

    private func load() async {
        guard let client = session.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            nodes = try await client.logTree()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 目录列表（根目录与子目录共用，靠 NavigationLink 递归下钻）
struct LogDirectoryList: View {

    let title: String
    let nodes: [LogNode]

    var body: some View {
        List {
            ForEach(nodes) { node in
                if node.isDirectory {
                    NavigationLink {
                        LogDirectoryList(title: node.title, nodes: node.children ?? [])
                    } label: {
                        LogNodeLabel(node: node)
                    }
                } else {
                    NavigationLink {
                        LogFileDetailView(node: node)
                    } label: {
                        LogNodeLabel(node: node)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LogNodeLabel: View {
    let node: LogNode

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: node.isDirectory ? "folder.fill" : "doc.text")
                .font(.system(size: 14))
                .foregroundStyle(node.isDirectory ? Color.accentColor : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(node.title)
                    .font(.system(size: 14, weight: node.isDirectory ? .semibold : .regular))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let size = QLFormat.byteSize(node.size) {
                        Text(size)
                    }
                    if let created = node.createTime {
                        Text(QLFormat.short(Date(timeIntervalSince1970: created / 1000)))
                    }
                    if node.isDirectory {
                        Text("\((node.children ?? []).count) 项")
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// 单个日志文件内容
struct LogFileDetailView: View {

    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    let node: LogNode

    @State private var content = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ScrollView {
                    ErrorBanner(message: errorMessage) { Task { await load() } }
                        .padding(.top, 12)
                }
            } else {
                LogTextDetailView(title: node.title, content: content)
            }
        }
        .navigationTitle(node.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        Task { await load() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("删除该日志", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await load() }
        .alert("确认删除日志文件？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) {
                Task { await deleteFile() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("文件将从面板磁盘上移除，无法恢复。")
        }
    }

    private func load() async {
        guard let client = session.client else { return }
        isLoading = content.isEmpty
        defer { isLoading = false }
        do {
            let raw = try await client.logFileContent(path: node.directoryPath, file: node.title)
            content = raw.strippingANSI
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteFile() async {
        guard let client = session.client else { return }
        do {
            try await client.deleteLogFile(path: node.directoryPath, file: node.title)
            session.show("日志文件已删除")
            dismiss()
        } catch {
            session.handle(error, context: "删除失败")
        }
    }
}
