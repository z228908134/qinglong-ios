import Foundation
import SwiftUI

/// 一次面板连接所需的全部信息。整块以 JSON 形式存进钥匙串。
struct PanelConnection: Codable, Equatable {
    var rawAddress: String
    var baseURLString: String
    /// 面板登录账号。与令牌一起存进钥匙串，用于令牌失效后自动续期。
    var username: String
    var password: String
    var token: String?
    var tokenType: String?
    /// Unix 秒级时间戳，来自 `/open/auth/token` 的 expiration 字段
    var expiration: Double?

    var baseURL: URL? { URL(string: baseURLString) }

    var expirationDate: Date? {
        guard let expiration = expiration, expiration > 0 else { return nil }
        return Date(timeIntervalSince1970: expiration)
    }

    var isExpired: Bool {
        guard let date = expirationDate else { return false }
        return date.timeIntervalSinceNow < 0
    }

    var expirationText: String {
        guard let date = expirationDate else { return "有效期未知（面板未返回 expiration）" }
        if date.timeIntervalSinceNow < 0 { return "已过期，请重新登录" }
        let days = Int(date.timeIntervalSinceNow / 86400)
        if days >= 1 { return "剩余 \(days) 天有效" }
        return "有效期还剩不到 1 天"
    }

    /// 连接卡 / 设置页里展示的账号名。
    var accountName: String { username }
}

struct AlertMessage: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

/// 全局状态与业务入口。
///
/// 视图层只跟这个对象打交道，所有网络细节都被封装在 `APIClient` 里。
/// 任何一处出现 401/403 都会统一触发"需要重新登录"并清空会话。
@MainActor
final class PanelStore: ObservableObject {

    static let shared = PanelStore()

    private static let accountKey = "panel-connection"

    // MARK: 会话状态

    @Published private(set) var connection: PanelConnection?
    @Published private(set) var isAuthenticating = false
    @Published var alert: AlertMessage?

    // MARK: 数据

    @Published var crons: [Cron] = []
    @Published var envs: [QLEnv] = []
    @Published var subscriptions: [QLSubscription] = []
    @Published var dependencies: [QLDependence] = []

    @Published var overview: DashboardOverview?
    @Published var trend: [DashboardTrendPoint] = []
    @Published var runtime: RuntimeInfo?
    @Published var systemStat: SystemStat?
    @Published var configFiles: [ConfigFileItem] = []
    @Published var loginLogs: [LoginLogEntry] = []

    /// 概览各接口的加载失败原因。面板把概览数据放在独立的 `dashboard` 权限
    /// scope 下，未授权会返回 403；必须把原因显式呈现给用户，
    /// 否则界面上的 0% 会被误读成"数据真的是 0"。
    @Published var dashboardIssues: [String] = []

    /// 失败原因中是否包含权限拒绝（401/403），用于给出针对性指引。
    @Published var dashboardScopeDenied = false

    // MARK: 搜索词（由视图绑定，刷新时沿用）

    @Published var cronSearch = ""
    @Published var envSearch = ""
    @Published var subscriptionSearch = ""
    @Published var dependenceSearch = ""

    // MARK: 加载状态

    @Published private(set) var loadingModules: Set<String> = []

    private init() {
        restoreSession()
    }

    var isAuthenticated: Bool {
        (connection?.token?.isEmpty == false)
    }

    func isLoading(_ module: String) -> Bool {
        loadingModules.contains(module)
    }

    // MARK: - 会话管理

    private func restoreSession() {
        guard let data = KeychainStore.load(account: Self.accountKey),
              let saved = try? JSONDecoder().decode(PanelConnection.self, from: data) else {
            return
        }
        connection = saved
        APIClient.shared.configure(baseURL: saved.baseURL, token: saved.token, tokenType: saved.tokenType)
        APIClient.shared.setCredentials(username: saved.username, password: saved.password)
        APIClient.shared.onTokenRefreshed = { [weak self] token, tokenType, expiration in
            self?.handleTokenRefresh(token: token, tokenType: tokenType, expiration: expiration)
        }
    }

    private func persist(_ value: PanelConnection) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        KeychainStore.save(data, account: Self.accountKey)
    }

    /// 登录结果：成功，或面板开启了两步验证需要补充动态码。
    enum SignInOutcome {
        case success
        case needTwoFactor
        case failure
    }

    /// 使用面板账号密码登录。地址会自动补全协议与默认端口 5700。
    /// 面板开启两步验证时，首次调用返回 `.needTwoFactor`，
    /// 用户输入动态验证码后携带 `twoFactorCode` 再次调用即可。
    @discardableResult
    func signIn(
        address: String,
        username: String,
        password: String,
        twoFactorCode: String? = nil
    ) async -> SignInOutcome {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = APIClient.normalizeBaseURL(trimmedAddress) else {
            alert = AlertMessage(
                title: "地址无法解析",
                message: "请填写形如 192.168.1.8:5700、ql.example.com 或 https://ql.example.com 的地址。"
            )
            return .failure
        }
        guard !trimmedUsername.isEmpty, !trimmedPassword.isEmpty else {
            alert = AlertMessage(
                title: "请填写账号密码",
                message: "使用青龙面板网页端同一套账号密码登录即可，无需再创建 OpenAPI 应用。"
            )
            return .failure
        }

        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let authToken = try await APIClient.shared.login(
                baseURL: url,
                username: trimmedUsername,
                password: trimmedPassword,
                twoFactorCode: twoFactorCode
            )
            applyAuth(
                url: url,
                rawAddress: trimmedAddress,
                username: trimmedUsername,
                password: trimmedPassword,
                authToken: authToken
            )
            await refreshAll()
            return .success
        } catch APIError.business(let code, _) where code == 420 {
            // 面板开启了两步验证：界面显示动态码输入框后重试
            return .needTwoFactor
        } catch {
            APIClient.shared.clear()
            present(error)
            return .failure
        }
    }

    /// 用登录结果建立会话：写钥匙串、配置客户端（含自动续期凭据）。
    private func applyAuth(
        url: URL,
        rawAddress: String,
        username: String,
        password: String,
        authToken: AuthToken
    ) {
        // 面板用户令牌默认 20 天有效；响应若带毫秒时间戳则归一化为秒
        let expiration: Double?
        if let value = authToken.expiration {
            expiration = value > 1_000_000_000_000 ? Double(value) / 1000 : Double(value)
        } else {
            // 登录接口不返回有效期，按用户令牌默认 20 天估算
            expiration = Date().timeIntervalSince1970 + 20 * 86400
        }
        let saved = PanelConnection(
            rawAddress: rawAddress,
            baseURLString: url.absoluteString,
            username: username,
            password: password,
            token: authToken.token,
            tokenType: authToken.tokenType,
            expiration: expiration
        )
        persist(saved)
        connection = saved
        APIClient.shared.configure(baseURL: url, token: saved.token, tokenType: saved.tokenType)
        APIClient.shared.setCredentials(username: username, password: password)
        APIClient.shared.onTokenRefreshed = { [weak self] token, tokenType, expiration in
            self?.handleTokenRefresh(token: token, tokenType: tokenType, expiration: expiration)
        }
    }

    /// 静默续期成功后更新本地会话，用户无感知。
    private func handleTokenRefresh(token: String, tokenType: String?, expiration: Double?) {
        guard var saved = connection else { return }
        saved.token = token
        saved.tokenType = tokenType ?? saved.tokenType
        saved.expiration = expiration ?? saved.expiration
        connection = saved
        persist(saved)
    }

    /// 手动触发一次静默续期并全量刷新（设置页「重新登录并刷新令牌」）。
    func reSignInAndRefresh() async {
        guard let saved = connection, let url = saved.baseURL else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            let authToken = try await APIClient.shared.login(
                baseURL: url,
                username: saved.username,
                password: saved.password
            )
            applyAuth(
                url: url,
                rawAddress: saved.rawAddress,
                username: saved.username,
                password: saved.password,
                authToken: authToken
            )
            await refreshAll()
        } catch {
            present(error)
        }
    }

    func signOut() {
        KeychainStore.delete(account: Self.accountKey)
        APIClient.shared.clear()
        connection = nil
        crons = []
        envs = []
        subscriptions = []
        dependencies = []
        overview = nil
        trend = []
        runtime = nil
        systemStat = nil
        loadingModules = []
    }

    // MARK: - 错误处理

    func present(_ error: Error) {
        if let apiError = error as? APIError {
            if apiError.requiresReauth {
                let message = apiError.errorDescription ?? "登录状态已失效"
                signOut()
                alert = AlertMessage(title: "需要重新登录", message: message)
                return
            }
            alert = AlertMessage(title: "操作失败", message: apiError.errorDescription ?? "未知错误")
            return
        }
        alert = AlertMessage(title: "操作失败", message: error.localizedDescription)
    }

    private func perform(_ module: String, _ action: () async throws -> Void) async {
        loadingModules.insert(module)
        defer { loadingModules.remove(module) }
        do {
            try await action()
        } catch {
            present(error)
        }
    }

    // MARK: - 全量刷新

    func refreshAll() async {
        await loadDashboard()
        await loadCrons()
        await loadEnvs()
        await loadSubscriptions()
        await loadDependencies()
    }

    // MARK: - 概览

    /// 逐条拉取概览数据。
    ///
    /// 这里刻意**不再用 `try?` 静默吞掉错误**：四个端点在面板侧属于独立的
    /// `dashboard` 权限 scope，任何一个失败如果被吞掉，界面只会显示 0% / 空白，
    /// 用户无从判断是「数据真的是 0」还是「接口被拒绝」。因此每个失败都会记录
    /// 到 `dashboardIssues`，由概览页明确展示出来。
    func loadDashboard() async {
        await perform("dashboard") {
            dashboardIssues = []
            var permissionDenied = false

            // 1) 今日统计（总数 / 启用 / 成功失败 / 成功率 / 平均耗时）
            do {
                let response = try await APIClient.shared.send(.get, "dashboard/overview", as: JSONValue.self)
                if let object = response.data,
                   let payload = try? JSONEncoder().encode(object),
                   let decoded = try? JSONDecoder().decode(DashboardOverview.self, from: payload) {
                    overview = decoded
                } else {
                    overview = nil
                    dashboardIssues.append("今日统计：返回结构无法解析")
                }
            } catch {
                overview = nil
                if Self.isPermissionDenied(error) { permissionDenied = true }
                dashboardIssues.append("今日统计：\(Self.brief(error))")
            }

            // 2) 近 7 日执行趋势
            do {
                let response = try await APIClient.shared.send(
                    .get, "dashboard/trend", query: [("days", "7")], as: JSONValue.self
                )
                trend = ListDecoder.decode(response.data, as: DashboardTrendPoint.self)
            } catch {
                trend = []
                if Self.isPermissionDenied(error) { permissionDenied = true }
                dashboardIssues.append("执行趋势：\(Self.brief(error))")
            }

            // 3) 正在运行的实例
            do {
                let response = try await APIClient.shared.send(.get, "dashboard/runtime", as: JSONValue.self)
                if let object = response.data, let payload = try? JSONEncoder().encode(object) {
                    runtime = try? JSONDecoder().decode(RuntimeInfo.self, from: payload)
                }
            } catch {
                runtime = nil
                if Self.isPermissionDenied(error) { permissionDenied = true }
                dashboardIssues.append("运行实例：\(Self.brief(error))")
            }

            // 4) 面板运行环境（内存 / 负载 / 核数）
            do {
                let response = try await APIClient.shared.send(.get, "dashboard/system", as: JSONValue.self)
                if let object = response.data, let payload = try? JSONEncoder().encode(object) {
                    systemStat = try? JSONDecoder().decode(SystemStat.self, from: payload)
                }
            } catch {
                systemStat = nil
                dashboardIssues.append("面板环境：\(Self.brief(error))")
            }

            dashboardScopeDenied = permissionDenied
        }
    }

    /// 该错误是否属于「应用未被授予对应模块权限」。403 在青龙里表示
    /// 应用存在但 scopes 不含该模块，与网络故障要区分开提示。
    private static func isPermissionDenied(_ error: Error) -> Bool {
        guard let apiError = error as? APIError else { return false }
        switch apiError {
        case .business(let code, _):
            return code == 401 || code == 403
        case .http(let code):
            return code == 401 || code == 403
        default:
            return false
        }
    }

    /// 把错误压成一行，用于概览页的诊断清单。
    private static func brief(_ error: Error) -> String {
        guard let apiError = error as? APIError else {
            return error.localizedDescription
        }
        switch apiError {
        case .http(let code):
            return "HTTP \(code)"
        case .business(let code, let message):
            return message.isEmpty ? "code \(code)" : "code \(code) · \(message)"
        case .sessionExpired:
            return "登录状态已失效"
        case .transport(let underlying):
            return APIError.describe(underlying)
        default:
            return apiError.errorDescription ?? "未知错误"
        }
    }

    // MARK: - 定时任务

    func loadCrons() async {
        let keyword = cronSearch
        await perform("crons") {
            let response = try await APIClient.shared.send(
                .get,
                "crons",
                query: [("searchValue", keyword), ("page", "1"), ("size", "500")],
                as: JSONValue.self
            )
            crons = ListDecoder.decode(response.data, as: Cron.self)
        }
    }

    func runCrons(_ ids: [Int]) async {
        await mutate("crons/run", ids: ids) { await self.loadCrons() }
    }

    func stopCrons(_ ids: [Int]) async {
        await mutate("crons/stop", ids: ids) { await self.loadCrons() }
    }

    func enableCrons(_ ids: [Int]) async {
        await mutate("crons/enable", ids: ids) { await self.loadCrons() }
    }

    func disableCrons(_ ids: [Int]) async {
        await mutate("crons/disable", ids: ids) { await self.loadCrons() }
    }

    func pinCrons(_ ids: [Int], pinned: Bool) async {
        await mutate(pinned ? "crons/pin" : "crons/unpin", ids: ids) { await self.loadCrons() }
    }

    func deleteCrons(_ ids: [Int]) async {
        await mutate("crons", ids: ids, method: .delete) { await self.loadCrons() }
    }

    func saveCron(_ payload: CronPayload, isNew: Bool) async -> Bool {
        var succeeded = false
        await perform("cron-save") {
            if isNew {
                _ = try await APIClient.shared.send(.post, "crons", body: payload)
            } else {
                _ = try await APIClient.shared.send(.put, "crons", body: payload)
            }
            succeeded = true
        }
        if succeeded {
            await loadCrons()
        }
        return succeeded
    }

    /// 读取任务实时日志。`tail` 为 true 时只取末尾片段，适合查看正在运行的任务。
    func cronLog(id: Int, tail: Bool = true) async -> String {
        do {
            let response = try await APIClient.shared.send(
                .get,
                "crons/\(id)/log",
                query: [("tail", tail ? "true" : "false")],
                as: String.self
            )
            return response.data ?? "（日志为空）"
        } catch {
            present(error)
            return "读取日志失败：\((error as? APIError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    /// 某个任务的历史日志文件列表。
    func cronLogFiles(id: Int) async -> [FileNode] {
        do {
            let response = try await APIClient.shared.send(.get, "crons/\(id)/logs", as: JSONValue.self)
            return FileNode.parseList(response.data)
        } catch {
            present(error)
            return []
        }
    }

    // MARK: - 环境变量

    func loadEnvs() async {
        let keyword = envSearch
        await perform("envs") {
            let response = try await APIClient.shared.send(
                .get,
                "envs",
                query: [("searchValue", keyword)],
                as: JSONValue.self
            )
            envs = ListDecoder.decode(response.data, as: QLEnv.self)
        }
    }


    // MARK: - 配置文件

    func loadConfigFiles() async {
        await perform("config-files") {
            let response = try await APIClient.shared.send(
                .get, "configs/files", as: JSONValue.self
            )
            configFiles = ListDecoder.decode(response.data, as: ConfigFileItem.self)
        }
    }

    /// 读取配置文件内容。
    /// 新版面板走 `GET /api/configs/detail?path=<文件名>`；旧版走 `GET /api/configs/:file`，
    /// 两个都试，谁通用谁。
    func loadConfigContent(_ file: String) async -> String {
        if let response = try? await APIClient.shared.send(
            .get, "configs/detail",
            query: [("path", file)],
            as: String.self
        ), let text = response.data, !text.isEmpty {
            return text
        }
        if let response = try? await APIClient.shared.send(
            .get, "configs/\(file)", as: String.self
        ) {
            return response.data ?? ""
        }
        return ""
    }

    func saveConfigFile(name: String, content: String) async -> Bool {
        let payload = ConfigSavePayload(name: name, content: content)
        // 旧版面板用 PUT，新版 develop 用 POST，两个都试
        do {
            _ = try await APIClient.shared.send(
                .put, "configs/save", body: payload, as: JSONValue.self
            )
            return true
        } catch {}
        do {
            _ = try await APIClient.shared.send(
                .post, "configs/save", body: payload, as: JSONValue.self
            )
            return true
        } catch {}
        return false
    }

    // MARK: - 登录日志

    func loadLoginLogs() async {
        await perform("login-logs") {
            let response = try await APIClient.shared.send(
                .get, "user/login-log", as: JSONValue.self
            )
            loginLogs = ListDecoder.decode(response.data, as: LoginLogEntry.self)
        }
    }

    /// 任务日志历史文件名（`GET /api/crons/:id/logs`，最新在前）。
    /// 与上面的 `cronLogFiles(id:) -> [FileNode]` 区分命名，避免同名同参重定义。
    func cronLogFileNames(id: Int) async -> [String] {
        do {
            let response = try await APIClient.shared.send(
                .get, "crons/\(id)/logs", as: JSONValue.self
            )
            var files: [String] = []
            if let arr = response.data?.arrayValue {
                files = arr.compactMap { $0.stringValue }
            } else if let s = response.data?.stringValue {
                files = [s]
            }
            return files
        } catch {
            return []
        }
    }

    func createEnv(name: String, value: String, remarks: String) async -> Bool {
        var succeeded = false
        await perform("env-save") {
            let payload = [EnvCreatePayload(
                name: name,
                value: value,
                remarks: remarks.isEmpty ? nil : remarks,
                labels: nil
            )]
            _ = try await APIClient.shared.send(.post, "envs", body: payload)
            succeeded = true
        }
        if succeeded { await loadEnvs() }
        return succeeded
    }

    func updateEnv(id: Int, name: String, value: String, remarks: String) async -> Bool {
        var succeeded = false
        await perform("env-save") {
            let payload = EnvUpdatePayload(
                id: id,
                name: name,
                value: value,
                remarks: remarks.isEmpty ? nil : remarks,
                labels: nil
            )
            _ = try await APIClient.shared.send(.put, "envs", body: payload)
            succeeded = true
        }
        if succeeded { await loadEnvs() }
        return succeeded
    }

    func deleteEnvs(_ ids: [Int]) async {
        await mutate("envs", ids: ids, method: .delete) { await self.loadEnvs() }
    }

    func enableEnvs(_ ids: [Int]) async {
        await mutate("envs/enable", ids: ids) { await self.loadEnvs() }
    }

    func disableEnvs(_ ids: [Int]) async {
        await mutate("envs/disable", ids: ids) { await self.loadEnvs() }
    }

    func pinEnvs(_ ids: [Int], pinned: Bool) async {
        await mutate(pinned ? "envs/pin" : "envs/unpin", ids: ids) { await self.loadEnvs() }
    }

    // MARK: - 订阅

    func loadSubscriptions() async {
        let keyword = subscriptionSearch
        await perform("subscriptions") {
            let response = try await APIClient.shared.send(
                .get,
                "subscriptions",
                query: [("searchValue", keyword), ("page", "1"), ("size", "500")],
                as: JSONValue.self
            )
            subscriptions = ListDecoder.decode(response.data, as: QLSubscription.self)
        }
    }

    func runSubscriptions(_ ids: [Int]) async {
        await mutate("subscriptions/run", ids: ids) { await self.loadSubscriptions() }
    }

    func stopSubscriptions(_ ids: [Int]) async {
        await mutate("subscriptions/stop", ids: ids) { await self.loadSubscriptions() }
    }

    func enableSubscriptions(_ ids: [Int]) async {
        await mutate("subscriptions/enable", ids: ids) { await self.loadSubscriptions() }
    }

    func disableSubscriptions(_ ids: [Int]) async {
        await mutate("subscriptions/disable", ids: ids) { await self.loadSubscriptions() }
    }

    func deleteSubscriptions(_ ids: [Int]) async {
        await mutate("subscriptions", ids: ids, method: .delete) { await self.loadSubscriptions() }
    }

    func createSubscription(_ payload: SubscriptionCreatePayload) async -> Bool {
        var succeeded = false
        await perform("subscription-save") {
            _ = try await APIClient.shared.send(.post, "subscriptions", body: payload)
            succeeded = true
        }
        if succeeded { await loadSubscriptions() }
        return succeeded
    }

    func subscriptionLog(id: Int) async -> String {
        do {
            let response = try await APIClient.shared.send(
                .get,
                "subscriptions/\(id)/log",
                query: [("tail", "true")],
                as: String.self
            )
            return response.data ?? "（日志为空）"
        } catch {
            present(error)
            return "读取日志失败：\((error as? APIError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    // MARK: - 依赖

    func loadDependencies() async {
        let keyword = dependenceSearch
        await perform("dependencies") {
            let response = try await APIClient.shared.send(
                .get,
                "dependencies",
                query: [("searchValue", keyword)],
                as: JSONValue.self
            )
            dependencies = ListDecoder.decode(response.data, as: QLDependence.self)
        }
    }

    func createDependence(name: String, kind: DependenceKind, remark: String) async -> Bool {
        var succeeded = false
        await perform("dependence-save") {
            let payload = [DependenceCreatePayload(
                name: name,
                type: kind.rawValue,
                remark: remark.isEmpty ? nil : remark
            )]
            _ = try await APIClient.shared.send(.post, "dependencies", body: payload)
            succeeded = true
        }
        if succeeded { await loadDependencies() }
        return succeeded
    }

    func reinstallDependencies(_ ids: [Int]) async {
        await mutate("dependencies/reinstall", ids: ids) { await self.loadDependencies() }
    }

    func cancelDependencies(_ ids: [Int]) async {
        await mutate("dependencies/cancel", ids: ids) { await self.loadDependencies() }
    }

    func deleteDependencies(_ ids: [Int], force: Bool = false) async {
        await mutate(force ? "dependencies/force" : "dependencies", ids: ids, method: .delete) {
            await self.loadDependencies()
        }
    }

    /// 依赖的安装 / 卸载日志（面板以字符串数组返回）
    func dependenceLog(id: Int) async -> [String] {
        do {
            let response = try await APIClient.shared.send(.get, "dependencies/\(id)", as: JSONValue.self)
            guard let object = response.data, let payload = try? JSONEncoder().encode(object),
                  let parsed = try? JSONDecoder().decode(QLDependence.self, from: payload) else {
                return []
            }
            return parsed.log
        } catch {
            present(error)
            return []
        }
    }

    // MARK: - 日志文件

    func listLogs() async -> [FileNode] {
        do {
            let response = try await APIClient.shared.send(.get, "logs", as: JSONValue.self)
            return FileNode.parseList(response.data)
        } catch {
            present(error)
            return []
        }
    }

    func readLog(path: String, file: String) async -> String {
        do {
            let response = try await APIClient.shared.send(
                .get,
                "logs/detail",
                query: [("path", path), ("file", file), ("tail", "true")],
                as: String.self
            )
            // 面板会在日志里写入 ANSI 颜色控制符，这里做一次清理
            return LogText.cleanAnsi(response.data ?? "（日志为空）")
        } catch {
            present(error)
            return "读取日志失败：\((error as? APIError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    func deleteLog(path: String, file: String) async -> Bool {
        var succeeded = false
        await perform("log-delete") {
            _ = try await APIClient.shared.send(
                .delete,
                "logs",
                body: ["filename": file, "path": path]
            )
            succeeded = true
        }
        return succeeded
    }

    // MARK: - 脚本

    func listScripts(path: String = "") async -> [FileNode] {
        do {
            let response = try await APIClient.shared.send(
                .get,
                "scripts",
                query: [("path", path)],
                as: JSONValue.self
            )
            return FileNode.parseList(response.data)
        } catch {
            present(error)
            return []
        }
    }

    func readScript(path: String, file: String) async -> String {
        do {
            let response = try await APIClient.shared.send(
                .get,
                "scripts/detail",
                query: [("path", path), ("file", file)],
                as: String.self
            )
            return response.data ?? ""
        } catch {
            present(error)
            return "// 读取失败：\((error as? APIError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    func saveScript(path: String, file: String, content: String) async -> Bool {
        var succeeded = false
        await perform("script-save") {
            _ = try await APIClient.shared.send(
                .put,
                "scripts",
                body: ["filename": file, "path": path, "content": content]
            )
            succeeded = true
        }
        return succeeded
    }

    func deleteScript(path: String, file: String) async -> Bool {
        var succeeded = false
        await perform("script-delete") {
            _ = try await APIClient.shared.send(
                .delete,
                "scripts",
                body: ["filename": file, "path": path]
            )
            succeeded = true
        }
        return succeeded
    }

    // MARK: - 通用批量写操作

    /// 面板的批量接口（run / stop / enable / disable / pin / delete）请求体都是纯数字数组。
    private func mutate(
        _ path: String,
        ids: [Int],
        method: HTTPMethod = .put,
        reload: @escaping () async -> Void
    ) async {
        guard !ids.isEmpty else { return }
        await perform("mutate") {
            _ = try await APIClient.shared.send(method, path, body: ids)
        }
        await reload()
    }
}

// MARK: - 列表解析

/// 列表接口在不同面板版本里可能返回裸数组，也可能包一层 `{ data: [...] }`。
/// 统一先解成 `JSONValue` 再转换，避免因外层结构差异导致整页空白。
private enum ListDecoder {
    static func decode<T: Decodable>(_ value: JSONValue?, as type: T.Type) -> [T] {
        guard let value = value else { return [] }

        let items: [JSONValue]
        if let list = value.arrayValue {
            items = list
        } else if let list = value.objectValue?["data"]?.arrayValue {
            items = list
        } else if let list = value.objectValue?["list"]?.arrayValue {
            items = list
        } else if let list = value.objectValue?["records"]?.arrayValue {
            items = list
        } else {
            items = []
        }

        let decoder = JSONDecoder()
        return items.compactMap { item in
            guard let data = try? JSONEncoder().encode(item) else { return nil }
            return try? decoder.decode(T.self, from: data)
        }
    }
}

// MARK: - 日志文本处理

enum LogText {
    /// 清理面板日志里的 ANSI 转义序列（颜色、光标控制等）。
    ///
    /// 面板会把 `\u{1B}[32m` 这类控制符一起写进日志文件，
    /// 直接展示会在界面上出现乱码，所以在渲染前统一剥离。
    static func cleanAnsi(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var output = ""
        output.reserveCapacity(text.count)

        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]

            guard scalar == "\u{1B}" else {
                output.unicodeScalars.append(scalar)
                index += 1
                continue
            }

            // CSI 序列：ESC [ 数字/分号... 终止字母
            if index + 1 < scalars.count, scalars[index + 1] == "[" {
                var cursor = index + 2
                while cursor < scalars.count {
                    let current = scalars[cursor]
                    cursor += 1
                    if CharacterSet.letters.contains(current) || current == "@" || current == "`" {
                        break
                    }
                }
                index = cursor
            } else {
                index += 1
            }
        }

        return output
    }
}
