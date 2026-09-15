#!/usr/bin/env python3
"""
决竞球 3D 模型减面工具（交互式 + 命令行双模式）
用法1(命令行): blender --background --python tools/decimate_model.py -- <输入模型路径> [目标面数] [输出文件名]
用法2(交互式): blender --background --python tools/decimate_model.py
  启动后依次提示输入: 模型路径、目标面数、输出文件名

支持格式: .glb, .gltf, .fbx, .obj
输出: 同目录下 <原名>_decimated.fbx (默认6万面)，或通过第三参数指定输出名

示例:
  # 交互式（推荐，路径不固定）
  blender --background --python tools/decimate_model.py

  # 命令行 - 默认减面 6万面
  blender --background --python tools/decimate_model.py -- "建模素材库/3D模型素材/player1_base.glb"

  # 命令行 - 指定目标面数 8万
  blender --background --python tools/decimate_model.py -- "建模素材库/3D模型素材/player1_base.glb" 80000

  # 命令行 - 备用模型单独命名
  blender --background --python tools/decimate_model.py -- "建模素材库/3D模型素材/player2-.glb" 60000 "player2_v2_low.fbx"
"""

import sys
import bpy
from pathlib import Path

# ========== 参数 ==========
MAX_TRIANGLES = 60000  # 目标三角面数（可通过命令行修改）
DEFAULT_OUTPUT_SUFFIX = "_decimated"  # 默认输出后缀


def prompt_input(prompt: str, default: str = "") -> str:
    """交互式输入（Blender 后台模式 stdin 可用）"""
    try:
        val = input(prompt).strip()
        return val if val else default
    except (EOFError, OSError):
        return default


def get_input_params() -> tuple:
    """交互式获取输入参数，返回 (input_path, max_tris, output_name)"""
    print("=" * 60)
    print("决竞球 3D 模型减面工具 - 交互模式")
    print("=" * 60)

    # 1. 输入模型路径
    input_path = ""
    while not input_path:
        val = prompt_input("\n请输入模型文件路径（支持 .glb/.gltf/.fbx/.obj）: ")
        if not val:
            print("[ERROR] 路径不能为空")
            continue
        # 去除首尾引号
        val = val.strip('"').strip("'")
        if not Path(val).exists():
            print(f"[ERROR] 文件不存在: {val}")
            continue
        input_path = val

    # 2. 目标面数
    max_tris = MAX_TRIANGLES
    val = prompt_input(f"\n目标三角面数（默认 {MAX_TRIANGLES}）: ", str(MAX_TRIANGLES))
    try:
        max_tris = int(val) if val else MAX_TRIANGLES
    except ValueError:
        print(f"[WARN] 面数无效，使用默认 {MAX_TRIANGLES}")
        max_tris = MAX_TRIANGLES

    # 3. 输出文件名（可选）
    default_name = Path(input_path).stem + DEFAULT_OUTPUT_SUFFIX + ".fbx"
    val = prompt_input(f"\n输出文件名（回车=默认 {default_name}，可指定如 player2_v2_low.fbx）: ", default_name)
    output_name = val if val else default_name

    return input_path, max_tris, output_name


def decimate(input_path: str, max_tris: int = MAX_TRIANGLES, output_name: str = "") -> str:
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
            ratio = max(0.01, min(1.0, ratio))  # 最低保留1%(混元高模可达150万面,需低于10%)
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
    if output_name:
        # 用户指定输出名：支持纯文件名（放同目录）或完整路径
        out_file = Path(output_name)
        if not out_file.is_absolute():
            out_file = input_file.parent / output_name
        # 自动补 .fbx 后缀
        if out_file.suffix.lower() != ".fbx":
            out_file = out_file.with_suffix(".fbx")
        output_path = str(out_file)
    else:
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
    # Blender 模式: sys.argv = [blender.exe, --background, --python, script.py, --, user_arg1, ...]
    # 提取 '--' 之后的用户参数
    user_args = []
    found_separator = False
    for arg in sys.argv:
        if arg == '--':
            found_separator = True
            continue
        if found_separator:
            user_args.append(arg)

    # 非 Blender 模式（直接 python 调用）回退：取 argv[1:]
    if not user_args:
        user_args = sys.argv[1:]

    if not user_args:
        # 交互式模式：无命令行参数时手动输入
        input_path, max_tris, output_name = get_input_params()
    else:
        # 命令行模式
        input_path = user_args[0]
        max_tris = int(user_args[1]) if len(user_args) > 1 else MAX_TRIANGLES
        output_name = user_args[2] if len(user_args) > 2 else ""

    decimate(input_path, max_tris, output_name)
