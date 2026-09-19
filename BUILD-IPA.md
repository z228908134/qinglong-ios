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
| 最近一次构建 | ✅ 成功（run `35448984429`，commit `eb91d41`） |
| 本地 ipa | `qinglong-ios/out/QingLongClient-1.0.32-trollstore.ipa`（184368 字节） |
| SHA256 | `c03e585a6934b0880d4136314844a1d4870be6fe8d2b2f3f43cf68553a8c830e` |
| 产物保留 | Actions → Artifacts → `QingLongClient-1.0.32-trollstore`（保留 30 天） |

> **1.0.32 就一件事：搜出来的变量不用自己滑着找了**：
> - **搜索框下多一条「↑ 2/4 ↓」**。搜「jd」能出二十来条，分组之后还散在各组里、
>   有的组还折着 —— 以前只能自己滑着找，现在点箭头逐个跳过去，跳到的那条套一圈黄边。
> - **圈的是黄边 outline 不是背景**：背景会跟编辑模式的选中态（`.item.on`）撞在一起，
>   看不出到底跳没跳。黄边沿用「命中」那个黄，两套主题下都看得清。
> - **跳的顺序是页面上看见的顺序**，不是列表原顺序 —— 分组会把顺序重排，
>   照列表顺序跳会「跳回去」（比如跳到第 2 个却是列表里第 4 条）。
> - **目标在折叠的组里会先展开再跳**，否则跳过去是一片空白。
> - **回车 = 下一个、Shift+回车 = 上一个**，跟电脑上「查找下一个」一个意思；
>   回车会先把防抖落下去再跳，不然跳的是上一批旧结果。
> - **换关键字后原来的位置不算数**（拿 id 对一下，对不上就清掉），
>   不会「跳到另一个变量上还圈着它」。
>
> **装 1.0.32，别装 1.0.31 及更早的**。
>
> 历史：1.0.16 是功能版（底栏五项 / 主页 + 近 7 日趋势图 / 日志搜索 / 面板卡头像）；
> 1.0.17 加了头像真图但真机上不显示，已作废；1.0.18 修好头像、加了任务详情三处直达；
> 1.0.19 做了日志级别上色 / 只看错误 / 目录倒序；
> 1.0.21 做了日志内搜关键字 + 详情页状态/按钮实时跟着跑 + 概览今日成功/失败；
> 1.0.22 修好「从详情跳出去回不来」和头像不显示（根因是启动的「已有令牌」路径从不拉头像）；
> 1.0.23 加了任务批量运行/停止 + 任务列表搜索高亮 + 「上次耗时 / 本次已运行」；
> 1.0.27 加了任务列表「下次」加今天/明天前缀 + 去秒数 + 风格统一；
> 1.0.28 加了定时规则旁挂人类可读描述（cron 表达式翻人话）。
> 1.0.29 加了变量页批量复制（换 cookie 时一次抠多个值）；
> 1.0.30 加了变量页按第一标签分组 + 每组可折叠；
> 1.0.31 加了依赖卡片可折叠 + 依赖页批量操作（重装 / 删除 / 强制删除）；
> 1.0.32 加了变量搜索结果的上 / 下一个跳转（命中项逐个跳，折叠组自动展开）。

核对下载到的包对不对：

```bash
sha256sum QingLongClient-1.0.32-trollstore.ipa
# 应该得到 c03e585a6934b0880d4136314844a1d4870be6fe8d2b2f3f43cf68553a8c830e
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

## 这个包跟 PWA 是什么关系

**同一个页面。** iOS 壳装的就是 `qinglong-pwa/index.html` 的构建产物
（`tools/prepare_web.py` 拷进来，CI 会核对页面版本与工程版本一致），
所以脚本树、变量标签、面板概览、外观模式、面板设置三页（应用设置 / 其他设置 / 登录日志）、
上传下载全都一样，不存在「iOS 版功能少一半」。

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
qinglong-ios/out/QingLongClient-1.0.31-trollstore.ipa
```

以后自己下：点进那次成功的构建 → 页面底部 **Artifacts** → `QingLongClient-<版本>-trollstore`
→ 下载得到 zip，解压出同名的 `.ipa`。

### 这个包验过什么

在 ipa 上直接解包核对（不是看构建日志，是把包拆开读）。
**这一整套已经脚本化了**，改完页面出完包跑一句就行，任一项不过会 `exit 1`：

```bash
python tools/verify_ipa.py out/QingLongClient-1.0.32-trollstore.ipa
```

| 检查项 | 结果 |
|---|---|
| `Payload/QingLongClient.app/` 结构 | ✅ 12 个条目 |
| `_CodeSignature/CodeResources`（ad-hoc 签名结构） | ✅ 2961 字节 |
| `index.html` | ✅ 391050 字节，**与本地构建产物逐字节一致** |
| 页面 `APP_VER` | ✅ 1.0.32（与 `MARKETING_VERSION`、ipa 文件名三处一致） |
| `FALLBACK_SERVER` | ✅ `''`（空，不预填面板地址） |
| 页面里有无硬编码真实公网 IP | ✅ 无（只有示例 `1.2.3.4`、回环 `127.0.0.1`、输入框 placeholder `192.168.1.10`） |
| 应用设置（列表 / 8 项权限枚举 / 保留名 / 删除走 id 数组 / 密钥默认打码） | ✅ 5 个锚点全在 |
| 其他设置（读 `data.info` / 备份模块表 / 还原字段 `data` / 还原后调 `update/data` / 时区表） | ✅ 5 个锚点全在 |
| 登录日志（列表加载 / 时间按毫秒） | ✅ 都在 |
| 字号拖动条（`fsRange` / `btnFsDown` / `fsClamp` / 老档位迁移 / `bindFsRange`） | ✅ 都在 |
| 定时视图（`cronViewTabs` / `loadViews` / `/api/crons/views` / `queryString` 透传 / `viewsFailed` / `setView`） | ✅ 6 个锚点全在 |
| 底栏五项（**主页** / 任务 / 变量 / 脚本 / 我的，主页在最左且是新装默认页） | ✅ |
| 我的页入口（订阅管理 / 依赖管理 / 环境变量 / 面板日志 / 应用设置 / 其他设置 / 登录日志） | ✅ 7 个锚点全在 |
| 1.0.16 新增：趋势柱状图 `class="trend"` / `/api/dashboard/trend` `days: 7` | ✅ |
| 1.0.16 新增：面板卡头像 `class="hav"` | ✅ |
| 1.0.16 新增：日志搜索 `id="logSearch"` + `logKeyPath()` | ✅ |
| 1.0.17 新增：头像走 fetch（`await fetch(avStaticUrl(`）/ `blobToDataUrl` / `paintAvatars` / `class="avbig"` | ✅ 4 个锚点全在 |
| 1.0.17 新增：任务详情三处直达（`data-goscript=` / `data-gocronlog=` / `data-gocronlogdir=` / `scriptPathOf` / `shortPath` / `ensureLogTree`） | ✅ 6 个锚点全在 |
| 1.0.18 修复：`.kvrow .v` 的 `min-width:0` / `.btn` 的 `white-space:nowrap` | ✅ 都在 |
| 1.0.19 新增：日志级别上色 `logBoxHtml` / 「只看错误」`id="btnLogErr"` / 行号列 `.logbox .ln{` | ✅ 都在 |
| 1.0.19 新增：日志文件倒序 `sortLogNodes` / 运行后滚到日志区 `scrollToCronLog` | ✅ 都在 |
| 1.0.21 新增：日志内搜索 `logPick` / `logHi` / `id="logFind"` / 「复制匹配行」 | ✅ 都在 |
| 1.0.21 新增：详情页状态实时化 `paintCronState` / `id="cdAct"` / 运行日志上色 | ✅ 都在 |
| 1.0.21 新增：概览补「今日成功 / 今日失败」+ 失败 > 0 标红（`--red`） | ✅ 3 个锚点全在 |
| 1.0.21 新增：详情页运行日志筛选 `paintCronLog` / `id="cronLogFind"` / `id="btnCronLogErr"` / `logPickText` | ✅ 4 个锚点全在 |
| 1.0.22 修复：返回上一页（`function backToCron(` / `if (S.backTo && cronById(S.backTo)) return true;` / 顶栏 `‹` 走同一套） | ✅ 都在 |
| 1.0.22 修复：头像（「已有令牌」路径也拉头像 / 以 `/` 开头的相对路径补面板地址 / 诊断里带头像自检） | ✅ 3 个锚点全在 |
| 1.0.22 新增：面板日志筛选（`paintSysLog` / `id="sysLogFind"` / `id="btnSysLogErr"` / `id="btnSysLogCopy"` / 入口剥 ANSI） | ✅ 5 个锚点全在 |
| 1.0.22 修复：首次画日志跳到底（`var stick = !cl.painted \|\| atBottom(box);` / 贴底余量 48px） | ✅ 都在 |
| 1.0.23 新增：批量运行 / 停止（`data-cbatch="run"` / `data-cbatch="stop"` / 两行布局 / `/api/crons/run` / `/api/crons/stop` 传整组 id） | ✅ 6 个锚点全在 |
| 1.0.23 新增：任务页搜索高亮（复用 `logHi` / 标签也高亮 / `.item .hl` 单开一条写死黄底） | ✅ 3 个锚点全在 |
| 1.0.23 新增：上次耗时 + 本次已运行（`last += ' · 耗时 ' + fmtDur(...)` / `cronElapsed` / `id="cdSinceRow"` / `id="cdSince"` / 只有运行中才算） | ✅ 5 个锚点全在 |
| 1.0.24 修复：变量值「显示值」被单行省略号截断（`.envval.full` 换行 / 显示值切 `.full` / `data-eact="copy"` / 复制的是真实值） | ✅ 4 个锚点全在 |
| 1.0.24 新增：变量批量操作（`id="btnEnvEdit"` / `id="envEditBar"` / `data-ebatch="delete"` / `/api/envs/enable` / `/api/envs/disable` / `/api/envs` DELETE 传整组 id / 全选只作用于筛出来的） | ✅ 7 个锚点全在 |
| 1.0.24 新增：日志「跳到最新」（`id="btnLogTail"` / 浮在弹层之上 / `activeLogBox` / `syncLogTail` / 滚到底 / 关弹层收起） | ✅ 6 个锚点全在 |
| 1.0.24 重构：两条批量栏共用外壳（`openEditShell` / `batchDone` / 一条留白选择器 `#main.cronedit,#main.envsedit`） | ✅ 3 个锚点全在 |
| 1.0.25 新增：趋势图 7/30 天切换（`var TREND_DAYS = [7, 30]` / `setTrendDays` / `pickTrendDay` / `trendReadout` / 密集藏数字 `.trend.d30 .tv{display:none}` / `data-tday="'` / `data-tdays="'`） | ✅ 7 个锚点全在 |
| 1.0.25 新增：主页「正在执行」可点（`data-gocrons="running"` / `gotoCrons`） | ✅ 2 个锚点全在 |
| 1.0.25 新增：脚本树搜索高亮（`logHi(n.title, q)` / 命中在目录上画目录 `hitDir ? '<div ... 在 ' + logHi(r.dir, q) + '/' : ''`） | ✅ 2 个锚点全在 |
| 1.0.25 重构：三个新钩子都进委托（`[data-tdays],[data-tday],[data-gocrons],`） | ✅ 1 个锚点全在 |
| 1.0.26 新增：详情页日志反转（`lines.reverse();`） | ✅ 1 个锚点全在 |
| 1.0.26 新增：方向感知「在新端」（`box.id === 'logBox' ? box.scrollTop < 48 : atBottom(box)`） | ✅ 1 个锚点全在 |
| 1.0.26 新增：方向感知「跳到最新」（`box.id === 'logBox' ? 0 : box.scrollHeight`） | ✅ 1 个锚点全在 |
| 1.0.26 重构：详情页首次画跟顶（`var stick = !cl.painted || box.scrollTop < 48;`） | ✅ 1 个锚点全在 |
| 1.0.27 新增：`fmtNext` 加今天/明天前缀（`sameYMD(d, now) ? '今天' : ...`） | ✅ 1 个锚点全在 |
| 1.0.27 新增：`fmtNext` 函数（`function fmtNext(d) {`） | ✅ 1 个锚点全在 |
| 1.0.27 新增：下次时间去秒数（`return prefix + ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes())`，无 `:SS`） | ✅ 1 个锚点全在 |
| 1.0.27 重构：`nextRunText` 走 `fmtNext`（`return fmtNext(d);`） | ✅ 1 个锚点全在 |
| 1.0.28 新增：`cronHumanize` 函数（`function cronHumanize(sch) {`） | ✅ 1 个锚点全在 |
| 1.0.28 新增：`stepOf` helper（`function stepOf(set, n) {`） | ✅ 1 个锚点全在 |
| 1.0.28 详情页「定时规则」挂人话（`var human = cronHumanize(parseCron(t.schedule));`） | ✅ 1 个锚点全在 |
| 1.0.28 翻不出来不挂（`if (human) h += '<div ... padding:0 14px 8px'...`） | ✅ 1 个锚点全在 |
| 1.0.29 新增：变量批量复制分支（`else if (act === 'copy') {`） | ✅ 1 个锚点全在 |
| 1.0.29 新增：单选裸值 / 多选名=值（`var text = picked.length === 1`） | ✅ 1 个锚点全在 |
| 1.0.29 新增：名=值 拼法带空值兜底（`v.name + '=' + (v.value || '');`） | ✅ 1 个锚点全在 |
| 1.0.29 新增：复制完提前 return（不退出编辑） | ✅ 1 个锚点全在 |
| 1.0.29 新增：批量栏里的复制值按钮（`data-ebatch="copy"`） | ✅ 1 个锚点全在 |
| 1.0.30 新增：分组哨兵键（`var ENV_NO_TAG = '\\u0000none';`） | ✅ 1 个锚点全在 |
| 1.0.30 新增：取第一个标签当分组键（`var key = ls.length ? ls[0] : ENV_NO_TAG;`） | ✅ 1 个锚点全在 |
| 1.0.30 新增：未分类组排最后（`groups.push({ key: ENV_NO_TAG, name: '未分类'`） | ✅ 1 个锚点全在 |
| 1.0.30 新增：渲染走 envGrouped（`box.innerHTML = envGrouped().map(envGroupHtml)...`） | ✅ 1 个锚点全在 |
| 1.0.30 新增：折叠按钮钩子（`data-envcoll="`） | ✅ 1 个锚点全在 |
| 1.0.30 新增：折叠是 toggle（`delete S.envs.collapsed[gk]`） | ✅ 1 个锚点全在 |
| 1.0.30 新增：委托里有折叠（`[data-envcoll]`） | ✅ 1 个锚点全在 |
| 1.0.31 新增：依赖卡默认折起来（`var open = !editing && !!d.open[x.id];`） | ✅ 1 个锚点全在 |
| 1.0.31 新增：展开才渲染行内按钮（`      (open ?` 那一整块） | ✅ 1 个锚点全在 |
| 1.0.31 新增：折叠是 toggle（`delete S.deps.open[id]`） | ✅ 1 个锚点全在 |
| 1.0.31 新增：批量栏四按钮（`data-dbatch="force"`） | ✅ 1 个锚点全在 |
| 1.0.31 新增：重装跳过正在装/删的（`!depWorking(x.status)`） | ✅ 1 个锚点全在 |
| 1.0.31 新增：删除只发已安装的（`x.status === 1`） | ✅ 1 个锚点全在 |
| 1.0.31 新增：三条批量栏共用留白（`cronedit,#main.envsedit,#main.depsedit`） | ✅ 1 个锚点全在 |
| 1.0.31 新增：委托里有依赖钩子（`[data-deps],[data-dbatch],`） | ✅ 1 个锚点全在 |
| 1.0.32 新增：委托里有跳转钩子（`[data-envjump]`） | ✅ 1 个锚点全在 |
| 1.0.32 新增：分支把正负号传进去（`envJump(Number(el.dataset.envjump))`） | ✅ 1 个锚点全在 |
| 1.0.32 新增：渲染时给当前那条加类（`(cur ? ' hitcur' : '')`） | ✅ 1 个锚点全在 |
| 1.0.32 新增：当前套黄边 outline（`.item.hitcur{outline:2px solid #ffd479`） | ✅ 1 个锚点全在 |
| 1.0.32 新增：顺序用分组后的渲染顺序（`envGrouped().forEach`） | ✅ 1 个锚点全在 |
| 1.0.32 新增：列表换过后下标失效（`e.hitId == null \|\| !cur \|\| cur.id !== e.hitId`） | ✅ 1 个锚点全在 |
| 1.0.32 新增：跳到折叠组里会展开（`delete e.collapsed[t.key]`） | ✅ 1 个锚点全在 |
| 1.0.32 新增：跳完重画再滚（`renderEnvs();` 后接 `scrollToEnvHit()`） | ✅ 1 个锚点全在 |
| 1.0.32 新增：滚的是当前圈出来的那条（`#envList .item.hitcur`） | ✅ 1 个锚点全在 |
| 1.0.32 新增：搜索框挂回车跳转（`addEventListener('keydown'`） | ✅ 1 个锚点全在 |
| 1.0.32 新增：Shift+回车是上一个（`envJump(ev.shiftKey ? -1 : 1)`） | ✅ 1 个锚点全在 |
| 1.0.32 新增：换关键字时清掉跳转位置（`S.envs.hit = -1`） | ✅ 1 个锚点全在 |
| 面板日志（`loadSysLog` / `/api/system/log` / DELETE 清空 / `.lv-error` 配色） | ✅ 4 个锚点全在 |
| 时间格式化（`cronMs` 秒→毫秒 / `fmtDur` 运行时长 / `fmtFileTime` birthtime 兜底） | ✅ 3 个锚点全在 |
| 有没有 `window.open` | ✅ 无（它会顺着壳的 `WKUIDelegate` 把 App 导航走，且没有返回入口） |
| 任务页四档筛选 / 多账号切换代码在包里 | ✅ `cronBucket()` / `acctSwitch()` 都在 |
| 字号缩放变量 | ✅ `--fs` 在 |
| `QLBootstrap.js`（接管 fetch + `'ios'` 标记） | ✅ 7368 字节 |
| 桥的 `setBack` / `setTheme` | ✅ 都在 |
| `CFBundleIdentifier` / 版本 | ✅ `com.qinglong.client` / 1.0.32 (32) |
| `CFBundleDisplayName` | ✅ 青龙 |
| `UIDeviceFamily` | ✅ `[1, 2]`（iPhone + iPad） |
| `MinimumOSVersion` | ✅ 15.0 |
| ATS（允许明文 http 到自建面板） | ✅ `NSAllowsArbitraryLoads` + `NSAllowsLocalNetworking` |
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
| 版本 | 1.0.25 |

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

> **忘了跑 `prepare_web.py` 会怎样**：CI 里的 **Sanity check bundled page**
> 会拿页面里的 `APP_VER` 跟 `project.yml` 的 `MARKETING_VERSION` 对账，不一致直接红。
> 但**如果两边都忘了改**（都还是旧版本号），这一关是过得去的 —— 包里装的会是旧页面。
> 所以出包后一定要跑 `verify_ipa.py`：它把包里的 `index.html` 跟**本地构建产物逐字节比**，
> 比只看版本号可靠得多。

### 升版本号的正确顺序

版本号只有两处，**必须同时改**：

| 文件 | 改什么 |
|---|---|
| `qinglong-pwa/src/index.html` | `var APP_VER = 'x.y.z'` |
| `qinglong-ios/project.yml` | `MARKETING_VERSION: "x.y.z"` + `CURRENT_PROJECT_VERSION: "<递增整数>"` |

顺序：改 `APP_VER` → `python tools/build.py` → 改 `project.yml` →
`python tools/prepare_web.py`（这一步会对账，两边不一致直接拒绝写入）。
