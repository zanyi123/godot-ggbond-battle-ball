# 元灵技能标签系统 - 架构文档

## 系统概述

元灵技能标签系统是一个模块化的效果系统，通过标签来定义技能的效果，实现技能与效果解耦。

### 设计原则
1. **标签驱动**：每个技能通过标签定义效果
2. **对称设计**：每个标签都有反向标签
3. **类型分类**：按作用对象分为 BALL / FIELD / PLAYER 三大类
4. **模块化**：各组件独立可测试

---

## 系统架构

```
技能使用 → 技能触发器 → 标签注册表 → 效果处理器 → 实际效果 → UI反馈
   ↓           ↓            ↓             ↓           ↓          ↓
 use_skill  trigger_skill  tags_registry  apply_tag_effect  效果执行  ui_feedback
```

---

## 核心组件

### 1. 标签注册表 (tags_registry.json)

**路径**: `data/spirits/tags_registry.json`

**功能**: 定义所有标签的元数据

**数据结构**:
```json
{
  "tags": [
    {
      "id": "ball_dmg_up",
      "code": "01",
      "category": "BALL",
      "sub_category": "伤害",
      "name": "增伤",
      "reverse": "ball_dmg_down",
      "description": "伤害提升（百分比/固定值）",
      "params": ["value_type", "value", "duration"],
      "target_type": "ball"
    }
  ]
}
```

**字段说明**:
- `id`: 标签唯一标识
- `code`: 标签编号
- `category`: 大分类 (BALL/FIELD/PLAYER)
- `sub_category`: 子分类 (伤害/速度/范围等)
- `name`: 标签名称
- `reverse`: 反向标签ID
- `description`: 标签描述
- `params`: 标签参数列表
- `target_type`: 目标类型

---

### 2. 技能触发器 (SpiritSkillTrigger.gd)

**路径**: `scripts/systems/spirit_system/spirit_skill_trigger.gd`

**功能**:
- 检测技能使用
- 检查技能冷却
- 消耗技能能量
- 读取技能标签
- 调用效果处理器
- 发送UI反馈信号

**主要方法**:
- `trigger_skill(player_id, skill_id, target_data)`: 触发技能（主入口）
- `set_player_skills(player_id, skill_ids)`: 设置玩家上场技能
- `get_skill_cooldown(player_id, skill_id)`: 获取技能冷却时间
- `setup_battle_refs(battle_manager, players, ball)`: 设置战斗引用

**信号**:
- `skill_triggered(skill_id, caster_id, target_data)`: 技能触发
- `skill_effect_applied(skill_id, tag_id, effect_result)`: 技能效果应用
- `skill_ui_feedback(effect_type, effect_data)`: UI反馈

---

### 3. 标签效果处理器 (SpiritTagEffectHandler.gd)

**路径**: `scripts/systems/spirit_system/spirit_tag_effect_handler.gd`

**功能**:
- 执行标签对应的效果
- 管理持续效果堆栈
- 发送效果应用/结束信号

**主要方法**:
- `apply_tag_effect(tag_id, params, caster_id)`: 执行标签效果（主入口）
- `remove_tag_effect(effect_id)`: 清除标签效果
- `_process(delta)`: 更新持续效果

**效果函数**: (预留框架，待实现)
- 对球效果: `_apply_ball_dmg_up()`, `_apply_ball_speed_up()` 等
- 对场地效果: `_apply_field_obs_add()`, `_apply_field_zone_boost()` 等
- 对球员效果: `_apply_player_atk_up()`, `_apply_player_hp_heal()` 等

**信号**:
- `effect_applied(tag_id, effect_data)`: 效果已应用
- `effect_finished(tag_id, effect_data)`: 效果已结束

---

### 4. 系统管理器 (SpiritSystemManager.gd)

**路径**: `scripts/systems/spirit_system/spirit_system_manager.gd`

**功能**:
- 整合所有组件
- 提供统一入口
- 信号转发

**主要方法**:
- `initialize(battle_manager, players, ball_node)`: 初始化系统
- `set_player_skills(player_id, skill_ids)`: 设置玩家上场技能
- `use_skill(player_id, skill_id, target_data)`: 使用技能（统一入口）
- `get_skill_cooldown(player_id, skill_id)`: 获取技能冷却
- `get_player_skills(player_id)`: 获取玩家技能列表

**信号**:
- `skill_used(skill_id, caster_id, success)`: 技能已使用
- `effect_applied(tag_id, effect_data)`: 效果已应用
- `ui_feedback(effect_type, effect_data)`: UI反馈

---

## 5. 技能数据 (skills.json)

**路径**: `data/spirits/skills.json`

**功能**: 定义技能及其标签

**数据结构**:
```json
{
  "skills": [
    {
      "id": "skill_jingang_1",
      "name": "猛虎金刚闪",
      "element": "金刚",
      "type": "active",
      "energy_cost": 30,
      "cooldown": 8.0,
      "description": "金刚元灵奥义，凝聚金刚之力猛虎般冲击前方，造成大范围伤害",
      "detail": "伤害范围：前方扇形120度\n基础伤害：攻击力×1.5\n元灵能量消耗：30\n冷却时间：8秒",
      "icon_color": "#FFD700",
      "tags": ["ball_dmg_up", "ball_range_up"],
      "tag_params": {
        "ball_dmg_up": {
          "value_type": "percentage",
          "value": 50,
          "duration": 0
        },
        "ball_range_up": {
          "multiplier": 1.2,
          "duration": 0
        }
      }
    }
  ]
}
```

**字段说明**:
- `id`: 技能唯一标识
- `name`: 技能名称
- `element`: 元素属性
- `type`: 技能类型 (active/passive)
- `energy_cost`: 能量消耗
- `cooldown`: 冷却时间（秒）
- `tags`: 标签ID列表
- `tag_params`: 各标签的参数配置

---

## 系统流程

### 技能使用流程

```
1. 玩家使用技能
   ↓
2. SpiritSystemManager.use_skill()
   ↓
3. SpiritSkillTrigger.trigger_skill()
   ├── 检查玩家是否有该技能
   ├── 检查冷却时间
   ├── 检查能量消耗
   ├── 读取技能数据 (skills.json)
   ├── 读取技能标签 (tags_registry.json)
   ├── 触发信号 skill_triggered
   ↓
4. SpiritSkillTrigger._execute_skill_tags()
   ├── 遍历技能的标签列表
   ├── 构建标签参数
   ├── 调用效果处理器
   ↓
5. SpiritTagEffectHandler.apply_tag_effect()
   ├── 根据标签ID执行对应效果函数
   ├── 发送信号 effect_applied
   ├── 如有持续时间，加入效果堆栈
   ↓
6. 效果生效 (TODO: 具体实现)
   ↓
7. 发送UI反馈信号
   ├── skill_effect_applied
   ├── skill_ui_feedback
   └── ui_feedback
```

---

## 当前状态

### ✅ 已完成
1. 标签注册表 (68个标签)
2. 技能触发器框架
3. 标签效果处理器框架 (所有效果函数预留)
4. 系统管理器
5. 技能数据 (猛虎金刚闪 + 标签配置)

### 🔄 待完成
1. 标签效果函数具体实现
2. 能量系统对接
3. 冷却系统对接
4. UI反馈系统对接
5. 具体效果数值平衡

---

## 使用示例

### 初始化系统

```gdscript
# 在战斗场景中初始化
var spirit_system = SpiritSystemManager.new()
add_child(spirit_system)

spirit_system.initialize(battle_manager, players, ball_node)

# 设置玩家上场技能
spirit_system.set_player_skills(player_id_1, ["skill_jingang_1"])
```

### 使用技能

```gdscript
# 玩家使用技能
var success = spirit_system.use_skill(player_id, "skill_jingang_1", target_data)

# 检查冷却
var cooldown = spirit_system.get_skill_cooldown(player_id, "skill_jingang_1")
```

### 监听信号

```gdscript
# 监听技能使用
spirit_system.skill_used.connect(func(skill_id, caster_id, success):
    print("技能使用: ", skill_id, " 施法者: ", caster_id, " 成功: ", success)
)

# 监听效果应用
spirit_system.effect_applied.connect(func(tag_id, effect_data):
    print("效果应用: ", tag_id)
)

# 监听UI反馈
spirit_system.ui_feedback.connect(func(effect_type, effect_data):
    print("UI反馈: ", effect_type)
    # 更新UI显示
)
```

---

## 扩展新技能

### 1. 在 skills.json 中添加技能

```json
{
  "id": "skill_new_1",
  "name": "新技能",
  "element": "新元素",
  "type": "active",
  "energy_cost": 25,
  "cooldown": 10.0,
  "description": "技能描述",
  "detail": "详细说明",
  "icon_color": "#FF0000",
  "tags": ["ball_speed_up", "player_atk_up"],
  "tag_params": {
    "ball_speed_up": {
      "multiplier": 1.5,
      "duration": 5.0
    },
    "player_atk_up": {
      "value_type": "percentage",
      "value": 20,
      "duration": 5.0
    }
  }
}
```

### 2. 确保标签存在于 tags_registry.json

### 3. 如需新标签，添加到 tags_registry.json

### 4. 实现新标签的效果函数（在 SpiritTagEffectHandler.gd 中）

```gdscript
func _apply_new_tag_effect(params: Dictionary) -> void:
    # 实现具体效果
    pass
```

---

## 标签清单

### 对球 (BALL) - 14个标签
- 伤害: ball_dmg_up, ball_dmg_down, ball_penetrate, ball_armor
- 速度: ball_speed_up, ball_speed_down
- 范围: ball_range_up, ball_range_down, ball_lockon, ball_spread
- 轨迹: ball_tracking, ball_avoid, ball_boomerang, ball_straight

### 对场地 (FIELD) - 14个标签
- 障碍: field_obs_add, field_obs_clear, field_obs_move, field_obs_lock
- 地形: field_terra_change, field_terra_revert, field_zone_mark, field_zone_clear
- 区域: field_zone_boost, field_zone_slow, field_zone_danger, field_zone_safe
- 视觉: field_illusion_add, field_illusion_clear

### 对球员 (PLAYER) - 40个标签
- 属性: player_atk_up/down, player_def_up/down, player_spd_up/down, player_res_up/down (8)
- 状态: player_invincible/vulnerable, player_stealth/reveal, player_clone/clear (6)
- 体力: player_hp_heal/damage, player_hp_regen/dot (4)
- 运动: player_move_slow/boost, player_root/unroot (4)
- 能量: player_energy_gain/cost, player_energy_max_up/down (4)
- 元灵: player_spirit_cost_up/down, player_spirit_uses_up, player_spirit_cd_up/down, player_spirit_double/half (7)
- 控制: player_stun, player_cc_immune, player_silence, player_disarm/undisarm (5)
- 交互: player_teleport/return (2)

**总计: 68个标签**

---

## 注意事项

1. 标签效果函数目前是空框架，待后续实现具体逻辑
2. 能量消耗和冷却系统需要与现有系统对接
3. UI反馈信号需要与UI系统对接
4. 参数构建逻辑需要根据具体标签完善
5. 持续效果堆栈需要更完善的管理机制