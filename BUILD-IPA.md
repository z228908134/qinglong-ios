# 打出能用巨魔（TrollStore）装的 .ipa

> **为什么不能在我这台 Windows 上直接给你 ipa**
> iOS 应用的产物是 Mach-O 二进制，必须由 macOS 上的 `xcodebuild` 产出 —— 它需要 iOS SDK、
> Apple 的 Mach-O 链接器和 `codesign`。Windows 上没有、也装不上这套工具链。
> 任何「不用 Mac 编 iOS 应用」的说法都不成立。
>
> **可行的路**：借 GitHub 免费的 macOS 构建机跑一遍。

---

## 现状：已经出包了

| 项 | 值 |
|---|---|
| 仓库 | https://github.com/z228908134/qinglong-ios （Private） |
| 分支 | `main` |
| 最近一次构建 | ✅ 成功（run `35228440386`，commit `07083a9`，全部 11 步通过） |
| 本地 ipa | `qinglong-ios/out/QingLongClient-1.0.10-trollstore.ipa`（123662 字节） |
| SHA256 | `6e35a572284df8dd6ad897a466d44ef22b32e7b815db13a5c4bed93690562090` |
| 产物保留 | Actions → Artifacts → `QingLongClient-1.0.10-trollstore`（保留 30 天） |

核对下载到的包对不对：

```bash
sha256sum QingLongClient-1.0.10-trollstore.ipa
# 应该得到 6e35a572284df8dd6ad897a466d44ef22b32e7b815db13a5c4bed93690562090
```

**你现在直接做的事**：把上面那个 ipa 传到手机 → 打开 TrollStore → 右下角 `+` → 选它。
不用再跑构建。

想自己重跑：Actions → Build TrollStore IPA → **Run workflow**。

> 文件名里的版本号是**自动**从 `project.yml` 的 `MARKETING_VERSION` 取的。
> 以前这里是写死的 `1.0.9`：升到 1.0.10 后包内 `Info.plist` 是 1.0.10、文件名却还是
> 1.0.9，下下来根本分不清新旧 —— 已经改成自动取，并在打包时对账一次
> （包内 `CFBundleShortVersionString` 必须等于文件名版本，不等就直接报错）。

### 出包过程中真实踩到的三个坑（已修）

留在这里是因为**换了 Xcode 或 XcodeGen 版本还会再撞上**：

**1. `future Xcode project file format (77)`**

```
xcodebuild: error: Unable to read project 'QingLongClient.xcodeproj'.
Reason: ... it is in a future Xcode project file format (77).
```

XcodeGen **2.45 起把默认工程格式改成了 `xcode16_0`**（pbxproj 里 `objectVersion = 77`），
而 `macos-14` runner 上只有 Xcode 15.4，读不了 77。

→ 修法：`project.yml` 里显式写 `projectFormat: xcode15_3`（实测生成 `objectVersion = 63`，
Xcode 15.x / 16.x 都能打开）；runner 同时升到 `macos-15`。
流水线里加了 **Check project format** 步骤，会把 `objectVersion` 和 Xcode 版本打出来。

**2. `incorrect argument label in call (have 'forResource:ofType:', expected 'forResource:withExtension:')`**

Swift 里取 bundle 资源是 `Bundle.main.url(forResource:withExtension:)`；
`ofType:` 是 `path(forResource:ofType:)` 的标签，**两者不能混用**。
`WebViewController.swift` 里取 `index.html` 和 `QLBootstrap.js` 两处都写错过。

**3. ipa 文件名里的版本号写死**

见上面那段。修法是从 `project.yml` 取，而不是在流水线里再抄一遍版本号 ——
**同一个数字写两处，早晚会有一处忘了改**。

---

## 这个包跟安卓 1.0.10 是什么关系

**同一个页面。** iOS 壳装的就是 `qinglong-pwa/index.html`（安卓 1.0.10 里也是这一份），
所以脚本树、变量标签、面板概览、外观模式、上传下载全都一样，不存在「iOS 版功能少一半」。

壳本身只有五个文件：

| 文件 | 作用 |
|---|---|
| `QingLongClient/App/AppDelegate.swift` | 应用入口（经典 UIKit 生命周期，不用 SwiftUI） |
| `QingLongClient/Web/WebViewController.swift` | 一个撑满屏幕的 `WKWebView` |
| `QingLongClient/Web/QLBootstrap.js` | 注入页面：接管 `fetch` + `QLNative` 桥 |
| `QingLongClient/Web/QLNet.swift` | 用 `URLSession` 真正发请求（含 multipart 组装） |
| `QingLongClient/Web/QLBridge.swift` | 消息桥：网络 / 本地存储 / 保存文件 |

### 关键：为什么要把 fetch 整个接管过来

**青龙的 CORS 是坏的。** `back/config/index.ts` 里默认：

```js
cors: {
  origin: process.env.CORS_ORIGIN ? process.env.CORS_ORIGIN.split(',') : ['*'],
  ...
}
```

注意是 `['*']` —— **数组**。而 `cors` 这个 npm 包只对字符串 `'*'` 放行，数组里的 `'*'`
不会生效。实测你的面板：

| 请求 | 结果 |
|---|---|
| 普通 GET（简单请求） | 回 `Access-Control-Allow-Origin: *` ✅ |
| 带 `Authorization` / `application/json` 的 POST、PUT | **预检不回 `Access-Control-Allow-Origin`** ❌ |

也就是说**只有读操作能在浏览器里跑通，写操作（登录、新建、保存、上传）全被拦**，
而且报错长得很像「接口挂了」，极易误判。

安卓端是起本地 HTTP 服务 + `/api` 反代绕开的。iOS 上自己写 socket 服务风险太高
（这台机器没 Mac，编错了只能靠你来回跑 CI），所以这里改成：

```
页面 fetch()  ──接管──►  QLBootstrap.js  ──WKScriptMessageHandler──►  原生 URLSession  ──►  面板
                                        ◄──── __qlNetDone(status, headers, base64) ────────┘
```

不走浏览器网络栈，就没有同源限制，也完全不碰 CORS。

> `WKURLSchemeHandler` 这条路**行不通**：WebKit 的自定义 scheme 拿不到 POST body，
> 而这个 App 的写操作全是 POST/PUT。
>
> 另外 `QLNative.loadState()` 是**同步**调用的，`WKScriptMessageHandler` 是异步的，
> 所以本地存储不能走桥 —— 原生在创建 `WKUserScript` 时把值直接嵌进了脚本里的
> `__QL_STATE_JSON__` 占位符。

---

## 第 1 步：把代码传到 GitHub —— 已完成，此节留作备查

仓库 `z228908134/qinglong-ios` 已经建好并推上去了。下面这些命令是当初用的，
以后要**另建一个仓库**或者**换台机器**时照着来。

> 本机的 git 是 WorkBuddy 自带的 PortableGit，系统里没装 Git。
> 好消息是它**带了 Git Credential Manager**，第一次 `git push` 会弹浏览器让你
> 登录 GitHub 授权 —— **不需要手搓 Personal Access Token**。

### 关于仓库可见性（重要）

页面里已经**不再预填**任何面板地址（`FALLBACK_SERVER` 是空串），所以建公开仓库也不会泄露。
不过还是建议建 **Private** —— 免得别人拿你的构建机时长。

> 免费账号的私有仓库每月 2000 Actions 分钟，macOS runner 按 10 倍计费 → 约 200 分钟，
> 一次构建 4 分钟左右，够用 40 次。

### 命令行（推荐）

```bash
cd "C:/Users/ZYW/WorkBuddy AI/2026-09-16-21-24-48/qinglong-ios"

git init
git add -A
git commit -m "feat: 青龙面板 iOS 客户端（TrollStore）"
git branch -M main
git remote add origin https://github.com/你的用户名/仓库名.git
git push -u origin main
```

第一次 `git push` 时凭据管理器会**弹出浏览器窗口**让你登录 GitHub 并授权，
点一下就行，不用去生成 token。

（万一没弹出来、而是提示要账号密码：密码位置填 **Personal Access Token**，不是登录密码。
GitHub → Settings → Developer settings → Personal access tokens → **Tokens (classic)**
→ Generate new token (classic) → 勾选 `repo` → 生成后立刻复制。）

### 网页上传

1. 新建空仓库 → **uploading an existing file**
2. 打开 `qinglong-ios` 文件夹，**全选里面的内容**（不是拖文件夹本身）拖进去
3. `.github` 是隐藏目录，网页拖拽经常漏 → 拖完后 **Add file → Create new file**，
   文件名填 `.github/workflows/build-ipa.yml`，把本地文件内容粘进去
4. 上传完确认仓库根目录能同时看到 `project.yml`、`QingLongClient/`、
   `.github/workflows/build-ipa.yml` 这三样

---

## 第 2 步：跑构建

1. 仓库页面 → **Actions** 标签
2. 左侧选 **Build TrollStore IPA**（第一次可能要点 "I understand my workflows, go ahead and enable them"）
3. 右侧 **Run workflow** → 绿色 **Run workflow**
4. 约 **3～5 分钟**，等它变绿 ✅

流水线自己会做三件防呆，任一不过就直接红：

- `index.html` 存在且 > 100 KB（防止漏拷资源）
- 页面里的 `APP_VER` 与 `project.yml` 的 `MARKETING_VERSION` 一致（防止版本对不上）
- 打出的包里真的有 `index.html` 和 `QLBootstrap.js`

---

## 第 3 步：下载 ipa

**这次已经帮你下好了**，就在：

```
qinglong-ios/out/QingLongClient-1.0.10-trollstore.ipa
```

以后自己下：点进那次成功的构建 → 页面底部 **Artifacts** → `QingLongClient-<版本>-trollstore`
→ 下载得到 zip，解压出同名的 `.ipa`。

### 这个包验过什么

在 ipa 上直接解包核对（不是看构建日志，是把包拆开读）：

| 检查项 | 结果 |
|---|---|
| `Payload/QingLongClient.app/` 结构 | ✅ |
| `_CodeSignature/CodeResources`（ad-hoc 签名结构） | ✅ 2961 字节 |
| `index.html` | ✅ 216905 字节 |
| 页面 `APP_VER` | ✅ 1.0.10（与 `MARKETING_VERSION` 一致） |
| `FALLBACK_SERVER` | ✅ `''`（空，不预填面板地址） |
| 页面里有无硬编码真实公网 IP | ✅ 无（只有注释里的示例 `1.2.3.4`） |
| 任务页四档筛选 / 多账号切换代码在包里 | ✅ `cronBucket()` / `acctSwitch()` 都在 |
| 字号缩放变量 | ✅ `--fs` 在 |
| `QLBootstrap.js`（接管 fetch + `'ios'` 标记） | ✅ 7368 字节 |
| 桥的 `setBack` / `setTheme` | ✅ 都在 |
| `CFBundleIdentifier` / 版本 | ✅ `com.qinglong.client` / 1.0.10 (10) |
| `CFBundleDisplayName` | ✅ 青龙 |
| `UIDeviceFamily` | ✅ `[1, 2]`（iPhone + iPad） |
| `MinimumOSVersion` | ✅ 15.0 |
| ATS（允许明文 http 到自建面板） | ✅ `NSAllowsArbitraryLoads: true` |
| `NSLocalNetworkUsageDescription` | ✅ 有（内网 IP 面板需要） |
| 可执行文件 | ✅ arm64 Mach-O（`cputype 0x100000c`），158288 字节 |

---

## 第 4 步：用巨魔装

1. 把 ipa 传到手机（存到「文件」App 里，或 AirDrop / 微信都行）
2. 打开 **TrollStore** → 右下角 **+** → 选那个 ipa（或在「文件」里分享到 TrollStore）
3. 等它装完

**装完是永久签名的，不会 7 天过期，也不需要 Apple ID** —— 这就是巨魔的价值。

### 关于签名

流水线里 `xcodebuild` 完全不签名（CI 上没有开发者账号），出包后补了一步 **ad-hoc 签名**：

```bash
codesign --force --sign - --timestamp=none --generate-entitlement-der Payload/QingLongClient.app
```

这一步不能省：**完全没签名结构的 ipa 巨魔会拒**，ad-hoc 签名有合法结构但不需要证书，
正好配合巨魔的 CoreTrust 绕过。

---

## 壳跟网页对接的三件事（这三个坑都真机上踩过）

页面是「一份网页塞进壳里」，凡是需要跟 iOS 系统打交道的地方，页面自己办不到，
得靠 `QLNative` 桥通知原生。已经处理好的三个：

### 1. 左边缘右滑返回

**症状**：从屏幕左边缘往右划，页面不动。

**根因**：这个页面是单视图 SPA、**完全没用 `history` API**（`pushState` / `popstate` 一个都没有），
所以 `allowsBackForwardNavigationGestures` 背后是一个**空栈** —— 系统手势根本没有「上一页」可回。

**做法**：改成由页面主动声明「现在能不能返回」：

```
页面  canGoBack() 变化  ──►  QLNative.setBack(true/false)  ──►  原生开关 edgePan
原生  右滑手势结束       ──►  evaluateJavaScript("window.__qlBack()")  ──►  页面 closeSheet()/goBack()
```

`edgePan` 是 `UIScreenEdgePanGestureRecognizer`（`edges = .left`），**初始 `isEnabled = false`**，
等页面说「能返回」才打开 —— 否则在登录页右滑也会触发。

> 返回有三层：① 有弹层开着 → 关弹层；② 日志页在下钻 → 回上一级；
> ③ 从「我的」进去的非底栏页面 → 回「我的」。

### 2. 状态栏和页面对不上（顶部一条色带）

**症状**：状态栏区域和页面颜色不一样，边界特别明显。

**根因**：壳把 `WKWebView` 顶在 `safeAreaLayoutGuide.topAnchor` 上，
于是页面里的 `env(safe-area-inset-top)` **恒为 0**，露出来的那一条其实是**壳自己的
`view.backgroundColor`**（`#151316`），而页面是纯黑 `#040205`。

用录屏抽帧做像素采样量过：`y = 0~89` 是 `#151316`，`y = 90` 起才是 `#040205`，
边界正好是安全区高度。

**做法**：`WKWebView` 必须铺满**整个** `view`（`view.topAnchor`，不是 `safeAreaLayoutGuide.topAnchor`），
这样页面自己拿到 `env(safe-area-inset-top)` 去留白。另外壳的背景色跟着深浅走
（`underPageBackgroundColor` + `UIColor { trait in ... }`）。

**顺带一个**：手机是深色、但用户把页面强制成浅色时，状态栏文字还是白的、压在浅色页面上看不见。
所以页面还要通过 `QLNative.setTheme('dark'|'light')` 把**页面**的深浅告诉原生，
原生据此返回 `preferredStatusBarStyle`。

### 3. 字号缩放

**做法**：页面里所有字号写成 `calc(Npx * var(--fs))`，改 `--fs` 即可整体缩放。

**为什么不用 CSS `zoom`**：`zoom` 会把 `env(safe-area-inset-*)` **一起放大**，
跟上面第 2 点的安全区留白相互作用，而这两者的叠加效果**在没有 Mac / 模拟器的机器上验证不了**。
`calc` 的行为是确定的。

**一个易漏点**：`font: 15px/1.45 -apple-system` 这种**简写里的字号不受 `--fs` 影响**，
必须拆成 `font-family` + `font-size: calc(...)` + `line-height`。

---

## 兼容性

| 项 | 值 |
|---|---|
| 最低系统 | iOS 15.0 |
| 设备 | iPhone / iPad（`TARGETED_DEVICE_FAMILY: 1,2`） |
| Bundle ID | `com.qinglong.client` |
| 版本 | 1.0.10（跟安卓对齐） |

巨魔本身支持 iOS 14.0 – 16.6.1（17.0 需要特定机型 + 特定巨魔版本）。

---

## 构建失败了怎么办

流水线本身是通的（已经跑绿过），但**换了 Xcode / XcodeGen 大版本后仍可能再红**。
点进失败的那次 → 展开红色 ❌ 那一步 → 看 `error:` 开头那段。

实际遇到过的：

| 报错 | 原因 / 处理 |
|---|---|
| `future Xcode project file format (77)` | XcodeGen 换了默认工程格式。`project.yml` 里 `projectFormat` 改成 `xcode15_3`（或把 runner 升到更新的 macOS） |
| `incorrect argument label in call (have 'forResource:ofType:', expected 'forResource:withExtension:')` | Swift 取 bundle 资源要用 `withExtension:`，不是 `ofType:` |
| `scheme QingLongClient not found` | `project.yml` 不在仓库根目录，或 `schemes:` 段丢了 |
| `No such module` / brew 失败 | 重跑一次，runner 偶发网络抖动 |
| AppIcon 相关 error | `Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png` 没传上去（网页上传常漏二进制） |
| `index.html 不存在` | 跑一下 `python tools/prepare_web.py` 再提交 |

> **经验**：这轮一共红了三次，前两次都是「改完就提交、没确认改动真的进了 commit」。
> 现在改完 Swift 文件会先 `grep` 一遍磁盘内容再提交 —— 第 53 行的改动就曾经
> 被漏掉过一次，导致第三次 CI 报的还是同一个错。

---

## 改了页面之后要做什么

页面是**作为资源提交进仓库**的（GitHub 上拿不到隔壁的 `qinglong-pwa`），
所以改完 PWA 必须走一遍：

```bash
cd qinglong-pwa && python tools/build.py          # 重新产出 index.html
cd ../qinglong-ios && python tools/prepare_web.py # 拷进来（会顺带对账版本号）
git add -A && git commit -m "update web" && git push
```

然后重跑一次 Actions，下载新 ipa，巨魔里直接覆盖装就行（数据保留）。
