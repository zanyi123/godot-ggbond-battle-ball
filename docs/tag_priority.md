# 标签执行优先级设计

> 目的：多个技能标签作用同一对象时（间隔 < 0.1s），按优先级顺序执行，让比赛状态更真实。

## 跨大类执行顺序

**FIELD → PLAYER → BALL**

- 场地是环境基础（先改场地）
- 球员状态是主体（叠buff、点灯、控制）
- 球是投射物（带着所有加成结算）

---

## 一、BALL类（17个）— 对球效果

| 优先级 | 编号 | tag_id | 名称 | 说明 |
|--------|------|--------|------|------|
| **B-10** | | | **数值修改层** | 先改球的基础数值 |
| B-11 | 01 | ball_dmg_up_pct | 增伤(%) | 伤害×% |
| B-12 | 02 | ball_dmg_down_pct | 减伤(%) | 伤害÷% |
| B-13 | 03 | ball_dmg_up_flat | 增伤(固定) | 伤害+固定 |
| B-14 | 04 | ball_dmg_down_flat | 减伤(固定) | 伤害-固定 |
| B-15 | 05 | ball_speed_up_pct | 加速(%) | 球速×% |
| B-16 | 06 | ball_speed_down_pct | 减速(%) | 球速÷% |
| B-17 | 07 | ball_speed_up_flat | 加速(固定) | 球速+固定 |
| B-18 | 08 | ball_speed_down_flat | 减速(固定) | 球速-固定 |
| **B-20** | | | **飞行行为层** | 改球怎么飞 |
| B-21 | 09 | ball_tracking | 追踪 | 持续转向追人 |
| B-22 | 10 | ball_avoid | 避障 | 自动避开障碍 |
| B-23 | 11 | ball_boomerang | 回旋 | 飞一半返回 |
| B-24 | 12 | ball_straight | 直行 | 直线不受干扰 |
| B-25 | 13 | ball_lockon | 精准锁定 | 发球自动瞄准 |
| B-26 | 14 | ball_spread | 扩散 | 碰撞分裂 |
| **B-30** | | | **穿透/范围层** | 命中后效果 |
| B-31 | 15 | ball_penetrate | 穿透 | 击穿不停止 |
| B-32 | 16 | ball_range_up | 范围扩大 | AOE伤害 |
| B-33 | 17 | ball_range_down | 范围缩小 | 缩AOE |

---

## 二、FIELD类（12个）— 对场地效果

| 优先级 | 编号 | tag_id | 名称 | 说明 |
|--------|------|--------|------|------|
| **F-10** | | | **障碍层** | 场地实体 |
| F-11 | 01 | field_obs_add | 创造障碍 | 放障碍物 |
| F-12 | 02 | field_obs_clear | 清除障碍 | 拆障碍物 |
| **F-20** | | | **地形层** | 物理属性 |
| F-21 | 03 | field_terra_change | 地形改变 | 摩擦/弹性 |
| F-22 | 04 | field_terra_revert | 地形恢复 | 还原 |
| F-23 | 05 | field_zone_mark | 区域标注 | 标区域类型 |
| F-24 | 06 | field_zone_clear | 区域清除 | 清标注 |
| **F-30** | | | **区域效果层** | 区域内持续效果 |
| F-31 | 07 | field_zone_boost | 加速区 | 区域内加速 |
| F-32 | 08 | field_zone_slow | 减速区 | 区域内减速 |
| F-33 | 09 | field_zone_danger | 危险区 | 区域内伤害 |
| F-34 | 10 | field_zone_safe | 安全区 | 区域内免疫 |
| **F-40** | | | **视觉层** | 幻象/干扰 |
| F-41 | 11 | field_illusion_add | 幻象生成 | 假目标 |
| F-42 | 12 | field_illusion_clear | 幻象破除 | 破幻象 |

---

## 三、PLAYER类（51个）— 对球员效果

| 优先级 | 编号 | tag_id | 名称 | 说明 |
|--------|------|--------|------|------|
| **P-10** | | | **规则修改层** | 修改后续标签的结算规则（最先执行） |
| P-11 | 39 | player_spirit_cost_down | 减少消耗 | 技能消耗×倍率 |
| P-12 | 40 | player_spirit_cost_up | 增加消耗 | 技能消耗×倍率 |
| P-13 | 42 | player_spirit_cd_down | 冷却缩短 | CD×倍率 |
| P-14 | 43 | player_spirit_cd_up | 冷却延长 | CD×倍率 |
| P-15 | 44 | player_spirit_double | 双倍效果 | 下次技能×2 |
| P-16 | 45 | player_spirit_half | 效果减半 | 下次技能×0.5 |
| P-17 | 41 | player_spirit_uses_up | 增加使用次数 | 技能+次数 |
| **P-20** | | | **属性Buff层** | 叠加修改属性值（依赖P-10的规则） |
| P-21 | 01 | player_atk_up_pct | 攻击提升(%) | |
| P-22 | 02 | player_atk_down_pct | 攻击降低(%) | |
| P-23 | 03 | player_atk_up_flat | 攻击提升(固定) | |
| P-24 | 04 | player_atk_down_flat | 攻击降低(固定) | |
| P-25 | 05 | player_def_up_pct | 防御提升(%) | |
| P-26 | 06 | player_def_down_pct | 防御降低(%) | |
| P-27 | 07 | player_def_up_flat | 防御提升(固定) | |
| P-28 | 08 | player_def_down_flat | 防御降低(固定) | |
| P-29 | 09 | player_spd_up_pct | 速度提升(%) | |
| P-30 | 10 | player_spd_down_pct | 速度降低(%) | |
| P-31 | 11 | player_spd_up_flat | 速度提升(固定) | |
| P-32 | 12 | player_spd_down_flat | 速度降低(固定) | |
| P-33 | 13 | player_res_up_pct | 韧性提升(%) | |
| P-34 | 14 | player_res_down_pct | 韧性降低(%) | |
| P-35 | 15 | player_res_up_flat | 韧性提升(固定) | |
| P-36 | 16 | player_res_down_flat | 韧性降低(固定) | |
| P-37 | 35 | player_energy_max_up_pct | 最大能量提升(%) | |
| P-38 | 36 | player_energy_max_down_pct | 最大能量降低(%) | |
| P-39 | 37 | player_energy_max_up_flat | 最大能量提升(固定) | |
| P-40 | 38 | player_energy_max_down_flat | 最大能量降低(固定) | |
| **P-30** | | | **状态灯层** | 点灯/灭灯 |
| P-31 | 17 | player_invincible | 无敌 | |
| P-32 | 18 | player_vulnerable | 易伤 | |
| P-33 | 19 | player_stealth | 隐身 | |
| P-34 | 20 | player_reveal | 显形 | |
| **P-40** | | | **运动控制层** | 限制/增强移动 |
| P-41 | 27 | player_move_slow | 减速 | |
| P-42 | 28 | player_move_boost | 加速 | |
| P-43 | 29 | player_root | 定身 | |
| P-44 | 30 | player_unroot | 自由 | |
| **P-50** | | | **控制层** | 限制行动 |
| P-51 | 46 | player_stun | 眩晕 | |
| P-52 | 47 | player_cc_immune | 免疫控制 | |
| P-53 | 48 | player_silence | 沉默 | |
| P-54 | 49 | player_disarm | 缴械 | |
| **P-60** | | | **即时效果层** | 即时结算（依赖前面所有buff的最终值） |
| P-61 | 21 | player_hp_heal_pct | 恢复(%) | |
| P-62 | 22 | player_hp_damage_pct | 掉血(%) | |
| P-63 | 23 | player_hp_heal_flat | 恢复(固定) | |
| P-64 | 24 | player_hp_damage_flat | 掉血(固定) | |
| P-65 | 25 | player_hp_regen | 持续恢复 | |
| P-66 | 26 | player_hp_dot | 持续掉血 | |
| P-67 | 31 | player_energy_gain_pct | 能量恢复(%) | |
| P-68 | 32 | player_energy_cost_pct | 能量消耗(%) | |
| P-69 | 33 | player_energy_gain_flat | 能量恢复(固定) | |
| P-70 | 34 | player_energy_cost_flat | 能量消耗(固定) | |
| **P-70** | | | **交互层** | 位置改变 |
| P-71 | 50 | player_teleport | 传送 | |
| P-72 | 51 | player_return | 返回 | |

---

## 设计原则

1. **修改结算规则的先执行** — 减少消耗/双倍效果影响后续标签的数值计算
2. **修改自身属性的接着执行** — buff栈叠加，此时消耗已确定
3. **状态灯再执行** — 点灯/灭灯依赖buff是否已存在
4. **控制类再执行** — 眩晕/沉默/缴械
5. **即时效果最后执行** — 扣血/回血/能量变动，依赖前面buff的最终属性值
6. **位置改变最末** — 传送/返回，不影响任何数值

## 落实机制

在 `SpiritTagEffectHandler` 中：
- 新增 `_tag_priority` 字典：tag_id → 优先级数字
- 新增待执行队列 `_pending_tags`：多个标签在 0.1s 内到达时排队
- 新增 `_flush_timer`：0.1s 窗口到期后按优先级排序执行
- 单个标签直接执行不走队列（无并发时零开销）
