---
name: vibe_task
description: "决竞球 vibecoding 任务路由器。主人不懂技术、用白话派活时必触发：点菜式接单（主人说编号即可）、三句话出任务、按任务规模分级挂技能链，技能默认执行不反问流程。主人说「出任务/派活/做功能/修bug/调平衡/调研」等任何开发任务指令，或直接丢一段需求描述时触发。"
---

# Skill: vibe_task — vibecoding 出任务路由器

> 主人不懂技术也能高效派活：主人只管**点菜（说编号）**或用三句话描述新任务，
> 窗口负责翻译成技术动作并**按规模挂链执行**，不在流程上反复请示。

## 一、点菜式派活（首选）

1. 主人说编号或菜名（例：「上③，给平台窗口」「把菜单①办了」）→ 窗口读 `docs/当前任务菜单.md` 对应条目，**以菜单为准，不让主人复述细节**。
2. **接单先核时效**：对照最新 `工作日志/` 确认该条目未被完成或变更；菜单过时则按日志现状干，收尾时顺手更新菜单。
3. 菜单里「拍板类」条目不是活，是待主人决策项——主人提到时先呈选项再动手。

## 二、三句话模板（菜单外的新任务）

```
【目标】给<谁/哪个系统>加/改<什么>，玩家<怎么感知>
【完成标准】<什么场景看到什么效果>；不破坏现有<XX>
【禁区/参考】不许动什么 / 参考原作哪段（可留空）
```

缺项由窗口按项目现状补全并写进复述让主人确认，**不反问主人技术细节**。

## 三、按规模分级挂链（省额度）

| 规模 | 判定 | 挂链 |
|---|---|---|
| 轻活 | 改 1-2 个函数 / 纯数值 / 注释 / 文案 | 复述确认 → bug_fix 核心纪律（一个根因+语法自检）→ 简短总结，**不跑全链** |
| 常规 | 单文件级功能调整 | 下方路由表对应链 → test_first → write_log |
| 重活 | 新系统 / 新工单 / 跨文件大改 | 路由表全链（new_project/subsystem_dev → 实现 → test_first → verify_before_deliver → write_log） |

## 四、任务类型路由表（常规/重活用）

| 主人的话 | 任务类型 | 技能链（按序执行） |
|---|---|---|
| 做个新功能 / 新模块 / 新玩法 | 新功能 | project-context → new_project（UI 外离散判定系统→subsystem_dev）→ 实现 → test_first → verify_before_deliver → write_log |
| 报错了 / 有bug / 不对劲 / 坏了 | 修 Bug | project-context → bug_fix → test_first → verify_before_deliver → write_log |
| 太强了 / 太弱了 / 调数值 / AI 太傻 | 平衡调参 | project-context(§10 参数备忘) → ai_profile.gd 调参 → verify_before_deliver(必跑模拟) → write_log |
| 技能 / 元灵相关 | 元灵技能 | project-context → 技能规划工单 → 实现 → test_first → verify_before_deliver → write_log |
| 界面 / 按钮 / 操作 | UI/操控 | project-context → 操控与基础Ui规划 工单体系 → 实现 → test_first → write_log |
| 调研 / 方案 / 规划 / 写文档 | 调研规划 | project-context → 产出文档（docs/ 或对应规划文件夹）→ write_log |
| 分不清 / 混合型 | 默认 | 按新功能链起步，复述时说明归类理由，主人可改 |

## 五、执行纪律

- **动手前窄读**：>500 行文件禁整读，先 grep `docs/code_map.md` 拿函数行号再读目标段 ±80 行（细节见 project-context §五-补 窄读铁律）。
- **两处必须停**：①复述纲要等主人确认（轻活可简化，修复/修改类必须等「同意」）②模拟危险项>0 停下修根因，不带病交付。
- **花积分操作**（Godot/Blender MCP、建模、批量跑批）先按 `integrity_budget_control` 报预算。
- **收尾四件套**：完成总结 + 改动文件清单 + 待办 + 工作日志（write_log）。
- 开发规范冲突时以 `battle-ball` / `test_first` / `verify_before_deliver` 为准，本技能只管路由和挂链。
