import Foundation

/// 青龙统一响应信封。
///
/// 面板所有接口都返回 `{ code, message, data }` 结构；日志类接口还会在顶层
/// 额外带上 `logStatus / offset / nextOffset / total / truncated`。
struct APIResponse<T: Decodable>: Decodable {
    let code: Int?
    let message: String?
    let data: T?
    let logStatus: String?
    let offset: Int?
    let nextOffset: Int?
    let total: Int?
    let truncated: Bool?

    var isOK: Bool { code == 200 }
}

/// 认证接口返回的令牌信息。
struct AuthToken: Decodable {
    let token: String?
    let tokenType: String?
    let expiration: Int?

    enum CodingKeys: String, CodingKey {
        case token
        case tokenType = "token_type"
        case expiration
    }
}

/// 青龙面板网络客户端。
///
/// 所有请求都以 `/open` 为前缀，使用 `Authorization: Bearer <token>` 认证。
/// 认证方式为 OpenAPI 应用凭据（Client ID / Client Secret），而不是面板账号密码。
final class APIClient {

    static let shared = APIClient()

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    /// 形如 http://192.168.1.8:5700（可含反向代理子路径）
    private(set) var baseURL: URL?
    private(set) var token: String?
    private(set) var tokenType: String = "Bearer"

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        session = URLSession(configuration: configuration)
    }

    // MARK: - 会话配置

    func configure(baseURL: URL?, token: String?, tokenType: String?) {
        self.baseURL = baseURL
        self.token = token
        if let tokenType = tokenType, !tokenType.isEmpty {
            self.tokenType = tokenType
        }
    }

    func clear() {
        baseURL = nil
        token = nil
        tokenType = "Bearer"
    }

    var isConfigured: Bool {
        baseURL != nil && token != nil
    }

    // MARK: - 地址规范化

    /// 把用户随手输入的地址整理成可用的 baseURL。
    ///
    /// 支持的写法（与安卓端「定时精灵」保持一致）：
    /// - `192.168.1.8`            → http://192.168.1.8:5700
    /// - `192.168.1.8:5700`       → http://192.168.1.8:5700
    /// - `ql.example.com`         → http://ql.example.com:5700
    /// - `https://ql.example.com` → https://ql.example.com（保留 443，不补端口）
    static func normalizeBaseURL(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // 去掉不小心粘贴进来的路径尾巴（保留子路径的场景请显式写全）
        if text.hasSuffix("/") {
            while text.hasSuffix("/") { text.removeLast() }
        }

        let lowercased = text.lowercased()
        let hasScheme = lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://")
        if !hasScheme {
            text = "http://" + text
        }

        guard let url = URL(string: text),
              let host = url.host,
              !host.isEmpty else {
            return nil
        }

        // 用户没写协议、也没写端口时，按青龙默认端口 5700 补齐
        if !hasScheme, url.port == nil {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.port = 5700
            return components?.url ?? url
        }

        return url
    }

    // MARK: - 请求构造

    private func makeRequest(
        method: HTTPMethod,
        path: String,
        query: [(String, String)],
        body: Data?,
        contentType: String?,
        authorized: Bool
    ) throws -> URLRequest {
        guard let base = baseURL else { throw APIError.missingBaseURL }

        var components = URLComponents()
        components.scheme = base.scheme
        components.host = base.host
        components.port = base.port

        let prefix = base.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var fullPath = ""
        if !prefix.isEmpty {
            fullPath += "/" + prefix
        }
        fullPath += "/open/" + path
        components.path = fullPath

        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }

        guard let url = components.url else { throw APIError.invalidBaseURL }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = body

        if let contentType = contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        if authorized {
            guard let token = token else { throw APIError.notAuthorized }
            request.setValue("\(tokenType) \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>) in
            let task = session.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: APIError.transport(error))
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    continuation.resume(throwing: APIError.invalidResponse)
                    return
                }
                continuation.resume(returning: (data ?? Data(), http))
            }
            task.resume()
        }
    }

    private func decodeResponse<T: Decodable>(
        data: Data,
        response: HTTPURLResponse,
        as type: T.Type
    ) throws -> APIResponse<T> {
        // 面板正常业务响应统一是 200 + code 字段，先按目标类型解析
        if let envelope = try? decoder.decode(APIResponse<T>.self, from: data) {
            if let code = envelope.code, code != 200 {
                if code == 401 { throw APIError.sessionExpired }
                throw APIError.business(code: code, message: envelope.message ?? "")
            }
            if envelope.code == nil && !(200...299).contains(response.statusCode) {
                if response.statusCode == 401 { throw APIError.sessionExpired }
                throw APIError.http(response.statusCode)
            }
            return envelope
        }

        // 解析失败：先尝试取出服务端的错误码与提示，给出比「解析失败」更有用的信息
        if let raw = try? decoder.decode(APIResponse<JSONValue>.self, from: data) {
            if let code = raw.code, code != 200 {
                if code == 401 { throw APIError.sessionExpired }
                throw APIError.business(code: code, message: raw.message ?? "")
            }
            throw APIError.decoding("返回结构与预期不符（\(type)）")
        }

        if response.statusCode == 401 { throw APIError.sessionExpired }
        if !(200...299).contains(response.statusCode) {
            throw APIError.http(response.statusCode)
        }

        let snippet = String(data: data.prefix(200), encoding: .utf8) ?? "<非文本响应>"
        throw APIError.decoding(snippet)
    }

    // MARK: - 通用请求

    /// 发起请求并解析出指定类型的 `data`。
    func send<T: Decodable>(
        _ method: HTTPMethod,
        _ path: String,
        query: [(String, String)] = [],
        authorized: Bool = true,
        as type: T.Type
    ) async throws -> APIResponse<T> {
        let request = try makeRequest(
            method: method, path: path, query: query,
            body: nil, contentType: nil, authorized: authorized
        )
        let (data, response) = try await perform(request)
        return try decodeResponse(data: data, response: response, as: T.self)
    }

    /// 带 JSON 请求体的请求。请求体会按字段名自动省略 nil 的可选字段，
    /// 这一点很重要：面板用 Joi 校验入参，多传未知字段会直接返回 400。
    func send<Body: Encodable, T: Decodable>(
        _ method: HTTPMethod,
        _ path: String,
        query: [(String, String)] = [],
        body: Body,
        authorized: Bool = true,
        as type: T.Type
    ) async throws -> APIResponse<T> {
        let payload = try encoder.encode(body)
        let request = try makeRequest(
            method: method, path: path, query: query,
            body: payload, contentType: "application/json", authorized: authorized
        )
        let (data, response) = try await perform(request)
        return try decodeResponse(data: data, response: response, as: T.self)
    }

    /// 只关心成功与否的写操作（批量启停、置顶、删除等）。
    @discardableResult
    func send<Body: Encodable>(
        _ method: HTTPMethod,
        _ path: String,
        query: [(String, String)] = [],
        body: Body,
        authorized: Bool = true
    ) async throws -> APIResponse<JSONValue> {
        try await send(method, path, query: query, body: body, authorized: authorized, as: JSONValue.self)
    }

    /// 下载型接口（日志导出、脚本下载、数据备份），返回原始二进制。
    func download(
        _ method: HTTPMethod,
        _ path: String,
        body: Encodable?
    ) async throws -> Data {
        var payload: Data?
        if let body = body {
            payload = try encoder.encode(AnyEncodable(body))
        }
        let request = try makeRequest(
            method: method, path: path, query: [],
            body: payload, contentType: payload == nil ? nil : "application/json", authorized: true
        )
        let (data, response) = try await perform(request)
        if !(200...299).contains(response.statusCode) {
            _ = try? decodeResponse(data: data, response: response, as: JSONValue.self)
            throw APIError.http(response.statusCode)
        }
        return data
    }

    // MARK: - 认证

    /// 使用应用凭据换取访问令牌。
    ///
    /// `GET /open/auth/token?client_id=&client_secret=`，令牌有效期通常为 30 天。
    @discardableResult
    func fetchToken(
        baseURL: URL,
        clientID: String,
        clientSecret: String
    ) async throws -> AuthToken {
        self.baseURL = baseURL
        self.token = nil

        let response = try await send(
            .get,
            "auth/token",
            query: [("client_id", clientID), ("client_secret", clientSecret)],
            authorized: false,
            as: AuthToken.self
        )

        guard let payload = response.data, let value = payload.token, !value.isEmpty else {
            throw APIError.decoding("认证接口未返回 token，请确认 Client ID / Secret 是否正确以及已授予权限")
        }

        self.token = value
        self.tokenType = (payload.tokenType?.isEmpty == false) ? payload.tokenType! : "Bearer"
        return payload
    }

    /// 连通性探测：不依赖令牌，用于在登录页快速验证地址是否可达。
    func probe(host: URL) async throws -> Bool {
        var components = URLComponents()
        components.scheme = host.scheme
        components.host = host.host
        components.port = host.port
        let prefix = host.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = (prefix.isEmpty ? "" : "/" + prefix) + "/open/health"
        guard let url = components.url else { throw APIError.invalidBaseURL }

        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.get.rawValue
        request.timeoutInterval = 8

        let (_, response) = try await perform(request)
        // 面板无论是否授权都会返回 JSON（health 无需鉴权），只要不是 5xx 即视为可达
        return response.statusCode < 500
    }
}

/// 用于擦除具体类型的编码包装，让 `download` 这类方法可以接收任意 Encodable。
struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init(_ wrapped: Encodable) {
        encodeClosure = { encoder in
            try wrapped.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}
