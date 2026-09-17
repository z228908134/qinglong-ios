# 青龙管家 · QingLongClient（iOS）

一个对接 **青龙面板 v2.21.x** 的 iOS 客户端：原生 `WKWebView` 壳 + 与安卓 1.0.10 完全相同的
单文件页面（`qinglong-pwa/index.html`），**零第三方依赖**。
面板地址**留空**，第一次打开自己填（不预填 IP，免得仓库公开后泄露面板地址）。

> ⚠️ **先看这一条**：代码是完整可编译的 iOS 工程，但 **`.ipa` 只能由 macOS + Xcode 产出**，
> Windows 上无法构建（没有 iOS SDK 和签名工具链）。
> **没有 Mac 也能出 ipa** —— 用 GitHub 的免费 macOS 构建机，全程只需要 Windows：
> 见 **[BUILD-IPA.md](BUILD-IPA.md)**。

---

## 一、已实现的功能

| 模块 | 能力 |
| --- | --- |
| 登录 | 面板地址 + 账号密码；支持两步验证（TOTP）自动识别；token 存钥匙串，冷启动免登录；被踢下线自动回登录页 |
| 任务列表 | 分页加载、下拉刷新、服务端搜索（名称/命令/标签）；置顶标记、状态徽标、标签、上次执行时间 |
| 任务筛选 | 工具条四档筛选：**全部 / 运行中 / 未使用 / 已禁用**（按后端 `status` 分档，见下） |
| 任务批量 | 「编辑」进多选模式：全选、批量启用/禁用/删除（删除有二次确认），编辑时底栏自动让位 |
| 任务操作 | 左滑运行/停止，右滑启用/禁用/删除，长按菜单置顶、复制命令、编辑 |
| 任务详情 | 状态、定时规则、**下次执行时间本地推算**、上次执行/开始时间、PID、执行命令；运行/停止/启用/置顶按钮 |
| 运行日志 | 自动拉取 `crons/{id}/log`，运行中每 3 秒自动刷新（可关），ANSI 颜色码清理，全屏查看 + 复制 + 分享 |
| 任务编辑 | 新建/编辑任务，常用 cron 规则一键套用，保存前实时预览下次执行时间 |
| 环境变量 | 列表 + 搜索；**变量值默认打码**、点眼睛临时查看；新建/编辑/删除/启用/禁用；复制值/名称 |
| 脚本管理 | `GET /api/scripts` 脚本树浏览、搜索、查看内容、新建/编辑/删除 |
| 订阅管理 | `GET /api/subscriptions` 订阅列表；新建/编辑/删除、手动运行、启用/禁用、查看日志 |
| 依赖管理 | `GET /api/dependencies` 依赖列表；按类型（nodejs/python/linux）分组、安装/卸载、重新安装 |
| 面板设置 | `GET /api/configs/files` 配置文件列表，`config.sh` 等文件的内容查看与保存 |
| 日志文件 | 面板 `log` 目录树浏览（目录可逐级下钻）、文件内容查看、删除日志文件 |
| 我的 | 账号信息、两步验证状态、面板版本/分支、修改服务器地址、退出登录 |
| 多账号 | 登录历史（最多 8 条，按「用户名@面板地址」去重）；系统设置里一键切换，**不用重输密码**；显示最后登录时间，可删除单条 |
| 系统设置 | 外观模式（跟随系统/浅色/深色）、**字号四档**（小/标准/大/超大）、多账号切换 |

### iOS 壳特有的三件事

这三个是「网页壳」跟系统对接的地方，页面本身感知不到：

| 能力 | 怎么做的 |
| --- | --- |
| **左边缘右滑返回** | 页面是单视图 SPA、没用 `history` API，系统手势背后是空栈。改由页面通过 `QLNative.setBack(bool)` 声明「现在能不能返回」，原生用 `UIScreenEdgePanGestureRecognizer` 开关，回调 `window.__qlBack()` |
| **状态栏自适应** | `WKWebView` 必须铺满**整个** `view`（不能顶在 `safeAreaLayoutGuide` 下面，否则页面 `env(safe-area-inset-top)` 恒为 0，顶部露出一条壳的底色）。页面再通过 `QLNative.setTheme()` 把深浅告知原生，控制状态栏文字颜色 |
| **字号缩放** | 页面里所有字号写成 `calc(Npx * var(--fs))`，**不用 CSS `zoom`** —— `zoom` 会把 `env(safe-area-inset-*)` 一起放大 |

---

## 二、目录结构

```
qinglong-ios/
├── project.yml                     # XcodeGen 工程描述（CI 用它生成 .xcodeproj）
├── README.md
├── BUILD-IPA.md                    # 怎么打出巨魔能装的 ipa（Windows 全流程）
├── .github/workflows/
│   └── build-ipa.yml               # GitHub Actions：archive → ad-hoc 签名 → ipa
├── tools/
│   ├── make_icon.py                # 生成 1024×1024 App 图标（纯标准库）
│   └── prepare_web.py              # 把 qinglong-pwa/index.html 拷进来并核对版本
├── _legacy-swiftui/                # 早期那版纯 SwiftUI 实现（已不用，不参与编译）
└── QingLongClient/
    ├── App/
    │   └── AppDelegate.swift       # @main 入口（经典 UIKit 生命周期）
    ├── Web/
    │   ├── WebViewController.swift # 撑满屏幕的 WKWebView
    │   ├── QLBootstrap.js          # 注入页面：接管 fetch + QLNative 桥
    │   ├── QLNet.swift             # URLSession 发请求（含 multipart 组装）
    │   └── QLBridge.swift          # 消息桥：网络 / 本地存储 / 保存文件
    └── Resources/
        ├── index.html              # qinglong-pwa 的构建产物（跟安卓 1.0.10 同一份）
        ├── Info.plist              # 含 ATS 明文放行配置
        └── Assets.xcassets/
```

---

## 三、怎么编译

### 方式 0：没有 Mac（Windows 用户走这条）

见 **[BUILD-IPA.md](BUILD-IPA.md)**：把代码推到 GitHub，用自带的
`.github/workflows/build-ipa.yml` 在免费 macOS runner 上自动打出
`QingLongClient-<版本>-trollstore.ipa`（版本号从 `project.yml` 的 `MARKETING_VERSION` 自动取），
直接丢进 **TrollStore** 安装。全程不需要 Mac。

### 方式 A：XcodeGen（推荐，最省事）

```bash
brew install xcodegen
cd qinglong-ios
xcodegen generate          # 生成 QingLongClient.xcodeproj
open QingLongClient.xcodeproj
```

然后在 Xcode 里：选中 Target → **Signing & Capabilities** → 勾上 *Automatically manage signing* → Team 选你自己的 Apple ID → 选一台模拟器或真机 → ⌘R。

### 方式 B：手动建工程

1. Xcode → **File → New → Project → iOS → App**
2. Product Name 填 `QingLongClient`，Interface 选 **SwiftUI**，Language 选 **Swift**
3. 删掉 Xcode 自动生成的 `ContentView.swift` 和 `QingLongClientApp.swift`
4. 把 `qinglong-ios/QingLongClient/` 下的所有 `.swift` 拖进工程（勾选 *Copy items if needed*），`Assets.xcassets` 也拖进去
5. **Info.plist 用本仓库里的那份覆盖掉工程的**（关键是里面的 `NSAppTransportSecurity`，否则连 `http://` 面板会被系统直接拒绝）
6. Signing 里选自己的 Team，⌘R

### 装到 iPhone

- **免费 Apple ID**：真机运行可用，但签名 7 天过期，到期后要重新用 Xcode 装一次
- **付费开发者账号**（99 美元/年）：签名有效期 1 年，也可以走 TestFlight 分发
- **侧载工具**（AltStore / Sideloadly）：需要先打出 `.ipa`（Xcode → Product → Archive → Ad Hoc / Development 导出）

---

## 四、接口实现要点（踩过的坑都在这）

| 接口 | 用途 |
| --- | --- |
| `POST /api/user/login` | 登录，返回 `data.token` |
| `PUT /api/user/two-factor/login` | 两步验证登录（`code` + 账号密码） |
| `GET /api/user` | 当前用户（含 `twoFactorActivated`、`avatar`） |
| `GET /api/system` | 面板版本 / 分支 / 更新日志 |
| `GET /api/crons?searchValue=&page=&size=` | 任务列表，返回 `data:{ data:[...], total:n }` |
| `GET /api/crons/{id}` | 单个任务 |
| `PUT /api/crons/run` / `stop` / `enable` / `disable` / `pin` / `unpin` | body 是 **id 数组** |
| `DELETE /api/crons` | body 是 id 数组 |
| `POST` / `PUT /api/crons` | 新建 / 更新任务 |
| `GET /api/crons/{id}/log` | 任务日志，返回 `data:"文本"` + 顶层 `logStatus` |
| `GET /api/envs?searchValue=` | 环境变量列表 |
| `POST` / `PUT` / `DELETE /api/envs`、`/api/envs/enable|disable` | 变量增删改与启停 |
| `GET /api/logs` | 日志目录树（`title/key/type/parent/createTime/size/children`） |
| `GET /api/logs/detail?path=&file=` | 日志文件内容 |
| `DELETE /api/logs` | 删除日志文件 |

### 1. 最容易踩的坑：User-Agent 决定 platform

青龙后端 `getPlatform(UA)` 会把请求分成 `mobile` / `desktop`，登录时把 token 写进 `tokens[platform]`，
后续校验走 `isValidToken(authInfo, headerToken, req.platform)` —— **也是按 platform 取 token**。

所以客户端**每一个请求都必须带完全一致的 UA**，否则会出现「登录成功、下一个请求就 401」的诡异现象。
实现见 `APIClient.userAgent`（固定为包含 `iPhone` 的 UA，因此面板里会显示为 *mobile 端登录*）。

### 2. 任务状态枚举（v2.21 与老版本不同）

```
0 = 运行中 (running)
1 = 未使用 (idle)      ← 青龙网页版叫「未使用」，老文档里写「空闲」
2 = 已禁用 (disabled)
3 = 排队中 (queued)
```

另外任务上还有独立的 `isDisabled` 字段，代码里两个都判断了。

任务页那四档筛选就是按这两个字段分档的（`cronBucket()`）：

| 筛选项 | 命中条件 |
| --- | --- |
| 全部 | 不过滤 |
| 运行中 | `isDisabled !== 1` 且 `status !== 2` 且 `status !== 1`（即 0 和 3） |
| 未使用 | `status === 1` |
| 已禁用 | `isDisabled === 1` 或 `status === 2` |

注意 **3（排队中）归进「运行中」** —— 它也是「在用」的任务，单列一档没有意义。
四档互斥且穷尽：任何一个任务必然落进其中一档，不会漏。

### 3. Joi 严格校验

`POST/PUT /api/crons` 和 `/api/envs` 用的 `celebrate + Joi.object()` **默认不允许未知字段**，
而且 `name: Joi.string()` 不接受空串。所以：

- 请求体里只放后端 schema 声明过的字段（多一个就 400）
- 空值一律**不发送**（Swift 的 Optional + 合成编码器的 `encodeIfPresent` 正好干这个）
- 变量名还要满足 `^[a-zA-Z_][0-9a-zA-Z_]*$`，客户端做了本地校验

### 4. 明文 HTTP 与 ATS

面板跑在 `http://` 上，iOS 默认会拦截。`Info.plist` 里已经配好：

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoads</key><true/>
  <key>NSAllowsLocalNetworking</key><true/>
</dict>
```

如果面板在内网 IP（192.168.x.x / 10.x.x.x），iOS 14+ 还会弹「本地网络」权限，`NSLocalNetworkUsageDescription` 也已加上。

### 5. 其他

- 日志文件里带终端 ANSI 颜色转义，客户端做了清理（`String.strippingANSI`）
- 时间戳字段（`last_execution_time` 等）单位是**毫秒**，不是秒
- 6 段 cron（带秒）也支持，但「下次执行时间」按分钟粒度估算

---

## 五、没做的部分（有意留的边界）

- 运行实例列表 `/api/crons/{id}/instances`、单实例停止
- 任务的历史日志文件列表 `/api/crons/{id}/logs`
- 定时视图（views）—— 面板的「定时」聚合页，本客户端用任务页的四档筛选替代

App 图标已生成（`tools/make_icon.py`，纯标准库画的 1024×1024 闪电图标，改配色重跑即可）。

---

## 六、安全提醒

1. **明文 http = 密码和 token 在网络里裸奔**。这台面板挂在公网 IP 上，用 `http://` 登录时，
   运营商链路、公共 Wi-Fi 上的任何人都可能抓到你的账号密码和 JWT。
   强烈建议：**给面板配 HTTPS**（Nginx/Caddy 反代 + Let's Encrypt 证书），然后客户端里把地址换成 `https://...`。
2. 建议开启面板的两步验证，客户端已支持。
3. 令牌存在系统钥匙串（`kSecAttrAccessibleAfterFirstUnlock`），不写入 UserDefaults，不上传任何第三方。

---

## 七、没有 Mac 怎么办

`.ipa` 只能由 macOS 上的 `xcodebuild` 产出（需要 iOS SDK + Mach-O 链接器 + codesign），
Windows 上没有这套工具链。三条可行路径：

1. **GitHub Actions 的免费 macOS runner**（推荐，全程 Windows）——
   **不需要开发者证书**，先出一个未签名的 ipa，再用 Sideloadly 拿你自己的免费 Apple ID 签名安装。
   完整步骤见 **[BUILD-IPA.md](BUILD-IPA.md)**。
2. **借一台 Mac**（旧款 MacBook Air 也行），装 Xcode 15 就能跑通上面「方式 A」。
   有 99 美元/年的开发者账号的话，签名有效期 1 年，比免费账号的 7 天省心。
3. **改用 PWA**：单文件网页，iPhone 用 Safari 打开 →「添加到主屏幕」，图标和全屏体验接近原生，
   **不需要 Mac、不需要签名、不会 7 天过期**，功能可以做到和本客户端一致（任务/日志/变量）。
