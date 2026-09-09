"""详细分析截图，找模型边界"""
import sys
from PIL import Image

img = Image.open(r"E:\项目储存\决竞球battle-ball\sim_results\gui_screenshot_v3.png")
w, h = img.size
rgb = img.convert("RGB")
print(f"截图尺寸: {w}x{h}")

# 打印 9 宫格采样
print("\n=== 9 宫格采样 ===")
for y_pct in [0.1, 0.3, 0.5, 0.7, 0.9]:
    row = []
    for x_pct in [0.1, 0.3, 0.5, 0.7, 0.9]:
        x = int(w * x_pct)
        y = int(h * y_pct)
        r, g, b = rgb.getpixel((x, y))
        row.append(f"({x:4d},{y:3d})={r:3d},{g:3d},{b:3d}")
    print("  " + "  ".join(row))

# 找非纯黑/纯白/纯绿像素
print("\n=== 模型像素扫描（找非背景像素）===")
model_pixels = []
for y in range(0, h, 3):
    for x in range(0, w, 3):
        r, g, b = rgb.getpixel((x, y))
        # 排除纯黑(0,0,0)、纯白(>240,>240,>240)、绿场
        if r < 15 and g < 15 and b < 15:
            continue
        if r > 240 and g > 240 and b > 240:
            continue
        if g > max(r, b) + 20 and g > 60:
            continue  # 场地绿
        # 是模型像素
        model_pixels.append((x, y, r, g, b))

print(f"找到 {len(model_pixels)} 个模型像素")
if model_pixels:
    xs = [p[0] for p in model_pixels]
    ys = [p[1] for p in model_pixels]
    print(f"  X 范围: {min(xs)} - {max(xs)} (宽 {max(xs)-min(xs)})")
    print(f"  Y 范围: {min(ys)} - {max(ys)} (高 {max(ys)-min(ys)})")
    print(f"  X 占比: {(max(xs)-min(xs))/w*100:.1f}%")
    print(f"  Y 占比: {(max(ys)-min(ys))/h*100:.1f}%")
    # 采样一些像素
    print(f"\n前 5 个模型像素:")
    for p in model_pixels[:5]:
        print(f"  ({p[0]:4d},{p[1]:3d}) RGB=({p[2]:3d},{p[3]:3d},{p[4]:3d})")
