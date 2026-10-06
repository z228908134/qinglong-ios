import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

/// 面向用户的错误类型：每一条都能直接显示在界面上，并且尽量给出可操作的下一步。
enum APIError: LocalizedError {
    case missingBaseURL
    case invalidBaseURL
    case notAuthorized
    case sessionExpired
    case transport(Error)
    case invalidResponse
    case http(Int)
    case business(code: Int, message: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "请先填写面板地址"
        case .invalidBaseURL:
            return "面板地址无法解析，请检查格式，例如 192.168.1.8:5700"
        case .notAuthorized:
            return "尚未登录，请先填写面板账号密码"
        case .sessionExpired:
            return "登录状态已失效，请重新登录"
        case .transport(let error):
            return APIError.describe(error)
        case .invalidResponse:
            return "服务器返回了无法识别的响应，请确认地址指向的是青龙面板"
        case .http(let code):
            return "网络请求失败（HTTP \(code)）"
        case .business(let code, let message):
            if message.isEmpty {
                return "面板返回错误（code \(code)）"
            }
            return message
        case .decoding(let detail):
            return "数据解析失败：\(detail)"
        }
    }

    /// 可以提示用户重新登录的错误
    var requiresReauth: Bool {
        switch self {
        case .sessionExpired, .notAuthorized:
            return true
        case .business(let code, _):
            return code == 401 || code == 403
        case .http(let code):
            return code == 401 || code == 403
        default:
            return false
        }
    }

    static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return nsError.localizedDescription
        }
        switch nsError.code {
        case NSURLErrorCannotConnectToHost:
            return "无法连接到面板。请确认地址与端口正确，且手机与面板在同一网络（局域网内 HTTP 需要面板监听 0.0.0.0）"
        case NSURLErrorTimedOut:
            return "连接超时。面板可能未响应，或网络不通"
        case NSURLErrorNotConnectedToInternet:
            return "设备当前没有网络连接"
        case NSURLErrorNetworkConnectionLost:
            return "网络连接中断，请重试"
        case NSURLErrorCannotFindHost:
            return "找不到该主机。请检查域名是否可解析，局域网可改填 IP 地址"
        case NSURLErrorSecureConnectionFailed,
             NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateNotYetValid,
             NSURLErrorServerCertificateHasUnknownRoot:
            return "HTTPS 证书校验失败。自签证书可改用 http:// 访问"
        case NSURLErrorAppTransportSecurityRequiresSecureConnection:
            return "系统安全策略拦截了该请求，请改用 https:// 访问"
        default:
            return nsError.localizedDescription
        }
    }
}
