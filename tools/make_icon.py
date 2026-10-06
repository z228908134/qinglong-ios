import os
from PIL import Image, ImageDraw, ImageFont

SIZE = 1024
ACCENT = (23, 161, 112, 255)
WHITE = (255, 255, 255, 255)

OUT_DIR = os.path.join(
    "C:/Users/ZYW/WorkBuddy/2026-10-06-18-59-37/qinglong-ios/QingLong/Resources/Assets.xcassets/AppIcon.appiconset"
)
os.makedirs(OUT_DIR, exist_ok=True)

img = Image.new("RGBA", (SIZE, SIZE), ACCENT)
draw = ImageDraw.Draw(img)

font = None
for candidate in [
    "C:/Windows/Fonts/ariblk.ttf",
    "C:/Windows/Fonts/arialbd.ttf",
    "C:/Windows/Fonts/segoeuib.ttf",
    "C:/Windows/Fonts/arial.ttf",
]:
    if os.path.exists(candidate):
        font = ImageFont.truetype(candidate, 372)
        print("font:", candidate)
        break

if font is None:
    raise SystemExit("no usable font found")

draw.text((SIZE / 2, 452), "QL", font=font, fill=WHITE, anchor="mm")

bar_w, bar_h = 268, 34
bar_x = (SIZE - bar_w) / 2
bar_y = 700
draw.rounded_rectangle(
    [bar_x, bar_y, bar_x + bar_w, bar_y + bar_h],
    radius=bar_h / 2,
    fill=WHITE,
)

path = os.path.join(OUT_DIR, "AppIcon.png")
img.convert("RGB").save(path, "PNG")
print("saved:", path, img.size)
