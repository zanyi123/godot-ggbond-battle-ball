#!/usr/bin/env python3
"""网格拓扑修复批处理 — 修混元生成件的黑色斑点/碎面（任务4）

保守三件套：合并重合顶点 → 重算法线 → 删游离元素
不做：补洞（可能填掉设计孔隙）、平滑（观感需人工判断）

用法:
  blender --background --python tools/repair_mesh_topology.py -- 输入.glb|fbx 输出.glb
输出: 修复报告(stdout JSON)
"""
import sys
import json

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SRC, DST = argv[0], argv[1]

import bpy
import bmesh

bpy.ops.wm.read_factory_settings(use_empty=True)

if SRC.lower().endswith(".glb"):
    bpy.ops.import_scene.gltf(filepath=SRC)
elif SRC.lower().endswith(".fbx"):
    bpy.ops.import_scene.fbx(filepath=SRC)
else:
    raise SystemExit("不支持的格式: " + SRC)

report = {"file": SRC, "meshes": []}

def mesh_stats(me):
    bm = bmesh.new()
    bm.from_mesh(me)
    nonmanifold = sum(1 for e in bm.edges if not e.is_manifold)
    n = {"verts": len(bm.verts), "faces": len(bm.faces), "nonmanifold_edges": nonmanifold}
    bm.free()
    return n

for obj in list(bpy.data.objects):
    if obj.type != 'MESH':
        continue
    me = obj.data
    before = mesh_stats(me)

    bm = bmesh.new()
    bm.from_mesh(me)
    # 1. 合并重合顶点(0.001m) — 碎缝主因
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.001)
    # 2. 重算法线朝外 — 黑斑主因
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # 3. 删游离顶点与边
    loose_v = [v for v in bm.verts if not v.link_edges]
    if loose_v:
        bmesh.ops.delete(bm, geom=loose_v, context='VERTS')
    loose_e = [e for e in bm.edges if not e.link_faces]
    if loose_e:
        bmesh.ops.delete(bm, geom=loose_e, context='EDGES')
    bm.to_mesh(me)
    bm.free()
    me.update()

    after = mesh_stats(me)
    report["meshes"].append({"name": obj.name, "before": before, "after": after})

# 4. 导出GLB（整场景）
bpy.ops.export_scene.gltf(filepath=DST, export_format='GLB',
                          export_skins=True, export_yup=True)
report["output"] = DST
print("REPAIR_REPORT:" + json.dumps(report, ensure_ascii=False))
