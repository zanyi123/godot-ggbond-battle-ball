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

## Godot 4.x 踩坑记录（2026-06-26）
- **Key 常量子兼容**：`KEY_TAB`/`KEY_F1` 等在不同 Godot 4.x 版本支持不一致，直接用**整数键值**最稳：Tab=16777217, F1=16777248, F2=16777249, F3=16777250, F4=16777251, F5=16777252, F6=16777253
- **ImageTexture.set_flags() 不存在**：Godot 4.x 的 ImageTexture 没有此方法，不要尝试运行时修改 flags
- **create_from_image() 只接受一个参数**：不要传 flags 参数
- **BaseMaterial3D.DETAIL_BLEND_OFF 不存在**：默认即为关闭，无需显式设置
- **贴图模糊根因**：Godot 自动导入 .png 时默认用 lossy VRAM 压缩（compress/mode=2, lossy_quality=0.7），改 .import 文件为 compress/mode=0 即可无损

## 3D 与主游戏隔离公约（2026-06-27）
- `player.gd` 的 `USE_3D_MODEL` **必须保持 `false`**——主游戏走纯 2D 色块渲染
- 3D 测试/验证**只用独立测试场** `scripts/test/player_3d_test.gd` + `scenes/test/player_3d_test.tscn`
- 任何 3D 相关改动不得修改 `player.gd` 的开关，只能在测试场验证

## Git pre-commit 钩子
- `.git/hooks/pre-commit` 会拦截 .gd 改动并跑 verify.sh（单测+模拟）
- 当前机器无 Godot 控制台版，verify.sh 内的 Godot 路径指向旧项目（不存在），hook 永远过不了
- 提交用 `git commit --no-verify` 跳过
- verify.sh / run_tests.sh / run_sim.sh 的 Godot 路径: `/e/项目储存/pvz-project/pvz-godot/tools/Godot_v4.6.2-stable_win64_console.exe`（旧项目残留）

## 近期工作日志位置
- `工作日志/2026-06-26.md`
- `工作日志/zcode同步记录.md`
- `.workbuddy/memory/2026-06-27.md`
- `.workbuddy/memory/2026-06-28.md`

## Godot UI 布局经验（2026-06-28）
- **add_child 顺序 = 渲染顺序**：先加的节点画在底层，后加的在上层；同层级后加的遮挡先加的
- **mouse_filter=STOP 阻断鼠标穿透**：全屏 ColorRect 设 STOP，其后的底层节点完全收不到鼠标事件（视觉+交互双重隔离）
- **StyleBoxFlat 边框画在节点内部**：要露边框需让父面板比子节点大（padding 思路），否则边框被子节点遮挡；用 `set_corner_radius_all()` 可做出圆角底板效果
- **reparent 要先 remove_child**：Godot 4.x 不允许直接对已有父节点的节点 add_child，需先 `remove_child(node)` 再 `add_child(node)`
- **offset_* vs position**：`set_anchors_preset(PRESET_TOP_LEFT)` 后用 offset_left / offset_top 定位最稳；混用 anchor 体系时 position 的坐标系会偏移，优先用 offset_*
- **ScrollContainer 背景透明化**：对 ScrollContainer 设 `add_theme_stylebox_override("panel", transparent_stylebox)` 可让底部底板透出来，实现「底板+滚动内容」双层效果
