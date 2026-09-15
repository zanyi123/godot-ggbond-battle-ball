#!/usr/bin/env python3
"""低头/前倾补偿修复器 — 修正混元3D动画角色头颈骨的恒定前倾偏移

原理：给头/颈骨的动画曲线整体叠加一个恒定旋转偏移（保留原有头部动画），
     而不是替换姿态，修好后导出 GLB 供 Godot 直接使用。

用法（必须由 Blender 命令行调用，勿直接 python 运行）：
  "G:/Blender/blender.exe" --background --python tools/fix_head_tilt.py -- \
      <输入.glb或.fbx> <输出.glb> [--angle -20] [--axis X] [--bones 自动] [--dry-run]

参数：
  --angle   补偿角度（度）。负值=绕轴负方向转。默认 -20
  --axis    俯仰轴 X/Y/Z（骨骼局部轴）。默认 X
  --bones   逗号分隔骨名关键字过滤，默认自动匹配 head/neck（排除 HeadTop 等）
  --dry-run 只诊断不改不导出
"""
import sys
import math
import argparse


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("input")
    p.add_argument("output", nargs="?", default="")
    p.add_argument("--angle", type=float, default=-20.0)
    p.add_argument("--axis", choices=["X", "Y", "Z"], default="X")
    p.add_argument("--bones", default="")
    p.add_argument("--dry-run", action="store_true")
    return p.parse_args(argv)


def clear_scene():
    import bpy
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.armatures, bpy.data.actions,
                  bpy.data.materials, bpy.data.images):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def import_file(path):
    import bpy
    low = path.lower()
    if low.endswith(".glb") or low.endswith(".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif low.endswith(".fbx"):
        bpy.ops.import_scene.fbx(filepath=path)
    else:
        raise SystemExit("不支持的格式: %s（仅 glb/gltf/fbx）" % path)


def find_armature():
    import bpy
    for obj in bpy.data.objects:
        if obj.type == "ARMATURE":
            return obj
    raise SystemExit("未找到骨架（Armature）——文件可能没绑骨")


def pick_bones(arm, keywords):
    """按关键字挑目标骨；无关键字时匹配 head/neck，排除末端占位骨。"""
    exclude = ("top", "end", "tip")
    hits = []
    for bone in arm.pose.bones:
        n = bone.name.lower()
        if keywords:
            if any(k.lower() in n for k in keywords):
                hits.append(bone)
            continue
        if ("head" in n or "neck" in n) and not any(e in n for e in exclude):
            hits.append(bone)
    return hits


def action_fcurves(action):
    """兼容 Blender API：旧版 action.fcurves；4.4+ / 5.1 走 layers>strips>channelbags。"""
    if hasattr(action, "fcurves"):
        return list(action.fcurves)
    fcs = []
    for layer in getattr(action, "layers", []):
        for strip in layer.strips:
            for cb in strip.channelbags:
                fcs.extend(cb.fcurves)
    return fcs


def fcurves_for_bone(action, arm, bone_name):
    prefix = 'pose.bones["%s"]' % bone_name
    return [fc for fc in action_fcurves(action)
            if fc.data_path.startswith(prefix)
            and ("rotation" in fc.data_path)]


def offset_quat(axis, deg):
    from mathutils import Quaternion
    v = {"X": (1, 0, 0), "Y": (0, 1, 0), "Z": (0, 0, 1)}[axis]
    return Quaternion(v, math.radians(deg))


def diagnose(arm, bones):
    import bpy
    print("== 诊断 ==")
    print("骨架: %s | 骨骼总数: %d" % (arm.name, len(arm.pose.bones)))
    print("全部骨名:", [b.name for b in arm.pose.bones])
    for bone in bones:
        rest = bone.rotation_quaternion if bone.rotation_mode == "QUATERNION" else None
        print("目标骨: %s (mode=%s) rest=%s" % (
            bone.name, bone.rotation_mode,
            tuple(round(v, 3) for v in rest) if rest else bone.rotation_euler))
        acts = [a for a in bpy.data.actions if action_fcurves(a)]
        for a in acts:
            fcs = fcurves_for_bone(a, arm, bone.name)
            if fcs:
                for fc in fcs:
                    vals = [kp.co[1] for kp in fc.keyframe_points]
                    print("  动画[%s] %s: %.3f ~ %.3f (%d关键帧)" % (
                        a.name, fc.data_path.split(".")[-1],
                        min(vals), max(vals), len(vals)))
            else:
                print("  动画[%s]: 无 %s 旋转曲线" % (a.name, bone.name))


def apply_offset(arm, bones, axis, deg):
    """把恒定旋转叠加到目标骨所有动画关键帧上（保形补偿）。"""
    import bpy
    from mathutils import Quaternion, Euler
    q_off = offset_quat(axis, deg)
    touched = 0
    for action in bpy.data.actions:
        for bone in bones:
            rot_fcs = fcurves_for_bone(action, arm, bone.name)
            # 四元数：按同帧聚合四通道，逐帧合成后回写
            qchans = {c.array_index: c for c in rot_fcs
                      if "quaternion" in c.data_path}
            if set(qchans) == {0, 1, 2, 3}:
                frames = sorted({round(kp.co[0], 4)
                                 for kp in qchans[0].keyframe_points})
                for f in frames:
                    q = Quaternion((qchans[0].evaluate(f),
                                    qchans[1].evaluate(f),
                                    qchans[2].evaluate(f),
                                    qchans[3].evaluate(f)))
                    q2 = q_off @ q
                    for ai, val in zip((0, 1, 2, 3),
                                       (q2.w, q2.x, q2.y, q2.z)):
                        qchans[ai].keyframe_points.insert(
                            frame=f, value=val, options={"REPLACE"})
                for c in qchans.values():
                    c.update()
                touched += 1
            # 欧拉：逐帧转四元数合成再转回
            echans = {c.array_index: c for c in rot_fcs
                      if "rotation_euler" in c.data_path}
            if set(echans) == {0, 1, 2}:
                frames = sorted({round(kp.co[0], 4)
                                 for kp in echans[0].keyframe_points})
                for f in frames:
                    e = Euler((echans[0].evaluate(f),
                               echans[1].evaluate(f),
                               echans[2].evaluate(f)))
                    q2 = q_off @ e.to_quaternion()
                    e2 = q2.to_euler()
                    for ai, val in zip((0, 1, 2), (e2.x, e2.y, e2.z)):
                        echans[ai].keyframe_points.insert(
                            frame=f, value=val, options={"REPLACE"})
                for c in echans.values():
                    c.update()
                touched += 1
    return touched


def main():
    args = parse_args()
    import bpy
    clear_scene()
    import_file(args.input)
    arm = find_armature()
    keywords = [k for k in args.bones.split(",") if k.strip()]
    bones = pick_bones(arm, keywords)
    if not bones:
        raise SystemExit("未匹配到头/颈骨，请用 --bones 指定关键字")
    diagnose(arm, bones)
    if args.dry_run:
        print("== dry-run 结束，未修改 ==")
        return
    n = apply_offset(arm, bones, args.axis, args.angle)
    print("== 已给 %d 条骨动画曲线叠加 %.1f° %s 轴补偿 ==" % (n, args.angle, args.axis))
    out = args.output or args.input.rsplit(".", 1)[0] + "_fixed.glb"
    bpy.ops.export_scene.gltf(
        filepath=out, export_format="GLB",
        export_animations=True, export_skins=True,
        export_yup=True)
    print("== 已导出: %s ==" % out)


if __name__ == "__main__":
    main()
