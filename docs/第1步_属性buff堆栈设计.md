# 第1步：属性 Buff 堆栈设计

## 计算公式

```
最终值 = 基础值 × 所有乘法buff连乘 + 所有加法buff求和
```

举例（基础攻击50）：
- buff1：+30%（乘法 1.3）
- buff2：-20%（乘法 0.8）
- buff3：+10固定（加法 10）

最终 = 50 × 1.3 × 0.8 + 10 = 52

---

## 20个属性标签 → 公式与参与变量

### 攻击力（attack_power）

来源变量：`player.attack_power`（角色数据中的 attack_power 字段）

用途：作为球的伤害基数，由 `ball.attack_power` 继承

| # | 标签ID | 名称 | buff参数 | 计算方式 | 举例（基础=50） |
|---|--------|------|----------|----------|-----------------|
| 01 | `player_atk_up_pct` | 攻击提升(%) | mult=1.3 | 乘法 | 50×1.3 = **65** |
| 02 | `player_atk_down_pct` | 攻击降低(%) | mult=1/(1+x) | 乘法 | x=30→50×0.769 = **38.5** |
| 03 | `player_atk_up_flat` | 攻击提升(固定) | flat=+10 | 加法 | 50+10 = **60** |
| 04 | `player_atk_down_flat` | 攻击降低(固定) | flat=-10 | 加法 | 50-10 = **40** |

最终读取：`get_effective_attack()` = `(attack_power + flat总和) × mult连乘`

---

### 防御值（defense）

来源变量：`player.defense`（角色数据中的 defense 字段）

用途：参与伤害减免计算，公式为 `defense_resist = get_effective_defense() × defense_factor`

注意：**只改 defense，不改 defense_factor**。defense_factor 是角色固有属性（0.1~0.2），不参与buff

| # | 标签ID | 名称 | buff参数 | 计算方式 | 举例（defense=60, factor=0.15） |
|---|--------|------|----------|----------|----------------------------------|
| 05 | `player_def_up_pct` | 防御提升(%) | mult=1.3 | 乘法 | 60×1.3=78 → 抗伤=78×0.15=**11.7**（原9） |
| 06 | `player_def_down_pct` | 防御降低(%) | mult=1/(1+x) | 乘法 | x=30→60×0.769=46.2 → 抗伤=**6.9**（原9） |
| 07 | `player_def_up_flat` | 防御提升(固定) | flat=+10 | 加法 | 60+10=70 → 抗伤=70×0.15=**10.5** |
| 08 | `player_def_down_flat` | 防御降低(固定) | flat=-10 | 加法 | 60-10=50 → 抗伤=50×0.15=**7.5** |

最终读取：`get_effective_defense()` = `(defense + flat总和) × mult连乘`

实际抗伤 = `get_effective_defense() × defense_factor`（defense_factor不变）

---

### 移动速度（speed）

来源变量：`player.speed`（角色数据中的 speed 字段）

用途：`_physics_process` 中 `move_speed = get_effective_speed()` 控制每帧位移

| # | 标签ID | 名称 | buff参数 | 计算方式 | 举例（基础=200） |
|---|--------|------|----------|----------|-----------------|
| 09 | `player_spd_up_pct` | 速度提升(%) | mult=1.3 | 乘法 | 200×1.3 = **260** |
| 10 | `player_spd_down_pct` | 速度降低(%) | mult=1/(1+x) | 乘法 | x=30→200×0.769 = **153.8** |
| 11 | `player_spd_up_flat` | 速度提升(固定) | flat=+50 | 加法 | 200+50 = **250** |
| 12 | `player_spd_down_flat` | 速度降低(固定) | flat=-50 | 加法 | 200-50 = **150** |

最终读取：`get_effective_speed()` = `(speed + flat总和) × mult连乘`

---

### 韧性（resilience）

来源变量：`player.resilience`（角色数据中的 resilience 字段，范围0~100）

用途：查表决定三个效果：
- `_get_resilience_decay_rate(rd)` → 伤害衰减百分比（0%~50%）
- `_get_stagger_by_resilience(rd)` → 僵直时间（0.3s~0.7s）
- `_roll_resilience_effect(rd)` → 击退/弹飞概率

| # | 标签ID | 名称 | buff参数 | 计算方式 | 举例（基础=50） |
|---|--------|------|----------|----------|-----------------|
| 13 | `player_res_up_pct` | 韧性提升(%) | mult=1.3 | 乘法 | 50×1.3=65 → 衰减率从20%→30%档 |
| 14 | `player_res_down_pct` | 韧性降低(%) | mult=1/(1+x) | 乘法 | x=30→50×0.769=38.5 → 衰减率20%→10%档 |
| 15 | `player_res_up_flat` | 韧性提升(固定) | flat=+10 | 加法 | 50+10=60 → 衰减率跳到30%档 |
| 16 | `player_res_down_flat` | 韧性降低(固定) | flat=-10 | 加法 | 50-10=40 → 衰减率不变（20%档） |

最终读取：`get_effective_resilience()` = `(resilience + flat总和) × mult连乘`

---

### 最大能量（max_spirit_energy）

来源变量：`player.max_spirit_energy`（初始100）

用途：能量上限，影响 `spirit_energy` 的 clamp 上限和能量UI条

| # | 标签ID | 名称 | buff参数 | 计算方式 | 举例（基础=100） |
|---|--------|------|----------|----------|-----------------|
| 35 | `player_energy_max_up_pct` | 最大能量提升(%) | mult=1.3 | 乘法 | 100×1.3 = **130** |
| 36 | `player_energy_max_down_pct` | 最大能量降低(%) | mult=1/(1+x) | 乘法 | x=30→100×0.769 = **76.9** |
| 37 | `player_energy_max_up_flat` | 最大能量提升(固定) | flat=+20 | 加法 | 100+20 = **120** |
| 38 | `player_energy_max_down_flat` | 最大能量降低(固定) | flat=-20 | 加法 | 100-20 = **80** |

最终读取：`get_effective_max_energy()` = `(max_spirit_energy + flat总和) × mult连乘`

---

## 多buff叠加规则

同属性可以同时挂多个buff，计算时先乘后加：

```
最终值 = 基础值 × (乘法buff1 × 乘法buff2 × ...) + (加法buff1 + 加法buff2 + ...)
```

**举例（攻击力基础50）：**
- buff A：+30%攻击（乘法1.3，持续5秒）
- buff B：-20%攻击（乘法0.8，持续3秒）
- buff C：+10攻击（加法+10，持续4秒）

叠加结果 = 50 × 1.3 × 0.8 + 10 = 52 + 10 = **62**

3秒后B过期 → 50 × 1.3 + 10 = **75**

5秒后A过期 → 50 + 10 = **60**（C还有1秒）

6秒后C也过期 → **50**（回到基础值）

---

## Buff数据结构（纸条）

```gdscript
{
    "id": "buff_001",              # 唯一编号（同id重复add会覆盖旧值）
    "stat": "attack",              # 属性名：attack/defense/speed/resilience/max_energy
    "mult": 1.3,                   # 乘法修正（默认1.0=不改）
    "flat": 0.0,                   # 加法修正（默认0.0=不改）
    "source": "player_atk_up_pct", # 来自哪个标签（用于调试）
    "duration": 5.0,               # 持续时间（秒）
    "remaining": 5.0               # 剩余时间（每帧递减，到0自动删除）
}
```

每张纸条同时持有 mult 和 flat，大部分标签只填其中一个、另一个留默认值。

---

## 属性保护规则

1. **乘法结果不低于0.01**（防止属性归零）
2. **加法结果不设下限**（允许负值场景，如降防到负数）
3. **duration到期直接消失**（纯数值层，视觉由UI处理）

---

## 已确认问题

1. ✅ 降低公式用 `1/(1+x)`（永不为负）
2. ✅ 乘法结果下限0.01
3. ✅ 到期直接消失，无淡出
4. ✅ 防御只改 defense 值，defense_factor 不参与buff
