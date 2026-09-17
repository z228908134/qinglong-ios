import UIKit

// 用经典 UIKit 生命周期（Info.plist 里没有 UIApplicationSceneManifest，
// 所以 iOS 会走 application(_:didFinishLaunchingWithOptions:) + self.window 这条路）。
// 不用 SwiftUI 是为了把编译风险压到最低：这套工程在 CI 上编，我这边没有 Mac 能先跑一遍。

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let win = UIWindow(frame: UIScreen.main.bounds)
        win.rootViewController = WebViewController()
        win.makeKeyAndVisible()
        window = win
        return true
    }
}
