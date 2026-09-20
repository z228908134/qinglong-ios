# -*- coding: utf-8 -*-
"""1.0.35 文档补丁：BUILD-IPA.md / README.md。

⚠️ 这两个文件里**同时存在多个历史版本号**（1.0.33 / 1.0.34 都还在），
   所以一律**不许**做「把 1.0.34 全换成 1.0.35」这种整体替换 ——
   那样会把「别装 1.0.33 及更早的」那类句子一起改掉（1.0.26 / 1.0.30 各踩过一次）。
   每条替换都带够上下文，并 assert 命中次数 == 1，命中 0 处或 2 处以上直接报错停下。

二进制读写保 LF。
"""
import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

NEW_SHA = "e80daa02a985257740e41cb089968be817bfc5625de271bde8d2e5b885cc6297"
OLD_SHA = "2790688a6815c4eeb27e8b58ff4cb7641ac243125e6b034d80b8684bad16250c"
NEW_RUN = "35494965773"
NEW_IOS_COMMIT = "d9f795c"
NEW_IPA = "191900"

HIGHLIGHT = """> **1.0.35：「我的」页会记路了，订阅 / 依赖 / 配置三处搜完能看见命中在哪**：
> - **「我的」页顶部加「最近打开」**：记下最近点过的 3 个功能模块，放在 12 张
>   功能卡片上面，第二次进来直接点。底栏只有四个 tab（任务 / 变量 / 脚本 / 我的），
>   订阅 / 依赖 / 配置 / 日志都得从这一页进 —— 常用的那两三个每次都要重新找一遍。
>   只记「能当 tab 用的」（系统设置那张走弹层，记下来也跳不过去）；读的时候顺手把
>   「现在已经没有的模块」滤掉，不然会留一张点不动的空卡。
> - **订阅 / 依赖两页补上搜索命中高亮**：任务 / 变量 / 脚本三页一直有，这两页搜完
>   只是「列表变短了」，命中的是哪几个字还得自己一行行找。订阅那页名字、链接、
>   类型标签、排期、分支都圈；依赖那页名称和备注一起圈（备注展开后才看得到）。
> - **配置文件页补搜索**：面板自带的就 `auth.json` / `config.sh` 那几个，但装过插件、
>   自己加过 `extra.sh` 的能堆到十几个。列表是整份拉回来的，所以**纯本地过滤、
>   不重打接口**；副标题给「命中 / 总数」（「2 / 6 个文件」），一条都没命中时
>   空态带上你敲的字，而不是笼统一句「没有配置文件」。
"""

ANCHOR_ROWS = [
    "1.0.35 新增：最近打开存储键（`recent: 'ql.recent'`）",
    "1.0.35 新增：最近打开读取函数（`function recentTabs()`）",
    "1.0.35 新增：只记能当 tab 的模块（`FEATURES.some(f => f.tab === t)`）",
    "1.0.35 新增：记录里有重复要去重（`seen[t]`）",
    "1.0.35 新增：读的时候最多留 3 个（`}).slice(0, 3)`）",
    "1.0.35 新增：记录函数（`function pushRecent(tab)`）",
    "1.0.35 新增：写之前先去掉同名的（`filter(t => t !== tab)`）",
    "1.0.35 新增：存进去的时候也只留 3 个（`list.slice(0, 3)`）",
    "1.0.35 新增：有记录时才读一次（`var rec = recentTabs()`）",
    "1.0.35 新增：「最近打开」区标题（`<div class=\"sec\">最近打开</div>`）",
    "1.0.35 新增：点功能卡片时记一笔（`pushRecent(el.dataset.goto)`）",
    "1.0.35 新增：订阅名命中上黄底（`logHi(x.name …, s.q)`）",
    "1.0.35 新增：订阅链接命中上黄底（`logHi(x.url, s.q)`）",
    "1.0.35 新增：订阅类型标签命中上黄底（`logHi(subTypeName(x.type), s.q)`）",
    "1.0.35 新增：依赖名命中上黄底（`logHi(x.name, d.q)`）",
    "1.0.35 新增：依赖备注命中上黄底（`logHi(x.remark, d.q)`）",
    "1.0.35 新增：配置文件页搜索框（`id=\"cfgSearch\"`）",
    "1.0.35 新增：配置文件按文件名本地过滤",
    "1.0.35 新增：副标题给「命中 / 总数」（`list.length + ' / ' + c.list.length`）",
    "1.0.35 新增：搜不到时空态带上关键字（`没有匹配「' + esc(c.q) + '」`）",
    "1.0.35 新增：配置文件名命中上黄底（`logHi(f.title, c.q)`）",
    "1.0.35 新增：搜索框挂了 input 事件（`$('#cfgSearch')`）",
    "1.0.35 新增：搜索只重画不重打接口（`S.configs.q = …; renderConfigs()`）",
    "1.0.35 新增：`configs` 状态带 `q`",
    "1.0.34 跟进：编辑态勾选圈改锚 `logHi`（订阅名换了高亮渲染）",
]


def patch(path, edits):
    full = os.path.join(ROOT, path)
    with io.open(full, "rb") as f:
        raw = f.read()
    text = raw.decode("utf-8")
    if b"\r\n" in raw:
        sys.exit("%s 里有 CRLF，先查一下" % path)
    for label, old, new in edits:
        n = text.count(old)
        if n != 1:
            sys.exit("!! %s / %s 命中 %d 处（要求 1）" % (path, label, n))
        text = text.replace(old, new)
    with io.open(full, "wb") as f:
        f.write(text.encode("utf-8"))
    print("  写好 %s（%d 条替换）" % (path, len(edits)))


# ---------------- BUILD-IPA.md ----------------
old_block_start = "> **1.0.34：订阅页也能批量了，批量动作不再「原样全发」**："
old_block_end = ">   （变量 / 依赖 / 订阅三页都有这两句，就任务页漏了）。"
bld = os.path.join(ROOT, "BUILD-IPA.md")
with io.open(bld, "rb") as f:
    bt = f.read().decode("utf-8")
i = bt.find(old_block_start)
j = bt.find(old_block_end)
if i < 0 or j < 0:
    sys.exit("!! BUILD-IPA.md 里找不到 1.0.34 那段说明块")
j += len(old_block_end)

edits_ipa = [
    ("最近一次构建", "run `35490985882`，commit `b3b2121`",
     "run `%s`，commit `%s`" % (NEW_RUN, NEW_IOS_COMMIT)),
    ("本地 ipa", "QingLongClient-1.0.34-trollstore.ipa`（190569 字节）",
     "QingLongClient-1.0.35-trollstore.ipa`（%s 字节）" % NEW_IPA),
    ("SHA256", "| SHA256 | `%s` |" % OLD_SHA, "| SHA256 | `%s` |" % NEW_SHA),
    ("产物保留", "→ `QingLongClient-1.0.34-trollstore`（保留 30 天）",
     "→ `QingLongClient-1.0.35-trollstore`（保留 30 天）"),
    ("装哪个", "> **装 1.0.34，别装 1.0.33 及更早的**。",
     "> **装 1.0.35，别装 1.0.34 及更早的**。"),
    ("历史一行", "> 1.0.34 给订阅页补上批量操作，四个页面的批量动作改成按状态过滤 + 批量栏细分提示。",
     "> 1.0.34 给订阅页补上批量操作，四个页面的批量动作改成按状态过滤 + 批量栏细分提示。\n"
     "> 1.0.35 加了「我的」页的「最近打开」、订阅 / 依赖两页的搜索命中高亮、配置文件页搜索。"),
    ("sha256sum", "sha256sum QingLongClient-1.0.34-trollstore.ipa",
     "sha256sum QingLongClient-1.0.35-trollstore.ipa"),
    ("应得哈希", "# 应该得到 %s" % OLD_SHA, "# 应该得到 %s" % NEW_SHA),
    ("产物路径", "qinglong-ios/out/QingLongClient-1.0.34-trollstore.ipa",
     "qinglong-ios/out/QingLongClient-1.0.35-trollstore.ipa"),
    ("验货命令", "python tools/verify_ipa.py out/QingLongClient-1.0.34-trollstore.ipa",
     "python tools/verify_ipa.py out/QingLongClient-1.0.35-trollstore.ipa"),
    ("APP_VER 表", "| 页面 `APP_VER` | ✅ 1.0.34（与", "| 页面 `APP_VER` | ✅ 1.0.35（与"),
    ("版本表", "| `CFBundleIdentifier` / 版本 | ✅ `com.qinglong.client` / 1.0.34 (34) |",
     "| `CFBundleIdentifier` / 版本 | ✅ `com.qinglong.client` / 1.0.35 (35) |"),
    ("锚点表尾行",
     "| 1.0.34 修复：任务页切走还原按钮文案（`var bC = $('#btnCronEdit');`） | ✅ 1 个锚点全在 |",
     "| 1.0.34 修复：任务页切走还原按钮文案（`var bC = $('#btnCronEdit');`） | ✅ 1 个锚点全在 |\n"
     + "\n".join("| %s | ✅ 1 个锚点全在 |" % r for r in ANCHOR_ROWS)),
]

# 说明块单独做（整段替换，起点终点都算过，是文件里唯一那一段）
with io.open(bld, "rb") as f:
    text = f.read().decode("utf-8")
seg = text[i:j]
if text.count(old_block_start) != 1:
    sys.exit("!! 1.0.34 说明块的起点不唯一")
text = text[:i] + HIGHLIGHT.rstrip("\n") + text[j:]
with io.open(bld, "wb") as f:
    f.write(text.encode("utf-8"))
print("  写好 BUILD-IPA.md（说明块 + %d 条替换）" % len(edits_ipa))

patch("BUILD-IPA.md", edits_ipa)

# ---------------- README.md ----------------
patch("README.md", [
    ("安卓版本 1", "与安卓 1.0.34 完全相同的", "与安卓 1.0.35 完全相同的"),
    ("安卓版本 2", "（跟安卓 1.0.34 同一份）", "（跟安卓 1.0.35 同一份）"),
    ("订阅管理行",
     "手动运行、启用/禁用、查看日志、**批量操作**（全选 / 运行 / 停止 / 启用 / 禁用 / 删除，按选中项状态过滤） |",
     "手动运行、启用/禁用、查看日志、**批量操作**（全选 / 运行 / 停止 / 启用 / 禁用 / 删除，按选中项状态过滤）；**搜索结果命中上黄底**（名称 / 链接 / 类型 / 排期 / 分支） |"),
    ("依赖管理行",
     "**支持批量操作**（全选 / 重装 / 删除 / 强制删除） |",
     "**支持批量操作**（全选 / 重装 / 删除 / 强制删除）；**搜索结果命中上黄底**（名称和备注一起圈） |"),
    ("面板设置行",
     "`config.sh` 等文件的内容查看与保存 |",
     "`config.sh` 等文件的内容查看与保存；**按文件名搜索**（整份列表本地过滤，不重打接口） |"),
    ("我的行",
     "+ 顶部「切换账号」胶囊 |",
     "+ 顶部「切换账号」胶囊；最上面一排**「最近打开」**（最近点过的 3 个模块，省得每次在 12 张卡片里翻） |"),
])

print("\n残留扫描：")
for p in ("BUILD-IPA.md", "README.md"):
    with io.open(os.path.join(ROOT, p), "rb") as f:
        t = f.read().decode("utf-8")
    hits = []
    for bad in ("190569", OLD_SHA, "35490985882", "b3b2121"):
        if bad in t:
            hits.append(bad)
    # 「1.0.34」还会合法地留在历史说明里，只统计「不该再有」的那些
    print("  %-14s %s" % (p, "干净" if not hits else "!! 残留 " + ", ".join(hits)))
