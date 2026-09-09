#!/usr/bin/env python3
"""
决竞球 3D 模型减面工具
用法: python tools/decimate_model.py <输入模型路径> [目标面数]

支持格式: .glb, .gltf, .fbx, .obj
输出: 同目录下 <原名>_decimated.fbx (默认6万面)
"""

import sys
import bpy
from pathlib import Path

# ========== 参数 ==========
MAX_TRIANGLES = 60000  # 目标三角面数（可通过命令行修改）


def decimate(input_path: str, max_tris: int = MAX_TRIANGLES) -> str:
    """减面并导出 FBX，返回输出路径"""
    input_file = Path(input_path)
    if not input_file.exists():
        print(f"[ERROR] 文件不存在: {input_path}")
        sys.exit(1)

    # 清空场景
    bpy.ops.wm.read_factory_settings(use_empty=True)

    # 导入
    ext = input_file.suffix.lower()
    if ext == '.fbx':
        bpy.ops.import_scene.fbx(filepath=str(input_file))
    elif ext in ('.glb', '.gltf'):
        bpy.ops.import_scene.gltf(filepath=str(input_file))
    elif ext == '.obj':
        bpy.ops.import_scene.obj(filepath=str(input_file))
    else:
        print(f"[ERROR] 不支持的格式: {ext}")
        sys.exit(1)

    # 处理所有网格对象
    mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
    if not mesh_objects:
        print("[ERROR] 场景中没有网格对象")
        sys.exit(1)

    print(f"[INFO] 找到 {len(mesh_objects)} 个网格对象")

    for obj in mesh_objects:
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)

        # 统计当前面数
        depsgraph = bpy.context.evaluated_depsgraph_get()
        eval_obj = obj.evaluated_get(depsgraph)
        mesh = bpy.data.meshes.new_from_object(eval_obj)
        current_tris = len(mesh.polygons)
        bpy.data.meshes.remove(mesh)

        print(f"[INFO] '{obj.name}': 当前 {current_tris} 三角面")

        if current_tris > max_tris:
            ratio = max_tris / current_tris
            ratio = max(0.1, min(1.0, ratio))  # 最低保留10%
            print(f"[INFO] 减面 ratio={ratio:.3f} -> 目标 {int(current_tris * ratio)} 面")

            # 应用减面修改器
            bpy.ops.object.modifier_add(type='DECIMATE')
            modifier = obj.modifiers[-1]
            modifier.ratio = ratio
            modifier.use_collapse_triangulate = True
            bpy.ops.object.modifier_apply(modifier=modifier.name)

            # 验证减面结果
            eval_obj2 = obj.evaluated_get(depsgraph)
            mesh2 = bpy.data.meshes.new_from_object(eval_obj2)
            new_tris = len(mesh2.polygons)
            bpy.data.meshes.remove(mesh2)
            print(f"[OK]   '{obj.name}': 减面后 {new_tris} 三角面")
        else:
            print(f"[SKIP] '{obj.name}': 面数已达标，跳过")

        obj.select_set(False)

    # 导出 FBX
    output_path = str(input_file.parent / f"{input_file.stem}_decimated.fbx")
    print(f"[INFO] 导出到: {output_path}")

    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.fbx(
        filepath=output_path,
        use_selection=True,
        apply_unit_scale=True,
        axis_forward='-Z',
        axis_up='Y',
        embed_textures=True,
        path_mode='COPY',
        bake_space_transform=True,
        use_mesh_modifiers=True,
    )

    print(f"\n[DONE] 减面完成: {output_path}")
    return output_path


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(__doc__)
        print("示例: python tools/decimate_model.py model.glb 60000")
        sys.exit(1)

    input_path = sys.argv[1]
    max_tris = int(sys.argv[2]) if len(sys.argv) > 2 else MAX_TRIANGLES

    decimate(input_path, max_tris)
