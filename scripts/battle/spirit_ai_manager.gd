extends Node

const AIProfile = preload("res://scripts/battle/ai_profile.gd")

const GOAL_A: Vector2 = Vector2(300.0, 0.0)
const GOAL_B: Vector2 = Vector2(-300.0, 0.0)

## 失误局部短冷却（02前置地基工单追加，主人批"按你的做"）：
## 失误后冻结该技能 N 个决策周期，封死"重选→重掷"高频循环；
## 以 skill_decide_count 为时钟（确定性），不引入墙钟
const MISTAKE_HOLD_CYCLES := 3

## ===== 原语层接线（06§五集成契约，2026-09-26 集成窗口）=====
## 波函数表用 preload 本地词表（新脚本类名未进全局缓存时按名引用会解析失败，波C实录教训）；
## 开关语义单口收口在 registry（08工单）——查不到描述符=自然走旧评分分支，本文件各接线点
## 在未命中时与旧版行为逐位一致（manager 对开关零感知、零条件分支）
const SpiritAIPrimitiveRegistry := preload("res://scripts/battle/spirit_ai/primitive_registry.gd")
const PRIMITIVES_A := preload("res://scripts/battle/spirit_ai/primitives_a.gd")
const PRIMITIVES_B := preload("res://scripts/battle/spirit_ai/primitives_b.gd")
const PRIMITIVES_C := preload("res://scripts/battle/spirit_ai/primitives_c.gd")
const PRIMITIVES_D := preload("res://scripts/battle/spirit_ai/primitives_d.gd")
const EVENT_HOOKS_SCRIPT := preload("res://scripts/battle/spirit_ai/event_hooks.gd")
const AI_INPUT_SOURCE := preload("res://scripts/battle/spirit_ai/ai_input_source.gd")

## wave 字母 → 契约函数表分发（registry 按 JSON 顶层 wave 打标；波E 未交付=无条目=未命中）
const _WAVE_PRIMITIVES := {"A": PRIMITIVES_A, "B": PRIMITIVES_B, "C": PRIMITIVES_C, "D": PRIMITIVES_D}

## 原语 ctx 默认威胁半径（06§三 self_threatened 判定，manager 组装时可调）
const PRIMITIVE_THREAT_RADIUS := 200.0

var battle_manager: Node2D
var spirit_system: SpiritSystemManager
var ai_manager: Node
var ball_node: Area2D

var spirit_ai_data: Array[Dictionary] = []

var element_counters: Dictionary = {}
var counter_multiplier: float = 1.3

## 波B事件钩子实例（受击/异常状态反应热窗口；总线在首次物理帧挂接）
var _event_hooks = null
var _hooks_attached := false

func initialize(battle_mgr: Node2D, spirit_sys: SpiritSystemManager, ai_mgr: Node) -> void:
	battle_manager = battle_mgr
	spirit_system = spirit_sys
	ai_manager = ai_mgr
	_load_element_counters()
	print("[SpiritAI] 初始化完成")

func _load_element_counters() -> void:
	var elements_data = DataManager.elements
	if not elements_data:
		return
	
	counter_multiplier = elements_data.get("counter_multiplier", 1.3)
	
	for counter_entry in elements_data.get("counters", []):
		var attacker = counter_entry.get("attacker", "")
		var defender = counter_entry.get("defender", "")
		if attacker and defender:
			if attacker not in element_counters:
				element_counters[attacker] = []
			element_counters[attacker].append(defender)

func register_player(player: CharacterBody2D, profile: AIProfile) -> void:
	var player_analysis = _analyze_player_attributes(player)
	var skills_analysis: Array[Dictionary] = []
	spirit_ai_data.append({
		"player": player,
		"profile": profile,
		# 注册思考相位确定性化：原 randf 消耗全局随机流，跨运行不可复现（02前置地基工单A）
		"skill_think_timer": _deterministic_dice(_player_key_v(str(player.character_id), str(player.team)), 1) * profile.skill_think_interval,
		"skill_decide_count": 0,
		"skill_exec_count": 0,
		"mistake_hold": {},
		"ai_input_attached": false,
		"last_skill_use_time": 0.0,
		"player_analysis": player_analysis,
		"skills_analysis": skills_analysis,
	})
	print("[SpiritAI] 注册球员: %s, 弱点: %s" % [player.name, str(player_analysis.get("weaknesses", []))])

func refresh_all_skills_analysis() -> void:
	if battle_manager and battle_manager.spirit_system:
		spirit_system = battle_manager.spirit_system
	if not spirit_system:
		print("[SpiritAI] 警告: spirit_system 为空，无法分析技能")
		return
	for sad in spirit_ai_data:
		sad["skills_analysis"] = _analyze_skills_for_player(sad["player"], sad["player_analysis"])
		print("[SpiritAI] %s 技能分析完成，技能数: %d" % [sad["player"].name, sad["skills_analysis"].size()])

func _analyze_player_attributes(player: CharacterBody2D) -> Dictionary:
	var result: Dictionary = {}
	result["weaknesses"] = []
	result["strengths"] = []
	result["risk_level"] = "medium"
	result["risk_score"] = 0.0
	
	var attack = player.attack_power
	var defense = player.defense
	var speed = player.speed
	var stamina = player.stamina
	var resilience = player.resilience
	
	var max_attr = max(attack, defense, speed, stamina, resilience)
	
	if defense < max_attr * 0.5:
		result["weaknesses"].append("defense_low")
		result["risk_score"] += 0.4
	if stamina < max_attr * 0.5:
		result["weaknesses"].append("stamina_low")
		result["risk_score"] += 0.3
	if resilience < max_attr * 0.5:
		result["weaknesses"].append("resilience_low")
		result["risk_score"] += 0.3
	
	if attack > max_attr * 0.8:
		result["strengths"].append("attack_high")
	if defense > max_attr * 0.8:
		result["strengths"].append("defense_high")
	if speed > max_attr * 0.8:
		result["strengths"].append("speed_high")
	
	result["risk_score"] = clampf(result["risk_score"], 0.0, 1.0)
	
	if result["risk_score"] > 0.6:
		result["risk_level"] = "high"
	elif result["risk_score"] < 0.3:
		result["risk_level"] = "low"
	
	result["base_attack"] = attack
	result["base_defense"] = defense
	result["base_speed"] = speed
	result["base_stamina"] = stamina
	result["base_resilience"] = resilience
	
	return result

func _analyze_skills_for_player(player: CharacterBody2D, player_analysis: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not spirit_system:
		return result
	var player_skills = spirit_system.get_player_skills(player.get_instance_id())
	for skill_id in player_skills:
		var skill_data = DataManager.get_skill_by_id(skill_id)
		if not skill_data:
			continue
		var analysis = _analyze_single_skill(skill_data, player_analysis)
		analysis["skill_id"] = skill_id
		analysis["skill_data"] = skill_data
		result.append(analysis)
	
	_analyze_skill_combinations(result)
	
	return result

func _analyze_skill_combinations(skills_analysis: Array[Dictionary]) -> void:
	for i in range(skills_analysis.size()):
		var skill_a = skills_analysis[i]
		skill_a["combos"] = []
		
		for j in range(skills_analysis.size()):
			if i == j:
				continue
			var skill_b = skills_analysis[j]
			var combo_type = _detect_combo_type(skill_a, skill_b)
			if combo_type:
				skill_a["combos"].append({
					"skill_id": skill_b["skill_id"],
					"combo_type": combo_type,
					"bonus": _get_combo_bonus(combo_type),
				})

func _detect_combo_type(skill_a: Dictionary, skill_b: Dictionary) -> String:
	var tags_a = skill_a.get("tags", [])
	var tags_b = skill_b.get("tags", [])
	var intents_a = skill_a.get("intents", {})
	var intents_b = skill_b.get("intents", {})
	
	if intents_a.get("control", 0) > 0.5 and intents_b.get("attack", 0) > 0.5:
		if "on_player" in tags_a and "on_ball" in tags_b:
			return "combo_control_attack"
		if "on_field" in tags_a and "on_ball" in tags_b:
			return "combo_control_attack"
	
	if intents_a.get("support", 0) > 0.5 and intents_b.get("attack", 0) > 0.5:
		return "combo_buff_attack"
	
	if intents_a.get("defense", 0) > 0.5 and intents_b.get("control", 0) > 0.5:
		return "combo_defense_control"
	
	return ""

func _get_combo_bonus(combo_type: String) -> float:
	match combo_type:
		"combo_control_attack":
			return 0.4
		"combo_buff_attack":
			return 0.3
		"combo_defense_control":
			return 0.25
	return 0.0

func _analyze_single_skill(skill_data: Dictionary, player_analysis: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	# 原始 tag_id 列表（06§五#1：原语查表/闸门键，归一化前保留）
	var raw_tags: Array[String] = _extract_raw_tags(skill_data.get("tags", []))
	var tags = _map_tags_to_categories(raw_tags)
	var tag_params = skill_data.get("tag_params", {})
	var energy_cost = skill_data.get("energy_cost", 20)
	var cooldown = skill_data.get("cooldown", 5.0)

	result["tags"] = tags
	result["raw_tags"] = raw_tags
	result["tag_count"] = tags.size()
	result["has_ball_tag"] = "on_ball" in tags
	result["has_player_tag"] = "on_player" in tags
	result["has_field_tag"] = "on_field" in tags
	result["base_value"] = _compute_base_value(tags, tag_params, energy_cost, cooldown)
	result["intents"] = _determine_intents(tags, tag_params)
	result["primary_intent"] = _get_primary_intent(result["intents"])
	result["synergy_level"] = _compute_synergy_level(tags, tag_params, player_analysis)
	result["synergy_bonus"] = _compute_synergy_bonus(result["synergy_level"])
	return result

func _compute_synergy_level(tags: Array[String], values: Dictionary, player_analysis: Dictionary) -> String:
	var weaknesses = player_analysis.get("weaknesses", [])
	var strengths = player_analysis.get("strengths", [])
	
	var synergy_score: float = 0.0
	
	for tag in tags:
		match tag:
			"on_player":
				if values.has("defense_bonus") or values.has("shield_hp") or values.has("damage_reduction"):
					if "defense_low" in weaknesses:
						synergy_score += 0.8
					elif "defense_high" in strengths:
						synergy_score += 0.4
					else:
						synergy_score += 0.2
				if values.has("slow_percent") or values.has("root_duration"):
					if "speed_high" in strengths:
						synergy_score += 0.3
			"on_ball":
				if values.has("damage_bonus"):
					if "attack_high" in strengths:
						synergy_score += 0.5
					else:
						synergy_score += 0.2
				if values.has("speed_multiplier"):
					if "speed_high" in strengths:
						synergy_score += 0.4
			"on_field":
				if values.has("wall_width"):
					if "defense_low" in weaknesses:
						synergy_score += 0.6
					else:
						synergy_score += 0.2
	
	synergy_score = clampf(synergy_score, 0.0, 1.0)
	
	if synergy_score >= 0.7:
		return "critical"
	elif synergy_score >= 0.4:
		return "high"
	elif synergy_score >= 0.2:
		return "medium"
	else:
		return "low"

func _compute_synergy_bonus(synergy_level: String) -> float:
	match synergy_level:
		"critical":
			return 1.5
		"high":
			return 1.25
		"medium":
			return 1.0
		"low":
			return 0.8
	return 1.0

func _normalize_tags(tag_data) -> Array[String]:
	return _map_tags_to_categories(_extract_raw_tags(tag_data))


## 归一化前原始 tag_id 列表（06§五#1：原语查表键；tag_params 的键与其同源）
func _extract_raw_tags(tag_data) -> Array[String]:
	var raw_tags: Array[String] = []

	if tag_data is String:
		if not tag_data.is_empty():
			raw_tags = [tag_data] as Array[String]
	elif tag_data is Array:
		for t in tag_data:
			if t is String and not (t as String).is_empty():
				raw_tags.append(t as String)

	return raw_tags

func _map_tags_to_categories(raw_tags: Array[String]) -> Array[String]:
	var result: Array[String] = []
	var has_ball: bool = false
	var has_player: bool = false
	var has_field: bool = false
	
	for tag in raw_tags:
		var category = _get_tag_category(tag)
		match category:
			"BALL":
				has_ball = true
			"PLAYER":
				has_player = true
			"FIELD":
				has_field = true
	
	if has_ball:
		result.append("on_ball")
	if has_player:
		result.append("on_player")
	if has_field:
		result.append("on_field")
	
	if result.is_empty() and not raw_tags.is_empty():
		for tag in raw_tags:
			if not result.has(tag):
				result.append(tag)
	
	return result

func _get_tag_category(tag_id: String) -> String:
	var tags_array = DataManager.tags
	if tags_array:
		for tag_entry in tags_array:
			if tag_entry.get("id", "") == tag_id:
				return tag_entry.get("category", "")
	
	if tag_id.begins_with("ball_"):
		return "BALL"
	elif tag_id.begins_with("player_"):
		return "PLAYER"
	elif tag_id.begins_with("field_"):
		return "FIELD"
	
	return ""

func _extract_values_from_tag_params(tag_params: Dictionary) -> Dictionary:
	var values: Dictionary = {}
	for tag_id in tag_params:
		var params = tag_params[tag_id]
		for key in params:
			if not values.has(key):
				values[key] = params[key]
			else:
				if typeof(params[key]) == TYPE_FLOAT or typeof(params[key]) == TYPE_INT:
					values[key] = max(values[key], params[key])
	return values

func _compute_base_value(tags: Array[String], tag_params: Dictionary, energy_cost: int, cooldown: float) -> float:
	if tags.is_empty():
		return 10.0

	# 原语计价（06§五#2）：任一 raw tag 命中描述符 → 逐标签描述符计价×多标签权重(1/0.7/0.5/0.4)；
	# 技能内未命中标签按旧分支未知标签缺省 10.0 计；全未命中（含开关全关）→ 旧三大类分支逐位不变
	var primitive_total: float = 0.0
	var primitive_hit := false
	for tag_id in tag_params:
		var hit := _query_primitive(str(tag_id))
		if hit.is_empty():
			primitive_total += 10.0  # 未覆盖标签=旧分支未知标签缺省分（_compute_*_value 的 _ 支同口径）
			continue
		primitive_hit = true
		primitive_total += float(hit["primitives"].compute_value(hit["descriptor"], tag_params[tag_id]))
	if primitive_hit:
		var primitive_weight := 1.0
		match tag_params.size():
			2:
				primitive_weight = 0.7
			3:
				primitive_weight = 0.5
			_:
				if tag_params.size() >= 4:
					primitive_weight = 0.4
		return clampf(primitive_total * primitive_weight, 10.0, 100.0)

	var total_value: float = 0.0
	var tag_count: int = tags.size()
	
	var tag_weight: float
	match tag_count:
		1:
			tag_weight = 1.0
		2:
			tag_weight = 0.7
		3:
			tag_weight = 0.5
		_:
			tag_weight = 0.4
	
	for tag in tags:
		var tag_value: float = 0.0
		match tag:
			"on_ball":
				tag_value = _compute_ball_value(tag_params)
			"on_player":
				tag_value = _compute_player_value(tag_params)
			"on_field":
				tag_value = _compute_field_value(tag_params)
			_:
				tag_value = 10.0
		total_value += tag_value
	
	var combined_value: float = total_value * tag_weight
	var efficiency: float = combined_value / float(max(energy_cost, 1))
	var cd_factor: float = clampf(10.0 / max(cooldown, 1.0), 0.3, 2.0)
	
	return clampf(combined_value * cd_factor * 0.5 + efficiency * 5.0, 10.0, 100.0)

func _compute_ball_value(tag_params: Dictionary) -> float:
	var value: float = 0.0
	
	for tag_id in tag_params:
		var params = tag_params[tag_id]
		var tag_value = params.get("value", 0)
		var multiplier = params.get("multiplier", 0)
		var duration = params.get("duration", 0)
		
		if tag_id.begins_with("ball_dmg_up"):
			value += tag_value * 1.5
		# 波4 球类参数化（10 工单）
		elif tag_id.begins_with("ball_bounce_enhance"):
			value += params.get("max_bounces", params.get("bounce_max", 0)) * 4.0
			value += params.get("speed_keep_pct", params.get("speed_mult", 0)) * 8.0
		elif tag_id.begins_with("ball_sure_hit"):
			value += 30.0
		elif tag_id.begins_with("ball_transform"):
			value += params.get("size_scale", 0) * 15.0
		elif tag_id.begins_with("ball_stealth"):
			value += 25.0
		elif tag_id.begins_with("ball_speed_up"):
			value += multiplier * 1.0
		elif tag_id.begins_with("ball_range_up"):
			value += tag_value * 0.5
		elif tag_id.begins_with("ball_dmg_down"):
			value += tag_value * 0.8
		elif tag_id.begins_with("ball_slow"):
			value += multiplier * 0.8
			value += duration * 5.0
		elif tag_id.begins_with("ball_knockback"):
			value += tag_value * 0.5
		elif tag_id.begins_with("ball_burn"):
			value += duration * 8.0
		elif tag_id.begins_with("ball_deception"):
			value += 25.0
		elif tag_id.begins_with("ball_split"):
			value += tag_value * 20.0
	
	return max(value, 15.0)

func _compute_player_value(tag_params: Dictionary) -> float:
	var value: float = 0.0
	
	for tag_id in tag_params:
		var params = tag_params[tag_id]
		var tag_value = params.get("value", 0)
		var multiplier = params.get("multiplier", 0)
		var duration = params.get("duration", 0)
		
		if tag_id.begins_with("player_def_up"):
			value += tag_value * 1.2
			value += duration * 2.0
		elif tag_id.begins_with("player_hp_regen"):
			value += tag_value * 3.0
			value += duration * 3.0
		elif tag_id.begins_with("player_spd_up"):
			value += tag_value * 0.8
			value += duration * 2.0
		elif tag_id.begins_with("player_move_slow"):
			value += multiplier * 1.0
			value += duration * 8.0
		elif tag_id.begins_with("player_root"):
			value += duration * 20.0
		elif tag_id.begins_with("player_damage_reduction"):
			value += tag_value * 1.5
		elif tag_id.begins_with("player_stealth"):
			value += 30.0
			value += duration * 5.0
		# 波3 球员管道变体（09 工单）
		elif tag_id.begins_with("player_heal_block"):
			value += duration * 6.0
		elif tag_id.begins_with("player_damage_reflect"):
			value += tag_value * 1.2
			value += params.get("pct", 0) * 60.0
			value += duration * 3.0
		elif tag_id.begins_with("player_element_immune") or tag_id.begins_with("player_element_weak"):
			value += 25.0
			value += params.get("elements", []).size() * 5.0
			value += duration * 3.0
		elif tag_id.begins_with("player_energy_share"):
			value += params.get("share_pct", 0) * 30.0
			value += duration * 3.0
		elif tag_id.begins_with("player_charge_stock"):
			value += params.get("charges", 0) * 6.0
		elif tag_id.begins_with("player_on_hit_expire"):
			value += 10.0
		elif tag_id.begins_with("player_shield"):
			value += tag_value * 1.8
	
	return max(value, 15.0)

func _compute_field_value(tag_params: Dictionary) -> float:
	var value: float = 0.0
	
	for tag_id in tag_params:
		var params = tag_params[tag_id]
		var tag_value = params.get("value", 0)
		var multiplier = params.get("multiplier", 0)
		var duration = params.get("duration", 0)
		var width = params.get("width", 0)
		var height = params.get("height", 0)
		var radius = params.get("radius", 0)
		var hp = params.get("hp", 0)
		
		if tag_id.begins_with("field_obs_add"):
			value += width * 0.3
			value += height * 0.2
			value += hp * 0.1
			value += duration * 3.0
		elif tag_id.begins_with("field_slow_zone"):
			value += radius * 0.4
			value += multiplier * 0.8
			value += duration * 4.0
		elif tag_id.begins_with("field_stun"):
			value += radius * 0.5
			value += duration * 25.0
		elif tag_id.begins_with("field_clone"):
			value += tag_value * 30.0
		elif tag_id.begins_with("player_shield_obstacle"):
			# V1-2 体外实体盾（05 文档）：与岩石墙同尺度——耐久+时长+次数
			value += hp * 0.1
			value += duration * 3.0
			value += params.get("uses", 0) * 5.0
		elif tag_id.begins_with("field_zone_boost") or tag_id.begins_with("field_zone_slow"):
			# V1-3 区域效果（06 文档）：半径映射的尺寸+倍率+时长
			value += (params.get("width", 0) as float) * 0.15
			value += (params.get("height", 0) as float) * 0.15
			value += multiplier * 8.0
			value += duration * 4.0
		elif tag_id.begins_with("field_zone_danger"):
			# 危险区：伤害区价值（灼烧 dot 口径）
			value += (params.get("radius", 0) as float) * 0.4
			value += params.get("damage_value", 0) * 4.0
			value += duration * 6.0
		elif tag_id.begins_with("field_zone_safe"):
			value += duration * 5.0

	return max(value, 15.0)

func _determine_intents(tags: Array[String], tag_params: Dictionary) -> Dictionary:
	var intents: Dictionary = {
		"attack": 0.0,
		"defense": 0.0,
		"support": 0.0,
		"control": 0.0,
	}
	
	if tags.is_empty():
		return intents
	
	var tag_count: int = tags.size()
	var tag_weight: float
	match tag_count:
		1:
			tag_weight = 1.0
		2:
			tag_weight = 0.7
		3:
			tag_weight = 0.5
		_:
			tag_weight = 0.4
	
	for tag in tags:
		var sub_intents = _compute_tag_intents(tag, tag_params)
		for key in sub_intents:
			intents[key] = intents.get(key, 0) + sub_intents[key] * tag_weight

	# 原语意图校准（06§七）：命中描述符的 raw tag，其 intent/intent_strength 以 max 并入，
	# 随后统一归一化；开关全关=无命中=本段零变化
	for tag_id in tag_params:
		var hit := _query_primitive(str(tag_id))
		if hit.is_empty():
			continue
		var intent_key := str(hit["descriptor"].get("intent", ""))
		if intents.has(intent_key):
			intents[intent_key] = maxf(float(intents[intent_key]), float(hit["descriptor"].get("intent_strength", 0.0)))

	var total: float = intents["attack"] + intents["defense"] + intents["support"] + intents["control"]
	if total > 0:
		intents["attack"] /= total
		intents["defense"] /= total
		intents["support"] /= total
		intents["control"] /= total
	
	return intents

func _compute_tag_intents(tag: String, tag_params: Dictionary) -> Dictionary:
	var intents: Dictionary = {
		"attack": 0.0,
		"defense": 0.0,
		"support": 0.0,
		"control": 0.0,
	}
	
	for tag_id in tag_params:
		if tag_id.begins_with("ball_dmg_up") or tag_id.begins_with("ball_speed_up") or tag_id.begins_with("ball_range_up"):
			intents["attack"] = max(intents["attack"], 0.8)
		# 波4 球类参数化（10 工单）
		elif tag_id.begins_with("ball_bounce_enhance"):
			intents["control"] = max(intents["control"], 0.5)
			intents["attack"] = max(intents["attack"], 0.4)
		elif tag_id.begins_with("ball_sure_hit"):
			intents["attack"] = max(intents["attack"], 0.9)
		elif tag_id.begins_with("ball_transform"):
			intents["attack"] = max(intents["attack"], 0.6)
		elif tag_id.begins_with("ball_stealth"):
			intents["attack"] = max(intents["attack"], 0.7)
			intents["control"] = max(intents["control"], 0.4)
		elif tag_id.begins_with("ball_dmg_down") or tag_id.begins_with("ball_slow"):
			intents["control"] = max(intents["control"], 0.5)
		elif tag_id.begins_with("ball_deception"):
			intents["control"] = max(intents["control"], 0.5)
		elif tag_id.begins_with("ball_split"):
			intents["attack"] = max(intents["attack"], 1.0)
		elif tag_id.begins_with("player_def_up") or tag_id.begins_with("player_shield"):
			intents["defense"] = max(intents["defense"], 0.8)
		elif tag_id.begins_with("player_hp_regen"):
			intents["support"] = max(intents["support"], 0.8)
		elif tag_id.begins_with("player_spd_up"):
			intents["support"] = max(intents["support"], 0.5)
		elif tag_id.begins_with("player_move_slow") or tag_id.begins_with("player_root"):
			intents["control"] = max(intents["control"], 0.7)
		elif tag_id.begins_with("player_stealth"):
			intents["control"] = max(intents["control"], 0.5)
			intents["defense"] = max(intents["defense"], 0.3)
		elif tag_id.begins_with("field_obs_add"):
			intents["defense"] = max(intents["defense"], 0.9)
		# 波3 球员管道变体（09 工单）
		elif tag_id.begins_with("player_heal_block"):
			intents["control"] = max(intents["control"], 0.6)
			intents["attack"] = max(intents["attack"], 0.4)
		elif tag_id.begins_with("player_damage_reflect"):
			intents["defense"] = max(intents["defense"], 0.8)
		elif tag_id.begins_with("player_element_immune") or tag_id.begins_with("player_element_weak"):
			intents["defense"] = max(intents["defense"], 0.9)
		elif tag_id.begins_with("player_energy_share"):
			intents["support"] = max(intents["support"], 0.7)
		elif tag_id.begins_with("player_charge_stock"):
			intents["support"] = max(intents["support"], 0.4)
		elif tag_id.begins_with("player_on_hit_expire"):
			intents["control"] = max(intents["control"], 0.5)
		elif tag_id.begins_with("field_zone_danger"):
			intents["attack"] = max(intents["attack"], 0.6)
			intents["defense"] = max(intents["defense"], 0.4)
		elif tag_id.begins_with("field_zone_slow"):
			intents["control"] = max(intents["control"], 0.6)
			intents["defense"] = max(intents["defense"], 0.5)
		elif tag_id.begins_with("field_zone_boost"):
			intents["support"] = max(intents["support"], 0.7)
		elif tag_id.begins_with("field_zone_safe"):
			intents["defense"] = max(intents["defense"], 0.7)
		elif tag_id.begins_with("field_slow"):
			intents["control"] = max(intents["control"], 0.6)
			intents["defense"] = max(intents["defense"], 0.5)
		elif tag_id.begins_with("field_stun"):
			intents["control"] = max(intents["control"], 0.9)
		elif tag_id.begins_with("field_clone"):
			intents["attack"] = max(intents["attack"], 0.5)
			intents["support"] = max(intents["support"], 0.3)
	
	if intents["attack"] == 0 and intents["defense"] == 0 and intents["support"] == 0 and intents["control"] == 0:
		match tag:
			"on_ball":
				intents["attack"] = 0.8
			"on_player":
				intents["support"] = 0.5
			"on_field":
				intents["control"] = 0.6
	
	return intents

func _get_primary_intent(intents: Dictionary) -> String:
	var max_val: float = -1.0
	var primary: String = "attack"
	for key in intents:
		if intents[key] > max_val:
			max_val = intents[key]
			primary = key
	return primary

func _physics_process(delta: float) -> void:
	# 波B事件钩子挂接（event_hooks.gd 头注三步之一）：首次物理帧时必已在树内，
	# 总线不可得时 attach(null) 静默降级（is_reaction_hot 恒 false=波B原语缺省 fail-closed 同义）
	if not _hooks_attached:
		_hooks_attached = true
		_setup_event_hooks()

	if not battle_manager or not battle_manager.match_started:
		return

	if not ball_node:
		ball_node = battle_manager.ball_node
	if not ball_node:
		return

	for sad in spirit_ai_data:
		if not _is_valid(sad):
			continue

		sad.skill_think_timer += delta
		if sad.skill_think_timer >= sad.profile.skill_think_interval:
			sad.skill_think_timer = 0.0
			_decide_skill(sad)
			_try_send_need_buff(sad)

func _is_valid(sad: Dictionary) -> bool:
	var p = sad.player
	if not p or not is_instance_valid(p):
		return false
	if ai_manager and ai_manager.input_manager and ai_manager.input_manager.controlled_player == p:
		return false
	if p.is_defeated:
		return false
	return true

func _decide_skill(sad: Dictionary) -> void:
	var p = sad.player
	var profile = sad.profile

	sad["skill_decide_count"] += 1

	# 波B事件钩子：注入决策周期时钟（TTL 全周期计数，零墙钟；event_hooks.gd 三步之二）
	if _event_hooks:
		_event_hooks.set_cycle(int(sad["skill_decide_count"]))
	# 波C AI输入源登记（懒挂：首决策时状态机必已就绪；旧状态机无 AI 口时 fail-closed 静默）
	if not bool(sad.get("ai_input_attached", false)):
		sad["ai_input_attached"] = true
		_attach_ai_input_source(p)

	if p.spirit_energy < profile.skill_energy_min:
		return

	if not _should_think_about_skills(sad):
		return

	var available_skills = _get_available_skills(sad)
	if available_skills.is_empty():
		return

	# 原语时机闸门（06§五#3）：候选技能 raw_tags 逐标签跑 gate，OR 放行、bonus 取通过者最大值；
	# ctx 惰性组装（首命中时一次/周期；开关全关=无命中=闸门不参与，评分路径与旧版逐位一致）
	var primitive_ctx_box: Dictionary = {}
	var scored_skills: Array[Dictionary] = []
	for skill_info in available_skills:
		var gate := _evaluate_primitive_gates(sad, skill_info, primitive_ctx_box)
		if bool(gate.get("gated", false)) and not bool(gate.get("ok", false)):
			continue  # 闸门不过=本周期跳过（无惩罚，06§一）
		var score = _compute_skill_score(sad, skill_info)
		if bool(gate.get("gated", false)):
			score *= float(gate.get("bonus", 1.0))
		if score > 0:
			scored_skills.append({
				"skill": skill_info,
				"score": score,
			})

	if scored_skills.is_empty():
		return

	var best_skill = _select_skill_with_softmax(sad, scored_skills, profile.skill_selection_temperature)

	if best_skill and best_skill["score"] >= profile.skill_use_threshold:
		_execute_skill(sad, best_skill["skill"])

## ===== 确定性骰子（02前置地基工单A）=====
## Knuth 乘法散列，同 ai_manager._dodge_roll 范式。
## 输入必须是跨运行稳定量：character_id/team/skill_id 字符串 hash、sad 决策计数器。
## 禁 instance_id（跨运行漂移）、禁 randf（全局随机流消耗顺序随时序漂移）。
## 同一场面恒同一结果 → sim 可复现。
## ⚠ key_c（计数器）必须走大乘数混映：小步长乘数会使相邻计数骰值仅差~1e-5量级，
## 一旦落入失误/选择区间即连续数千周期不变 → 失误死循环/选技卡死（2026-09-25 实证）
func _deterministic_dice(key_a: int, key_b: int, key_c: int = 0) -> float:
	var h: int = (key_a % 1000003) * 2654435761 + (key_b % 100007) * 40503 + (key_c % 1000003) * 2654435761
	h = h % 4294967296
	if h < 0:
		h += 4294967296
	return float(h) / 4294967296.0

func _player_key_v(character_id: String, team: String) -> int:
	return hash(character_id + "_" + team)

func _player_key(sad: Dictionary) -> int:
	return _player_key_v(str(sad.player.character_id), str(sad.player.team))

func _select_skill_with_softmax(sad: Dictionary, scored_skills: Array[Dictionary], temperature: float) -> Dictionary:
	if scored_skills.size() == 1:
		return scored_skills[0]
	
	if temperature <= 0.01:
		var best = scored_skills[0]
		for s in scored_skills:
			if s["score"] > best["score"]:
				best = s
		return best
	
	var max_score: float = -INF
	for s in scored_skills:
		if s["score"] > max_score:
			max_score = s["score"]
	
	var exp_scores: Array[float] = []
	var total_exp: float = 0.0
	for s in scored_skills:
		var exp_val = exp((s["score"] - max_score) / temperature)
		exp_scores.append(exp_val)
		total_exp += exp_val
	
	var r = _deterministic_dice(_player_key(sad), sad["skill_decide_count"]) * total_exp
	var cum = 0.0
	for i in range(scored_skills.size()):
		cum += exp_scores[i]
		if r <= cum:
			return scored_skills[i]
	
	return scored_skills[0]

func _should_think_about_skills(sad: Dictionary) -> bool:
	var p = sad.player
	var profile = sad.profile
	
	if p.is_carrying_ball:
		return true
	
	if ball_node and ball_node.owner_player and ball_node.owner_player.team == p.team:
		return true
	
	if ball_node and ball_node.is_active:
		return true
	
	if profile.role == "defender":
		return true
	
	for analysis in sad.skills_analysis:
		if analysis.get("has_field_tag", false):
			return true
	
	return false

func _get_available_skills(sad: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var p = sad.player
	for analysis in sad.skills_analysis:
		var skill_id = analysis["skill_id"]
		# 被动技能由事件自动触发，不进主动评分池
		# （否则每周期选中→use_skill 被拒→无冷却→无限重试刷屏，2026-09-13 seed3 诊断发现）
		if analysis["skill_data"].get("type", "active") == "passive":
			continue
		# 失误局部短冷却中（02前置地基工单追加）
		var hold_until: int = int(sad.get("mistake_hold", {}).get(skill_id, 0))
		if int(sad["skill_decide_count"]) < hold_until:
			continue
		var cd = spirit_system.get_skill_cooldown(p.get_instance_id(), skill_id)
		var energy_cost = analysis["skill_data"].get("energy_cost", 20)
		if cd <= 0.0 and p.spirit_energy >= energy_cost:
			result.append(analysis)
	return result

## ===== 原语层接线函数（06§五集成契约；未命中一律回落旧路径=全关零扰动）=====

## 波B事件钩子挂接（event_hooks.gd 头注三步之一）。总线不可得时静默降级
func _setup_event_hooks() -> void:
	_event_hooks = EVENT_HOOKS_SCRIPT.new()
	if is_inside_tree():
		var bus = BattleEventBus.get_bus(get_tree())
		if bus:
			_event_hooks.attach(bus)


## 波C AI输入源登记（ai_input_source.attach：状态机补 AI 施法者链路，03§3.2方案a）。
## 登记本身零行为（消费只发生在操控族激活窗 tick——激活技能查询口属 skill_state_manager，
## 波C单写者已收官，tick 留后续集成工单，见看板集成行备注）
func _attach_ai_input_source(player: CharacterBody2D) -> void:
	if battle_manager == null:
		return
	var input_manager = battle_manager.get("input_manager")
	if input_manager == null:
		return
	var state_manager = input_manager.get("skill_state_manager")
	if state_manager == null:
		return
	AI_INPUT_SOURCE.attach(state_manager, player.get_instance_id(), player)


## 原语单口查询：返回 {"descriptor": Dictionary, "primitives": GDScript} 或 {}
## 未命中/波未开/未知波次字母一律 {}（08工单开关契约；波字母→函数表分发经 registry 打标）
func _query_primitive(tag_id: String) -> Dictionary:
	var entry: Dictionary = SpiritAIPrimitiveRegistry.get_descriptor_entry(str(tag_id))
	if entry.is_empty():
		return {}
	var wave: String = str(entry.get("wave", ""))
	if not _WAVE_PRIMITIVES.has(wave):
		return {}
	return {"descriptor": entry.get("descriptor", {}), "primitives": _WAVE_PRIMITIVES[wave]}


## 时机闸门评估（06§五#3）：技能 raw_tags 逐标签跑 timing_gate——OR 逻辑，任一标签通过即放行，
## bonus 取通过者最大值（06§一）。无任何标签命中描述符 → gated=false（闸门不参与，旧评分零扰动）。
## ctx_box：单键字典 {"ctx": Dictionary}，首命中时惰性组装（每决策周期至多一次；测试可预填）
func _evaluate_primitive_gates(sad: Dictionary, skill_info: Dictionary, ctx_box: Dictionary) -> Dictionary:
	var gated := false
	var any_ok := false
	var best_bonus := 0.0
	for tag in skill_info.get("raw_tags", []):
		var hit := _query_primitive(tag)
		if hit.is_empty():
			continue
		if not ctx_box.has("ctx"):
			ctx_box["ctx"] = _build_primitive_ctx(sad)
		var gate_result: Dictionary = hit["primitives"].timing_gate(hit["descriptor"], sad, ctx_box["ctx"])
		gated = true
		if bool(gate_result.get("ok", false)):
			any_ok = true
			best_bonus = maxf(best_bonus, float(gate_result.get("bonus", 1.0)))
	if not gated:
		return {"gated": false, "ok": false, "bonus": 1.0}
	return {"gated": true, "ok": any_ok, "bonus": (best_bonus if any_ok else 1.0)}


## 原语 ctx 组装（06§4.1 冻结字段 + Q5/Q7/Q8 增补键）：感知全部 manager 单口算好，原语零直连；
## 无球/无总线时省略对应键=各波 fail-closed（等价 false/空）
func _build_primitive_ctx(sad: Dictionary) -> Dictionary:
	var p: CharacterBody2D = sad.player
	var ctx: Dictionary = {
		"player": p,
		"stamina_ratio": float(p.stamina) / float(max(p.max_stamina, 1)),
		"energy_ratio": float(p.spirit_energy) / float(max(p.max_spirit_energy, 1)),
		"has_energy_blocked_burst": _has_energy_blocked_burst(sad),
		"threat_radius": PRIMITIVE_THREAT_RADIUS,
	}
	# 感知：02工单感知口 + FOV 过滤（fail-closed：无 ap=视野外=空表）
	var fov_ap: Dictionary = {}
	if ai_manager and ai_manager.has_method("get_ap_for_player"):
		fov_ap = ai_manager.get_ap_for_player(p)
	var visible_enemies: Array = []
	if not fov_ap.is_empty() and ai_manager.has_method("_is_in_field_of_view"):
		for enemy in _get_enemies(p):
			if is_instance_valid(enemy) and ai_manager._is_in_field_of_view(fov_ap, enemy.global_position):
				visible_enemies.append(enemy)
	ctx["fov_ap"] = fov_ap
	ctx["visible_enemies"] = visible_enemies
	# 队友（Q7）同源双形态：字典表（波A/B 消费）+ 比值表（波C/D 消费）
	var allies: Array = []
	var ally_ratios: Array = []
	for member in _get_team_members(p):
		if not is_instance_valid(member):
			continue
		var ratio := float(member.stamina) / float(max(member.max_stamina, 1))
		allies.append({"player": member, "stamina_ratio": ratio})
		ally_ratios.append(ratio)
	ctx["allies"] = allies
	ctx["ally_stamina_ratios"] = ally_ratios
	# 波B受击反应热窗口（事件钩子；未挂接=false）
	if _event_hooks:
		ctx["reaction_hot"] = _event_hooks.is_reaction_hot(p)
	# 球面键（Q5/Q8）
	if ball_node and is_instance_valid(ball_node):
		ctx["ball_position"] = ball_node.global_position
		ctx["ball_in_flight"] = bool(ball_node.is_active)
		ctx["ball_velocity"] = ball_node.ball_direction * ball_node.ball_speed
	ctx["own_goal"] = _get_our_goal_position(p)
	ctx["enemy_goal"] = _get_enemy_goal_position(p)
	var carrier = _get_enemy_ball_holder(p)
	if carrier != null and is_instance_valid(carrier):
		ctx["enemy_carrier"] = carrier
		ctx["enemy_carrier_visible"] = carrier in visible_enemies
	return ctx


## pre_burst 资源时机（06§三）：自己最高 base_value 的主动技能当前被能量/冷却卡住
## （按语义只看能量/冷却，不含 mistake_hold；spirit_system 缺失时 fail-closed=false）
func _has_energy_blocked_burst(sad: Dictionary) -> bool:
	if spirit_system == null:
		return false
	var p: CharacterBody2D = sad.player
	var best_analysis: Dictionary = {}
	var best_value: float = -INF
	for analysis in sad.get("skills_analysis", []):
		if analysis["skill_data"].get("type", "active") == "passive":
			continue
		var bv := float(analysis.get("base_value", 0.0))
		if bv > best_value:
			best_value = bv
			best_analysis = analysis
	if best_analysis.is_empty():
		return false
	var skill_id: String = str(best_analysis["skill_id"])
	if float(spirit_system.get_skill_cooldown(p.get_instance_id(), skill_id)) > 0.0:
		return true
	return p.spirit_energy < float(best_analysis["skill_data"].get("energy_cost", 20))


func _compute_skill_score(sad: Dictionary, skill_info: Dictionary) -> float:
	var base_value: float = skill_info["base_value"]
	var situation_factor: float = _compute_situation_factor(sad, skill_info)
	var intent_match: float = _compute_intent_match(sad, skill_info)
	var synergy_bonus: float = skill_info.get("synergy_bonus", 1.0)
	var stamina_factor: float = _compute_stamina_factor(sad, skill_info)
	var time_factor: float = _compute_time_factor(sad, skill_info)
	var comm_factor: float = _compute_communication_factor(sad, skill_info)
	var element_factor: float = _compute_element_factor(sad, skill_info)
	var combo_factor: float = _compute_combo_factor(sad, skill_info)
	var team_factor: float = _compute_team_factor(sad, skill_info)
	
	var raw_score: float = base_value * situation_factor * intent_match * synergy_bonus * stamina_factor * time_factor * comm_factor * element_factor * combo_factor * team_factor
	
	if not _should_use_energy(sad, skill_info, raw_score):
		return 0.0
	
	return raw_score

func _compute_team_factor(sad: Dictionary, skill_info: Dictionary) -> float:
	var p = sad.player
	
	var team_weaknesses = _get_team_weaknesses(p.team)
	if team_weaknesses.is_empty():
		return 1.0
	
	var intents = skill_info["intents"]
	var factor: float = 1.0
	
	if intents.get("defense", 0) > 0.3 or intents.get("support", 0) > 0.3:
		if "team_defense_low" in team_weaknesses:
			factor *= 1.2
		if "team_stamina_low" in team_weaknesses:
			factor *= 1.15
	
	if intents.get("attack", 0) > 0.3:
		if "team_attack_low" in team_weaknesses:
			factor *= 1.1
	
	return factor

func _get_team_weaknesses(team: String) -> Array[String]:
	if not ai_manager:
		return []
	
	var attack_sum = 0
	var defense_sum = 0
	var stamina_sum = 0
	var count = 0
	
	for ap in ai_manager.ai_players:
		var member = ap.player
		if not is_instance_valid(member) or member.team != team:
			continue
		attack_sum += member.attack_power
		defense_sum += member.defense
		stamina_sum += member.stamina
		count += 1
	
	if count == 0:
		return []
	
	var avg_attack = float(attack_sum) / float(count)
	var avg_defense = float(defense_sum) / float(count)
	var avg_stamina = float(stamina_sum) / float(count)
	
	var max_attr = max(avg_attack, avg_defense, avg_stamina)
	var weaknesses: Array[String] = []
	
	if avg_defense < max_attr * 0.6:
		weaknesses.append("team_defense_low")
	if avg_stamina < max_attr * 0.6:
		weaknesses.append("team_stamina_low")
	if avg_attack < max_attr * 0.6:
		weaknesses.append("team_attack_low")
	
	return weaknesses

func _compute_combo_factor(sad: Dictionary, skill_info: Dictionary) -> float:
	var p = sad.player
	var combos = skill_info.get("combos", [])
	
	if combos.is_empty():
		return 1.0
	
	var factor: float = 1.0
	for combo in combos:
		var combo_skill_id = combo["skill_id"]
		var cd = spirit_system.get_skill_cooldown(p.get_instance_id(), combo_skill_id)
		if cd <= 0.0:
			factor += combo["bonus"]
	
	return factor

func _compute_element_factor(sad: Dictionary, skill_info: Dictionary) -> float:
	var p = sad.player
	var skill_element = skill_info.get("skill_data", {}).get("element", "")
	
	if skill_element.is_empty() or element_counters.is_empty():
		return 1.0
	
	var target = _select_player_target(sad, skill_info)
	if not target or target == p:
		return 1.0
	
	var target_spirit_data = DataManager.get_spirit_by_id(target.spirit_id)
	if not target_spirit_data:
		return 1.0
	
	var target_element = target_spirit_data.get("element", "")
	if target_element.is_empty():
		return 1.0
	
	if skill_element in element_counters:
		if target_element in element_counters[skill_element]:
			return counter_multiplier
	
	return 1.0

func _compute_communication_factor(sad: Dictionary, skill_info: Dictionary) -> float:
	var p = sad.player
	
	if not battle_manager or not battle_manager.comm_system:
		return 1.0
	
	var intents = skill_info["intents"]
	var factor: float = 1.0
	
	if intents.get("support", 0) > 0.3:
		if battle_manager.comm_system.has_need_buff(p.team):
			var need_buff_sender = battle_manager.comm_system.get_need_buff_sender(p.team)
			if need_buff_sender and p.global_position.distance_to(need_buff_sender.global_position) < 150.0:
				factor *= 1.4
	
	if intents.get("attack", 0) > 0.5:
		if battle_manager.comm_system.has_buff_on_you(p):
			factor *= 1.25
	
	return factor

func _compute_time_factor(sad: Dictionary, skill_info: Dictionary) -> float:
	var p = sad.player
	var profile = sad.profile
	
	var remaining_time: float = 0.0
	var total_time: float = 180.0
	
	if GameManager:
		remaining_time = GameManager.match_time
		if GameManager.match_phase == GameManager.MatchPhase.FIRST_HALF:
			total_time = GameManager.get_first_half_duration()
		elif GameManager.match_phase == GameManager.MatchPhase.SECOND_HALF:
			total_time = GameManager.get_second_half_duration()
	
	var time_ratio: float = 1.0 - float(remaining_time) / float(max(total_time, 1))
	time_ratio = clampf(time_ratio, 0.0, 1.0)
	
	if time_ratio < 0.3:
		return 0.85
	elif time_ratio < 0.7:
		return 1.0
	else:
		var remaining_ratio = 1.0 - time_ratio
		return 1.0 + (1.0 - remaining_ratio) * (profile.skill_late_game_bonus - 1.0)

func _should_use_energy(sad: Dictionary, skill_info: Dictionary, current_score: float) -> bool:
	var p = sad.player
	var profile = sad.profile
	
	var energy_cost = skill_info.get("skill_data", {}).get("energy_cost", 20)
	var current_energy = p.spirit_energy
	var energy_ratio = float(current_energy - energy_cost) / float(max(p.max_spirit_energy, 1))
	
	var reserve_weight = profile.skill_reserve_weight
	
	var future_value: float = profile.skill_expected_future_score * (1.0 - energy_ratio * reserve_weight)
	var current_value: float = current_score
	
	if current_value >= future_value:
		return true
	
	var uncertainty_discount = profile.skill_uncertainty_discount
	if current_value * (1.0 - uncertainty_discount) >= future_value * uncertainty_discount:
		return true
	
	return false

func _compute_situation_factor(sad: Dictionary, skill_info: Dictionary) -> float:
	var possession_factor: float = _compute_possession_factor(sad, skill_info)
	var score_factor: float = _compute_score_factor(sad)
	var numbers_factor: float = _compute_numbers_factor(sad, skill_info)
	
	return possession_factor * 0.4 + score_factor * 0.3 + numbers_factor * 0.3

func _compute_numbers_factor(sad: Dictionary, skill_info: Dictionary) -> float:
	var p = sad.player
	var profile = sad.profile
	var intents = skill_info["intents"]
	
	var alive_team = 0
	var alive_enemy = 0
	
	if battle_manager:
		var team_members = battle_manager.team_a_players if p.team == "a" else battle_manager.team_b_players
		var enemy_members = battle_manager.team_b_players if p.team == "a" else battle_manager.team_a_players
		for member in team_members:
			if is_instance_valid(member) and not member.is_defeated:
				alive_team += 1
		for enemy in enemy_members:
			if is_instance_valid(enemy) and not enemy.is_defeated:
				alive_enemy += 1
	
	var diff: int = alive_team - alive_enemy
	var normalized_diff: float = float(diff) / 3.0
	normalized_diff = clampf(normalized_diff, -1.0, 1.0)
	
	var is_defensive = intents.get("defense", 0) > intents.get("attack", 0)
	
	if is_defensive:
		if normalized_diff < 0:
			return 1.0 + abs(normalized_diff) * (profile.skill_outnumbered_bonus - 1.0)
		else:
			return 1.0 - normalized_diff * 0.3
	else:
		if normalized_diff > 0:
			return 1.0 + normalized_diff * 0.3
		else:
			return 1.0 + abs(normalized_diff) * 0.2
	
	return 1.0

func _compute_possession_factor(sad: Dictionary, skill_info: Dictionary) -> float:
	var p = sad.player
	var intents = skill_info["intents"]
	
	if not ball_node:
		return 0.5
	
	if p.is_carrying_ball:
		var factor: float = 0.0
		factor += intents.get("attack", 0) * 1.5
		factor += intents.get("control", 0) * 1.2
		factor += intents.get("defense", 0) * 0.6
		factor += intents.get("support", 0) * 0.8
		return clampf(factor, 0.5, 1.5)
	
	if ball_node.owner_player and ball_node.owner_player.team == p.team:
		var factor: float = 0.0
		factor += intents.get("support", 0) * 1.3
		factor += intents.get("defense", 0) * 0.9
		factor += intents.get("attack", 0) * 0.8
		factor += intents.get("control", 0) * 1.0
		return clampf(factor, 0.5, 1.5)
	
	if ball_node.owner_player and ball_node.owner_player.team != p.team:
		var factor: float = 0.0
		factor += intents.get("defense", 0) * 1.4
		factor += intents.get("control", 0) * 1.1
		factor += intents.get("attack", 0) * 0.5
		factor += intents.get("support", 0) * 0.7
		return clampf(factor, 0.5, 1.5)
	
	return 0.7

func _compute_score_factor(sad: Dictionary) -> float:
	var p = sad.player
	var profile = sad.profile
	
	var my_score: int = 0
	var enemy_score: int = 0
	if GameManager:
		if p.team == "a":
			my_score = GameManager.score_team_a
			enemy_score = GameManager.score_team_b
		else:
			my_score = GameManager.score_team_b
			enemy_score = GameManager.score_team_a
	
	var diff: int = my_score - enemy_score
	var max_score: int = max(my_score, enemy_score)
	var normalized_diff: float = float(diff) / float(max(max_score, 3))
	normalized_diff = clampf(normalized_diff, -1.0, 1.0)
	
	if normalized_diff < 0:
		var losing_magnitude: float = abs(normalized_diff)
		return 1.0 + losing_magnitude * (profile.skill_losing_bonus - 1.0)
	elif normalized_diff > 0.3:
		var leading_magnitude: float = normalized_diff
		return profile.skill_leading_penalty + (1.0 - leading_magnitude) * (1.0 - profile.skill_leading_penalty)
	else:
		return 1.0

func _compute_intent_match(sad: Dictionary, skill_info: Dictionary) -> float:
	var profile = sad.profile
	var intents = skill_info["intents"]
	
	var match_score: float = 0.0
	match_score += intents.get("attack", 0) * profile.skill_attack_intent_weight
	match_score += intents.get("defense", 0) * profile.skill_defense_intent_weight
	match_score += intents.get("support", 0) * profile.skill_support_intent_weight
	match_score += intents.get("control", 0) * (profile.skill_attack_intent_weight + profile.skill_defense_intent_weight) * 0.5
	
	var max_possible: float = max(profile.skill_attack_intent_weight, profile.skill_defense_intent_weight, profile.skill_support_intent_weight)
	
	return clampf(match_score / max_possible, 0.5, 1.5)

func _compute_stamina_factor(sad: Dictionary, skill_info: Dictionary) -> float:
	var p = sad.player
	var profile = sad.profile
	
	var current_stamina = p.stamina
	var max_stamina = p.max_stamina
	var current_energy = p.spirit_energy
	var max_energy = p.max_spirit_energy
	
	var stamina_ratio: float = float(current_stamina) / float(max(max_stamina, 1))
	var energy_ratio: float = float(current_energy) / float(max(max_energy, 1))
	
	var avg_ratio: float = (stamina_ratio + energy_ratio) * 0.5
	
	var intents = skill_info["intents"]
	var has_defense = intents.get("defense", 0) > 0.3 or intents.get("support", 0) > 0.3
	
	if has_defense:
		if avg_ratio < 0.3:
			return 2.0
		elif avg_ratio < 0.5:
			return 1.5
		elif avg_ratio < 0.7:
			return 1.1
		else:
			return 1.0
	else:
		if avg_ratio < 0.2:
			return 0.5
		elif avg_ratio < 0.4:
			return 0.8
		else:
			return 1.0

func _select_player_target(sad: Dictionary, skill_info: Dictionary) -> CharacterBody2D:
	var p = sad.player
	var profile = sad.profile
	var has_player_tag = skill_info.get("has_player_tag", false)
	
	if not has_player_tag:
		return null
	
	var intents = skill_info["intents"]
	var primary_intent = skill_info["primary_intent"]
	
	if primary_intent == "support" or (intents.get("defense", 0) > 0.5 and intents.get("support", 0) > 0.3):
		return _select_support_target(sad)
	elif primary_intent == "attack" or intents.get("control", 0) > 0.5:
		return _select_attack_target(sad)
	else:
		return p

func _select_support_target(sad: Dictionary) -> CharacterBody2D:
	var p = sad.player
	
	var team_members = _get_team_members(p)
	if team_members.is_empty():
		return p
	
	var best_target = p
	var best_score: float = -INF
	
	for member in team_members:
		if not is_instance_valid(member):
			continue
		
		var stamina_ratio = float(member.stamina) / float(max(member.max_stamina, 1))
		var energy_ratio = float(member.spirit_energy) / float(max(member.max_spirit_energy, 1))
		var distance = p.global_position.distance_to(member.global_position)
		
		var score: float = 0.0
		score += (1.0 - stamina_ratio) * 3.0
		score += (1.0 - energy_ratio) * 2.0
		score += 1.0 / max(distance / 100.0, 0.1)
		
		if score > best_score:
			best_score = score
			best_target = member
	
	return best_target

func _select_attack_target(sad: Dictionary) -> CharacterBody2D:
	var p = sad.player

	var enemies = _get_enemies(p)
	if enemies.is_empty():
		return null

	# 视野闸门（02前置地基工单B，主人裁决 2026-09-25：只有180°视野内的对象可被选中，禁卡视野）
	# fail-closed：拿不到感知 ap 时按"无合法目标"处理
	var fov_ap: Dictionary = {}
	if ai_manager and ai_manager.has_method("get_ap_for_player"):
		fov_ap = ai_manager.get_ap_for_player(p)
	if fov_ap.is_empty():
		return null

	var best_target = null
	var best_score: float = -INF

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if not ai_manager._is_in_field_of_view(fov_ap, enemy.global_position):
			continue  # 视野外敌人不可选中
		
		var stamina_ratio = float(enemy.stamina) / float(max(enemy.max_stamina, 1))
		var distance = p.global_position.distance_to(enemy.global_position)
		var is_closest_to_ball = false
		
		if ball_node and ball_node.owner_player:
			var enemy_to_ball = enemy.global_position.distance_to(ball_node.global_position)
			var min_dist = INF
			for e in enemies:
				var d = e.global_position.distance_to(ball_node.global_position)
				if d < min_dist:
					min_dist = d
			is_closest_to_ball = abs(enemy_to_ball - min_dist) < 5.0
		
		var score: float = 0.0
		score += (1.0 - stamina_ratio) * 2.0
		score += 1.0 / max(distance / 100.0, 0.1)
		if is_closest_to_ball:
			score += 1.5
		
		if score > best_score:
			best_score = score
			best_target = enemy
	
	return best_target

func _get_team_members(player: CharacterBody2D) -> Array[CharacterBody2D]:
	var result: Array[CharacterBody2D] = []
	if not ai_manager:
		return result
	for ap in ai_manager.ai_players:
		var member = ap.player
		if member != player and is_instance_valid(member) and member.team == player.team:
			result.append(member)
	return result

func _get_enemies(player: CharacterBody2D) -> Array[CharacterBody2D]:
	var result: Array[CharacterBody2D] = []
	if not ai_manager:
		return result
	for ap in ai_manager.ai_players:
		var enemy = ap.player
		if is_instance_valid(enemy) and enemy.team != player.team:
			result.append(enemy)
	return result

func _select_field_position(sad: Dictionary, skill_info: Dictionary) -> Vector2:
	var p = sad.player
	var has_field_tag = skill_info.get("has_field_tag", false)

	if not has_field_tag:
		return p.global_position

	# 波D放置语义（Q4③ position_intent）：首个带放置函数的命中描述符 → 委托原语选位；
	# 原语缺 ctx 键时自身 fail-closed 回自站位，返回零向量（拿不到施法者）时同样回自站位
	for tag_id in skill_info.get("skill_data", {}).get("tag_params", {}):
		var hit := _query_primitive(str(tag_id))
		if hit.is_empty():
			continue
		var primitives = hit["primitives"]
		if not primitives.has_method("select_field_position"):
			continue
		var pos: Vector2 = primitives.select_field_position(hit["descriptor"], sad, _build_primitive_ctx(sad))
		return p.global_position if pos == Vector2.ZERO else pos

	var values = skill_info.get("skill_data", {}).get("values", {})
	var intents = skill_info["intents"]
	
	var is_defensive = intents.get("defense", 0) > intents.get("attack", 0) and intents.get("defense", 0) > intents.get("control", 0)
	var has_wall = values.has("wall_width")
	var has_radius = values.has("radius")
	var has_stun = values.has("stun_duration")
	
	if has_wall:
		return _select_wall_position(sad, is_defensive)
	elif has_stun:
		return _select_aoe_position(sad, is_defensive)
	elif has_radius:
		return _select_area_position(sad, is_defensive)
	else:
		return p.global_position

func _select_wall_position(sad: Dictionary, is_defensive: bool) -> Vector2:
	var p = sad.player
	var our_goal = _get_our_goal_position(p)
	var enemy_goal = _get_enemy_goal_position(p)
	
	if not ball_node:
		return p.global_position
	
	if is_defensive:
		var ball_dir = ball_node.global_position - our_goal
		var dist_to_goal = ball_dir.length()
		var wall_pos = our_goal + ball_dir.normalized() * min(dist_to_goal * 0.6, 80.0)
		return wall_pos
	else:
		var enemy_ball_holder = _get_enemy_ball_holder(p)
		if enemy_ball_holder:
			var to_enemy = enemy_ball_holder.global_position - our_goal
			var wall_pos = our_goal + to_enemy.normalized() * min(to_enemy.length() * 0.4, 60.0)
			return wall_pos
		else:
			return p.global_position + (enemy_goal - p.global_position).normalized() * 30.0

func _select_aoe_position(sad: Dictionary, is_defensive: bool) -> Vector2:
	var p = sad.player
	
	var enemies = _get_enemies(p)
	if enemies.is_empty():
		return p.global_position
	
	if is_defensive:
		var closest_enemy = null
		var min_dist = INF
		for enemy in enemies:
			var d = p.global_position.distance_to(enemy.global_position)
			if d < min_dist:
				min_dist = d
				closest_enemy = enemy
		if closest_enemy:
			return closest_enemy.global_position
	else:
		var lowest_stamina_enemy = null
		var min_stamina_ratio = INF
		for enemy in enemies:
			var stamina_ratio = float(enemy.stamina) / float(max(enemy.max_stamina, 1))
			if stamina_ratio < min_stamina_ratio:
				min_stamina_ratio = stamina_ratio
				lowest_stamina_enemy = enemy
		if lowest_stamina_enemy:
			return lowest_stamina_enemy.global_position
	
	return p.global_position

func _select_area_position(sad: Dictionary, is_defensive: bool) -> Vector2:
	var p = sad.player
	var our_goal = _get_our_goal_position(p)
	
	if is_defensive:
		return our_goal + Vector2(0, 20)
	else:
		return p.global_position + Vector2(0, -20)

func _get_our_goal_position(player: CharacterBody2D) -> Vector2:
	if player.team == "a":
		return GOAL_A
	else:
		return GOAL_B

func _get_enemy_goal_position(player: CharacterBody2D) -> Vector2:
	if player.team == "a":
		return GOAL_B
	else:
		return GOAL_A

func _get_enemy_ball_holder(player: CharacterBody2D) -> CharacterBody2D:
	if not ball_node or not ball_node.owner_player:
		return null
	if ball_node.owner_player.team != player.team:
		return ball_node.owner_player
	return null

func _execute_skill(sad: Dictionary, skill_info: Dictionary) -> void:
	var p = sad.player
	var profile = sad.profile

	sad["skill_exec_count"] += 1

	if _deterministic_dice(_player_key(sad), hash("mistake_" + str(skill_info["skill_id"])), sad["skill_exec_count"]) < profile.skill_mistake_chance:
		var mistake_type = _decide_mistake_type(sad, skill_info)
		# 失误→局部短冷却：周期计数时钟冻结该技能，防重选重掷循环
		var hold: Dictionary = sad.get("mistake_hold", {})
		hold[str(skill_info["skill_id"])] = int(sad["skill_decide_count"]) + MISTAKE_HOLD_CYCLES
		sad["mistake_hold"] = hold
		print("[SpiritAI] %s 技能失误: %s (失误类型: %s, 冷却%d周期)" % [p.name, skill_info["skill_data"].get("name", "unknown"), mistake_type, MISTAKE_HOLD_CYCLES])
		return

	var target = _select_player_target(sad, skill_info)
	var field_pos = _select_field_position(sad, skill_info)

	# 视野闸门（02前置地基工单B，主人裁决 2026-09-25：不准借选择卡视野）：
	# 带选中对象的攻击/控制类技能选不出合法（视野内）目标 → 放弃释放
	if target == null and skill_info.get("has_player_tag", false):
		var exec_intents: Dictionary = skill_info["intents"]
		if float(exec_intents.get("attack", 0.0)) > 0.5 or float(exec_intents.get("control", 0.0)) > 0.5:
			return

	var target_data: Dictionary = {}
	if target:
		target_data["target_player_id"] = target.get_instance_id()
		target_data["target_position"] = target.global_position
	if skill_info.get("has_field_tag", false):
		target_data["field_position"] = field_pos
	
	var success = spirit_system.use_skill(p.get_instance_id(), skill_info["skill_id"], target_data)

	if success:
		sad.last_skill_use_time = Time.get_ticks_msec() / 1000.0
		var target_name = "自己" if target == p else (target.name if target else "无")
		var pos_str = "无" if not skill_info.get("has_field_tag", false) else "场地"
		print("[SpiritAI] %s 使用技能: %s (评分: %.1f, 目标: %s, 位置: %s)" % [p.name, skill_info["skill_data"].get("name", "unknown"), skill_info.get("base_value", 0), target_name, pos_str])
		
		_send_skill_message(sad, skill_info, target)

func _send_skill_message(sad: Dictionary, skill_info: Dictionary, target: CharacterBody2D) -> void:
	var p = sad.player
	var intents = skill_info["intents"]
	
	if not battle_manager or not battle_manager.comm_system:
		return
	
	if intents.get("support", 0) > 0.5 and target != null and target != p:
		battle_manager.comm_system.try_send_message(p, battle_manager.comm_system.MsgType.BUFF_ON_YOU)
		battle_manager.comm_system.record_message(p, battle_manager.comm_system.MsgType.BUFF_ON_YOU)
	
	if intents.get("attack", 0) > 0.7 and intents.get("control", 0) > 0.3:
		if _deterministic_dice(_player_key(sad), hash("msgsr_" + str(skill_info["skill_id"])), sad["skill_exec_count"]) < 0.3:
			battle_manager.comm_system.try_send_message(p, battle_manager.comm_system.MsgType.SKILL_READY)
			battle_manager.comm_system.record_message(p, battle_manager.comm_system.MsgType.SKILL_READY)

func _try_send_need_buff(sad: Dictionary) -> void:
	var p = sad.player
	
	if not battle_manager or not battle_manager.comm_system:
		return
	
	if not battle_manager.comm_system.can_send(p):
		return
	
	var has_support_skill = false
	for analysis in sad.skills_analysis:
		if analysis.get("synergy_level", "low") == "critical":
			has_support_skill = true
			break
	
	var stamina_ratio = float(p.stamina) / float(max(p.max_stamina, 1))
	var energy_ratio = float(p.spirit_energy) / float(max(p.max_spirit_energy, 1))
	
	if (stamina_ratio < 0.2 or energy_ratio < 0.2) and not has_support_skill:
		if _deterministic_dice(_player_key(sad), hash("msgnb"), sad["skill_decide_count"]) < 0.2:
			battle_manager.comm_system.try_send_message(p, battle_manager.comm_system.MsgType.NEED_BUFF)
			battle_manager.comm_system.record_message(p, battle_manager.comm_system.MsgType.NEED_BUFF)

func _decide_mistake_type(sad: Dictionary, skill_info: Dictionary) -> String:
	var r = _deterministic_dice(_player_key(sad), hash("mtype_" + str(skill_info["skill_id"])), sad["skill_exec_count"])
	if r < 0.4:
		return "时机失误"
	elif r < 0.7:
		return "目标失误"
	else:
		return "技能失误"
