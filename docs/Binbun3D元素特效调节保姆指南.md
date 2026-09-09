# Binbun3D Elemental Magic FX — 元素特效调节保姆指南

> 本文档针对 Godot 4.x 项目中已导入的 Binbun3D **Elemental Magic FX Free** 包，手把手教你如何调节元素特效的每一个参数。

---

## 目录

1. [打开特效场景](#1-打开特效场景)
2. [特效类型一览](#2-特效类型一览)
3. [Projectile（投射物）参数详解](#3-projectile投射物参数详解)
4. [Area（范围攻击）参数详解](#4-area范围攻击参数详解)
5. [Cast（施法闪光）参数详解](#5-cast施法闪光参数详解)
6. [一键换元素配色方案](#6-一键换元素配色方案)
7. [Inspector 面板操作图解](#7-inspector-面板操作图解)
8. [常见问题 FAQ](#8-常见问题-faq)

---

## 1. 打开特效场景

### 1.1 找到文件

在 Godot 左侧 **FileSystem（文件系统）** 面板中，沿路径展开：

```
assets → BinbunVFX_Vol2 → ElementalMagicFX → elemental_magic_scene_free.tscn
```

### 1.2 双击打开

双击 `elemental_magic_scene_free.tscn`，场景编辑器会加载完整演示场景。

### 1.3 运行看效果

按 **F6**（运行当前场景），你会看到：
- **左侧**：Fire Projectile（火球投射 + 拖尾）
- **右侧**：Fire Area（地面火焰光环 + 粒子上升）
- **后方**：Fire Cast（施法闪光动画，自动循环播放）

> 💡 因为所有脚本都标了 `@tool`，**不运行也能在编辑器 3D 视口里实时看效果**——改 Inspector 参数立即生效！

---

## 2. 特效类型一览

| 特效类型 | 场景文件 | 脚本类名 | 继承自 | 用途 |
|---------|---------|---------|--------|------|
| 🔥 Projectile | `effects/projectile/vfx_fire_projectile_01.tscn` | `VFXElementalProjectileBB` | `VFXEmitterBB` | 飞行火球 + 拖尾 + 火星 |
| 🔥 Area | `effects/area/vfx_fire_area_01.tscn` | `VFXElementalAreaBB` | `VFXEmitterBB` | 地面光环 + 上升火焰 |
| 🔥 Cast | `effects/cast/vfx_fire_cast_01.tscn` | `VFXElementalCastBB` | `VFXControllerBB` | 球体闪光施法动画 |

---

## 3. Projectile（投射物）参数详解

在场景树中点击 `Projectile → VFXFireProjectile_01`，右侧 Inspector 显示参数。

### 🔵 Color（颜色组）

| 参数 | 类型 | 默认值 | 作用 | 调节建议 |
|------|------|--------|------|---------|
| `primary_color` | Color | `(1, 0.8, 0.2)` 橙黄 | **火焰核心色**（最亮最内层） | 改这个就能一键换元素！ |
| `secondary_color` | Color | `(1, 0.4, 0.1)` 橙红 | **火焰中层过渡色** | 比primary暗/浓一个色调 |
| `tertiary_color` | Color | `(0.6, 0.1, 0.05)` 深红 | **火焰边缘消散色** | 改成深蓝/深绿让边缘更自然 |
| `emission` | float | `2.0` | **发光强度** | 1.0=微光，2.0=正常，5.0=刺眼 |
| `color_curve` | 缓动曲线 | `1.0` | **主色→辅色过渡曲线** | 1.0=线性，<1更快过渡，>1主色更长 |

### 🟡 Light（光源组）

| 参数 | 类型 | 默认值 | 作用 |
|------|------|--------|------|
| `light_color` | Color | `(1, 0.71, 0.31)` 暖橙 | 投射物发出的灯光颜色 |
| `light_energy` | float | `5.0` | 灯光亮度 |
| `light_indirect_energy` | float | `1.0` | 间接光照（反弹光）强度 |
| `light_volumetric_fog_energy` | float | `1.0` | 体积雾光照强度 |

### 🟢 Shape（形状组）

| 参数 | 类型 | 默认值 | 作用 | 调节建议 |
|------|------|--------|------|---------|
| `noise_texture` | Texture2D | 内置cellular噪波 | 火焰纹理形状 | 一般不用换 |
| `noise_scale` | Vector2 | `(1.0, 1.0)` | 纹理缩放，越大越细碎 | <1.0可能硬边，谨慎 |
| `noise_scroll` | Vector2 | `(0.1, 0.5)` | 火焰流动速度 | Y越大燃烧越快 |
| `noise_curve` | 缓动曲线 | `1.0` | 噪波明暗对比曲线 | >1更锐利，<1更柔和 |
| `wave_scale` | float | `2.0` | 火尖波浪缩放 | 增大=更细波浪 |
| `wave_speed` | float | `1.0` | 波浪移动速度 |
| `wave_detail` | float | `3.0` | 波浪偏移细节量 |
| `wave_twist` | float | `3.0` | 波浪扭转程度 | 0=不扭，越大越扭 |
| `tail_length` | float 0~1 | `0.7` | 拖尾淡出距离 | 1.0=最长，0.3=短尾巴 |
| `streaks_width` | float 0~1 | `0.1` | 螺旋条纹宽度 | 0=无条纹，0.3=粗条纹 |

### 🟣 Spiral（螺旋组）

| 参数 | 类型 | 默认值 | 作用 | 调节建议 |
|------|------|--------|------|---------|
| `spiral_amount` | float 0~1+ | `0.4` | 螺旋强度 | 0=直线，0.8=强力螺旋 |
| `spiral_scale` | float | `20.0` | 螺旋波密度 | 越大=纹理更密 |
| `spiral_count` | int | `3` | 螺旋线数量 | 2=双旋，5=多旋 |
| `spiral_speed` | float | `4.0` | 螺旋旋转速度 |
| `spiral_noise` | float 0~1 | `0.0` | 螺旋噪波扰动 | 0=纯数学螺旋，0.3=自然扭曲 |

### 🔴 Particles（粒子组）

| 参数 | 类型 | 默认值 | 作用 | 调节建议 |
|------|------|--------|------|---------|
| `particles_amount` | int | `64` | 火星粒子数量 | 32=稀疏，128=密集 |
| `lifetime` | float | `1.0` | 粒子生命（秒） | 0.5=短火星，2.0=长尾 |
| `explosiveness` | float 0~1 | `0.0` | 粒子爆发性 | 0=稳定燃烧，0.5=半爆发 |

### ⚪ Transparency（透明度组）

| 参数 | 类型 | 默认值 | 作用 | 调节建议 |
|------|------|--------|------|---------|
| `edge_hardness` | float 0~1 | `0.0` | 边缘硬度 | 火/冰用0（柔和），岩石用高值 |
| `edge_position` | float 0~1 | `0.2` | 硬边切割位置 | 配合edge_hardness使用 |

---

## 4. Area（范围攻击）参数详解

在场景树中点击 `Area → VFXFireArea_01`。

### 🔵 Color（颜色组）

| 参数 | 类型 | 默认值 | 作用 | 调节建议 |
|------|------|--------|------|---------|
| `primary_color` | Color | `(1, 0.8, 0.2)` | 火焰核心色 | 改色换元素 |
| `secondary_color` | Color | `(1, 0.4, 0.1)` | 中层过渡色 |
| `tertiary_color` | Color | `(0.6, 0.1, 0.05)` | 边缘消散色 |
| `emission` | float | `3.0` | 发光强度（Area默认更高） |
| `color_curve` | 缓动曲线 | `1.0` | 颜色过渡曲线 |

### 🟢 Shape（形状组）

| 参数 | 类型 | 默认值 | 作用 | 调节建议 |
|------|------|--------|------|---------|
| `noise_texture` | Texture2D | 内置cellular | 火焰纹理 |
| `noise_scale` | Vector2 | `(2.0, 1.0)` | 纹理缩放（Area默认X=2更细碎） |
| `noise_scroll` | Vector2 | `(0.1, 0.3)` | 火焰流动速度 |
| `shape_curve` | 缓动曲线 | `1.0` | 噪波形状曲线 |
| `stepped_animation` | float 0~1 | `0.0` | 阶梯动画混合 | 0=平滑，0.5~1=像素风 |
| `animation_steps` | float | `20.0` | 阶梯级数 | 8=粗糙像素，30=细腻定格 |
| `area_radius` | float | `1.4` | 范围半径 | ⚠️ 同时改mesh和粒子环，影响整体大小 |

### 🔴 Particles（粒子组）

| 参数 | 类型 | 默认值 | 作用 | 调节建议 |
|------|------|--------|------|---------|
| `particles_amount` | int | `64` | 上升火焰粒子数 |
| `lifetime` | float | `2.0` | 粒子生命 | 1.0=矮火焰，3.0=高大火焰 |
| `explosiveness` | float 0~1 | `0.0` | 爆发性 |

### ⚪ Transparency（透明度组）

同 Projectile。

---

## 5. Cast（施法闪光）参数详解

在场景树中点击 `Cast → VFXFireCast_01`。

> Cast 继承 `VFXControllerBB`，用 AnimationPlayer 驱动一次性施法动画。

### 🔵 Color（颜色组）

| 参数 | 类型 | 默认值 | 作用 | 调节建议 |
|------|------|--------|------|---------|
| `primary_color` | Color | `(1, 0.8, 0.2)` | 闪光核心色 |
| `secondary_color` | Color | `(1, 0.4, 0.1)` | 闪光外层色 |
| `emission` | float | `4.0` | 发光强度（Cast默认最高） | 2.0=温和，8.0=爆炸式闪光 |
| `color_curve` | 缓动曲线 | `1.0` | 颜色过渡曲线 |

### 🟢 Shape（形状组）

| 参数 | 类型 | 默认值 | 作用 | 调节建议 |
|------|------|--------|------|---------|
| `noise_texture` | Texture2D | 内置cellular | 闪光纹理 |
| `noise_scale` | Vector2 | `(1.0, 2.0)` | 纹理缩放（Cast默认Y=2） |
| `noise_scroll` | Vector2 | `(0.1, 0.3)` | 流动速度 |
| `shape_curve` | 缓动曲线 | `1.0` | 噪波形状曲线 |

### ⚪ Transparency（透明度组）

| 参数 | 类型 | 默认值 | 作用 | 调节建议 |
|------|------|--------|------|---------|
| `edge_hardness` | float 0~1 | `0.5` | 边缘硬度 | Cast默认0.5（比Projectile/Area硬一点） |
| `edge_position` | float 0~1 | `0.2` | 硬边位置 |

### 🔧 Cast 特有控制参数

| 参数 | 类型 | 默认值 | 作用 | 调节建议 |
|------|------|--------|------|---------|
| `one_shot` | bool | `false` | 播放一次就停？ | true=只播一次（施法瞬间），false=循环播放 |
| `autoplay` | bool | `false`（场景实例设为true） | 场景加载时自动播放 | |
| `speed_scale` | float 0~8 | `1.0` | 动画+粒子速度缩放 | 2.0=两倍速，0.5=慢动作 |
| `emitting` | bool | — | 点击触发 `play()` | Inspector里点击即触发播放 |

### Inspector 工具按钮

在 Inspector 顶部 About 组里有两个按钮：
- **📘 Documentation** — 打开 Binbun3D 官方文档
- **⭐ Rate This Effect!** — 打开 itch.io 评分页

---

## 6. 一键换元素配色方案

**核心原理**：三种特效共享相同的颜色参数体系。只需修改 `primary_color`、`secondary_color`、`tertiary_color` + `light_color`，就能把火系变成任何元素！

### 🎨 推荐配色表

| 元素 | primary_color | secondary_color | tertiary_color | light_color |
|------|--------------|----------------|----------------|-------------|
| 🔥 **火焰**（默认） | `(1, 0.8, 0.2)` 橙黄 | `(1, 0.4, 0.1)` 橙红 | `(0.6, 0.1, 0.05)` 深红 | `(1, 0.71, 0.31)` 暖橙 |
| 🧊 **冰霜** | `(0.5, 0.8, 1.0)` 浅蓝 | `(0.2, 0.5, 0.9)` 中蓝 | `(0.05, 0.1, 0.4)` 深蓝 | `(0.6, 0.8, 1.0)` 冰蓝 |
| 🌿 **草木** | `(0.5, 0.9, 0.3)` 亮绿 | `(0.2, 0.7, 0.1)` 深绿 | `(0.05, 0.2, 0.05)` 暗绿 | `(0.4, 0.8, 0.3)` 绿光 |
| ⚡ **雷电** | `(0.9, 0.95, 1.0)` 白蓝 | `(0.3, 0.5, 1.0)` 蓝 | `(0.05, 0.1, 0.3)` 深蓝紫 | `(0.7, 0.8, 1.0)` 蓝白 |
| 💀 **暗影** | `(0.3, 0.1, 0.4)` 深紫 | `(0.15, 0.05, 0.2)` 暗紫 | `(0.05, 0.02, 0.08)` 近黑 | `(0.3, 0.15, 0.4)` 紫光 |
| 💎 **水晶** | `(0.85, 0.85, 1.0)` 白蓝 | `(0.6, 0.7, 0.9)` 浅蓝 | `(0.3, 0.4, 0.6)` 蓝灰 | `(0.8, 0.85, 1.0)` 白光 |
| 🌊 **水系** | `(0.2, 0.6, 0.9)` 海蓝 | `(0.1, 0.4, 0.7)` 深蓝 | `(0.05, 0.15, 0.35)` 暗蓝 | `(0.3, 0.6, 0.9)` 蓝光 |
| 🌙 **月光** | `(0.9, 0.95, 1.0)` 月白 | `(0.6, 0.65, 0.8)` 银蓝 | `(0.3, 0.35, 0.5)` 灰蓝 | `(0.8, 0.85, 1.0)` 银光 |

### 🛠️ 操作步骤（保姆级）

1. 在场景树中**选中你要改色的特效节点**（如 `VFXFireProjectile_01`）
2. 在 Inspector 面板找到 **Color** 分组
3. 点击 `primary_color` 旁边的**颜色条** → 弹出颜色选择器
4. 在颜色选择器中输入 RGB 值（如冰霜的 `(0.5, 0.8, 1.0)`）
5. 3D 视口**立即显示效果**，实时预览
6. 重复操作改 `secondary_color`、`tertiary_color`
7. 如果是 Projectile，还要改 **Light** 组的 `light_color`（这决定特效照亮周围环境的颜色）
8. 满意后 **Ctrl+S 保存场景**

### 💡 进阶技巧

- **发光强度也要调**：冰/水系的 `emission` 可以降到 1.5~2.0（冷光不需要太亮），暗影系可以降到 1.0
- **edge_hardness 跟元素走**：火=0.0（柔和边缘），冰=0.3~0.5（半硬边），水晶=0.8~1.0（硬切割）
- **速度也跟元素走**：雷电 `noise_scroll` 改 `(0.5, 2.0)`（快闪），水系改 `(0.05, 0.1)`（慢流）

---

## 7. Inspector 面板操作图解

### 7.1 如何找到参数

```
Inspector 面板布局（选中特效节点后）：

┌─────────────────────────────────────┐
│ VFXFireProjectile_01                │ ← 节点名
├─────────────────────────────────────┤
│ ▼ Color                             │ ← 第1组：颜色
│   primary_color    [████] 橙黄      │ ← 点颜色条改色
│   secondary_color  [████] 橙红      │
│   tertiary_color   [████] 深红      │
│   emission         [2.0  ]          │ ← 拖动或输入数字
│   color_curve      [1.0  ]          │ ← 缓动曲线编辑器
│                                     │
│ ▼ Light                             │ ← 第2组：光源
│   light_color      [████] 暖橙      │
│   light_energy     [5.0  ]          │
│   ...                               │
│                                     │
│ ▼ Shape                             │ ← 第3组：形状
│   noise_texture    [内置]           │ ← 一般不用换
│   noise_scroll     (0.1, 0.5)       │ ← Vector2，两个值
│   ...                               │
│                                     │
│ ▼ Spiral                            │ ← 第4组：螺旋
│   ...                               │
│                                     │
│ ▼ Particles                         │ ← 第5组：粒子
│   ...                               │
│                                     │
│ ▼ Transparency                      │ ← 第6组：透明度
│   ...                               │
│                                     │
│ ▼ Audio                             │ ← 第7组：音频
│   ...                               │
│                                     │
│ ▼ About                             │ ← 第8组：工具按钮
│   [📘 Documentation]                │ ← 点按钮打开网页
│   [⭐ Rate This Effect!]            │
└─────────────────────────────────────┘
```

### 7.2 各参数类型的编辑方式

| 参数类型 | Inspector中的外观 | 操作方式 |
|---------|-----------------|---------|
| **Color** | 颜色条 `[████]` | 点击颜色条 → 弹出颜色选择器，输入RGB或直接选色 |
| **float** | 数字输入 `[2.0]` | 直接输入数字，或拖动左右调整 |
| **int** | 数字输入 `[64]` | 直接输入整数 |
| **Vector2** | 两个数字 `(X, Y)` | 分别修改X和Y值 |
| **Texture2D** | 资源引用 `[内置]` | 点击 → 选择其他纹理资源 |
| **缓动曲线** | 特殊编辑器 `[1.0]` | 点击弹出曲线编辑器，拖动控制点 |

### 7.3 缓动曲线编辑器用法

`color_curve`、`noise_curve`、`shape_curve` 这类参数用的是缓动曲线编辑器：

1. 点击数字旁边的**小曲线图标**
2. 弹出一个曲线编辑面板
3. 拖动**两个端点**调整曲线形状
4. **左端点**控制起始过渡速度，**右端点**控制结束过渡速度
5. 曲线越陡 = 过渡越快，越平 = 过渡越慢

---

## 8. 常见问题 FAQ

### Q1: 改了颜色但3D视口没变化？

**原因**：Godot 还在导入资源。
**解决**：等底部导入进度条走完，或者关闭场景再重新打开。

### Q2: 特效看起来全是黑的？

**原因**：环境光照没加载。
**解决**：确保打开了完整演示场景（`elemental_magic_scene_free.tscn`），它自带 WorldEnvironment。如果只打开子场景，需要自己添加环境。

### Q3: Area 特效看不到上升火焰？

**原因**：粒子默认 autoplay=false，需要手动触发。
**解决**：在 Inspector 中找到 `emitting` 属性，勾选它。或者运行场景（F6），场景里的 AnimationPlayer autoplay="open" 会自动启动。

### Q4: Cast 特效只闪一次就消失了？

**原因**：Cast 默认 `one_shot=false` 会循环播放，但演示场景里设了 `autoplay=true`。
**解决**：想让它只闪一次 → 勾选 `one_shot`。想持续循环 → 确保 `one_shot=false` + `autoplay=true`。

### Q5: Projectile 的拖尾太短/太长？

**解决**：调整 Shape 组的 `tail_length`（0~1），0.3=短尾巴，0.9=长尾巴。

### Q6: 特效太亮/太暗？

**解决**：
- 调 `emission`（2.0=正常，1.0=暗，5.0=很亮）
- 调 Light 组的 `light_energy`（影响照亮环境的程度）
- 如果有体积雾，也调 `light_volumetric_fog_energy`

### Q7: 如何在自己的游戏场景中使用这些特效？

**步骤**：
1. 把 `vfx_fire_projectile_01.tscn` 等子场景实例化到你的场景中
2. 在代码中用 `preload("res://assets/BinbunVFX_Vol2/ElementalMagicFX/effects/projectile/vfx_fire_projectile_01.tscn")` 加载
3. 实例化后设置颜色：`instance.primary_color = Color(0.5, 0.8, 1.0)`
4. 播放：`instance.open()`（Emitter类型）或 `instance.play()`（Controller类型）
5. 停止：`instance.close()`（Emitter）或 `instance.stop()`（Controller）

### Q8: 保存后特效颜色没保存？

**原因**：你可能改的是子场景内部节点的 ShaderMaterial 参数，而不是根节点的 export 参数。
**解决**：**只改根节点的 Inspector 参数**（primary_color 等），不要展开子节点改 ShaderMaterial。

---

## 附录：文件路径速查

| 文件 | 路径 |
|------|------|
| 主演示场景 | `res://assets/BinbunVFX_Vol2/ElementalMagicFX/elemental_magic_scene_free.tscn` |
| Projectile | `res://assets/BinbunVFX_Vol2/ElementalMagicFX/effects/projectile/vfx_fire_projectile_01.tscn` |
| Area | `res://assets/BinbunVFX_Vol2/ElementalMagicFX/effects/area/vfx_fire_area_01.tscn` |
| Cast | `res://assets/BinbunVFX_Vol2/ElementalMagicFX/effects/cast/vfx_fire_cast_01.tscn` |
| Projectile脚本 | `res://assets/BinbunVFX_Vol2/ElementalMagicFX/script/VFXElementalProjectileBB.gd` |
| Area脚本 | `res://assets/BinbunVFX_Vol2/ElementalMagicFX/script/VFXElementalAreaBB.gd` |
| Cast脚本 | `res://assets/BinbunVFX_Vol2/ElementalMagicFX/script/VFXElementalCastBB.gd` |
| Emitter基类 | `res://assets/BinbunVFX_Vol2/shared/script/VFXEmitterBB.gd` |
| Controller基类 | `res://assets/BinbunVFX_Vol2/shared/script/VFXControllerBB.gd` |
| OmniLight | `res://assets/BinbunVFX_Vol2/shared/script/VFXOmniLightBB.gd` |

---

_文档生成日期：2026-07-18 | 项目：决竞球 battle-ball | Godot 4.x_
