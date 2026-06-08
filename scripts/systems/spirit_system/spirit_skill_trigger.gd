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

# 技能冷却状态
var _skill_cooldowns: Dictionary = {}  # {player_id: {skill_id: remaining_time}}

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

	# 检查能量消耗
	var energy_cost = skill_data.get("energy_cost", 0)
	if not _consume_energy(player_id, energy_cost):
		print("[SpiritSkillTrigger] 能量不足")
		return false

	# 发送技能触发信号
	skill_triggered.emit(skill_id, player_id, target_data)

	# 先重置球修饰符（清空上一次技能的残留）
	if _effect_handler:
		_effect_handler.reset_ball_mods()

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

## 获取技能数据
func _get_skill_data(skill_id: String) -> Dictionary:
	_load_skills_data()
	if _skills_cache.has(skill_id):
		return _skills_cache[skill_id]
	return {}

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

## 消耗能量
func _consume_energy(player_id: int, amount: int) -> bool:
	# TODO: 从玩家获取当前能量并扣除
	# 目前先返回true
	return true

## 设置技能冷却
func _set_skill_cooldown(player_id: int, skill_id: String, cooldown: float) -> void:
	if not _skill_cooldowns.has(player_id):
		_skill_cooldowns[player_id] = {}
	_skill_cooldowns[player_id][skill_id] = cooldown

## 更新冷却时间（每帧调用）
func _process(delta: float) -> void:
	for player_id in _skill_cooldowns.keys():
		for skill_id in _skill_cooldowns[player_id].keys():
			var remaining = _skill_cooldowns[player_id][skill_id]
			if remaining > 0:
				_skill_cooldowns[player_id][skill_id] = max(0, remaining - delta)

## 获取技能剩余冷却时间
func get_skill_cooldown(player_id: int, skill_id: String) -> float:
	if _skill_cooldowns.has(player_id) and _skill_cooldowns[player_id].has(skill_id):
		return _skill_cooldowns[player_id][skill_id]
	return 0.0

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
