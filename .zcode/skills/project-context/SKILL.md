---
name: "project-context"
description: "决竞球项目记忆中枢。新会话接手、开工、跨工具交接、理解项目上下文时必读。包含项目定位、开发铁律、验证纪律、架构速查、当前进度、记忆资产索引。建议每次开工先触发。"
---

# 决竞球项目记忆中枢

> 新会话开工第一动作：读本技能 + 读最近一份工作日志。
> ⚠ **不要主动读全部代码**，按「代码按需读取清单」按任务读相关文件。

## 一、项目定位

- **名称**：决竞球 Battle Ball（《猪猪侠之决竞球》同人 Godot 复刻）
- **类型**：3v3 球类对战游戏，核心玩法是 AI 球员战术对抗
- **引擎**：Godot 4.6 / GDScript
- **入口场景**：`res://scenes/main/main_menu.tscn`
- **当前重心**：AI 系统调优 + 3D 渲染进化 + UI 系统

## 二、开发铁律（必读必守）

1. **消歧义**：需求不清先问，不猜测执行。
2. **复述+纲要**：动手前先复述理解、列步骤大纲，让主人确认。
3. **过程精简**：中间细节别刷屏，只报关键节点和决策。
4. **完成总结**：交付时说清「做了什么 / 改了哪些文件 / 有何待办」。
5. **自检自测**：实现后查逻辑/节点/信号；能跑的必跑；跑不了的明确告诉主人「需要你手动验证什么」。
6. **有疑问就问**：设计/数值/交互不确定，主动问，宁问不错。
7. **称呼**：回复开头加「主人」。

## 三、验证纪律（改 AI 代码时强制激活）

改了下面任一文件，**必须跑模拟**：

| 文件 | 影响 |
|---|---|
| `scripts/battle/ai_manager.gd` | AI 决策/移动/感知 |
| `scripts/battle/ai_profile.gd` | AI 参数/角色预设 |
| `scripts/battle/battle_manager.gd` | 比赛流程/球权 |
| `scripts/core/game_manager.gd` | 计时/阶段 |
| `scripts/battle/match_stats.gd` | 指标采集 |
| `scripts/battle/ball.gd` | 球物理/信号（影响接投球） |

```bash
./run_sim.sh 3 6 1 80   # 3场 / 6倍速 / 种子1-3 / 每半场80秒，约90秒
```

- **危险总数 = 0** 才能交付（比分僵死0-0、卡死>0、传球率<80%、零击中 都是危险）
- 有危险项必须定位根因修复重跑，**禁止"让主人跑游戏看看"**
- 警告项（状态切换过多等）不阻塞，但要说明是已知现象还是本次引入
- 对比基线：`sim_results/baseline.json` 的 `known_observations` 区分"正常但可疑"与真 bug
- **豁免**：纯注释/格式/只改 print/不影响 AI 行为的数值，可只查语法

> ⚠ 注意：verify.sh / run_tests.sh / run_sim.sh 的 Godot 路径指向旧项目（不存在），当前机器无 Godot 控制台版时模拟无法直接运行。此时需明确告知主人需手动验证。

## 四、Bug 维修纪律

- 每轮**只修一个根因**，最多改 1-3 个文件，不重构无关代码
- 先读报错+代码+节点树，用人话解释，定位根因再动手
- 改完代码**必查语法**

## 五、架构速查

**Autoload 单例**（`project.godot` 注册）：
- `DataManager` → `scripts/core/data_manager.gd`（加载 JSON 数据）
- `GameManager` → `scripts/core/game_manager.gd`（比赛状态/计时/阶段）

**核心脚本分层**：
```
scripts/
├── core/      data_manager / game_manager（单例）
├── battle/    player / ball / battle_manager / battle_hud / input_manager
│              ai_manager / ai_profile / match_stats   ← AI 子系统
│              field_zone / field_physics_manager / obstacle_manager
│              illusion_manager / knockback_physics
├── systems/   buff_system / spirit_system
├── ui/        main_menu / character_selection / preparation_ui / character_system
└── test/      player_3d_test / field_tag_test 等
```

**物理层**（`project.godot`）：players / ball / field_bounds / skills / penalty_walls

**数据**（`data/*.json`，开发者可热改）：7 球员 / 21 技能 / 6 元灵 / 元素克制

## 五-补、代码按需读取清单（⚠ 重要：不要全读）

全项目 49+ 个脚本 / 约 25000+ 行，**禁止启动时全读**。

**AI 子系统（最常读，共 ~8000 行）——改 AI 行为前必读这几个：**
| 文件 | 行数 | 作用 |
|---|---|---|
| `scripts/battle/ai_manager.gd` | 2260 | AI 决策状态机 + Steering + 工具函数 |
| `scripts/battle/player.gd` | 1138 | 球员逻辑（移动/体力/技能/韧性/3D模型挂载） |
| `scripts/battle/ball.gd` | 891 | 球物理 + 信号（影响接投球） |
| `scripts/battle/battle_manager.gd` | 1296 | 比赛主控 + auto_simulate |
| `scripts/battle/match_stats.gd` | 187 | 指标采集 |
| `scripts/battle/ai_profile.gd` | 337 | AI 参数/角色预设（调平衡先看这） |

**任务导航：**
- 修 AI bug → 先读 `ai_manager.gd` 对应状态/函数
- 调 AI 平衡 → 先读 `ai_profile.gd`（参数都在这）
- 改比赛流程 → 先读 `battle_manager.gd`
- 改球员/球手感 → 先读 `player.gd` / `ball.gd`
- 元灵技能/buff → `scripts/systems/spirit_system/` 下
- UI → `scripts/ui/` 下
- 3D 渲染 → `scripts/test/player_3d_test.gd`（独立测试场）

## 六、当前进度（指针，详见工作日志）

> **最近工作日志**：`工作日志/` 目录下最新文件 + `.workbuddy/memory/` 下最新记忆

- **AI P0（避障+防抖）**：✅ 完成，卡死清零
- **AI P1（效用曲线+系数 profile 化）**：✅ 完成
- **方案A（自动模拟比赛+指标）**：✅ 可用
- **6 元灵技能绑定**：✅ 完成（雷火/冰雪/草木/梦幻/大地/金刚）
- **六层状态系统**：✅ 完成（Buff/控制/持续/倍率/检查/标签）
- **3D 渲染进化（battle3d 模块，2026-09-10）**：Phase 0~5 ✅ 全部完成。2D 逻辑权威 + 3D 视觉代理（USE_3D_SCENE 默认 true，sim 强制纯 2D）。P1 场景复刻 144FPS；P3 白线双轨 22/22；P4 特效矩阵 18/18；单位制铁律=GD 像素 1:1。详见 docs/3D场景回归Godot融合方案.md
- **角色系统UI**：✅ 基础完成，鼠标穿透已修复
^- **3D 与主游戏隔离公约**：`player.gd` 的 `USE_3D_MODEL` 保持 `false`（旧 per-player 路线）；新 3D 走 `scripts/battle3d/`（USE_3D_SCENE 开关）

## 七、记忆资产索引

| 类型 | 位置 | 用途 |
|---|---|---|
| 工作日志 | `工作日志/*.md` | **跨会话交接主载体** |
| AI记忆 | `.workbuddy/memory/*.md` | workbuddy 专属记忆 |
| 设计文档 | `docs/` | 架构/AI/标签/buff/物理 |
| 验证基线 | `sim_results/baseline.json` | 模拟健康指标基准 |
| 未完成节点 | `docs/6.23前未完成节点.md` | 遗留问题追踪 |
| TRAE skills | `.trae/skills/` | TRAE 专属技能（本文件） |

## 八、TRAE 专属技能清单

- `project-context` — **本文件**，项目记忆中枢
- `battle-ball` — 项目开发流程铁律
- `bug-fix` — Bug 维修纪律
- `verify-before-deliver` — 交付前模拟验证纪律
- `write-log` — 工作日志规范化写作
- `new-project` — 新子项目/新功能模块化开发

## 九、跨工具交接协议

本项目同时用 pi、zcode、TRAE 等多个 AI 工具，交接靠**文件**：
1. **收尾时**：把本次成果写进 `工作日志/<日期>.md`
2. **开工时**：读本技能 + 读最近一份工作日志
3. 工作日志、docs、代码是所有工具共享的项目资产（git 跟踪）

## 十、关键参数备忘

- 分离力：`separation_inner=600` / `separation_outer=1400`（内外场）
- 队友感知半径：`separation_radius=80`
- 带球碰撞预测：`avoid_lookahead=0.4s`
- 决策防抖容差（按角色）：主攻5 / 防御8 / 辅助12
- 卡死换向滞回：`stuck_redecide_margin=30`
- 效用曲线：`curve_k` 默认 1.0，拐点 0.5
- GDScript 缩进用 **Tab**，不用空格
- Key 常量兼容：用整数键值最稳（Tab=16777217, F1=16777248...）

## 十一、Godot 4.x 踩坑记录

- `look_at()` 的 up 向量不能与相机到目标方向平行（俯视必须用 up=(0,0,-1)）
- `ImageTexture.set_flags()` 不存在（Godot 4.x）
- `create_from_image()` 只接受一个参数
- `BaseMaterial3D.DETAIL_BLEND_OFF` 不存在
- 贴图模糊根因：.png 默认 lossy VRAM 压缩，改 .import compress/mode=0 无损
- SubViewport 必须设 `world_3d=World3D.new()` + `Environment` + `UPDATE_ALWAYS`
- `player_model_3d.tscn` 的 [node] 块禁止 `#` 注释（导致 load() 失败）
- Key 常量 `KEY_TAB`/`KEY_F1` 等在不同 Godot 4.x 版本支持不一致

---

**给接手的 AI**：你现在的身份是决竞球项目的协作开发者。本文件已读，接下来读最近一份工作日志了解进度，然后等主人指令。称呼主人「主人」，遵守开发铁律，改 AI 代码记得跑 `run_sim.sh`（若环境可用）。
