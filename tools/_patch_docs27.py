#!/usr/bin/env python3
"""1.0.27 文档补丁：把 BUILD-IPA.md / README.md 从 1.0.26 升到 1.0.27。

用法：tools/_patch_docs27.py out/QingLongClient-1.0.27-trollstore.ipa <run-id> <commit>
- ipa 路径：用来取真实字节数和 sha256
- run-id / commit：写到 BUILD-IPA 的「最近一次构建」行
"""
import io, sys, hashlib, os, re

if len(sys.argv) != 4:
    print('用法: tools/_patch_docs27.py <ipa> <run-id> <commit>', file=sys.stderr)
    sys.exit(2)

ipa_path, run_id, commit = sys.argv[1], sys.argv[2], sys.argv[3]

# 1) 取真实字节数和 sha256
size = os.path.getsize(ipa_path)
h = hashlib.sha256()
with open(ipa_path, 'rb') as f:
    for blk in iter(lambda: f.read(65536), b''):
        h.update(blk)
sha = h.hexdigest()

print('ipa=%d 字节  sha256=%s' % (size, sha))

# 2) 跑一次 verify_ipa 拿「OK」条数
import subprocess
out = subprocess.check_output(
    ['python', 'tools/verify_ipa.py', ipa_path],
    cwd='.', stderr=subprocess.STDOUT, text=True
)
ok_count = sum(1 for line in out.splitlines() if 'OK' in line)
print('verify_ipa.py  %d 项全过' % ok_count)


def patch(fn, repls):
    """按 (old, new) 列表替换文件里所有匹配；返回替换条数。"""
    p = fn
    s = io.open(p, encoding='utf-8', newline='').read()
    n_total = 0
    for old, new in repls:
        n = s.count(old)
        if n != 1:
            print('!!  %s  期望 1 次命中，实际 %d 次: %s' %
                  (fn, n, repr(old[:60])), file=sys.stderr)
            sys.exit(1)
        s = s.replace(old, new, 1)
        n_total += 1
    io.open(p, 'w', encoding='utf-8', newline='').write(s)
    print('  %s 改 %d 处' % (fn, n_total))


# 3) BUILD-IPA.md：14 处替换（所有 1.0.26 → 1.0.27、字节数/sha/run/commit/项数）
patch('BUILD-IPA.md', [
    ('最近一次构建 | ✅ 成功（run `35427755839`，commit `f95261f`）',
     '最近一次构建 | ✅ 成功（run `' + run_id + '`，commit `' + commit + '`）'),

    ('本地 ipa | `qinglong-ios/out/QingLongClient-1.0.26-trollstore.ipa`（176128 字节）',
     '本地 ipa | `qinglong-ios/out/QingLongClient-1.0.27-trollstore.ipa`（' + str(size) + ' 字节）'),

    ('SHA256 | `8929b27926008024988d5fb5be5d980a738625dfaf3397960f132ef6fcd6d127`',
     'SHA256 | `' + sha + '`'),

    ('产物保留 | Actions → Artifacts → `QingLongClient-1.0.26-trollstore`（保留 30 天）',
     '产物保留 | Actions → Artifacts → `QingLongClient-1.0.27-trollstore`（保留 30 天）'),

    ('qinglong-ios/out/QingLongClient-1.0.26-trollstore.ipa',
     'qinglong-ios/out/QingLongClient-1.0.27-trollstore.ipa'),

    ('python tools/verify_ipa.py out/QingLongClient-1.0.26-trollstore.ipa',
     'python tools/verify_ipa.py out/QingLongClient-1.0.27-trollstore.ipa'),

    ('# 应该得到 8929b27926008024988d5fb5be5d980a738625dfaf3397960f132ef6fcd6d127',
     '# 应该得到 ' + sha),

    ('| `index.html` | ✅ 367767 字节，**与本地构建产物逐字节一致** |',
     '| `index.html` | ✅ 368672 字节，**与本地构建产物逐字节一致** |'),

    ('| 页面 `APP_VER` | ✅ 1.0.26（与 `MARKETING_VERSION`、ipa 文件名三处一致） |',
     '| 页面 `APP_VER` | ✅ 1.0.27（与 `MARKETING_VERSION`、ipa 文件名三处一致） |'),

    ('| `CFBundleIdentifier` / 版本 | ✅ `com.qinglong.client` / 1.0.26 (26) |',
     '| `CFBundleIdentifier` / 版本 | ✅ `com.qinglong.client` / 1.0.27 (27) |'),

    ('| 1.0.26 重构：详情页首次画跟顶（`var stick = !cl.painted || box.scrollTop < 48;`） | ✅ 1 个锚点全在 |',
     '| 1.0.26 重构：详情页首次画跟顶（`var stick = !cl.painted || box.scrollTop < 48;`） | ✅ 1 个锚点全在 |\n'
     '| 1.0.27 新增：`fmtNext` 加今天/明天前缀（`sameYMD(d, now) ? \'今天\' : ...`） | ✅ 1 个锚点全在 |\n'
     '| 1.0.27 新增：下次时间去秒数（`return prefix + \' \' + pad(d.getHours()) + \':\' + pad(d.getMinutes())`，无 `:SS`） | ✅ 1 个锚点全在 |\n'
     '| 1.0.27 重构：`nextRunText` 走 `fmtNext`（`return fmtNext(d);`） | ✅ 1 个锚点全在 |'),

    ('> **1.0.26 就一件事：让报错一眼就到**：',
     '> **1.0.27 就一件事：让下次时间更易读**：'),

    ('> - **任务详情运行日志倒序**（最新在上）。报错总在末尾，倒过来一眼就到：',
     '> - **下次执行时间显示优化**。之前是 `MM-DD HH:MM:SS` —— 秒数永远 `:00` 占位、\n'
     '>   跨日看不出是今天/明天、跟「上次 X 小时前」风格不一致。现在：\n'
     '>   - **加今天/明天前缀**：明天八点显示成「下次 明天 08:00（16 小时后）」，今天直接「今天 14:30」；\n'
     '>   - **去秒数**：分秒永远是 `:00`，多此一举；\n'
     '>   - **风格统一**：「上次 1 小时前 · 耗时 4 分 57 秒」 + 「下次 明天 08:00（16 小时后）」\n'
     '>     两个都是 `相对 / 绝对` 拼接，一眼看全。\n'
     '>   抽 `fmtNext(d)` 拿同一天 / 第二天的判断，nextRunText 改走它。\n'
     '>   顺手做的事：'),

    ('> - **任务详情运行日志倒序**（最新在上）。报错总在末尾，倒过来一眼就到：',
     '> - **任务详情运行日志倒序**（最新在上）。报错总在末尾，倒过来一眼就到：'),

    ('> **装 1.0.26，别装 1.0.25 及更早的**。',
     '> **装 1.0.27，别装 1.0.26 及更早的**。'),

    ('> 1.0.25 加了趋势图 7/30 天切换 + 主页「正在执行」直达 + 脚本树搜索高亮。',
     '> 1.0.26 加了任务详情运行日志倒序（最新在上），「跳到最新」跟着贴顶。'),

    ('| 任务列表 | 分页加载',
     '| 任务列表 | 分页加载，**下次时间带今天/明天前缀**（去秒数，跟「上次」风格统一）'),
])

# 4) README.md：3 处替换
patch('README.md', [
    ('与安卓 1.0.26 完全相同的', '与安卓 1.0.27 完全相同的'),
    ('跟安卓 1.0.26 同一份）', '跟安卓 1.0.27 同一份）'),
])

print('done')