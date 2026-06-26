# 决竞球 Battle-Ball 项目记忆

## 项目概述
基于 Godot 4.x 的植物大战僵尸主题卡牌对战游戏，采用 2.5D 架构（2D 物理层 + SubViewport 渲染 3D 角色模型）。

## 核心架构
- **2.5D 渲染**：CharacterBody2D → SubViewport + Camera3D → ViewportTexture → Sprite2D
- **ModelSlot 扶正**：Transform3D(1,0,0, 0,0,-1, 0,1,0, 0,0,0) 将混元/Mixamo 生成的水平骨骼（+Y→+Z）转为垂直站立（+Y 朝上）
- **SubViewport 修复**：必须 `world_3d=World3D.new()` + `Environment` + `UPDATE_ALWAYS`，否则渲染冻结

## 角色 3D 模型路径系统（2026-06-26）
- `CHAR_3D_MODEL_PATHS` 字典按 `character_id` 映射专属模型路径
- `_get_model_path(action)` 方法：优先查专属路径，未命中回落 `GLB_*_PATH` 默认
- body GLB 无 AnimationPlayer 时自动兜底换用 idle FBX
- 当前已配置：`char_001`（猪猪侠）= `建模素材库/3D模型素材/player1动作/` 下的 4 个 FBX + `2cff3ad...glb`

## 大相机 Camera3D 三模式（测试场）
- 俯视：正交，+Y 上方 1000 单位，up=(0,0,-1)
- 斜视45°：透视，YZ 平面 45° 位置，d=1200
- 平视跟随：透视，+X 侧跟随球员 Z 坐标
- 坐标映射：2D X→3D X，2D Y→3D Z，场地上方→3D Y
- **代理体已替换为 player1 真模型（2026-06-26）**：`_make_3d_player()` 加载 body GLB + ModelSlot 扶正 + scale 0.55 + 脚下色环区分队伍

## 5 阶段 3D 进化路线
- Phase 0 ✅ 扶正+缩放
- Phase 1 ⏳ 3D 场地（Camera3D 看不见 2D 节点，硬依赖）
- Phase 2 ⏳ Camera2D→Camera3D（测试场已验证三模式）
- Phase 3 ⏳ 鼠标 raycasting
- Phase 4 ⏳ 物理 2D→3D

## 工作约定
- 使用中文技术交流，输出 Markdown 格式
- player.gd 中 player_model_3d.tscn 的 [node] 块禁止 `#` 注释（导致 load() 失败）
- GDScript 缩进用 Tab，不用空格
- FBX 文件通过 Godot 自动导入系统加载，可像 GLB 一样 `load()`

## 近期工作日志位置
- `工作日志/2026-06-26.md`
- `工作日志/zcode同步记录.md`
