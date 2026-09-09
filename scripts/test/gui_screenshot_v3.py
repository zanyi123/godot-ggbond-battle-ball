"""GUI 截图测试 v3 - 使用 Win32 API 抓取 Godot 窗口"""
import subprocess
import time
import os
import sys
from PIL import Image

PROJECT_DIR = r"E:\项目储存\决竞球battle-ball"
GODOT_PATH = r"E:\项目储存\pvz-project\pvz-godot\tools\Godot_v4.6.2-stable_win64.exe"
SCENE_PATH = "res://scenes/test/player_3d_test.tscn"
SCREENSHOT_PATH = os.path.join(PROJECT_DIR, "sim_results", "gui_screenshot_v3.png")


def get_godot_window():
    """通过 Win32 API 找到 Godot 窗口"""
    import ctypes
    from ctypes import wintypes

    user32 = ctypes.windll.user32
    EnumWindows = user32.EnumWindows
    GetWindowTextW = user32.GetWindowTextW
    GetWindowRect = user32.GetWindowRect
    IsWindowVisible = user32.IsWindowVisible

    GWL_EXSTYLE = -20
    WS_EX_TOOLWINDOW = 0x00000080
    WS_EX_APPWINDOW = 0x00040000

    result = []

    @ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_int, ctypes.c_int)
    def enum_proc(hwnd, lParam):
        if not IsWindowVisible(hwnd):
            return True
        length = user32.GetWindowTextLengthW(hwnd)
        if length == 0:
            return True
        buff = ctypes.create_unicode_buffer(length + 1)
        GetWindowTextW(hwnd, buff, length + 1)
        title = buff.value
        if "Godot" in title or "Battle" in title or "Player3D" in title:
            rect = wintypes.RECT()
            GetWindowRect(hwnd, ctypes.byref(rect))
            result.append((hwnd, title, rect))
        return True

    EnumWindows(enum_proc, 0)
    return result


def main():
    os.makedirs(os.path.dirname(SCREENSHOT_PATH), exist_ok=True)

    print("[Python] 启动 Godot...")
    proc = subprocess.Popen(
        [GODOT_PATH, "--resolution", "1440x900", "--position", "100,100", SCENE_PATH],
        cwd=PROJECT_DIR,
    )

    # 等待 Godot 窗口出现
    print("[Python] 等待 Godot 窗口出现...")
    all_wins = []
    for i in range(20):
        time.sleep(0.5)
        wins = get_godot_window()
        if wins:
            all_wins = wins
            print(f"[Python] 第{i}次: 找到 {len(wins)} 个 Godot 窗口")
            for w in wins:
                rect = w[2]
                ww = rect.right - rect.left
                wh = rect.bottom - rect.top
                print(f"  '{w[1]}' hwnd={w[0]} pos=({rect.left},{rect.top}) size={ww}x{wh}")
            # 找最大的（游戏窗口）
            biggest = max(wins, key=lambda w: (w[2].right - w[2].left) * (w[2].bottom - w[2].top))
            r = biggest[2]
            rw = r.right - r.left
            rh = r.bottom - r.top
            if rw > 200 and rh > 200:
                hwnd_target = biggest
                break

    if hwnd_target is None:
        print("[Python] ❌ 找不到 Godot 游戏窗口")
        proc.terminate()
        return

    print(f"[Python] 选用: '{hwnd_target[1]}' size={rw}x{rh}")
    # 再等几秒让场景完全加载
    print("[Python] 等待场景加载 5 秒...")
    time.sleep(5)

    # 用 ImageGrab 直接抓取屏幕区域（GPU 渲染内容也可捕获）
    print("[Python] 用 ImageGrab 抓取 Godot 窗口屏幕区域...")
    import ctypes
    from ctypes import wintypes
    from PIL import ImageGrab

    hwnd = hwnd_target[0]
    rect = hwnd_target[2]
    w = rect.right - rect.left
    h = rect.bottom - rect.top
    print(f"[Python] 窗口尺寸: {w}x{h} 位置: ({rect.left},{rect.top})")

    user32 = ctypes.windll.user32
    # 把窗口置前
    user32.SetForegroundWindow(hwnd)
    time.sleep(1)

    # 用 ImageGrab 抓取窗口区域
    img = ImageGrab.grab(bbox=(rect.left, rect.top, rect.right, rect.bottom), all_screens=True)
    img = img.convert("RGB")
    img.save(SCREENSHOT_PATH)
    print(f"[Python] ✅ 截图保存: {SCREENSHOT_PATH}")

    # 终止 Godot
    print("[Python] 终止 Godot...")
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()

    # 分析
    print(f"[Python] 截图尺寸: {img.size}")
    analyze(img)


def analyze(img):
    """分析截图 - 找出模型像素位置"""
    from collections import Counter
    w, h = img.size
    rgb = img.convert("RGB")

    # 找出非绿色的像素（即模型像素）
    print(f"[Python] 截图尺寸: {w}x{h}")
    # 扫描每行
    print("[Python] 模型 Y 范围（从上到下扫描）:")
    model_top = None
    model_bottom = None
    for y in range(0, h, 5):
        has_model = False
        for x in range(0, w, 5):
            r, g, b = rgb.getpixel((x, y))
            # 非绿色（场地）且非深色（背景）
            if not (g > max(r, b) - 10) and not (r < 30 and g < 30 and b < 30):
                if abs(r - g) > 30 or abs(g - b) > 30:  # 非灰色
                    has_model = True
                    break
        if has_model:
            if model_top is None:
                model_top = y
            model_bottom = y
    if model_top is not None:
        print(f"  模型 Y 范围: {model_top} - {model_bottom} (高度 {model_bottom - model_top} 像素)")
    else:
        print("  ❌ 没找到模型")

    # 找出中间行的模型 X 范围
    mid_y = h // 2
    print(f"[Python] 第 {mid_y} 行模型 X 范围:")
    model_xs = []
    for x in range(w):
        r, g, b = rgb.getpixel((x, mid_y))
        if abs(r - g) > 30 or abs(g - b) > 30:
            model_xs.append(x)
    if model_xs:
        print(f"  X 范围: {model_xs[0]} - {model_xs[-1]} (宽度 {model_xs[-1] - model_xs[0]} 像素)")
    else:
        print("  ❌ 这行没找到模型")

    # 颜色直方图
    colors = Counter()
    for y in range(0, h, 30):
        for x in range(0, w, 30):
            r, g, b = rgb.getpixel((x, y))
            if g > max(r, b) + 20:
                colors['field_green'] += 1
            elif r < 30 and g < 30 and b < 30:
                colors['dark'] += 1
            elif r > 200 and g > 200 and b > 200:
                colors['white'] += 1
            else:
                colors[f'other_{r//50}_{g//50}_{b//50}'] += 1
    print("[Python] 颜色分布:")
    for c, n in colors.most_common(8):
        print(f"  {c}: {n}")


if __name__ == "__main__":
    main()
