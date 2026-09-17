import UIKit
import WebKit

// 主界面：一个撑满屏幕的 WKWebView，装的是 qinglong-pwa 产出的单文件 index.html。
// 跟安卓端 1.0.9 是同一份页面，所以功能天然一致（脚本树 / 变量标签 / 面板概览 /
// 外观模式 / 上传下载），不用在 iOS 上重写一遍 UI。

final class WebViewController: UIViewController {

    private var webView: WKWebView!
    private let bridge = QLBridge()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // 页面里的 <input type="file"> 要靠它选文件（上传脚本用）
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let uc = WKUserContentController()
        ["qlnet", "qlstate", "qltarget", "qlsave"].forEach {
            uc.add(bridge, name: $0)
        }
        uc.addUserScript(WKUserScript(source: WebViewController.bootstrapScript(),
                                      injectionTime: .atDocumentStart,
                                      forMainFrameOnly: true))
        config.userContentController = uc

        webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = view.backgroundColor
        webView.navigationDelegate = self
        webView.uiDelegate = self
        bridge.webView = webView
        bridge.presenter = self

        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        loadApp()
    }

    private func loadApp() {
        guard let url = Bundle.main.url(forResource: "index", ofType: "html") else {
            showFatal("没找到内置的 index.html，打包时漏了资源")
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    private func showFatal(_ msg: String) {
        let label = UILabel()
        label.text = msg
        label.textColor = .white
        label.numberOfLines = 0
        label.textAlignment = .center
        label.frame = view.bounds.insetBy(dx: 30, dy: 0)
        view.addSubview(label)
    }

    /// 把 QLBootstrap.js 读出来，并把本地存储的值填进 __QL_STATE_JSON__ 占位符。
    /// 必须放在 atDocumentStart：页面一上来就同步调 QLNative.loadState()。
    private static func bootstrapScript() -> String {
        guard let url = Bundle.main.url(forResource: "QLBootstrap", withExtension: "js"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return "window.__QL_NATIVE__='ios';"
        }
        return raw.replacingOccurrences(of: "__QL_STATE_JSON__",
                                        with: QLBridge.jsString(QLBridge.savedState()))
    }
}

extension WebViewController: WKNavigationDelegate, WKUIDelegate {

    // 页面里 target=_blank / window.open 一律在当前页打开
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(_ webView: WKWebView,
                 didFail navigation: WKNavigation!,
                 withError error: Error) {
        // 首次加载失败时给个能看懂的提示，别停在白屏
        NSLog("[QL] load failed: %@", error.localizedDescription)
    }

    // JS 的 alert/confirm 在 WKWebView 里默认不弹，这里补上（页面里的 confirm 依赖它）
    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let ac = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
        present(ac, animated: true)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let ac = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        ac.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
        present(ac, animated: true)
    }
}
