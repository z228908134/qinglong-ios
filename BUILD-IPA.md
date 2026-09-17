# 打出能用巨魔（TrollStore）装的 .ipa

> **为什么不能在我这台 Windows 上直接给你 ipa**
> iOS 应用的产物是 Mach-O 二进制，必须由 macOS 上的 `xcodebuild` 产出 —— 它需要 iOS SDK、
> Apple 的 Mach-O 链接器和 `codesign`。Windows 上没有、也装不上这套工具链。
> 任何「不用 Mac 编 iOS 应用」的说法都不成立。
>
> **可行的路**：借 GitHub 免费的 macOS 构建机跑一遍。整个过程你只需要 Windows + 一部 iPhone。

---

## 这个包跟安卓 1.0.9 是什么关系

**同一个页面。** iOS 壳装的就是 `qinglong-pwa/index.html`（安卓 1.0.9 里也是这一份），
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

## 第 1 步：把代码传到 GitHub

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

`git push` 要输的**密码位置填 Personal Access Token**，不是登录密码：
GitHub → Settings → Developer settings → Personal access tokens → **Tokens (classic)**
→ Generate new token (classic) → 勾选 `repo` → 生成后立刻复制。

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

点进那次成功的构建 → 页面底部 **Artifacts** → `QingLongClient-1.0.9-trollstore`
→ 下载得到 zip，解压出 `QingLongClient-1.0.9-trollstore.ipa`。

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

## 兼容性

| 项 | 值 |
|---|---|
| 最低系统 | iOS 15.0 |
| 设备 | iPhone / iPad（`TARGETED_DEVICE_FAMILY: 1,2`） |
| Bundle ID | `com.qinglong.client` |
| 版本 | 1.0.9（跟安卓对齐） |

巨魔本身支持 iOS 14.0 – 16.6.1（17.0 需要特定机型 + 特定巨魔版本）。

---

## 构建失败了怎么办

我这边**没有 Mac，无法本地预跑这条流水线**，第一次有可能报错。如果红了：

1. 点进失败的那次 → 展开红色 ❌ 那一步
2. 把 `error:` 开头的那段发我，我直接改

最常见的几类：

| 报错 | 原因 / 处理 |
|---|---|
| `scheme QingLongClient not found` | `project.yml` 不在仓库根目录，或 `schemes:` 段丢了 |
| `No such module` / brew 失败 | 重跑一次，runner 偶发网络抖动 |
| AppIcon 相关 error | `Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png` 没传上去（网页上传常漏二进制） |
| `index.html 不存在` | 跑一下 `python tools/prepare_web.py` 再提交 |

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
