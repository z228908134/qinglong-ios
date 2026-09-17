import Foundation
import WebKit
import UIKit

// WKWebView 消息桥。页面侧对应的入口在 QLBootstrap.js 里：
//   qlnet    —— 发请求（接管 fetch）
//   qlstate  —— 登录凭据等本地存储
//   qltarget —— 当前面板地址（诊断页会用）
//   qlsave   —— 把下载的文件存下来
//   qlback   —— 页面现在能不能返回上一页（控制左边缘右滑手势的开关）
//   qltheme  —— 页面现在是深色还是浅色（控制状态栏文字颜色）

final class QLBridge: NSObject, WKScriptMessageHandler {

    static let stateKey = "ql.native.state"
    static let targetKey = "ql.native.target"

    weak var webView: WKWebView?
    weak var presenter: UIViewController?

    /* 页面两个「告知」型消息的落点。用闭包而不是直接持有 WebViewController：
       桥不该知道控制器长什么样，而「切手势开关 / 切状态栏样式」本来就该由
       控制器决定怎么落（页面只说事实，不说怎么做）。 */
    var onBackEnabled: ((Bool) -> Void)?
    var onPageDark: ((Bool) -> Void)?

    // 页面脚本里出现的字符串都要先过一遍转义，否则一个引号就能把整段脚本带崩
    static func jsString(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "\\", with: "\\\\")
        out = out.replacingOccurrences(of: "'", with: "\\'")
        out = out.replacingOccurrences(of: "\r", with: "")
        out = out.replacingOccurrences(of: "\n", with: "\\n")
        out = out.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        out = out.replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        out = out.replacingOccurrences(of: "</", with: "<\\/")
        return "'" + out + "'"
    }

    static func savedState() -> String {
        UserDefaults.standard.string(forKey: stateKey) ?? ""
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        /* 注意：qlnet / qlsave 传的是字典，qlstate / qltarget / qltheme 传的是**裸字符串**，
           qlback 传的是**裸布尔**。统一按字典取的话后几个会直接被 guard 挡掉，
           状态根本存不下来 / 手势开关永远不动。 */
        switch message.name {
        case "qlstate":
            if let s = message.body as? String { UserDefaults.standard.set(s, forKey: QLBridge.stateKey) }
        case "qltarget":
            if let s = message.body as? String { UserDefaults.standard.set(s, forKey: QLBridge.targetKey) }
        case "qlback":
            /* JS 的 true/false 过桥后是 NSNumber，`as? Bool` 一般能拿到，
               拿不到就走 NSNumber 兜底 —— 这个值丢了会表现为「右滑完全没反应」。 */
            let on: Bool? = (message.body as? Bool) ?? (message.body as? NSNumber)?.boolValue
            if let on = on { onBackEnabled?(on) }
        case "qltheme":
            if let s = message.body as? String { onPageDark?(s == "dark") }
        case "qlnet":
            guard let body = message.body as? [String: Any] else { return }
            handleNet(body)
        case "qlsave":
            guard let body = message.body as? [String: Any] else { return }
            handleSave(body)
        default:
            break
        }
    }

    // MARK: - 网络

    private func handleNet(_ body: [String: Any]) {
        /* JS 的 number 过桥后是 NSNumber，`as? Int` 有时拿不到（尤其是大整数），
           所以走 NSNumber 再转一次。拿不到 id 就没法回调页面，整个请求会挂住。 */
        let idNum: Int? = (body["id"] as? Int)
            ?? (body["id"] as? NSNumber)?.intValue
        guard let id = idNum, let url = body["url"] as? String else { return }
        let method = (body["method"] as? String) ?? "GET"
        let headers = (body["headers"] as? [String: String]) ?? [:]
        let qlBody = parseBody(body["body"])

        QLNet.shared.send(urlString: url, method: method, headers: headers, body: qlBody) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let res):
                let b64 = res.data.base64EncodedString()
                self.eval("window.__qlNetDone(\(id), \(res.status), \(self.dictLiteral(res.headers)), \(QLBridge.jsString(b64)))")
            case .failure(let err):
                let msg = err.localizedDescription.replacingOccurrences(of: "\"", with: "")
                self.eval("window.__qlNetFail(\(id), \(QLBridge.jsString(msg)))")
            }
        }
    }

    private func parseBody(_ raw: Any?) -> QLBody {
        guard let d = raw as? [String: Any], let t = d["t"] as? String else { return .none }
        if t == "text" { return .text((d["v"] as? String) ?? "") }
        if t == "form" {
            var parts: [QLFormPart] = []
            if let arr = d["p"] as? [[String: Any]] {
                for p in arr {
                    let name = (p["n"] as? String) ?? ""
                    if let b64 = p["b"] as? String, let data = Data(base64Encoded: b64) {
                        parts.append(QLFormPart(name: name,
                                                fileName: (p["f"] as? String) ?? "file",
                                                mimeType: (p["m"] as? String) ?? "application/octet-stream",
                                                text: nil, data: data))
                    } else {
                        parts.append(QLFormPart(name: name, fileName: nil, mimeType: nil,
                                                text: (p["v"] as? String) ?? "", data: nil))
                    }
                }
            }
            return .form(parts)
        }
        return .none
    }

    private func dictLiteral(_ d: [String: String]) -> String {
        // 只透出页面真正会看的几个头，全量塞回去既慢又容易撞上非法字符
        var out = "{"
        var first = true
        for k in ["content-type", "content-disposition"] {
            if let v = d[k] {
                if !first { out += "," }
                out += QLBridge.jsString(k) + ":" + QLBridge.jsString(v)
                first = false
            }
        }
        out += "}"
        return out
    }

    // MARK: - 保存文件

    private func handleSave(_ body: [String: Any]) {
        let name = (body["name"] as? String) ?? "download"
        let b64 = (body["b64"] as? String) ?? ""
        let cbId = (body["id"] as? String) ?? ""
        guard let data = Data(base64Encoded: b64) else {
            callback(cbId, ok: false, msg: "内容解码失败")
            return
        }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(safeName(name))
        do {
            try data.write(to: tmp, options: .atomic)
        } catch {
            callback(cbId, ok: false, msg: "写入临时文件失败")
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.presentShare(url: tmp, cbId: cbId)
        }
    }

    private func safeName(_ n: String) -> String {
        var s = n.replacingOccurrences(of: "/", with: "_")
        s = s.replacingOccurrences(of: ":", with: "_")
        if s.isEmpty { s = "download" }
        return s
    }

    private func presentShare(url: URL, cbId: String) {
        guard let presenter = presenter else {
            callback(cbId, ok: false, msg: "无法弹出保存界面")
            return
        }
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        av.completionWithItemsHandler = { [weak self] _, completed, _, err in
            if completed {
                self?.callback(cbId, ok: true, msg: "手机（在弹层里选的位置）")
            } else {
                self?.callback(cbId, ok: false, msg: err?.localizedDescription ?? "已取消")
            }
        }
        if av.popoverPresentationController != nil {
            av.popoverPresentationController?.sourceView = presenter.view
            av.popoverPresentationController?.sourceRect =
                CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
        }
        presenter.present(av, animated: true)
    }

    // MARK: - 回调页面

    private func callback(_ cbId: String, ok: Bool, msg: String) {
        guard !cbId.isEmpty else { return }
        eval("window.__qlSaved(\(QLBridge.jsString(cbId)), \(ok ? "true" : "false"), \(QLBridge.jsString(msg)))")
    }

    private func eval(_ js: String) {
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
