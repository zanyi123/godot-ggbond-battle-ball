import bpy, json, math

argv = sys_argv = []
if "--" in __import__('sys').argv:
    argv = __import__('sys').argv[__import__('sys').argv.index("--")+1:]
SRC = argv[0]

bpy.ops.wm.read_factory_settings(use_empty=True)
if SRC.lower().endswith(".fbx"):
    bpy.ops.import_scene.fbx(filepath=SRC)
else:
    bpy.ops.import_scene.gltf(filepath=SRC)

report = {"file": SRC, "arms": []}
for o in bpy.data.objects:
    if o.type == 'ARMATURE':
        bones = []
        for b in o.data.bones:
            L = (b.tail_local - b.head_local).length
            bones.append([b.name, round(L, 4)])
        bones.sort(key=lambda x: -x[1])
        report["arms"].append({"arm": o.name, "bone_count": len(bones), "longest": bones[:8], "scale": [round(v,4) for v in o.scale]})
        # 蒙皮网格显示 bbox（求值）
        for c in o.children:
            if c.type == 'MESH':
                vs = [c.matrix_world @ v.co for v in c.data.vertices]
                if vs:
                    xs=[v.x for v in vs]; ys=[v.y for v in vs]; zs=[v.z for v in vs]
                    report.setdefault("mesh_bbox", {})
                    report["mesh_bbox"][c.name] = {"x":[round(min(xs),3),round(max(xs),3)],
                        "y":[round(min(ys),3),round(max(ys),3)],"z":[round(min(zs),3),round(max(zs),3)],
                        "verts": len(c.data.vertices)}
print("DIAG:" + json.dumps(report, ensure_ascii=False))
