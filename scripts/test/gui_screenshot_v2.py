"""GUI 截图测试 - 直接运行 Godot 并截取整个屏幕"""
import subprocess
import time
import os
from PIL import ImageGrab, Image

PROJECT_DIR = r"E:\项目储存\决竞球battle-ball"
GODOT_PATH = r"E:\项目储存\pvz-project\pvz-godot\tools\Godot_v4.6.2-stable_win64.exe"
SCENE_PATH = "res://scenes/test/player_3d_test.tscn"
SCREENSHOT_PATH = os.path.join(PROJECT_DIR, "sim_results", "gui_screenshot_v2.png")

def main():
    # 确保输出目录存在
    os.makedirs(os.path.dirname(SCREENSHOT_PATH), exist_ok=True)

    # 启动 Godot（不使用 --quit-after，让它自然运行）
    print("[Python] 启动 Godot（无 quit-after）...")
    proc = subprocess.Popen(
        [GODOT_PATH, SCENE_PATH],
        cwd=PROJECT_DIR,
        # 不创建新窗口，让它显示在当前桌面
    )

    # 等待场景加载（8秒，足够模型加载和渲染）
    print("[Python] 等待场景加载 8 秒...")
    time.sleep(8)

    # 截取整个屏幕
    print("[Python] 截取整个屏幕...")
    screenshot = ImageGrab.grab()
    screenshot.save(SCREENSHOT_PATH)
    print(f"[Python] 截图保存: {SCREENSHOT_PATH}")
    print(f"[Python] 图片尺寸: {screenshot.size}")

    # 终止 Godot
    print("[Python] 终止 Godot...")
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()

    # 分析截图
    analyze_screenshot(screenshot)

def analyze_screenshot(img):
    """分析截图内容"""
    from collections import Counter

    width, height = img.size
    print(f"[Python] === 截图分析 ===")
    print(f"[Python] 尺寸: {width}x{height}")

    # 转换为 RGB
    rgb_img = img.convert("RGB")

    # 全屏采样分析（每隔 100 像素）
    colors = Counter()
    for y in range(0, height, 100):
        for x in range(0, width, 100):
            r, g, b = rgb_img.getpixel((x, y))
            # 分类颜色
            if g > max(r, b) + 20:  # 绿色为主
                colors['green'] += 1
            elif b > max(r, g) + 20:  # 蓝色为主
                colors['blue'] += 1
            elif r > max(g, b) + 20:  # 红色为主
                colors['red'] += 1
            elif r > 180 and g > 140 and b < 120:  # 皮肤色
                colors['skin'] += 1
            elif r < 50 and g < 50 and b < 50:  # 深色
                colors['dark'] += 1
            elif r > 200 and g > 200 and b > 200:  # 白色/亮色
                colors['white'] += 1
            else:
                colors['other'] += 1

    print(f"[Python] 全屏颜色分布（每100像素采样）:")
    for color, count in colors.most_common(10):
        print(f"[Python]   {color}: {count}")

    # 检查关键区域
    # 屏幕中心（应该是场地）
    cx, cy = width // 2, height // 2
    center_color = rgb_img.getpixel((cx, cy))
    print(f"[Python] 屏幕中心 ({cx},{cy}) 颜色: RGB({center_color[0]}, {center_color[1]}, {center_color[2]})")

    # 左侧区域（球员A位置）
    left_x = width // 4
    left_color = rgb_img.getpixel((left_x, cy))
    print(f"[Python] 左侧区域 ({left_x},{cy}) 颜色: RGB({left_color[0]}, {left_color[1]}, {left_color[2]})")

    # 右侧区域（球员B位置）
    right_x = width * 3 // 4
    right_color = rgb_img.getpixel((right_x, cy))
    print(f"[Python] 右侧区域 ({right_x},{cy}) 颜色: RGB({right_color[0]}, {right_color[1]}, {right_color[2]})")

    # 判断场地颜色
    if center_color[1] > 30:  # 绿色分量足够高
        print("[Python] ✅ 检测到场地绿色")
    else:
        print("[Python] ⚠️ 场地颜色不明显")

    # 判断模型
    skin_count = colors.get('skin', 0)
    if skin_count > 10:
        print(f"[Python] ✅ 检测到皮肤色区域: {skin_count}")
    else:
        print(f"[Python] ⚠️ 皮肤色像素较少: {skin_count}")

if __name__ == "__main__":
    main()