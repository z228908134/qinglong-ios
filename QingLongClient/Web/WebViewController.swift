import UIKit
import WebKit

// 主界面：一个撑满屏幕的 WKWebView，装的是 qinglong-pwa 产出的单文件 index.html。
// 跟安卓端 1.0.9 是同一份页面，所以功能天然一致（脚本树 / 变量标签 / 面板概览 /
// 外观模式 / 上传下载），不用在 iOS 上重写一遍 UI。

final class WebViewController: UIViewController {

    private var webView: WKWebView!
    private let bridge = QLBridge()

    /// 左边缘右滑 = 返回上一页。
    ///
    /// 页面是**单视图 SPA，完全没用 history API**（底部 tab 切视图 + 弹层），
    /// 所以 WKWebView 自带的 `allowsBackForwardNavigationGestures` 是死的 ——
    /// 它背后根本没有历史栈。改成：页面通过 `QLNative.setBack(bool)` 告诉原生
    /// 「现在能不能返回」，原生据此开关这个手势；触发时回调页面里的 `window.__qlBack()`，
    /// 由页面自己决定退回哪一层（弹层 → 日志上一级 → 底栏）。
    private lazy var edgePan = UIScreenEdgePanGestureRecognizer(
        target: self, action: #selector(onEdgePan(_:)))

    /// 页面当前是不是深色。默认跟系统（页面默认外观是「跟随系统」），
    /// 页面 boot() 一跑就会通过 `qltheme` 把真实值送过来覆盖它。
    private var pageIsDark = UITraitCollection.current.userInterfaceStyle == .dark

    /// 状态栏文字颜色必须跟**页面**走，不能只跟系统走。
    /// 反例：手机是深色、用户在设置里把页面强制成浅色 —— 状态栏还是白字，
    /// 压在浅色页面上基本看不见。
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return pageIsDark ? .lightContent : .darkContent
    }

    /// 壳自己的底色，只负责「页面还没画出来」那一瞬间（冷启动、加载失败白屏）。
    /// 页面一渲染就被自己的 `--bg` 盖住。
    private static let bgLight = UIColor(red: 0.949, green: 0.949, blue: 0.969, alpha: 1) // #f2f2f7
    private static let bgDark = UIColor(red: 0, green: 0, blue: 0, alpha: 1)             // #000000

    /// 写死深灰的话，浅色模式下每次冷启动都会先闪一下黑。
    private static var pageBackground: UIColor {
        return UIColor { tc in tc.userInterfaceStyle == .dark ? bgDark : bgLight }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = WebViewController.pageBackground

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // 页面里的 <input type="file"> 要靠它选文件（上传脚本用）
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let uc = WKUserContentController()
        /* qlback / qltheme 是页面「告知」原生的两个消息，名字必须和
           QLBootstrap.js 里 postMessage 的通道名一字不差 —— 对不上的话
           postMessage 会抛异常（页面里 catch 掉了），表现为手势永远不生效、
           状态栏字色永远不翻。 */
        ["qlnet", "qlstate", "qltarget", "qlsave", "qlback", "qltheme"].forEach {
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
        webView.scrollView.backgroundColor = .clear
        if #available(iOS 15.0, *) {
            // 页面滚过头（橡皮筋）时露出来的底色。不设的话是白色，深色模式下很跳。
            webView.underPageBackgroundColor = WebViewController.pageBackground
        }
        webView.navigationDelegate = self
        webView.uiDelegate = self
        bridge.webView = webView
        bridge.presenter = self
        bridge.onBackEnabled = { [weak self] on in self?.edgePan.isEnabled = on }
        bridge.onPageDark = { [weak self] dark in self?.applyPageDark(dark) }

        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            /* 铺满**整个** view，不能顶在 safeAreaLayoutGuide 下面。
               页面本来就是按 edge-to-edge 设计的：viewport-fit=cover +
               `--top:env(safe-area-inset-top,0px)`，顶栏和底栏各自把安全区加进自己的内边距。
               WebView 一顶到安全区下方，env() 就恒为 0，状态栏那一条露出的是**壳的背景色**，
               跟页面底色对不上 —— 就是用户截图里那道难看的色带。 */
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        /* 页面没用到 history API，系统那个前进/后退手势背后是空栈，
           开着只会跟边缘手势抢触摸。 */
        webView.allowsBackForwardNavigationGestures = false
        edgePan.edges = .left
        edgePan.isEnabled = false   // 等页面说「能返回」再打开
        webView.addGestureRecognizer(edgePan)

        loadApp()
    }

    /// 页面通过 `qltheme` 送来的当前深浅。只在真的变了的时候刷状态栏，
    /// 免得每次 applyTheme 都触发一次无谓的外观重算。
    private func applyPageDark(_ dark: Bool) {
        if pageIsDark == dark { return }
        pageIsDark = dark
        /* 必须显式通知：状态栏样式不会自己重算，要等到下一次转屏之类的事件才更新。 */
        setNeedsStatusBarAppearanceUpdate()
    }

    /// 手势结束才回调页面（拖到一半松手前不动）。页面里 `__qlBack()` 返回布尔，
    /// 但这里不需要结果 —— 页面自己会再调一次 `syncBack()` 把新的可返回状态送回来，
    /// 原生只管跟着开关手势，不自己维护状态机。
    @objc private func onEdgePan(_ g: UIScreenEdgePanGestureRecognizer) {
        guard g.state == .ended else { return }
        webView.evaluateJavaScript("window.__qlBack && window.__qlBack()", completionHandler: nil)
    }

    private func loadApp() {
        guard let url = Bundle.main.url(forResource: "index", withExtension: "html") else {
            showFatal("没找到内置的 index.html，打包时漏了资源")
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    private func showFatal(_ msg: String) {
        let label = UILabel()
        label.text = msg
        // 用 .label 而不是 .white：浅色模式下白字压在浅色底上等于没写
        label.textColor = .label
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
