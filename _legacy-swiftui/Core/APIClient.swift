//
//  APIClient.swift
//  青龙面板 HTTP 客户端（纯 URLSession + async/await，无第三方依赖）
//

import Foundation

// MARK: - 错误

enum QLAPIError: LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case unauthorized(String)
    case twoFactorRequired
    case rateLimited(String)
    case server(code: Int, message: String)
    case decoding(String)
    case network(String)
    case emptyPayload

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "服务器地址不正确，请检查是否包含 http:// 前缀和端口号"
        case .invalidResponse:
            return "服务器返回了无法识别的响应"
        case .unauthorized(let message):
            return message
        case .twoFactorRequired:
            return "该账号已开启两步验证，请输入动态验证码"
        case .rateLimited(let message):
            return message
        case .server(_, let message):
            return message
        case .decoding(let detail):
            return "数据解析失败：\(detail)"
        case .network(let detail):
            return detail
        case .emptyPayload:
            return "服务器没有返回数据"
        }
    }

    /// 登录态失效需要回到登录页
    var isUnauthorized: Bool {
        if case .unauthorized = self { return true }
        return false
    }
}

// MARK: - 客户端

struct APIClient {

    /// 面板地址，例如 http://1.2.3.4:5700（结尾不带 /）
    let baseURL: URL
    /// 登录后拿到的 JWT
    let token: String?

    /// ⚠️ 关键：青龙后端用 User-Agent 判断 platform（mobile / desktop），
    /// 并把 token 存进 tokens[platform]。所以客户端必须在**每一个请求**上
    /// 带上完全一致的 UA，否则登录时算 mobile、后续请求算 desktop，token 直接失效。
    static let userAgent = "QingLongClient/1.0 (iPhone; iOS) Mobile Safari"

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    // MARK: 构造

    /// 把用户输入的地址规整成 URL
    static func normalizedBaseURL(from raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "http://" + text
        }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), url.host != nil else { return nil }
        return url
    }

    func with(token newToken: String?) -> APIClient {
        APIClient(baseURL: baseURL, token: newToken)
    }

    // MARK: 底层请求

    private func makeRequest(
        path: String,
        method: String,
        query: [String: String],
        body: Data?
    ) throws -> URLRequest {
        let suffix = path.hasPrefix("/") ? path : "/" + path
        guard let plain = URL(string: baseURL.absoluteString + suffix),
              var components = URLComponents(url: plain, resolvingAgainstBaseURL: false)
        else { throw QLAPIError.invalidURL }

        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw QLAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func transport(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await Self.session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw QLAPIError.invalidResponse }
            return (data, http)
        } catch let error as QLAPIError {
            throw error
        } catch let error as URLError {
            throw QLAPIError.network(Self.friendlyMessage(for: error))
        } catch {
            throw QLAPIError.network(error.localizedDescription)
        }
    }

    private static func friendlyMessage(for error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet: return "网络不可用，请检查手机网络"
        case .timedOut: return "连接超时，请确认面板地址和端口是否可访问"
        case .cannotConnectToHost: return "无法连接服务器，请确认面板是否在运行、端口是否放行"
        case .cannotFindHost: return "找不到服务器，请检查地址是否写错"
        case .networkConnectionLost: return "网络连接中断，请重试"
        case .appTransportSecurityRequiresSecureConnection: return "系统拦截了明文 HTTP 请求（ATS 配置缺失）"
        case .secureConnectionFailed: return "TLS 握手失败，请检查证书"
        default: return error.localizedDescription
        }
    }

    /// 校验业务 code，非 200 一律抛错
    private static func validate(code: Int, message: String?) throws {
        switch code {
        case 200:
            return
        case 401:
            throw QLAPIError.unauthorized(message ?? "登录已失效，请重新登录")
        case 420:
            throw QLAPIError.twoFactorRequired
        case 410:
            throw QLAPIError.rateLimited(message ?? "操作过于频繁，请稍后再试")
        default:
            throw QLAPIError.server(code: code, message: message ?? "请求失败（code \(code)）")
        }
    }

    /// 校验 HTTP 状态码，返回原始 body
    private func rawBody(_ request: URLRequest) async throws -> Data {
        let (data, http) = try await transport(request)

        if http.statusCode == 401 {
            let message = (try? Self.decoder.decode(QLStatusEnvelope.self, from: data))?.message
            throw QLAPIError.unauthorized(message ?? "登录已失效，请重新登录")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? Self.decoder.decode(QLStatusEnvelope.self, from: data))?.message
            throw QLAPIError.server(code: http.statusCode, message: message ?? "服务器错误（HTTP \(http.statusCode)）")
        }
        return data
    }

    private func envelope<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> QLEnvelope<T> {
        let data = try await rawBody(request)
        let decoded: QLEnvelope<T>
        do {
            decoded = try Self.decoder.decode(QLEnvelope<T>.self, from: data)
        } catch {
            throw QLAPIError.decoding(error.localizedDescription)
        }
        try Self.validate(code: decoded.code, message: decoded.message)
        return decoded
    }

    /// 动作类接口：只校验业务 code，完全忽略 data 的结构
    /// （青龙的 run / enable / create 等接口返回的 data 类型不统一，硬解会炸）
    private func checkStatus(_ request: URLRequest) async throws {
        let data = try await rawBody(request)
        guard let decoded = try? Self.decoder.decode(QLStatusEnvelope.self, from: data) else {
            throw QLAPIError.decoding("响应不是合法的 JSON")
        }
        try Self.validate(code: decoded.code, message: decoded.message)
    }

    // MARK: 四个通用入口

    func send<T: Decodable>(_ path: String,
                            method: String = "GET",
                            query: [String: String] = [:],
                            as type: T.Type) async throws -> T {
        let request = try makeRequest(path: path, method: method, query: query, body: nil)
        let box = try await envelope(request, as: T.self)
        guard let payload = box.data else { throw QLAPIError.emptyPayload }
        return payload
    }

    func send<T: Decodable, B: Encodable>(_ path: String,
                                          method: String,
                                          query: [String: String] = [:],
                                          body: B,
                                          as type: T.Type) async throws -> T {
        let data = try Self.encoder.encode(body)
        let request = try makeRequest(path: path, method: method, query: query, body: data)
        let box = try await envelope(request, as: T.self)
        guard let payload = box.data else { throw QLAPIError.emptyPayload }
        return payload
    }

    func sendVoid(_ path: String,
                  method: String = "GET",
                  query: [String: String] = [:]) async throws {
        let request = try makeRequest(path: path, method: method, query: query, body: nil)
        try await checkStatus(request)
    }

    func sendVoid<B: Encodable>(_ path: String,
                                method: String,
                                query: [String: String] = [:],
                                body: B) async throws {
        let data = try Self.encoder.encode(body)
        let request = try makeRequest(path: path, method: method, query: query, body: data)
        try await checkStatus(request)
    }

    // MARK: - 认证

    func login(username: String, password: String) async throws -> QLLoginResult {
        try await send("/api/user/login",
                       method: "POST",
                       body: LoginPayload(username: username, password: password),
                       as: QLLoginResult.self)
    }

    func twoFactorLogin(username: String, password: String, code: String) async throws -> QLLoginResult {
        try await send("/api/user/two-factor/login",
                       method: "PUT",
                       body: TwoFactorPayload(username: username, password: password, code: code),
                       as: QLLoginResult.self)
    }

    func currentUser() async throws -> QLUser {
        try await send("/api/user", as: QLUser.self)
    }

    func logout() async throws {
        try await sendVoid("/api/user/logout", method: "POST")
    }

    func systemInfo() async throws -> QLSystemInfo {
        try await send("/api/system", as: QLSystemInfo.self)
    }

    // MARK: - 定时任务

    func crons(search: String = "", page: Int? = nil, size: Int? = nil) async throws -> CronPage {
        var query: [String: String] = [:]
        if !search.isEmpty { query["searchValue"] = search }
        if let page, let size {
            query["page"] = String(page)
            query["size"] = String(size)
        }
        return try await send("/api/crons", query: query, as: CronPage.self)
    }

    func cron(id: Int) async throws -> CronTask {
        try await send("/api/crons/\(id)", as: CronTask.self)
    }

    func runCrons(_ ids: [Int]) async throws {
        try await sendVoid("/api/crons/run", method: "PUT", body: ids)
    }

    func stopCrons(_ ids: [Int]) async throws {
        try await sendVoid("/api/crons/stop", method: "PUT", body: ids)
    }

    func enableCrons(_ ids: [Int]) async throws {
        try await sendVoid("/api/crons/enable", method: "PUT", body: ids)
    }

    func disableCrons(_ ids: [Int]) async throws {
        try await sendVoid("/api/crons/disable", method: "PUT", body: ids)
    }

    func pinCrons(_ ids: [Int]) async throws {
        try await sendVoid("/api/crons/pin", method: "PUT", body: ids)
    }

    func unpinCrons(_ ids: [Int]) async throws {
        try await sendVoid("/api/crons/unpin", method: "PUT", body: ids)
    }

    func deleteCrons(_ ids: [Int]) async throws {
        try await sendVoid("/api/crons", method: "DELETE", body: ids)
    }

    func createCron(_ payload: CronPayload) async throws {
        try await sendVoid("/api/crons", method: "POST", body: payload)
    }

    func updateCron(_ payload: CronPayload) async throws {
        try await sendVoid("/api/crons", method: "PUT", body: payload)
    }

    /// 返回 (日志内容, 日志状态)。日志状态：empty / ignored / running / completed / notFound
    func cronLog(id: Int) async throws -> (content: String, status: String?) {
        let request = try makeRequest(path: "/api/crons/\(id)/log", method: "GET", query: [:], body: nil)
        let box = try await envelope(request, as: String.self)
        return (box.data ?? "", box.logStatus)
    }

    // MARK: - 环境变量

    func envs(search: String = "") async throws -> [EnvVar] {
        var query: [String: String] = [:]
        if !search.isEmpty { query["searchValue"] = search }
        return try await send("/api/envs", query: query, as: [EnvVar].self)
    }

    func createEnvs(_ payloads: [EnvPayload]) async throws {
        try await sendVoid("/api/envs", method: "POST", body: payloads)
    }

    func updateEnv(_ payload: EnvPayload) async throws {
        try await sendVoid("/api/envs", method: "PUT", body: payload)
    }

    func deleteEnvs(_ ids: [Int]) async throws {
        try await sendVoid("/api/envs", method: "DELETE", body: ids)
    }

    func enableEnvs(_ ids: [Int]) async throws {
        try await sendVoid("/api/envs/enable", method: "PUT", body: ids)
    }

    func disableEnvs(_ ids: [Int]) async throws {
        try await sendVoid("/api/envs/disable", method: "PUT", body: ids)
    }

    // MARK: - 日志文件

    func logTree() async throws -> [LogNode] {
        try await send("/api/logs", as: [LogNode].self)
    }

    func logFileContent(path: String, file: String) async throws -> String {
        let request = try makeRequest(path: "/api/logs/detail",
                                      method: "GET",
                                      query: ["path": path, "file": file],
                                      body: nil)
        let box = try await envelope(request, as: String.self)
        return box.data ?? ""
    }

    func deleteLogFile(path: String, file: String) async throws {
        struct Body: Encodable {
            let filename: String
            let path: String
        }
        try await sendVoid("/api/logs", method: "DELETE", body: Body(filename: file, path: path))
    }
}
