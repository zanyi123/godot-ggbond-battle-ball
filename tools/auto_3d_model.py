#!/usr/bin/env python3
"""
决竞球3D建模自动化工具

全流程自动脚本化：
  ① 接受即梦生成的T-pose参考图（用户提供）
  ② 混元3D API图生3D生成模型（OpenAI兼容接口，sk-xxxxx密钥）
  ③ Blender命令行转FBX（仅当混元输出GLB时需要，备用）
  ④ Mixamo手动绑骨+下载动画
  ⑤ 复制到Godot项目目录

使用方法:
    python tools/auto_3d_model.py <角色名> --image <即梦图片路径>

示例:
    python tools/auto_3d_model.py player1 --image "建模素材库/2D图片素材/player1.png"
    python tools/auto_3d_model.py player5 --image "建模素材库/2D图片素材/player5.png"

目录结构（按项目现有规范）：
    建模素材库/
      ├── 2D图片素材/                    即梦参考图 (player1.png, player5.png...)
      └── 3D模型素材/
            ├── player1.fbx              基础FBX模型
            ├── player1动作/             动画文件夹
            │     ├── Idle.fbx
            │     ├── Jog Forward.fbx
            │     └── ...
            └── (混元原始GLB和贴图文件)

配置文件: tools/auto_3d_model_config.json
  需要填写混元3D API KEY (sk-xxxxx格式)
  开通地址: https://console.cloud.tencent.com/ai3d/settings
  API KEY创建: https://console.cloud.tencent.com/ai3d/start
  使用OpenAI兼容接口: https://api.ai3d.cloud.tencent.com
"""

import os
import sys
import json
import time
import shutil
import subprocess
import base64
import argparse
import requests
from pathlib import Path

# ==================== 路径配置 ====================
PROJECT_ROOT = Path(__file__).parent.parent.resolve()
TOOL_DIR = PROJECT_ROOT / "tools"
CONFIG_FILE = TOOL_DIR / "auto_3d_model_config.json"

# 素材目录（对齐项目现有规范）
REF_IMAGE_DIR = PROJECT_ROOT / "建模素材库" / "2D图片素材"    # 参考图
MODEL_DIR = PROJECT_ROOT / "建模素材库" / "3D模型素材"         # 3D模型根目录

# Godot目标目录
GODOT_ASSETS_DIR = PROJECT_ROOT / "assets" / "characters" / "avatars"

# 混元3D可用模板（足球相关的标★）
HUNYUAN_TEMPLATES = {
    "footballboy": "足球小将 ★（推荐）",
    "footballboykicking1": "激情逐风（踢球动作1）",
    "footballboykicking2": "绿茵之星（踢球动作2）",
    "basketball": "动感球手",
    "badminton": "羽扬中华",
    "pingpong": "国球荣耀",
    "gymnastics": "勇攀巅峰",
    "pilidance": "舞动青春",
    "tennis": "网球甜心",
    "athletics": "东方疾风",
    "guitar": "甜酷弦音",
    "skateboard": "滑跃青春",
    "futuresoilder": "未来战士",
    "explorer": "逐梦旷野",
    "beardollgirl": "可爱女孩",
    "bibpantsboy": "都市白领",
    "womansitpose": "职业丽影",
    "womanstandpose2": "悠闲时光",
    "mysteriousprincess": "海洋公主",
    "manstandpose2": "演讲之星",
}

# Mixamo推荐动画（中文名→搜索词→推荐选名）
# 对齐项目现有命名：直接用Mixamo原始文件名
MIXAMO_ANIMS = [
    {"key": "idle",    "search": "Idle",        "name": "Breathing Idle",      "loop": True,  "file": "Breathing Idle.fbx"},
    {"key": "run",     "search": "Jog",         "name": "Jog Forward",          "loop": True,  "file": "Jog Forward.fbx"},
    {"key": "throw",   "search": "Throw",       "name": "Throw",                "loop": False, "file": "Throw.fbx"},
    {"key": "hurt",    "search": "Stumble",     "name": "Stumble Backwards",    "loop": False, "file": "Stumble Backwards.fbx"},
]


def get_anim_dir(char_id):
    """获取角色动画目录路径：3D模型素材/{char_id}动作/"""
    return MODEL_DIR / f"{char_id}动作"


def get_base_fbx(char_id):
    """获取基础FBX路径：3D模型素材/{char_id}.fbx"""
    return MODEL_DIR / f"{char_id}.fbx"


def get_ref_image(char_id):
    """获取参考图路径（检查所有常见扩展名）"""
    for ext in ['.png', '.jpg', '.jpeg', '.webp']:
        p = REF_IMAGE_DIR / f"{char_id}{ext}"
        if p.exists():
            return p
    return REF_IMAGE_DIR / f"{char_id}.png"  # 默认路径


# ==================== 配置加载 ====================
def load_config():
    if not CONFIG_FILE.exists():
        default_config = {
            "hunyuan_api_key": "",
            "blender_path": "blender",
            "hunyuan_template": "footballboy",
            "result_format": "",
            "poll_interval_seconds": 5,
            "max_poll_attempts": 120
        }
        with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
            json.dump(default_config, f, indent=2, ensure_ascii=False)
        print(f"[配置] 已生成默认配置文件: {CONFIG_FILE}")
        print(f"[配置] 请填写hunyuan_api_key（sk-xxxxx格式）后重新运行")
        print(f"[配置] 开通地址: https://console.cloud.tencent.com/ai3d/settings")
        print(f"[配置] 创建KEY: https://console.cloud.tencent.com/ai3d/start")
        sys.exit(1)

    with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
        return json.load(f)


# ==================== 0. 全局检查：是否已完成 ====================
def check_already_done(char_id):
    """检查角色是否已经完成所有步骤，避免重复工作"""
    base_fbx = get_base_fbx(char_id)
    anim_dir = get_anim_dir(char_id)
    godot_dir = GODOT_ASSETS_DIR

    status = {
        "ref_image": False,
        "base_fbx": False,
        "anim_count": 0,
        "godot_count": 0,
        "all_done": False,
    }

    # 参考图
    ref = get_ref_image(char_id)
    if ref.exists():
        status["ref_image"] = True

    # 基础FBX
    if base_fbx.exists() and base_fbx.stat().st_size > 0:
        status["base_fbx"] = True

    # 动画文件（在anim目录里找所有fbx）
    if anim_dir.exists():
        anim_files = list(anim_dir.glob("*.fbx"))
        status["anim_count"] = len(anim_files)

    # Godot目录中的动画
    if godot_dir.exists():
        for anim_info in MIXAMO_ANIMS:
            dst = godot_dir / f"{char_id}_{anim_info['key']}.fbx"
            if dst.exists() and dst.stat().st_size > 0:
                status["godot_count"] += 1

    # 全部完成判定
    if (status["base_fbx"] and
            status["anim_count"] >= len(MIXAMO_ANIMS) and
            status["godot_count"] >= len(MIXAMO_ANIMS)):
        status["all_done"] = True

    return status


# ==================== 1. 接受即梦图片 ====================
def prepare_tpose_image(char_id, image_path):
    """接受用户提供的即梦T-pose参考图，复制到素材库标准位置"""
    src = Path(image_path)
    if not src.exists():
        print(f"[ERROR] 图片不存在: {src}")
        sys.exit(1)

    # 目标路径：建模素材库/2D图片素材/{char_id}.png（保持原扩展名）
    ext = src.suffix.lower()
    dst = REF_IMAGE_DIR / f"{char_id}{ext}"
    dst.parent.mkdir(parents=True, exist_ok=True)

    # 如果已存在同名同大小，跳过
    if dst.exists() and dst.stat().st_size == src.stat().st_size:
        print(f"[步骤1] 参考图已存在，跳过: {dst}")
        return str(dst)

    shutil.copy(src, dst)
    print(f"[步骤1] 参考图已复制: {src.name} -> {dst}")
    return str(dst)


# ==================== 2. 混元3D API图生3D ====================
HUNYUAN_SUBMIT_URL = "https://api.ai3d.cloud.tencent.com/v1/ai3d/submit"
HUNYUAN_QUERY_URL = "https://api.ai3d.cloud.tencent.com/v1/ai3d/query"


def generate_3d_model_api(config, char_id, image_path):
    """使用腾讯混元3D OpenAI兼容接口图生3D"""
    base_fbx = get_base_fbx(char_id)

    # 检测：基础FBX已存在，直接跳过
    if base_fbx.exists() and base_fbx.stat().st_size > 0:
        print(f"[步骤2] 基础FBX已存在，跳过生成: {base_fbx}")
        return str(base_fbx)

    # 检测：命名匹配的GLB文件（只认 {char_id}.glb 或 {char_id}_base.glb）
    matched_glbs = []
    for glb in MODEL_DIR.glob("*.glb"):
        stem_lower = glb.stem.lower()
        char_lower = char_id.lower()
        if stem_lower == char_lower or stem_lower == f"{char_lower}_base":
            matched_glbs.append(glb)
    
    if matched_glbs:
        matched_glb = matched_glbs[0]
        print(f"[步骤2] 检测到匹配的GLB: {matched_glb.name}")
        print(f"[步骤2] 将作为 {char_id} 的模型，自动转FBX")
        return str(matched_glb)

    api_key = config.get("hunyuan_api_key", "")

    if not api_key:
        print(f"[步骤2] API KEY未配置，进入手动模式...")
        return _manual_hunyuan(char_id, image_path)

    print(f"[步骤2] 调用混元3D API生成模型...")
    print(f"[步骤2] 接口: OpenAI兼容 (sk-xxxxx方式)")

    # 读取图片并转Base64
    with open(image_path, 'rb') as f:
        img_base64 = base64.b64encode(f.read()).decode('utf-8')

    ext = Path(image_path).suffix.lower()
    mime_map = {'.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp'}
    mime_type = mime_map.get(ext, 'image/jpeg')
    img_data_uri = f"data:{mime_type};base64,{img_base64}"

    headers = {
        "Authorization": api_key,
        "Content-Type": "application/json"
    }

    # OpenAI兼容接口请求体
    # 根据文档: ImageUrl.Url 支持图片链接和data URI两种方式
    submit_payload = {
        "Model": "3.0",
        "ImageUrl": {
            "Url": img_data_uri  # data:image/png;base64,xxxxxx 格式
        }
    }

    # 可选参数
    if config.get("result_format"):
        submit_payload["ResultFormat"] = config["result_format"]

    print(f"[步骤2] 提交生成任务...")
    print(f"[DEBUG] API地址: {HUNYUAN_SUBMIT_URL}")
    print(f"[DEBUG] Model: 3.0")
    print(f"[DEBUG] ImageUrl类型: data URI ({len(img_data_uri)} 字符)")
    print(f"[DEBUG] 图片Base64长度: {len(img_base64)} 字符")

    try:
        resp = requests.post(HUNYUAN_SUBMIT_URL, headers=headers, json=submit_payload, timeout=60)
        print(f"[DEBUG] 响应状态码: {resp.status_code}")
        print(f"[DEBUG] 响应内容: {resp.text[:500]}")
        resp.raise_for_status()
        data = resp.json()
    except requests.exceptions.RequestException as e:
        print(f"[步骤2] API调用失败: {e}")
        if hasattr(e, 'response') and e.response is not None:
            print(f"[步骤2] 响应内容: {e.response.text[:500]}")
        print(f"[步骤2] 进入手动模式...")
        return _manual_hunyuan(char_id, image_path)

    # 解析JobId
    job_id = None
    if isinstance(data, dict):
        job_id = data.get("JobId") or data.get("job_id") or data.get("id")
        if not job_id and "Response" in data:
            job_id = data["Response"].get("JobId")

    if not job_id:
        print(f"[步骤2] 未获取到JobId，响应: {json.dumps(data, indent=2, ensure_ascii=False)[:500]}")
        print(f"[步骤2] 进入手动模式...")
        return _manual_hunyuan(char_id, image_path)

    print(f"[步骤2] 任务已提交, JobId: {job_id}")
    return _poll_hunyuan_job(api_key, job_id, char_id)


def _poll_hunyuan_job(api_key, job_id, char_id):
    """轮询混元3D生成任务"""
    headers = {"Authorization": api_key, "Content-Type": "application/json"}

    poll_interval = 5
    max_attempts = 120

    print(f"[步骤2] 等待生成完成（每{poll_interval}秒查询一次，最长{max_attempts * poll_interval}秒）...")

    for attempt in range(max_attempts):
        time.sleep(poll_interval)

        query_payload = {"JobId": job_id}

        try:
            resp = requests.post(HUNYUAN_QUERY_URL, headers=headers, json=query_payload, timeout=30)
            resp.raise_for_status()
            data = resp.json()
        except Exception as e:
            print(f"[步骤2] 轮询失败: {e}")
            continue

        # 解析状态
        status = ""
        result_files = []

        if isinstance(data, dict):
            status = data.get("Status") or data.get("status", "")
            result_files = data.get("ResultFile3Ds") or data.get("result_file3ds") or []
            if not status and "Response" in data:
                resp_data = data["Response"]
                status = resp_data.get("Status", "")
                result_files = resp_data.get("ResultFile3Ds", [])

        if status == "DONE":
            print(f"[步骤2] 生成完成！正在下载模型文件...")
            return _download_result_files(result_files, char_id)

        elif status == "FAIL":
            error_msg = ""
            if isinstance(data, dict):
                error_msg = data.get("ErrorMessage") or data.get("error_message") or ""
                if "Response" in data:
                    error_msg = data["Response"].get("ErrorMessage", "")
            print(f"[步骤2] 生成失败: {error_msg}")
            print(f"[步骤2] 完整响应: {json.dumps(data, indent=2, ensure_ascii=False)[:500]}")
            return None

        elif status in ("WAIT", "RUN"):
            if attempt % 6 == 0:
                elapsed = (attempt + 1) * poll_interval
                print(f"[步骤2] 等待中... 状态: {status} (已等待{elapsed}秒)")
        else:
            if attempt % 6 == 0:
                print(f"[步骤2] 未知状态: {status} (已等待{(attempt + 1) * poll_interval}秒)")
                print(f"  响应片段: {json.dumps(data, indent=2, ensure_ascii=False)[:200]}")

    print(f"[步骤2] 超时！生成耗时超过{max_attempts * poll_interval}秒")
    return None


def _download_result_files(result_files, char_id):
    """从查询结果中下载模型文件，保存到3D模型素材目录"""
    if not result_files:
        print(f"[步骤2] 生成完成但无文件列表")
        return None

    fbx_url = None
    glb_url = None
    obj_url = None

    for f in result_files:
        file_type = f.get("Type") or f.get("type", "")
        file_url = f.get("Url") or f.get("url", "")
        if file_type == "FBX" and file_url:
            fbx_url = file_url
        elif file_type == "GLB" and file_url:
            glb_url = file_url
        elif file_type == "OBJ" and file_url:
            obj_url = file_url

    # 确保目录存在
    MODEL_DIR.mkdir(parents=True, exist_ok=True)

    # 优先下载FBX，直接保存为 char_id.fbx
    if fbx_url:
        fbx_path = get_base_fbx(char_id)
        print(f"[步骤2] 下载FBX模型 -> {fbx_path}")
        _download_file(fbx_url, fbx_path)
        return str(fbx_path)

    # 其次下载GLB，保存为混元原始名（hash命名），需要后续Blender转
    elif glb_url:
        # 用char_id_base.glb命名，方便识别
        glb_path = MODEL_DIR / f"{char_id}_base.glb"
        print(f"[步骤2] 下载GLB模型 -> {glb_path}")
        _download_file(glb_url, glb_path)
        return str(glb_path)

    elif obj_url:
        obj_path = MODEL_DIR / f"{char_id}_base_obj.zip"
        print(f"[步骤2] 下载OBJ模型 -> {obj_path}")
        _download_file(obj_url, obj_path)
        return str(obj_path)
    else:
        print(f"[步骤2] 无可下载的模型文件")
        print(f"  可用文件: {[f.get('Type', '?') for f in result_files]}")
        return None


def _manual_hunyuan(char_id, image_path):
    """手动混元3D模式"""
    base_fbx = get_base_fbx(char_id)
    anim_dir = get_anim_dir(char_id)

    print(f"\n{'='*50}")
    print(f"  手动模式：混元3D图生3D")
    print(f"{'='*50}")
    print(f"  1. 打开 https://3d.hunyuan.tencent.com/")
    print(f"  2. 点「图生3D」")
    print(f"  3. 上传图片: {image_path}")
    print(f"  4. 风格选「风格化/卡通」")
    print(f"  5. 生成后下载GLB或FBX")
    print(f"  6. 文件放到: {MODEL_DIR}/")
    print(f"     - FBX命名为: {char_id}.fbx")
    print(f"     - GLB命名为: {char_id}_base.glb（脚本会自动转FBX）")
    print(f"  7. 动画下载到: {anim_dir}/")
    print(f"{'='*50}")

    print(f"  完成后按回车继续...")
    try:
        input()
    except EOFError:
        print(f"[注意] 非交互式模式，跳过等待。请手动下载动画后重新运行脚本。")

    print(f"[检测] 正在查找模型文件...")
    print(f"[检测] 期望路径: {MODEL_DIR}/")
    print(f"[检测] 期望文件名: {char_id}.fbx 或 {char_id}_base.glb")

    # 列出当前目录下所有相关文件（帮助调试）
    if MODEL_DIR.exists():
        all_files = list(MODEL_DIR.glob(f"*{char_id}*"))
        if all_files:
            print(f"[检测] 找到以下匹配文件:")
            for f in all_files:
                size_kb = f.stat().st_size / 1024
                print(f"       - {f.name} ({size_kb:.0f}KB)")
        else:
            print(f"[检测] 目录 {MODEL_DIR} 中没有包含 '{char_id}' 的文件")
    else:
        print(f"[检测] 目录 {MODEL_DIR} 不存在！")

    # 检查FBX（大小写不敏感）
    for f in MODEL_DIR.glob("*.fbx"):
        if f.stem.lower() == char_id.lower() and f.stat().st_size > 0:
            print(f"[步骤2] 检测到FBX: {f}")
            return str(f)

    # 检查GLB（大小写不敏感）
    for f in MODEL_DIR.glob("*.glb"):
        if f.stem.lower() == char_id.lower() or f.stem.lower() == f"{char_id}_base".lower():
            if f.stat().st_size > 0:
                print(f"[步骤2] 检测到GLB: {f}，将自动转FBX")
                return str(f)

    print(f"[步骤2] 未检测到模型文件")
    print(f"[步骤2] 请确认文件已放到: {MODEL_DIR}/")
    print(f"[步骤2] 且文件名为: {char_id}.fbx 或 {char_id}_base.glb")
    return None


def _download_file(url, save_path):
    """下载文件"""
    resp = requests.get(url, stream=True, timeout=120)
    resp.raise_for_status()
    save_path.parent.mkdir(parents=True, exist_ok=True)
    with open(save_path, 'wb') as f:
        for chunk in resp.iter_content(chunk_size=8192):
            f.write(chunk)
    size_kb = save_path.stat().st_size / 1024
    print(f"[下载] 保存到: {save_path} ({size_kb:.0f}KB)")


# ==================== 3. Blender转FBX ====================
def convert_glb_to_fbx(config, char_id, glb_path):
    """使用Blender命令行将GLB转为FBX"""
    if glb_path.endswith('.fbx'):
        return glb_path

    output_path = get_base_fbx(char_id)
    if output_path.exists() and output_path.stat().st_size > 0:
        print(f"[步骤3] FBX已存在，跳过转换: {output_path}")
        return str(output_path)

    print(f"[步骤3] Blender转FBX...")
    print(f"[步骤3] 输入: {glb_path}")
    print(f"[步骤3] 输出: {output_path}")

    blender_script = f"""
import bpy
from mathutils import Vector

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

bpy.ops.import_scene.gltf(filepath=r"{glb_path}")

# 合并所有网格对象为一个（解决头发分离问题）
mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
if len(mesh_objects) > 1:
    print(f"[Blender] 发现 {{len(mesh_objects)}} 个网格对象，合并为一个")
    bpy.context.view_layer.objects.active = mesh_objects[0]
    for obj in mesh_objects[1:]:
        obj.select_set(True)
    bpy.ops.object.join()
    print(f"[Blender] 合并完成")

bpy.ops.object.select_all(action='SELECT')
obj = bpy.context.selected_objects[0] if bpy.context.selected_objects else None

if obj:
    bpy.context.view_layer.objects.active = obj
    
    # 应用所有变换
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    
    # 原点居中 + 底部贴地
    bpy.ops.object.origin_set(type='ORIGIN_CENTER_OF_MASS', center='BOUNDS')
    bbox_corners = [obj.matrix_world @ Vector(v) for v in obj.bound_box]
    min_y = min(c.y for c in bbox_corners)
    obj.location.y -= min_y
    bpy.ops.object.transform_apply(location=True)
    
    # 修复网格（降低去重阈值，避免手指顶点被合并）
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.remove_doubles(threshold=0.0001)
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.mesh.quads_convert_to_tris()
    bpy.ops.object.mode_set(mode='OBJECT')
    
    # 对称修复：仅对称化四肢区域，保护头部特征
    # 使用 Symmetrize 工具，只对选中的四肢顶点生效
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='DESELECT')
    bpy.ops.object.mode_set(mode='OBJECT')
    
    # 选择四肢区域的顶点：X绝对值较大（手臂）或 Y较低（腿部）
    # 排除头部区域（Y较高且靠近中线的部分）
    mesh = obj.data
    for v in mesh.vertices:
        is_limb = (abs(v.co.x) > 0.3) or (v.co.y < -0.3)
        v.select = is_limb
    
    # 在编辑模式下对称化选中的顶点（从-X侧复制到+X侧）
    bpy.ops.object.mode_set(mode='EDIT')
    try:
        bpy.ops.mesh.symmetrize(direction='NEGATIVE_X')
        print(f"[Blender] 四肢区域已对称化（保留头部特征）")
    except Exception as e:
        print(f"[Blender] 对称化工具失败: {{e}}，跳过对称修复")
    bpy.ops.mesh.select_all(action='DESELECT')
    bpy.ops.object.mode_set(mode='OBJECT')
    
    # 修复镜像后的网格问题（再次去重，阈值更小）
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.remove_doubles(threshold=0.0001)
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    
    # 自动减面：目标不超过 60,000 三角面
    # 提高阈值以保留头发等细长结构的细节，避免权重扭曲
    MAX_TRIANGLES = 60000
    depsgraph = bpy.context.evaluated_depsgraph_get()
    eval_obj = obj.evaluated_get(depsgraph)
    mesh = bpy.data.meshes.new_from_object(eval_obj)
    current_triangles = len(mesh.polygons)
    bpy.data.meshes.remove(mesh)
    
    print(f"[Blender] 当前三角面数: {{current_triangles}}")
    
    if current_triangles > MAX_TRIANGLES:
        ratio = MAX_TRIANGLES / current_triangles
        ratio = max(0.2, min(1.0, ratio))  # 最低保留20%，防止头发等结构过度损失
        print(f"[Blender] 面数过高，自动减面 ratio={{ratio:.3f}}")
        
        bpy.ops.object.modifier_add(type='DECIMATE')
        modifier = obj.modifiers[-1]
        modifier.ratio = ratio
        modifier.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        
        eval_obj = obj.evaluated_get(depsgraph)
        mesh = bpy.data.meshes.new_from_object(eval_obj)
        new_triangles = len(mesh.polygons)
        bpy.data.meshes.remove(mesh)
        print(f"[Blender] 减面后三角面数: {{new_triangles}}")
    else:
        print(f"[Blender] 面数合适，跳过减面")

    # 优化材质：压缩贴图尺寸到1024x1024（保留清晰度）
    for mat in bpy.data.materials:
        if mat.node_tree:
            for node in mat.node_tree.nodes:
                if node.type == 'TEX_IMAGE' and node.image:
                    tex_img = node.image
                    if tex_img.size[0] > 1024 or tex_img.size[1] > 1024:
                        tex_img.scale(1024, 1024)
                        print(f"[Blender] 压缩贴图: {{tex_img.name}} -> 1024x1024")

bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.fbx(
    filepath=r"{output_path}",
    use_selection=True,
    apply_unit_scale=True,
    axis_forward='-Z',
    axis_up='Y',
    embed_textures=True,
    path_mode='COPY',
    bake_space_transform=True
)
print("EXPORT_OK")
"""

    script_path = TOOL_DIR / f"temp_convert_{char_id}.py"
    with open(script_path, 'w', encoding='utf-8') as f:
        f.write(blender_script)

    blender_exe = config.get("blender_path", "blender")
    cmd = [blender_exe, "--background", "--python", str(script_path)]
    print(f"[步骤3] 执行: {' '.join(cmd)}")

    result = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace')

    script_path.unlink(missing_ok=True)

    if result.returncode == 0 and output_path.exists():
        print(f"[步骤3] Blender转FBX成功: {output_path}")
        return str(output_path)
    else:
        print(f"[步骤3] Blender转FBX失败")
        if result.stderr:
            print(f"  stderr: {result.stderr[:500]}")
        return None


# ==================== 4. Mixamo手动绑骨指引 ====================
def guide_mixamo(char_id, fbx_path):
    """输出Mixamo绑骨+动画下载指引，并检查已有动画"""
    anim_dir = get_anim_dir(char_id)
    anim_dir.mkdir(parents=True, exist_ok=True)

    # 统计已有动画
    existing_anims = []
    missing_anims = []
    for anim_info in MIXAMO_ANIMS:
        # 检查动画目录下是否有对应文件（可能是推荐名，也可能是用户自己选的名字）
        fbx_files = list(anim_dir.glob("*.fbx"))
        found = False
        for f in fbx_files:
            # 简单匹配：文件名包含搜索关键词就算有
            if anim_info["search"].lower() in f.stem.lower():
                found = True
                break
            if anim_info["name"].lower() in f.stem.lower():
                found = True
                break
        if found:
            existing_anims.append(anim_info)
        else:
            missing_anims.append(anim_info)

    total = len(MIXAMO_ANIMS)
    done_count = len(existing_anims)

    print(f"\n{'='*60}")
    print(f"  Mixamo绑骨+动画下载指引")
    print(f"{'='*60}")
    print(f"  上传文件: {fbx_path}")
    print(f"  动画目录: {anim_dir}")
    print(f"  已有动画: {done_count}/{total}")
    print(f"  下载设置: Format=FBX for Unity | Include Skin=勾 | In Place=勾 | FPS=30")
    print(f"")

    if done_count >= total:
        print(f"  ✅ 所有动画已齐全，跳过Mixamo步骤")
        print(f"{'='*60}")
        return

    if missing_anims:
        print(f"  还需下载 {len(missing_anims)} 个动画:")
        for anim_info in missing_anims:
            print(f"    {anim_info['key']:6s} | 搜: {anim_info['search']:12s} | 选: {anim_info['name']:20s}")
        print(f"")
        print(f"  下载后放到: {anim_dir}/")
        print(f"  文件名保持Mixamo默认即可（如 Jog Forward.fbx）")

    print(f"{'='*60}")
    print(f"  完成后按回车继续...")
    try:
        input()
    except EOFError:
        print(f"[注意] 非交互式模式，跳过等待。请手动下载动画后重新运行脚本。")


# ==================== 5. 复制到Godot项目 ====================
def copy_to_godot(char_id):
    """复制动画FBX到Godot项目目录，并重命名为规范名"""
    anim_dir = get_anim_dir(char_id)
    GODOT_ASSETS_DIR.mkdir(parents=True, exist_ok=True)

    print(f"[步骤5] 复制到Godot项目")
    print(f"[步骤5] 源目录: {anim_dir}")
    print(f"[步骤5] 目标: {GODOT_ASSETS_DIR}")

    copied = 0
    skipped = 0

    for anim_info in MIXAMO_ANIMS:
        key = anim_info["key"]
        target_name = f"{char_id}_{key}.fbx"
        dst = GODOT_ASSETS_DIR / target_name

        # 目标已存在，跳过
        if dst.exists() and dst.stat().st_size > 0:
            print(f"  [跳过] {target_name} 已存在")
            skipped += 1
            copied += 1
            continue

        # 在anim目录里找匹配的源文件
        src_file = None
        if anim_dir.exists():
            # 优先匹配推荐名
            rec_name = anim_info["name"] + ".fbx"
            candidate = anim_dir / rec_name
            if candidate.exists() and candidate.stat().st_size > 0:
                src_file = candidate
            else:
                # 模糊匹配：文件名包含搜索关键词
                for f in anim_dir.glob("*.fbx"):
                    if anim_info["search"].lower() in f.stem.lower():
                        src_file = f
                        break

        if not src_file:
            print(f"  [跳过] {key} 动画不存在（{anim_info['search']}.fbx）")
            continue

        shutil.copy(src_file, dst)
        # 删除.import让Godot重新导入
        import_file = str(dst) + '.import'
        if os.path.exists(import_file):
            os.remove(import_file)
        print(f"  [OK] {src_file.name} -> {target_name}")
        copied += 1

    total = len(MIXAMO_ANIMS)
    print(f"[步骤5] 复制完成: {copied}/{total} 个动画（跳过{skipped}个已存在的）")
    if copied - skipped > 0:
        print(f"[步骤5] 新增了文件，请重启Godot编辑器以重新导入")
    return copied


# ==================== 主流程 ====================
def main():
    parser = argparse.ArgumentParser(description="决竞球3D建模自动化工具")
    parser.add_argument("char_id", help="角色ID (如 player1, player5)")
    parser.add_argument("--image", "-i", default=None, help="即梦T-pose参考图路径（已有则可不填）")
    parser.add_argument("--template", "-t", default=None,
                       help=f"混元3D模板 (可选: {', '.join(HUNYUAN_TEMPLATES.keys())})")
    parser.add_argument("--format", "-f", default=None, choices=["FBX", "STL", "USDZ"],
                       help="输出格式 (可选: FBX/STL/USDZ，留空默认GLB+OBJ)")
    parser.add_argument("--skip-api", action="store_true", help="跳过混元API，直接手动模式")
    parser.add_argument("--skip-mixamo", action="store_true", help="跳过Mixamo步骤（已绑好骨时用）")
    parser.add_argument("--list-templates", action="store_true", help="列出所有可用模板")
    parser.add_argument("--force", action="store_true", help="强制重新生成，不跳过已有文件")
    parser.add_argument("--status", action="store_true", help="仅查看角色当前完成状态，不执行任何操作")
    args = parser.parse_args()

    if args.list_templates:
        print("混元3D可用模板:")
        for key, desc in HUNYUAN_TEMPLATES.items():
            print(f"  {key:30s} {desc}")
        return

    char_id = args.char_id

    # 仅查看状态
    if args.status:
        status = check_already_done(char_id)
        print(f"\n{'='*50}")
        print(f"  角色 {char_id} 当前状态")
        print(f"{'='*50}")
        print(f"  参考图:   {'✅ 已存在' if status['ref_image'] else '⬜ 缺失'}")
        print(f"  基础FBX:  {'✅ 已存在' if status['base_fbx'] else '⬜ 缺失'}")
        print(f"  动画文件:  {status['anim_count']}/{len(MIXAMO_ANIMS)} 个")
        print(f"  Godot导入: {status['godot_count']}/{len(MIXAMO_ANIMS)} 个")
        print(f"  全部完成:  {'✅ 是' if status['all_done'] else '⬜ 否'}")
        print(f"{'='*50}")
        return

    print(f"{'='*60}")
    print(f"  决竞球3D建模自动化工具")
    print(f"  角色ID: {char_id}")
    if args.image:
        print(f"  参考图: {args.image}")
    if args.template:
        print(f"  混元模板: {args.template}")
    if args.format:
        print(f"  输出格式: {args.format}")
    if args.force:
        print(f"  ⚠  强制模式：不跳过已有文件")
    print(f"{'='*60}")

    # 先检查状态
    status = check_already_done(char_id)
    if status["all_done"] and not args.force:
        print(f"\n✅ 角色 {char_id} 已全部完成，无需重复工作。")
        print(f"   如需强制重新生成，请加 --force 参数")
        return

    # 加载配置
    config = load_config()

    # 命令行覆盖
    if args.format:
        config["result_format"] = args.format

    # 确保目录存在
    REF_IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    get_anim_dir(char_id).mkdir(parents=True, exist_ok=True)
    GODOT_ASSETS_DIR.mkdir(parents=True, exist_ok=True)

    # ============= 步骤1: 参考图 =============
    print(f"\n--- 步骤1: 参考图 ---")
    if args.image:
        image_path = prepare_tpose_image(char_id, args.image)
    else:
        # 没传image参数，检查是否已有参考图
        ref = get_ref_image(char_id)
        if ref.exists():
            image_path = str(ref)
            print(f"[步骤1] 使用已有参考图: {ref}")
        else:
            print(f"[ERROR] 未找到参考图，也没有提供 --image 参数")
            print(f"        请将图片放到 {REF_IMAGE_DIR}/{char_id}.png")
            print(f"        或使用 --image <路径> 指定图片")
            sys.exit(1)

    # ============= 步骤2: 混元3D生模型 =============
    print(f"\n--- 步骤2: 混元3D生成模型 ---")
    base_fbx = get_base_fbx(char_id)
    if base_fbx.exists() and base_fbx.stat().st_size > 0 and not args.force:
        print(f"[步骤2] 基础FBX已存在，跳过: {base_fbx}")
        model_path = str(base_fbx)
    elif args.skip_api:
        model_path = _manual_hunyuan(char_id, image_path)
    else:
        model_path = generate_3d_model_api(config, char_id, image_path)

    if not model_path:
        print(f"\n[ERROR] 模型生成失败，请手动完成后重新运行脚本")
        return

    # ============= 步骤3: GLB转FBX =============
    print(f"\n--- 步骤3: 格式转换 ---")
    fbx_path = convert_glb_to_fbx(config, char_id, model_path)
    if not fbx_path:
        print(f"\n[ERROR] FBX获取失败")
        return

    # ============= 步骤4: Mixamo绑骨+动画 =============
    if not args.skip_mixamo:
        print(f"\n--- 步骤4: Mixamo绑骨+动画 ---")
        guide_mixamo(char_id, fbx_path)
    else:
        print(f"\n--- 步骤4: Mixamo（跳过）---")

    # ============= 步骤5: 复制到Godot =============
    print(f"\n--- 步骤5: 复制到Godot ---")
    copied = copy_to_godot(char_id)

    # ============= 最终汇总 =============
    final_status = check_already_done(char_id)
    print(f"\n{'='*60}")
    print(f"  流程完成汇总 — {char_id}")
    print(f"{'='*60}")
    print(f"  参考图:   {'✅' if final_status['ref_image'] else '⬜'}  {get_ref_image(char_id)}")
    print(f"  基础FBX:  {'✅' if final_status['base_fbx'] else '⬜'}  {get_base_fbx(char_id)}")
    print(f"  动画目录: {'✅' if final_status['anim_count'] >= len(MIXAMO_ANIMS) else '⬜'}  {get_anim_dir(char_id)} ({final_status['anim_count']}/{len(MIXAMO_ANIMS)}个)")
    print(f"  Godot目录: {'✅' if final_status['godot_count'] >= len(MIXAMO_ANIMS) else '⬜'}  {GODOT_ASSETS_DIR} ({final_status['godot_count']}/{len(MIXAMO_ANIMS)}个)")
    print(f"")
    if final_status["all_done"]:
        print(f"  ✅ 全部完成！请重启Godot编辑器")
    else:
        print(f"  ⚠  还有未完成项，补齐后重新运行脚本即可（不会重复工作）")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
