"""
素材导入处理工具 - 标准化流程
将建模素材库的大图处理成游戏可用的图标

使用方法:
    python tools/import_assets.py

经验教训:
1. 直接缩放，不要搞透明处理（边缘抗锯齿像素会产生白点）
2. 目标尺寸要和UI显示尺寸一致（如80x80）
3. 使用 LANCZOS 算法保证缩放质量
4. 处理后删除旧的 .import 文件，让Godot重新导入
"""

import os
import sys
from PIL import Image

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS_ROOT = os.path.join(PROJECT_ROOT, "建模素材库", "2D图片素材", "道具")
ICONS_ROOT = os.path.join(PROJECT_ROOT, "assets", "icons", "items")


def process_image(src_path, dst_path, size=(80, 80)):
    if not os.path.exists(src_path):
        print(f"  [跳过] 源文件不存在: {src_path}")
        return False
    
    img = Image.open(src_path).convert('RGBA')
    img = img.resize(size, Image.LANCZOS)
    
    os.makedirs(os.path.dirname(dst_path), exist_ok=True)
    img.save(dst_path)
    
    import_file = dst_path + '.import'
    if os.path.exists(import_file):
        os.remove(import_file)
    
    print(f"  [OK] {os.path.basename(src_path)} -> {os.path.basename(dst_path)} ({size[0]}x{size[1]})")
    return True


def import_equipment():
    print("\n=== 导入装备图标 ===")
    equip_dir = os.path.join(ASSETS_ROOT, "装备")
    dst_dir = os.path.join(ICONS_ROOT, "equipment")
    
    mappings = [
        ("赛博手套-普通.png", "glove_common.png"),
        ("赛博手套-优秀.png", "glove_good.png"),
        ("赛博手套-稀有.png", "glove_rare.png"),
        ("赛博手套-史诗.png", "glove_epic.png"),
        ("赛博手套-传说.png", "glove_legendary.png"),
        ("赛博球衣-普通.png", "jersey_common.png"),
        ("赛博球衣-优秀.png", "jersey_good.png"),
        ("赛博球衣-稀有.png", "jersey_rare.png"),
        ("赛博球衣-史诗.png", "jersey_epic.png"),
        ("赛博球衣-传说.png", "jersey_legendary.png"),
        ("赛博球鞋-普通.png", "shoes_common.png"),
        ("赛博球鞋-优秀.png", "shoes_good.png"),
        ("赛博球鞋-稀有.png", "shoes_rare.png"),
        ("赛博球鞋-史诗.png", "shoes_epic.png"),
        ("赛博球鞋-传说.png", "shoes_legendary.png"),
    ]
    
    success = 0
    for src_name, dst_name in mappings:
        src = os.path.join(equip_dir, src_name)
        dst = os.path.join(dst_dir, dst_name)
        if process_image(src, dst):
            success += 1
    
    print(f"装备: {success}/{len(mappings)} 成功")
    return success


def import_food():
    print("\n=== 导入食物图标 ===")
    food_dir = os.path.join(ASSETS_ROOT, "食物")
    dst_dir = os.path.join(ICONS_ROOT, "food")
    
    mappings = [
        ("超级棒棒糖-普通.png", "food_common.png"),
        ("超级棒棒糖-优秀.png", "food_good.png"),
        ("超级棒棒糖-稀有.png", "food_rare.png"),
        ("超级棒棒糖-史诗.png", "food_epic.png"),
        ("超级棒棒糖-传说.png", "food_legendary.png"),
    ]
    
    success = 0
    for src_name, dst_name in mappings:
        src = os.path.join(food_dir, src_name)
        dst = os.path.join(dst_dir, dst_name)
        if process_image(src, dst):
            success += 1
    
    print(f"食物: {success}/{len(mappings)} 成功")
    return success


def main():
    print("素材导入工具 - 决竞球项目")
    print(f"素材库: {ASSETS_ROOT}")
    print(f"目标目录: {ICONS_ROOT}")
    
    eq = import_equipment()
    fd = import_food()
    
    print(f"\n=== 总计: {eq + fd} 个图标导入成功 ===")
    print("注意: 请重启Godot编辑器以重新导入图片")


if __name__ == "__main__":
    main()
