extends Node

const AIProfile = preload("res://scripts/battle/ai_profile.gd")
## 16号合一：端区锚点（外场方向锚，原误称 GOAL_*）权威定义=ai_manager.SIDE_ANCHOR_A/B，
## 本文件经脚本常量引用（ai_manager 侧已改运行时 load 解除循环预载）。
## 领域知识详见 ai_manager 头部永久注释（交叉布局/勿按球门修/搞混史）。
const AIManagerScript = preload("res://scripts/battle/ai_manager.gd")

# ⚠ 场地方位领域知识（主人裁定 2026-09-27 永久注释，历史上多次搞混——防再混）：
# 决竞球没有球门（得分=击中球员）。SIDE_ANCHOR_A/SIDE_ANCHOR_B 实为「外场方向锚点」，交叉布局：
#   SIDE_ANCHOR_A=(300,0)=a 队外场锚——a 队内场在左(x≤0)，但 a 队流放外场在右侧（对方内场背后，
#   环带布局；见 field_zone.start_field_transition：流放区 a=右外场、b=左外场）；
#   SIDE_ANCHOR_B=(-300,0)=b 队外场锚，镜像对称。
# 消费语义：防守提醒/保护站位/放置朝向中的 SIDE_ANCHOR_X =「X 队自己的后方（外场）方向」，设计如此。
# 勿按"球门/方向反了"修（2026-09-27 曾误判方向反了，主人纠正；此前也有搞混史）。

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
const PRIMITIVES_E := preload("res://scripts/battle/spirit_ai/primitives_e.gd")
const EVENT_HOOKS_SCRIPT := preload("res://scripts/battle/spirit_ai/event_hooks.gd")
const AI_INPUT_SOURCE := preload("res://scripts/battle/spirit_ai/ai_input_source.gd")

## wave 字母 → 契约函数表分发（registry 按 JSON 顶层 wave 打标；波E 未交付=无条目=未命中）
const _WAVE_PRIMITIVES := {"A": PRIMITIVES_A, "B": PRIMITIVES_B, "C": PRIMITIVES_C, "D": PRIMITIVES_D, "E": PRIMITIVES_E}

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

## 决策评分明细 dump（10工单P3观测层；get_decision_dump 只读口，_decide_skill 每周期刷新，纯观测零行为）
var last_decision_dump: Dictionary = {}

## 22-B 投球窗口事件钩子连接标志（幂等；仅 event_hook_priority 开时连接）
var _catch_hook_connected := false


## 22-B S2 钩子连接（幂等；开关 event_hook_priority 默认关=不连接=轮询旧路径逐位一致）
func _ensure_catch_hook() -> void:
	if _catch_hook_connected:
		return
	if not SpiritAIPrimitiveRegistry.get_extra_flag("event_hook_priority"):
		return
	if ball_node == null or not is_instance_valid(ball_node) or not ball_node.has_signal("ball_caught"):
		return
	_catch_hook_connected = true
	ball_node.ball_caught.connect(_on_ball_caught_hook)


## 22-B：持球开始 → 立即技能评估（旁路轮询时钟；非注册/无效/受控者静默跳过）
func _on_ball_caught_hook(catcher) -> void:
	if catcher == null or not is_instance_valid(catcher):
		return
	for sad in spirit_ai_data:
		if sad.get("player") != catcher:
			continue
		if not _is_valid(sad):
			return
		_decide_skill(sad)
		sad.skill_think_timer = 0.0   # 立即评估后重置轮询相位（防同窗口双评）
		return

## ===== 工单15交付物1：技能释放统计表（纯观察零决策影响；run_sim/平台报告聚合源）=====
## skill_id -> {"name","cat"(BALL/PLAYER/FIELD),"ok","miss","registered"}
## 15工单验收口径：覆盖率=出手技能数/实配技能数（基线3/9），三分类各≥1出手，失误率可见
var _cast_stats: Dictionary = {}
var _cast_stats_hooked: bool = false

func initialize(battle_mgr: Node2D, spirit_sys: SpiritSystemManager, ai_mgr: Node) -> void:
	battle_manager = battle_mgr
	spirit_system = spirit_sys
	ai_manager = ai_mgr
	_load_element_counters()
	# Q9b 波E复制族：敌方施法快照喂数（event_hooks record_skill_cast；仅 success 施法入账）
	if spirit_system and not spirit_system.skill_used.is_connected(_on_skill_used_for_hooks):
		spirit_system.skill_used.connect(_on_skill_used_for_hooks)
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
		_cast_stats_register(sad["skills_analysis"])
		print("[SpiritAI] %s 技能分析完成，技能数: %d" % [sad["player"].name, sad["skills_analysis"].size()])
	_cast_stats_hookup()


## ===== 工单15交付物1：技能释放统计（纯观察，不碰决策/骰子/评分任何路径）=====

## 分母注册：实配主动技能（被动由事件触发不进评分池，不计覆盖率分母）
func _cast_stats_register(skills_analysis: Array[Dictionary]) -> void:
	for analysis in skills_analysis:
		if str(analysis.get("skill_data", {}).get("type", "active")) == "passive":
			continue
		_cast_stats_note(analysis, true)

## 单技能登记（registered=true 计入覆盖率分母；出手时未注册也补记但不入分母）
func _cast_stats_note(skill_info: Dictionary, registered: bool) -> void:
	var sid := str(skill_info.get("skill_id", ""))
	if sid.is_empty():
		return
	if _cast_stats.has(sid):
		if registered:
			_cast_stats[sid]["registered"] = true
		return
	var cat := "PLAYER"
	if bool(skill_info.get("has_field_tag", false)):
		cat = "FIELD"
	elif bool(skill_info.get("has_ball_tag", false)):
		cat = "BALL"
	_cast_stats[sid] = {
		"name": str(skill_info.get("skill_data", {}).get("name", sid)),
		"cat": cat, "ok": 0, "miss": 0, "registered": registered,
	}

## 出手计数（_execute_skill 成功/失误两处调用）
func _cast_stats_count(skill_info: Dictionary, ok: bool) -> void:
	_cast_stats_note(skill_info, false)
	var sid := str(skill_info.get("skill_id", ""))
	if sid.is_empty():
		return
	var entry: Dictionary = _cast_stats[sid]
	if ok:
		entry["ok"] = int(entry.get("ok", 0)) + 1
	else:
		entry["miss"] = int(entry.get("miss", 0)) + 1

## 终场信号挂接（GameManager.match_ended；autoload 信号无需在树）
func _cast_stats_hookup() -> void:
	if _cast_stats_hooked:
		return
	_cast_stats_hooked = true
	GameManager.match_ended.connect(_print_cast_stats)

## 终场统计表（[SpiritAIStats] 行供 run_sim.sh 聚合；SUMMARY 行机器可读）
func _print_cast_stats(_score_a: int = 0, _score_b: int = 0, _result: String = "") -> void:
	var denom_cat := {"BALL": 0, "PLAYER": 0, "FIELD": 0}
	var cast_cat := {"BALL": 0, "PLAYER": 0, "FIELD": 0}
	var total := 0
	var cast := 0
	var ok_sum := 0
	var miss_sum := 0
	var sids: Array = _cast_stats.keys()
	sids.sort()  # 稳定输出（同种子逐位可比）
	print("[SpiritAIStats] === 技能释放统计 ===")
	for sid in sids:
		var e: Dictionary = _cast_stats[sid]
		if not bool(e.get("registered", false)):
			continue
		total += 1
		denom_cat[str(e["cat"])] = int(denom_cat.get(str(e["cat"]), 0)) + 1
		var ok_n := int(e.get("ok", 0))
		var miss_n := int(e.get("miss", 0))
		ok_sum += ok_n
		miss_sum += miss_n
		if ok_n > 0:
			cast += 1
			cast_cat[str(e["cat"])] = int(cast_cat.get(str(e["cat"]), 0)) + 1
		print("[SpiritAIStats] %s %s: 成功%d 失误%d" % [str(e["cat"]), str(e["name"]), ok_n, miss_n])
	var cover_pct := (100.0 * cast / total) if total > 0 else 0.0
	var total_try := ok_sum + miss_sum
	var miss_pct := (100.0 * miss_sum / total_try) if total_try > 0 else 0.0
	print("[SpiritAIStats] SUMMARY 出手=%d/%d 覆盖率=%.1f%% BALL=%d/%d PLAYER=%d/%d FIELD=%d/%d 成功=%d 失误=%d 失误率=%.1f%%" % [
		cast, total, cover_pct,
		int(cast_cat["BALL"]), int(denom_cat["BALL"]),
		int(cast_cat["PLAYER"]), int(denom_cat["PLAYER"]),
		int(cast_cat["FIELD"]), int(denom_cat["FIELD"]),
		ok_sum, miss_sum, miss_pct])

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

	# 22-B S2（工单22 主人批"继续主线B"）：投球窗口事件钩子（连接逻辑见 _ensure_catch_hook）
	_ensure_catch_hook()

	for sad in spirit_ai_data:
		if not _is_valid(sad):
			continue

		sad.skill_think_timer += delta
		# 22-B（P2修复）：事件钩子开时，持球者 think 提频
		# （持球窗口<0.5s 时轮询一次都轮不到的错拍修复；关=轮询旧路径逐位一致）
		var cadence: float = sad.profile.skill_think_interval
		if SpiritAIPrimitiveRegistry.is_event_hook_priority() and sad.player.is_carrying_ball:
			cadence = minf(cadence, 0.1)  # 持球期 100ms 档（10次/秒，覆盖 0.1s 级持球窗口）
		if sad.skill_think_timer >= cadence:
			sad.skill_think_timer = 0.0
			_decide_skill(sad)
			_try_send_need_buff(sad)

func _is_valid(sad: Dictionary) -> bool:
	var p = sad.player
	if not p or not is_instance_valid(p):
		return false
	if ai_manager and ai_manager.input_manager and ai_manager.input_manager.controlled_player == p:
		return false
	# 14号修复RC0（主人裁定d，14a诊断§四1）：战败流放=is_defeated+is_penalized 双置
	# （battle_manager 击败→传送外场→set_penalized）→ 外场与内场同权放行决策；
	# 纯 is_defeated 未流放（击倒瞬态/真正出局）维持排除
	if p.is_defeated and not p.is_penalized:
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
	var gate_traces: Array = []
	var scored_skills: Array[Dictionary] = []
	for skill_info in available_skills:
		var gate := _evaluate_primitive_gates(sad, skill_info, primitive_ctx_box)
		gate_traces.append({
			"skill_id": str(skill_info["skill_id"]),
			"gated": bool(gate.get("gated", false)),
			"ok": bool(gate.get("ok", false)),
			"bonus": snappedf(float(gate.get("bonus", 1.0)), 0.01),
		})
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
		_record_decision_dump(sad, gate_traces, [], null, 0.0)
		return

	var best_skill = _select_skill_with_softmax(sad, scored_skills, profile.skill_selection_temperature)

	_record_decision_dump(sad, gate_traces, scored_skills, best_skill, float(profile.skill_use_threshold))

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

	# 14号修复RC1（主人裁定d，14a诊断§四2）：流放球员无条件进入技能思考
	# （原逻辑在"不持球+球非己方+非defender+无场地技"下 think 全灭——金刚类真身）
	if p.is_penalized:
		return true

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

## 决策明细 dump 只读口（10工单P3观测层，observe_layer 探活 get_decision_dump 自动点亮）
## Q9b 波E复制族：技能释放快照喂数（hooks 头注处方；caster 经本表实例反查）
func _on_skill_used_for_hooks(skill_id: String, caster_id: int, success: bool) -> void:
	if not success or _event_hooks == null:
		return
	for sad in spirit_ai_data:
		var caster = sad.get("player")
		if caster != null and is_instance_valid(caster) and caster.get_instance_id() == caster_id:
			_event_hooks.record_skill_cast(caster, skill_id)
			return


func get_decision_dump() -> Dictionary:
	return last_decision_dump


## 刷新决策明细（纯观测零行为）：闸门轨迹+候选评分 top3+胜者阈值判定+开关状态
func _record_decision_dump(sad: Dictionary, gate_traces: Array, scored_skills: Array, best_skill: Variant, threshold: float) -> void:
	var p: CharacterBody2D = sad.player
	var ranked: Array = []
	for scored in scored_skills:
		ranked.append({
			"skill_id": str(scored["skill"]["skill_id"]),
			"score": snappedf(float(scored["score"]), 0.1),
		})
	ranked.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	last_decision_dump = {
		"player": str(p.name),
		"team": str(p.team),
		"cycle": int(sad.get("skill_decide_count", 0)),
		"switches": SpiritAIPrimitiveRegistry.get_switches_state(),
		"gates": gate_traces,
		"top3": ranked.slice(0, 3),
		"threshold": snappedf(threshold, 0.1),
		"chosen": (str(best_skill["skill"]["skill_id"]) if best_skill != null and float(best_skill["score"]) >= threshold else ""),
	}

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
	# Q15收口（0928-10）：优先 battle 级全局实例（全 AI 场景 input_manager 懒建不触发）
	var state_manager = battle_manager.get("skill_state_manager")
	if state_manager == null:
		var input_manager = battle_manager.get("input_manager")
		if input_manager != null:
			state_manager = input_manager.get("skill_state_manager")
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
		# 14号附带修正（14a诊断§二2/§四5）：_is_in_field_of_view 是纯角度锥无距离上限，
		# 补 vision_range 距离过滤对齐 ai_manager 感知层口径——防开波后外场隔墙越界施法
		var vision_range := 350.0
		var profile = sad.get("profile")
		if profile != null:
			vision_range = float(profile.vision_range)
		for enemy in _get_enemies(p):
			if is_instance_valid(enemy) \
					and p.global_position.distance_to(enemy.global_position) <= vision_range \
					and ai_manager._is_in_field_of_view(fov_ap, enemy.global_position):
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
	# 17号v2：Q7预留键 combo_setup_active 兑现（COMBO_SETUP 活跃=连招窗口；关=恒 false，ally_cast_setup gate 语义待 JSON 换名）
	if battle_manager and battle_manager.comm_system:
		var comm_v2 = battle_manager.comm_system
		ctx["combo_setup_active"] = comm_v2.protocol_v2_enabled \
				and comm_v2.is_type_active(str(p.team), comm_v2.MsgType.COMBO_SETUP)
	ctx["enemy_goal"] = _get_enemy_goal_position(p)
	var carrier = _get_enemy_ball_holder(p)
	if carrier != null and is_instance_valid(carrier):
		ctx["enemy_carrier"] = carrier
		ctx["enemy_carrier_visible"] = carrier in visible_enemies
	# 13号场地知识 ctx（Q9a①，主人批 2026-09-28）：个体场地语义单口组装，
	# 静态几何由原语 preload knowledge_* 直查（布场API）。纯增量：无描述符引用前零行为
	var field_zone_script: GDScript = load("res://scripts/battle/field_zone.gd")
	var my_zone: String = str(field_zone_script.knowledge_zone_of(p.global_position, str(p.team)))
	ctx["my_zone"] = my_zone
	ctx["in_outer"] = my_zone.begins_with("outer")
	ctx["goal_own"] = field_zone_script.knowledge_goal_area_point(str(p.team))
	ctx["goal_enemy"] = field_zone_script.knowledge_goal_area_point("b" if str(p.team) == "a" else "a")
	# Q10 RC2 配套：己方持球判定（outer_support gate 用；与 enemy_carrier 对偶）
	var ball_owner = ball_node.owner_player if (ball_node and is_instance_valid(ball_node)) else null
	ctx["own_team_has_ball"] = ball_owner != null and is_instance_valid(ball_owner) and ball_owner.team == p.team
	# Q9b 波E时机（0928-9 批准）：复制族快照 + 救球弹道预测（纯增量，无引用前零行为）
	if _event_hooks:
		ctx["ally_skill_cast_recent"] = not _event_hooks.get_recent_enemy_cast(p).is_empty()
	var bop := false
	if ai_manager and ai_manager.has_method("_is_ball_heading_to_outer") 			and ball_node and is_instance_valid(ball_node) and bool(ball_node.is_active) 			and bool(ai_manager._is_ball_heading_to_outer(str(p.team))):
		var pred: Vector2 = ball_node.global_position + (ball_node.ball_direction * ball_node.ball_speed) * 1.5
		var fz: GDScript = load("res://scripts/battle/field_zone.gd")
		bop = str(fz.knowledge_zone_of(pred, str(p.team))).begins_with("outer")
	ctx["ball_out_predicted"] = bop
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
	
	var comm = battle_manager.comm_system
	var intents = skill_info["intents"]
	var factor: float = 1.0
	
	if intents.get("support", 0) > 0.3:
		if comm.has_need_buff(p.team):
			var need_buff_sender = comm.get_need_buff_sender(p.team)
			if need_buff_sender and p.global_position.distance_to(need_buff_sender.global_position) < 150.0:
				factor *= 1.4
	
	if intents.get("attack", 0) > 0.5:
		if comm.has_buff_on_you(p):
			factor *= 1.25
	
	# ===== 17号v2 消费（protocol_v2 关=两查询恒 false，本段恒不触发）=====
	# COMBO_SETUP 连招窗口：队友起手邀约期内，进攻技评分↑（连招第2拍价值，06§三 ally_cast_setup 语义的评分面）
	if comm.protocol_v2_enabled and comm.is_type_active(p.team, comm.MsgType.COMBO_SETUP) \
			and intents.get("attack", 0) > 0.3:
		factor *= 1.25
	
	# ENEMY_ULT_WARNING 敌大招预警窗口：控场/防御技评分↑（cc_immune 类时机来源，Q3/Q10口径）
	if comm.is_enemy_ult_warning_hot(p.team) \
			and (intents.get("control", 0) > 0.3 or intents.get("defense", 0) > 0.3):
		factor *= 1.3
	
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
		# 14号修复RC3（主人裁定d，14a诊断§四4）：流放施法者对内场队友按比例计距
		# （外场↔内场 380px+ 的绝对距离把支援分压至≈0，按 0.4 系数豁免）
		if p.is_penalized:
			distance *= 0.4

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
		return AIManagerScript.SIDE_ANCHOR_A
	else:
		return AIManagerScript.SIDE_ANCHOR_B

func _get_enemy_goal_position(player: CharacterBody2D) -> Vector2:
	if player.team == "a":
		return AIManagerScript.SIDE_ANCHOR_B
	else:
		return AIManagerScript.SIDE_ANCHOR_A

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
		_cast_stats_count(skill_info, false)
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
		# Q12直生+止血阀（Q14备案 2026-09-27）：field_position 仅在波D开启时下发——
		# AI 墙/区域落地随波D能力开启（彼时放置语义=波D六意图），全关世界维持无墙锚定
		# （实测全关直生墙入世=卡死2/8/1+seed1传球率11.1%，故挂开关走08止血阀语义）；
		# 不下发时 handler 直生分支无坐标自动回退鼠标路径（=Q12前"白放"世界，玩家路径零影响）
		if SpiritAIPrimitiveRegistry.is_wave_enabled("D"):
			target_data["field_position"] = field_pos
	
	var success = spirit_system.use_skill(p.get_instance_id(), skill_info["skill_id"], target_data)

	if success:
		sad.last_skill_use_time = Time.get_ticks_msec() / 1000.0
		var target_name = "自己" if target == p else (target.name if target else "无")
		var pos_str = "无" if not skill_info.get("has_field_tag", false) else "场地"
		print("[SpiritAI] %s 使用技能: %s (评分: %.1f, 目标: %s, 位置: %s)" % [p.name, skill_info["skill_data"].get("name", "unknown"), skill_info.get("base_value", 0), target_name, pos_str])
		_cast_stats_count(skill_info, true)
		
		_send_skill_message(sad, skill_info, target)

func _send_skill_message(sad: Dictionary, skill_info: Dictionary, target: CharacterBody2D) -> void:
	var p = sad.player
	var intents = skill_info["intents"]
	
	if not battle_manager or not battle_manager.comm_system:
		return
	var comm = battle_manager.comm_system
	
	if intents.get("support", 0) > 0.5 and target != null and target != p:
		if comm.try_send_message(p, comm.MsgType.BUFF_ON_YOU):
			comm.record_message(p, comm.MsgType.BUFF_ON_YOU)
			_comm_v2_post(comm, p, comm.MsgType.BUFF_ON_YOU, skill_info, {"urgency": 0.6})
	
	if intents.get("attack", 0) > 0.7 and intents.get("control", 0) > 0.3:
		if _deterministic_dice(_player_key(sad), hash("msgsr_" + str(skill_info["skill_id"])), sad["skill_exec_count"]) < 0.3:
			if comm.try_send_message(p, comm.MsgType.SKILL_READY):
				comm.record_message(p, comm.MsgType.SKILL_READY)
				_comm_v2_post(comm, p, comm.MsgType.SKILL_READY, skill_info, {"urgency": 0.8})

	# 17号v2新消息（protocol_v2 关=整段跳过：不占 legacy 冷却/频控槽，构造性零扰动）
	if comm.protocol_v2_enabled:
		# 17号v2新消息：COMBO_SETUP（连招邀约，12号合体链可直接用）——合体半装/连招起手技释放即广播
		var raw_tags: Array = skill_info.get("raw_tags", [])
		var is_combo_setup: bool = raw_tags.has("player_combo_ready") \
				or bool(skill_info.get("skill_data", {}).get("combo_setup", false))
		if is_combo_setup:
			if comm.try_send_message(p, comm.MsgType.COMBO_SETUP):
				comm.record_message(p, comm.MsgType.COMBO_SETUP)
				_comm_v2_post(comm, p, comm.MsgType.COMBO_SETUP, skill_info, {"urgency": 0.8})

		# 17号v2新消息：ENEMY_ULT_WARNING（大招预警）——高耗能技（≥30能量）释放即广播，消费端按敌队查询
		var energy_cost: float = float(skill_info.get("skill_data", {}).get("energy_cost", 0))
		if energy_cost >= 30.0:
			if comm.try_send_message(p, comm.MsgType.ENEMY_ULT_WARNING):
				comm.record_message(p, comm.MsgType.ENEMY_ULT_WARNING)
				_comm_v2_post(comm, p, comm.MsgType.ENEMY_ULT_WARNING, skill_info, {"urgency": 0.9})


## 17号v2 负载登记（须在 legacy try_send 成功后调用；record_v2_message 受 protocol_v2 开关约束，
## 关=零存储零行为；不走 post_message 以免二次冷却闸拦下真实路径）
func _comm_v2_post(comm, sender: CharacterBody2D, msg_type: int, skill_info: Dictionary, payload: Dictionary) -> void:
	var full_payload: Dictionary = {
		"related_skill_id": str(skill_info.get("skill_id", "")),
		"position": sender.global_position,
	}
	for k in payload:
		full_payload[k] = payload[k]
	comm.record_v2_message(sender, msg_type, full_payload)

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
