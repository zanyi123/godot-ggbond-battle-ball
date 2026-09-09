# Codex + Blender 建模工作手册（V2）

> 决竞球 Battle Ball 3D 化工作专用  
> 创建日期：2026-08-06 | 更新日期：2026-08-06  
> **核心原则：基于已有资产优化，不重造轮子**

---

## 一、已有 3D 资产盘点（重要！）

### 1.1 现有可用资产

| 资产 | 路径 | 状态 | 备注 |
|---|---|---|---|
| **player1 身体** | `建模素材库/3D模型素材/player1_base.glb` | ✅ 完整 | 含贴图+骨骼+动画 |
| **player1 动画** | `player1动作/` 下 4 个 FBX | ✅ 完整 | Idle/Jog_Forward/Goalie_Throw/Goalkeeper_Catch |
| **通用 GLB** | `assets/characters/avatars/` 下 4 个 GLB | ✅ 可用 | 其他球员默认共用 |
| **决竞球** | `建模素材库/3D模型素材/battleball.glb` | ✅ 可用 | 含 PBR 贴图 |
| **通用球场** | `决竞球场地.glb` | ❌ 不可用 | 仅 4.4KB，需重建 |

### 1.2 现有代码参数（已调优）

```gdscript
# 摘自 scripts/test/player_3d_test.gd
const PROXY_SCALE: float = 70.0           # 模型缩放
const PROXY_MODEL_HEIGHT: float = 49.86    # 模型实际高度
const BALL_SCALE_3D: float = 30.0         # 球缩放

# 摘自 scripts/battle/player.gd
# ModelSlot 扶正矩阵：绕 X 轴 -90°
Basis(Vector3.RIGHT, deg_to_rad(-90.0))

# 小相机斜视 45°
Basis(Vector3.RIGHT, deg_to_rad(-45.0))
```

### 1.3 已知历史问题（必须规避）

| 问题 | 根因 | 解决方案 | 禁止事项 |
|---|---|---|---|
| **Mixamo FBX 白膜** | Mixamo 导出丢贴图 | Blender 中转合并贴图+动画为 GLB | ❌ 不要直接用 Mixamo FBX |
| **GLB 尺寸 105 米** | 混元/Mixamo 用厘米导出 | 导出前在 Blender 缩放到 1.7 米 | ❌ 不要在 Godot 里硬调缩放 |
| **GLB 朝向躺平** | 骨骼+Z 朝上 | Blender 导出前校正朝向（+Y 站立） | ❌ 不要依赖 Godot 扶正 |
| **AnimationLibrary 共享** | Godot 缓存机制 | 运行时 `duplicate(true)` 深拷贝 | ❌ 不要直接 modify 共享资源 |
| **模型叠加** | 4 个 FBX mesh 同时渲染 | 只保留 idle mesh，其他隐藏 mesh | ❌ 不要同时显示多个 FBX |

---

## 二、Codex + Blender 分工策略

### 2.1 Codex 负责（省额度版）

| 任务 | 说明 | 预估消耗 |
|---|---|---|
| **球场建模** | 创建真实 3D 球场，导出为标准尺寸 GLB | ~15 credits |
| **材质修复** | 修复现有 GLB 的白膜/贴图丢失问题 | ~10 credits |
| **模型变体** | 基于 player1 为其他球员创建颜色变体 | ~20 credits |
| **尺寸标准化** | 批量缩放所有 GLB 到正确尺寸 | ~10 credits |

### 2.2 手动操作（不费额度）

| 任务 | 工具 | 说明 |
|---|---|---|
| UV 展开 | Blender | AI 不擅长 UV，手动做 |
| 精细雕刻 | Blender/ZBrush | 细节需要手感 |
| 骨骼绑定 | Blender/Mixamo | 手动绑定更可靠 |
| 动画制作 | Mixamo | Mixamo 自动化程度高 |

---

## 三、核心提示词（按优先级）

### 【P0】任务 1：重建 3D 球场

**为什么不重造角色？** 已有 player1 GLB + 通用 GLB 可用，当前最大缺口是**球场**（只有 4.4KB 占位）。

#### Codex 提示词

```
在 Blender 中创建一个真实比例的 3D 决竞球球场。

【尺寸规格 - 必须严格遵守】
- 场地尺寸：1300 单位宽(X) × 780 单位深(Z)
- 单位 = 厘米（与现有 GLB 坐标系一致）
- 场地高度 Y=0 为地面

【场地元素】
1. 草地平面：
   - 主色：深绿色 (color: #1F3320)
   - 尺寸：1300 × 780
   - 轻微起伏（用 Displacement Modifier + Noise Texture）
   - 草地纹理：用 Procedural Texture，不要用贴图

2. 边界线：
   - 4 条白色边界线，宽度 20 单位，高度 1 单位
   - 位置：场地四周，离边缘 10 单位

3. 中线：
   - 1 条白色横线，贯穿场地宽度
   - 宽度 10 单位

4. 中圈：
   - 半径 150 单位的白色圆圈
   - 宽度 10 单位

5. 球门区（两端各一个）：
   - 矩形区域，深 150 单位、宽 600 单位
   - 白色边线

6. 球门（两个）：
   - 位于球门区中央
   - 宽度 300 单位、高度 240 单位
   - 金属框（圆柱，直径 5 单位）
   - 球网（半透明白色平面 + Wireframe Modifier）

【材质要求】
- 草地：Diffuse BSDF，roughness=0.9
- 边界线：Diffuse BSDF，albedo=#FFFFFF
- 球门金属：Metal BSDF，metallic=0.9，roughness=0.3
- 球网：Diffuse BSDF，alpha=0.3

【导出要求 - 关键！】
1. 导出前：全选所有物体，Apply Rotation & Scale (Ctrl+A)
2. 确保模型 Y 轴朝上站立
3. 导出为 GLB：
   - File → Export → glTF 2.0 (.glb)
   - Include: ✅ Geometry, ✅ Materials, ❌ Animation, ❌ Skin
   - Transform: ✅ Apply Modifiers
   - Up Axis: Y
4. 输出路径：
   E:/项目储存/决竞球battle-ball/建模素材库/3D模型素材/battle_field_v2.glb

【验证】
导出后在 Blender 中检查：
- File → Import → glTF，重新导入检查
- 确认尺寸：1300 × 780
- 确认朝向：Y 轴朝上
- 确认材质：草地绿色、边界白色
```

#### 预期产出

```
建模素材库/3D模型素材/
└── battle_field_v2.glb    ← 新球场（约 5-15MB）
```

---

### 【P1】任务 2：现有 GLB 材质修复（防白膜）

#### Codex 提示词

```
检查并修复现有 GLB 文件的材质/贴图问题。

【目标文件】
E:/项目储存/决竞球battle-ball/assets/characters/avatars/
  - Idle.glb
  - Jog_Forward.glb
  - Goalie_Throw.glb
  - Goalkeeper_Catch.glb

【检查步骤】
1. 导入 Idle.glb
2. 检查所有材质是否正确绑定了贴图：
   - albedo map（颜色贴图）
   - normal map（法线贴图，如果有）
   - roughness map（粗糙度贴图，如果有）
3. 检查每个 Material 的 Surface 模式：
   - 必须使用 "Standard"（不是 "Unlit"）
   - 基础色不能是纯白色（除非本来就是白色物体）

【修复操作】
如果发现白膜问题（材质是纯白/灰色，没有贴图）：
1. 为每个 Mesh 的 Material 重新指定纹理
2. 如果原始 GLB 没有嵌入贴图：
   a. 查找同目录下的 .png/.jpg 贴图文件
   b. 或用 Blender 的 "Re-link" 功能重新关联贴图
   c. 如果找不到贴图，创建临时 Procedural 材质（保持颜色一致即可）

【导出】
修复后重新导出：
- 格式：GLB
- 嵌入所有贴图
- 输出到原路径（覆盖原文件）
```

---

### 【P2】任务 3：为 player2-7 创建颜色变体

**目标**：基于 player1 GLB 创建其他 6 个球员的颜色变体，**不重新建模，只改材质颜色**。

#### Codex 提示词

```
基于 player1_base.glb 为其他 6 个球员创建颜色变体。

【源文件】
E:/项目储存/决竞球battle-ball/建模素材库/3D模型素材/player1_base.glb

【球员配色表】
| char_id | 名字 | 球衣主色 | 短裤色 | 发色 |
|---|---|---|---|---|
| char_002 | 超人强 | #1E3A5F 深蓝 | #1E3A5F | #1a1a1a 黑 |
| char_003 | 菲菲 | #228B22 绿色 | #FFFFFF 白 | #8B4513 棕红 |
| char_004 | 小呆呆 | #4169E1 浅蓝 | #1E3A5F 深蓝 | #D2691E 浅棕 |
| char_005 | 波比 | #DC143C 红色 | #FFFFFF 白 | #E65100 橙红 |
| char_006 | 迷糊老师 | #800080 紫色 | #4B0082 深紫 | #808080 灰白 |
| char_007 | 卜三 | #FF69B4 粉色 | #FFFFFF 白 | #FFD700 金色 |

【操作步骤】
对每个球员重复：
1. 导入 player1_base.glb
2. 在 Outliner 中找到所有 Mesh
3. 对每个 Mesh 的 Material：
   - 球衣 Mesh：修改 Base Color 为球衣主色
   - 短裤 Mesh：修改 Base Color 为短裤色
   - 头发 Mesh：修改 Base Color 为发色
   - 皮肤 Mesh：保持原色（player1 的肤色作为基础）
4. 其他参数保持不变（metallic, roughness）
5. 导出为 GLB

【输出路径】
E:/项目储存/决竞球battle-ball/建模素材库/3D模型素材/
  - player2_base.glb  （超人强）
  - player3_base.glb  （菲菲）
  - player4_base.glb  （小呆呆）
  - player5_base.glb  （波比）
  - player6_base.glb  （迷糊老师）
  - player7_base.glb  （卜三）

【导出要求】
- 格式：GLB
- 嵌入所有纹理
- Apply Rotation & Scale
- Y 轴朝上
- 文件大小：每个约 15-30MB（比原 player1 小，因为贴图少）
```

---

### 【P3】任务 4：GLB 尺寸标准化

**目标**：在 Blender 导出时就设好正确尺寸，避免 Godot 里硬调缩放。

#### Codex 提示词

```
批量检查并标准化所有 GLB 文件的尺寸。

【目标文件】
建模素材库/3D模型素材/ 下所有 .glb 文件：
  - player1_base.glb
  - player2_base.glb ~ player7_base.glb
  - battleball_v2.glb
  - battle_field_v2.glb

【尺寸标准】
| 资产 | 目标尺寸 (Y 高度) | 说明 |
|---|---|---|
| 球员 | 170 cm (Y=1.7) | 标准成人身高 |
| 球 | 24 cm (直径) | 标准足球大小 |
| 球场 | 1300 × 780 cm | 已正确，无需调整 |

【操作步骤】
1. 逐个导入 GLB
2. 检查 Y 轴高度：
   - 球员：如果 > 100 cm，缩放到 170 cm
   - 球：如果直径 > 50 cm，缩放到 24 cm
3. 缩放操作：
   a. 选中所有物体
   b. Object → Apply → Scale (Ctrl+A)
   c. Object → Apply → Rotation
   d. 必要时 Object → Apply → Delta Transform
4. 验证尺寸：
   - 3D Viewport 右下角会显示当前尺寸
   - 或用 Properties → Item → Dimensions 检查
5. 导出覆盖原文件

【注意】
- 不要改动画文件 (player*动作/*.fbx) 的尺寸
- 只改静态 body GLB 和球场 GLB
```

---

## 四、Godot 对接检查清单（每个资产必查）

### 4.1 GLB 导入后检查

在 Godot 编辑器中导入 GLB 后，**必须**检查：

```
□ 模型能正常显示（无白膜/无缺失）
□ 材质贴图正确（颜色、法线正常）
□ Y 轴朝上站立（不是躺平）
□ 尺寸正确（与 Godot 场景匹配）
□ 文件大小合理（球员 15-30MB，球场 5-15MB）
```

### 4.2 代码接入检查

在 `player.gd` 中接入新模型后，**必须**检查：

```gdscript
// 1. 路径常量正确
const CHAR_3D_MODEL_PATHS := {
    "char_002": {
        "body": "res://建模素材库/3D模型素材/player2_base.glb",
        // 动画沿用 player1 的 FBX（如果没有专属动画）
        "idle": "res://建模素材库/3D模型素材/player1动作/Idle.fbx",
        "run": "res://.../player1动作/Jog Forward.fbx",
        "throw": "res://.../player1动作/Goalie Throw.fbx",
        "catch": "res://.../player1动作/Goalkeeper Catch.fbx",
    },
    // ... 其他角色
}

// 2. ModelSlot 扶正矩阵（必须！）
// 在 player_model_3d.tscn 中设置 ModelSlot 的 Transform3D：
// Basis(Vector3.RIGHT, deg_to_rad(-90.0))

// 3. PROXY_SCALE 调整（如果改了 GLB 尺寸）
// 原先 scale=70 对应 105m 的模型
// 如果 GLB 已经是 1.7m 标准尺寸，scale 应该约为 2.0
const PROXY_SCALE: float = 2.0  // ← 根据实际调整

// 4. AnimationLibrary 深拷贝（必须！防止共享问题）
func _deep_copy_anim_library(anim_player: AnimationPlayer) -> void:
    for lib_name in anim_player.get_animation_library_list():
        var lib = anim_player.get_animation_library(lib_name)
        anim_player.remove_animation_library(lib_name)
        anim_player.add_animation_library(lib.duplicate(true))
```

### 4.3 运行时验证

运行 `player_3d_test.tscn` 测试场景，检查：

```
□ 模型在小相机 SubViewport 中正确显示
□ 3 个视角（俯视/斜视/平视）都正常
□ 动画正确播放（idle → run → throw → catch）
□ 多个球员同时显示不叠加（只有 idle mesh 可见）
□ 切换角色时动画不串（深拷贝生效）
```

---

## 五、额度节省最佳实践

### 5.1 单次指令完成多步

```
❌ 低效：
"创建超人强的材质" → "创建菲菲的材质" → ...

✅ 高效：
"读取 player1_base.glb，批量为 6 个球员修改球衣/短裤/头发颜色，
一次导出 6 个变体 GLB，不要分步。"
```

### 5.2 用 Python 脚本替代手动

```
✅ 让 Codex 写 Blender Python 脚本：
"写一个 Blender Python 脚本，读取 colors.json 配置，
批量修改 GLB 材质颜色，输出到指定目录。"

这样一次写好脚本，后续可以反复运行，不费额度。
```

### 5.3 额度监控

每完成一个任务记录消耗：

| 任务 | 预估 | 实际 |
|---|---|---|
| 球场建模 | ~15 | |
| 材质修复 | ~10 | |
| 6 个变体 | ~20 | |
| 尺寸标准化 | ~10 | |
| **合计** | **~55** | |

---

## 六、执行顺序建议

```
第 1 轮：球场 + 尺寸标准化
  → 跑通 Codex+Blender 管线
  → 验证 GLB → Godot 全流程

第 2 轮：材质修复 + 6 个颜色变体
  → 批量处理，效率最高
  → 逐个在 Godot 中验证

第 3 轮：（可选）专属动画
  → 用 Mixamo 为每个球员单独做动画
  → Blender 中转合并贴图+动画为 GLB
```

---

## 七、绝对禁止事项

| 禁止 | 原因 |
|---|---|
| ❌ 从零创建角色模型 | 已有 player1 + 通用 GLB，重造浪费额度且效果不可控 |
| ❌ 在 Godot 里硬调缩放（>2x） | 根因在 Blender 导出，应在源头解决 |
| ❌ 直接用 Mixamo FBX | 会白膜，必须 Blender 中转 |
| ❌ 同时显示多个 FBX mesh | 会叠加，只保留 idle mesh |
| ❌ 不做 AnimationLibrary 深拷贝 | 会导致动画串台 |
| ❌ 修改共享的 .import 缓存资源 | 会影响所有使用该资源的实例 |

---

## 八、目录结构规范

```
建模素材库/
├── 3D模型素材/
│   ├── battle_field_v2.glb          ← 新球场（P0）
│   ├── battleball.glb                ← 球（已有）
│   ├── player1_base.glb              ← 猪猪侠（已有）
│   ├── player2_base.glb              ← 超人强颜色变体（P2）
│   ├── player3_base.glb              ← 菲菲颜色变体（P2）
│   ├── player4_base.glb              ← 小呆呆颜色变体（P2）
│   ├── player5_base.glb              ← 波比颜色变体（P2）
│   ├── player6_base.glb              ← 迷糊老师颜色变体（P2）
│   ├── player7_base.glb              ← 卜三颜色变体（P2）
│   ├── player1动作/                  ← 猪猪侠动画（已有）
│   │   ├── Idle.fbx
│   │   ├── Jog Forward.fbx
│   │   ├── Goalie Throw.fbx
│   │   └── Goalkeeper Catch.fbx
│   └── ...（其他球员动画待补充）
│
├── scripts/                          ← Blender Python 脚本
│   ├── batch_color_variants.py       ← 批量颜色变体脚本
│   ├── fix_materials.py              ← 材质修复脚本
│   └── normalize_scale.py            ← 尺寸标准化脚本
│
└── config/
    └── character_colors.json         ← 球员配色配置
```

---

## 九、窗口尺寸匹配（关键！）

### 9.1 当前参数现状

根据 `player_model_3d.tscn` 和 `player_3d_test.gd`：

| 组件 | 小相机（球员） | 大相机（全景） |
|---|---|---|
| **SubViewport 尺寸** | 512 × 512 | 2560 × 1440 |
| **Camera3D 正交尺寸** | 80.0 | 870.0（俯视）|
| **Sprite2D 缩放** | 0.35 | 全屏显示 |
| **ModelSlot 缩放** | 70.0 | 1.0 |

### 9.2 尺寸匹配检查清单

#### 小相机（球员模型）

```
□ SubViewport 宽高比 = 1:1（正方形，512×512）
□ Camera3D 正交尺寸 = 80.0（覆盖球员全身）
□ Sprite2D scale = 0.35（匹配 2D 头像大小 ~56px）
□ ModelSlot scale = 70.0（GLB 缩放到合适比例）
□ Sprite2D offset = (0, -28)（居中显示）
□ SubViewport transparent_bg = true（背景透明）
□ SubViewport render_target_update_mode = ALWAYS
```

#### 大相机（全景相机）

```
□ SubViewport 尺寸 = 2560 × 1440（16:9，4K 分辨率）
□ Camera3D 模式 = Orthogonal（俯视/斜视）或 Perspective（平视）
□ BIG_CAM_TOP_ORTHO_SIZE = 870.0（覆盖 1300 宽场地）
□ BIG_CAM_ANGLED_DIST = 1200.0（斜视距离）
□ BIG_CAM_FOV = 62.0（透视视野角）
□ SubViewport render_target_update_mode = ALWAYS
□ TextureRect stretch_mode = Keep Aspect（防止拉伸变形）
```

### 9.3 尺寸不匹配的常见问题

| 问题 | 现象 | 根因 | 解决方案 |
|---|---|---|---|
| **贴图模糊** | 3D 模型显示模糊 | SubViewport 分辨率太低 | 增大 SubViewport 尺寸（512→1024 或更高） |
| **模型变形** | 球员被拉伸或压缩 | 宽高比不匹配 | 确保 Sprite2D 的 TextureRect 保持 1:1 |
| **边缘裁切** | 球员显示不全 | 正交尺寸太小 | 增大 Camera3D size 参数 |
| **黑边** | 模型周围有黑色边框 | SubViewport 非透明 | 设置 transparent_bg = true |
| **分辨率浪费** | 清晰度过高但无必要 | 2560×1440 太高 | 降到 1920×1080 节省性能 |

### 9.4 Codex 辅助调整提示词

```
检查并调整 player_model_3d.tscn 中的尺寸参数，确保小相机 SubViewport、Camera3D、Sprite2D 的尺寸匹配。

【当前参数】
- SubViewport: 512×512
- Camera3D size: 80
- Sprite2D scale: 0.35
- ModelSlot scale: 70

【目标效果】
- 3D 球员在 Sprite2D 中显示清晰（无模糊）
- 球员完整可见（无边切）
- 比例与 2D 占位球员大小一致（约 56×56 像素）

【检查步骤】
1. 确认 SubViewport 分辨率不低于 512×512
2. 检查 Camera3D 正交尺寸是否覆盖球员全身
3. 计算 Sprite2D 最终显示尺寸：
   - 512 × 0.35 = 179.2 像素（太大，会糊）
   - 建议 SubViewport 1024×1024 + scale 0.2 → 204.8 像素
   - 或 SubViewport 512×512 + scale 0.1 → 51.2 像素（接近目标）
4. 如果显示模糊，优先增大 SubViewport 分辨率

调整后导出 .tscn 文件覆盖原文件。
```

---

## 十、动画流畅度方案

### 10.1 当前动画参数

根据 `player_3d_test.gd`：

| 动画 | 类型 | 时长 | 循环 |
|---|---|---|---|
| idle | 待机动画 | 2.0-3.0 秒 | ✅ 循环 |
| run | 跑步动画 | 0.5 秒 | ✅ 循环 |
| throw | 投球动画 | 1.5 秒 | ❌ 单次 |
| catch | 接球动画 | 1.2 秒 | ❌ 单次 |

### 10.2 流畅度检查清单

#### Blender 动画制作

```
□ 动画帧率 = 30 或 60 FPS（与 Godot 匹配）
□ 关键帧分布均匀（不要太稀疏或太密集）
□ 循环动画的首尾帧无缝衔接
□ 单次动画的最终姿态自然过渡
□ 骨骼动画无穿模、无异常抖动
□ 总时长符合游戏需求（idle 2-3 秒，run 0.5 秒）
```

#### Godot 播放设置

```
□ AnimationLibrary 深拷贝（防止共享问题）
□ 循环动画设置为 LOOP（不要用 ONCE）
□ 单次动画设置为 ONCE
□ 播放速度 = 1.0（正常速度）
□ 不要在 _physics_process 中反复调用 play()
□ 使用 animation_finished 信号自动切换
□ 初始动画锁定机制正确（_manual_anim_locked）
```

### 10.3 动画切换逻辑（摘自 player_3d_test.gd）

```gdscript
# 正确的动画切换方式
func _physics_process(delta: float) -> void:
    if _manual_anim_locked:
        return  # 手动锁定时不自动切换
    
    var current_state = _get_current_state()
    var desired_anim = _get_anim_for_state(current_state)
    
    if desired_anim != _current_anim:
        if not _anim_player.is_playing() or _anim_player.current_animation != desired_anim:
            _anim_player.play(desired_anim)
            _current_anim = desired_anim

# 错误的方式（不要这样做！）
func _physics_process(delta: float) -> void:
    # ❌ 每帧都调用 play()，会重置动画
    if is_moving:
        _anim_player.play("run")
    else:
        _anim_player.play("idle")
```

### 10.4 动画卡顿的常见原因

| 问题 | 现象 | 根因 | 解决方案 |
|---|---|---|---|
| **动画重置** | 动作从头播起 | _physics_process 反复调用 play() | 只在状态变化时调用 play() |
| **动画串台** | 切角色后动画错 | AnimationLibrary 共享 | 深拷贝动画库 |
| **帧间跳动** | 运动不连贯 | 帧率太低或关键帧太少 | 增加关键帧或提高动画帧率 |
| **模型叠加** | 多套 FBX 同时显示 | 4 个 FBX mesh 同时渲染 | 只保留 idle mesh，其他隐藏 |
| **动画不循环** | idle 播一次就停 | 循环模式设置错误 | 检查 Animation.loop_mode |

### 10.5 Codex 辅助优化提示词

```
检查现有 player1 GLB 动画的质量，确保在 Godot 中播放流畅。

【检查项】
1. 导入以下 FBX 文件：
   - Idle.fbx
   - Jog Forward.fbx
   - Goalie Throw.fbx
   - Goalkeeper Catch.fbx

2. 在 Blender 中检查：
   - 动画帧率：是否为 30 或 60 FPS？
   - idle/run：首尾帧是否无缝衔接？（循环动画）
   - throw/catch：最终姿态是否自然？（单次动画）
   - 关键帧数量：是否在合理范围（idle: 60-90 帧，run: 15-18 帧）

3. 如果需要优化：
   - 循环动画：删除首尾差异，确保无缝
   - 关键帧太少：在关键姿势间插入过渡帧
   - 帧率不一致：统一为 30 FPS

4. 优化后重新导出 FBX：
   - Format: FBX
   - Include: Animation + Skin + Mesh
   - Apply Scaling: Yes
```

---

## 十一、文档版本历史

| 版本 | 日期 | 变化 |
|---|---|---|
| V1.0 | 2026-08-06 | 初始版本 |
| V2.0 | 2026-08-06 | 核心变化：基于已有资产优化，不重造轮子 |
| V2.1 | 2026-08-06 | 新增：窗口尺寸匹配（第九章）+ 动画流畅度（第十章）|

---

*文档版本：V2.1 | 创建于 2026-08-06*  
*核心变化：基于已有资产优化，不重造轮子*
