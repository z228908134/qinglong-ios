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
    ("日志 搜索框", r'id="logSearch"'),
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
    ("详情 日志历史直达", r"data-gocronlogdir="),
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
    ("日志 搜索框", r'id="logFind"'),
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
    ("批量 运行走 run 接口", r"await api\('/api/crons/run', \{ method: 'PUT', body: ids \}\)"),
    ("批量 停止走 stop 接口", r"await api\('/api/crons/stop', \{ method: 'PUT', body: ids \}\)"),
    # 批量栏比底栏高一截，列表底部留白要跟着加，不然最后一张卡片被盖住。
    # 1.0.24：变量页也加了批量栏，两条栏同高，这条规则并成了一条选择器 ——
    # 锚点绑字面量，CSS 改写法就得跟着改，不然出包后这里报一项缺失。
    ("批量 编辑模式加留白", r"#main\.cronedit,#main\.envsedit\{padding-bottom:calc\(168px \+ var\(--bot\)\)\}"),
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
    ("变量 批量启用接口", r"await api\('/api/envs/enable', \{ method: 'PUT', body: ids \}\)"),
    ("变量 批量禁用接口", r"await api\('/api/envs/disable', \{ method: 'PUT', body: ids \}\)"),
    ("变量 批量删除接口", r"await api\('/api/envs', \{ method: 'DELETE', body: ids \}\)"),
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
