# 13 · handler 拆分与数据归一方案（#1 复制系前置闸门，报批稿）

> 依据：12 工单 #1 闸门 + 08 §六 + 总纲 §1.7（唯一全局手术）。
> 性质：**纯等价重构**方案——批准后先行重构，run_sim 全量 diff 无实质差异才准叠加复制系功能。
> 制定：2026-09-22（实施窗口出稿）。状态：**✅ 已批准（2026-09-22 主人拍板方案 A：拆分+复制系一批做）**。
> ⚠ 文件撞号更正待执行：本文件应更名《15_handler拆分与数据归一方案.md》（与《13_基础UI批次规划》撞号），实施窗口开工第一步执行更名并同步所有引用。
> 批准时同步的引导词见文末。
> **执行记录（2026-09-22 规划窗口验收）**：拆分落地=facade 57行+ball_route 285/player_route 369/field_route 297/base_route 859（shared_tools 并入 base_route，命名变体可接受）；复制系四件套齐（环形缓冲20条+防自噬/敌方快照检索/复制折扣执行/SKILL_COPIED 反制钩子+暗黑共享槽）。
> 待补三项（不阻塞）：①实施工作日志未写 ②13→15 更名未执行 ③copy_last 的 params 名 damage_pct 实折能耗（语义错位，建议改 cost_pct）——波7 工单附带整改。

---

## 一、现状（2026-09-22 实测）

`spirit_tag_effect_handler.gd` **约 1500 行 / 100+ case 分发 / 90+ 函数**，单文件承载四条消费路线：
1. **BALL 路线**：`_apply_ball_*` → 写 `_ball_mods_by_caster` 准备区 → ball.launch 快照消费（波1 后已按投球者隔离）
2. **PLAYER 路线**：`_apply_player_*` → 状态灯/buff/tick/倍率 → player 六层管道消费
3. **FIELD 路线**：`_apply_field_*` + zone 四类+HEAL+VISION → ObstacleManager / FieldZoneManager / pending 桥（V1-3）
4. **优先级队列**：`_tag_priority` 100+ 条 + FLUSH_WINDOW 排队/flush

已确认的耦合痛点：三条路线共享一份 params 构建与目标选取工具（_get_caster/_get_player_targets/_get_enemies）+ 一个 match 分发 + 一张优先级表——新增原语必须四处登记（02"AI 评分必填"之外第五处）。

## 二、拆分目标（拆三路线文件 + facade）

```
spirit_system/
  spirit_tag_effect_handler.gd   → 纯 facade（分发 + 信号 + 队列调度，~200行）
  handler/ball_route.gd          → BALL 路线（ball_mods_by_caster + take_ball_mods_snapshot + _apply_ball_*）
  handler/player_route.gd        → PLAYER 路线（_apply_player_* + TOGGLE_STATUS_MAP）
  handler/field_route.gd         → FIELD 路线（obstacle/zone/vision/pending + spawn_at 桥）
  handler/shared_tools.gd        → 共享工具（目标选取/caster 查找/元素色/expire 标记）
```

**facade 契约（对外零变化）**：
- 类名 `SpiritTagEffectHandler` 保留（spirit_system_manager 引用不动）
- 公开方法签名不变：`apply_tag_effect / _do_apply_tag / take_ball_mods_snapshot / get_modified_ball_damage / get_modified_ball_speed / has_tag / _tag_priority`
- 信号不变：effect_applied / effect_finished / skill_ui_feedback
- 内部：facade 持有三路线子节点实例，`_do_apply_tag` 按 category 转发；工具经 shared_tools 静态/注入共享

**数据归一（与拆分同批）**：
- registry `params` 数组与 handler 实际消费键的账实核对脚本（`tag_audit` 已有雏形，收编为常驻测试）
- `_tag_priority` 表迁至 `handler/priority_table.gd`（数据文件化，JSON 常量）

## 三、实施步骤（每步可回退）

| 步 | 内容 | 验证 |
|---|---|---|
| 1 | 建 handler/ 目录骨架 + shared_tools 抽取（纯搬运） | 编译+全量回归 |
| 2 | BALL 路线迁出（含 ball_mods_by_caster） | 波1 隔离测试 9/9 + run_sim diff |
| 3 | PLAYER 路线迁出（含波3 六件） | wave3 22/22 + run_sim diff |
| 4 | FIELD 路线迁出（含 zone/obstacle 桥） | wave5 18/18 + zone 11/11 + run_sim diff |
| 5 | facade 瘦身 + 优先级表数据化 | 全量回归 + **run_sim 3 场×seed1-3 diff 对比基线（比分/事件账本无实质差异）** |
| 6 | 复制系功能叠加（trigger 历史缓冲 + skill_copy_last/skill_share_copy + skill_copied 事件） | 12 工单 #1 断言 |

## 四、风险与回滚

- 每步一个 git 提交点，任意步可回退
- 最大风险=GDScript 引用传递（子节点持有 battle_manager/players 引用需同步注入——setup_battle_refs 链路扩展）
- 等价性判据：重构前后 run_sim 同 seed 对局的**事件账本 diff 为空**（比分/击中/接球序列逐条比对）

## 五、执行记录

| 步 | 日期 | 状态 | 备注 |
|---|---|---|---|
| 批准 | 2026-09-22 | ✅ | 主人令"现在做13方案"=批准执行 |
| 步1~5 | 2026-09-22 | ✅ | **实现机制=GDScript extends 继承链**（base←ball←player←field←facade，四文件拼一类，状态/方法同实例解析，等价性最强）；两处发现并修正：①信号声明必须在链底 base；②基类静态调子层方法不允许→分发处改 call() 动态（match 内 `_apply_*` 与兄弟层 `_apply_field_zone_effect`）。验证：语法四文件 OK+全量回归全绿（三件套+10 项 headless）+run_sim 3 场危险=0 |
| 步6 复制系 | 2026-09-22 | ✅ | trigger 历史环形缓冲20（复制系不入史防自噬）+暗黑共享槽+SKILL_COPIED 事件（event_bus 新枚举）+skill_copy_last（折扣复制/fallback）+skill_share_copy；handler trigger_ref 注入口；test_skill_copy **7/7**+run_sim 3 场危险=0 |
| 收官 | 2026-09-22 | ✅ | **23/23 原语全部落地** |

---

## 附：开工引导词（2026-09-22 主人批准方案A，填好版直接粘贴）

```
主人已批准《15_handler拆分与数据归一方案》（方案A：拆分+复制系一批做）。
按方案严格执行，顺序与闸门如下：

第0步 文件更名：本文档更名《技能规划/15_handler拆分与数据归一方案.md》
（与《13_基础UI批次规划》撞号），同步更新 08/12 工单里的所有引用。

第一步 等价重构（方案 §三 第1~5步，严格按步走，每步验证后才准进下一步）：
- handler 拆三路线文件+facade+shared_tools，对外接口零变化
- 每步：对应波次测试全过 + run_sim diff
- 第5步完成 = 重构验收闸门：run_sim 3 场×seed1-3 与基线对比，
  比分/事件账本无实质差异——不达标停下回报，禁止带病叠加

第二步 复制系叠加（方案 §三 第6步）：
- trigger 技能释放历史环形缓冲 + skill_copy_last/skill_share_copy + skill_copied 事件
- 按 12 工单 #1 断言执行（快照覆盖/折扣执行/无快照fallback/事件可订阅）

边界红线（08 §五 全程有效）：
1. 禁止改 data/spirits/skills.json 任何技能条目
2. 禁止表现层；3. 拆分中发现的存量问题一律记录上报不修；
4. 除本方案外不做其他批次原语/其他改动；5. 拿不准停下来问，汇报只报事实。

最终验收：重构 diff 无实质差异 + 复制系断言全过 + 全量回归（150+ 断言）+
run_sim 3 场危险总数=0 → 原语 23/23 收官；
回写 02 台账（#1）/08 执行记录/15 方案执行记录/工作日志，汇报只报事实数据。
```
