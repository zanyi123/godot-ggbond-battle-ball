---
name: project-context
description: 决竞球项目记忆中枢。新会话接手、开工、跨工具交接、理解项目上下文时必读。包含项目定位、开发铁律、验证纪律、架构速查、当前进度、记忆资产索引、跨工具交接协议。用于任何需要了解"这个项目是什么、怎么干、干到哪了"的场景，建议每次开工先触发本技能。
---

# 决竞球项目记忆中枢（zcode 专属）

> 本文件是 zcode 工作时的项目记忆。pi 有它自己的一套（`.pi/skills/`），互不干扰。
> **zcode 新会话开工第一动作：读本技能 + 读最近一份工作日志。**
> ⚠ **不要主动读全部代码**，按「代码按需读取清单」（第五-补节）按任务读相关文件。

## 一、项目定位

- **名称**：决竞球 Battle Ball（《猪猪侠之决竞球》同人 Godot 复刻）
- **类型**：6v6 球类对战游戏，核心玩法是 AI 球员战术对抗
- **引擎**：Godot 4.6 / GDScript
- **入口场景**：`res://scenes/main/main_menu.tscn`
- **当前重心**：AI 系统调优（决策/移动/感知/平衡）

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
├── ai/        （待建）
└── ui/        main_menu
```

**物理层**（`project.godot`）：players / ball / field_bounds / skills / penalty_walls

**数据**（`data/*.json`，开发者可热改）：6 球员 / 6 技能 / 6 元灵 / 元素克制

## 五-补、代码按需读取清单（⚠ 重要：不要全读）

全项目 49 个脚本 / 约 25000 行，**禁止启动时全读**（挤占上下文、注意力分散）。
按任务只读相关文件。`use` 用 `read` 工具或 `rg` 定位。

**AI 子系统（最常读，共 ~8000 行）——改 AI 行为前必读这几个：**
| 文件 | 行数 | 作用 |
|---|---|---|
| `scripts/battle/ai_manager.gd` | 2260 | AI 决策状态机 + Steering + 工具函数 |
| `scripts/battle/player.gd` | 1138 | 球员逻辑（移动/体力/技能/韧性） |
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
- 找某函数/字符串 → 先 `rg "关键词" scripts/`，别逐个读

**原则：**
1. 先按任务导航确定读哪 1-3 个文件，别撒网式读
2. 大文件（>800 行）用 `read` 的 `offset/limit` 分段读相关部分，别整文件吞
3. 拿不准位置先 `rg`，定位到行号再 `read`

## 六、当前进度（指针，详见工作日志）

> **最近一份：`工作日志/2026-06-17.md`** —— 接手前必读

- **AI P0（避障+防抖）**：✅ 完成，卡死清零，持续有效
- **AI P1（效用曲线+系数 profile 化）**：✅ 完成，8 权重 + 4 曲线字段
- **方案A（自动模拟比赛+指标）**：✅ 可用，`run_sim.sh` + `match_stats.gd`
- **5 元灵技能绑定**：✅ 完成（雷火/冰雪/草木/梦幻 + 原大地/金刚）
- **种子确定性**：✅ 同种子核心指标可复现
- **AI P2（影响力地图）**：⚠️ 函数已写未接入，需先做**位置缓存机制**防目标漂移卡死
- **待主人验证**：P0/P1 手感、5 元灵技能效果、能量/冷却 UI 表现

**下一阶段方向**（见 `docs/项目结构说明.md`）：第二阶段 AI 系统完善 / 备战场景 / 韧性公式 / 发球辅助线 UI

## 七、记忆资产索引

| 类型 | 位置 | 用途 |
|---|---|---|
| 工作日志 | `工作日志/2026-05-29.md` ~ `2026-06-17.md` | **跨会话交接主载体**，每次收尾写当日 |
| 设计文档 | `docs/` | 架构/AI 系统/标签/buff 状态机/物理/开发日志 |
| 方法论 | `docs/Vibecoding学习与实践记录.md`、`docs/AI协作开发效率指南.md` | 「如何与 AI 协作」的演进记录 |
| 设计问答 | `docs/问题提问日志.md` | 历史决策依据 |
| 验证基线 | `sim_results/baseline.json` | 模拟健康指标对比基准 |
| 技能 | `.zcode/skills/` | zcode 专属 6 个 skill（含本记忆中枢） |

## 八、zcode 专属技能清单（`.zcode/skills/`）

- `project-context` — **本文件**，项目记忆中枢（铁律/架构/进度/交接）
- `battle-ball` — 项目开发流程铁律（消歧义/纲要/精简/总结/自检）
- `bug_fix` — Bug 维修纪律（1 根因/3 文件/查语法）
- `verify_before_deliver` — 交付前模拟验证纪律（改 AI 代码必跑 run_sim）
- `new_project` — 新子项目/新功能模块化开发
- `write_log` — 工作日志规范化写作

触发：靠 description 自动加载；或 `/skill <名字> <指令>` 强制加载。

## 九、跨工具交接协议

本项目同时用 pi 和 zcode，**对话历史互不相通**（pi 存 `~/.pi/agent/sessions/*.jsonl`，zcode 存 `~/.zcode/cli/db/db.sqlite`）。交接靠**文件**，不靠聊天记录：

1. **收尾时**（任何工具）：把本次成果写进 `工作日志/<日期>.md`
2. **开工时**（zcode）：第一句话——「/skill project-context 然后读最近一份工作日志，接着干 XXX」
3. **切工具时**：照 `.zcode/交接模板.md` 填一页，新工具读它接手

工作日志、docs、代码是**两个工具共享的项目资产**（git 跟踪）；只有 skill 和对话历史是各自独立的。所以铁律/进度写在共享文件里两边都看得到，但记忆中枢 skill 各自维护。

## 十、关键参数备忘（避免重新踩坑）

- 分离力：`separation_inner=600` / `separation_outer=1400`（内外场）
- 队友感知半径：`separation_radius=80`
- 带球碰撞预测：`avoid_lookahead=0.4s`
- 决策防抖容差（按角色）：主攻5 / 防御8 / 辅助12
- 卡死换向滞回：`stuck_redecide_margin=30`
- 效用曲线：`curve_k` 默认 1.0，拐点 0.5（中点行为与原线性一致）

---

**给接手的 AI**：你现在的身份是决竞球项目的协作开发者。本文件已读，接下来读 `工作日志/2026-06-17.md` 了解最近进度，然后等主人指令。称呼主人「主人」，遵守开发铁律，改 AI 代码记得跑 `run_sim.sh`。
