# 元灵技能AI集成方案

> 本文档描述元灵技能AI如何嵌入现有球员AI系统，与 `ai_manager.gd`、`ai_profile.gd`、`spirit_system_manager.gd` 配合工作。

---

## 一、集成架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                        Battle Scene                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐       ┌─────────────────┐                      │
│  │ GameManager │───────▶│ BattleManager   │                      │
│  └─────────────┘       └────────┬────────┘                      │
│                                 │                                │
│          ┌──────────────────────┼──────────────────────┐        │
│          │                      │                      │        │
│  ┌───────▼───────┐    ┌────────▼────────┐   ┌─────────▼────────┐│
│  │  ai_manager   │◀──▶│spirit_ai_manager│──▶│spirit_system_mgr ││
│  │  (球员AI)      │    │  (技能AI决策器)   │   │  (技能执行器)    ││
│  └───────┬───────┘    └────────┬────────┘   └─────────┬────────┘│
│          │                     │                      │         │
│          ▼                     ▼                      ▼         │
│  ┌─────────────┐    ┌─────────────────┐   ┌───────────────────┐│
│  │  ai_profile │    │skill_decision_  │   │skill_trigger      ││
│  │  (参数模板)  │    │  template       │   │  (技能触发器)     ││
│  └─────────────┘    │  (个性化决策模板) │   │  tag_effect_      ││
│                     └─────────────────┘   │  handler(效果处理) ││
│                                          └───────────────────┘│
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 二、新增文件

### 2.1 `spirit_ai_manager.gd`（元灵技能AI决策器）

**位置**：`scripts/battle/spirit_ai_manager.gd`

**职责**：
- 赛前分析：根据球员属性+元灵技能（含复合技能）生成个性化决策模板
- 赛中决策：每间隔计算技能评分，选最高分释放
- 调用 `spirit_system_manager.use_skill()` 执行技能

**核心接口**：

| 方法 | 功能 |
|------|------|
| `initialize(battle_mgr, spirit_sys_mgr, ai_mgr)` | 初始化，建立引用 |
| `register_player(player, profile)` | 注册AI球员，生成决策模板（含复合技能分析） |
| `_physics_process(delta)` | 主循环，每间隔决策一次 |
| `_evaluate_all_skills(ap)` | 评估所有可用技能，返回最高分 |
| `_compute_skill_score(ap, skill)` | 计算单个技能评分（支持复合技能） |
| `_should_use_energy(ap, skill_score)` | 动态能量评估 |
| `_normalize_tags(tag_data)` | **复合技能处理**：tag 字段归一化（字符串/数组） |
| `_compute_base_value(tags, ...)` | **复合技能处理**：按多标签权重计算基础价值 |
| `_determine_intents(tags, ...)` | **复合技能处理**：按多标签权重合并意图 |

---

## 三、修改文件

### 3.1 `ai_profile.gd`（新增元灵技能AI参数）

在现有参数基础上新增：

```gdscript
# ──── 元灵技能AI参数（2026-07-13 新增）────
# 技能释放评分阈值
var skill_use_threshold: float = 40.0
# 使用技能的最低能量要求
var skill_energy_min: float = 20.0
# 能量保留权重（越高越倾向保留）
var skill_reserve_weight: float = 0.9
# 进攻/防御/支援意图权重
var skill_attack_intent_weight: float = 1.0
var skill_defense_intent_weight: float = 1.0
var skill_support_intent_weight: float = 1.0
# 技能决策间隔（秒）
var skill_think_interval: float = 0.5
# 末段技能释放加成
var skill_late_game_bonus: float = 1.5
# 落后时技能释放加成
var skill_losing_bonus: float = 1.3
# 领先时技能释放惩罚
var skill_leading_penalty: float = 0.7
# 未来机会不确定性折扣
var skill_uncertainty_discount: float = 0.6
# 未来技能使用预期评分（基准）
var skill_expected_future_score: float = 50.0
# 元素克制加成/惩罚
var skill_element_counter_bonus: float = 1.3
var skill_element_counter_penalty: float = 0.7
# 连招组合额外加成
var skill_combo_bonus: float = 0.5
# 威胁评估权重（影响目标选择）
var skill_threat_assessment_weight: float = 0.3
# 距离因素权重（影响目标选择）
var skill_distance_factor_weight: float = 0.1
# 局势阅读深度（随难度变化）
var skill_situation_reading_depth: int = 3
# 技能使用精准度（随难度变化）
var skill_accuracy: float = 0.7
# 技能失误率（随难度变化）
var skill_mistake_chance: float = 0.15
# 关键协同技能加成
var skill_synergy_bonus_critical: float = 1.5
# 高协同技能加成
var skill_synergy_bonus_high: float = 1.3
```

**角色预设中新增技能AI参数**：

```gdscript
match role_name:
    "attacker":
        # ... 现有参数 ...
        skill_reserve_weight = 0.7        # 机会型，更愿意现在用
        skill_attack_intent_weight = 1.4
        skill_defense_intent_weight = 0.9
        skill_support_intent_weight = 1.0
        skill_think_interval = 0.3        # 决策快

    "defender":
        # ... 现有参数 ...
        skill_reserve_weight = 1.1        # 预判型，更愿意保留
        skill_attack_intent_weight = 0.9
        skill_defense_intent_weight = 1.4
        skill_support_intent_weight = 1.0
        skill_think_interval = 0.4        # 决策慢

    "supporter":
        # ... 现有参数 ...
        skill_reserve_weight = 0.9        # 响应型，接近中性
        skill_attack_intent_weight = 1.0
        skill_defense_intent_weight = 1.0
        skill_support_intent_weight = 1.4
        skill_think_interval = 0.35       # 决策较快
```

**难度修正中新增**：

```gdscript
static func apply_difficulty(profile: AIProfile, difficulty: String) -> void:
    match difficulty:
        "easy":
            # ... 现有修正 ...
            profile.skill_use_threshold *= 1.4      # 更高阈值，更少用技能
            profile.skill_mistake_chance = 0.3      # 高失误率
            profile.skill_situation_reading_depth = 1
            profile.skill_accuracy = 0.4
            profile.skill_reserve_weight = 1.3      # 更保守
            
        "normal":
            pass
            
        "hard":
            # ... 现有修正 ...
            profile.skill_use_threshold *= 0.6      # 更低阈值，更多用技能
            profile.skill_mistake_chance = 0.0      # 零失误
            profile.skill_situation_reading_depth = 6
            profile.skill_accuracy = 1.0
            profile.skill_reserve_weight = 0.7      # 更激进
```

---

### 3.2 `ai_manager.gd`（集成技能AI调用）

**修改点1**：初始化时创建并注册技能AI管理器

```gdscript
# 在 _ready() 或 initialize() 中
var spirit_ai_mgr: Node = null

func initialize(battle_mgr: Node2D, input_mgr: Node) -> void:
    battle_manager = battle_mgr
    input_manager = input_mgr
    
    # 创建并初始化技能AI管理器
    spirit_ai_mgr = SpiritAIManager.new()
    spirit_ai_mgr.name = "SpiritAIManager"
    add_child(spirit_ai_mgr)
    spirit_ai_mgr.initialize(battle_manager, battle_manager.spirit_system, self)
```

**修改点2**：`register_player()` 中注册到技能AI

```gdscript
func register_player(player: CharacterBody2D, team_name: String, index: int, profile: AIProfile) -> void:
    # ... 现有注册逻辑 ...
    
    # 注册到技能AI管理器
    if spirit_ai_mgr:
        spirit_ai_mgr.register_player(player, profile)
```

**修改点3**：`_physics_process()` 中调用技能AI

```gdscript
func _physics_process(delta: float) -> void:
    if not battle_manager:
        return
    if not battle_manager.match_started:
        return
    
    # ... 现有AI决策逻辑 ...
    
    # 技能AI决策（每帧调用，内部有计时控制）
    if spirit_ai_mgr:
        spirit_ai_mgr._physics_process(delta)
```

**修改点4**：决策时考虑技能就绪度（已有 `_eval_active_skill_ready()`，保留）

---

### 3.3 `battle_manager.gd`（提供 spirit_system 引用）

确保 `battle_manager` 有 `spirit_system` 属性可供访问：

```gdscript
var spirit_system: SpiritSystemManager = null

func _ready():
    spirit_system = get_node_or_null("SpiritSystemManager")
```

---

## 四、spirit_ai_manager.gd 核心实现

### 4.1 初始化与注册

```gdscript
extends Node

const AIProfile = preload("res://scripts/battle/ai_profile.gd")

var battle_manager: Node2D
var spirit_system: SpiritSystemManager
var ai_manager: Node
var ball_node: Area2D

# 技能AI数据（每个AI球员一份）
var spirit_ai_data: Array[Dictionary] = []

func initialize(battle_mgr: Node2D, spirit_sys: SpiritSystemManager, ai_mgr: Node) -> void:
    battle_manager = battle_mgr
    spirit_system = spirit_sys
    ai_manager = ai_mgr
    print("[SpiritAI] 初始化完成")

func register_player(player: CharacterBody2D, profile: AIProfile) -> void:
    # 赛前分析：生成个性化决策模板
    var decision_template = _generate_decision_template(player, profile)
    
    spirit_ai_data.append({
        "player": player,
        "profile": profile,
        "decision_template": decision_template,
        "skill_think_timer": randf() * profile.skill_think_interval,
        "current_intent": "attack",
        "last_skill_use_time": 0.0,
        "consecutive_skill_uses": 0,
    })
    
    print("[SpiritAI] 注册球员: %s, 技能数: %d" % [player.name, len(decision_template.skills_analysis)])
```

### 4.2 赛前分析：生成决策模板

```gdscript
func _generate_decision_template(player: CharacterBody2D, profile: AIProfile) -> Dictionary:
    var template: Dictionary = {}
    
    # 1. 球员属性分析
    template["player_profiling"] = _analyze_player(player)
    
    # 2. 技能深度分析
    var player_skills = spirit_system.get_player_skills(player.get_instance_id())
    template["skills_analysis"] = []
    for skill_id in player_skills:
        var skill_data = DataManager.get_skill_by_id(skill_id)
        template["skills_analysis"].append(_analyze_skill(skill_data, player, profile))
    
    # 3. 能量管理策略
    template["energy_strategy"] = _determine_energy_strategy(player, profile)
    
    # 4. 组合策略
    template["combo_strategy"] = _determine_combo_strategy(template["skills_analysis"])
    
    return template
```

### 4.3 球员分析

```gdscript
func _analyze_player(player: CharacterBody2D) -> Dictionary:
    var weaknesses: Array = []
    var strengths: Array = []
    
    # 归一化属性（假设最大值为100）
    var def_norm = player.defense / 100.0
    var sta_norm = player.stamina / player.max_stamina if player.max_stamina > 0 else 0.0
    var res_norm = player.resilience / 100.0 if hasattr(player, "resilience") else 0.5
    var spd_norm = player.speed / 100.0
    var atk_norm = player.attack / 100.0
    
    # 判定弱点/强项
    if def_norm < 0.5:
        weaknesses.append("defense_low")
        if def_norm < 0.3:
            weaknesses.append("defense_critical")
    if sta_norm < 0.5:
        weaknesses.append("stamina_low")
    if res_norm < 0.5:
        weaknesses.append("resilience_low")
    
    if spd_norm > 0.7:
        strengths.append("speed_high")
    if atk_norm > 0.7:
        strengths.append("attack_high")
    
    # 生存风险等级
    var risk_score = (1-def_norm)*0.3 + (1-sta_norm)*0.3 + (1-res_norm)*0.2 + (1-spd_norm)*0.2
    var risk_level = "low"
    if risk_score > 0.6:
        risk_level = "high"
    elif risk_score > 0.3:
        risk_level = "medium"
    
    return {
        "weaknesses": weaknesses,
        "strengths": strengths,
        "risk_level": risk_level,
    }
```

### 4.4 技能深度分析

```gdscript
func _analyze_skill(skill_data: Dictionary, player: CharacterBody2D, profile: AIProfile) -> Dictionary:
	var analysis: Dictionary = {}
	analysis["skill_id"] = skill_data.get("id", "")
	analysis["skill_name"] = skill_data.get("name", "")
	analysis["energy_cost"] = skill_data.get("energy_cost", 20)
	analysis["cooldown"] = skill_data.get("cooldown", 10.0)
	analysis["element"] = skill_data.get("element", "")
	
	# === 复合技能处理：tags 归一化 ===
	var raw_tag = skill_data.get("tag", "")
	analysis["tags"] = _normalize_tags(raw_tag)
	analysis["tag_count"] = analysis["tags"].size()
	# 多标签权重：1=100%/2=70%/3=50%
	match analysis["tag_count"]:
		1: analysis["tag_weight"] = 1.0
		2: analysis["tag_weight"] = 0.7
		3: analysis["tag_weight"] = 0.5
		_: analysis["tag_weight"] = 0.4
	
	# 按每个标签分别分析
	analysis["tags_analysis"] = []
	for tag in analysis["tags"]:
		var tag_data = spirit_system.get_tag_data(tag)
		analysis["tags_analysis"].append(_analyze_tag(tag, tag_data, player))
	
	# 复合技能意图合并（各标签意图按 tag_weight 加权叠加）
	analysis["intents"] = _determine_intents(analysis["tags"], skill_data.get("values", {}))
	analysis["primary_intent"] = _get_primary_intent(analysis["intents"])
	
	# 复合技能协同度（各标签分别计算后取最高）
	analysis["synergy_level"] = _calculate_synergy_max(analysis["tags"], player)
	
	# 局势响应规则（按主标签生成）
	analysis["situation_rules"] = _generate_situation_rules(analysis)
	
	return analysis
```

### 4.5 赛中决策主循环

```gdscript
func _physics_process(delta: float) -> void:
    if not battle_manager or not battle_manager.match_started:
        return
    
    if not ball_node:
        ball_node = battle_manager.ball_node
    if not ball_node:
        return
    
    for sad in spirit_ai_data:
        if not _is_valid_spirit_ai(sad):
            continue
        
        sad.skill_think_timer += delta
        if sad.skill_think_timer >= sad.profile.skill_think_interval:
            sad.skill_think_timer = 0.0
            _decide_skill(sad)

func _is_valid_spirit_ai(sad: Dictionary) -> bool:
    var p = sad.player
    if not p or not is_instance_valid(p):
        return false
    if ai_manager and ai_manager.input_manager:
        if ai_manager.input_manager.controlled_player == p:
            return false
    if p.is_defeated:
        return false
    return true

func _decide_skill(sad: Dictionary) -> void:
    var p = sad.player
    var profile = sad.profile
    var template = sad.decision_template
    
    # 1. 检查能量
    if p.spirit_energy < profile.skill_energy_min:
        return
    
    # 2. 获取可用技能（冷却已结束）
    var available_skills = []
    for skill_analysis in template["skills_analysis"]:
        var cd = spirit_system.get_skill_cooldown(p.get_instance_id(), skill_analysis["skill_id"])
        if cd <= 0.0 and p.spirit_energy >= skill_analysis["energy_cost"]:
            available_skills.append(skill_analysis)
    
    if available_skills.is_empty():
        return
    
    # 3. 评估所有可用技能
    var best_skill = null
    var best_score = -INF
    
    for skill_analysis in available_skills:
        var score = _compute_skill_score(sad, skill_analysis)
        
        # 难度修正
        var normalized_diff = (profile.skill_accuracy - 0.5) * 2
        score *= (1.0 + normalized_diff * 0.3)
        
        # 失误机制
        if randf() < profile.skill_mistake_chance:
            score *= randf_range(0.5, 1.5)
        
        if score > best_score:
            best_score = score
            best_skill = skill_analysis
    
    # 4. 动态能量评估
    if best_skill and not _should_use_energy(sad, best_score):
        return
    
    # 5. 释放技能
    if best_skill and best_score >= profile.skill_use_threshold:
        _execute_skill(sad, best_skill)
```

### 4.6 技能评分计算

```gdscript
func _compute_skill_score(sad: Dictionary, skill_analysis: Dictionary) -> float:
    var p = sad.player
    var profile = sad.profile
    var template = sad.decision_template
    
    # 1. 基础价值（技能效果价值）
    var base_value = _compute_base_value(skill_analysis)
    
    # 2. 局势因子
    var situation_factor = _compute_situation_factor(sad, skill_analysis)
    
    # 3. 意图匹配度
    var intent_match = _compute_intent_match(sad, skill_analysis)
    
    # 4. 协同度加成
    var synergy_bonus = 1.0
    match skill_analysis["synergy_level"]:
        "critical": synergy_bonus = profile.skill_synergy_bonus_critical
        "high": synergy_bonus = profile.skill_synergy_bonus_high
    
    # 5. 元素克制
    var element_factor = _compute_element_factor(sad, skill_analysis)
    
    # 总分
    return base_value * situation_factor * intent_match * synergy_bonus * element_factor
```

### 4.7 动态能量评估

```gdscript
func _should_use_energy(sad: Dictionary, current_score: float) -> bool:
    var profile = sad.profile
    
    # 当前价值
    var energy_value_now = current_score
    
    # 未来预期价值
    var time_remaining = _get_time_remaining_ratio()
    var energy_value_future = profile.skill_expected_future_score * time_remaining * profile.skill_uncertainty_discount
    
    # 局势修正
    var situation_modifier = _get_situation_reserve_modifier(sad)
    
    # 角色保留权重
    var effective_reserve = profile.skill_reserve_weight * situation_modifier
    
    return energy_value_now > energy_value_future * effective_reserve
```

### 4.8 技能执行

```gdscript
func _execute_skill(sad: Dictionary, skill_analysis: Dictionary) -> void:
    var p = sad.player
    var profile = sad.profile
    
    # 确定目标
    var target_data = _determine_target(sad, skill_analysis)
    
    # 调用技能系统
    var success = spirit_system.use_skill(p.get_instance_id(), skill_analysis["skill_id"], target_data)
    
    if success:
        sad.last_skill_use_time = OS.get_ticks_msec() / 1000.0
        sad.consecutive_skill_uses += 1
        
        # 更新球员状态（视觉反馈）
        if p.has_method("set_active_skill"):
            p.set_active_skill(skill_analysis["skill_id"])
        
        print("[SpiritAI] %s 使用技能: %s" % [p.name, skill_analysis["skill_name"]])
```

---

## 五、数据流转图

```
赛前：
  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────────┐
  │ characters.json │───▶│ _analyze_player │───▶│ player_profiling    │
  └─────────────────┘    └─────────────────┘    │ (弱点/强项/风险)    │
                                                └─────────┬───────────┘
                                                          │
  ┌─────────────────┐    ┌─────────────────┐              ▼
  │  skills.json    │───▶│ _analyze_skill  │───▶┌─────────────────────┐
  └─────────────────┘    └─────────────────┘    │ skills_analysis     │
                                                │ (标签分析/意图/协同)│
                                                └─────────┬───────────┘
                                                          │
  ┌─────────────────┐    ┌──────────────────┐             ▼
  │   ai_profile    │───▶│ _generate_rules  │───▶┌─────────────────────┐
  └─────────────────┘    └──────────────────┘    │ decision_template   │
                                                │ (完整个性化模板)     │
                                                └─────────────────────┘

赛中：
  ┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐
  │ 实时局势数据     │───▶│ _compute_situation│───▶│ situation_factor    │
  │ (球权/分差/体力) │    │    _factor       │    └─────────┬───────────┘
  └─────────────────┘    └──────────────────┘              │
                                                          ▼
  ┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐
  │ decision_template│───▶│ _compute_skill   │───▶│ total_score         │
  │ (赛前生成)       │    │    _score        │    └─────────┬───────────┘
  └─────────────────┘    └──────────────────┘              │
                                                          ▼
                                                ┌─────────────────────┐
                                                │ _should_use_energy │
                                                │ (动态能量评估)      │
                                                └─────────┬───────────┘
                                                          │
                                            ┌──────────────┴──────────────┐
                                            ▼                               ▼
                                      能量评估通过                   能量评估不通过
                                            │                               │
                                            ▼                               ▼
                              ┌─────────────────────┐              ┌─────────────────────┐
                              │ spirit_system.       │              │ 等待下次决策         │
                              │ use_skill()         │              └─────────────────────┘
                              │ (执行技能)          │
                              └─────────────────────┘
```

---

## 六、与球员AI的配合时机

| 球员AI状态 | 技能AI行为 | 说明 |
|-----------|-----------|------|
| `IDLE` / `DEFEND` | 评估防御/支援技能 | 无球待机时，准备防守或支援队友 |
| `CHASE_BALL` / `GOTO_BALL` | 评估加速/位移技能 | 追球时，用技能提升追球效率 |
| `DRIBBLE` | 评估球强化/加速技能 | 带球时，准备进攻技能 |
| `ATTACK` | 评估球强化/伤害技能 | 投球前，用技能增强攻击效果 |
| `PASS` | 评估球控制/加速技能 | 传球前，用技能提升传球成功率 |
| `SUPPORT` | 评估支援/控场技能 | 跑位时，准备支援队友 |
| `READY_CATCH` | 评估防御/护盾技能 | 准备接球时，用技能保护自己 |

---

## 七、关键设计决策

### 7.1 独立决策循环

技能AI有自己独立的决策间隔（`skill_think_interval`），不与球员AI的决策间隔绑定。原因：
- 技能决策不需要每帧计算（能量、冷却变化慢）
- 降低性能开销
- 更符合真实玩家的思考节奏

### 7.2 赛前模板生成

所有个性化分析在赛前完成，赛中只做评分计算。原因：
- 赛中计算量减少，提升性能
- 模板可以被多个决策周期复用
- 便于调试（赛前模板可以打印检查）

### 7.3 动态能量评估

不使用固定阈值，而是比较"现在用的价值"vs"留到未来的价值"。原因：
- 关键球时刻低能量也该用
- 垃圾时间高能量也不该浪费
- 角色风格影响保留意愿（主攻手机会型 vs 防御手预判型）

### 7.4 意图匹配度

用"意图"替代"技能类型"作为评估维度。原因：
- 同一个PLAYER类技能，不同角色看到不同意图
- 主攻手给自己加攻=进攻准备，不是"不爱PLAYER技能"
- 防御手用球强化=转守为攻，不是"不爱BALL技能"

### 7.5 协同度计算

技能与球员属性的协同度决定使用优先级。原因：
- 菲菲（防御低）+ 草木（防御buff）= critical，必须优先用
- 菲菲（防御低）+ 梦幻（无防御技能）= 隐身变成唯一保命手段
- 超人强（无弱点）+ 大地（岩石墙）= high，可以攒能量

---

## 八、实现优先级

| Phase | 内容 | 依赖 |
|-------|------|------|
| **Phase 1** | 框架搭建 + BALL类技能评分 | ai_profile 参数 + spirit_system 接口 |
| **Phase 2** | PLAYER类技能评分 + 目标选择 | Phase 1 |
| **Phase 3** | FIELD类技能评分 + 位置选择 | Phase 2 |
| **Phase 4** | 动态能量评估 + 组合策略 | Phase 3 |
| **Phase 5** | 难度系统对接 + 元素克制 | Phase 4 |
| **Phase 6** | 团队配合（队友技能联动） | Phase 5 |

---

## 九、注意事项

1. **性能**：技能AI决策间隔设为0.5秒，避免每帧计算
2. **技能冲突**：同一时刻只能释放一个技能，需加互斥判断
3. **视觉反馈**：技能释放后调用 `set_active_skill()` 更新球员状态
4. **错误处理**：`use_skill()` 返回失败时需处理（能量不足/冷却未结束）
5. **调试**：赛前模板打印到控制台，便于检查分析结果
