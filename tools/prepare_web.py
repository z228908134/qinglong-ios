"""把 qinglong-pwa 的构建产物复制进 iOS 工程，作为内置页面。

用法（在本机改完 PWA 后跑一次，然后把 index.html 一起提交）：
    python tools/prepare_web.py

为什么是「复制」而不是「构建时拉取」：GitHub Actions 上只有 qinglong-ios 这个仓库，
拿不到隔壁的 qinglong-pwa。所以页面必须作为资源**提交进仓库**，
改了 PWA 忘了跑这个脚本再提交 → 手机上还是旧页面（这点在 workflow 里加了防呆）。
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(os.path.dirname(ROOT), "qinglong-pwa", "index.html")
DST = os.path.join(ROOT, "QingLongClient", "Resources", "index.html")

if not os.path.exists(SRC):
    sys.exit("找不到 %s。先在 qinglong-pwa 里跑 python tools/build.py" % SRC)

html = open(SRC, encoding="utf-8").read()
if len(html) < 20000:
    sys.exit("index.html 只有 %d 字节，像是没构建完整（正常应 >150KB）" % len(html))
if "__ICON_" in html:
    sys.exit("index.html 里还有未替换的 __ICON_ 占位符，build.py 没跑完")

# 版本号对账：iOS 工程声明的版本必须跟页面里的一致，
# 否则手机上「设置 → 关于」显示的版本跟包名对不上，排查时会误导。
m = re.search(r"var APP_VER = '([^']+)'", html)
page_ver = m.group(1) if m else "?"
yml = open(os.path.join(ROOT, "project.yml"), encoding="utf-8").read()
mv = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', yml)
proj_ver = mv.group(1) if mv else "?"
if page_ver != proj_ver:
    sys.exit("版本对不上：页面 %s，project.yml %s。改完再跑一次。" % (page_ver, proj_ver))

open(DST, "w", encoding="utf-8").write(html)
print("已写入 %s  (%.1f KB, 版本 %s)" % (
    os.path.relpath(DST, ROOT), len(html.encode("utf-8")) / 1024, page_ver))
