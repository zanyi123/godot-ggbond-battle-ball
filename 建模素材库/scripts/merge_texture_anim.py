"""
Blender 自动化脚本: 合并贴图(GLB) + 骨骼动画(Mixamo FBX) → 输出带贴图GLB
用法:
    blender --background --python merge_texture_anim.py -- <fbx_path> <glb_path> <out_glb_path>

原理:
    1. 原始 GLB 含完整贴图(混元下载,79MB,带baseColor/normal/metallic)
    2. Mixamo 导出的 FBX 含骨骼动画但贴图丢失(全身通粉)
    3. 本脚本把 GLB 的贴图材质赋给 FBX 的网格,再导出 GLB
"""
import bpy
import sys
import os

def parse_argv():
    # Blender 在 -- 后传参
    argv = sys.argv
    if "--" in argv:
        args = argv[argv.index("--") + 1:]
    else:
        args = []
    if len(args) < 3:
        print("[MERGE] ERROR: 参数不足,需要 fbx_path glb_path out_glb_path")
        sys.exit(1)
    return args[0], args[1], args[2]

def clear_scene():
    """清空默认场景"""
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    # 清空残余数据
    for block in list(bpy.data.meshes):
        bpy.data.meshes.remove(block)
    for block in list(bpy.data.materials):
        bpy.data.materials.remove(block)
    for block in list(bpy.data.textures):
        bpy.data.textures.remove(block)
    for block in list(bpy.data.images):
        bpy.data.images.remove(block)
    for block in list(bpy.data.armatures):
        bpy.data.armatures.remove(block)
    for block in list(bpy.data.actions):
        bpy.data.actions.remove(block)

def extract_textures_from_glb(glb_path):
    """只从 GLB 提取贴图图片数据,不保留 GLB 的网格
    返回 dict: {slot_name: image},比如 {'base': Image, 'normal': Image, ...}
    """
    print(f"[MERGE] 提取 GLB 贴图: {glb_path}")
    bpy.ops.import_scene.gltf(filepath=glb_path)
    # 收集所有 image
    images = {img.name: img for img in bpy.data.images}
    # 找带贴图的材质,解析它的节点,提取 baseColor/normal/metallic 图片
    textures = {}
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        for node in mat.node_tree.nodes:
            if node.type == 'TEX_IMAGE' and node.image:
                # 根据连接关系判断这张图是 baseColor 还是 normal 等
                for link in mat.node_tree.links:
                    if link.from_node == node:
                        target = link.to_node
                        target_socket = link.to_socket.name
                        if target_socket == 'Base Color':
                            textures['base'] = node.image
                        elif target_socket == 'Normal':
                            textures['normal'] = node.image
                        elif target_socket in ('Metallic', 'Roughness'):
                            textures['metallic_roughness'] = node.image
    print(f"[MERGE] 提取到贴图: {list(textures.keys())}")
    # 删除 GLB 网格,但保留 image 数据
    glb_mesh_objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    for o in glb_mesh_objs:
        bpy.data.objects.remove(o, do_unlink=True)
    return textures

def import_glb(glb_path):
    """导入原始 GLB,返回 (网格对象列表, 材质列表)"""
    print(f"[MERGE] 导入 GLB: {glb_path}")
    bpy.ops.import_scene.gltf(filepath=glb_path)
    # 收集网格对象和材质
    mesh_objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    materials = []
    for o in mesh_objs:
        for m in o.data.materials:
            if m and m not in materials:
                materials.append(m)
    print(f"[MERGE] GLB 网格数: {len(mesh_objs)}, 材质数: {len(materials)}")
    for i, m in enumerate(materials):
        print(f"[MERGE]   材质[{i}]: {m.name}, 节点数: {len(m.node_tree.nodes) if m.node_tree else 0}")
    return mesh_objs, materials

def _monkey_patch_cycles_light():
    """绕过 Blender 5.1.2 的 FBX 导入 bug
    报错: 'CyclesLightSettings' object has no attribute 'cast_shadow'
    位置: io_scene_fbx/import_fbx.py:2255
        lamp.cycles.cast_shadow = lamp.use_shadow
    原因: 5.1 API 移除了 cycles.cast_shadow,但 FBX addon 还在用旧 API
    修复: 替换模块级函数 blen_read_light,删掉那一行
    """
    try:
        import io_scene_fbx.import_fbx as fbx_mod
        if hasattr(fbx_mod, 'blen_read_light'):
            orig_fn = fbx_mod.blen_read_light
            def safe_blen_read_light(fbx_tmpl, fbx_obj, settings):
                try:
                    return orig_fn(fbx_tmpl, fbx_obj, settings)
                except AttributeError as e:
                    if 'cast_shadow' in str(e):
                        print(f"[MERGE] [PATCH] 跳过 FBX cycles.cast_shadow (5.1 兼容)")
                        return None
                    raise
            fbx_mod.blen_read_light = safe_blen_read_light
            print(f"[MERGE] [PATCH] 已替换 blen_read_light")
        else:
            print(f"[MERGE] [PATCH] 警告: 模块里找不到 blen_read_light")
    except Exception as e:
        print(f"[MERGE] [PATCH] 警告: patch 失败({e})")

def import_fbx(fbx_path):
    """导入 Mixamo FBX,返回 (网格对象列表, 骨架对象)"""
    print(f"[MERGE] 导入 FBX: {fbx_path}")
    _monkey_patch_cycles_light()
    # Mixamo FBX: 自动检测比例,通常不需要手动改
    try:
        bpy.ops.import_scene.fbx(filepath=fbx_path)
    except Exception as e:
        print(f"[MERGE] WARNING: FBX 标准导入失败({e})")
        print(f"[MERGE] 尝试用 ignore_leaf_bones / 禁用灯光选项重试...")
        bpy.ops.import_scene.fbx(
            filepath=fbx_path,
            use_anim=True,
            use_custom_normals=True,
            use_image_search=False,
        )
    mesh_objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    armatures = [o for o in bpy.context.scene.objects if o.type == 'ARMATURE']
    print(f"[MERGE] FBX 网格数: {len(mesh_objs)}, 骨架数: {len(armatures)}")
    return mesh_objs, armatures

def apply_texture_to_meshes(glb_materials, fbx_meshes):
    """把 GLB 的材质(含节点树+贴图)赋给 FBX 的网格"""
    if not glb_materials:
        print("[MERGE] WARNING: GLB 没有材质,无法赋值")
        return
    if not fbx_meshes:
        print("[MERGE] WARNING: FBX 没有网格")
        return

    # 用 GLB 的第一个材质(混元模型通常单一材质)
    # 优先选带贴图(节点数最多)的材质
    src_mat = None
    if len(glb_materials) == 1:
        src_mat = glb_materials[0]
    else:
        # 多个材质时,选节点数最多的(通常是带贴图的主材质)
        best_score = -1
        for m in glb_materials:
            try:
                score = len(m.node_tree.nodes) if m.node_tree else 0
                if score > best_score:
                    best_score = score
                    src_mat = m
            except ReferenceError:
                continue
    if src_mat is None:
        print("[MERGE] WARNING: 没有可用材质")
        return
    print(f"[MERGE] 使用源材质: {src_mat.name}")

    # 重新获取 fbx_meshes(防止引用失效)
    fresh_fbx_meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    print(f"[MERGE] 重新获取 FBX 网格数: {len(fresh_fbx_meshes)}")

    for mesh_obj in fresh_fbx_meshes:
        # 重新关联材质数据(避免引用失效)
        try:
            mesh_obj.data.materials.clear()
            mesh_obj.data.materials.append(src_mat)
            print(f"[MERGE]   网格 '{mesh_obj.name}' 已赋材质")
        except ReferenceError:
            print(f"[MERGE]   警告: 网格引用失效,跳过")

def export_glb(out_path):
    """导出 GLB,内嵌贴图"""
    print(f"[MERGE] 导出 GLB: {out_path}")
    # 显式选中并激活所有对象
    bpy.ops.object.select_all(action='DESELECT')
    for obj in bpy.context.scene.objects:
        obj.select_set(True)
    # active 设为 Armature(导出骨架需要)
    armature_obj = None
    for obj in bpy.context.scene.objects:
        if obj.type == 'ARMATURE':
            armature_obj = obj
            break
    if armature_obj:
        bpy.context.view_layer.objects.active = armature_obj
    else:
        # 没有 armature 就用第一个 mesh
        bpy.context.view_layer.objects.active = bpy.context.scene.objects[0]
    sel_count = len([o for o in bpy.context.scene.objects if o.select_get()])
    print(f"[MERGE] 选中对象数: {sel_count}, active: {bpy.context.view_layer.objects.active.name if bpy.context.view_layer.objects.active else 'None'}")

    # 重写 context 字典, 解决 background 模式 ops 报 context 不对
    try:
        bpy.ops.export_scene.gltf(
            filepath=out_path,
            export_format='GLB',
            export_materials='EXPORT',    # 导出材质(5.1 默认带贴图)
            export_yup=True,
            export_apply=True,
            use_selection=True,
            export_animations=True,       # 5.1 是 export_animations(带 s)
        )
    except Exception as e:
        import traceback
        print(f"[MERGE] EXPORT ERROR: {e}")
        traceback.print_exc()
        return False

    import os
    if os.path.exists(out_path):
        size = os.path.getsize(out_path)
        print(f"[MERGE] 导出成功: {out_path} ({size} bytes)")
        return True
    else:
        print(f"[MERGE] ERROR: 导出文件不存在! {out_path}")
        return False

def main():
    fbx_path, glb_path, out_path = parse_argv()
    fbx_path = os.path.abspath(fbx_path)
    glb_path = os.path.abspath(glb_path)
    out_path = os.path.abspath(out_path)

    print(f"[MERGE] === 开始合并 ===")
    print(f"[MERGE] FBX: {fbx_path}")
    print(f"[MERGE] GLB: {glb_path}")
    print(f"[MERGE] 输出: {out_path}")

    if not os.path.exists(fbx_path):
        print(f"[MERGE] ERROR: FBX 不存在")
        sys.exit(1)
    if not os.path.exists(glb_path):
        print(f"[MERGE] ERROR: GLB 不存在")
        sys.exit(1)

    clear_scene()
    # 顺序很重要: 先导入 FBX(骨骼动画), 再导入 GLB(贴图)
    # 这样 GLB 后导入, 引用一定有效
    fbx_meshes_before, armatures = import_fbx(fbx_path)
    glb_meshes, glb_mats = import_glb(glb_path)

    # 重新从场景获取 FBX 网格(GLB 导入后场景对象引用可能变化)
    fbx_meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    # FBX 的 mesh 和 GLB 的 mesh 都在,需要区分:FBX 的通常名字带 Armature/Skeleton
    print(f"[MERGE] 当前场景网格总数: {len(fbx_meshes)}")
    for o in fbx_meshes:
        print(f"[MERGE]   - {o.name} (parent: {o.parent.name if o.parent else 'None'})")

    # 删除 GLB 的网格(只用它的材质)
    # 通过名字区分: GLB 的网格名通常是 node_0 或来自混元,Fbx 的网格有 Armature 父级
    glb_mesh_to_del = []
    for o in fbx_meshes:
        # GLB 网格通常没有 Armature 作为父级
        is_from_fbx = False
        if o.parent and o.parent.type == 'ARMATURE':
            is_from_fbx = True
        # 也通过 vertex_count 区分(混元的网格通常面数不同)
        if not is_from_fbx:
            # 再检查一下是否就是 GLB 那个(通过判断父级不是 armature)
            glb_mesh_to_del.append(o)

    print(f"[MERGE] 识别为 GLB 网格待删: {len(glb_mesh_to_del)}")
    for o in glb_mesh_to_del:
        name_snapshot = "<unknown>"
        try:
            name_snapshot = o.name
            bpy.data.objects.remove(o, do_unlink=True)
            print(f"[MERGE]   已删除 GLB 网格: {name_snapshot}")
        except ReferenceError:
            print(f"[MERGE]   网格已失效(已删): {name_snapshot}")
        except Exception as e:
            print(f"[MERGE]   删除失败 {name_snapshot}: {e}")

    apply_texture_to_meshes(glb_mats, fbx_meshes)

    export_glb(out_path)
    print(f"[MERGE] === 全部完成 ===")

if __name__ == "__main__":
    main()
