#!/usr/bin/env python3
"""
决竞球 3D 模型批量减面工具
批量处理 player1-8_base.glb 高面模型，输出统一命名的低面模型

用法: python tools/batch_decimate.py [目标面数]
默认目标: 60000 三角面

输入: 建模素材库/3D模型素材/playerX_base.glb (混元高模)
输出: 建模素材库/3D模型素材/playerX_low.fbx (低模)
"""

import sys
import bpy
from pathlib import Path

# ========== 配置 ==========
PROJECT_ROOT = Path(__file__).parent.parent.resolve()
MODEL_DIR = PROJECT_ROOT / "建模素材库" / "3D模型素材"
MAX_TRIANGLES = 60000  # 目标三角面数


def decimate_model(input_path: Path, output_path: Path, max_tris: int) -> bool:
    """减面单个模型，返回是否成功"""
    model_name = input_path.stem  # e.g. "player1_base"
    
    # 清空场景
    bpy.ops.wm.read_factory_settings(use_empty=True)
    
    # 导入 GLB
    bpy.ops.import_scene.gltf(filepath=str(input_path))
    
    # 统计网格
    mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
    if not mesh_objects:
        print(f"  [SKIP] {model_name}: 无网格对象")
        return False
    
    total_current = 0
    need_decimate = False
    
    # 第一遍：统计面数
    for obj in mesh_objects:
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        depsgraph = bpy.context.evaluated_depsgraph_get()
        eval_obj = obj.evaluated_get(depsgraph)
        mesh = bpy.data.meshes.new_from_object(eval_obj)
        tris = len(mesh.polygons)
        bpy.data.meshes.remove(mesh)
        total_current += tris
        if tris > max_tris:
            need_decimate = True
        obj.select_set(False)
    
    print(f"  {model_name}: 当前总面数 = {total_current}")
    
    if not need_decimate:
        print(f"    [OK] 面数已达标，直接导出")
    else:
        # 第二遍：执行减面
        for obj in mesh_objects:
            bpy.context.view_layer.objects.active = obj
            obj.select_set(True)
            depsgraph = bpy.context.evaluated_depsgraph_get()
            eval_obj = obj.evaluated_get(depsgraph)
            mesh = bpy.data.meshes.new_from_object(eval_obj)
            current_tris = len(mesh.polygons)
            bpy.data.meshes.remove(mesh)
            
            if current_tris > max_tris:
                ratio = max_tris / current_tris
                ratio = max(0.1, min(1.0, ratio))
                print(f"    减面 '{obj.name}': {current_tris} -> {int(current_tris * ratio)} (ratio={ratio:.3f})")
                bpy.ops.object.modifier_add(type='DECIMATE')
                modifier = obj.modifiers[-1]
                modifier.ratio = ratio
                modifier.use_collapse_triangulate = True
                bpy.ops.object.modifier_apply(modifier=modifier.name)
            obj.select_set(False)
        
        # 验证结果
        total_new = 0
        for obj in mesh_objects:
            bpy.context.view_layer.objects.active = obj
            obj.select_set(True)
            depsgraph = bpy.context.evaluated_depsgraph_get()
            eval_obj = obj.evaluated_get(depsgraph)
            mesh = bpy.data.meshes.new_from_object(eval_obj)
            total_new += len(mesh.polygons)
            bpy.data.meshes.remove(mesh)
            obj.select_set(False)
        print(f"    减面后总面数 = {total_new}")
    
    # 导出 FBX
    output_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.fbx(
        filepath=str(output_path),
        use_selection=True,
        apply_unit_scale=True,
        axis_forward='-Z',
        axis_up='Y',
        embed_textures=True,
        path_mode='COPY',
        bake_space_transform=True,
        use_mesh_modifiers=True,
    )
    print(f"  [SAVED] {output_path.name}")
    return True


def main():
    # Blender sys.argv 格式: [blender_exe, --background, --python, script.py, --, user_arg1, user_arg2, ...]
    # 提取 '--' 之后的用户参数
    user_args = []
    found_separator = False
    for arg in sys.argv:
        if arg == '--':
            found_separator = True
            continue
        if found_separator:
            user_args.append(arg)
    
    max_tris = int(user_args[0]) if user_args else MAX_TRIANGLES
    
    # 查找所有 playerX_base.glb 文件
    glb_files = sorted(MODEL_DIR.glob("player*_base.glb"))
    
    if not glb_files:
        print(f"[ERROR] 在 {MODEL_DIR} 下未找到 player*_base.glb 文件")
        sys.exit(1)
    
    print(f"[INFO] 找到 {len(glb_files)} 个高模文件，目标面数: {max_tris}")
    print(f"[INFO] 输出目录: {MODEL_DIR}")
    print(f"[INFO] 命名规则: playerX_low.fbx")
    print("=" * 60)
    
    success_count = 0
    fail_count = 0
    
    for glb_path in glb_files:
        # 生成统一命名输出路径: player1_base.glb -> player1_low.fbx
        player_num = glb_path.stem.replace("_base", "")
        output_name = f"{player_num}_low.fbx"
        output_path = MODEL_DIR / output_name
        
        print(f"\n[PROCESS] {glb_path.name} -> {output_name}")
        
        try:
            if decimate_model(glb_path, output_path, max_tris):
                success_count += 1
            else:
                fail_count += 1
        except Exception as e:
            print(f"  [ERROR] 处理失败: {e}")
            fail_count += 1
    
    print("\n" + "=" * 60)
    print(f"[DONE] 批量减面完成: 成功 {success_count} 个, 失败 {fail_count} 个")
    print(f"[OUTPUT] 低模文件列表:")
    for f in sorted(MODEL_DIR.glob("player*_low.fbx")):
        print(f"  - {f.name}")


if __name__ == '__main__':
    main()
