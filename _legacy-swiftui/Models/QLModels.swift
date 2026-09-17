//
//  QLModels.swift
//  青龙面板（Qinglong v2.21.x）数据模型
//
//  说明：解码统一使用 JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase，
//  因此这里的属性名是驼峰，对应后端下划线字段（log_name -> logName）。
//

import Foundation

// MARK: - 统一响应外壳

/// 青龙接口统一返回：`{ "code": 200, "message": "...", "data": ... }`
/// 任务日志接口还会额外返回 `logStatus`。
struct QLEnvelope<T: Decodable>: Decodable {
    let code: Int
    let message: String?
    let data: T?
    let logStatus: String?
}

/// 只关心执行结果的响应外壳，用于 data 结构不确定的动作类接口
/// （Swift 解码器会忽略未声明的字段，所以 data 是数组还是对象都无所谓）。
struct QLStatusEnvelope: Decodable {
    let code: Int
    let message: String?
}

// MARK: - 用户 / 系统

struct QLUser: Decodable {
    let username: String?
    let avatar: String?
    let twoFactorActivated: Bool?
}

/// POST /api/user/login 的 data
/// （后端还会返回 lastip / lastaddr / lastlogon 等字段，这里用不到就不声明了）
struct QLLoginResult: Decodable {
    let token: String
}

/// GET /api/system 的 data
struct QLSystemInfo: Decodable {
    let isInitialized: Bool?
    let version: String?
    let branch: String?
    let publishTime: Double?
    let changeLog: String?
    let changeLogLink: String?
}

// MARK: - 任务状态

/// 对应后端 CrontabStatus 枚举（v2.21）
enum CronStatus: Int, Decodable, Hashable {
    case running = 0
    case idle = 1
    case disabled = 2
    case queued = 3

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(Int.self)
        self = CronStatus(rawValue: raw) ?? .idle
    }
}

struct ExtraSchedule: Decodable, Hashable {
    let schedule: String?
}

// MARK: - 定时任务

struct CronTask: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let command: String?
    let schedule: String?
    let status: CronStatus?
    let pid: Int?
    let isDisabled: Int?
    let isPinned: Int?
    let isSystem: Int?
    let logName: String?
    let logPath: String?
    let labels: [String]?
    let lastRunningTime: Double?
    let lastExecutionTime: Double?
    let extraSchedules: [ExtraSchedule]?
    let taskBefore: String?
    let taskAfter: String?
    let workDir: String?
    let allowMultipleInstances: Int?
    let createdAt: String?
    let updatedAt: String?

    var displayName: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名任务" : trimmed
    }

    /// isDisabled 与 status 任一表明禁用，即视为禁用
    var isDisabledTask: Bool {
        (isDisabled ?? 0) == 1 || status == .disabled
    }

    var effectiveStatus: CronStatus {
        isDisabledTask ? .disabled : (status ?? .idle)
    }

    var isBusy: Bool {
        effectiveStatus == .running || effectiveStatus == .queued
    }

    var isPinnedTask: Bool { (isPinned ?? 0) == 1 }

    var isSystemTask: Bool { (isSystem ?? 0) == 1 }
}

/// GET /api/crons 的 data
struct CronPage: Decodable {
    let data: [CronTask]
    let total: Int
}

// MARK: - 环境变量

/// 对应后端 EnvStatus 枚举：0 正常 / 1 禁用
enum EnvStatus: Int, Decodable, Hashable {
    case normal = 0
    case disabled = 1

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(Int.self)
        self = EnvStatus(rawValue: raw) ?? .normal
    }
}

struct EnvVar: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let value: String?
    let remarks: String?
    let status: EnvStatus?
    let position: Double?
    let isPinned: Int?
    let labels: [String]?
    let createdAt: String?
    let updatedAt: String?

    var displayName: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(未命名变量)" : trimmed
    }

    var isDisabledVar: Bool { status == .disabled }
}

// MARK: - 日志文件树

/// GET /api/logs 返回的 IFile 结构
struct LogNode: Decodable, Identifiable, Hashable {
    let title: String
    let key: String
    let type: String
    let parent: String?
    let createTime: Double?
    let size: Double?
    let children: [LogNode]?

    var id: String { key }
    var isDirectory: Bool { type == "directory" }
    var byteSize: Int? { size.map { Int($0) } }
}

// MARK: - 请求体

/// POST /api/crons 与 PUT /api/crons 的请求体。
/// 注意：Joi 校验默认不允许未知字段，这里只放后端 schema 里声明过的字段；
/// 新建时 id 为 nil，编码器会自动省略；name 为空也省略（Joi 不允许空串）。
struct CronPayload: Encodable {
    var id: Int?
    var name: String?
    var command: String
    var schedule: String
    var labels: [String]?
    var taskBefore: String?
    var taskAfter: String?
    var logName: String?
    var workDir: String?
    var allowMultipleInstances: Int?
}

/// POST /api/envs 与 PUT /api/envs 的请求体
struct EnvPayload: Encodable {
    var id: Int?
    var name: String
    var value: String
    var remarks: String?
    var labels: [String]?
}

struct LoginPayload: Encodable {
    let username: String
    let password: String
}

struct TwoFactorPayload: Encodable {
    let username: String
    let password: String
    let code: String
}
