# 04 · 地基修复计划：_ball_mods 按投球者隔离（V1 步骤1 详细路线）

> 目标缺陷：技能规划/01 缺口台账 #1（全局污染）+ #2 相关的 ball 越界直写（债务 P2-1 第一轮）。
> 性质：**缺陷修复**（现有管道坏了），不是新原语。
> **范围声明（防误解）**：本档只覆盖 `_ball_mods` 地基修复（V1-1），**不含任何原语工单**。护盾（V1-2）/区域触发（V1-3）是加新能力，另出独立计划——分开是为每批独立验证独立回退（地基批验收="行为与修复前一致"，原语批验收="新能力生效"）。
> 状态：计划待主人批准。批准后按步执行，每步独立验证可回退。
> 制定：2026-09-19（基于当日代码实读，行号以此为准）。

---

## 一、现状数据流（为什么坏）

```
技能释放（任何人）                    投球（任何人）                     球飞行中
trigger._fire_skill()               ball.launch(attacker)              ball._physics_process
  ├ reset_ball_mods() ←—— ①擦掉全局唯一一张纸（覆盖别人没生效的）  │
  └ handler._apply_ball_xxx          ├ 从组里抓 handler 实例              ├ 直读 handler._ball_mods
     直接写全局 _ball_mods ②          ├ 读 getter 算伤害/速度             ├ 直写 tracking_target/boomerang
      （无 duration 字段，           └ 直读 _ball_mods.lockon_target       （伸手进口袋）
       写了就一直有效）
```

**三个具体坏点**：
1. **串味**：全局一张纸——A 开增伤没投，B 投球吃到 A 的增伤
2. **覆盖**：任何人放技能先擦纸——A 的 3 秒增益被 B 的技能直接清掉
3. **无期限**：字典里没有 expires 字段，效果写到下一次任何人放技能为止

**附带病灶**：ball.gd:656 类型直引 handler + :271/277/281/291 直写其私有字典 + :740 组查找——ball 与 handler 双向纠缠（改 handler 字段名 ball 五处连带崩）。

---

## 二、修复目标（修成什么样）

```
技能释放（A）                        投球（X）                        球飞行中
trigger._fire_skill(caster=A)       ball.launch(attacker=X)          ball 读自己的快照
  └ handler 写 A 的准备区            ├ 向 handler 要 X 的快照            （回旋/追踪状态机字段
     _ball_mods_by_caster[A]        │   （过期的字段按默认值算）          全部内联为球私有状态）
     （每人一张纸+到期时间）          └ 注入 ball.ball_mods 快照
                                    取走即清 X 的准备区（expiry 兜底）
```

**验收标准（全部满足才算修好）**：
1. A 开增益、B 投球 → B 的球不吃 A 的任何修饰（隔离断言）
2. 带 duration 的修饰到期 → 快照中该字段回落默认值（过期断言）
3. 玩家/AI/被动三条投球路径行为与修复前一致（回归：run_sim 危险=0，球速分布/命中轨迹与基线无明显漂移）
4. ball.gd 中不再出现 `_ball_mods` 直读直写（grep 断言）

---

## 三、修复路线（四步，每步独立验证可回退）

### Step 0：调用链梳理（0.5 批次，只读不改）
- 确认 ball.launch() 的全部调用方（玩家路径/AI 路径/sim 路径）与 attacker 参数可靠性
- 确认"旧式技能"注入路径（ball.gd:714 `_apply_ball_skill`，不走 handler 的旧体系）不受影响
- 产出：一张真实调用链图贴进本文件（执行时补）

**产出（2026-09-19 实测，行号为当日快照）**：

```
【投球路径 → ball.launch(from, dir, dmg, dist, attacker, skills, ...)】
玩家:  battle_manager.gd:369  attacker=真实球员 ✓
AI:    ai_manager.gd:1942/1994 attacker=真实球员 ✓
测试:  test_air_throw 等存在 attacker=null → 快照注入须容忍 null（无攻击者=无技能修饰，快照默认即等价）
sim:   AI 路径同源（ai_manager）

【技能修饰注入（新体系）】
trigger._fire_skill(caster)
  ├ handler.reset_ball_mods()        ← 全清（覆盖根源，Step2 改为清指定 caster）
  └ handler.apply_tag_effect(tag_id, params, caster_id)
      └ _apply_ball_xxx × 15 写入全局 _ball_mods（dmg_up/down、penetrate、armor、
        speed_up/down、range_up/down、lockon、tracking、boomerang、straight）
      （ball_avoid/ball_spread 两标签 handler 标记成功但 ball.gd 无消费——快照等价带上）

【投球消费（ball.gd 当日行号）】
launch:658      → :719-720 get_modified_ball_damage/speed（读全局）
                → :723-726 直读 _ball_mods.lockon_target
飞行:           → :263 is_ball_tracking / :267 get_tracking_target
                → :271/:277 直写 tracking_target=null（隐身/失效）
                → :274 get_tracking_turn_speed
                → :281/:284 直读 boomerang_dist/boomerang_triggered → :285 trigger_boomerang
                → :291 直读 lock_straight
命中:           → :463-465 AOE(has_ball_aoe/radius/pct) → :505-506 penetrate/tracking
弹道豁免:       → :971/:973 is_ball_tracking / is_ball_boomerang
类型直引:       → :654 var tag_effect_handler: SpiritTagEffectHandler
                → :740-750 _get_tag_effect_handler() 组查找 + is 类型判断

【旧体系（零交叉确认 ✓）】
launch :707-710 skills 参数 tag=="on_ball" → _apply_ball_skill(:785)：fire/ice 纯元素弹道，
不读不写 handler._ball_mods，与新体系无任何交叉，本轮不动。
```

### Step 1：球侧快照化（1 批次，纯等价重构）
**改 ball.gd**：
- 新增成员 `var ball_mods: Dictionary = {...默认值同 reset 字典}` ——球的私有快照
- launch() 里：从 handler 取 `take_ball_mods_snapshot(attacker)` 注入（组查找保留但**只调这一个公开只读方法**）
- 全部消费点改读自身快照：
  - 飞行段 ：263-291（追踪/回旋/直行）→ 读 ball_mods；`tracking_target=null`、`boomerang_triggered/return_dir` 等**飞行状态字段内联为球私有变量**（handler.trigger_boomerang 逻辑内联进 ball）
  - 命中段 ：463-487（AOE）、:505（穿透）
  - launch 段 ：717-726（伤害/速度/锁定）
  - :967-975（弹道豁免判定）
- 删除 ：656 类型直引与直写（:271/277/281/291 全消失）

**改 handler**：新增公开只读 `take_ball_mods_snapshot(caster) -> Dictionary`（v1 行为=返回全局 _ball_mods 副本，等价过渡）；getter（get_modified_ball_damage 等）改造成对传入快照运算的静态/实例双态。

**验证**：headless 编译 + test_ballistic_ball/test_air_throw/test_fp_mode 全过 + run_sim 危险=0 + grep 断言（ball 无 `_ball_mods` 字样）。此步行为与修复前完全一致。

### Step 2：按投球者隔离 + 有效期（1 批次，行为修复）
**改 handler**：
- `_ball_mods` → `_ball_mods_by_caster: Dictionary`（caster_id → mods 字典）
- 写入 API（_apply_ball_xxx 系列，:644/:655 等约 15 处写入点）带 caster_id——标签 case 本就有 caster_id 上下文，顺参数即可
- 写入时带 `expires_at`（tags 的 duration 参数 × 当前比赛时钟；无 duration=投球前不过期）
- `take_ball_mods_snapshot(caster)`：取该 caster 的准备区 → 过期字段回落默认值 → **取走即清**该准备区（expiry 作兜底清理，定时清扫挂 handler 现有 tick）
- reset_ball_mods() 退役（改为清指定 caster，_fire_skill 不再全清）

**设计取舍（执行时确认）**：取走即清 vs 保留至过期——v1 选**取走即清**（一技一球语义，简单）；原语#8 分裂工单时再改"保留至 expiry"（一技多球）。

**验证**：新增 `scripts/test3d/regression/test_ball_mods_isolation.gd`（或 test/ 同级）：三断言（隔离/过期/三路径回归）+ run_sim 危险=0。

### Step 3：收尾与回写（0.5 批次）
- handler 旧 getter 清理、注释更新（"球落地/回收时清空"的历史注释与实现对齐）
- 回写：01 缺口台账 #1 打勾、P2-1 提示词标记"第一轮完成"（第二轮=彻底解耦注入链，视情况另立项）、02 §七批次记录、工作日志

**合计 ≈ 3 个批次。**

---

## 四、风险与协调

| 风险 | 缓解 |
|---|---|
| Step1 动 ball.gd 核心飞行段，与债务窗口 P0-2（AOE 落空）同文件 | **开工前问主人 P0-1/P0-2 窗口状态**；错开执行；每步 git 可回退 |
| P0-1（双扣能）若属实会改 trigger，与 Step2 的写入 API 改动相邻 | 同上——建议 P0-1 先出验证结果 |
| 追踪目标 Node 引用存快照，球回收悬挂 | 快照清空时 tracking_target 置 null（回收路径已有 reset 点） |
| 旧式技能体系（_apply_ball_skill）误伤 | Step0 先隔离确认，两体系不交叉 |
| AI 行为漂移（AI 靠技能修饰的球速/伤害评估） | run_sim 球速分布+事件账本 diff 对比基线，漂移超预期即停 |

## 五、执行记录

| 步 | 日期 | 状态 | 验证结果 | 备注 |
|---|---|---|---|---|
| 0 | 2026-09-19 | ✅ | 调用链图已贴（上文）；P0-1 已先行修复完成（trigger 单点扣费），P0-2 未开工、错开满足 | attacker=null 测试路径需容忍 |
| 1 | 2026-09-19 | ✅ | test_ballistic_ball / test_air_throw / test_fp_mode 全 PASS + run_sim 3 场危险=0 + grep 断言：ball 无 `_ball_mods` 直读直写、无 handler 类型引用 | ball 快照化+回旋状态内联；handler 增 take_ball_mods_snapshot 与 getter 双态 |
| 2 | 2026-09-19 | ✅ | 新增 test_ball_mods_isolation 9/9 PASS（隔离/过期/取走即清/兼容视图/清扫）+ 回归三测试 PASS + test_skill_mults 22/22 + run_sim 3 场危险=0 | `_ball_mods_by_caster` + expires_at（比赛时钟）+ 取走即清；兼容视图保 AI/测试面板零改动 |
| 3 | 2026-09-19 | ✅ | 01 台账 #1 ✅、02 §七批次记录、本文档回写、P2-1 标注、工作日志 | 第二轮（彻底解耦注入链：快照由 player/handler 注入而非 ball 组查找）视情况另立项 |
