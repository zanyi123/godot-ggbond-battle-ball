#!/usr/bin/env python3
"""建模素材库/3D模型素材 重分类迁移工具（2026-09-15 结构改造）

目标结构：
  player1~8/   球员模型+贴图（扁平，动作已独立）
  actions/     共享动作库（骨名同构，全体球员共用）
  ball/ field/ 球与场地（模型+贴图+动作）
  归档/        旧日期批次与重复下载封存

用法:
  python tools/reorganize_3d_lib.py --dry   # 预演，只打印清单
  python tools/reorganize_3d_lib.py         # 执行
"""
import os
import re
import sys
import shutil

BASE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "建模素材库", "3D模型素材")
DRY = "--dry" in sys.argv

ACTIONS_CANON = {  # player1动作 里的通用 Mixamo 动作 → actions/ 的规范名
    "Idle.fbx": "idle.fbx", "Jog Forward.fbx": "jog.fbx",
    "Goalie Throw.fbx": "throw.fbx", "Goalkeeper Catch.fbx": "catch.fbx",
    "Baseball Pitching.fbx": "pitch.fbx", "Receiver Catch.fbx": "receive.fbx",
    "Standing Block Idle.fbx": "block_idle.fbx",
}

moves = []   # (src, dst)


def plan(src, dst):
    moves.append((os.path.normpath(src), os.path.normpath(dst)))


def dest_for(rel, fname):
    """返回目标相对路径；None=原地不动；'ARCHIVE'=整文件夹归档判断用"""
    low = fname.lower()
    m = re.match(r"player(\d)[-_.]", low)
    if m:  # 球员模型/贴图/专属动作（player2-v2-base.glb / playerN_low_walk.fbx / hy_luodi… 不匹配）
        if fname in ACTIONS_CANON:  # player1动作 里的通用动作走共享库
            return os.path.join("actions", ACTIONS_CANON[fname])
        if low.startswith("hy_"):  # 混元动作专属
            return None
        return os.path.join("player%s" % m.group(1), fname)
    if low in ("battleball.glb", "battleball.fbx") or low.startswith("battleball_texture"):
        return os.path.join("ball", fname)
    if low.startswith("battle_field"):
        return os.path.join("field", fname)
    return None


def main():
    tops = [d for d in os.listdir(BASE)
            if os.path.isdir(os.path.join(BASE, d)) and not d.startswith(".")]
    tops.sort()

    # 1. 根目录散文件
    for fname in os.listdir(BASE):
        p = os.path.join(BASE, fname)
        if os.path.isfile(p) and not fname.endswith(".import"):
            d = dest_for("", fname)
            if d:
                plan(p, os.path.join(BASE, d))

    # 2. 逐文件夹处理
    for folder in tops:
        fdir = os.path.join(BASE, folder)
        files = [f for f in os.listdir(fdir)
                 if os.path.isfile(os.path.join(fdir, f)) and not f.endswith(".import")]

        if folder == "player1动作":  # 通用动作 → actions/；其余（hy_落地动作+贴图）→ player1/
            for f in files:
                if f in ACTIONS_CANON:
                    plan(os.path.join(fdir, f), os.path.join(BASE, "actions", ACTIONS_CANON[f]))
                else:
                    plan(os.path.join(fdir, f), os.path.join(BASE, "player1", f))
            continue
        if re.fullmatch(r"player\d+动作", folder):  # 其他球员动作文件夹 = 重复下载 → 归档
            plan(fdir, os.path.join(BASE, "归档", folder))
            continue
        if folder.endswith(".fbm") or folder == "player1_materials":
            plan(fdir, os.path.join(BASE, "归档", folder))
            continue
        if folder in ("ball动作", "battleball动作", "battleball.glb动作"):
            for f in files:
                plan(os.path.join(fdir, f), os.path.join(BASE, "ball", "动作", f))
            continue

        # 日期文件夹：抽走球员/球/场地产权文件，剩余整folder归档
        extracted_any = False
        for f in files:
            d = dest_for(folder, f)
            if d:
                extracted_any = True
                plan(os.path.join(fdir, f), os.path.join(BASE, d))
        plan(fdir, os.path.join(BASE, "归档", folder) if not extracted_any
             else os.path.join(BASE, "归档", folder))  # 整folder也进归档（抽出后剩什么归什么）

    # 3. 打印 + 执行
    print("计划迁移 %d 项:" % len(moves))
    conflict = 0
    for src, dst in moves:
        tag = ""
        if os.path.exists(dst) and not os.path.isdir(src):
            tag = "  [合并冲突->跳过]"
            conflict += 1
        print("  %-70s -> %s%s" % (os.path.relpath(src, BASE), os.path.relpath(dst, BASE), tag))
    if DRY:
        print("== 预演结束 ==")
        return
    n = 0
    for src, dst in moves:
        if os.path.exists(dst) and not os.path.isdir(src):
            continue  # 同名已存在，保留先到者
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        for suffix in ("", ".import"):
            s, d = src + suffix, dst + suffix
            if os.path.exists(s):
                shutil.move(s, d)
        n += 1
    # 清空目录删除
    for root, dirs, files in os.walk(BASE, topdown=False):
        if root != BASE and not os.listdir(root):
            os.rmdir(root)
    print("== 已迁移 %d 项（冲突跳过 %d）==" % (n, conflict))


if __name__ == "__main__":
    main()
