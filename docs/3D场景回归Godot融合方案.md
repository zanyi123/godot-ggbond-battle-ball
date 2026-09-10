# 3D 场景回归 Godot 融合方案（v2 · 基于 2026-09 双端调研）

> 目标：把 Unity 项目（`E:\项目储存\BattleBall_Unity`）独有的一体化 3D 主战斗场景（球场+球员+球全 3D 模型）迁回 Godot，替换 2.5D 像素风视觉。**主游戏流程除战斗场景视觉外一切不变**：备战/结算/主菜单 UI、比赛流程、AI、元灵系统、数值全部走 Godot 原有 2D 系统。
>
> 本版取代 2026-07 旧版。旧版假设"Unity 仅作规则参考"，已过时——Unity 侧 2026-08~09 已系统性建成一体化 3D 场景并完成白线对齐，本方案按 Unity 现状重新制定。

## 一、调研结论（决策依据）

### 1.1 Unity 侧现状（TestBattle.unity，2026-09-07 最新）

**场景编排（迁移主体）**——平铺结构、球员场景预置、一切逻辑代码化（0 Prefab / 0 Shader / UI 全代码创建）：

| 对象 | 编排 | 备注 |
|---|---|---|
| BattleField | `battle_field_yup.fbx` 位置(0,0,0) **scale=2** | Godot 侧有同名 GLB `scenes/blender/battle_field_3d_yup.glb` |
| TeamA_player1~3 | 预置，(-9,0,-4)/(-9,0,0)/(-9,0,4)，player1~3.fbx + Animator | 玩家控制位=A[0] |
| TeamB_player4~6 | 预置，(9,0,-4)/(9,0,0)/(9,0,4)，player4~6.fbx | B[2] 朝向 y=180° |
| battleball | (0,0.2,0) **scale=0.2515**，battleball.fbx | 飞行自旋 12 rad/s |
| Main Camera | **(0,16,-10) 俯角 58°** 固定单一视角 | 无多相机模式 |
| 出生点标记 ×7 | Home/Away_Spawn ±9 / BallSpawnCenter | 仅 Transform 标记 |
| 管理器 ×8 | _BattleManager/_InputManager/_AiManager/_BuffManager/_SpiritSystemManager/__Bootstrap 平铺挂载 | 全代码绑定 |

**白线规则（类二验证标的，Unity 2026-09-07 对齐后新值）**：

```
内场矩形   x ∈ [-7.6, 7.6], z ∈ [-5.2, 5.2]
外场边界   x ∈ [-10.2, 10.2], z ∈ [-6.5, 6.5]（外场 z = 内场 z ±1.3）
中线       x = 0（队A 左半场 x<0，队A 专属外场=右外场）
违规传送点 A队→(8.9, 0, 0) / B队→(-8.9, 0, 0)
球出界     |x|>10.2 → 球权给对面最近存活球员；|z|>8.5 → 按 x 半场给球权
违规类型   1=蓝色禁区(既不在内场也不在任一外场) 2=越中线(内场内) 3=越内外场边界
判罚       对方 +1 分 + 传送己方外场中心；_violatingPlayers 字典防滞留重复计分
得分来源   仅两种：击倒(HP≤0)=对方+1 / 违规=对方+1（无球门机制，决竞球规则）
```

**坐标换算铁律（Unity 已验证，仅供读懂 Unity 资料）**：`GD 2D 像素 × 0.01 = Unity 米`，球场模型整体 ×2 后场景内等效 `GD px × 0.02 = Unity m`。验证：GD field_zone.gd INNER ±380px ×0.02 = ±7.6 ✓；外场 main ±510px ×0.02 = ±10.2 ✓。**Unity 白线新值与 GD 2D 规则同形，仅差统一缩放因子 0.02。**（Godot 3D 层**不采用**米制——GLB 原生单位即像素级，见 §二 单位制决策；读 Unity 数值时 ×50。）

**特效现状**：无粒子/Shader/VFX Graph，全部动态 Mesh 代码绘制——`SkillVisualManager`(288行) + `SkillOutlineNode`(249行，GD 直译)：球外膜圆环(半径0.3+0.06)、球员脚下圆环(0.4+0.05)、场地四方向条带(厚0.08)，元素色板六色（金刚0.85,0.75,0.3 / 大地0.7,0.55,0.35 / 雷火1,0.4,0.2 / 冰雪0.4,0.8,1 / 草木0.3,0.8,0.3 / 梦幻0.7,0.5,0.9）。另有接球 0.2s 缩放脉冲、球飞行自旋、幻象半透明克隆(α0.55)。

**Unity 已知遗留（迁回时在 Godot 侧补齐或不迁，见 §九）**：玩家技能输入未接、能量扣减恒 true、无下半场换边、球员仅 Idle 动画、单相机、AiManager/FieldZoneManager 仍用 ×2 前旧值 ±3.8（AI 实际只在内场活动）、FieldZoneManager 场景无实例。

### 1.2 Godot 侧接入点（逻辑层权威，零改动承诺的基础）

- **场景几乎为空**：`battle_arena.tscn` = BattleArena(Node2D + battle_manager.gd) + Camera2D。一切战斗实体由 `battle_manager.gd::_ready()` 纯代码创建（:76-132，16 步固定顺序：field→ball→input→players×6→HUD→AI→comm→备战UI→物理/障碍/区域/幻象→元灵系统→瞄准可视化）。
- **同步坐标映射已三处验证**：2D(x,y) → 3D(x, 0, y)（field_zone_3d.gd / ball_proxy_3d.gd / player_3d_test.gd `_game2d_to_3d`）。
- **特效信号链完全解耦**：`player.skill_used` → battle_manager 分发 → ① `spirit_system.use_skill`（数值链，1199 行 tag handler）② `skill_visual_manager.on_skill_triggered`（视觉链）。回链 `effect_applied/effect_finished`、球事件 `ball_hit_player/ball_caught`。半径接口 `player.get_visual_radius()=28 / ball.get_visual_radius()=20` 已预留 3D 化适配点。
- **显隐时点（3D 层必须同步的 6 组成对清单）**：备战 `_setup_preparation_ui`、中场 `_freeze_all_for_half_time`/`_show_half_time_prep`、下半场 `_hide_half_time_prep`、结算等，控制 field_zone/ball/players/penalty_walls/aim_* 的 `visible` 与 `set_process`。
- **输入依赖 Camera2D**：input_manager._process 用 `viewport.get_camera_2d().get_global_mouse_position()` 做朝向与蓄力距离 → 3D 模式必须保留隐形 Camera2D（或平行同步），瞄准线/箭头/圆环均为 battle_manager 2D 自绘。
- **模拟验证可用**：本机 Godot 4.6.2 控制台版存在，`run_sim.sh` headless 加载 battle_arena.tscn 跑 AI 比赛 → 3D 层代码在 headless 下照常执行，运行时错误直接暴露，比分/传球率/卡死指标对比 `sim_results/baseline.json`。
- **3D 资产已就位**：`建模素材库/3D模型素材/player1~8_base.glb`（含 PBR 三件套贴图）+ playerN动作/*.fbx（Idle/Jog/Throw/Catch）+ `battleball.glb` + `scenes/blender/battle_field_3d_yup.glb`。缺口：player.gd 的 `CHAR_3D_MODEL_PATHS` 只登记了 char_001。
- **可参考的既有 3D 基础设施**（`scripts/test/`，只借模式不直接复用）：`ball_proxy_3d.gd`（只读同步+PBR修复+持球挂手）、`battle_field_3d_test.gd`（相机三模式+按节点名分材质+3D版违规/传送复刻）、`player_3d_test.gd`（2408 行：GLB贴图→FBX骨骼 mesh 材质搬运、动画库深拷贝断共享、Root Motion 剥离、大 SubViewport 全场渲染——约 350 行补偿逻辑已趟过坑）、`field_zone_3d.gd`（像素单位规则版）。

### 1.3 关键架构判断

1. Unity 的玩法逻辑本身就是从 GD 迁去的（15 文件含 GD 直译头注释），**不存在"Unity 独有且需反向迁移的逻辑"**；Unity 真正独有的是**场景编排+模型布局+相机+米制白线对齐成果**。因此迁移方向是：**场景资产与编排照搬，逻辑保持 GD 2D 权威**。
2. Unity 独立重写的 AiManager（效用AI）不迁——GD `ai_manager.gd`(2260行) 是权威且经过模拟基线验证。
3. Unity 的反射调用点（RegisterSpiritSkills 等）在 Godot 天然不需要——GD 侧本就是直连。

## 二、总体架构：2D 逻辑权威 + 3D 场景视觉代理

```
battle_arena_3d.tscn (Node2D 根，复制 battle_arena.tscn)
│
├── [2D 游戏逻辑层 — 与现版完全一致，仅隐藏视觉]
│   ├── BattleManager (battle_manager.gd)
│   │   └── _ready() 创建 FieldZone/Ball/6×Player/AI/元灵/UI …（1.2 所列 16 步）
│   ├── 2D 节点保留碰撞与坐标，visible=false（ColorRect 占位/场线/瞄准线隐藏）
│   ├── Camera2D 保留（隐形，input_manager 鼠标世界坐标依赖）
│   └── CanvasLayer (HUD/备战/结算) — 原样
│
├── [3D 场景层 — 新增 battle3d 模块，镜像 Unity TestBattle 编排]
│   ├── BattleArena3DBridge (总线：订阅 2D 创建/显隐/特效信号 → 驱动 3D)
│   ├── SubViewport 1920×1080 (独立 World3D + Environment + UPDATE_ALWAYS)
│   │   ├── WorldEnvironment + DirectionalLight3D
│   │   ├── Camera3D（默认 Unity 观感 (0,800,-500) 俯角58°=Unity值×50，另备 俯视/斜视/跟随）
│   │   ├── FieldModel (battle_field_3d_yup.glb, scale=1 原生像素级 + 根偏移微调)
│   │   ├── FieldRules3D (像素白线常量 = field_zone.gd 权威值 — 类二双轨用)
│   │   ├── PlayerProxy3D ×6 (playerN_base.glb, ModelSlot scale=70 铁律)
│   │   ├── BallProxy3D (battleball.glb, BALL_SCALE_3D=30, 自旋+持球跟随+PBR修复)
│   │   └── SkillFx3DAdapter (球膜/脚环/条带 3D 等价物 — 类一验证)
│   └── TextureRect (ViewportTexture 全屏贴回主画面)
│
└── [UI 层 — 不变] 备战/结算/主菜单全部 2D
```

**数据流**：2D 逻辑(权威) → 3D 代理(只读视觉)，单向不回写。物理碰撞、技能数值、AI 决策全部留在 2D 层。

**单位制决策（2026-09-10 修订：锚定球员规格，弃 Unity 米制）**：3D 层世界单位 = **GD 2D 像素，1:1，零换算**。推导链（不可倒置）：
1. **球员规格定死**（player_3d_test 已验证 + battle-ball skill《3D 模型缩放铁律》）：ModelSlot scale=70 唯一缩放点、FBX 强制 1.0、模型高 ≈49.86；
2. **单位即像素**：桥接同步只做 `(x,y)→(x,0,y)`，不存在换算因子，"2.5D 规格转换"是结构性成立的（3D 读的就是 2D 玩法那套数字本身，无换算误差可言）；
3. **球场比例由规则反推**：白线必须落在 `field_zone.gd` 权威常量（±380/±260/±510/±325/中圈60）上，模型 scale/offset 为满足此条件服务——`battle_field_3d_yup.glb` 原生单位即像素级（同一模型 Unity 需 ×2 到米制），Godot 测试场 scale=1 + 根偏移(-1.837,1.042,0.355) 已对齐过，Phase 1 画框复核；
4. **Unity 数值降级为观感参考**：读取时 ×50（相机 (0,16,-10)58°→(0,800,-500)58°；摆位 ±9m→±450px），只用于复刻观感，不作权威。

**红线**：禁止在 3D 层引入 ×0.01/×0.02 米制换算因子（那是 Unity 侧历史包袱）。

**切换开关**：`battle_manager.gd` 顶部 `const USE_3D_SCENE := false`。false=纯 2D 像素（默认，run_sim 走此路，run_sim.sh 前置检查强制）；true=2D 可视隐藏+3D 层激活。改一个常量即可切换，其余文件零感知。

## 三、目录结构：Unity → Godot 映射（battle3d 模块）

```
Unity Assets/_Project/                    →  Godot（新模块，全部落在 battle3d 命名空间下）
─────────────────────────────────────────────────────────────────────
Scenes/TestBattle.unity                   →  scenes/battle/battle_arena_3d.tscn（主场景）
                                             scenes/test3d/unity_scene_parity_test.tscn（Phase1 独立验证场）
Models/Environment/battle_field_yup.fbx   →  scenes/blender/battle_field_3d_yup.glb（已有）
Models/Characters/player1~8.fbx+贴图       →  建模素材库/3D模型素材/playerN_base.glb+PBR贴图（已有）
Models/Environment/battleball.fbx         →  建模素材库/3D模型素材/battleball.glb（已有）
Animations/Characters/Clips/*.fbx         →  建模素材库/3D模型素材/playerN动作/*.fbx（已有）

Scripts/Battle/BattleManager.cs           →  不迁（GD battle_manager.gd 权威，加 USE_3D_SCENE + 创建信号）
Scripts/Battle/BallController.cs          →  scripts/battle3d/visual/ball_proxy_3d.gd（只读代理，非物理）
Scripts/Battle/PlayerController.cs        →  scripts/battle3d/visual/player_proxy_3d.gd（只读代理）
Scripts/Battle/InputManager.cs            →  不迁（GD input_manager.gd 权威，保留隐形 Camera2D）
Scripts/Battle/AI/AiManager.cs(效用AI)     →  不迁（GD ai_manager.gd 权威）
Scripts/Battle/AI/SpiritAIManager.cs      →  不迁（GD spirit_ai_manager.gd 权威）
Scripts/Battle/Physics/FieldZone*.cs      →  scripts/battle3d/rules/field_rules_3d.gd（仅常量+判定，类二双轨）
Scripts/Battle/Physics/Obstacle/Illusion  →  scripts/battle3d/visual/field_entity_proxy_3d.gd（障碍/区域/幻象 3D 外观）
Systems/SpiritSystem/SkillVisualManager   →  scripts/battle3d/visual/skill_fx_3d_adapter.gd + skill_outline_3d.gd
（Unity 无对应）                           →  scripts/battle3d/battle_arena_3d_bridge.gd（桥接总线）
                                             scripts/battle3d/visual/camera_3d_controller.gd
（Unity 无对应）                           →  scripts/test3d/regression/test_3d_rules_parity.gd（类二）
                                             scripts/test3d/regression/test_3d_effect_compat.gd（类一）
```

**隔离公约（红线）**：
- `player.gd::USE_3D_MODEL` 保持 `false`（per-player SubViewport 路线彻底弃用，走场景级共享大 SubViewport）。
- `scripts/battle/` 既有文件只允许三类改动：battle_manager 加开关+信号（2-3 行/处）；player/ball/field_zone 加 `set_visual_visible(bool)`；不改任何逻辑/接口/信号名。
- `ai_manager.gd / ai_profile.gd / spirit_system/* / game_manager.gd / data/*.json` 一律不动。
- `scripts/test/` 既有 3D 测试设施原样保留作参考，不修改。
- 新代码全部进 `scripts/battle3d/` 与 `scripts/test3d/`，GDScript 缩进用 Tab。

## 四、Unity → Godot 引擎 API 映射表

| Unity（TestBattle 用法） | Godot 3D 层对应 | 说明 |
|---|---|---|
| `transform.position += dir * speed * dt` | `global_position += dir * speed * delta` | 代理同步用，权威位移在 2D 层 |
| `Quaternion.Slerp` 朝向 | `quaternion.slerp(target, w)` 或 `rotation.y = atan2(dir.x, dir.z)` | player_3d_test 已验证 atan2 方案 |
| `OnTriggerEnter`（球碰人） | 不需要——碰撞判定 2D 层独占（Area2D/距离检测） | 3D 层零碰撞体（纯视觉） |
| 动态 Mesh 画圆环/条带（SkillOutlineNode） | `ImmediateMesh` / `TorusMesh`+`StandardMaterial3D`(unshaded, transparency) | 或 CylinderMesh 压扁，元素色透明度 0.55 复刻 |
| UGUI/IMGUI 调试面板 | 不迁——GD HUD/battle_hud 原样 | UI 全 2D |
| `Resources.Load` | `preload()/load()` / `ResourceLoader.load_threaded_request` | 大 GLB（79MB 级）异步预加载 |
| 协程插值（缩放脉冲等） | `Tween`（`create_tween()`） | 接球脉冲 0.2s 正弦 |
| 固定 Camera (0,16,-10) pitch58° | `Camera3D` position=(0,800,-500)（×50），俯角 58° | **Phase 1 实测校准**：以画面构图对齐为准 |
| `Rigidbody.isKinematic` | 无需——3D 层无物理 | — |
| scale=2 球场 / 0.2515 球 | 球场 scale=1（GLB 原生像素级）；球 BALL_SCALE_3D=30 | 不抄 Unity 数值，规格锚定 player_3d_test 铁律 |
| Animator(仅Idle) | `AnimationPlayer` + idle/jog/throw/catch 动画合并 | GD 侧动画资产比 Unity 全，是增强项 |

## 五、接入点清单（Phase 2 桥接的实现依据）

**创建**：battle_manager `_create_player()`(:253)/`_create_ball()`(:188)/`_create_field()`(:155) 末尾各发一个信号（`player_created(player)` / `ball_created(ball)` / `field_created(field)`），bridge 订阅后 spawn 对应 3D 代理。

**逐帧同步**（bridge `_process` 驱动各代理 `sync_from_2d()`）：
- 球员：`global_position → Vector3(x, 0, y)`（1:1 零换算）；`facing_direction → rotation.y = atan2(dir.x, dir.y)`（镜像 Unity 队B y=180°）；`velocity 长度>10px/s` 切 idle/jog；`is_defeated` 倒地表现（灰化/倒下，暂用 modulate 变暗）。
- 球：`is_active` 飞行→ `(x, 30, y)` + 绕 Y 轴 12 rad/s 自旋；持球→挂持球者代理手部节点（HandProxy，高度 55）；回收→白模+隐藏。
- 场地实体：ObstacleManager/FieldZoneManager/IllusionManager 创建/销毁实体时（hook 其 add/remove）spawn 3D 外观代理（障碍盒体、四色区域平面、幻象半透明克隆 α0.55）。

**显隐**（bridge 监听 `GameManager.phase_changed` + battle_manager 新增 `battle_visuals_hidden/shown` 信号，避免侵入 6 组清单）：备战/中场隐藏 3D 层（`SubViewport.render_target_update_mode = UPDATE_DISABLED` 或 TextureRect visible=false），开赛/下半场恢复。penalty_walls 隔离墙同步出 3D 围栏外观。

**特效**（skill_fx_3d_adapter 订阅，与 2D skill_visual_manager 同源信号）：
- `player.skill_used(skill_id, skill_data)` → 按 tags_registry `target_type` 分发：
  - ball → 球代理外膜圆环（半径 = `ball.get_visual_radius() + 6`，元素色 α0.55，直用 GD 2D 数值）
  - player → 球员代理脚下圆环（`player.get_visual_radius() + 5`）
  - field → 球员朝向四方向条带（长=半径，厚度同 GD 2D skill_outline_node）
- `spirit_system.effect_finished` → 清环；`ball.ball_hit_player / ball_caught` → 清球膜 + 接球缩放脉冲
- 元素色板六色与 GD `player.gd::_ELEMENT_COLORS` 同源，直接复用 GD 值
- 2D 层的 skill_visual_manager/skill_aura 在 3D 模式下随 `set_visual_visible(false)` 一并隐藏，逻辑不动

**传送/换场**：field_zone `start_field_transition` 期间 2D smoothstep 改 `global_position`，3D 代理逐帧跟随即自动平滑；`player_transition_completed` 无需额外处理。

**相机/输入**：保留隐形 Camera2D 供 input_manager 鼠标世界坐标；瞄准线（aim_line/arrow/cursor_ring）在 3D 模式下由 bridge 转绘——方案A：2D 瞄准层放 CanvasLayer 顶层直接叠加显示（成本最低，Phase 2 先用）；方案B：3D 等价物（ImmediateMesh 地面投影，Phase 4 优化）。**先用 A。**

## 六、分阶段实施

### Phase 0：资产与骨架准备 ✅（2026-09-10 完成）
1. battle3d 模块自带 `MODEL_MAP`（char_001~008 → mesh FBX + PBR 贴图前缀 + 共享动画），**未改 player.gd 的 CHAR_3D_MODEL_PATHS** ✓
2. `scripts/battle3d/`（README 公约 + battle3d_const.gd 常量表）、`scripts/test3d/` 目录已建 ✓
3. 预加载策略：Phase 1 验证场同步 load + 计时打印（可接受）；Phase 2 bridge 用 `load_threaded_request`（README 已记）✓
   - 资产现实：player1~5 有专属 idle 姿势 FBX（命名不一：Idle/Standing Idle/Standing Block Idle/player5_idle）；player6~8 无动作 FBX → mesh 兜底共享 avatars/Idle.fbx（已知限制，待补资产）；动画统一从共享 Mixamo 动作库合并（run/throw/catch），6 球员全部成功合并四动作

### Phase 1：Unity 场景复刻独立验证场 ✅（2026-09-10 完成，RESULT: PASS）
`scenes/test3d/unity_scene_parity_test.tscn`（Node3D 根，纯代码构建）：
1. ✅ `battle_field_3d_yup.glb` scale=1（原生像素级）+ 根偏移 (-1.837,1.042,0.355)；316 mesh 材质分组（grass/street/wall/line/foliage×3/trunk/lamp×2 按节点名，移植自 battle_field_3d_test 并修正其 Foliage_2 笔误）
2. ✅ 6× PlayerProxy3D 按 Unity 编排摆位（±450/∓200），B 队 rotation.y=PI；ModelSlot scale=70 铁律 + FBX 强制 1.0 + 手动 PBR 贴图
3. ✅ battleball.glb BALL_SCALE=30，PBR 修复，飞行自旋 + 持球挂 HandProxy(8,30,0)
4. ✅ 相机四模式 UNITY(默认,look_at 场心)/TOP(正交870)/ANGLED(45°)/FOLLOW（常量直接搬 player_3d_test，零换算）
5. ✅ 动画：GLB贴图+FBX骨骼模式移植，6/6 球员 idle/run/throw/catch 四动作，Root Motion 双保险（轨道剥离+每帧根骨重置）
6. ✅ 验收证据：`--p1auto` 自动巡检 7/7 PASS + 5 张截图存档 `docs/img/3d_p1/`（unity/top/angled/follow/idle_carried）；TOP 截图肉眼确认红色判定框与 GLB 白线对齐；UNITY 截图确认构图/比例/球员贴图/跑姿
- 踩坑修复 3 轮：① Godot 4.3+ `AnimationPlayer.process_callback` 已改名 `playback_process_mode`（AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS）② UNITY 相机不能直套 rotation(-58,0,0)（Godot 相机朝 -Z，会背对球场），用 look_at 场心 ③ 58° 俯角 + 太阳(-45,-30) 方位 = UNITY 视角全背光发黑，太阳转侧光 yaw 90° + 环境光 0.8
- 新增光照/材质经验：混元球场 GLB 不上材质分组则草地发灰；normal_map 需先 normal_enabled=true

### Phase 2：桥接主流程（2D 逻辑零改动）
1. `battle_manager.gd`：加 `USE_3D_SCENE` 常量 + 3 个创建信号 + 显隐信号（合计 ~15 行，不改逻辑）
2. `player.gd/ball.gd/field_zone.gd`：各加 `set_visual_visible(bool)`（隐藏 ColorRect/场线，保留碰撞体）
3. `battle_arena_3d_bridge.gd` 按第五节清单实现创建/同步/显隐/传送跟随
4. 新建 `scenes/battle/battle_arena_3d.tscn`（原场景 + bridge + SubViewport + TextureRect）
5. `run_sim.sh` 前置检查：`USE_3D_SCENE=true` 时警告并强制按 false 跑
6. **通过标准**：`USE_3D_SCENE=true` 手动跑完整比赛，3D 随 2D 实时同步（含传送/击倒/出界回收）；`=false` 时与现版行为完全一致；跑 `run_sim.sh 3 6 1 80` 对比基线无回归（此时开关为 false，逻辑未动，应零差异）

### Phase 3：类二验证——白线规则完整迁移
1. `field_rules_3d.gd`：像素常量**逐字抄 field_zone.gd 权威值**（±380/±260/±510/±325 等，与 field_zone_3d.gd 同款），实现 `check_violation(team, pos_px) -> int`（1/2/3 同义）
2. bridge 每帧：2D 球员位置原样喂 `field_rules_3d.check_violation`（零换算），与 2D `field_zone.check_zone_violation` 结果比对；**不一致即 push_error**
3. 边界用例全覆盖：蓝色禁区×4 方向 / 越中线（A右B左，内场内）/ 越内外场边界（A进左外场/B进右外场）/ 凹字形臂部边界 / 传送点 ±445 / 球出界 ±510、±425 就近球权
4. 画框模式：ImmediateMesh 把内场/外场/中线/中圈矩形边框叠画在 3D 球场上，肉眼比对 GLB 白线贴图
5. **通过标准**：自动化双轨判定 100% 一致（headless 可跑）+ 画框与白线贴图肉眼对齐
6. ⚠ 已知偏差处理：Unity AiManager 旧值 ±3.8 不迁（GD AI 权威）；GD 2D 中圈半径 60px(=1.2m) Unity 未用于判定只画线——以 GD 为准

### Phase 4：类一验证——2.5D 特效贴合 3D
1. `skill_fx_3d_adapter.gd + skill_outline_3d.gd` 按第五节实现三类视觉（球膜/脚环/条带）+ 接球脉冲 + 状态灯（3D 头顶 Sprite3D 或光环色）
2. **18 项验证矩阵**（3 类 × 6 元素代表技，元素=雷火/冰雪/草木/梦幻/大地/金刚）：
   - BALL：球外观变化（烈焰冲击类）/ 轨迹修饰（追踪/回旋/弧线 → 3D 自旋与轨迹代理体现）/ 击中反馈
   - PLAYER：光环/护盾/状态（铁壁守护类/定身/隐身→半透明）
   - FIELD：区域（草地陷阱→区域 Quad）/ 障碍（石墙→障碍盒）/ 幻象（α0.55 克隆）
3. 特效位置误差 < 5px（与 2D 同单位直读，无换算）；技能数值链（spirit_system）零改动——run_sim 指标证明
4. **通过标准**：18 项逐一截图存档；6 元素色与 2D 版并排对比无色偏

### Phase 5：主场景切换与收尾 ✅（2026-09-10 完成）
1. ✅ 主场景切换以开关形态落地：`USE_3D_SCENE := true`（默认 3D）+ spawn 条件 `and not auto_simulate`（sim 强制纯 2D）；回退=改常量，旧 2D 视觉全保留
2. ✅ run_sim.sh guard 改"警告+降级提示"，3 场模拟正常（基线波动为存量问题）
3. 手动全流程：主菜单→备战(2D)→3D 战斗→中场备战→下半场→结算(2D)→回主菜单
4. ✅ 性能验收：P1 验证场演示负载 144 FPS @1440x900（球场+6GLB+球全渲染），bridge 真实比赛每 10s 打印 FPS
5. 更新 project-context skill / 工作日志 / 提交

## 七、风险与坑（含既有踩坑记录）

1. **SubViewport 三件套**：独立 `World3D.new()` + `Environment` + `UPDATE_ALWAYS`（player_model_3d.tscn 踩坑）；SubViewport 内 AnimationPlayer 需手动 `advance(delta)`。
2. **混元 GLB 材质**：metallic=1/roughness=1 全黑金属感，必须 PBR 修复（ball_proxy_3d `_fix_ball_pbr` 模式）；球场 GLB 按节点名分组上材质（battle_field_3d_test `_apply_field_materials` 模式）。
3. **GLB/FBX 组合**：GLB 有贴图无动画、FBX 有动画无贴图 → 材质按 surface 索引搬运（sRGB/Linear 区分）+ AnimationLibrary `duplicate(true)` 断共享 + Root Motion 每帧骨骼归零——player_3d_test 已趟通，直接移植，勿重写。
4. **相机换算**：Unity 数值读入一律 ×50（角度不变）；Unity 与 Godot rotation_degrees 符号/轴向差异，Phase 1 以画面构图对齐为准，不迷信数值直抄。
5. **球场模型 transform 偏移**：battle_field_3d_test.tscn 根节点带偏移，白线对齐依赖它；米制新场景需重新标定（Phase 3 画框模式先行）。
6. **Godot 4.x**：`.tscn` 内禁 `#` 注释；`look_at` 俯视 up=(0,0,-1)；贴图无损导入 compress/mode=0；Key 常量用整数键值。
7. **性能**：79MB 级 GLB×8 预加载必须异步；首包只载当场所需 6 个。
8. **逻辑回归**：任何阶段怀疑动了逻辑 → 立即 run_sim 对基线；headless 下 3D 节点照常创建，3D 代码错误会炸 sim——这本身是免费的 3D 冒烟测试。

## 八、验证方法汇总

| 阶段 | 验证 | 工具 |
|---|---|---|
| P1 | 场景复刻与 Unity 截图对比、动画、相机 | 手动 + 截图存档 `docs/img/3d_p1/` |
| P2 | 3D/2D 同步、开关双向一致、逻辑零回归 | 手动 + `run_sim.sh` 基线 |
| P3 | 白线双轨 100% 一致 | `test_3d_rules_parity.gd` headless 自动 |
| P4 | 18 项特效矩阵 | `test_3d_effect_compat.gd` + 截图存档 |
| P5 | 全流程 + 性能 + 基线 | 手动 + run_sim + 帧率计数 |

## 九、Unity 遗留问题处置表（迁回时的机会清单）

| Unity 遗留 | 处置 |
|---|---|
| 玩家技能输入未接（4/5/6 无人订阅） | 不存在问题——GD input_manager 本来就接通 |
| 能量扣减恒 true | GD 侧已实现，不迁 |
| 无下半场换边 | GD 侧本就无换边（与 Unity 同形），维持现状；若未来要加，加在 GD 2D 层 |
| 球员仅 Idle 动画 | **GD 侧增强**：playerN动作/*.fbx 四动作全上（Phase 1） |
| 单一固定相机 | **GD 侧增强**：camera_3d_controller 四模式（Phase 1） |
| AiManager/FieldZoneManager 旧值 ±3.8 | 不迁；GD ai_manager 权威。记录：Unity AI 场地感知偏小是已知 Unity bug |
| FieldZoneManager 无场景实例 | 不迁（GD field_zone_manager.gd 已有且在用） |
| 反射跨程序集调用 | Godot 直连，不存在 |

## 十、文件清单（本方案全部产出物）

**新增**：
```
scripts/battle3d/battle_arena_3d_bridge.gd        桥接总线
scripts/battle3d/visual/player_proxy_3d.gd        球员代理（含动画/材质搬运移植）
scripts/battle3d/visual/ball_proxy_3d_v2.gd       球代理（像素制，对齐 player_3d_test 口径）
scripts/battle3d/visual/camera_3d_controller.gd   相机四模式
scripts/battle3d/visual/skill_fx_3d_adapter.gd    特效适配
scripts/battle3d/visual/skill_outline_3d.gd       环/条带 3D 绘制
scripts/battle3d/visual/field_entity_proxy_3d.gd  障碍/区域/幻象外观
scripts/battle3d/rules/field_rules_3d.gd          像素白线规则（类二，常量=field_zone.gd 权威值）
scripts/test3d/regression/test_3d_rules_parity.gd 类二自动验证
scripts/test3d/regression/test_3d_effect_compat.gd 类一矩阵验证
scenes/battle/battle_arena_3d.tscn                3D 主场景
scenes/test3d/unity_scene_parity_test.tscn        Phase1 独立验证场
```

**修改（仅加接口，不动逻辑）**：`battle_manager.gd`（开关+3创建信号+显隐信号）、`player.gd`/`ball.gd`/`field_zone.gd`（各加 `set_visual_visible`）。

**不动**：`scripts/battle/` 其余全部、`scripts/test/` 全部、`spirit_system/*`、`game_manager.gd`、`data/*.json`、全部 UI。
