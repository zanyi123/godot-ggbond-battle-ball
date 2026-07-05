extends Node
## 训练场地系统管理器 - Autoload 单例
## 负责：训练逻辑、场地升级、成长曲线、属性上限检查

const GROWTH_CURVES_PATH := "res://data/characters/growth_curves.json"

const BASE_TRAIN_COST := 100
const BASE_FIELD_UPGRADE_COST := 500
const FIELD_UPGRADE_MULTIPLIER := 1.5
const MAX_FIELD_LEVEL := 10
const TRAIN_BONUS_PER_TIME := 2

var _growth_curves: Dictionary = {}

signal training_changed(char_id: String)
signal field_level_changed(level: int)


func _ready() -> void:
	_load_growth_curves()


func _load_growth_curves() -> void:
	if not FileAccess.file_exists(GROWTH_CURVES_PATH):
		_generate_default_growth_curves()
		return
	
	var file := FileAccess.open(GROWTH_CURVES_PATH, FileAccess.READ)
	if file == null:
		push_error("[TrainingManager] 无法打开成长曲线文件")
		_generate_default_growth_curves()
		return
	
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	
	if err != OK or not json.data is Dictionary:
		push_error("[TrainingManager] 成长曲线解析失败")
		_generate_default_growth_curves()
		return
	
	_growth_curves = json.data.get("growth_curves", {})
	print("[TrainingManager] 加载成长曲线: %d 个球员" % _growth_curves.size())


func _generate_default_growth_curves() -> void:
	var curves: Dictionary = {}
	var chars: Array = DataManager.characters
	
	## 默认每级固定增量（非百分比）
	var increment := {
		"stamina": 10,
		"defense": 8,
		"speed": 8,
		"attack": 5,
		"resilience": 6,
		"ball_speed": 30,
	}
	
	for char in chars:
		var cid: String = char.get("id", "")
		var cname: String = char.get("name", "")
		if cid == "":
			continue
		
		var base_stats := {
			"stamina": float(char.get("stamina", 80)),
			"defense": float(char.get("defense", 60)),
			"speed": float(char.get("speed", 70)),
			"attack": float(char.get("attack", 40)),
			"resilience": float(char.get("resilience", 50)),
			"ball_speed": float(char.get("ball_speed", 400))
		}
		
		var char_curve: Dictionary = {
			"name": cname
		}
		
		for level in range(1, MAX_FIELD_LEVEL + 1):
			# Lv.N 上限 = 基础值 + N * 每级固定增量
			char_curve["field_level_%d" % level] = {
				"stamina_max": int(round(base_stats["stamina"] + level * increment["stamina"])),
				"defense_max": int(round(base_stats["defense"] + level * increment["defense"])),
				"speed_max": int(round(base_stats["speed"] + level * increment["speed"])),
				"attack_max": int(round(base_stats["attack"] + level * increment["attack"])),
				"resilience_max": int(round(base_stats["resilience"] + level * increment["resilience"])),
				"ball_speed_max": int(round(base_stats["ball_speed"] + level * increment["ball_speed"]))
			}
		
		curves[cid] = char_curve
	
	_growth_curves = curves
	_save_growth_curves()


func _save_growth_curves() -> void:
	DirAccess.make_dir_absolute("res://data/characters")
	
	var file := FileAccess.open(GROWTH_CURVES_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[TrainingManager] 无法保存成长曲线")
		return
	
	var data := {"growth_curves": _growth_curves}
	file.store_string(JSON.stringify(data, "	"))
	file.close()


func get_field_level() -> int:
	return PlayerSaveManager.get_field_level()


func get_train_cost() -> int:
	return BASE_TRAIN_COST


func get_field_upgrade_cost(level: int) -> int:
	if level < 1 or level >= MAX_FIELD_LEVEL:
		return -1
	var cost: float = BASE_FIELD_UPGRADE_COST
	for i in range(level - 1):
		cost *= FIELD_UPGRADE_MULTIPLIER
	return int(round(cost))


func get_stat_max(char_id: String, stat_key: String) -> float:
	var field_level: int = get_field_level()
	var curve: Dictionary = _growth_curves.get(char_id, {})
	var level_key: String = "field_level_%d" % field_level
	
	if curve.has(level_key):
		var level_data: Dictionary = curve[level_key]
		return float(level_data.get(stat_key + "_max", 0))
	
	var char_data: Dictionary = DataManager.get_character_by_id(char_id)
	if char_data.has(stat_key):
		return float(char_data[stat_key])
	
	return 0


func can_train(char_id: String, stat_key: String) -> bool:
	var current_bonus: int = get_current_bonus(char_id, stat_key)
	var stat_max: float = get_stat_max(char_id, stat_key)
	var char_data: Dictionary = DataManager.get_character_by_id(char_id)
	var base_value: float = float(char_data.get(stat_key, 0))
	
	return (base_value + float(current_bonus)) < stat_max


func get_current_bonus(char_id: String, stat_key: String) -> int:
	var train: Dictionary = PlayerSaveManager.get_character_train(char_id)
	return int(train.get(stat_key + "_bonus", 0))


func train_stat(char_id: String, stat_key: String) -> bool:
	if not can_train(char_id, stat_key):
		return false
	
	var cost: int = get_train_cost()
	var fairy_coin: int = PlayerSaveManager.get_currency("fairy_coin")
	if fairy_coin < cost:
		return false
	
	PlayerSaveManager.add_currency("fairy_coin", -cost)
	
	var current: int = get_current_bonus(char_id, stat_key)
	var new_value: int = current + TRAIN_BONUS_PER_TIME
	PlayerSaveManager.set_training_bonus(char_id, stat_key + "_bonus", new_value)
	
	training_changed.emit(char_id)
	return true


func upgrade_field() -> bool:
	var current_level: int = get_field_level()
	if current_level >= MAX_FIELD_LEVEL:
		return false
	
	var cost: int = get_field_upgrade_cost(current_level)
	var fairy_coin: int = PlayerSaveManager.get_currency("fairy_coin")
	if fairy_coin < cost:
		return false
	
	PlayerSaveManager.add_currency("fairy_coin", -cost)
	PlayerSaveManager.set_field_level(current_level + 1)
	
	field_level_changed.emit(current_level + 1)
	return true


func get_all_growth_curves() -> Dictionary:
	return _growth_curves.duplicate()


func set_growth_curves(curves: Dictionary) -> void:
	_growth_curves = curves
	_save_growth_curves()


func get_curve_for_char(char_id: String) -> Dictionary:
	return _growth_curves.get(char_id, {}).duplicate()


func update_curve_for_char(char_id: String, level: int, stats: Dictionary) -> void:
	if not _growth_curves.has(char_id):
		_growth_curves[char_id] = {"name": ""}
	
	var level_key: String = "field_level_%d" % level
	var level_data: Dictionary = _growth_curves[char_id].get(level_key, {})
	
	for stat_key in stats:
		level_data[stat_key] = stats[stat_key]
	
	_growth_curves[char_id][level_key] = level_data
	_save_growth_curves()
