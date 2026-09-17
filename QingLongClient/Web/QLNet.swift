import Foundation

// 原生网络层。页面的 fetch 被 QLBootstrap.js 接管后，请求全部从这里发出去。
//
// 为什么要绕开 WKWebView 自己发：青龙的 CORS 配坏了（cors.origin 是个数组 ['*']，
// 而 cors 包只认字符串 '*'），带 Authorization / application/json 的预检拿不到
// Access-Control-Allow-Origin，浏览器会把 POST / PUT 全拦掉。走 URLSession 就没这回事。

struct QLFormPart {
    let name: String
    let fileName: String?
    let mimeType: String?
    let text: String?
    let data: Data?
}

enum QLBody {
    case none
    case text(String)
    case form([QLFormPart])
}

struct QLResponse {
    let status: Int
    let headers: [String: String]
    let data: Data
}

final class QLNet {

    static let shared = QLNet()

    // ephemeral：不落 cookie / 不缓存，跟安卓端 LocalServer 的行为保持一致
    private let session: URLSession

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 300
        cfg.httpShouldSetCookies = false
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        session = URLSession(configuration: cfg, delegate: QLNetDelegate.shared, delegateQueue: nil)
    }

    func send(urlString: String,
              method: String,
              headers: [String: String],
              body: QLBody,
              completion: @escaping (Result<QLResponse, Error>) -> Void) {

        guard let url = URL(string: urlString), url.scheme != nil else {
            completion(.failure(QLNetError.badURL))
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        switch body {
        case .none:
            break
        case .text(let s):
            req.httpBody = s.data(using: .utf8)
        case .form(let parts):
            let boundary = "----QLFormBoundary" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            req.setValue("multipart/form-data; boundary=" + boundary, forHTTPHeaderField: "Content-Type")
            req.httpBody = QLNet.multipartData(parts: parts, boundary: boundary)
        }

        for (k, v) in headers {
            // Content-Type 由 multipart 分支自己设，别让页面传的覆盖掉边界串
            if k == "content-type", case .form = body { continue }
            req.setValue(v, forHTTPHeaderField: k)
        }

        let task = session.dataTask(with: req) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            let http = response as? HTTPURLResponse
            var hs: [String: String] = [:]
            http?.allHeaderFields.forEach { pair in
                if let k = pair.key as? String, let v = pair.value as? String {
                    hs[k.lowercased()] = v
                }
            }
            completion(.success(QLResponse(status: http?.statusCode ?? 200,
                                           headers: hs,
                                           data: data ?? Data())))
        }
        task.resume()
    }

    private static func multipartData(parts: [QLFormPart], boundary: String) -> Data {
        var d = Data()
        let crlf = "\r\n"
        for p in parts {
            d.append("--\(boundary)\r\n".data(using: .utf8)!)
            if let fn = p.fileName {
                let mime = p.mimeType ?? "application/octet-stream"
                d.append("Content-Disposition: form-data; name=\"\(p.name)\"; filename=\"\(fn)\"\r\n".data(using: .utf8)!)
                d.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
                if let data = p.data { d.append(data) }
            } else {
                d.append("Content-Disposition: form-data; name=\"\(p.name)\"\r\n\r\n".data(using: .utf8)!)
                d.append((p.text ?? "").data(using: .utf8)!)
            }
            d.append(crlf.data(using: .utf8)!)
        }
        d.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return d
    }

    enum QLNetError: LocalizedError {
        case badURL
        case badBase64
        var errorDescription: String? {
            switch self {
            case .badURL: return "面板地址不合法"
            case .badBase64: return "内容解码失败"
            }
        }
    }
}

// 面板基本都是自签 / 明文 http，这里放行所有主机名。
// （ATS 在 Info.plist 里也关了，两处都要开，否则 URLSession 仍会被拦。）
private final class QLNetDelegate: NSObject, URLSessionDelegate {
    static let shared = QLNetDelegate()
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
