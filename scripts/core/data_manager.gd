extends Node
## 数据管理器 - 从JSON加载游戏数据
## 挂载为Autoload单例，全局访问

var characters: Array[Dictionary] = []
var spirits: Array[Dictionary] = []
var skills: Array[Dictionary] = []
var elements: Dictionary = {}

signal data_loaded


func _ready() -> void:
	load_all_data()


func load_all_data() -> void:
	characters = _load_json_array("res://data/characters/characters.json")
	spirits = _load_spirits_array()
	skills = _load_spirits_skills()
	elements = _load_json_dict("res://data/spirits/elements.json")
	data_loaded.emit()
	print("[DataManager] 数据加载完成: %d 角色, %d 元灵, %d 技能" % [characters.size(), spirits.size(), skills.size()])


func _load_json_raw(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_warning("[DataManager] 文件不存在: %s" % path)
		return null
	
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[DataManager] 无法打开: %s" % path)
		return null
	
	var text := file.get_as_text()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("[DataManager] JSON解析错误 %s (行%d): %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	
	return json.data


func _load_json_array(path: String) -> Array[Dictionary]:
	var result = _load_json_raw(path)
	if result is Array:
		var typed_array: Array[Dictionary] = []
		for item in result:
			if item is Dictionary:
				typed_array.append(item)
		return typed_array
	return []


func _load_json_dict(path: String) -> Dictionary:
	var result = _load_json_raw(path)
	if result is Dictionary:
		return result
	return {}


func _load_spirits_skills() -> Array[Dictionary]:
	"""从 spirits/skills.json 加载技能（支持 {skills:[...]} 格式）"""
	var result = _load_json_raw("res://data/spirits/skills.json")
	if result is Dictionary and result.has("skills"):
		var typed_array: Array[Dictionary] = []
		for item in result["skills"]:
			if item is Dictionary:
				typed_array.append(item)
		return typed_array
	return []


func _load_spirits_array() -> Array[Dictionary]:
	"""从 spirits/spirits.json 加载元灵（支持 {spirits:[...]} 格式）"""
	var result = _load_json_raw("res://data/spirits/spirits.json")
	if result is Dictionary and result.has("spirits"):
		var typed_array: Array[Dictionary] = []
		for item in result["spirits"]:
			if item is Dictionary:
				typed_array.append(item)
		return typed_array
	return []


# ===== 查询方法 =====

func get_character_by_id(char_id: String) -> Dictionary:
	for c in characters:
		if c.get("id") == char_id:
			return c
	return {}


func get_spirit_by_id(spirit_id: String) -> Dictionary:
	for s in spirits:
		if s.get("id") == spirit_id:
			return s
	return {}


func get_skills_for_spirit(spirit_id: String) -> Array[Dictionary]:
	return skills.filter(func(s: Dictionary): return s.get("spirit_id") == spirit_id if s.has("spirit_id") else "")


func get_skill_by_id(skill_id: String) -> Dictionary:
	for s in skills:
		if s.get("id") == skill_id:
			return s
	return {}


func get_skills_by_tag(tag: String) -> Array[Dictionary]:
	return skills.filter(func(s: Dictionary): return s.get("tag") == tag if s.has("tag") else "")


func get_counter_multiplier(attacker_element: String, defender_element: String) -> float:
	if elements.is_empty():
		return 1.0
	for counter in elements.get("counters") if elements.has("counters") else []:
		if counter.get("attacker") == attacker_element and counter.get("defender") == defender_element:
			return elements.get("counter_multiplier") if elements.has("counter_multiplier") else 1.3
	return 1.0
