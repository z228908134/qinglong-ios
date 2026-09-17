//
//  CronListViewModel.swift
//  任务列表：分页加载 + 服务端搜索 + 批量动作
//

import Foundation
import SwiftUI

@MainActor
final class CronListViewModel: ObservableObject {

    @Published var tasks: [CronTask] = []
    @Published var searchText = ""
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?

    @Published private(set) var total = 0
    private(set) var hasLoadedOnce = false

    private let pageSize = 20
    private var page = 1

    var summary: String {
        if total == 0 { return "共 0 个任务" }
        let running = tasks.filter { $0.effectiveStatus == .running }.count
        let disabled = tasks.filter { $0.isDisabledTask }.count
        return "共 \(total) 个任务 · 本页运行 \(running) · 禁用 \(disabled)"
    }

    // MARK: 加载

    func refresh(client: APIClient) async {
        if tasks.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            let result = try await client.crons(search: searchText, page: 1, size: pageSize)
            tasks = result.data
            total = result.total
            page = 1
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        hasLoadedOnce = true
    }

    /// 动作执行后刷新，但保留用户已经加载出来的条数，避免列表突然缩短、位置跳动
    func reloadCurrentWindow(client: APIClient) async {
        let size = max(pageSize, tasks.count)
        do {
            let result = try await client.crons(search: searchText, page: 1, size: size)
            tasks = result.data
            total = result.total
            page = max(1, Int(ceil(Double(size) / Double(pageSize))))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreIfNeeded(current task: CronTask, client: APIClient) async {
        guard tasks.last?.id == task.id, tasks.count < total, !isLoadingMore, !isLoading else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let nextPage = page + 1
            let result = try await client.crons(search: searchText, page: nextPage, size: pageSize)
            let existing = Set(tasks.map(\.id))
            tasks.append(contentsOf: result.data.filter { !existing.contains($0.id) })
            total = result.total
            page = nextPage
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: 动作

    func run(_ task: CronTask, client: APIClient) async throws {
        try await client.runCrons([task.id])
    }

    func stop(_ task: CronTask, client: APIClient) async throws {
        try await client.stopCrons([task.id])
    }

    func setEnabled(_ task: CronTask, enabled: Bool, client: APIClient) async throws {
        if enabled {
            try await client.enableCrons([task.id])
        } else {
            try await client.disableCrons([task.id])
        }
    }

    func setPinned(_ task: CronTask, pinned: Bool, client: APIClient) async throws {
        if pinned {
            try await client.pinCrons([task.id])
        } else {
            try await client.unpinCrons([task.id])
        }
    }

    func delete(_ task: CronTask, client: APIClient) async throws {
        try await client.deleteCrons([task.id])
    }
}
