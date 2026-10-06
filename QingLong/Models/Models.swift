import Foundation
import SwiftUI

/// 状态色语义。具体颜色在 Components.swift 里映射，模型层只表达"含义"。
enum StatusTone {
    case success
    case info
    case warning
    case danger
    case muted
}

// MARK: - 定时任务

/// 任务运行状态。数值与面板 `CrontabStatus` 枚举一一对应。
enum CronRunStatus: Int {
    case running = 0
    case idle = 1
    case disabled = 2
    case queued = 3

    var title: String {
        switch self {
        case .running: return "运行中"
        case .idle: return "已就绪"
        case .disabled: return "已禁用"
        case .queued: return "排队中"
        }
    }

    var tone: StatusTone {
        switch self {
        case .running: return .info
        case .idle: return .success
        case .disabled: return .muted
        case .queued: return .warning
        }
    }

    /// 是否处于"可以停止"的状态
    var isActive: Bool {
        self == .running || self == .queued
    }
}

/// 附加调度规则（`extra_schedules`）
struct ExtraSchedule: Codable {
    var schedule: String?
}

struct Cron: Codable, Identifiable {
    var id: Int = 0
    var name: String?
    var command: String = ""
    var schedule: String?
    var timestamp: String?
    var status: Int?
    var isSystem: Int?
    var pid: Int?
    var isDisabled: Int?
    var logPath: String?
    var isPinned: Int?
    var labels: [String] = []
    var lastRunningTime: Int?
    var lastExecutionTime: Int?
    var subId: Int?
    var taskBefore: String?
    var taskAfter: String?
    var logName: String?
    var allowMultipleInstances: Int?
    var workDir: String?
    var extraSchedules: [ExtraSchedule]?

    enum CodingKeys: String, CodingKey {
        case id, name, command, schedule, timestamp, status, pid, labels
        case isSystem, isDisabled, isPinned
        case logPath = "log_path"
        case lastRunningTime = "last_running_time"
        case lastExecutionTime = "last_execution_time"
        case subId = "sub_id"
        case taskBefore = "task_before"
        case taskAfter = "task_after"
        case logName = "log_name"
        case allowMultipleInstances = "allow_multiple_instances"
        case workDir = "work_dir"
        case extraSchedules = "extra_schedules"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexInt(.id) ?? 0
        name = c.flexString(.name)
        command = c.flexString(.command) ?? ""
        schedule = c.flexString(.schedule)
        timestamp = c.flexString(.timestamp)
        status = c.flexInt(.status)
        isSystem = c.flexInt(.isSystem)
        pid = c.flexInt(.pid)
        isDisabled = c.flexInt(.isDisabled)
        logPath = c.flexString(.logPath)
        isPinned = c.flexInt(.isPinned)
        labels = c.flexStringArray(.labels) ?? []
        lastRunningTime = c.flexInt(.lastRunningTime)
        lastExecutionTime = c.flexInt(.lastExecutionTime)
        subId = c.flexInt(.subId)
        taskBefore = c.flexString(.taskBefore)
        taskAfter = c.flexString(.taskAfter)
        logName = c.flexString(.logName)
        allowMultipleInstances = c.flexInt(.allowMultipleInstances)
        workDir = c.flexString(.workDir)
        extraSchedules = try? c.decodeIfPresent([ExtraSchedule].self, forKey: .extraSchedules)
    }

    init() {}

    // MARK: 派生属性

    var runStatus: CronRunStatus {
        CronRunStatus(rawValue: status ?? 1) ?? .idle
    }

    var displayName: String {
        if let name = name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return name
        }
        return command
    }

    var isPinnedTask: Bool { (isPinned ?? 0) == 1 }

    var isDisabledTask: Bool { (isDisabled ?? 0) == 1 }

    var isSubscribed: Bool { (subId ?? 0) > 0 }

    /// 最近一次执行时间的可读文本
    var lastRunText: String {
        guard let stamp = lastExecutionTime, stamp > 0 else { return "从未执行" }
        return Date(timeIntervalSince1970: TimeInterval(stamp)).qlRelativeText
    }

    /// 任务类型的猜测（仅用于图标展示，判断失败不影响功能）
    var kindIcon: String {
        let text = command.lowercased()
        if text.contains(".py") { return "chevron.left.forwardslash.chevron.right" }
        if text.contains(".js") || text.contains(".ts") { return "curlybraces" }
        if text.contains(".sh") { return "terminal" }
        return "doc.text"
    }
}

/// 任务新建 / 更新的请求体。
///
/// 只包含面板 Joi 校验允许的字段——多传未知字段会被直接拒绝（400）。
/// 可选字段为 nil 时不会出现在请求体里。
struct CronPayload: Encodable {
    var id: Int?
    var name: String?
    var command: String
    var schedule: String
    var labels: [String]?
    var subId: Int?
    var taskBefore: String?
    var taskAfter: String?
    var logName: String?
    var workDir: String?
    var allowMultipleInstances: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, command, schedule, labels
        case subId = "sub_id"
        case taskBefore = "task_before"
        case taskAfter = "task_after"
        case logName = "log_name"
        case workDir = "work_dir"
        case allowMultipleInstances = "allow_multiple_instances"
    }

    init(
        id: Int? = nil,
        name: String?,
        command: String,
        schedule: String,
        labels: [String]? = nil,
        subId: Int? = nil,
        taskBefore: String? = nil,
        taskAfter: String? = nil,
        logName: String? = nil,
        workDir: String? = nil,
        allowMultipleInstances: Int? = nil
    ) {
        self.id = id
        self.name = Self.clean(name)
        self.command = command
        self.schedule = schedule
        self.labels = (labels?.isEmpty == false) ? labels : nil
        self.subId = subId
        self.taskBefore = Self.clean(taskBefore)
        self.taskAfter = Self.clean(taskAfter)
        self.logName = Self.clean(logName)
        self.workDir = Self.clean(workDir)
        self.allowMultipleInstances = allowMultipleInstances
    }

    private static func clean(_ value: String?) -> String? {
        guard let value = value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}

// MARK: - 环境变量

struct QLEnv: Codable, Identifiable {
    var id: Int = 0
    var name: String = ""
    var value: String = ""
    var remarks: String = ""
    var status: Int?
    var position: Double?
    var isPinned: Int?
    var labels: [String] = []
    var timestamp: String?

    enum CodingKeys: String, CodingKey {
        case id, name, value, remarks, status, position, labels, timestamp
        case isPinned
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexInt(.id) ?? 0
        name = c.flexString(.name) ?? ""
        value = c.flexString(.value) ?? ""
        remarks = c.flexString(.remarks) ?? ""
        status = c.flexInt(.status)
        position = c.flexDouble(.position)
        isPinned = c.flexInt(.isPinned)
        labels = c.flexStringArray(.labels) ?? []
        timestamp = c.flexString(.timestamp)
    }

    init() {}

    init(id: Int, name: String, value: String, remarks: String = "") {
        self.id = id
        self.name = name
        self.value = value
        self.remarks = remarks
    }

    var isDisabledEnv: Bool { (status ?? 0) == 1 }
    var isPinnedEnv: Bool { (isPinned ?? 0) == 1 }
    var statusTitle: String { isDisabledEnv ? "已禁用" : "已启用" }
    var statusTone: StatusTone { isDisabledEnv ? .muted : .success }
}

/// 新建环境变量：面板要求提交"对象数组"。
struct EnvCreatePayload: Encodable {
    var name: String
    var value: String
    var remarks: String?
    var labels: [String]?
}

/// 更新环境变量：面板要求提交"单个对象"，且必须带 id。
struct EnvUpdatePayload: Encodable {
    var id: Int
    var name: String
    var value: String
    var remarks: String?
    var labels: [String]?
}

// MARK: - 订阅

struct SubscriptionInterval: Codable {
    var type: String?
    var value: Double?
}

struct QLSubscription: Codable, Identifiable {
    var id: Int = 0
    var name: String?
    var alias: String = ""
    var type: String?
    var scheduleType: String?
    var schedule: String?
    var intervalSchedule: SubscriptionInterval?
    var url: String?
    var whitelist: String?
    var blacklist: String?
    var dependences: String?
    var branch: String?
    var status: Int?
    var pid: Int?
    var isDisabled: Int?
    var logPath: String?
    var command: String?
    var autoAddCron: Int?
    var autoDelCron: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, alias, type, schedule, url, whitelist, blacklist,
             dependences, branch, status, pid, command
        case scheduleType = "schedule_type"
        case intervalSchedule = "interval_schedule"
        case isDisabled = "is_disabled"
        case logPath = "log_path"
        case autoAddCron, autoDelCron
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexInt(.id) ?? 0
        name = c.flexString(.name)
        alias = c.flexString(.alias) ?? c.flexString(.name) ?? ""
        type = c.flexString(.type)
        scheduleType = c.flexString(.scheduleType)
        schedule = c.flexString(.schedule)
        intervalSchedule = try? c.decodeIfPresent(SubscriptionInterval.self, forKey: .intervalSchedule)
        url = c.flexString(.url)
        whitelist = c.flexString(.whitelist)
        blacklist = c.flexString(.blacklist)
        dependences = c.flexString(.dependences)
        branch = c.flexString(.branch)
        status = c.flexInt(.status)
        pid = c.flexInt(.pid)
        isDisabled = c.flexInt(.isDisabled)
        logPath = c.flexString(.logPath)
        command = c.flexString(.command)
        autoAddCron = c.flexInt(.autoAddCron)
        autoDelCron = c.flexInt(.autoDelCron)
    }

    init() {}

    var runStatus: CronRunStatus {
        CronRunStatus(rawValue: status ?? 1) ?? .idle
    }

    var displayName: String {
        if !alias.isEmpty { return alias }
        if let name = name, !name.isEmpty { return name }
        return "订阅 #\(id)"
    }

    var typeTitle: String {
        switch type {
        case "public-repo": return "公开仓库"
        case "private-repo": return "私有仓库"
        case "file": return "单文件"
        default: return type ?? "未知类型"
        }
    }

    var scheduleDescription: String {
        if scheduleType == "interval", let interval = intervalSchedule {
            let unit: String
            switch interval.type {
            case "seconds": unit = "秒"
            case "minutes": unit = "分钟"
            case "hours": unit = "小时"
            case "days": unit = "天"
            default: unit = interval.type ?? ""
            }
            return "每 \(Int(interval.value ?? 0)) \(unit)"
        }
        return schedule ?? "未设置"
    }
}

// MARK: - 依赖

enum DependenceKind: Int {
    case nodejs = 0
    case python3 = 1
    case linux = 2

    var title: String {
        switch self {
        case .nodejs: return "NodeJs"
        case .python3: return "Python3"
        case .linux: return "Linux"
        }
    }

    var shortTitle: String {
        switch self {
        case .nodejs: return "JS"
        case .python3: return "PY"
        case .linux: return "LNX"
        }
    }
}

enum DependenceStatus: Int {
    case installing = 0
    case installed = 1
    case installFailed = 2
    case removing = 3
    case removed = 4
    case removeFailed = 5
    case queued = 6
    case cancelled = 7

    var title: String {
        switch self {
        case .installing: return "安装中"
        case .installed: return "已安装"
        case .installFailed: return "安装失败"
        case .removing: return "删除中"
        case .removed: return "已删除"
        case .removeFailed: return "删除失败"
        case .queued: return "排队中"
        case .cancelled: return "已取消"
        }
    }

    var tone: StatusTone {
        switch self {
        case .installed: return .success
        case .installing, .removing, .queued: return .info
        case .installFailed, .removeFailed: return .danger
        case .removed, .cancelled: return .muted
        }
    }

    var isBusy: Bool {
        self == .installing || self == .removing || self == .queued
    }
}

struct QLDependence: Codable, Identifiable {
    var id: Int = 0
    var name: String = ""
    var type: Int?
    var status: Int?
    var remark: String = ""
    var log: [String] = []
    var timestamp: String?

    enum CodingKeys: String, CodingKey {
        case id, name, type, status, remark, log, timestamp
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexInt(.id) ?? 0
        name = c.flexString(.name) ?? ""
        type = c.flexInt(.type)
        status = c.flexInt(.status)
        remark = c.flexString(.remark) ?? ""
        log = c.flexStringArray(.log) ?? []
        timestamp = c.flexString(.timestamp)
    }

    init() {}

    var kind: DependenceKind { DependenceKind(rawValue: type ?? 0) ?? .nodejs }
    var runState: DependenceStatus { DependenceStatus(rawValue: status ?? 6) ?? .queued }
}

/// 依赖新建请求体：面板同样要求"对象数组"。
struct DependenceCreatePayload: Encodable {
    var name: String
    var type: Int
    var remark: String?
}

// MARK: - 日志与脚本目录树

/// 日志 / 脚本目录树节点。
///
/// 面板 `/open/logs`、`/open/scripts` 返回的是递归目录结构，
/// 但不同版本的字段名略有差异，这里做统一归一化。
struct FileNode: Identifiable, Hashable {
    var id: String
    var title: String
    /// 相对路径（部分响应里叫 value / path / key）
    var path: String
    var isDirectory: Bool
    var children: [FileNode]

    var fileExtension: String {
        (title as NSString).pathExtension.lowercased()
    }

    /// 从面板返回的任意结构里解析出目录树。
    static func parseList(_ value: JSONValue?) -> [FileNode] {
        guard let list = value?.arrayValue else {
            return parseListFromSingle(value)
        }
        return list.compactMap { parseNode($0) }
    }

    private static func parseListFromSingle(_ value: JSONValue?) -> [FileNode] {
        guard let node = value.flatMap({ parseNode($0) }) else { return [] }
        return [node]
    }

    static func parseNode(_ value: JSONValue) -> FileNode? {
        guard let object = value.objectValue else { return nil }

        let title = object["title"]?.stringValue
            ?? object["name"]?.stringValue
            ?? object["filename"]?.stringValue
            ?? object["value"]?.stringValue
            ?? "未命名"

        let path = object["value"]?.stringValue
            ?? object["path"]?.stringValue
            ?? object["key"]?.stringValue
            ?? title

        let typeText = object["type"]?.stringValue
            ?? object["isDirectory"]?.stringValue
            ?? ""
        let isDirectory = typeText == "directory"
            || typeText == "true"
            || object["children"] != nil

        var children: [FileNode] = []
        if let rawChildren = object["children"]?.arrayValue {
            children = rawChildren.compactMap { parseNode($0) }
        }

        let identifier = (isDirectory ? "d:" : "f:") + path + "#" + title
        return FileNode(
            id: identifier,
            title: title,
            path: path,
            isDirectory: isDirectory,
            children: children
        )
    }
}

// MARK: - 概览

struct DashboardOverview: Codable {
    var total: Int = 0
    var enabled: Int = 0
    var disabled: Int = 0
    var todayRuns: Int = 0
    var todaySuccess: Int = 0
    var todayFail: Int = 0
    var successRate: String = "0"
    var avgTime: Int = 0

    enum CodingKeys: String, CodingKey {
        case total, enabled, disabled, todayRuns, todaySuccess, todayFail, successRate, avgTime
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = c.flexInt(.total) ?? 0
        enabled = c.flexInt(.enabled) ?? 0
        disabled = c.flexInt(.disabled) ?? 0
        todayRuns = c.flexInt(.todayRuns) ?? 0
        todaySuccess = c.flexInt(.todaySuccess) ?? 0
        todayFail = c.flexInt(.todayFail) ?? 0
        successRate = c.flexString(.successRate) ?? "0"
        avgTime = c.flexInt(.avgTime) ?? 0
    }

    init() {}
}

struct DashboardTrendPoint: Codable, Identifiable {
    var date: String = ""
    var total: Int = 0
    var success: Int = 0
    var fail: Int = 0

    var id: String { date }

    enum CodingKeys: String, CodingKey { case date, total, success, fail }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = c.flexString(.date) ?? ""
        total = c.flexInt(.total) ?? 0
        success = c.flexInt(.success) ?? 0
        fail = c.flexInt(.fail) ?? 0
    }

    init() {}
}

struct RunningTask: Codable, Identifiable {
    var instanceId: Int = 0
    var id: Int = 0
    var name: String = ""
    var pid: Int?
    var elapsed: Int = 0
    var logPath: String?

    enum CodingKeys: String, CodingKey { case instanceId, id, name, pid, elapsed, logPath }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        instanceId = c.flexInt(.instanceId) ?? 0
        id = c.flexInt(.id) ?? 0
        name = c.flexString(.name) ?? ""
        pid = c.flexInt(.pid)
        elapsed = c.flexInt(.elapsed) ?? 0
        logPath = c.flexString(.logPath)
    }

    init() {}

    /// 兜底构造：当 `/dashboard/runtime` 不可用（例如应用未授予概览权限）时，
    /// 用任务自身的 `status` 与 `last_running_time` 推导出运行实例，
    /// 保证「正在运行」区域在降级情况下依然可用。
    init(cron: Cron, elapsed: Int) {
        self.instanceId = 0
        self.id = cron.id
        self.name = cron.displayName
        self.pid = cron.pid
        self.elapsed = max(0, elapsed)
        self.logPath = cron.logPath
    }

    var elapsedText: String {
        if elapsed < 60 { return "\(elapsed) 秒" }
        if elapsed < 3600 { return "\(elapsed / 60) 分 \(elapsed % 60) 秒" }
        return "\(elapsed / 3600) 时 \((elapsed % 3600) / 60) 分"
    }
}

struct RuntimeInfo: Codable {
    var runningCount: Int = 0
    var queuedCount: Int = 0
    var running: [RunningTask] = []

    enum CodingKeys: String, CodingKey { case runningCount, queuedCount, running }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        runningCount = c.flexInt(.runningCount) ?? 0
        queuedCount = c.flexInt(.queuedCount) ?? 0
        running = (try? c.decodeIfPresent([RunningTask].self, forKey: .running)) ?? []
    }

    init() {}
}

struct SystemStat: Codable {
    var platform: String = ""
    var uptime: Int = 0
    var memTotal: Double = 0
    var memFree: Double = 0
    var memUsagePercent: String = "0"
    var heapUsed: Int = 0
    var cpus: Int = 0
    var loadAvg: [Double] = []

    enum CodingKeys: String, CodingKey {
        case platform, uptime, memTotal, memFree, memUsagePercent, heapUsed, cpus, loadAvg
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        platform = c.flexString(.platform) ?? ""
        uptime = c.flexInt(.uptime) ?? 0
        memTotal = c.flexDouble(.memTotal) ?? 0
        memFree = c.flexDouble(.memFree) ?? 0
        memUsagePercent = c.flexString(.memUsagePercent) ?? "0"
        heapUsed = c.flexInt(.heapUsed) ?? 0
        cpus = c.flexInt(.cpus) ?? 0
        if let raw = try? c.decodeIfPresent([JSONValue].self, forKey: .loadAvg) {
            loadAvg = raw.compactMap { $0.doubleValue }
        }
    }

    init() {}

    var uptimeText: String {
        let days = uptime / 86400
        let hours = (uptime % 86400) / 3600
        let minutes = (uptime % 3600) / 60
        if days > 0 { return "\(days) 天 \(hours) 小时" }
        if hours > 0 { return "\(hours) 小时 \(minutes) 分" }
        return "\(minutes) 分钟"
    }

    var memUsedGB: Double {
        max(0, (memTotal - memFree) / 1024 / 1024 / 1024)
    }

    var memTotalGB: Double {
        memTotal / 1024 / 1024 / 1024
    }
}

// MARK: - 时间格式化

extension Date {
    /// "3 分钟前" / "2 小时前" / "08-12 21:30"
    var qlRelativeText: String {
        let interval = Date().timeIntervalSince(self)
        if interval < 0 { return qlClockText }
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        if interval < 86400 * 7 { return "\(Int(interval / 86400)) 天前" }
        return qlClockText
    }

    var qlClockText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: self)
    }

    var qlFullText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: self)
    }
}
