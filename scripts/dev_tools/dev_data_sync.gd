class_name DevDataSync
extends RefCounted
## 开发者工具 - 数据同步器
## 负责读写JSON数据、生成ID、同步所有系统
## 全部使用 static 方法，无需实例化

const CHARACTERS_PATH := "res://data/characters/characters.json"
const SPIRITS_PATH := "res://data/spirits/spirits.json"
const SKILLS_PATH := "res://data/spirits/skills.json"
const TAGS_PATH := "res://data/spirits/tags_registry.json"

## 读取角色数据
static func load_characters() -> Array:
	var file := FileAccess.open(CHARACTERS_PATH, FileAccess.READ)
	if file:
		var json := JSON.new()
		var err := json.parse(file.get_as_text())
		file.close()
		if err == OK:
			return json.data if json.data is Array else []
	return []

## 保存角色数据
static func save_characters(data: Array) -> bool:
	var file := FileAccess.open(CHARACTERS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		print("[DevSync] 角色数据已保存, 共 ", data.size(), " 个角色")
		return true
	printerr("[DevSync] 无法保存角色数据")
	return false

## 读取元灵数据
static func load_spirits() -> Array:
	var file := FileAccess.open(SPIRITS_PATH, FileAccess.READ)
	if file:
		var json := JSON.new()
		var err := json.parse(file.get_as_text())
		file.close()
		if err == OK:
			return json.data.get("spirits", []) if json.data is Dictionary else []
	return []

## 保存元灵数据
static func save_spirits(data: Array) -> bool:
	var wrapper := {"spirits": data}
	var file := FileAccess.open(SPIRITS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(wrapper, "\t"))
		file.close()
		print("[DevSync] 元灵数据已保存, 共 ", data.size(), " 个元灵")
		return true
	printerr("[DevSync] 无法保存元灵数据")
	return false

## 读取技能数据
static func load_skills() -> Array:
	var file := FileAccess.open(SKILLS_PATH, FileAccess.READ)
	if file:
		var json := JSON.new()
		var err := json.parse(file.get_as_text())
		file.close()
		if err == OK:
			return json.data.get("skills", []) if json.data is Dictionary else []
	return []

## 保存技能数据
static func save_skills(data: Array) -> bool:
	var wrapper := {"skills": data}
	var file := FileAccess.open(SKILLS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(wrapper, "\t"))
		file.close()
		print("[DevSync] 技能数据已保存, 共 ", data.size(), " 个技能")
		return true
	printerr("[DevSync] 无法保存技能数据")
	return false

## 读取标签注册表
static func load_tags() -> Array:
	var file := FileAccess.open(TAGS_PATH, FileAccess.READ)
	if file:
		var json := JSON.new()
		var err := json.parse(file.get_as_text())
		file.close()
		if err == OK:
			return json.data.get("tags", []) if json.data is Dictionary else []
	return []

## 生成新角色ID
static func generate_char_id(existing: Array) -> String:
	var max_num := 0
	for c in existing:
		var id_str: String = str(c.get("id", ""))
		if id_str.begins_with("char_"):
			var num := id_str.substr(5).to_int()
			if num > max_num:
				max_num = num
	return "char_%03d" % (max_num + 1)

## 生成新元灵ID
static func generate_spirit_id(existing: Array) -> String:
	var ids: PackedStringArray = []
	for s in existing:
		ids.append(str(s.get("id", "")))
	var idx := 1
	while true:
		var candidate := "spirit_%d" % idx
		if not candidate in ids:
			return candidate
		idx += 1
	return "spirit_new"

## 生成新技能ID
static func generate_skill_id(existing: Array, prefix: String) -> String:
	var ids: PackedStringArray = []
	for s in existing:
		ids.append(str(s.get("id", "")))
	var idx := 1
	while true:
		var candidate := "skill_%s_%d" % [prefix, idx]
		if not candidate in ids:
			return candidate
		idx += 1
	return "skill_new_1"

## 创建新角色模板
static func create_character_template(id: String) -> Dictionary:
	return {
		"id": id,
		"name": "新球员",
		"stamina": 70,
		"defense": 60,
		"speed": 70,
		"attack": 35,
		"resilience": 50,
		"defense_factor": 0.15,
		"talent_name": "未命名天赋",
		"talent_desc": "天赋效果描述",
		"spirit_preference": "金刚",
		"ultimate_skill": "未命名大招",
		"description": "新建球员"
	}

## 创建新元灵模板
static func create_spirit_template(id: String) -> Dictionary:
	return {
		"id": id,
		"name": "新元灵",
		"element": "金刚",
		"level": 1,
		"max_level": 10,
		"description": "新建元灵",
		"icon_color": "#FFD700",
		"skills": []
	}

## 创建新技能模板
static func create_skill_template(id: String, element: String) -> Dictionary:
	return {
		"id": id,
		"name": "新技能",
		"element": element,
		"type": "active",
		"unlock_level": 1,
		"unlock_cost": 0,
		"energy_cost": 20,
		"cooldown": 10.0,
		"description": "新建技能",
		"detail": "技能详细说明",
		"icon_color": "#FFFFFF",
		"tags": [],
		"tag_params": {}
	}

## 元素列表
static func get_elements() -> PackedStringArray:
	return ["金刚", "大地", "雷火", "冰雪", "草木", "梦幻"]

## 元素颜色映射
static func get_element_color(element: String) -> Color:
	var colors: Dictionary = {
		"金刚": Color(0.85, 0.75, 0.3),
		"大地": Color(0.7, 0.55, 0.35),
		"雷火": Color(1.0, 0.4, 0.2),
		"冰雪": Color(0.4, 0.8, 1.0),
		"草木": Color(0.3, 0.8, 0.3),
		"梦幻": Color(0.7, 0.5, 0.9),
	}
	return colors.get(element, Color.GRAY)
