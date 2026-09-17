"""生成 1024x1024 的 App 图标（纯标准库，无需 Pillow）。
设计：teal 底 + 白色闪电（呼应青龙面板）。抗锯齿用 4x 行超采样。
"""
import struct
import zlib

W = H = 1024
SS = 4

BG = (29, 158, 117)      # #1D9E75
FG = (255, 255, 255)

# 闪电多边形（0~1 归一化坐标）
RAW = [
    (0.58, 0.06),
    (0.28, 0.52),
    (0.46, 0.52),
    (0.40, 0.94),
    (0.72, 0.46),
    (0.54, 0.46),
]

SCALE = 0.66
CX = CY = 0.5
PTS = [
    (CX + (x - CX) * SCALE, CY + (y - CY) * SCALE)
    for (x, y) in RAW
]
PTS = [(x * W, y * H) for (x, y) in PTS]
N = len(PTS)


def add_span(row, x0, x1, weight):
    if x1 <= x0:
        return
    if x0 < 0:
        x0 = 0.0
    if x1 > W:
        x1 = float(W)
    if x1 <= x0:
        return
    i0 = int(x0)
    i1 = int(x1)
    if i0 == i1:
        row[i0] += weight * (x1 - x0)
        return
    row[i0] += weight * (i0 + 1 - x0)
    last = min(i1, W - 1)
    for i in range(i0 + 1, last):
        row[i] += weight
    if i1 < W:
        row[i1] += weight * (x1 - i1)
    else:
        row[W - 1] += weight * (x1 - last)


coverage = [[0.0] * W for _ in range(H)]

for y in range(H):
    row = coverage[y]
    for s in range(SS):
        yy = y + (s + 0.5) / SS
        xs = []
        for i in range(N):
            x1, y1 = PTS[i]
            x2, y2 = PTS[(i + 1) % N]
            if (y1 <= yy < y2) or (y2 <= yy < y1):
                t = (yy - y1) / (y2 - y1)
                xs.append(x1 + t * (x2 - x1))
        xs.sort()
        for k in range(0, len(xs) - 1, 2):
            add_span(row, xs[k], xs[k + 1], 1.0 / SS)

raw = bytearray()
for y in range(H):
    raw.append(0)
    row = coverage[y]
    for x in range(W):
        c = row[x]
        if c <= 0.0:
            raw += bytes(BG) + b"\xff"
        elif c >= 1.0:
            raw += bytes(FG) + b"\xff"
        else:
            r = int(BG[0] + (FG[0] - BG[0]) * c + 0.5)
            g = int(BG[1] + (FG[1] - BG[1]) * c + 0.5)
            b = int(BG[2] + (FG[2] - BG[2]) * c + 0.5)
            raw += bytes((r, g, b, 255))


def chunk(tag, data):
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


out = (
    b"\x89PNG\r\n\x1a\n"
    + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0))
    + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    + chunk(b"IEND", b"")
)

path = "QingLongClient/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
with open(path, "wb") as f:
    f.write(out)
print("written:", path, len(out), "bytes")
