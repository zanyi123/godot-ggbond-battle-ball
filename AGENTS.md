# AGENTS.md — 决竞球 Battle Ball（AI 代理说明书）

> 跨工具通用（ZCode / TRAE / Codex / Cursor / Claude Code 均识别本文件）。
> 原则：只写指针和铁律摘要，细节进技能文件，避免双头维护失同步。

## 项目是什么

- 《猪猪侠之决竞球》同人 **Godot 4.6 / GDScript** 复刻：3v3 球类对战，核心是 AI 球员战术对抗
- 入口场景 `res://scenes/main/main_menu.tscn`；**2D 玩法层是逻辑权威**，3D 只是视觉代理（`scripts/battle3d/`，`USE_3D_SCENE` 开关，sim 强制纯 2D）
- 全项目 49+ 脚本 / 25000+ 行，**禁止启动时全读代码**

## 开工第一动作（每次会话必做）

1. 读项目记忆中枢技能：`.zcode/skills/project-context/SKILL.md`（铁律/架构速查/按需读取清单/参数备忘/Godot 踩坑）
2. 读 `工作日志/` 目录最新一份，了解进度
3. 然后等主人指令，回复开头称呼「主人」

## 任务路由（主人不懂技术，窗口负责把白话翻译成技术动作）

路由器技能：`.zcode/skills/vibe_task/SKILL.md`（按任务类型默认串联技能链，技能默认执行）：

- 修 Bug / 报错 → `bug_fix`（一轮只修一个根因，最多改 1-3 文件，改完必查语法）
- 新功能 / 新模块 → `new_project`（UI 外的离散判定系统 → `subsystem_dev`）
- 全部代码任务 → `test_first`（自检自测全部通过才交付）
- 改 AI 相关文件（ai_manager / ai_profile / battle_manager / game_manager / match_stats / ball）→ `verify_before_deliver`：必跑 `./run_sim.sh 3 6 1 80`，对照 `sim_results/baseline.json`，**危险总数 = 0 才能交付**
- 收尾 → `write_log` 写工作日志

## 铁律摘要（完整版见 `battle-ball` 技能）

- 动手前：消歧义 + 复述 + 纲要，等主人确认（修复/修改类必须等「同意」；新建文件类可简化）
- 过程精简；完成必须总结（做了什么 / 改了哪些文件 / 有何待办）
- GDScript 缩进用 **Tab**；3D 层单位 = GD 像素 1:1 零换算；FBX 缩放恒 1.0（`player_3d_test.gd` 810 行铁律）
- 花积分操作（Godot/Blender MCP、建模、批量跑批）前先按 `integrity_budget_control` 报预算

## 出任务与提示词

主人出任务模板（vibecoding 三件套）与成熟提示词库出处：`docs/vibecoding提示词库.md`

## 交接协议

本项目多工具协作（pi / zcode / TRAE），交接靠文件：收尾写 `工作日志/<日期>.md`，开工读它 + 记忆中枢。工作日志、docs、代码是所有工具共享的 git 资产。
