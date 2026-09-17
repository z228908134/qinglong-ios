# -*- coding: utf-8 -*-
"""解包 ipa 逐项核对 —— 不是看构建日志，是把包拆开读。

用法：
    python tools/verify_ipa.py out/QingLongClient-1.0.11-trollstore.ipa
    python tools/verify_ipa.py <ipa> --pwa ../qinglong-pwa

为什么要单独写一个脚本：CI 日志只证明「打包这一步没报错」，
证明不了「包里装的页面是新的」。曾经出现过改了 PWA 忘了 prepare_web.py
就 push，CI 全绿、装到手机上功能还是老的。所以出包后一律解包读一遍。

检查项：
  1. 包结构（index.html / QLBootstrap.js / Info.plist / 可执行文件 / 签名）
  2. 内置页面：字节数、与本地构建产物**逐字节一致**、APP_VER、不预填面板地址
  3. 各功能代码是否真在包里（应用设置 / 其他设置 / 登录日志 / 字号拖动条）
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
    ("面板设置入口", r'data-goto="sysconf"'),
    ("字号 拖动条元素", r'id="fsRange"'),
    ("字号 两端 A", r'id="btnFsDown"'),
    ("字号 夹取防 NaN", r"function fsClamp\("),
    ("字号 老档位迁移", r"Object\.prototype\.hasOwnProperty\.call\(FS, v\)"),
    ("字号 滑杆重绑", r"function bindFsRange\("),
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
