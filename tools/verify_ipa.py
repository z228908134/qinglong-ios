# -*- coding: utf-8 -*-
"""解包 ipa 逐项核对 —— 不是看构建日志，是把包拆开读。

用法：
    python tools/verify_ipa.py out/QingLongClient-1.0.14-trollstore.ipa
    python tools/verify_ipa.py <ipa> --pwa ../qinglong-pwa

为什么要单独写一个脚本：CI 日志只证明「打包这一步没报错」，
证明不了「包里装的页面是新的」。曾经出现过改了 PWA 忘了 prepare_web.py
就 push，CI 全绿、装到手机上功能还是老的。所以出包后一律解包读一遍。

检查项：
  1. 包结构（index.html / QLBootstrap.js / Info.plist / 可执行文件 / 签名）
  2. 内置页面：字节数、与本地构建产物**逐字节一致**、APP_VER、不预填面板地址
  3. 各功能代码是否真在包里（应用设置 / 其他设置 / 登录日志 / 字号拖动条 / 定时视图 /
     底栏四项 / 面板日志 / 三个时间格式化函数）
  4. 不该出现的东西（window.open、真实公网 IP）
  5. Info.plist 关键键（Bundle ID / 版本 / ATS / 本地网络权限）
  6. 可执行文件架构（arm64 Mach-O）
  7. ad-hoc 签名结构（完全没签名的 ipa 巨魔会拒）
"""
import argparse
import hashlib
import os
import plistlib
import re
import struct
import sys
import zipfile

APP = "Payload/QingLongClient.app/"

# 功能锚点：(显示名, 正则)。这些字符串是**代码里真实存在**的标识，
# 不是文案 —— 文案改一个字就失配，锚在函数名/变量名上才稳。
FEATURES = [
    ("应用设置 列表加载", r"function loadApps\("),
    ("应用设置 权限枚举", r"var APP_SCOPES = \["),
    ("应用设置 保留名", r"var APP_RESERVED = 'system'"),
    ("应用设置 删除走 id 数组", r"body: \[Number\(id\)\]"),
    ("应用设置 密钥默认打码", r"data-secret="),
    ("其他设置 配置加载", r"function loadSysconf\("),
    ("其他设置 读 data.info", r"r\.data\.info"),
    ("其他设置 备份模块表", r"var BACKUP_MODULES = \["),
    ("其他设置 还原字段 data", r"fd\.append\('data'"),
    ("其他设置 还原后 update/data", r"'/api/update/data'"),
    ("其他设置 时区表", r"var TZ_COMMON = \["),
    ("登录日志 列表加载", r"function loadLoginLog\("),
    ("登录日志 时间按毫秒", r"new Date\(Number\(ms\)\)"),
    ("百分比夹在 0-100", r"return Math\.max\(0, Math\.min\(100, n\)\)"),
    ("字号 拖动条元素", r'id="fsRange"'),
    ("字号 两端 A", r'id="btnFsDown"'),
    ("字号 夹取防 NaN", r"function fsClamp\("),
    ("字号 老档位迁移", r"Object\.prototype\.hasOwnProperty\.call\(FS, v\)"),
    ("字号 滑杆重绑", r"function bindFsRange\("),
    ("定时视图 挂载点", r'id="cronViewTabs"'),
    ("定时视图 列表加载", r"function loadViews\("),
    ("定时视图 接口路径", r"/api/crons/views"),
    ("定时视图 透传 queryString", r"q\.queryString = JSON\.stringify\("),
    ("定时视图 降级标志", r"viewsFailed"),
    ("定时视图 切 tab", r"function setView\("),
    # 底栏五项：主页 / 任务 / 变量 / 脚本 / 我的（1.0.16 在最左加了「主页」）。
    # 主页必须在最左 —— 用户说的是「任务栏左边」。锚在字面量上，顺序由 E2a 那组测。
    ("底栏 有主页", r'<button data-tab="home"><span class="ti">◰</span>主页</button>'),
    ("底栏 有我的", r'data-tab="me"'),
    # 1.0.16 新增：趋势图 / 面板卡头像 / 日志搜索
    ("趋势 柱状图容器", r"class=\"trend'"),
    # 1.0.25：days 从写死 7 换成 d.trendDays || 7（接口本身还是 /api/dashboard/trend）。
    ("趋势 接口 days=N", r"/api/dashboard/trend', \{ days: d\.trendDays"),
    ("面板卡 头像", r'class="hav"'),
    ("日志 搜索框（面板日志）", r'id="logSearch"'),
    ("日志 key 拆前缀", r"function logKeyPath\("),
    # 功能网格的卡片：data-goto 是 featCard() 运行时拼出来的（`data-goto="' + f.tab + '"`），
    # 产物里搜不到 data-goto="subs" 这种字面量 —— 只能锚 FEATURES 表里的条目。
    # （第一版就锚错了，跑出来「缺失 !!」，白惊一场。）
    ("我的页 订阅管理入口", r"\{ tab: 'subs',"),
    ("我的页 依赖管理入口", r"\{ tab: 'deps',"),
    ("我的页 环境变量入口", r"\{ tab: 'envs',"),
    ("我的页 面板日志入口", r"\{ tab: 'syslog',"),
    # 这三个跟弹层里那份重名，但走的是功能网格：data-goto 由 featCard() 运行时拼，
    # 产物里搜不到字面量，只能锚 FEATURES 表条目。
    # （第一版锚成了弹层的 data-goto="apps"，弹层一撤就「缺失 !!」，白惊一场。）
    ("我的页 应用设置入口", r"\{ tab: 'apps',"),
    ("我的页 其他设置入口", r"\{ tab: 'sysconf',"),
    ("我的页 登录日志入口", r"\{ tab: 'loginlog',"),
    ("面板日志 列表加载", r"function loadSysLog\("),
    ("面板日志 纯文本接口", r"/api/system/log"),
    ("面板日志 清空走 DELETE", r"\{ method: 'DELETE' \}"),
    ("面板日志 级别配色", r"\.logbox \.lv-error\{"),
    # 1.0.17 头像：真机不显示的根因是**把 URL 直接塞进 <img src>**
    # （iOS 是 file:// 源、安卓走回环代理，子资源加载没保证）。
    # 改成 fetch 取 blob → 转 data: URL 才显示得出来 —— 锚在这条链上。
    ("头像 走 fetch 取图", r"await fetch\(avStaticUrl\("),
    ("头像 转 data: URL", r"function blobToDataUrl\("),
    ("头像 异步到位后就地换", r"function paintAvatars\("),
    ("头像 大图弹层", r'class="avbig"'),
    ("头像 失败三处一起退回", r"\$\$\('\.hav, \.acct \.av, #tabAv'\)"),
    # 1.0.17 后半：任务详情 → 脚本 / 日志 直达（照面板网页版的任务详情）
    ("详情 脚本直达", r"data-goscript="),
    ("详情 最新日志直达", r"data-gocronlog="),
    # 1.0.38：原来那条直接跳日志页（data-gocronlogdir），现在是独立的历史日志页。
    ("详情 日志历史直达", r"data-gocronlogs="),
    ("详情 命令里抠脚本路径", r"function scriptPathOf\("),
    ("详情 长路径缩略显示", r"function shortPath\("),
    ("详情 补日志树不碰 path", r"async function ensureLogTree\("),
    # 1.0.18 布局修复：两条都是预览截图里肉眼看到的
    ("布局 长值不挤掉右箭头", r"\.kvrow \.v\{flex:1;min-width:0;"),
    ("布局 按钮文案不换行", r"white-space:nowrap;background:var\(--fill\)"),
    # 1.0.19 日志查看：长日志里靠肉眼扫找报错不现实
    ("日志 级别上色重排", r"function logBoxHtml\("),
    ("日志 只看错误筛选", r'id="btnLogErr"'),
    ("日志 行号列", r"\.logbox \.ln\{"),
    ("日志 打开贴到底", r"function paintLogFile\("),
    ("日志 文件倒序（最新在上）", r"function sortLogNodes\("),
    ("日志 运行后滚到日志区", r"function scrollToCronLog\("),
    # 1.0.20 日志内搜关键字 + 详情页状态实时化
    ("日志 关键字搜索过滤", r"function logPick\("),
    ("日志 命中高亮", r"function logHi\("),
    ("日志 搜索框（运行日志）", r'id="logFind"'),
    ("日志 复制匹配行", r"复制匹配行"),
    ("详情 状态徽标就地重画", r"function paintCronState\("),
    ("详情 主按钮跟着状态变", r'id="cdAct"'),
    # 1.0.21：这行从 loadCronLog 搬进了 paintCronLog，变量名也从 lines 变成 cl.lines。
    # 锚点绑字面量，搬一次家就要改一次 —— 不改就是出包后验货报一项没过。
    ("详情 运行日志上色", r"box\.innerHTML = cl\.lines\.length \? logBoxHtml\("),
    # 1.0.21 概览补六格 + 运行日志筛选 + 贴底策略
    ("概览 今日成功格", r", '今日成功', "),
    ("概览 今日失败格", r", '今日失败', "),
    ("概览 失败标红", r"\.stats \.n\.bad\{color:var\(--red\)\}"),
    ("详情 运行日志重画", r"function paintCronLog\("),
    ("详情 运行日志搜索框", r'id="cronLogFind"'),
    ("详情 只看错误按钮", r'id="btnCronLogErr"'),
    ("详情 复制走筛选后的原文", r"function logPickText\("),
    # 1.0.22：1.0.21 加的这条锚的是内联的阈值比较，1.0.22 把阈值抽进了
    # atBottom() —— 字面量搬家，锚点就得跟着搬。不改的话出包后这里会报
    # 「详情 只在贴底时贴底 缺失 !!」，白折腾一轮 CI。
    ("详情 只在贴底时贴底", r"if \(atBottom\(el\)\) el\.scrollTop = el\.scrollHeight;"),
    ("详情 贴底余量 48px", r"return el\.scrollHeight - el\.scrollTop - \(el\.clientHeight \|\| 0\) < 48;"),
    # 1.0.22 新增：① 从任务详情跳出去之后要能返回上一页
    ("返回 回来源任务", r"function backToCron\(\)"),
    ("返回 能返回的判断", r"if \(S\.backTo && cronById\(S\.backTo\)\) return true;"),
    ("返回 顶栏走同一套", r"if \(!goBack\(\)\) setTab\('me'\);"),
    ("返回 来源只用一次", r"S\.backTo = null;"),
    # 1.0.22 新增：② 头像（根因是 boot 的「已有令牌」路径以前不拉头像）
    ("头像 已有令牌路径也拉", r"loadAvatar\(\)\.then\(paintAvatars\);"),
    ("头像 相对路径补面板地址", r"if \(f\.charAt\(0\) === '/'\) return apiBase\(\) \+ f;"),
    ("头像 连接诊断自检", r"async function diagAvatar\(\)"),
    # 1.0.22 新增：③ 面板日志补搜索 / 只看错误 / 复制（和另外两处日志界面统一）
    ("面板日志 重画", r"function paintSysLog\("),
    ("面板日志 搜索框", r'id="sysLogFind"'),
    ("面板日志 只看错误按钮", r'id="btnSysLogErr"'),
    ("面板日志 复制按钮", r'id="btnSysLogCopy"'),
    ("面板日志 剥 ANSI 在入口", r"g\.text = stripAnsi\(text \|\| ''\);"),
    # 1.0.22 新增：④ 首次画日志直接跳到底（1.0.21 引入的回归）
    ("日志 第一次画跳到底（面板日志，#logPre 正序贴底，1.0.26 没改它）",
    r"var stick = !g\.painted \|\| atBottom\(pre\);"),
    # 1.0.23 新增：① 批量运行 / 批量停止。编辑模式以前只有启用 / 禁用 / 删除，
    # 最常用的「把这几个都跑一遍」反而得一个个点进详情页。
    ("批量 运行按钮", r'data-cbatch="run"'),
    ("批量 停止按钮", r'data-cbatch="stop"'),
    ("批量 拆两行", r"gap:8px;margin-bottom:8px"),
    ("批量 运行走 run 接口", r"await api\('/api/crons/run', \{ method: 'PUT', body: send \}\)"),
    ("批量 停止走 stop 接口", r"await api\('/api/crons/stop', \{ method: 'PUT', body: send \}\)"),
    # 批量栏比底栏高一截，列表底部留白要跟着加，不然最后一张卡片被盖住。
    # 1.0.24：变量页也加了批量栏，两条栏同高，这条规则并成了一条选择器 ——
    # 锚点绑字面量，CSS 改写法就得跟着改，不然出包后这里报一项缺失。
    ("批量 编辑模式加留白", r"#main\.cronedit,#main\.envsedit,#main\.depsedit,#main\.subsedit\{padding-bottom:calc\(168px \+ var\(--bot\)\)\}"),
    # 1.0.23 新增：② 任务列表搜索命中高亮（复用日志那套 logHi，体验统一）
    ("列表 命中高亮复用 logHi", r"logHi\(t\.name \|\| '未命名任务', c\.q\)"),
    ("列表 标签也高亮", r"logHi\(l, c\.q\)"),
    # `.logbox .hl` 出了日志框不生效 —— 列表必须单开一条，写死黄底（两套主题都看得清）
    ("列表 高亮单开一条", r"\.item \.hl\{background:#ffd479;color:#1a1200;border-radius:2px\}"),
    # 1.0.23 新增：③ 「上次耗时」与「本次已运行」
    # last_running_time 是**秒数**（不是时间点），面板一直有、页面只在详情页画了「上次运行」；
    # 脚本越跑越慢是京东类任务最常见的毛病，列表行里挂一个耗时一眼就能看出来。
    ("列表 上次耗时", r"last \+= ' · 耗时 ' \+ fmtDur\(t\.last_running_time\)"),
    ("详情 本次已运行函数", r"function cronElapsed\("),
    ("详情 本次已运行行", r'id="cdSinceRow"'),
    ("详情 本次已运行数字", r'id="cdSince"'),
    # 排队中（status 3）时 last_execution_time 还是**上一次**跑的时间，
    # 不判断状态会算出「十几小时」这种离谱值
    ("详情 只有运行中才算本次", r"var running = t\.status === 0;"),
    # 两个时间字段的单位都跟直觉相反，写错了不报错、只是显示成 1970
    ("时间 秒级时间戳换算", r"function cronMs\("),
    ("时间 运行时长格式化", r"function fmtDur\("),
    ("时间 文件时间兜底", r"function fmtFileTime\("),
    # 1.0.24 新增：① 变量的值「显示值」以前被 .ell 的单行省略号截断 ——
    # 京东 cookie 一百多字符只显示前 40 来个，等于没显示；手机上想核对 pt_pin
    # 只能长按选中再拖手柄，两三百个字符根本抠不出来。所以：完整换行 + 一键复制。
    ("变量 值完整显示样式", r"\.envval\.full\{white-space:normal;word-break:break-all"),
    ("变量 显示值切到完整", r"line\.classList\.toggle\('full', !shown\);"),
    ("变量 复制按钮", r'data-eact="copy"'),
    # 复制的是**真实值**（不是打码的那份），也不用先点「显示值」
    ("变量 复制的是真实值", r"copyText\(v\.value \|\| ''\)"),
    # 1.0.24 新增：② 变量页批量操作（照任务页 1.0.23 那套：编辑模式 + 两行操作栏）。
    # 京东 cookie 一堆账号时逐个点行内按钮太慢，「换 cookie 时把过期的删掉」是常规操作。
    ("变量 编辑按钮", r'id="btnEnvEdit"'),
    ("变量 批量栏容器", r'id="envEditBar"'),
    ("变量 批量删除按钮", r'data-ebatch="delete"'),
    ("变量 批量启用接口", r"await api\('/api/envs/enable', \{ method: 'PUT', body: send \}\)"),
    ("变量 批量禁用接口", r"await api\('/api/envs/disable', \{ method: 'PUT', body: send \}\)"),
    ("变量 批量删除接口", r"await api\('/api/envs', \{ method: 'DELETE', body: send \}\)"),
    # 全选只作用于**筛出来的**那些：筛了「京东」再点全选，用户想处理的就是这些
    ("变量 全选按筛选结果", r"function envFiltered\("),
    # 两条批量栏（任务 / 变量）共用外壳与样式 —— 各写一份迟早会出现
    # 「变量页底栏没藏、最后一张卡片被盖住」这种只坏一边的问题。
    # 重构时把这段从 renderCronEditBar 里搬进了 openEditShell，锚点也得跟着搬。
    ("批量 外壳两条栏共用", r"function openEditShell\("),
    ("批量 完成提示共用", r"function batchDone\("),
    # 1.0.24 新增：③ 日志「跳到最新」—— 1.0.21 的贴底策略只在本来就贴着底时才跟随，
    # 往上翻看报错之后就停在那儿了，回最新只能自己一路滑到底。
    ("日志 跳到最新按钮", r'id="btnLogTail"'),
    ("日志 跳到最新浮在弹层上", r"#btnLogTail\{position:fixed;"),
    ("日志 当前日志框判定", r"function activeLogBox\("),
    ("日志 只在离开底部时露出", r"function syncLogTail\("),
    ("日志 跳到最新滚到底（1.0.26 起详情页跳顶，#logPre 仍跳底 → 改成锚 jumpNewest 内的分支）",
    r"box\.id === 'logBox' \? 0 : box\.scrollHeight;"),
    # 关弹层必须**显式**收起：#shB 的内容不会清空，不收的话那个按钮会一直浮在主页上
    ("日志 关弹层收起按钮", r"var lt = \$\('#btnLogTail'\);\s*if \(lt\) lt\.classList\.add\('hidden'\);"),
    # 1.0.25 新增：① 趋势图 7 / 30 天切换。7 天看不出「是不是越来越常失败」，
    # 30 天才看得出（点柱子还能看那天具体多少次 —— 密集模式下柱顶数字被藏了）。
    ("趋势 两档常量", r"var TREND_DAYS = \[7, 30\]"),
    ("趋势 切档函数", r"async function setTrendDays\("),
    ("趋势 点柱子", r"function pickTrendDay\("),
    ("趋势 读数函数", r"function trendReadout\("),
    ("趋势 密集藏数字", r"\.trend\.d30 \.tv\{display:none\}"),
    ("趋势 柱子钩子", r'data-tday="\''),
    ("趋势 切换钩子", r'data-tdays="\''),
    # 1.0.25 新增：② 主页「正在执行 N 个」可点 → 跳任务页「运行中」筛选
    # （之前只能看个数字，想知道哪几个还得切过去再点一次筛选）。
    ("概览 跳转钩子", r'data-gocrons="running"'),
    ("概览 跳转函数", r"async function gotoCrons\("),
    # 1.0.25 新增：③ 脚本树搜索命中上黄底（跟任务列表 1.0.23 / 变量页统一）。
    # 不加这条就会出现「任务列表搜出来有黄底、变量页有、脚本树偏偏没有」的怪事。
    ("脚本树 命中高亮", r"logHi\(n\.title, q\)"),
    # 命中只在父目录名上时（文件名一个命中都没有），把目录画出来，
    # 否则用户不知道这个文件为什么出现在搜索结果里。文件名缩进变化可能把锚点打散 —— 整行锚。
    ("脚本树 命中在目录上画目录", r"hitDir \? '<div class=\"f11 t3 ell\">在 ' \+ logHi\(r\.dir, q\) \+ '/<\/div>' : ''\)"),
    # 三个新钩子都进了委托：漏一个就是「点了没反应」且最难查
    ("委托 新钩子", r"\[data-tdays\],\[data-tday\],\[data-gocrons\],"),

    # 1.0.26 新增：任务详情运行日志**倒序**（最新在上，报错总在末尾 → 现在一眼就到）。
    # loadCronLog 拿完日志调 reverse() 再存到 S.cronlog.lines；AG1 锚着这行。
    ("详情页日志 反转", r"lines\.reverse\(\);"),
    # 方向感知的「在新端」判断 —— #logBox（详情页倒序）贴顶、#logPre（文件弹层正序）贴底。
    ("日志 在新端判断（按 box.id 分两边）", r"box\.id === 'logBox' \? box\.scrollTop < 48 : atBottom\(box\)"),
    ("日志 跳到最新（按 box.id 分两边）", r"box\.id === 'logBox' \? 0 : box\.scrollHeight"),
    # paintCronLog 用「贴顶」做贴新端判断（1.0.21 那条 AC32 的字面量也改了）。
    ("详情页日志 首次画跟顶", r"var stick = !cl\.painted \|\| box\.scrollTop < 48;"),

    # 1.0.27：下次执行时间显示优化（之前是 `MM-DD HH:MM:SS`，秒数永远 :00 占位、
    # 跨日看不出是今天/明天、跟「上次 X 小时前」风格不一致）。
    # 抽 fmtNext(d) 加今天/明天前缀 + 去秒数；nextRunText 走 fmtNext。
    ("下次时间 今天/明天 前缀", r"sameYMD\(d, now\) \? '今天' :\s*sameYMD\(d, tomorrow\) \? '明天'"),
    ("下次时间 fmtNext 函数", r"function fmtNext\(d\) \{"),
    ("下次时间 去秒数（HH:MM，不是 HH:MM:SS）",
     r"return prefix \+ ' ' \+ pad\(d\.getHours\(\)\) \+ ':' \+ pad\(d\.getMinutes\(\)\)"),
    ("下次时间 nextRunText 走 fmtNext", r"  return fmtNext\(d\);"),

    # 1.0.28：cron 表达式翻人话（`0 8 * * *` → 「每天 08:00」），
    # 详情页「定时规则」下面挂一行灰色小字。翻不出来时返回 null（不显示）。
    ("定时规则 人话描述 函数", r"function cronHumanize\(sch\) \{"),
    ("定时规则 人话描述 stepOf helper", r"function stepOf\(set, n\) \{"),
    ("定时规则 详情页挂人话", r"var human = cronHumanize\(parseCron\(t\.schedule\)\);"),
    ("定时规则 翻不出来不挂（if human）",
     r"if \(human\) h \+= '<div class=\"f11 t3\" style=\"padding:0 14px 8px\">' \+ esc\(human\) \+ '</div>';"),

    # 1.0.29：变量页批量复制（换 cookie 时一次抠多个值，不用逐个点「复制」）。
    # 单选复制裸值、多选复制「名=值」换行；复制完不退出编辑、不刷新列表。
    ("变量批量 复制分支", r"else if \(act === 'copy'\) \{"),
    ("变量批量 单选裸值 / 多选名=值", r"var text = picked\.length === 1"),
    ("变量批量 名=值 拼法（带空值兜底）", r"v\.name \+ '=' \+ \(v\.value \|\| ''\)"),
    ("变量批量 复制完不退出编辑（提前 return）", r"      toast\('已复制 ' \+ picked\.length \+ ' 个变量'"),
    ("变量批量 栏里的复制值按钮", r'data-ebatch="copy"'),

    # 1.0.30：变量页按**第一个标签**分组 + 每组可折叠。
    # 几十上百个 cookie 混在一个长列表里，找某一个得一路滑；分组后一眼分开。
    ("变量分组 哨兵键（不与真标签撞）", r"var ENV_NO_TAG = '\\u0000none';"),
    ("变量分组 取第一个标签", r"var key = ls\.length \? ls\[0\] : ENV_NO_TAG;"),
    ("变量分组 未分类排最后", r"groups\.push\(\{ key: ENV_NO_TAG, name: '未分类'"),
    ("变量分组 渲染走 envGrouped", r"box\.innerHTML = envGrouped\(\)\.map\(envGroupHtml\)\.join\(''\);"),
    ("变量分组 折叠按钮钩子", r'data-envcoll="'),
    ("变量分组 折叠是 toggle", r"delete S\.envs\.collapsed\[gk\]"),
    ("变量分组 委托里有折叠", r"\[data-envcoll\]"),

    # 1.0.31：依赖卡片可折叠（默认只显示名称 + 状态，点一下展开三个按钮）
    #        + 依赖页批量操作（重装 / 删除 / 强制删除，按状态过滤后整批发）。
    ("依赖折叠 默认收起（编辑模式下不展开）", r"var open = !editing && !!d\.open\[x\.id\];"),
    ("依赖折叠 箭头跟着状态", r"\(open \? '▾' : '▸'\)"),
    ("依赖折叠 toggle", r"if \(S\.deps\.open\[id\]\) delete S\.deps\.open\[id\];"),
    ("依赖批量 重装按状态过滤", r"return !depWorking\(x\.status\); \}\);"),
    ("依赖批量 删除只发已安装", r"return x\.status === 1; \}\);"),
    ("依赖批量 发的是过滤后那批", r"var send = go\.map\(function \(x\) \{ return Number\(x\.id\); \}\);"),
    ("依赖批量 强制删除 danger", r'class="btn danger" data-dbatch="force"'),
    ("依赖批量 委托里整行与批量按钮", r"\[data-deps\],\[data-dbatch\],"),

    # 1.0.32：变量搜索结果「上 / 下一个」跳转（搜「JD」出 20 条也得能逐个跳过去看）。
    #        三个交付点：① 跳转条按钮 + 计数；② 圈出当前那条用黄边（不用背景），
    #        不跟编辑模式的选中态 .item.on 撞脸；③ 回车 = 下一个匹配、Shift+回车 = 上一个。
    ("搜索跳转 委托钩子", r"\[data-envjump\]"),
    ("搜索跳转 onClick 传 ±1", r"envJump\(Number\(el\.dataset\.envjump\)\)"),
    ("搜索跳转 渲染里给当前那条加类", r"\(cur \? ' hitcur' : ''\)"),
    ("搜索跳转 当前套黄边 outline", r"\.item\.hitcur\{outline:2px solid #ffd479"),
    ("搜索跳转 顺序用分组后的渲染顺序", r"envGrouped\(\)\.forEach\(function \(g\) \{\s*g\.items\.forEach\(function \(v\) \{ out\.push\(\{ id: v\.id, key: g\.key \}\)"),
    ("搜索跳转 列表换过下标失效", r"if \(e\.hitId == null \|\| !cur \|\| cur\.id !== e\.hitId\) \{ e\.hit = -1; e\.hitId = null; \}"),
    ("搜索跳转 跳到折叠组里会展开", r"if \(t\.key && e\.collapsed\[t\.key\]\) delete e\.collapsed\[t\.key\]"),
    ("搜索跳转 跳完重画", r"renderEnvs\(\);\s*scrollToEnvHit\(\)"),
    ("搜索跳转 滚到中间", r"#envList \.item\.hitcur"),
    ("搜索跳转 回车跳下一个", r"#envSearch.*addEventListener\('keydown'"),
    ("搜索跳转 Shift+回车是上一个", r"envJump\(ev\.shiftKey \? -1 : 1\)"),
    ("搜索跳转 换关键字时清位置", r"S\.envs\.hit = -1; S\.envs\.hitId = null;\s*loadEnvs\(\)"),

    # 1.0.33：同一套「搜索跳转」铺到任务页 / 脚本树（三处各写一份，不硬抽公共函数
    #         —— 变量页有分组、任务页没有、脚本页是树形，硬抽三处都变复杂），
    #         变量页另加「按状态筛选」+「一键全部展开 / 折叠」。
    ("任务跳转 委托钩子", r"\[data-cronjump\],"),
    ("任务跳转 分支传 ±1", r"if \(el\.dataset\.cronjump\) return cronJump\(Number\(el\.dataset\.cronjump\)\);"),
    ("任务跳转 顺序取筛完的", r"return cronFiltered\(\)\.map\(function \(t\) \{ return t\.id; \}\);"),
    ("任务跳转 列表换过后下标失效", r"if \(c\.hitId == null \|\| cur !== c\.hitId\) \{ c\.hit = -1; c\.hitId = null; \}"),
    ("任务跳转 跳转条 HTML", r'id="cronJump"'),
    ("任务跳转 渲染给当前那条加类", r"\(on \? ' on' : ''\) \+ \(cur \? ' hitcur' : ''\)"),
    ("任务跳转 回车要等接口回来再跳", r"loadCrons\(true\)\.then\(function \(\) \{ cronJump\(ev\.shiftKey \? -1 : 1\); \}\)"),
    ("脚本跳转 委托钩子", r"\[data-scrjump\],"),
    ("脚本跳转 分支传 ±1", r"if \(el\.dataset\.scrjump\) return scrJump\(Number\(el\.dataset\.scrjump\)\);"),
    ("脚本跳转 列表渲染与跳转条同源", r"var rows = scrRows\(\);"),
    ("脚本跳转 身份用完整相对路径", r"return scrRows\(\)\.map\(function \(r\) \{ return r\.key; \}\);"),
    ("脚本跳转 跳转条 HTML", r'id="scrJump"'),
    ("脚本跳转 搜索态写父目录", r"var hitDir = q && r\.dir;"),
    ("变量状态筛选 委托钩子", r"\[data-envstat\],"),
    ("变量状态筛选 分支", r"if \(el\.dataset\.envstat != null\) \{"),
    ("变量状态筛选 已启用 / 已禁用", r"if \(e\.stat === 'on'\) list = list\.filter\(function \(v\) \{ return v\.status !== 1; \}\);"),
    ("变量状态筛选 再点同一档取消", r"S\.envs\.stat = \(st === '' \|\| S\.envs\.stat === st\) \? '' : st;"),
    ("变量全折叠 委托钩子", r"#btnEnvFold,"),
    ("变量全折叠 分支", r"if \(el\.id === 'btnEnvFold'\) return envFoldAll\(\);"),
    ("变量全折叠 有展开的就全折起来", r"if \(anyOpen\) e\.collapsed\[g\.key\] = true;"),
    ("变量全折叠 文案跟着状态变", r"fb\.textContent = envAnyOpen\(\) \? '全部折叠' : '全部展开';"),

    # 1.0.34：订阅页补上批量操作（跟任务 / 变量 / 依赖三页一套做法），
    #         批量动作改成**先按选中项状态过滤、只发有用的那些**（以前原样全发，
    #         选 10 个里面有 3 个正在跑，点「运行」会再触发一遍），
    #         批量栏右边那句带上细分（其中几个在跑 / 已启用 / 已装）。
    ("订阅批量 委托钩子", r"\[data-sub\],\[data-sbatch\],"),
    ("订阅批量 编辑按钮分支", r"if \(el\.id === 'btnSubEdit'\) return toggleSubEdit\(\);"),
    ("订阅批量 全选分支", r"if \(el\.id === 'btnSubAll'\) return subSelectAll\(subSelCount\(\) !== S\.subs\.list\.length\);"),
    ("订阅批量 动作分支", r"if \(el\.dataset\.sbatch\) return subBatch\(el\.dataset\.sbatch\);"),
    ("订阅批量 点整行勾选", r"if \(S\.subs\.edit\) return toggleSubSel\(Number\(el\.dataset\.sub\)\);"),
    ("订阅批量 卡片挂 data-sub", r'" data-sub="\' \+ x\.id'),
    ("订阅批量 编辑态勾选圈", r"\(editing \? '<span class=\"ckb\">✓</span>' : ''\) \+\s*'<div class=\"nm sp\">' \+ logHi\(x\.name \|\| x\.alias \|\| '未命名订阅', s\.q\)"),
    ("订阅批量 编辑态行内按钮收起", r"\(editing \? '' :\s*'<div class=\"row\" style=\"gap:8px;margin-top:10px\">' \+\s*'<button class=\"btn\" style=\"flex:1;padding:8px\" data-subact="),
    ("订阅批量 退出清勾选", r"if \(!S\.subs\.edit\) S\.subs\.sel = \{\};"),
    ("订阅批量 运行过滤在拉取的", r"go = picked\.filter\(function \(x\) \{ return !subRunning\(x\); \}\);"),
    ("订阅批量 停止只发在拉取的", r"go = picked\.filter\(subRunning\);"),
    ("订阅批量 启用只发已禁用的", r"go = picked\.filter\(function \(x\) \{ return x\.status === 2; \}\);"),
    ("订阅批量 禁用只发没禁用的", r"go = picked\.filter\(function \(x\) \{ return x\.status !== 2; \}\);"),
    ("订阅批量 排队中也算在拉取", r"function subRunning\(x\) \{ return !!x && \(x\.status === 0 \|\| x\.status === 3\); \}"),
    ("订阅批量 批量栏 HTML", r'id="subEditBar"'),
    ("订阅批量 栏内按钮", r'data-sbatch="run"'),
    ("订阅批量 贴底 CSS", r"#cronEditBar,#envEditBar,#depEditBar,#subEditBar\{position:fixed"),
    ("订阅批量 列表底部留白", r"#main\.cronedit,#main\.envsedit,#main\.depsedit,#main\.subsedit\{padding-bottom"),
    ("批量按状态过滤 任务运行跳过在跑的", r"go = picked\.filter\(function \(t\) \{ return !isBusy\(t\); \}\);"),
    ("批量按状态过滤 任务启用只发禁用的", r"go = picked\.filter\(function \(t\) \{ return cronBucket\(t\) === 'disabled'; \}\);"),
    ("批量按状态过滤 变量启用只发禁用的", r"go = picked\.filter\(function \(v\) \{ return v\.status === 1; \}\);"),
    ("批量按状态过滤 发的是滤过的", r"var send = go\.map\(function \(x\) \{ return Number\(x\.id\); \}\);"),
    ("批量按状态过滤 空则拦住", r"if \(!go\.length\) \{ toast\(why, true\); return; \}"),
    ("批量细分提示 公共件", r"function selHint\(n, extra, extraLabel\) \{"),
    ("批量细分提示 任务栏", r"\(busy \? selHint\(n, busy, '运行中'\) : selHint\(n, offN, '已禁用'\)\)"),
    ("批量细分提示 变量栏", r"selHint\(n, onN, '已启用'\)"),
    ("批量细分提示 依赖栏", r"selHint\(n, instN, '已装'\)"),
    ("批量细分提示 订阅栏", r"running \? selHint\(n, running, '拉取中'\) : selHint\(n, disabled, '已禁用'\)"),
    ("批量完成提示 带跳过数", r"\(skipped \? '（跳过 ' \+ skipped \+ ' 个）' : ''\)"),
    ("任务页切走清留白", r"var mnC = \$\('#main'\);"),
    ("任务页切走还原文案", r"var bC = \$\('#btnCronEdit'\);"),

    # 1.0.35：三件事。
    #   ① 「我的」页顶部加「最近打开」—— 底栏只有四个 tab（任务 / 变量 / 脚本 /
    #      我的），订阅 / 依赖 / 配置 / 日志都得从「我的」进去，常用的那两三个
    #      每次要在 12 张卡片里翻一遍。记下最近点过的放网格上面，第二次直接点。
    #   ② 订阅 / 依赖两页补搜索命中高亮 —— 任务 / 变量 / 脚本三页一直有，
    #      这两页搜完只是「列表变短了」，命中的是哪几个字还得自己一行行找。
    #   ③ 配置文件页补搜索。列表是**整份**拉回来的，所以纯本地过滤，不重打接口。
    ("最近打开 存储键", r"recent: 'ql\.recent'"),
    ("最近打开 读函数", r"function recentTabs\(\) \{"),
    ("最近打开 只留能当 tab 的", r"if \(!FEATURES\.some\(function \(f\) \{ return f\.tab === t; \}\)\) return false;"),
    ("最近打开 去重", r"if \(typeof t !== 'string' \|\| seen\[t\]\) return false;"),
    ("最近打开 读时截断", r"\}\)\.slice\(0, 3\);"),
    ("最近打开 写函数", r"function pushRecent\(tab\) \{"),
    ("最近打开 写时先去掉旧的", r"var list = recentTabs\(\)\.filter\(function \(t\) \{ return t !== tab; \}\);"),
    ("最近打开 写时截断", r"sset\(K\.recent, JSON\.stringify\(list\.slice\(0, 3\)\)\);"),
    ("最近打开 有记录才画", r"var rec = recentTabs\(\);"),
    ("最近打开 区标题", r"h \+= '<div class=\"sec\">最近打开</div>';"),
    ("最近打开 点卡片记一笔", r"pushRecent\(el\.dataset\.goto\);"),
    ("搜索高亮 订阅名", r"'<div class=\"nm sp\">' \+ logHi\(x\.name \|\| x\.alias \|\| '未命名订阅', s\.q\) \+ '</div>'"),
    ("搜索高亮 订阅链接", r"logHi\(x\.url \|\| '', s\.q\)"),
    ("搜索高亮 订阅类型标签", r"logHi\(subTypeName\(x\.type\), s\.q\)"),
    ("搜索高亮 依赖名", r"'<div class=\"nm sp mono\" style=\"font-size:calc\(14px\*var\(--fs\)\)\">' \+ logHi\(x\.name, d\.q\) \+ '</div>'"),
    ("搜索高亮 依赖备注", r"'<div class=\"f11 t3\" style=\"margin-top:5px\">' \+ logHi\(x\.remark, d\.q\) \+ '</div>'"),
    ("配置搜索 搜索框", r'id="cfgSearch"'),
    ("配置搜索 纯本地过滤", r"var list = q \? c\.list\.filter\(function \(f\) \{"),
    ("配置搜索 命中计数", r"\(list\.length \+ ' / ' \+ c\.list\.length \+ ' 个文件'\)"),
    ("配置搜索 空态带关键字", r"'没有匹配「' \+ esc\(c\.q\) \+ '」的配置文件'"),
    ("配置搜索 文件名高亮", r"logHi\(f\.title, c\.q\)"),
    ("配置搜索 输入框绑定", r"\$\('#cfgSearch'\)\.addEventListener\('input', function \(e\) \{"),
    ("配置搜索 只重画不打接口", r"S\.configs\.q = e\.target\.value\.trim\(\); renderConfigs\(\);"),
    ("配置搜索 状态带 q", r"configs: \{ list: \[\], q: '', loading: false \}"),

    # 1.0.36：登录日志页补「只看失败」+ 搜索。
    #   面板的登录日志最多 100 条，翻起来清一色「成功」，真正要看的那几条失败
    #   混在中间；自己搭的面板挂在公网上，失败登录值得一眼看见。
    #   按钮上带失败条数（不点开就知道今天有没有人试过），筛完副标题说
    #   「命中 / 总数」，命中处上黄底。列表整份在手上，所以纯本地过滤、不重打接口。
    ("登录日志 搜索框", r'id="loginSearch"'),
    ("登录日志 只看失败按钮", r'id="btnLoginFail"'),
    ("登录日志 筛选状态", r"loginlog: \{ list: \[\], loading: false, err: '', onlyFail: false, q: '' \},"),
    ("登录日志 失败判据函数", r"function loginlogFail\(x\) \{"),
    ("登录日志 失败判据是 1", r"return Number\(x && x\.status\) === 1;"),
    ("登录日志 筛选函数", r"function loginlogFiltered\(\) \{"),
    ("登录日志 只看失败要真滤", r"if \(l\.onlyFail && !loginlogFail\(x\)\) return false;"),
    ("登录日志 搜索覆盖三个字段", r"return \[x\.ip, x\.address, x\.platform\]\.some\(function \(v\) \{"),
    ("登录日志 搜索忽略大小写", r"return String\(v == null \? '' : v\)\.toLowerCase\(\)\.indexOf\(q\) >= 0;"),
    ("登录日志 关键字去空格", r"var q = String\(l\.q \|\| ''\)\.trim\(\)\.toLowerCase\(\);"),
    ("登录日志 列表按筛完的画", r"box\.innerHTML = rows\.map\(function \(x, i\) \{"),
    ("登录日志 副标题给命中总数", r"\? \(filtered \? \(rows\.length \+ ' / ' \+ l\.list\.length \+ ' 条记录'\)"),
    ("登录日志 按钮带失败条数", r"\(failN \? '（' \+ failN \+ '）' : ''\)"),
    ("登录日志 按钮高亮跟状态", r"fb\.classList\.toggle\('on', !!l\.onlyFail\);"),
    ("登录日志 开关函数", r"function toggleLoginFail\(\) \{"),
    ("登录日志 开关能翻回来", r"S\.loginlog\.onlyFail = !S\.loginlog\.onlyFail;"),
    ("登录日志 空态分开说（两个都没命中）", r"\(l\.onlyFail && q \? '没有匹配「' \+ esc\(q\) \+ '」的失败登录'"),
    ("登录日志 空态分开说（没有失败）", r": \(l\.onlyFail \? '没有失败的登录记录'"),
    ("登录日志 IP 命中上黄底", r"logHi\(x\.ip \|\| '—', q\)"),
    ("登录日志 地址命中上黄底", r"logHi\(x\.address \|\| '—', q\)"),
    ("登录日志 设备命中上黄底", r"logHi\(x\.platform \|\| '—', q\)"),
    ("登录日志 按钮进委托选择器", r"'#btnLoginFail,' \+"),
    ("登录日志 委托分支", r"if \(el\.id === 'btnLoginFail'\) return toggleLoginFail\(\);"),
    ("登录日志 搜索框绑定", r"\$\('#loginSearch'\)\.addEventListener\('input', function \(e\) \{"),
    ("登录日志 搜索本地重画", r"S\.loginlog\.q = e\.target\.value\.trim\(\); renderLoginLog\(\);"),

    # 1.0.37：多实例任务的运行实例列表。
    #   开了「允许同时运行多个实例」的任务，跑起来之后任务列表上只有一个「运行中」；
    #   到底起了几个、哪个卡住了、要停哪一个，面板网页版的任务详情里能看，
    #   手机上之前看不了。入口在任务详情的「其他 → 运行实例」。
    #   状态判据**只看 finished_at**（后端各版本的 status 枚举编号未必一致，
    #   认数值会把「正在跑」的实例说成「已完成」，而这种错在界面上看不出来）。
    ("运行实例 视图", r'<section class="view" id="v-instances">'),
    ("运行实例 标题", r"instances: '运行实例',"),
    ("运行实例 页面状态", r"instances: \{ id: null, name: '', list: \[\], loading: false, err: '', busy: \{\} \},"),
    ("运行实例 在跑判据函数", r"function instRunning\(x\) \{"),
    ("运行实例 判据只看 finished_at", r"return !\(Number\(x && x\.finished_at\) > 0\);"),
    ("运行实例 状态文案函数", r"function instState\(x\) \{"),
    ("运行实例 143 说已停止", r"if \(code === 143\) return \{ t: '已停止', c: 'gray' \};"),
    ("运行实例 出错带上退出码", r"return \{ t: '出错 ' \+ code, c: 'red' \};"),
    ("运行实例 时长函数", r"function instDurSec\(x\) \{"),
    ("运行实例 跑着的按现在算", r"var end = instRunning\(x\) \? Math\.floor\(Date\.now\(\) \/ 1000\)"),
    ("运行实例 在跑计数函数", r"function instRunningCount\(list\) \{"),
    ("运行实例 跳转函数", r"function gotoInstances\(t\) \{"),
    ("运行实例 加载函数", r"async function loadInstances\(id, force\) \{"),
    ("运行实例 列表接口", r"'\/api\/crons\/' \+ encodeURIComponent\(v\.id\) \+ '\/instances'"),
    ("运行实例 停止函数", r"async function stopInstance\(iid\) \{"),
    ("运行实例 停止走 POST", r"encodeURIComponent\(iid\) \+ '\/stop', \{ method: 'POST' \}\)"),
    ("运行实例 停完重拉列表", r"await loadInstances\(v\.id, true\);"),
    ("运行实例 渲染函数", r"function renderInstances\(\) \{"),
    ("运行实例 副标题给总数在跑数", r"v\.list\.length \+ ' 个实例' \+ \(runN \? ' · ' \+ runN \+ ' 个在跑' : ''\)"),
    ("运行实例 停止只给在跑的", r"\(running \? '<div class=\"row\" style=\"margin-top:10px\">' \+"),
    ("运行实例 404 说版本不支持", r"'这个面板版本还不支持运行实例列表'"),
    ("运行实例 详情页入口", r'id="cdInst" data-goinst="'),
    ("运行实例 入口只给多实例", r"if \(t\.allow_multiple_instances === 1\) \{"),
    ("运行实例 详情页那行补在跑数", r"el\.textContent = n \? \(n \+ ' 个在跑'\) : '暂无在跑';"),
    ("运行实例 委托选择器", r"'\[data-goinst\],\[data-inststop\],' \+"),
    ("运行实例 委托分支 跳转", r"if \(el\.dataset\.goinst\) return gotoInstances\(cronById\(el\.dataset\.goinst\)\);"),
    ("运行实例 委托分支 停止", r"if \(el\.dataset\.inststop\) return stopInstance\(Number\(el\.dataset\.inststop\)\);"),
    # 1.0.38：1.0.37 这条选择器是**最后一行**，1.0.38 后面加了 #btnCronLogsReload 那行，
    # 这一行末尾多了 `,' +`（要被下一行接住）。锚点跟着改。
    ("运行实例 刷新按钮进选择器", r"'#btnInstReload,#btnInstRetry,' \+"),
    ("运行实例 refresh 管这一页", r"if \(S\.tab === 'instances'\) return loadInstances\(S\.instances\.id, true\);"),
    ("运行实例 换任务先清旧列表", r"S\.instances\.list = \[\];"),

    # 1.0.39：批量加 / 删标签（任务页 + 变量页）。以前标签只能一条条加，
    #   想把「京东」一类任务全贴上得逐个点详情、编辑、保存。批量标签
    #   走 POST/DELETE /api/{crons,envs}/labels，跟面板 web 端同一条路。
    ("批量标签 splitLabels 顶层函数", r"function splitLabels\(text\) \{"),
    ("批量标签 拆分规则 含#", r"split\(\/\[,，\\s#\]\+\/\)"),
    ("批量标签 去掉空串", r"\.filter\(function \(s\) \{ return s\.length > 0; \}\)"),
    ("批量标签 promptLabels 顶层", r"function promptLabels\(kind, count, act\) \{"),
    ("批量标签 弹层输入框", r'id="plInput"'),
    ("批量标签 确定按钮", r'id="plOk"'),
    ("批量标签 取消按钮", r'id="plCancel"'),
    ("批量标签 提示条目数", r"'给选中的 <b>' \+ count \+ '</b> 个'"),
    ("批量标签 任务页 加标签 按钮", r'data-cbatch="addlabel"'),
    ("批量标签 任务页 删标签 按钮", r'data-cbatch="removelabel"'),
    ("批量标签 变量页 加标签 按钮", r'data-ebatch="addlabel"'),
    ("批量标签 变量页 删标签 按钮", r'data-ebatch="removelabel"'),
    # method 三元表达式 + 端点 + body 都得在源码里。两条分页锚。
    ("批量标签 任务 method 切换", r"var method = act === 'addlabel' \? 'POST' : 'DELETE';"
                                  r"\s*await api\('\/api\/crons\/labels', \{ method: method, body: \{ ids: send, labels: labels \} \}"),
    ("批量标签 变量 method 切换", r"var method = act === 'addlabel' \? 'POST' : 'DELETE';"
                                  r"\s*await api\('\/api\/envs\/labels', \{ method: method, body: \{ ids: send, labels: labels \} \}"),
    # 标签动作不过滤：「如果 addlabel/removelabel 也被过滤」会导致已禁用任务
    # 永远贴不上标签 → 用标签找回已禁用任务这条路断了。
    ("批量标签 任务页 不过滤", r"if \(act === 'addlabel' \|\| act === 'removelabel'\) \{\s*\/\* 走原样的 picked，不按状态过滤 \*\/\s*\} else if \(act === 'run'\)"),
    ("批量标签 变量页 不过滤", r"if \(act === 'addlabel' \|\| act === 'removelabel'\) \{\s*\/\* 走原样的 picked \*\/\s*\} else if \(act === 'enable'\)"),
    # cronBatch / envBatch 调 promptLabels（不弹层也行，但表达式得在）。
    ("批量标签 任务页 调 promptLabels", r"promptLabels\('cron', send\.length, act\)"),
    ("批量标签 变量页 调 promptLabels", r"promptLabels\('env', send\.length, act\)"),

    # 1.0.38：任务的历史日志列表。
    #   「最新日志」只有一条，想看昨天那次跑成什么样得自己在日志目录里翻，
    #   文件名都是 2026-09-18-08-00-03-118.log 这种，找「昨天那次」得逐个认。
    #   数据不用新接口：日志树里这个任务的目录节点就带着 children（含 size / createTime）。
    ("历史日志 视图", r'<section class="view" id="v-cronlogs">'),
    ("历史日志 TITLES", r"cronlogs: '历史日志',"),
    ("历史日志 状态字段", r"cronlogs: \{ id: null, name: '', list: \[\], loading: false,"
                          r" err: '', dirKey: '', dirName: '' \},"),
    ("历史日志 只挑文件", r"return x && x\.type !== 'directory';"),
    ("历史日志 按名字倒序", r"return x < y \? 1 : \(x > y \? -1 : 0\);"),
    ("历史日志 没目录返回空", r"var files = \(\(dir && dir\.children\) \|\| \[\]\)\.filter"),
    ("历史日志 详情页未拉树文案", r"if \(!S\.logs\.tree\.length\) return '查看历史日志';"),
    ("历史日志 详情页无日志文案", r"return n \? \(n \+ ' 个文件'\) : '暂无日志';"),
    # 跨行的锚点得容忍 \r\n：ipa 里的页面是 build.py 用文本模式写的（默认 CRLF），
    # 而 verify 是把字节当 str 解码出来（不做换行归一化），pattern 里写死 \n 就漏了。
    ("历史日志 跳走记来源", r"S\.backTo = from;[\r\n]+  S\.cronlogs\.id = t\.id;"),
    ("历史日志 切到这一页", r"setTab\('cronlogs'\);"),
    ("历史日志 任务不在列表", r"v\.err = '这个任务已经不在当前列表里了';"),
    ("历史日志 刷新清日志树缓存", r"if \(force\) S\.logs\.tree = \[\];"),
    ("历史日志 记住目录 key", r"v\.dirKey = dir \? String\(dir\.key \|\| ''\) : '';"),
    ("历史日志 跳日志目录", r"loadLogs\(logKeyPath\(v\.dirKey\), false\);"),
    ("历史日志 副标题", r"\$\('#sub'\)\.textContent = v\.list\.length \? "
                       r"\(v\.list\.length \+ ' 个日志文件'\) : '';"),
    ("历史日志 显示日志目录名", r"日志目录：' \+ esc\(v\.dirName\)"),
    ("历史日志 浏览目录按钮", r'id="btnCronLogsDir"'),
    ("历史日志 空态", r"这个任务还没有日志"),
    ("历史日志 列表项存树节点 key", r"data-cronlogopen=\"' \+ esc\(f\.key\)"),
    ("历史日志 显示文件大小", r"esc\(fmtSize\(f\.size\)\)"),
    ("历史日志 委托选择器", r"'\[data-goscript\],\[data-gocronlog\],\[data-gocronlogs\],"
                            r"\[data-cronlogopen\],' \+"),
    ("历史日志 委托分支 跳转", r"if \(el\.dataset\.gocronlogs\) return gotoCronLogs"
                               r"\(cronById\(el\.dataset\.gocronlogs\)\);"),
    ("历史日志 委托分支 打开某一份", r"var lnode = findLogNode\(el\.dataset\.cronlogopen\);"),
    # 1.0.40 在它后面又加了 `[data-gobkinst],[data-bkmod],' +` 一行 →
    # 这一行从「最后一行」变成「中间一行」，末尾的 `'` 跟着变 `,' +`。
    ("历史日志 按钮进选择器", r"'#btnCronLogsReload,#btnCronLogsRetry,#btnCronLogsDir,' \+"),
    ("历史日志 refresh 管这一页", r"if \(S\.tab === 'cronlogs'\) return loadCronLogs"
                                  r"\(S\.cronlogs\.id, true\);"),
    ("历史日志 详情页那行 id", r'id="cdLogHisV"'),
    ("历史日志 详情页补文件数", r"if \(vh && S\.detailId === t\.id\) vh\.textContent = logHisHint\(t\);"),

    # 1.0.40：数据备份。「我的」页加一张「数据备份」卡 → v-backup：
    #   ① 立即备份：PUT /api/system/data/export 拿 .tgz，交给 saveBlobToDevice
    #      弹系统分享菜单（飞牛 / 百度 / 微信由用户在分享菜单里选，App 不绑死网盘）；
    #   ② 自动发现青龙里「备份类任务」（名字含 备份 / backup）的最近运行。
    #   定时 + 上传不做在 App 里：iOS 后台会被杀，那一步放青龙侧的脚本 + rclone。
    ("数据备份 视图", r'<section class="view" id="v-backup">'),
    ("数据备份 TITLES", r"backup: '数据备份',"),
    ("数据备份 FEATURES 卡", r"\{ tab: 'backup',"),
    ("数据备份 状态字段", r"backup: \{ mods: \{ base: 1 \}, hisCrons: \[\], loading: false,"
                          r" busy: false \},"),
    ("数据备份 gotoBackup", r"function gotoBackup\(\) \{"),
    ("数据备份 isBackupCron", r"function isBackupCron\(t\) \{"),
    ("数据备份 关键词 中英文", r"return \/备份\|backup\/\.test\(n\);"),
    ("数据备份 backupFindCrons", r"function backupFindCrons\(\) \{"),
    ("数据备份 倒序", r"out\.sort\(function \(a, b\) \{ return b\.when - a\.when; \}\);"),
    ("数据备份 填入列表", r"v\.hisCrons = backupFindCrons\(\);"),
    ("数据备份 组装 type", r"var type = BACKUP_MODULES\.filter\(function \(m\) \{"
                           r" return v\.mods\[m\[0\]\]; \}\)"),
    ("数据备份 导出用 PUT", r"apiBlob\('\/api\/system\/data\/export', \{ type: type \}, 'PUT'\)"),
    ("数据备份 文件名带时间戳", r"var name = 'qinglong-' \+ fmtStamp\(Date\.now\(\)\) \+ '\.tgz';"),
    ("数据备份 fmtStamp", r"function fmtStamp\(ts\) \{"),
    ("数据备份 fmtStamp 补零", r", p = function \(n\) \{ return \(n < 10 \? '0' : ''\) \+ n; \};"),
    # 名字别叫 toggleBackupMod：系统设置页那个已经占了名，同名函数后定义盖先定义。
    ("数据备份 bkToggleMod", r"function bkToggleMod\(btn\) \{"),
    ("数据备份 基础数据不可取消", r"toast\('「基础数据」是必选的，取消不了'\)"),
    ("数据备份 同步按钮 class", r"btn\.classList\.toggle\('on', !!v\.mods\[k\]\);"),
    ("数据备份 模块按钮属性", r"data-bkmod="),
    ("数据备份 模块默认勾上", r"var on = m\[2\] \? 1 : \(v\.mods\[m\[0\]\] \? 1 : 0\);"),
    ("数据备份 打包中禁用", r"\(v\.busy \? 'disabled' : ''\)"),
    ("数据备份 打包中文案", r"\(v\.busy \? '正在打包…' : '立即备份'\)"),
    ("数据备份 任务行可点", r"data-gobkinst=\"' \+ esc\(String\(t\.id\)\)"),
    ("数据备份 尚未运行", r"'尚未运行'"),
    ("数据备份 副标题", r"个备份任务"),
    ("数据备份 空态", r"还没挂自动备份任务"),
    ("数据备份 空态教 rclone", r"rclone"),
    ("数据备份 委托选择器 属性", r"'\[data-gobkinst\],\[data-bkmod\],' \+"),
    ("数据备份 委托选择器 按钮", r"'#btnBkExport,#btnBkImport,#btnBkRetry,'"),
    ("数据备份 委托分支 任务行", r"if \(el\.dataset\.gobkinst\) \{"),
    ("数据备份 委托分支 模块", r"if \(el\.dataset\.bkmod != null\) return bkToggleMod\(el\);"),
    ("数据备份 委托分支 立即备份", r"if \(el\.id === 'btnBkExport'\) return exportBackupNow\(\);"),
    ("数据备份 委托分支 还原", r"if \(el\.id === 'btnBkImport'\) \{ var fi = \$\('#fileBkImport'\);"),
    ("数据备份 文件框", r'id="fileBkImport"'),
    ("数据备份 还原接 importBackup", r"if \(bkImp\) bkImp\.addEventListener\('change'"),
    ("数据备份 refresh 管这一页", r"if \(S\.tab === 'backup'\) return loadBackup\(true\);"),

    # 1.0.41：通知设置。「我的」页加一张「通知设置」卡 → v-notify：
    #   ① 25 个渠道，**照抄面板自己的顺序和叫法**（用户是照面板的名字找的）；
    #   ② 每个渠道一张字段表，保存 = PUT /api/user/notification。
    #   面板**先试发一条，发得出去才存** —— 所以「保存」本身就是测试，
    #   报「通知发送失败」时配置没存上，不能提示「已保存」。
    #   两类「写错了不报错」的坑（下面各锚了几条）：
    #     · 字段名拼错一个字母 → 保存成功、但那栏没存上，界面上看不出来；
    #     · 只提交当前渠道的字段 → 后端整份替换（直接写 info），别的渠道被悄悄清空。
    ("通知设置 视图", r'<section class="view" id="v-notify">'),
    ("通知设置 TITLES", r"notify: '通知设置'"),
    ("通知设置 FEATURES 卡", r"\{ tab: 'notify',"),
    ("通知设置 状态字段", r"notify: \{ cfg: null, pick: 'closed', loaded: false, loading: false,"),
    ("通知设置 渠道表 头两档", r"\['gotify', 'Gotify'\], \['ntfy', 'Ntfy'\]"),
    ("通知设置 渠道表 已关闭", r"\['closed', '已关闭'\]"),
    ("通知设置 字段表 Server酱", r"\['serverChanKey',"),
    ("通知设置 字段表 大写 P", r"\['pushPlusToken',"),
    ("通知设置 字段表 小写 p", r"\['pushplusChannel',"),
    ("通知设置 别名表", r"var NOTIFY_ALIAS = \{ pushPlusTemplate: 'pushplusTemplate' \};"),
    ("通知设置 webhook 方法下拉", r"\['webhookMethod', '请求方法', 1, \[\['GET', 'GET'\]"),
    ("通知设置 notifyModeLabel", r"function notifyModeLabel\(v\) \{"),
    ("通知设置 notifyModeOptions", r"function notifyModeOptions\(cur\) \{"),
    ("通知设置 不认识的渠道补进下拉", r"list\.unshift\(\[cur, cur \+ '（App 不认识，保持原样）'\]\)"),
    ("通知设置 notifyFields", r"function notifyFields\(mode\) \{ return NOTIFY_FIELDS\[mode\] \|\| \[\]; \}"),
    ("通知设置 loadNotify", r"async function loadNotify\(force\) \{"),
    ("通知设置 读配置接口", r"api\('\/api\/user\/notification'\)"),
    ("通知设置 读失败当空配置", r"v\.cfg = \{\};"),
    ("通知设置 type 空还原成已关闭", r"v\.pick = \(v\.cfg\.type \? String\(v\.cfg\.type\) : 'closed'\);"),
    # 1.0.43：依赖设置页。三个坑跟之前的设置类页一样：异步接口返回空 body
    # （node-mirror / linux-mirror），要走 raw 分支；字段名带 Mirror 后缀；
    # 代理字段是 dependenceProxy（不是 dependenceProxyMirror）。
    ("依赖设置 视图", r'<section class="view" id="v-mirror">'),
    ("依赖设置 TITLES", r"mirror: '依赖设置'"),
    ("依赖设置 FEATURES 卡", r"\{ tab: 'mirror',"),
    ("依赖设置 状态字段", r"mirror: \{ cfg: null, loading: false, err: '', busy: '', task: null, custom: '' \},"),
    ("依赖设置 三源表", r"var MIRROR_ITEMS = \["),
    ("依赖设置 代理独立项", r"var MIRROR_PROXY = \{ key: 'proxy', title: '依赖代理',"),
    ("依赖设置 预设 node", r"\['淘宝', 'https://registry\.npmmirror\.com'\]"),
    ("依赖设置 预设 linux", r"\['阿里云', 'https://mirrors\.aliyun\.com'\]"),
    ("依赖设置 异步项 raw 分支", r"\{ method: 'PUT', body: body, raw: !!it\.async \}"),
    ("依赖设置 异步后留 task", r"m\.task = \{ title: it\.title, pid: \(r && r\.pid\) \|\| '' \};"),
    ("依赖设置 raw 分支取 QL-Task-Pid", r"res\.headers\.get\('QL-Task-Pid'\)"),
    ("依赖设置 空串留空", r"if \(mirrorCur\(key\) === val\) \{ toast\('已经在用这个了'\); return; \}"),
    ("通知设置 renderNotify", r"function renderNotify\(\) \{"),
    ("通知设置 渠道下拉撑满整行", r"'<select id=\"ntMode\" style=\"width:100%\"'"),
    ("通知设置 字段框带 data-ntf", r"data-ntf="),
    ("通知设置 必填下拉默认第一档", r"if \(!sel && f\[2\] && items && items\.length\) sel = items\[0\]\[0\];"),
    ("通知设置 字段说明在输入框下面", r"return f\[1\] \? \('· <b>' \+ esc\(f\[0\]\)"),
    ("通知设置 关闭说明", r"面板就不再发通知"),
    ("通知设置 保存按钮", r'id="btnNtSave"'),
    ("通知设置 重试按钮", r'id="btnNtRetry"'),
    ("通知设置 保存中禁用", r"'style=\"width:100%;padding:11px 4px\"' \+ \(v\.saving \? ' disabled' : ''\)"),
    ("通知设置 保存中文案", r"\(v\.saving \? '正在测试…'"),
    ("通知设置 saveNotify", r"async function saveNotify\(\) \{"),
    ("通知设置 保存用 PUT", r"api\('\/api\/user\/notification', \{ method: 'PUT', body: body \}\)"),
    ("通知设置 整份带上", r"Object\.keys\(v\.cfg\)\.forEach\(function \(k\) \{ body\[k\] = v\.cfg\[k\]; \}\);"),
    ("通知设置 已关闭提交空 type", r"body\.type = \(mode === 'closed'\) \? '' : mode;"),
    ("通知设置 别名写进 body", r"if \(alias\) body\[alias\] = el\.value;"),
    ("通知设置 失败不报已保存", r"toast\(e\.message, true\);"),
    ("通知设置 refresh 管这一页", r"if \(S\.tab === 'notify'\) return loadNotify\(true\);"),
    # 1.0.42 在这一行后面又接了 `'[data-vact],#btnViewAdmin,...'` 一行 →
    # 这一行从「最后一行」变成「中间一行」，末尾的 `'` 跟着变 `,' +`。
    ("通知设置 委托选择器 按钮", r"'#btnNtSave,#btnNtRetry,' \+"),
    ("通知设置 委托分支 保存", r"if \(el\.id === 'btnNtSave'\) return saveNotify\(\);"),
    ("通知设置 委托分支 重试", r"if \(el\.id === 'btnNtRetry'\) return loadNotify\(true\);"),
    ("通知设置 下拉 change 委托", r"if \(t && t\.id === 'ntMode'\) \{"),

    # 1.0.42：视图管理（本轮主体）。面板「定时任务 → 视图」那套在手机上做**降级版**：
    #   改名 / 上移下移 / 停用启用 / 删除 全都有；新建只做「名称 + 一条文本条件」
    #   （面板那套多条件 + 多排序的表单在窄屏上太局促）。入口是任务页视图 tab 栏最右的「管理」。
    #   下面 ①②③ 各锚住了「写错了不报错」的那三处，是本功能的成败点：
    #     ① 筛选条件的键叫 **operation**，写成 operator 条件会静默失效（面板读的是 operation）；
    #     ② move 收的是**全量数组里的下标**（含停用项），拿 tab 栏那份算会错一格；
    #     ③ 改名的 body **绝不能带 position** —— 后端是「原记录 + 新记录」合并，
    #        带回去就把视图挪到别处了（改个名能把排序搞乱，界面上完全看不出）。
    ("视图管理 视图", r'<section class="view" id="v-views">'),
    ("视图管理 TITLES", r"views: '视图管理',"),
    ("视图管理 状态字段", r"viewAdmin: \{ loading: false, err: '', form: null, busy: '' \},"),
    ("视图管理 全量字段", r"views: \[\], viewsAll: \[\], view: null, viewsFailed: false \},"),
    ("视图管理 全量那份照抄接口", r"c\.viewsAll = Array\.isArray\(r\.data\) \? r\.data : \[\];"),
    ("视图管理 tab 栏那份只留启用", r"c\.views = c\.viewsAll\.filter\(function \(v\) \{ return !v\.isDisabled; \}\);"),
    ("视图管理 property 六档", r"\['command', '命令'\], \['name', '名称'\], \['schedule', '定时规则'\],"),
    ("视图管理 operation 四档", r"var VIEW_OPS = \[\['Reg', '包含'\], \['NotReg', '不包含'\], \['In', '属于'\], \['Nin', '不属于'\]\];"),
    ("视图管理 状态四档", r"var VIEW_STATUS = \[\[0, '运行中'\], \[1, '空闲中'\], \[2, '已禁用'\], \[3, '排队中'\]\];"),
    ("视图管理 新建只给四字段", r"var VIEW_NEW_PROPS = \['command', 'name', 'schedule', 'labels'\];"),
    ("视图管理 新建只给两操作符", r"var VIEW_NEW_OPS = \['Reg', 'NotReg'\];"),
    ("视图管理 viewPropLabel", r"function viewPropLabel\(p\) \{"),
    ("视图管理 viewOpLabel", r"function viewOpLabel\(o\) \{"),
    ("视图管理 viewValText", r"function viewValText\(v, val\) \{"),
    ("视图管理 viewCondText", r"function viewCondText\(v\) \{"),
    ("视图管理 没有条件时说明是全部", r"return '没有筛选条件（显示全部任务）';"),
    ("视图管理 空壳条件不拼半截话", r"if \(f\.value == null \|\| f\.value === ''\) return viewPropLabel\(f\.property\)"),
    ("视图管理 gotoViewAdmin", r"function gotoViewAdmin\(\) \{"),
    ("视图管理 loadViewAdmin", r"async function loadViewAdmin\(\) \{"),
    ("视图管理 借 loadViews 拉数据", r"\r?\n    await loadViews\(\);"),
    ("视图管理 老面板没接口要出话", r"if \(S\.crons\.viewsFailed\) v\.err = '这个面板没有「定时视图」接口（面板版本较老）';"),
    ("视图管理 renderViewAdmin", r"function renderViewAdmin\(\) \{"),
    ("视图管理 空态", r'<span class="ei">◫</span>还没有视图'),
    ("视图管理 未命名兜底", r"esc\(x\.name \|\| '未命名视图'\)"),
    ("视图管理 已停用标签", r"\(off \? '<span class=\"tag\">已停用</span>' : ''\)"),
    ("视图管理 行按钮带 data-vact", r"data-vact=\"up\" data-id=\"' \+ esc\(x\.id\)"),
    ("视图管理 首条禁用上移", r"\(i === 0 \|\| busy \? ' disabled' : ''\)"),
    ("视图管理 末条禁用下移", r"\(i === list\.length - 1 \|\| busy \? ' disabled' : ''\)"),
    ("视图管理 停用项按钮显示启用", r"\(off \? '启用' : '停用'\)"),
    ("视图管理 viewFormOpen", r"function viewFormOpen\(\) \{"),
    ("视图管理 新建草稿默认值", r"v\.form = \{ name: '', prop: 'name', op: 'Reg', val: '' \};"),
    ("视图管理 viewFormClose", r"function viewFormClose\(\) \{"),
    ("视图管理 vaFormDraft", r"function vaFormDraft\(\) \{"),
    ("视图管理 viewFormHtml", r"function viewFormHtml\(\) \{"),
    ("视图管理 表单名称框", r'id="vaName"'),
    ("视图管理 表单条件框", r'id="vaVal"'),
    ("视图管理 表单说明只支持一条", r"'这里新建只支持<b>一条文本条件</b>。"),
    ("视图管理 表单创建取消按钮", r'id="btnVaCreate"'),
    ("视图管理 表单开着时新建禁用", r"\(v\.form \? ' disabled' : ''\)"),
    ("视图管理 viewCreate", r"async function viewCreate\(\) \{"),
    ("视图管理 名称空要拦", r"if \(!name\) \{ toast\('请填视图名称', true\); return; \}"),
    ("视图管理 内容空要拦", r"if \(!val\) \{ toast\('请填要匹配的内容', true\); return; \}"),
    # ① 键名是 operation
    ("视图管理 新建条件键名 operation", r"filters: \[\{ property: d\.prop, operation: d\.op, value: val \}\],"),
    ("视图管理 新建打 POST", r"await api\('\/api\/crons\/views', \{ method: 'POST', body: \{"),
    ("视图管理 viewMove", r"async function viewMove\(id, dir\) \{"),
    # ② 下标按全量数组算
    ("视图管理 排序用全量下标", r"var all = S\.crons\.viewsAll;"),
    ("视图管理 上移 -1 下移 +1", r"var to = dir === 'up' \? from - 1 : from \+ 1;"),
    ("视图管理 越界不发请求", r"if \(to < 0 \|\| to >= all\.length\) return;"),
    ("视图管理 move 接口", r"await api\('\/api\/crons\/views\/move', \{ method: 'PUT', body: \{"),
    ("视图管理 move 带全量下标", r"id: Number\(id\), fromIndex: from, toIndex: to"),
    ("视图管理 viewToggle", r"async function viewToggle\(x\) \{"),
    ("视图管理 停用启用两条路径", r"await api\('\/api\/crons\/views\/' \+ \(off \? 'enable' : 'disable'\),"),
    ("视图管理 启停 body 是数组", r"\{ method: 'PUT', body: \[Number\(x\.id\)\] \}\);"),
    ("视图管理 viewRenameBody", r"function viewRenameBody\(x, name\) \{"),
    # ③ 改名不带 position
    ("视图管理 改名 body 无 position", r"id: Number\(x\.id\), name: name,\s+filters: x\.filters \|\| \[\], sorts: x\.sorts \|\| null,"),
    ("视图管理 viewRename", r"async function viewRename\(x\) \{"),
    ("视图管理 改名走 promptText", r"var name = await promptText\('重命名视图', '视图名称', x\.name \|\| ''\);"),
    ("视图管理 改名打 PUT", r"await api\('\/api\/crons\/views', \{ method: 'PUT', body: viewRenameBody\(x, name\) \}\);"),
    ("视图管理 viewDelete", r"async function viewDelete\(x\) \{"),
    ("视图管理 删除文案说清只删视图", r"只删这个视图（一组筛选条件），不会删掉任何任务。"),
    ("视图管理 删除打 DELETE", r"await api\('\/api\/crons\/views', \{ method: 'DELETE', body: \[Number\(x\.id\)\] \}\);"),
    ("视图管理 promptText", r"function promptText\(title, label, value\) \{"),
    ("视图管理 管理入口按钮", r"<button class=\"vtab vtabmgr\" id=\"btnViewAdmin\">管理</button>"),
    ("视图管理 管理按钮靠右", r"\.vtabmgr\{margin-left:auto;"),
    ("视图管理 只有拉失败才藏栏", r"if \(c\.viewsFailed\) \{\s+box\.classList\.add\('hidden'\);\s+box\.innerHTML = '';"),
    ("视图管理 refresh 管这一页", r"if \(S\.tab === 'views'\) return loadViewAdmin\(\);"),
    ("视图管理 返回回任务页", r"if \(S\.tab === 'views'\) \{ setTab\('crons'\); return true; \}"),
    ("视图管理 委托选择器 属性", r"'\[data-vact\],#btnViewAdmin,#btnVaNew,#btnVaCreate,#btnVaCancel,#btnVaRetry,?'"),
    ("视图管理 委托分支 进管理", r"if \(el\.id === 'btnViewAdmin'\) return gotoViewAdmin\(\);"),
    ("视图管理 委托分支 新建", r"if \(el\.id === 'btnVaNew'\) return viewFormOpen\(\);"),
    ("视图管理 委托分支 创建", r"if \(el\.id === 'btnVaCreate'\) return viewCreate\(\);"),
    ("视图管理 委托分支 上移", r"if \(el\.dataset\.vact === 'up'\) return viewMove\(vx\.id, 'up'\);"),
    ("视图管理 委托分支 删除", r"if \(el\.dataset\.vact === 'del'\) return viewDelete\(vx\);"),
    ("视图管理 找不到就提示", r"if \(!vx\) \{ toast\('这个视图已经不在列表里了', true\); return; \}"),

    # 1.0.42 小改进之一：一级页之间的滚动位置记忆。
    # 以前每次切 tab 都 scrollTop = 0，任务列表滚到很下面、切去变量页再切回来就得重翻。
    # 二级页（实例 / 历史日志 / 视图管理）**故意不记** —— 它们每次从不同上下文进，
    # 恢复上次的位置反而会落到莫名其妙的地方。
    ("滚动记忆 SCROLLS", r"var SCROLLS = \{\};"),
    ("滚动记忆 补试时间点", r"var SCROLL_RETRY = \[50, 150, 350\];"),
    ("滚动记忆 saveScroll", r"function saveScroll\(\) \{"),
    ("滚动记忆 restoreScroll", r"function restoreScroll\(tab\) \{"),
    ("滚动记忆 setTab 里先存旧页", r"saveScroll\(\);\s+S\.tab = tab;"),
    ("滚动记忆 切完页再恢复", r"restoreScroll\(tab\);\s+syncBack\(\);"),
    ("滚动记忆 内容渲染完补恢复", r"if \(S\.tab === tab\) m\.scrollTop = want;"),

    # 1.0.42 小改进之二：退出登录时顺手把面板那边的 session 作废。
    # ⚠️ 必须在清 S.token **之前**发 —— api() 的 Authorization 头读的就是它，
    # 清掉之后发出去就是匿名请求，面板不认（等于白发）。失败也不影响退出流程。
    ("真登出 发 logout", r"try \{ api\('\/api\/user\/logout', \{ method: 'POST' \}\)\.catch\(function \(\) \{\}\); \} catch \(e\) \{\}"),
    ("真登出 在清 token 之前", r"catch \(e\) \{\}\s+S\.token = '';"),
]

# 1.0.15 从系统设置弹层里撤掉的东西：这四个入口点了没反应（青龙没这些页面 /
# 单用户面板没有会话管理），撤了就不能再冒出来。
# 这几个是弹层里**写死**的，产物里有字面量，可以放心锚。
FORBIDDEN = [
    ("弹层 无 应用设置 入口", r'data-goto="apps"'),
    ("弹层 无 其他设置 入口", r'data-goto="sysconf"'),
    ("弹层 无 登录日志 入口", r'data-goto="loginlog"'),
    ("弹层 无 面板日志 入口", r'data-goto="syslog"'),
    ("弹层 无 面板设置 分区", r'<div class="secttl">面板设置</div>'),
]

PLIST_KEYS = [
    "CFBundleIdentifier",
    "CFBundleShortVersionString",
    "CFBundleVersion",
    "CFBundleDisplayName",
    "UIDeviceFamily",
    "MinimumOSVersion",
    "NSLocalNetworkUsageDescription",
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ipa")
    ap.add_argument("--pwa", default="../qinglong-pwa",
                    help="qinglong-pwa 目录（用来跟本地构建产物对账）")
    args = ap.parse_args()

    if not os.path.exists(args.ipa):
        sys.exit("找不到 %s" % args.ipa)

    bad = []

    def chk(label, cond, extra=""):
        print("    %-28s %s%s" % (label, "OK" if cond else "缺失 !!", extra))
        if not cond:
            bad.append(label)

    z = zipfile.ZipFile(args.ipa)
    names = z.namelist()

    print("=" * 64)
    print("ipa: %s  (%d 字节)" % (args.ipa, os.path.getsize(args.ipa)))
    print("sha256: %s" % hashlib.sha256(open(args.ipa, "rb").read()).hexdigest())
    print("=" * 64)

    # ---------- 1. 结构 ----------
    print("\n[1] 包内结构（条目 %d 个）" % len(names))
    for n in ["index.html", "QLBootstrap.js", "Info.plist", "QingLongClient",
              "_CodeSignature/CodeResources"]:
        chk(n, (APP + n) in names)

    # ---------- 2. 页面 ----------
    print("\n[2] 内置页面")
    html = z.read(APP + "index.html")
    src = html.decode("utf-8")
    print("    index.html 字节: %d" % len(html))

    local_path = os.path.join(args.pwa, "index.html")
    if os.path.exists(local_path):
        local = open(local_path, "rb").read()
        print("    本地产物字节: %d" % len(local))
        chk("与本地产物逐字节一致", html == local)
    else:
        print("    （没找到 %s，跳过与本地产物对账）" % local_path)

    m = re.search(r"var APP_VER = '([^']*)'", src)
    ver = m.group(1) if m else None
    print("    APP_VER: %s" % (ver or "没找到 !!"))
    if not ver:
        bad.append("APP_VER")
    # 文件名里的版本要跟页面里的一致 —— 下下来分不清新旧就是这个错了
    fn = os.path.basename(args.ipa)
    if ver:
        chk("文件名版本与页面一致", ("-%s-" % ver) in fn, "（文件名 %s）" % fn)

    m = re.search(r"var FALLBACK_SERVER = '([^']*)'", src)
    chk("不预填面板地址", m is not None and m.group(1) == "",
        "（FALLBACK_SERVER=%r）" % (m.group(1) if m else None))

    # ---------- 3. 功能锚点 ----------
    print("\n[3] 功能代码是否真在包里")
    for label, pat in FEATURES:
        chk(label, re.search(pat, src) is not None)

    # ---------- 4. 不该出现的东西 ----------
    print("\n[4] 不该出现的东西")
    for label, pat in FORBIDDEN:
        chk(label, re.search(pat, src) is None)

    has_open = re.search(r"window\.open\(", src) is not None
    chk("无 window.open", not has_open)
    if has_open:
        print("       ↑ 壳的 WKUIDelegate 把 targetFrame==nil 当「在当前页打开」，")
        print("         一按 App 就被导航走且没有返回入口，只能杀进程。")

    # 页面里的 IPv4 只允许是示例 / 回环地址
    ALLOW = {"1.2.3.4", "127.0.0.1", "0.0.0.0"}
    ips = sorted(set(re.findall(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", src)))
    extra = [x for x in ips if x not in ALLOW and not x.startswith("192.168.")]
    print("    出现的 IPv4: %s" % (", ".join(ips) if ips else "无"))
    if extra:
        print("       ↑ 这些既不是示例也不是内网段，确认一下是不是真实面板地址 !!")
        bad.append("可疑 IPv4")

    # ---------- 5. 桥脚本 ----------
    print("\n[5] 桥脚本 QLBootstrap.js")
    js = z.read(APP + "QLBootstrap.js")
    jss = js.decode("utf-8")
    print("    字节: %d" % len(js))
    chk("接管 fetch", "fetch" in jss)
    chk("有 ios 标记", "'ios'" in jss)

    # ---------- 6. Info.plist ----------
    print("\n[6] Info.plist")
    pl = plistlib.loads(z.read(APP + "Info.plist"))
    for k in PLIST_KEYS:
        v = pl.get(k, "缺失 !!")
        print("    %-32s %r" % (k, v))
        if v == "缺失 !!":
            bad.append(k)
    ats = pl.get("NSAppTransportSecurity", {})
    chk("ATS 放行明文 http", ats.get("NSAllowsArbitraryLoads") is True)
    chk("ATS 放行本地网络", ats.get("NSAllowsLocalNetworking") is True)
    if ver and pl.get("CFBundleShortVersionString") != ver:
        print("    !! 包内版本 %r 与页面 APP_VER %r 对不上"
              % (pl.get("CFBundleShortVersionString"), ver))
        bad.append("包内版本")

    # ---------- 7. 可执行文件 ----------
    print("\n[7] 可执行文件")
    exe = z.read(APP + "QingLongClient")
    magic = struct.unpack("<I", exe[:4])[0]
    cputype = struct.unpack("<I", exe[4:8])[0]
    print("    字节: %d" % len(exe))
    chk("Mach-O 64 小端", magic == 0xFEEDFACF, "（magic 0x%08x）" % magic)
    chk("arm64", cputype == 0x0100000C, "（cputype 0x%08x）" % cputype)

    # ---------- 8. 签名 ----------
    print("\n[8] ad-hoc 签名结构")
    cr = z.read(APP + "_CodeSignature/CodeResources")
    print("    CodeResources 字节: %d" % len(cr))
    chk("是合法 plist", cr[:8] == b"bplist00" or cr[:5] == b"<?xml")

    print("\n" + "=" * 64)
    if bad:
        print("有 %d 项没过：%s" % (len(bad), "、".join(bad)))
        sys.exit(1)
    print("全部核对通过")


if __name__ == "__main__":
    main()
