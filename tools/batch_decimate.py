#!/usr/bin/env python3
"""
决竞球 3D 模型批量减面工具（交互式 + 命令行双模式）
批量扫描指定目录下所有 player*_base.glb 高模，输出 playerX_low.fbx 低模

用法1(命令行): blender --background --python tools/batch_decimate.py -- [目标面数] [目录路径]
用法2(交互式): blender --background --python tools/batch_decimate.py
  启动后依次提示输入: 目录路径、目标面数、文件匹配模式

默认扫描: 建模素材库/3D模型素材/
默认目标: 60000 三角面
默认匹配: player*_base.glb
输出命名: playerX_low.fbx（放同目录）

示例:
  # 交互式（推荐，路径不固定）
  blender --background --python tools/batch_decimate.py

  # 命令行 - 扫描默认目录
  blender --background --python tools/batch_decimate.py -- 60000

  # 命令行 - 指定目录
  blender --background --python tools/batch_decimate.py -- 60000 "建模素材库/3D模型素材/20260714_glb_player_base"
"""

import sys
import bpy
from pathlib import Path

# ========== 配置 ==========
PROJECT_ROOT = Path(__file__).parent.parent.resolve()
DEFAULT_MODEL_DIR = PROJECT_ROOT / "建模素材库" / "3D模型素材"
MAX_TRIANGLES = 60000  # 目标三角面数
DEFAULT_PATTERN = "player*_base.glb"


def prompt_input(prompt: str, default: str = "") -> str:
    """交互式输入"""
    try:
        val = input(prompt).strip()
        return val if val else default
    except (EOFError, OSError):
        return default


def get_input_params() -> tuple:
    """交互式获取参数，返回 (model_dir, max_tris, pattern)"""
    print("=" * 60)
    print("决竞球 3D 模型批量减面工具 - 交互模式")
    print("=" * 60)

    # 1. 目录路径
    default_dir = str(DEFAULT_MODEL_DIR)
    val = prompt_input(f"\n扫描目录路径（回车=默认 {default_dir}）: ", default_dir)
    val = val.strip('"').strip("'")
    model_dir = Path(val) if val else DEFAULT_MODEL_DIR
    if not model_dir.exists():
        print(f"[ERROR] 目录不存在: {model_dir}")
        sys.exit(1)
    if not model_dir.is_dir():
        print(f"[ERROR] 不是目录: {model_dir}")
        sys.exit(1)

    # 2. 目标面数
    val = prompt_input(f"\n目标三角面数（默认 {MAX_TRIANGLES}）: ", str(MAX_TRIANGLES))
    try:
        max_tris = int(val) if val else MAX_TRIANGLES
    except ValueError:
        print(f"[WARN] 面数无效，使用默认 {MAX_TRIANGLES}")
        max_tris = MAX_TRIANGLES

    # 3. 文件匹配模式
    val = prompt_input(f"\n文件匹配模式（回车=默认 {DEFAULT_PATTERN}）: ", DEFAULT_PATTERN)
    pattern = val if val else DEFAULT_PATTERN

    return model_dir, max_tris, pattern


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
    # Blender sys.argv 格式: [blender_exe, --background, --python, script.py, --, user_arg1, ...]
    # 提取 '--' 之后的用户参数
    user_args = []
    found_separator = False
    for arg in sys.argv:
        if arg == '--':
            found_separator = True
            continue
        if found_separator:
            user_args.append(arg)

    if not user_args:
        # 交互式模式
        model_dir, max_tris, pattern = get_input_params()
    else:
        # 命令行模式: [目标面数] [目录路径] [匹配模式]
        max_tris = int(user_args[0]) if len(user_args) >= 1 else MAX_TRIANGLES
        dir_arg = user_args[1] if len(user_args) > 1 else ""
        pattern = user_args[2] if len(user_args) > 2 else DEFAULT_PATTERN

        if dir_arg:
            model_dir = Path(dir_arg.strip('"').strip("'"))
            if not model_dir.is_absolute():
                model_dir = PROJECT_ROOT / dir_arg
        else:
            model_dir = DEFAULT_MODEL_DIR

    if not model_dir.exists():
        print(f"[ERROR] 目录不存在: {model_dir}")
        sys.exit(1)

    # 查找所有匹配的 glb 文件
    glb_files = sorted(model_dir.glob(pattern))

    if not glb_files:
        print(f"[ERROR] 在 {model_dir} 下未找到匹配 {pattern} 的文件")
        sys.exit(1)

    print(f"[INFO] 扫描目录: {model_dir}")
    print(f"[INFO] 匹配模式: {pattern}")
    print(f"[INFO] 找到 {len(glb_files)} 个高模文件，目标面数: {max_tris}")
    print(f"[INFO] 输出目录: {model_dir}")
    print(f"[INFO] 命名规则: playerX_low.fbx")
    print("=" * 60)

    success_count = 0
    fail_count = 0

    for glb_path in glb_files:
        # 生成统一命名输出路径: player1_base.glb -> player1_low.fbx
        player_num = glb_path.stem.replace("_base", "")
        output_name = f"{player_num}_low.fbx"
        output_path = model_dir / output_name

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
    for f in sorted(model_dir.glob("player*_low.fbx")):
        print(f"  - {f.name}")


if __name__ == '__main__':
    main()
