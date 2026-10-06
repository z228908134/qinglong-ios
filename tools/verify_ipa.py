#!/usr/bin/env python3
"""校验 CI 产出的未签名 IPA 是否结构完整、可用 TrollStore 直接安装。

用法:
    python3 tools/verify_ipa.py QingLong-unsigned.ipa

退出码 0 表示全部通过，1 表示存在失败项。
仅依赖 Python 标准库。

背景说明（几个容易踩的点）:
  * Apple 的代码签名 blob 采用 **大端** 字节序，CSMAGIC_EMBEDDED_SIGNATURE
    在文件里的字节是 fa de 0c c0，不是 c0 0c de fa。按小端搜会误报"未签名"。
  * xcodebuild 关闭签名后，ldid -S 会往 __LINKEDIT 段的 LC_CODE_SIGNATURE
    指向的区域写入签名，因此判定依据应取 load command，而不是全文件搜字节。
"""

import plistlib
import struct
import sys
import zipfile
from pathlib import Path

APP_DIR = "Payload/QingLong.app/"
EXE_PATH = APP_DIR + "QingLong"

LC_CODE_SIGNATURE = 0x1D
CSMAGIC_EMBEDDED_SIGNATURE = 0xFADE0CC0

CPU_ARM64 = 0x0100000C
CPU_NAMES = {
    0x0100000C: "arm64",
    0x00000007: "i386",
    0x01000007: "x86_64",
    0x0000000C: "arm",
}

results = []


def check(ok, label, detail=""):
    results.append(ok)
    mark = "\033[32m✓\033[0m" if ok else "\033[31m✗\033[0m"
    line = f"{mark} {label}"
    if detail:
        line += f"\n    {detail}"
    print(line)
    return ok


def parse_macho(data):
    """返回 (cputype, filetype, code_signature(datasize), 是否找到 LC_CODE_SIGNATURE)。"""
    if len(data) < 32:
        return None
    cputype = struct.unpack("<I", data[4:8])[0]
    filetype = struct.unpack("<I", data[12:16])[0]
    ncmds = struct.unpack("<I", data[16:20])[0]
    sig_datasize = None
    off = 32
    for _ in range(ncmds):
        if off + 8 > len(data):
            break
        cmd, cmdsize = struct.unpack("<II", data[off:off + 8])
        if cmdsize == 0:
            break
        if cmd == LC_CODE_SIGNATURE:
            _, datasize = struct.unpack("<II", data[off + 8:off + 16])
            sig_datasize = datasize
        off += cmdsize
    return cputype, filetype, sig_datasize


def main():
    if len(sys.argv) < 2:
        print("用法: python3 tools/verify_ipa.py <ipa 路径>")
        return 2

    ipa = Path(sys.argv[1])
    if not ipa.exists():
        print(f"找不到文件: {ipa}")
        return 2

    z = zipfile.ZipFile(ipa)
    names = set(z.namelist())
    size = ipa.stat().st_size
    print(f"\n=== 校验 {ipa.name}  ({size:,} 字节 / {size / 1048576:.2f} MB) ===\n")

    # ---------- 1. 目录结构 ----------
    print("[1] 目录结构")
    check("Payload/" in names or any(n.startswith("Payload/") for n in names), "存在 Payload/ 目录")
    check(EXE_PATH in names, "存在可执行文件", EXE_PATH)
    check(APP_DIR + "Info.plist" in names, "存在 Info.plist")
    check(APP_DIR + "Assets.car" in names, "存在 Assets.car（图标资源已编译）")

    # ---------- 2. 可执行文件 ----------
    print("\n[2] 可执行文件架构")
    parsed = None
    if EXE_PATH in names:
        data = z.read(EXE_PATH)
        parsed = parse_macho(data)
        if parsed:
            cputype, filetype, sig_datasize = parsed
            check(cputype == CPU_ARM64, f"CPU 架构 = {CPU_NAMES.get(cputype, hex(cputype))}（要求 arm64）")
            check(filetype == 2, f"Mach-O 文件类型 = {filetype}（2 = MH_EXECUTE）")

            print("\n[3] 伪签名（TrollStore 安装依赖）")
            check(sig_datasize is not None, "存在 LC_CODE_SIGNATURE 加载命令")
            if sig_datasize is not None:
                check(sig_datasize > 0, f"签名数据大小 = {sig_datasize:,} 字节（>0 表示 ldid 已写入）")
                # 从 load command 读回偏移，核对 blob magic（大端）
                off = 32
                ncmds = struct.unpack("<I", data[16:20])[0]
                dataoff = None
                for _ in range(ncmds):
                    cmd, cmdsize = struct.unpack("<II", data[off:off + 8])
                    if cmd == LC_CODE_SIGNATURE:
                        dataoff, _ = struct.unpack("<II", data[off + 8:off + 16])
                        break
                    off += cmdsize
                if dataoff is not None and dataoff + 12 <= len(data):
                    blob = data[dataoff:dataoff + 12]
                    magic = struct.unpack(">I", blob[:4])[0]
                    length = struct.unpack(">I", blob[4:8])[0]
                    count = struct.unpack(">I", blob[8:12])[0]
                    check(magic == CSMAGIC_EMBEDDED_SIGNATURE,
                          f"签名 blob magic = 0x{magic:08x}（应为 0x{CSMAGIC_EMBEDDED_SIGNATURE:08x}）",
                          f"SuperBlob 长度 {length:,}，子项 {count} 个")
        else:
            check(False, "无法解析 Mach-O 头")

    # ---------- 4. iOS 14 兼容性 ----------
    print("\n[4] iOS 14 兼容性")
    check(APP_DIR + "Frameworks/libswift_Concurrency.dylib" in names,
          "已打包 libswift_Concurrency.dylib",
          "Swift 并发的向后部署库，iOS 14 目标必须携带")

    # ---------- 5. Info.plist ----------
    print("\n[5] Info.plist 关键字段")
    pl_path = APP_DIR + "Info.plist"
    if pl_path in names:
        pl = plistlib.loads(z.read(pl_path))
        check(pl.get("CFBundleIdentifier") == "com.qinglong.ios",
              f"CFBundleIdentifier = {pl.get('CFBundleIdentifier')}")
        check(pl.get("MinimumOSVersion") == "14.0",
              f"MinimumOSVersion = {pl.get('MinimumOSVersion')}")
        check(pl.get("CFBundleExecutable") == "QingLong",
              f"CFBundleExecutable = {pl.get('CFBundleExecutable')}")

        ats = pl.get("NSAppTransportSecurity", {})
        check(ats.get("NSAllowsArbitraryLoads") is True,
              "NSAllowsArbitraryLoads = True",
              "允许 http:// 连自建面板；无此项则局域网明文请求会被系统拦截")
        check(bool(pl.get("NSLocalNetworkUsageDescription")),
              "已声明 NSLocalNetworkUsageDescription",
              pl.get("NSLocalNetworkUsageDescription", ""))
        check(1 in (pl.get("UIDeviceFamily") or []),
              f"UIDeviceFamily = {pl.get('UIDeviceFamily')}（含 1 = iPhone）")
    else:
        check(False, "无法读取 Info.plist")

    # ---------- 汇总 ----------
    passed = sum(1 for r in results if r)
    total = len(results)
    failed = total - passed
    print(f"\n{'=' * 46}")
    if failed == 0:
        print(f"全部通过：{passed}/{total}")
        print("该 IPA 可直接用 TrollStore 安装。")
    else:
        print(f"通过 {passed}/{total}，失败 {failed} 项")
    print("=" * 46)
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
