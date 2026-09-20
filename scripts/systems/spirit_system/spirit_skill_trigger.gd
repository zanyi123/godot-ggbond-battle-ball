extends Node
class_name SpiritSkillTrigger

## 元灵技能触发器
## 负责检测技能使用并调用标签效果

signal skill_triggered(skill_id: String, caster_id: int, target_data: Dictionary)
signal skill_effect_applied(skill_id: String, tag_id: String, effect_result: Dictionary)
signal skill_ui_feedback(effect_type: String, effect_data: Dictionary)

# 标签注册表
var _tags_registry: Dictionary = {}

# 标签效果处理器
var _effect_handler: SpiritTagEffectHandler

# 玩家技能映射（玩家ID -> 上场技能列表）
var _player_skills: Dictionary = {}  # {player_id: [skill_ids]}

# E3：被动注册表 {"p":player_id,"s":skill_id} -> {ev, trigger}
var _passive_registry: Dictionary = {}

# 技能冷却状态
var _skill_cooldowns: Dictionary = {}  # {player_id: {skill_id: remaining_time}}
# CD 初值记录（供冷却进度按实际生效CD计算比例）
var _skill_cd_totals: Dictionary = {}  # {player_id: {skill_id: applied_cd}}

# 战斗中引用
var battle_manager: Node
var players: Array[Node] = []
var ball_node: Node

func _ready() -> void:
	# 加载标签注册表
	_load_tags_registry()

	# 创建效果处理器
	_effect_handler = SpiritTagEffectHandler.new()
	add_child(_effect_handler)
	_effect_handler.effect_applied.connect(_on_effect_applied)
	_effect_handler.effect_finished.connect(_on_effect_finished)

	print("[SpiritSkillTrigger] 初始化完成")

## 加载标签注册表
func _load_tags_registry() -> void:
	var file = FileAccess.open("res://data/spirits/tags_registry.json", FileAccess.READ)
	if file:
		var json_text = file.get_as_text()
		file.close()

		var json = JSON.new()
		var error = json.parse(json_text)
		if error == OK:
			var data = json.data
			for tag in data.tags:
				_tags_registry[tag.id] = tag
			print("[SpiritSkillTrigger] 加载标签注册表成功: ", _tags_registry.size(), " 个标签")
		else:
			printerr("[SpiritSkillTrigger] 解析标签注册表失败: ", json.get_error_message())
	else:
		printerr("[SpiritSkillTrigger] 无法打开标签注册表文件")

## 设置战斗引用
func setup_battle_refs(battle_mgr: Node, player_nodes: Array[Node], ball: Node) -> void:
	battle_manager = battle_mgr
	players = player_nodes
	ball_node = ball

	if _effect_handler:
		_effect_handler.battle_manager = battle_manager
		_effect_handler.ball_node = ball
		_effect_handler.players = players

## 设置玩家上场技能
func set_player_skills(player_id: int, skill_ids: Array[String]) -> void:
	_player_skills[player_id] = skill_ids

	# 初始化冷却状态
	if not _skill_cooldowns.has(player_id):
		_skill_cooldowns[player_id] = {}

	for skill_id in skill_ids:
		if not _skill_cooldowns[player_id].has(skill_id):
			_skill_cooldowns[player_id][skill_id] = 0.0
	# E3：被动技能按 trigger.event 向事件总线订阅
	_subscribe_passives(player_id, skill_ids)

## 被动注册：trigger.event → 响应器（事件到达→条件→CD→能量→_fire_skill）
func _subscribe_passives(player_id: int, skill_ids: Array[String]) -> void:
	var bus = get_tree().get_first_node_in_group("battle_event_bus") if is_inside_tree() else null
	if bus == null:
		return
	for skill_id in skill_ids:
		var sd := _get_skill_data(skill_id)
		if sd.is_empty() or sd.get("type", "active") != "passive":
			continue
		var trigger: Dictionary = sd.get("trigger", {})
		if trigger.is_empty() or trigger.get("event", "") == "":
			push_warning("[SpiritSkillTrigger] 被动缺少 trigger 配置，不自动触发: %s" % skill_id)
			continue
		var ev := _event_name_to_enum(str(trigger.get("event")))
		if ev < 0:
			push_warning("[SpiritSkillTrigger] 未知触发事件: %s (%s)" % [str(trigger.get("event")), skill_id])
			continue
		_passive_registry[{"p": player_id, "s": skill_id}] = {"ev": ev, "trigger": trigger}
		bus.subscribe(ev, _on_passive_event.bind({"p": player_id, "s": skill_id, "trigger": trigger}))
		print("[SpiritSkillTrigger] 被动注册: %s ← %s" % [skill_id, str(trigger.get("event"))])

## 事件名（字符串）→ GameEvent 枚举
func _event_name_to_enum(name: String) -> int:
	# 格式 "Defend.BOUNCED" / "Hit.HIT_TAKEN"
	var parts := name.split(".")
	if parts.size() != 2:
		return -1
	var prefix := parts[0].to_lower()
	for ev in BattleEventBus.GameEvent.values():
		var key: String = BattleEventBus.GameEvent.keys()[ev]
		if key.to_lower().begins_with(prefix) and key.to_lower().ends_with(parts[1].to_lower()):
			return ev
	return -1

## 被动事件响应：condition → CD → 能量 → _fire_skill
func _on_passive_event(_payload: Dictionary, ctx: Dictionary) -> void:
	var player_id: int = ctx["p"]
	var skill_id: String = ctx["s"]
	var trigger: Dictionary = ctx["trigger"]
	# 条件检查（首期：{field, op, value} 简单比较）
	var cond: Dictionary = trigger.get("condition", {})
	if not cond.is_empty() and not _check_condition(cond, _payload, player_id):
		return
	# 冷却
	if get_skill_cooldown(player_id, skill_id) > 0.0:
		return
	# 触发
	var sd := _get_skill_data(skill_id)
	if sd.is_empty():
		return
	print("[SpiritSkillTrigger] 被动触发: %s (%s)" % [skill_id, str(trigger.get("event"))])
	_fire_skill(sd, player_id, skill_id, {"trigger_payload": _payload})

## 首期条件检查：field/op/value（op: eq/ne/gt/lt/gte/lte）
func _check_condition(cond: Dictionary, payload: Dictionary, player_id: int) -> bool:
	var field := str(cond.get("field", ""))
	var op := str(cond.get("op", "eq"))
	var value = cond.get("value")
	# field 解析：payload 直接字段；或 "self.<属性>" 取本球员属性
	var actual = null
	if payload.has(field):
		actual = payload[field]
	elif field.begins_with("self."):
		var p := _get_player_by_id(player_id)
		if p != null:
			actual = p.get(field.substr(5))
	if actual == null:
		return false
	match op:
		"eq": return actual == value
		"ne": return actual != value
		"gt", "lt", "gte", "lte":
			# 数值比较：非数值（对象/字典）一律不满足，防 float(对象) 崩溃
			if not (actual is float or actual is int):
				return false
			if not (value is float or value is int):
				return false
			var av := float(actual)
			var vv := float(value)
			match op:
				"gt": return av > vv
				"lt": return av < vv
				"gte": return av >= vv
				_: return av <= vv
	return false

## 主入口：触发技能
## @param player_id 玩家ID
## @param skill_id 技能ID
## @param target_data 目标数据（可选）
## @return 是否成功触发
func trigger_skill(player_id: int, skill_id: String, target_data: Dictionary = {}) -> bool:
	print("[SpiritSkillTrigger] 触发技能: player_id=", player_id, ", skill_id=", skill_id)

	# 检查玩家是否有该技能
	if not _player_skills.has(player_id):
		print("[SpiritSkillTrigger] 玩家无上场技能: ", player_id)
		return false

	if not skill_id in _player_skills[player_id]:
		print("[SpiritSkillTrigger] 玩家未上场该技能: ", skill_id)
		return false

	# 检查冷却
	if _skill_cooldowns.has(player_id) and _skill_cooldowns[player_id].has(skill_id):
		if _skill_cooldowns[player_id][skill_id] > 0:
			print("[SpiritSkillTrigger] 技能冷却中: ", _skill_cooldowns[player_id][skill_id])
			return false

	# 获取技能数据
	var skill_data = _get_skill_data(skill_id)
	if skill_data.is_empty():
		printerr("[SpiritSkillTrigger] 技能数据不存在: ", skill_id)
		return false

	# E3：被动技能禁止主动释放（只能由 trigger 事件自动触发）
	if skill_data.get("type", "active") == "passive":
		print("[SpiritSkillTrigger] 被动技能不可主动释放: ", skill_id)
		return false

	return _fire_skill(skill_data, player_id, skill_id, target_data)


## 实际触发路径（主动与被动自动触发共用；调用方已完成资格校验）
func _fire_skill(skill_data: Dictionary, player_id: int, skill_id: String, target_data: Dictionary) -> bool:
	# 检查能量消耗（2026-09-17 单点扣费：基础 + 标签附加）
	var energy_cost: int = int(skill_data.get("energy_cost", 0))
	for tag_id in skill_data.get("tags", []):
		var tag_data: Dictionary = _tags_registry.get(tag_id, {})
		energy_cost += int(tag_data.get("energy_cost", 0))
	if not _consume_energy(player_id, energy_cost):
		print("[SpiritSkillTrigger] 能量不足")
		return false

	# 发送技能触发信号
	skill_triggered.emit(skill_id, player_id, target_data)

	# 先重置施法者自己的球修饰符准备区（2026-09-19 Step2：不再全清，别人的准备区不受影响）
	if _effect_handler:
		_effect_handler.reset_ball_mods_for(player_id)

	# 执行技能标签效果
	_execute_skill_tags(skill_id, player_id, target_data)

	# 设置冷却
	var cooldown = skill_data.get("cooldown", 0)
	_set_skill_cooldown(player_id, skill_id, cooldown)

	return true

## 技能数据缓存
var _skills_cache: Dictionary = {}  # {skill_id: skill_data}
var _skills_loaded: bool = false

## 加载技能数据到缓存
func _load_skills_data() -> void:
	if _skills_loaded:
		return
	var file := FileAccess.open("res://data/spirits/skills.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK:
			var skills_array: Array = json.data.get("skills", []) if json.data is Dictionary else []
			for s in skills_array:
				_skills_cache[s.get("id", "")] = s
		file.close()
	_skills_loaded = true

## 获取技能数据（E3：passive 同步锁——tag duration 不得超过 cooldown）
func _get_skill_data(skill_id: String) -> Dictionary:
	_load_skills_data()
	if _skills_cache.has(skill_id):
		var sd: Dictionary = _skills_cache[skill_id]
		_apply_passive_sync_lock(skill_id, sd)
		return sd
	return {}

## 被动生效时长同步锁：任何 tag duration > cooldown 时 clamp 到 cooldown
func _apply_passive_sync_lock(skill_id: String, sd: Dictionary) -> void:
	if sd.get("_lock_checked", false):
		return
	sd["_lock_checked"] = true
	if sd.get("type", "active") != "passive":
		return
	var cd := float(sd.get("cooldown", 0.0))
	if cd <= 0.0:
		return
	var params: Dictionary = sd.get("tag_params", {})
	for tag_id in params:
		if params[tag_id] is Dictionary:
			var dur := float(params[tag_id].get("duration", 0.0))
			if dur > cd:
				params[tag_id]["duration"] = cd
				push_warning("[同步锁] %s.%s duration %.1f > cooldown %.1f，已 clamp" % [skill_id, tag_id, dur, cd])

## 执行技能标签效果
func _execute_skill_tags(skill_id: String, player_id: int, target_data: Dictionary) -> void:
	var skill_data = _get_skill_data(skill_id)
	var tag_ids = skill_data.get("tags", [])

	print("[SpiritSkillTrigger] 执行技能标签: ", tag_ids)

	for tag_id in tag_ids:
		if not _tags_registry.has(tag_id):
			printerr("[SpiritSkillTrigger] 标签不存在: ", tag_id)
			continue

		var tag_data = _tags_registry[tag_id]

		# 构建标签参数
		var tag_params = _build_tag_params(tag_data, skill_data, player_id, target_data)

		# 调用效果处理器
		var result = _effect_handler.apply_tag_effect(tag_id, tag_params, player_id)

		# 发送UI反馈信号
		skill_effect_applied.emit(skill_id, tag_id, result)

		# 发送UI效果反馈
		_send_ui_feedback(tag_data, result)

## 构建标签参数
func _build_tag_params(tag_data: Dictionary, skill_data: Dictionary, player_id: int, target_data: Dictionary) -> Dictionary:
	var params: Dictionary = {}

	# 从技能的 tag_params 中读取该标签的参数
	var tag_id: String = tag_data.get("id", "")
	var all_tag_params: Dictionary = skill_data.get("tag_params", {})
	if all_tag_params.has(tag_id):
		params = all_tag_params[tag_id].duplicate()

	# 注入运行时上下文（标签函数可直接使用）
	params["_caster_id"] = player_id
	params["_skill_id"] = skill_data.get("id", "")
	params["_element"] = skill_data.get("element", "")
	params["_target_data"] = target_data

	return params

## 消耗能量（E3 接真：扣 player.spirit_energy；2026-09-17 起为全路径唯一扣费点）
## 费用 = (基础 + 标签附加) × 施法者消耗倍率（折扣/涨价卡挂在被施法者身上）
func _consume_energy(player_id: int, amount: int) -> bool:
	var p := _get_player_by_id(player_id)
	if p == null:
		return true  # 找不到球员时兼容旧路径（如 UI 预览调用）
	if amount <= 0:
		return true
	var cost: float = float(amount)
	if p.has_method("get_skill_cost_mult"):
		cost *= p.get_skill_cost_mult()
	if p.spirit_energy < cost:
		return false
	p.spirit_energy -= cost
	print("[SpiritSkillTrigger] 扣能量 %.1f → 剩余 %.0f" % [cost, p.spirit_energy])
	return true

## 按 instance_id 找球员节点
func _get_player_by_id(player_id: int) -> Node:
	for p in players:
		if p != null and is_instance_valid(p) and p.get_instance_id() == player_id:
			return p
	return null

## 设置技能冷却（2026-09-17 起为全路径唯一CD表；应用施法者CD倍率并记录初值）
func _set_skill_cooldown(player_id: int, skill_id: String, cooldown: float) -> void:
	var applied := cooldown
	var p := _get_player_by_id(player_id)
	if p and p.has_method("get_skill_cd_mult"):
		applied = cooldown * p.get_skill_cd_mult()
	if not _skill_cooldowns.has(player_id):
		_skill_cooldowns[player_id] = {}
	_skill_cooldowns[player_id][skill_id] = applied
	if not _skill_cd_totals.has(player_id):
		_skill_cd_totals[player_id] = {}
	_skill_cd_totals[player_id][skill_id] = applied

## 更新冷却时间（每帧调用）
func _process(delta: float) -> void:
	var bus = get_tree().get_first_node_in_group("battle_event_bus") if is_inside_tree() else null
	for player_id in _skill_cooldowns.keys():
		for skill_id in _skill_cooldowns[player_id].keys():
			var remaining = _skill_cooldowns[player_id][skill_id]
			if remaining > 0:
				_skill_cooldowns[player_id][skill_id] = max(0, remaining - delta)
				# E2/G 类事件：冷却结束
				if _skill_cooldowns[player_id][skill_id] == 0.0 and bus:
					bus.emit_event(BattleEventBus.GameEvent.RESOURCE_COOLDOWN_READY, {"player_id": player_id, "skill_id": skill_id})

## 获取技能剩余冷却时间
func get_skill_cooldown(player_id: int, skill_id: String) -> float:
	if _skill_cooldowns.has(player_id) and _skill_cooldowns[player_id].has(skill_id):
		return _skill_cooldowns[player_id][skill_id]
	return 0.0

## 获取技能冷却进度（0=可用，1=刚释放满冷却；按实际生效CD计算）
func get_skill_cooldown_ratio(player_id: int, skill_id: String) -> float:
	var remaining := get_skill_cooldown(player_id, skill_id)
	if remaining <= 0.0:
		return 0.0
	var total := 0.0
	if _skill_cd_totals.has(player_id) and _skill_cd_totals[player_id].has(skill_id):
		total = float(_skill_cd_totals[player_id][skill_id])
	if total <= 0.0:
		return 0.0
	return clampf(remaining / total, 0.0, 1.0)

## 增量注入单个技能（如天赋树 manual 解锁；避免全量重调导致被动重复订阅）
func add_player_skill(player_id: int, skill_id: String) -> void:
	if not _player_skills.has(player_id):
		_player_skills[player_id] = []
	if skill_id in _player_skills[player_id]:
		return
	_player_skills[player_id].append(skill_id)
	if not _skill_cooldowns.has(player_id):
		_skill_cooldowns[player_id] = {}
	_skill_cooldowns[player_id][skill_id] = 0.0
	var skills: Array[String] = [skill_id]
	_subscribe_passives(player_id, skills)

## 获取玩家上场技能列表
func get_player_skills(player_id: int) -> Array[String]:
	if _player_skills.has(player_id):
		return _player_skills[player_id]
	return []

## 检查标签是否存在
func has_tag(tag_id: String) -> bool:
	return _tags_registry.has(tag_id)

## 获取标签数据
func get_tag_data(tag_id: String) -> Dictionary:
	if _tags_registry.has(tag_id):
		return _tags_registry[tag_id]
	return {}

## 效果应用回调
func _on_effect_applied(tag_id: String, effect_data: Dictionary) -> void:
	print("[SpiritSkillTrigger] 效果已应用: ", tag_id)

## 效果结束回调
func _on_effect_finished(tag_id: String, effect_data: Dictionary) -> void:
	print("[SpiritSkillTrigger] 效果已结束: ", tag_id)

## 发送UI反馈
func _send_ui_feedback(tag_data: Dictionary, effect_result: Dictionary) -> void:
	var feedback_data = {
		"category": tag_data.get("category", ""),
		"sub_category": tag_data.get("sub_category", ""),
		"name": tag_data.get("name", ""),
		"target_type": tag_data.get("target_type", ""),
		"success": effect_result.get("success", false)
	}

	skill_ui_feedback.emit("effect_applied", feedback_data)
