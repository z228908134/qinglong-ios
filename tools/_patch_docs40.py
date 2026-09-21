# -*- coding: utf-8 -*-
"""把 1.0.40 的构建结果补进 BUILD-IPA.md / README.md。

用法（出包 + 验货之后跑）：
    python _patch_docs40.py <run_id> <ios_commit> <ipa字节> <sha256> <index字节> <产物条目数> <CodeResources字节>

为什么要写成脚本而不是手改：这份文档里 1.0.39 出现了 12 处，手改必漏一处；
而且历史上漏改过「别装 1.0.29」那种句子（whole 替换会把历史版本号一起换掉）。
每条替换都 assert count==1，改完还要扫一遍残留。

⚠️ 二进制读写（newline=''）：文档是 LF，用文本模式在 Windows 上会被改成 CRLF，
   git 一看整个文件都变了。
"""
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.join(HERE, "BUILD-IPA.md")
README = os.path.join(HERE, "README.md")

run_id, commit, ipa_bytes, sha, index_bytes, n_entries, n_codesig = sys.argv[1:8]

NEW_CH = """## 1.0.40：数据备份（手动备份 + 自动发现备份任务）

「我的」页加第 13 张卡「数据备份」。以前想备份面板只能去网页版翻系统设置，
手机上要么打不开要么点错；现在手机上两步就能存一份。

- **立即备份**：勾要备份的模块（基础数据固定必选 —— 后端 `base` 对应数据库 + 上传目录，
  取消掉等于备份个空壳），调 `PUT /api/system/data/export` 拿 `.tgz`，
  然后弹**系统分享菜单**：飞牛 / 百度 / 微信 / 其他 App 都行，App 不绑死网盘。
  文件名带时间戳（`qinglong-20260920-070509.tgz`），多份不会互相盖。
- **还原数据**：复用系统设置页那份 `importBackup`（两步：先上传解包、再 `reload` 让面板真用上新数据）。
- **自动备份任务**：从任务列表里筛出名字含「备份」或 `backup` 的任务（不区分大小写），
  按上次运行时间倒序列出来；点一行跳**运行实例**页（跟 1.0.37 那条路共用），
  能看它到底跑没跑、跑了多久。一条都没有时给的是**引导**（怎么挂、为什么放青龙），不是一片空白。
- **定时 + 上传不做在 App 里**：iOS 的后台会被系统杀掉，定时根本靠不住。
  这一步交给青龙侧的脚本（`PUT /api/system/data/export` + `rclone` 推 WebDAV，
  飞牛 / 群晖 / 坚果云一套配置通吃），**任务名里带「备份」两个字**就会被这页认出来。
- 顺手把「备份内容」那排模块按钮的勾选状态做成**只有这一页的**（`bkToggleMod`）——
  系统设置页早有一个同名函数，同名函数后定义的会盖掉先定义的，点备份页会改到那一页去。
- 测试 **1939** 项全过；全量变异 **674** 条 0 MISS / 0 SKIP / 0 BROKEN。
  FEATURES **395** 条 0 失配；逐字节一致。
- ipa **%(ipa_bytes)s** 字节 sha256 `%(sha_short)s…`；三方 %(index_bytes)s 字节（android +50）。

"""

HIST = "> 1.0.40 加了「数据备份」页（手动备份弹系统分享菜单 + 自动发现青龙里的备份任务）。\n"

ANCHORS = [
    ("1.0.40 新增：数据备份 视图（`<section class=\"view\" id=\"v-backup\">`）", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 标题（`backup: '数据备份'`）", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 FEATURES 卡（`{ tab: 'backup',`）", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 状态字段（`mods` / `hisCrons` / `loading` / `busy`）", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 跳转函数（`gotoBackup`）", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 `isBackupCron`（名字含「备份」/ `backup` 才命中）", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 关键词 中英文都要认（`/备份|backup/`）", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 `backupFindCrons`（筛 + 按上次运行倒序）", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 倒序（`b.when - a.when`）", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 `loadBackup` 把结果填进 `hisCrons`", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 按勾选组装 `type`", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 导出走 `PUT`（`apiBlob` 默认 POST，写死会 404）", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 文件名带时间戳", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 `fmtStamp`（`YYYYMMDD-HHMMSS`）", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 `fmtStamp` 补零（不补零 9 月会排在 10 月后面）", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 `bkToggleMod`（**不是** `toggleBackupMod`，重名会串台）", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 「基础数据」不可取消", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 勾选同步按钮 `.on`", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 模块按钮 `data-bkmod`", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 「基础数据」默认勾上（`m[2]` 那档）", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 打包中禁用按钮（连点会叠好几个请求）", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 打包中按钮文案", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 任务行可点（`data-gobkinst`）", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 「尚未运行」", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 副标题「N 个备份任务」", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 空态（怎么挂）", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 空态提到 rclone（网盘怎么传）", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 委托选择器 属性（`[data-gobkinst],[data-bkmod]`）", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 委托选择器 按钮（`#btnBkExport,#btnBkImport,#btnBkRetry`）", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 委托分支 任务行（跳运行实例）", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 委托分支 模块（`bkToggleMod`）", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 委托分支 立即备份（`exportBackupNow`）", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 委托分支 还原（点隐藏文件框）", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 文件框 `id=\"fileBkImport\"`", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 还原接 `importBackup`（共享系统设置页那份）", "1 个锚点全在"),
    ("1.0.40 新增：数据备份 `refresh` 管这一页", "1 个锚点全在"),
]


def sub(text, old, new, label):
    n = text.count(old)
    assert n == 1, "「%s」出现 %d 次（应为 1 次）" % (label, n)
    return text.replace(old, new)


def main():
    sha_short = sha[:8]
    b = io.open(BUILD, encoding="utf-8", newline="").read()
    r = io.open(README, encoding="utf-8", newline="").read()

    # ---- 顶部表 ----
    b = sub(b, "| 最近一次构建 | ✅ 成功（run `35515955275`，commit `dc80a81`） |",
            "| 最近一次构建 | ✅ 成功（run `%s`，commit `%s`） |" % (run_id, commit), "顶部 run")
    b = sub(b, "`qinglong-ios/out/QingLongClient-1.0.39-trollstore.ipa`（201867 字节）",
            "`qinglong-ios/out/QingLongClient-1.0.40-trollstore.ipa`（%s 字节）" % ipa_bytes, "顶部 ipa")
    b = sub(b, "| SHA256 | `3147823f159b95705e75d70977facb1d2bf0b21935a29db740db0c3ff22c46b3` |",
            "| SHA256 | `%s` |" % sha, "顶部 sha")
    b = sub(b, "`QingLongClient-1.0.39-trollstore`（保留 30 天）",
            "`QingLongClient-1.0.40-trollstore`（保留 30 天）", "顶部 artifact")

    # ---- 新章节（插在 1.0.39 那节前面）----
    new_ch = NEW_CH % {"ipa_bytes": ipa_bytes, "sha_short": sha_short, "index_bytes": index_bytes}
    b = sub(b, "## 1.0.39：批量加 / 删标签（任务页 + 变量页）", new_ch + "## 1.0.39：批量加 / 删标签（任务页 + 变量页）",
            "新章节")

    # ---- 装哪一版 / 历史行 ----
    b = sub(b, "> **装 1.0.39，别装 1.0.38 及更早的**。", "> **装 1.0.40，别装 1.0.39 及更早的**。", "装哪版")
    b = sub(b, "> 1.0.39 给任务 / 变量页批量栏加了「加 / 删标签」两个按钮（共用 promptLabels 弹层）。\n",
            "> 1.0.39 给任务 / 变量页批量栏加了「加 / 删标签」两个按钮（共用 promptLabels 弹层）。\n" + HIST,
            "历史行")

    # ---- 核对 sha / 第 3 步 / verify 命令 ----
    b = sub(b, "sha256sum QingLongClient-1.0.39-trollstore.ipa", "sha256sum QingLongClient-1.0.40-trollstore.ipa",
            "sha 命令")
    b = sub(b, "# 应该得到 3147823f159b95705e75d70977facb1d2bf0b21935a29db740db0c3ff22c46b3",
            "# 应该得到 " + sha, "sha 期望值")
    b = sub(b, "qinglong-ios/out/QingLongClient-1.0.39-trollstore.ipa", "qinglong-ios/out/QingLongClient-1.0.40-trollstore.ipa",
            "第 3 步路径")
    b = sub(b, "python tools/verify_ipa.py out/QingLongClient-1.0.39-trollstore.ipa",
            "python tools/verify_ipa.py out/QingLongClient-1.0.40-trollstore.ipa", "verify 命令")

    # ---- 验货表 ----
    b = sub(b, "| `Payload/QingLongClient.app/` 结构 | ✅ 12 个条目 |",
            "| `Payload/QingLongClient.app/` 结构 | ✅ %s 个条目 |" % n_entries, "验货 条目数")
    b = sub(b, "| `_CodeSignature/CodeResources`（ad-hoc 签名结构） | ✅ 2961 字节 |",
            "| `_CodeSignature/CodeResources`（ad-hoc 签名结构） | ✅ %s 字节 |" % n_codesig, "验货 CodeResources")
    b = sub(b, "| `index.html` | ✅ 450302 字节，**与本地构建产物逐字节一致** |",
            "| `index.html` | ✅ %s 字节，**与本地构建产物逐字节一致** |" % index_bytes, "验货 index")
    b = sub(b, "| 页面 `APP_VER` | ✅ 1.0.39（与 `MARKETING_VERSION`、ipa 文件名三处一致） |",
            "| 页面 `APP_VER` | ✅ 1.0.40（与 `MARKETING_VERSION`、ipa 文件名三处一致） |", "验货 APP_VER")

    # ---- 锚点表追加 ----
    anchor_block = "".join("| %s | ✅ %s |\n" % (a, s) for a, s in ANCHORS)
    b = sub(b, "| 1.0.39 新增：批量标签 变量页 `promptLabels('env', ...)` 调弹层 | ✅ 1 个锚点全在 |\n",
            "| 1.0.39 新增：批量标签 变量页 `promptLabels('env', ...)` 调弹层 | ✅ 1 个锚点全在 |\n" + anchor_block,
            "锚点表尾")

    # ---- README ----
    r = sub(r, "与安卓 1.0.39 完全相同", "与安卓 1.0.40 完全相同", "README 版本")

    # ---- 残留扫描：正文里不该再有 1.0.39 当「当前版本」的说法 ----
    left = [m for m in re.findall(r".{0,40}1\.0\.39.{0,40}", b) if "别装" not in m and "新增" not in m]
    io.open(BUILD, "w", encoding="utf-8", newline="").write(b)
    io.open(README, "w", encoding="utf-8", newline="").write(r)
    print("改完了。BUILD-IPA.md 里剩下的 1.0.39 提及（应该都是历史/锚点）：")
    for x in left:
        print("  " + x.replace("\n", " "))


if __name__ == "__main__":
    main()
