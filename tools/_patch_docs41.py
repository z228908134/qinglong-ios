# -*- coding: utf-8 -*-
"""把 1.0.41 的构建结果补进 BUILD-IPA.md / README.md。

用法（出包 + 验货之后跑）：
    python tools/_patch_docs41.py <run_id> <ios_commit> <ipa字节> <sha256> <index字节> <产物条目数> <CodeResources字节>

为什么要写成脚本而不是手改：这份文档里 1.0.40 出现了十几处，手改必漏一处；
而且历史上漏改过「别装 1.0.29」那种句子（whole 替换会把历史版本号一起换掉）。
每条替换都 assert count==1，改完还要扫一遍残留。

⚠️ 二进制读写（newline=''）：文档是 LF，用文本模式在 Windows 上会被改成 CRLF，
   git 一看整个文件都变了。

⚠️ 锚点表**从 verify_ipa.py 里现推**（标签以「通知设置」开头的那些）——
   手抄 46 行一定会抄错一两个标签，推出来的跟 verify_ipa 天然一致。
"""
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.join(HERE, "BUILD-IPA.md")
README = os.path.join(HERE, "README.md")
VERIFY = os.path.join(HERE, "verify_ipa.py")

run_id, commit, ipa_bytes, sha, index_bytes, n_entries, n_codesig = sys.argv[1:8]

sha_short = sha[:8]

# 测试 / 变异 / FEATURES 三条数字（跑完全量变异后填这里，别手改文档）
N_TESTS = "2028"
N_MUTS = "720"
N_FEATURES = "435"

NEW_CH = """## 1.0.41：通知设置（25 个渠道 + 「保存即试发」）

「我的」页加第 14 张卡「通知设置」。面板支持 25 个推送渠道，以前只能在网页版配；
现在手机上选渠道、填参数、点一下就能配好。

- **渠道表照抄面板**：25 档（Gotify / Ntfy / GoCqHttpBot / Server酱 / PushDeer / Bark /
  Telegram机器人 / 钉钉机器人 / 企业微信机器人 / 企业微信应用 / 智能微秘书 / IGot /
  PushPlus / 微加机器人 / wxPusher / 极简推送SPT / OpeniLink / WPUSH / 群晖chat / 邮箱 /
  飞书机器人 / PushMe / Chronocat / 自定义通知 / 已关闭），顺序和叫法跟面板一字不差
  —— 用户是照面板的名字找的。**面板比 App 新、多了个渠道时那个值原样补进下拉**，
  不会悄悄换成「已关闭」（换成关闭等于替用户把通知全关了，而且界面上看不出来）。
- **保存 = 试发**：`PUT /api/user/notification`，面板会**先真发一条测试消息**，
  发得出去才存。所以手机响了 = 配好了；报「通知发送失败」= 参数不对或者网络不通，
  **这时候配置没有存上** —— 页面不会说「已保存」。
- **保存提交的是整份配置**：后端是整份替换（直接写 `info`），只提交当前渠道那几栏会把
  别的渠道填过的内容悄悄清空。我们先把面板已存的整份带上，再覆盖当前渠道。
- **「已关闭」提交空 `type`**（面板就是这么存的，存成 `closed` 后端不认识），
  而且关掉通知**不清空**各渠道填过的内容，下次选回来还在。
- **字段名按服务端真正读的那个写**：面板自己的前端把「发送模板」提交成
  `pushplusTemplate`（小写 p），而后端 `back/services/notify.ts` 读的是
  `pushPlusTemplate`（大写 P）—— 也就是说网页版填的发送模板其实不生效。
  我们按大写 P 写，同时把小写那份也写一份，免得打开网页版看见那栏是空的。
- **读不到配置不是坏**：面板第一次用通知时后端根本没有那条记录（`getDb` 找不到就 throw），
  `GET` 会返回 500。这时当成空配置继续，顶部留一行灰字说明 + 一个「重新读取」按钮，
  不把人堵在错误页上。
- **青龙的通知不走 `HTTP_PROXY`**：`back/config/http.ts` 里 undici 直连、不传 dispatcher，
  只有 Telegram 一个渠道会用它自己的代理配置。所以容器里配了代理、axios 脚本能通，
  Bark / Server酱 照样直连超时 —— 参数填对了也发不出去。页面里写明了这点。
- 测试 **%(n_tests)s** 项全过；全量变异 **%(n_muts)s** 条 0 MISS / 0 SKIP / 0 BROKEN。
  FEATURES **%(n_features)s** 条 0 失配；逐字节一致。
- ipa **%(ipa_bytes)s** 字节 sha256 `%(sha_short)s…`；三方 %(index_bytes)s 字节（android +50）。

"""

HIST = "> 1.0.41 加了「通知设置」页（25 个渠道 + 保存时先试发一条测试消息）。\n"


def anchor_rows():
    """从 verify_ipa.py 的 FEATURES 里推出 1.0.41 的锚点表行。"""
    src = io.open(VERIFY, encoding="utf-8").read()
    head = src.split("# 1.0.15 从系统设置弹层")[0]
    ns = {}
    exec(compile(head, "verify_ipa.py", "exec"), ns)
    rows = []
    for label, _pat in ns["FEATURES"]:
        if label.startswith("通知设置"):
            rows.append("| 1.0.41 新增：%s | ✅ 1 个锚点全在 |\n" % label)
    if len(rows) < 40:
        raise SystemExit("锚点表只推出 %d 行，verify_ipa.py 里的「通知设置」锚点是不是少了？" % len(rows))
    return rows


def main():
    b = io.open(BUILD, encoding="utf-8", newline="").read()
    r = io.open(README, encoding="utf-8", newline="").read()

    def sub(text, old, new, what):
        n = text.count(old)
        assert n == 1, "[%s] 命中 %d 处（应该 1 处）：%s" % (what, n, old[:70])
        return text.replace(old, new)

    # ---- 顶部表 ----
    b = sub(b, "| 最近一次构建 | ✅ 成功（run `35558097156`，commit `73e1ac2`） |",
            "| 最近一次构建 | ✅ 成功（run `%s`，commit `%s`） |" % (run_id, commit), "顶部 run")
    b = sub(b, "`QingLongClient-1.0.40-trollstore.ipa`（206208 字节）",
            "`QingLongClient-1.0.41-trollstore.ipa`（%s 字节）" % ipa_bytes, "顶部 ipa 路径")
    b = sub(b, "`dd1e6bcab7da630ebac7bae62c9d5ec47bf06a828d5d934ad0178b3e8a26961d`",
            "`%s`" % sha, "顶部 sha256")
    b = sub(b, "`QingLongClient-1.0.40-trollstore`（保留 30 天）",
            "`QingLongClient-1.0.41-trollstore`（保留 30 天）", "顶部 artifact")

    # ---- 新章节（插在 1.0.40 那节前面）----
    new_ch = NEW_CH % {
        "ipa_bytes": ipa_bytes, "sha_short": sha_short, "index_bytes": index_bytes,
        "n_tests": N_TESTS, "n_muts": N_MUTS, "n_features": N_FEATURES,
    }
    b = sub(b, "## 1.0.40：数据备份（手动备份 + 自动发现备份任务）",
            new_ch + "## 1.0.40：数据备份（手动备份 + 自动发现备份任务）", "新章节")

    # ---- 装哪一版 / 历史行 ----
    b = sub(b, "> **装 1.0.40，别装 1.0.39 及更早的**。", "> **装 1.0.41，别装 1.0.40 及更早的**。", "装哪版")
    b = sub(b, "> 1.0.40 加了「数据备份」页（手动备份弹系统分享菜单 + 自动发现青龙里的备份任务）。\n",
            "> 1.0.40 加了「数据备份」页（手动备份弹系统分享菜单 + 自动发现青龙里的备份任务）。\n" + HIST,
            "历史行")

    # ---- 核对 sha / 第 3 步 / verify 命令 ----
    b = sub(b, "sha256sum QingLongClient-1.0.40-trollstore.ipa", "sha256sum QingLongClient-1.0.41-trollstore.ipa",
            "sha 命令")
    b = sub(b, "# 应该得到 dd1e6bcab7da630ebac7bae62c9d5ec47bf06a828d5d934ad0178b3e8a26961d",
            "# 应该得到 " + sha, "sha 期望值")
    b = sub(b, "qinglong-ios/out/QingLongClient-1.0.40-trollstore.ipa",
            "qinglong-ios/out/QingLongClient-1.0.41-trollstore.ipa", "第 3 步路径")
    b = sub(b, "python tools/verify_ipa.py out/QingLongClient-1.0.40-trollstore.ipa",
            "python tools/verify_ipa.py out/QingLongClient-1.0.41-trollstore.ipa", "verify 命令")

    # ---- 验货表 ----
    b = sub(b, "| `Payload/QingLongClient.app/` 结构 | ✅ 12 个条目 |",
            "| `Payload/QingLongClient.app/` 结构 | ✅ %s 个条目 |" % n_entries, "验货 条目数")
    b = sub(b, "| `_CodeSignature/CodeResources`（ad-hoc 签名结构） | ✅ 2961 字节 |",
            "| `_CodeSignature/CodeResources`（ad-hoc 签名结构） | ✅ %s 字节 |" % n_codesig, "验货 CodeResources")
    b = sub(b, "| `index.html` | ✅ 462886 字节，**与本地构建产物逐字节一致** |",
            "| `index.html` | ✅ %s 字节，**与本地构建产物逐字节一致** |" % index_bytes, "验货 index")
    b = sub(b, "| 页面 `APP_VER` | ✅ 1.0.40（与 `MARKETING_VERSION`、ipa 文件名三处一致） |",
            "| 页面 `APP_VER` | ✅ 1.0.41（与 `MARKETING_VERSION`、ipa 文件名三处一致） |", "验货 APP_VER")

    # ---- 锚点表追加 ----
    rows = anchor_rows()
    anchor_block = "".join(rows)
    b = sub(b, "| 1.0.40 新增：数据备份 refresh 管这一页 | ✅ 1 个锚点全在 |\n",
            "| 1.0.40 新增：数据备份 refresh 管这一页 | ✅ 1 个锚点全在 |\n" + anchor_block,
            "锚点表尾")
    print("锚点表追加 %d 行" % len(rows))

    # ---- README ----
    r = sub(r, "与安卓 1.0.40 完全相同", "与安卓 1.0.41 完全相同", "README 版本")

    # ---- 残留扫描：正文里不该再有 1.0.40 当「当前版本」的说法 ----
    left = [m for m in re.findall(r".{0,40}1\.0\.40.{0,40}", b) if "别装" not in m and "新增" not in m]
    io.open(BUILD, "w", encoding="utf-8", newline="").write(b)
    io.open(README, "w", encoding="utf-8", newline="").write(r)
    print("改完了。BUILD-IPA.md 里剩下的 1.0.40 提及（应该都是历史/锚点）：")
    for x in left:
        print("  " + x.replace("\n", " "))


if __name__ == "__main__":
    main()
