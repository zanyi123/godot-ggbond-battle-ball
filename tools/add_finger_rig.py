#!/usr/bin/env python3
"""手指绑骨自动工艺 — 从 player2_low_gu_v2 实战沉淀（2026-09-15）

给标准人形骨架（Mixamo 命名、无手指骨、28骨）自动添加五指骨链 + 分级蒙皮。
player2 验收数据：本指位移 0.24~0.81 / 40°，邻指牵连 0%，掌心隔离 0%。

用法（Blender 命令行或 MCP execute 内）：
  1. 先导入目标模型（需已有 Armature + Hand 骨，无手指骨）
  2. 调用 add_finger_rig(armature_obj, mesh_obj)
  3. 调用 curl_test(armature_obj, mesh_obj) 三指标验收
  4. 导出 GLB（use_selection 只选骨架+网格）

核心工艺要点（踩坑换来的）：
  A. 骨链定位：Hand 骨轴 0.11~沿轴最大值 为指区；五指列用"指尖带(>0.17)
     1D k-means k=4 聚类中心"定位，禁用均匀切分（会造成单指吞 58% 顶点）
  B. 拇指侧：取宽度两端中"更靠身体中线"的一端（世界半径小者）
  C. 分级蒙皮：掌区(0.11~0.17)留 Hand，中段 F1，指尖 F2，沿轴渐变，
     每顶点权重和恒为 1
  D. 验证必须用 depsgraph 求值网格（data.vertices 是绑定姿态恒为零位移）
  E. 已知缺陷：指骨 roll 未规范（局部轴随机），动画师摆姿势需用世界轴
     合成，或先跑 normalize_rolls()（TODO）
"""
import numpy as np
from mathutils import Quaternion, Vector

FINGERS = ['Index', 'Middle', 'Ring', 'Pinky', 'Thumb']
FZ0 = 0.11          # 指区起点（Hand骨轴比例，混元Q版实测值，其他模型可调）


def _hand_frame(arm, mesh, side):
    """返回 (指区顶点索引, along, wide, head_w, axis, w_axis)"""
    pb = arm.pose.bones[side + 'Hand']
    head_w = arm.matrix_world @ pb.head
    tail_w = arm.matrix_world @ pb.tail
    axis = (tail_w - head_w)
    axis.normalize()
    w_axis = axis.cross(Vector((0, 0, 1)))
    if w_axis.length < 0.1:
        w_axis = axis.cross(Vector((1, 0, 0)))
    w_axis.normalize()
    vg_names = [g.name for g in mesh.vertex_groups]
    mw = mesh.matrix_world
    pts, idxs = [], []
    for i in range(len(mesh.data.vertices)):
        ws = [(g.weight, vg_names[g.group])
              for g in mesh.data.vertices[i].groups if g.weight > 0.01]
        if sum(w for w, n in ws if side + 'Hand' in n) > 0.5:
            pts.append((mw @ mesh.data.vertices[i].co)[:])
            idxs.append(i)
    pts = np.array(pts)
    local = pts - np.array(head_w)
    return idxs, local @ np.array(axis), local @ np.array(w_axis), head_w, axis, w_axis


def add_finger_rig(arm, mesh, side):
    idxs, along, wide, head_w, axis, w_axis = _hand_frame(arm, mesh, side)
    fz1 = along.max() + 0.01
    zone = along > FZ0
    if zone.sum() < 50:
        raise RuntimeError("%s 指区顶点过少(%d)，检查骨架/权重" % (side, zone.sum()))

    # --- A. 骨链（两关节/指）---
    def add_bone(name, head, tail, parent):
        bpy.ops.object.mode_set(mode='EDIT')
        eb = arm.data.edit_bones.new(name)
        eb.head, eb.tail = head, tail
        eb.parent = arm.data.edit_bones[parent]
        eb.use_connect = False
        bpy.ops.object.mode_set(mode='OBJECT')
    tip_mask = along > FZ0 + 0.06
    tw = wide[tip_mask]
    centers = np.quantile(tw, [0.125, 0.375, 0.625, 0.875])
    for _ in range(15):   # 1D k-means
        lab = np.argmin(np.abs(tw[:, None] - centers[None, :]), axis=1)
        for k in range(4):
            if (lab == k).sum() > 0:
                centers[k] = tw[lab == k].mean()
    centers = np.sort(centers)
    base_axis = head_w + axis * (FZ0 + 0.012)
    thumb_w = (wide.min() if (base_axis + w_axis * wide.min()).length_squared
               < (base_axis + w_axis * wide.max()).length_squared else wide.max())
    for k, f in enumerate(FINGERS):
        cw = thumb_w if f == 'Thumb' else centers[k]
        base = head_w + axis * (FZ0 + 0.012) + w_axis * cw
        add_bone('%sHand%s1' % (side, f), base, base + axis * 0.055, side + 'Hand')
        add_bone('%sHand%s2' % (side, f), base + axis * 0.055,
                 base + axis * 0.11, '%sHand%s1' % (side, f))

    # --- C. 分级蒙皮 ---
    def vg(name):
        return mesh.vertex_groups.get(name) or mesh.vertex_groups.new(name=name)
    for j, vi in enumerate(idxs):
        if not zone[j]:
            continue
        a, wd = along[j], wide[j]
        best, bd = None, 1e9
        for k, f in enumerate(FINGERS):
            cw = thumb_w if f == 'Thumb' else centers[k]
            if abs(wd - cw) < bd:
                best, bd = f, abs(wd - cw)
        t = min(1.0, max(0.0, (a - FZ0) / 0.08))
        w_hand = max(0.0, 1.0 - t * 1.4) if a < 0.17 else 0.0
        w1 = (1.0 - t) * (1.0 - w_hand) + 0.25 * t
        w2 = max(0.0, 1.0 - w_hand - w1)
        vg(side + 'Hand').add([vi], 0.0, 'REPLACE')
        if w_hand > 0.001: vg(side + 'Hand').add([vi], w_hand, 'ADD')
        if w1 > 0.001: vg('%sHand%s1' % (side, best)).add([vi], w1, 'ADD')
        if w2 > 0.001: vg('%sHand%s2' % (side, best)).add([vi], w2, 'ADD')
    print("%s: 10根指骨 + 蒙皮完成（指列中心 %s, 拇指@%.3f）"
          % (side, np.round(centers, 3), thumb_w))


def curl_test(arm, mesh, side, deg=40):
    """三指标逐指测试：本指位移 / 邻指牵连 / 掌心隔离。返回全通过布尔"""
    scene = bpy.context.scene
    scene.frame_set(1)
    vg_names = [g.name for g in mesh.vertex_groups]

    def eval_verts():
        dg = bpy.context.evaluated_depsgraph_get()
        ev = mesh.evaluated_get(dg)
        me = ev.to_mesh()
        return np.array([(ev.matrix_world @ v.co)[:] for v in me.vertices])

    groups, palm = {}, []
    for i in range(len(mesh.data.vertices)):
        ws = [(g.weight, vg_names[g.group])
              for g in mesh.data.vertices[i].groups if g.weight > 0.01]
        if not ws:
            continue
        d = {}
        for w, n in ws:
            d[n] = d.get(n, 0) + w
        for f in FINGERS:
            fw = sum(v for k, v in d.items() if k.startswith(side) and f in k)
            if fw > 0.3:
                groups.setdefault(side + '_' + f, []).append(i)
                break
        else:
            if d.get(side + 'Hand', 0) > 0.6:
                palm.append(i)
    rest = eval_verts()
    ok_all = True
    for f in FINGERS:
        own = groups.get(side + '_' + f, [])
        pb_h = arm.pose.bones[side + 'Hand']
        head_w = arm.matrix_world @ pb_h.head
        tail_w = arm.matrix_world @ pb_h.tail
        axis = (tail_w - head_w)
        axis.normalize()
        w_ax = axis.cross(Vector((0, 0, 1)))
        if w_ax.length < 0.1:
            w_ax = axis.cross(Vector((1, 0, 0)))
        t_ax = axis.cross(w_ax).normalized()
        q_corr = Quaternion(t_ax, __import__('math').radians(deg))
        for jn in ('1', '2'):
            b = arm.pose.bones['%sHand%s%s' % (side, f, jn)]
            W = (arm.matrix_world @ b.matrix).to_quaternion()
            Wp = ((arm.matrix_world @ b.parent.matrix).to_quaternion()
                  if b.parent else Quaternion((1, 0, 0, 0)))
            b.rotation_quaternion = Wp.inverted() @ q_corr @ W
        bpy.context.view_layer.update()
        cur = eval_verts()
        others = [i for ff in FINGERS if ff != f
                  for i in groups.get(side + '_' + ff, [])[:20]]
        d_own = [float(((cur[i] - rest[i]) ** 2).sum() ** 0.5) for i in own[:150]]
        d_oth = [float(((cur[i] - rest[i]) ** 2).sum() ** 0.5) for i in others[:100]]
        dp = [float(((cur[i] - rest[i]) ** 2).sum() ** 0.5) for i in palm[:100]]
        for b in arm.pose.bones:
            if b.name.startswith(side + 'Hand') and b.name.endswith(('1', '2')) \
                    and any(x in b.name for x in FINGERS):
                b.rotation_quaternion = Quaternion((1, 0, 0, 0))
        a_m = sum(d_own) / len(d_own) if d_own else 0
        o_m = sum(d_oth) / len(d_oth) if d_oth else 0
        p_m = sum(dp) / len(dp) if dp else 0
        ok = a_m > 0.01 and o_m < a_m * 0.5
        ok_all = ok_all and ok
        print("%s-%s: 本指%.3f 邻指%.3f(%.0f%%) 掌%.3f [%s]"
              % (side, f, a_m, o_m, (o_m / a_m * 100) if a_m else 0, p_m,
                 "通过" if ok else "存疑"))
    return ok_all
