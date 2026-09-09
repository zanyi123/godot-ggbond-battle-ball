# 3D 技能特效 Codex + Blender 制作手册

> 决竞球 Battle Ball 3D 特效制作专用  
> 创建日期：2026-08-06  
> 配套文档：`docs/3D技能特效实现方案大纲.md`、`docs/3D特效资源完全指南.md`

---

## 一、可以做什么 & 不能做什么

### ✅ Codex + Blender 适合做的

| 特效类型 | 说明 | 产出格式 |
|---|---|---|
| **光球/能量核心** | 自发光球体，可动画（脉冲/缩放） | GLB（MeshInstance3D + 自发光材质） |
| **冲击波/涟漪** | 圆环扩散动画（用于击中、爆炸） | GLB（Shape Key 动画） |
| **护盾/光环** | 透明球体/光环，带呼吸动画 | GLB（MeshInstance3D + 透明自发光） |
| **粒子发射器形状** | 低多边形粒子发射几何体（六角星、闪电形状） | GLB（MeshInstance3D，作为粒子形状） |
| **拖尾轨迹** | 可沿路径变形的几何体（球的光尾） | GLB（Curve Path + 几何体） |
| **场景环境特效** | 场地区域的视觉变化（冰面、草地） | GLB（平面 + 材质动画） |

### ❌ 不适合做的

| 特效类型 | 原因 | 替代方案 |
|---|---|---|
| **真正的粒子系统** | Blender 粒子导出到 Godot 需重设 | Godot 内置 GPUParticles3D + Binbun3D 素材 |
| **动态火花/闪电** | 实时粒子模拟在 Blender 做不好 | Godot Shader + CPUParticles3D |
| **复杂流体** | 计算量大，不适合实时 | Godot 着色器模拟 |

### 🎯 正确分工

```
Blender + Codex 负责：
  → 静态/可预判动画的 3D 特效几何体
  → 材质动画（自发光脉冲、颜色渐变）
  → 粒子发射器的形状网格
  → 冲击波/护盾等可预烘焙动画

Godot 负责：
  → 实时粒子（GPUParticles3D）
  → 动态触发/销毁
  → 元素颜色映射
  → 与技能系统集成
```

---

## 二、6 元素视觉规范（与现有代码一致）

### 2.1 元素配色（摘自 fx_element_config.json）

| 元素 | 中文名 | 主色 | 发光色 | 代表效果 |
|---|---|---|---|---|
| FIRE | 雷火 | `#FF6633` 橙红 | `#FF994D` 亮橙 | 火球、爆炸、闪电 |
| DIAMOND | 金刚 | `#D9BF4D` 金黄 | `#FFE680` 亮金 | 金属护盾、壁垒 |
| ICE | 冰雪 | `#66CCFF` 冰蓝 | `#99E5FF` 亮蓝 | 冰冻、冰面、雪花 |
| NATURE | 草木 | `#4DCC4D` 翠绿 | `#80FF80` 亮绿 | 藤蔓、草地、荆棘 |
| EARTH | 大地 | `#B38C59` 棕褐 | `#D9B380` 亮棕 | 岩石、尘土、地震 |
| DREAM | 梦幻 | `#B380E6` 紫粉 | `#D999FF` 亮紫 | 星光、幻影、迷雾 |

### 2.2 特效参数（与现有配置一致）

| 元素 | 粒子速度 | 粒子大小 | 拖尾长度 | 冲击波半径 |
|---|---|---|---|---|
| FIRE | 2.0 | 0.5 | 15.0 | 8.0 |
| DIAMOND | 1.5 | 0.8 | 8.0 | 6.0 |
| ICE | 1.2 | 0.4 | 12.0 | 5.0 |
| NATURE | 0.8 | 0.6 | 10.0 | 7.0 |
| EARTH | 2.5 | 1.0 | 6.0 | 12.0 |
| DREAM | 1.0 | 0.3 | 20.0 | 4.0 |

---

## 三、核心提示词（按优先级）

### 【P0】任务 1：6 元素能量核心（光球）

**用途**：球被技能激活后的外观变化、技能释放时的手部光球

#### Codex 提示词

```
在 Blender 中为 6 个元素分别创建一个能量核心（光球）3D 模型。

【规格 - 每个元素一个】
- 形状：球体，直径 40 单位
- 风格：低多边形 + 自发光（卡通游戏风格）
- 面数：icosphere，细分级别 2（约 20 面，低多边形）

【动画 - 关键！】
每个光球需要一个 Shape Key 动画（用于 Godot 播放）：
- 动画 1：pulse（脉冲）
  - 时长 1.0 秒，循环
  - 效果：球体从 1.0 倍 → 1.2 倍 → 1.0 倍缩放
  - 同时发光强度从 0.5 → 1.0 → 0.5

- 动画 2：spawn（生成）
  - 时长 0.5 秒，单次
  - 效果：球体从 0.0 倍缩放 → 1.0 倍

- 动画 3：fade（消散）
  - 时长 0.5 秒，单次
  - 效果：球体从 1.0 倍 → 0.0 倍 + 透明度淡出

【材质 - 每个元素不同颜色】
| 元素 | albedo | emission |
|---|---|---|
| FIRE | #FF6633 | #FF3300 |
| DIAMOND | #D9BF4D | #FFCC00 |
| ICE | #66CCFF | #0099FF |
| NATURE | #4DCC4D | #00CC00 |
| EARTH | #B38C59 | #8B4513 |
| DREAM | #B380E6 | #9900FF |

材质设置：
- Surface: Standard
- Metallic: 0.1
- Roughness: 0.3
- Emission Energy: 0.8
- Alpha: 0.85（半透明）

【导出要求 - 关键】
1. 每个元素单独导出为 GLB
2. 文件名：
   - spirit_fire_core.glb
   - spirit_diamond_core.glb
   - spirit_ice_core.glb
   - spirit_nature_core.glb
   - spirit_earth_core.glb
   - spirit_dream_core.glb

3. 导出设置：
   - Format: GLB
   - Include: ✅ Geometry, ✅ Materials, ✅ Animation, ❌ Skin
   - Transform: ✅ Apply Modifiers
   - Up Axis: Y

4. 输出路径：
   E:/项目储存/决竞球battle-ball/建模素材库/3D模型素材/spirits/

【验证】
导出后在 Blender 中重新导入检查：
- 播放 Shape Key 动画能正常工作
- 材质颜色正确
- 文件大小合理（每个 < 500KB）
```

#### 预期产出

```
建模素材库/3D模型素材/spirits/
├── spirit_fire_core.glb      ← 雷火球
├── spirit_diamond_core.glb   ← 金刚球
├── spirit_ice_core.glb       ← 冰雪球
├── spirit_nature_core.glb    ← 草木球
├── spirit_earth_core.glb     ← 大地球
└── spirit_dream_core.glb     ← 梦幻球
```

#### Godot 接入示例

```gdscript
# 加载元素光球
const SPIRIT_CORE_PATHS := {
    "FIRE":     "res://建模素材库/3D模型素材/spirits/spirit_fire_core.glb",
    "DIAMOND":  "res://建模素材库/3D模型素材/spirits/spirit_diamond_core.glb",
    "ICE":      "res://建模素材库/3D模型素材/spirits/spirit_ice_core.glb",
    "NATURE":   "res://建模素材库/3D模型素材/spirits/spirit_nature_core.glb",
    "EARTH":    "res://建模素材库/3D模型素材/spirits/spirit_earth_core.glb",
    "DREAM":    "res://建模素材库/3D模型素材/spirits/spirit_dream_core.glb",
}

# 创建光球特效
func spawn_spirit_core(element: String, position: Vector3) -> void:
    var core_scene = load(SPIRIT_CORE_PATHS.get(element, SPIRIT_CORE_PATHS["FIRE"]))
    var core = core_scene.instantiate()
    
    # 深拷贝 AnimationLibrary（防止共享问题）
    for lib_name in core.get_animation_library_list():
        var lib = core.get_animation_library(lib_name)
        core.remove_animation_library(lib_name)
        core.add_animation_library(lib.duplicate(true))
    
    core.position = position
    viewport_3d.add_child(core)
    
    # 播放生成动画 → 切换到脉冲动画
    var anim_player = core.get_node("AnimationPlayer")
    anim_player.play("spawn")
    anim_player.animation_finished.connect(func(anim):
        if anim == "spawn":
            anim_player.play("pulse")
    )
```

---

### 【P0】任务 2：6 元素冲击波/涟漪

**用途**：球击中效果、技能释放冲击波

#### Codex 提示词

```
在 Blender 中为 6 个元素分别创建一个冲击波（扩散圆环）3D 模型。

【规格 - 通用】
- 形状：扁平圆环（Torus，内半径 5，外半径 8，管半径 0.3）
- 风格：低多边形 + 自发光边缘
- 面数：低多边形（圆环 48 段）
- 初始尺寸：圆环直径 16 单位

【动画 - Shape Key】
每个冲击波需要一个扩散动画：
- 动画 1：expand（扩散）
  - 时长 0.8 秒，单次
  - 效果：圆环从 1.0 倍 → 5.0 倍缩放 + 透明度 1.0 → 0.0
  - 用于：技能命中时的冲击波扩散

- 动画 2：pulse（脉冲）
  - 时长 0.6 秒，循环
  - 效果：圆环尺寸 1.0 → 1.15 → 1.0 + 透明度波动
  - 用于：持续效果的呼吸脉冲

【材质 - 与能量核心同色】
每个元素的 albedo 和 emission 与能量核心保持一致。

额外：给圆环的边缘加一个光棱效果
- 用 Wireframe Modifier 叠一层线框
- 线框材质：自发光，alpha=0.3

【导出要求】
- 格式：GLB
- 文件名：spirit_*_shockwave.glb（* = fire/diamond/ice/nature/earth/dream）
- Include: ✅ Geometry, ✅ Materials, ✅ Animation
- 输出路径：E:/.../spirits/

【验证】
- 播放 expand 动画能看到圆环扩散 + 淡出
- 文件大小每个 < 300KB
```

#### Godot 接入示例

```gdscript
# 冲击波触发
func spawn_shockwave(element: String, position: Vector3, radius: float = 8.0) -> void:
    var shock_path = SPIRIT_SHOCKWAVE_PATHS.get(element)
    var shock_scene = load(shock_path)
    var shock = shock_scene.instantiate()
    
    # 深拷贝动画库
    for lib_name in shock.get_animation_library_list():
        var lib = shock.get_animation_library(lib_name)
        shock.remove_animation_library(lib_name)
        shock.add_animation_library(lib.duplicate(true))
    
    shock.position = position
    viewport_3d.add_child(shock)
    
    # 播放扩散动画
    var anim = shock.get_node("AnimationPlayer")
    anim.play("expand")
    anim.animation_finished.connect(func(a):
        if a == "expand":
            shock.queue_free()  # 播完销毁
    )
```

---

### 【P1】任务 3：6 元素护盾/光环

**用途**：球员状态效果（护盾、光环、持续 buff 视觉）

#### Codex 提示词

```
在 Blender 中为 6 个元素分别创建一个护盾/光环 3D 模型。

【规格 - 护盾】
- 形状：椭球体（X:20, Y:30, Z:20 单位），包裹球员
- 风格：透明 + 自发光边缘
- 面数：icosphere 细分 2（低多边形）

【规格 - 光环】
- 形状：扁平圆环（放在球员脚下）
- 半径：25 单位
- 管半径：0.5 单位
- 面数：圆环 64 段

【动画】
护盾：
- 动画 1：intake（吸收）
  - 时长 1.0 秒，单次
  - 效果：透明度 0.0 → 0.8 + 尺寸 0.8 → 1.2

- 动画 2：breath（呼吸）
  - 时长 2.0 秒，循环
  - 效果：透明度 0.7 → 0.9 → 0.7 + 轻微缩放

- 动画 3：break（破裂）
  - 时长 0.5 秒，单次
  - 效果：透明度 0.8 → 0.0 + 尺寸 1.0 → 1.5

光环：
- 动画：spin（旋转）
  - 时长 2.0 秒，循环
  - 效果：绕 Y 轴旋转 360°

【材质 - 半透明自发光】
- Surface: Standard
- Alpha: 0.3（护盾）/ 0.5（光环）
- Emission Energy: 1.2
- 每个元素颜色与能量核心一致

【导出】
- 每个元素导出两个文件：
  - spirit_*_shield.glb（护盾）
  - spirit_*_aura.glb（光环）
- 输出路径：spirits/

【验证】
- 护盾在透明背景上可见（半透明）
- 光环旋转动画流畅
- 文件大小每个 < 500KB
```

#### 预期产出

```
spirits/
├── spirit_fire_shield.glb      ← 雷火护盾
├── spirit_fire_aura.glb        ← 雷火光环
├── spirit_diamond_shield.glb   ← 金刚护盾
├── spirit_diamond_aura.glb     ← 金刚光环
├── ... (其他 4 元素)
└── spirit_dream_aura.glb       ← 梦幻光环
```

---

### 【P2】任务 4：元素形状粒子（发射器形状）

**用途**：GPUParticles3D 的粒子形状，提供视觉辨识度

#### Codex 提示词

```
在 Blender 中为 6 个元素分别创建一个粒子发射器形状（低多边形几何体）。

【规格 - 每个元素一个独特形状】
| 元素 | 形状描述 |
|---|---|
| FIRE | 火焰形状（圆锥 + 锯齿边缘），高度 8 单位 |
| DIAMOND | 钻石晶体（八面体），高度 6 单位 |
| ICE | 雪花晶体（星形六角），直径 8 单位 |
| NATURE | 叶子形状（水滴 + 叶脉），长度 8 单位 |
| EARTH | 岩石碎片（不规则多面体），尺寸 6 单位 |
| DREAM | 星光（四角星），直径 8 单位 |

【技术要求】
- 每个形状是独立的 Mesh（不含动画）
- 面数控制在 20-50 面（低多边形）
- 所有顶点焊接（Merge by Distance），确保是流形网格
- Y 轴朝上站立

【材质】
- 每个元素对应配色（albedo + emission）
- 不需要动画（粒子自己会动，形状只是外观）

【导出】
- 格式：GLB（无动画）
- 文件名：spirit_*_particle_shape.glb
- Include: ✅ Geometry, ✅ Materials, ❌ Animation
- 输出路径：spirits/particle_shapes/

【验证】
- 每个形状单独导出后在 Blender 中检查
- 无破面、无重复顶点
- 文件大小每个 < 50KB
```

#### Godot 接入示例

```gdscript
# 用作 GPUParticles3D 的 Draw Pass 形状
func create_element_particles(element: String, position: Vector3) -> GPUParticles3D:
    var particles = GPUParticles3D.new()
    particles.process_material = ParticleProcessMaterial.new()
    particles.process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
    particles.process_material.emission_sphere_radius = 2.0
    particles.process_material.direction = Vector3(0, 1, 0)
    particles.process_material.spread = 30.0
    
    # 设置元素颜色
    var color = ELEMENT_COLORS.get(element, Color.WHITE)
    particles.process_material.color = color
    particles.process_material.color_ramp = ParticleProcessMaterial.LERP_RAMP
    
    # 加载元素形状作为粒子外观
    var shape_path = SPIRIT_SHAPE_PATHS.get(element)
    var shape_mesh = load(shape_path + ".glb")
    # 注意：Godot 中粒子形状需要用 Mesh 资源
    # 实际使用时可能需要将 GLB 中的 MeshInstance3D 提取为 Mesh
    
    particles.amount = 200
    particles.lifetime = 1.5
    particles.one_shot = true
    particles.global_position = position
    
    return particles
```

---

### 【P3】任务 5：场地环境特效

**用途**：FIELD 类技能的区域视觉变化（冰面、草地、石墙等）

#### Codex 提示词

```
在 Blender 中为 6 个元素分别创建一个场地区域特效（平面 + 材质动画）。

【规格 - 通用】
- 形状：圆形平面，半径 100 单位，厚度 0.5 单位
- 面数：低多边形（Circle 32 段）

【每个元素的独特视觉】
| 元素 | 表面效果 | 边缘效果 |
|---|---|---|
| FIRE | 红色脉动发光地面 | 火焰粒子装饰（小圆锥） |
| DIAMOND | 金色金属光泽地面 | 水晶尖刺（小八面体） |
| ICE | 冰蓝色半透明地面 | 冰晶装饰（小六角星） |
| NATURE | 翠绿色流动地面 | 小草/藤蔓装饰（小叶片） |
| EARTH | 棕色龟裂地面 | 岩石碎片装饰（小多面体） |
| DREAM | 紫色迷幻流动地面 | 星光装饰（小四角星） |

【动画 - 材质驱动】
每个场地特效需要：
- 动画 1：appear（出现）
  - 时长 0.5 秒，单次
  - 效果：平面从 0.0 尺寸 → 1.0 + 材质透明度 0 → 1

- 动画 2：sustain（持续）
  - 时长 3.0 秒，循环
  - 效果：自发光强度 0.8 → 1.2 → 0.8 脉动

- 动画 3：disappear（消失）
  - 时长 0.5 秒，单次
  - 效果：尺寸 1.0 → 0.0 + 透明度 1 → 0

【导出】
- 格式：GLB
- 文件名：spirit_*_field_zone.glb
- Include: ✅ Geometry, ✅ Materials, ✅ Animation
- 输出路径：spirits/field_zones/

【验证】
- appear/disappear 动画流畅
- 文件大小每个 < 1MB
```

---

## 四、Codex + Blender 操作流程

### 步骤 1：环境准备

确保以下工具已安装：

```bash
# 1. Blender（4.0+ 推荐）
# 下载地址：blender.org

# 2. Codex CLI（已安装）
codex --version  # 确认可用

# 3. blender-mcp（已配置）
# 确保 Blender 中已安装 MCP addon
# 侧边栏 N 键 → BlenderMCP → Connect
```

### 步骤 2：单次 Codex 会话完成一组元素

**关键：一次处理一个元素的所有特效，减少对话轮次。**

```
codex
>> 读取 E:/.../character_colors.json 配置，
>> 为 FIRE 元素创建所有 3 D 特效（能量核心+冲击波+护盾+光环+粒子形状+场地），
>> 一次性导出所有 GLB 文件到 spirits/ 目录。
>> 不要分步。
```

### 步骤 3：验证每个 GLB

在 Blender 中：
1. File → Import → glTF → 选择导出的 GLB
2. 检查：播放所有 Shape Key 动画是否正常
3. 检查：材质颜色是否正确
4. 检查：文件大小是否合理（< 1MB）

在 Godot 中：
1. 将 GLB 放入 `建模素材库/3D模型素材/spirits/`
2. 重启 Godot 让 .import 生成
3. 用脚本加载 GLB，检查是否能正常实例化和播放动画

---

## 五、额度节省策略

### 5.1 按元素分组批量处理

```
第一轮：FIRE + ICE（冷热对比，验证管线）
第二轮：DIAMOND + EARTH（金属/土系）
第三轮：NATURE + DREAM（自然/魔法）
```

### 5.2 单次指令完成多文件

```
❌ 低效：
"创建 FIRE 能量核心" → "创建 FIRE 冲击波" → ...（6 次对话/元素）

✅ 高效：
"为 FIRE 元素一次性创建：能量核心 + 冲击波 + 护盾 + 光环 + 粒子形状 + 场地，
导出所有 GLB 文件，不要分步。"（1 次对话/元素）
```

### 5.3 额度预估

| 任务 | 单次消耗 | 6 元素合计 |
|---|---|---|
| 能量核心（批量） | ~10 | ~60 |
| 冲击波（批量） | ~8 | ~48 |
| 护盾+光环（批量） | ~15 | ~90 |
| 粒子形状（批量） | ~5 | ~30 |
| 场地特效（批量） | ~15 | ~90 |
| **合计** | | **~318** |

建议：优先做 P0（能量核心+冲击波），验证管线后再批量做其他。

---

## 六、Godot 集成架构

### 6.1 特效管理器接口

```gdscript
# scripts/systems/spirit_system/skill_fx_manager_3d.gd

class_name SkillFxManager3D
extends Node

# 元素 → GLB 路径映射
const SPIRIT_CORE_PATHS := { ... }     # 能量核心
const SPIRIT_SHOCKWAVE_PATHS := { ... } # 冲击波
const SPIRIT_SHIELD_PATHS := { ... }    # 护盾
const SPIRIT_AURA_PATHS := { ... }      # 光环
const SPIRIT_FIELD_ZONE_PATHS := { ... } # 场地

# 活跃特效追踪
var _active_effects: Dictionary = {}  # { effect_id: fx_node }

# 触发技能特效
func trigger_skill_fx(skill_id: String, element: String, 
                       caster_pos: Vector3, target_pos: Vector3) -> void:
    # 1. 创建元素核心（在 caster 位置）
    spawn_element_core(element, caster_pos)
    
    # 2. 如果是球技能，创建球特效
    if skill_id.begins_with("ball_"):
        spawn_ball_fx(element, caster_pos, target_pos)
    
    # 3. 如果是球员技能，创建球员特效
    elif skill_id.begins_with("player_"):
        spawn_player_fx(element, caster_pos)
    
    # 4. 如果是场地技能，创建场地特效
    elif skill_id.begins_with("field_"):
        spawn_field_fx(element, target_pos)
    
    # 5. 创建冲击波（在 target 位置）
    spawn_shockwave(element, target_pos)

# 清理所有特效
func clear_all() -> void:
    for fx in _active_effects.values():
        if is_instance_valid(fx):
            fx.queue_free()
    _active_effects.clear()
```

### 6.2 与 SubViewport 的关系

```
CharacterBody2D（2D 物理层）
  └── SubViewport（512×512 或 2560×1440）
       ├── Camera3D
       ├── ModelSlot → 3D 球员模型
       ├── SpiritCore（GLB 能量核心）← 本手册产出
       ├── SpiritShockwave（GLB 冲击波）← 本手册产出
       ├── SpiritShield（GLB 护盾）← 本手册产出
       ├── SpiritAura（GLB 光环）← 本手册产出
       ├── SpiritFieldZone（GLB 场地）← 本手册产出
       └── GPUParticles3D（实时粒子，Binbun3D 素材）
```

### 6.3 性能优化

| 优化项 | 方案 |
|---|---|
| 动画共享 | 同一元素的 core/shockwave 共享 AnimationLibrary |
| 透明度排序 | 半透明材质用 Transparency > 0，避免 z-fighting |
| 贴图压缩 | 所有纹理用 VRAM Compressed，不要用未压缩 |
| 实例化 | 同类特效使用 Instance3D 而非独立 MeshInstance3D |
| 对象池 | 结束的特效回收到池，不销毁 |

---

## 七、绝对禁止事项

| 禁止 | 原因 |
|---|---|
| ❌ 让 Codex 做真正的粒子模拟 | Blender 粒子导出后 Godot 要重设，浪费额度 |
| ❌ 不用 Shape Key 而用关键帧动画 | 3D 变换动画在 GLB 里会丢失 |
| ❌ 忽略 AnimationLibrary 共享 | 多个特效会互相影响 |
| ❌ 元素颜色不一致 | 与现有 fx_element_config.json 冲突 |
| ❌ 不做深拷贝 | 多球员同屏时动画串台 |

---

## 八、与现有素材的关系

| 来源 | 用途 | 本手册补充 |
|---|---|---|
| Binbun3D itch.io | 真正的粒子特效（GPUParticles3D） | 提供元素形状 + 颜色 |
| VFX Sketchbook GitHub | 开源特效参考 | 补充冲击波/护盾 |
| EffectBlocks Demo | 100+ 免费特效 | 补充低多边形风格 |
| **本手册（Codex+Blender）** | 预烘焙动画的 3D 特效 | 能量核心/冲击波/护盾/光环/场地 |

**核心定位**：Codex+Blender 制作的是**"可预判动画"**的特效，作为 Godot 粒子系统的**补充**，而非替代。

---

*文档版本：V1.0 | 创建于 2026-08-06*
