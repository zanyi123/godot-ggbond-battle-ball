"""GUI 截图测试 - 用 Python 调用 Godot 并截图"""
import subprocess
import time
import os
from PIL import ImageGrab

PROJECT_DIR = r"E:\项目储存\决竞球battle-ball"
GODOT_PATH = r"E:\项目储存\pvz-project\pvz-godot\tools\Godot_v4.6.2-stable_win64.exe"
SCENE_PATH = "res://scenes/test/player_3d_test.tscn"
SCREENSHOT_PATH = os.path.join(PROJECT_DIR, "sim_results", "gui_screenshot.png")

def main():
    # 确保输出目录存在
    os.makedirs(os.path.dirname(SCREENSHOT_PATH), exist_ok=True)

    # 启动 Godot
    print("[Python] 启动 Godot...")
    proc = subprocess.Popen(
        [GODOT_PATH, SCENE_PATH],
        cwd=PROJECT_DIR,
        creationflags=subprocess.CREATE_NEW_CONSOLE
    )

    # 等待场景加载（5秒）
    print("[Python] 等待场景加载...")
    time.sleep(5)

    # 截图
    print("[Python] 截图...")
    screenshot = ImageGrab.grab()
    screenshot.save(SCREENSHOT_PATH)
    print(f"[Python] 截图保存: {SCREENSHOT_PATH}")
    print(f"[Python] 图片尺寸: {screenshot.size}")

    # 终止 Godot
    print("[Python] 终止 Godot...")
    proc.terminate()
    proc.wait(timeout=5)

    # 分析截图
    analyze_screenshot(screenshot)

def analyze_screenshot(img):
    """分析截图内容"""
    from PIL import Image
    import collections

    width, height = img.size
    print(f"[Python] === 截图分析 ===")
    print(f"[Python] 尺寸: {width}x{height}")

    # 转换为 RGB
    rgb_img = img.convert("RGB")

    # 采样分析
    colors = collections.Counter()
    sample_region = (width//2 - 200, height//2 - 200, width//2 + 200, height//2 + 200)
    for y in range(sample_region[1], sample_region[3], 10):
        for x in range(sample_region[0], sample_region[2], 10):
            r, g, b = rgb_img.getpixel((x, y))
            # 简化颜色分类
            if g > 150 and r < 100:  # 绿色（场地）
                colors['green'] += 1
            elif b > 150 and r < 100:  # 蓝色（球员A）
                colors['blue'] += 1
            elif r > 150 and g < 100 and b < 100:  # 红色（球员B）
                colors['red'] += 1
            elif r > 200 and g > 150 and b < 100:  # 皮肤色（模型）
                colors['skin'] += 1
            elif r < 50 and g < 50 and b < 50:  # 黑色/深色
                colors['dark'] += 1

    print(f"[Python] 采样区域颜色分布:")
    for color, count in colors.most_common():
        print(f"[Python]   {color}: {count}")

    # 判断模型是否显示
    skin_count = colors.get('skin', 0)
    if skin_count > 100:
        print(f"[Python] ✅ 检测到模型皮肤区域: {skin_count} 像素")
    elif skin_count > 10:
        print(f"[Python] ⚠️ 检测到少量皮肤区域: {skin_count} 像素，模型可能太小")
    else:
        print(f"[Python] ❌ 未检测到模型皮肤区域，模型可能未显示或颜色不在采样范围")

    # 判断场地
    green_count = colors.get('green', 0)
    if green_count > 100:
        print(f"[Python] ✅ 检测到场地: {green_count} 像素")
    else:
        print(f"[Python] ⚠️ 场地像素较少: {green_count}")

if __name__ == "__main__":
    main()