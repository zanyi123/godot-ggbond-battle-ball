class_name DevDataSync
extends RefCounted
## 开发者工具 - 数据同步器
## 负责读写JSON数据、生成ID、同步所有系统
## 全部使用 static 方法，无需实例化

const CHARACTERS_PATH := "res://data/characters/characters.json"
const SPIRITS_PATH := "res://data/spirits/spirits.json"
const SKILLS_PATH := "res://data/spirits/skills.json"
const TAGS_PATH := "res://data/spirits/tags_registry.json"
const ITEMS_PATH := "res://data/items/items.json"
const ITEM_ICONS_DIR := "res://assets/icons/items"

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
		"ball_speed": 400.0,
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
		"icon_path": "",
		"tags": [],
		"tag_params": {}
	}

const ICONS_DIR := "res://data/spirits/icons"

## 复制上传的图标到项目目录，返回存储路径（失败返回空字符串）
static func save_icon(source_path: String, skill_id: String) -> String:
	if source_path.strip_edges() == "":
		return ""
	if not FileAccess.file_exists(source_path):
		printerr("[DevDataSync] 图标源文件不存在: %s" % source_path)
		return ""
	# 确保目录存在
	DirAccess.make_dir_recursive_absolute(ICONS_DIR)
	var ext := source_path.get_extension().to_lower()
	if ext not in ["png", "jpg", "jpeg", "webp"]:
		ext = "png"
	var dest_path := "%s/%s.%s" % [ICONS_DIR, skill_id, ext]
	var err := DirAccess.copy_absolute(source_path, dest_path)
	if err != OK:
		printerr("[DevDataSync] 图标复制失败: %s → %s (err=%d)" % [source_path, dest_path, err])
		return ""
	print("[DevDataSync] 图标已保存: %s" % dest_path)
	return dest_path

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

## 读取道具数据（装备+食物）
static func load_items() -> Array:
	var file := FileAccess.open(ITEMS_PATH, FileAccess.READ)
	if file:
		var json := JSON.new()
		var err := json.parse(file.get_as_text())
		file.close()
		if err == OK:
			return json.data.get("items", []) if json.data is Dictionary else []
	return []

## 保存道具数据
static func save_items(data: Array) -> bool:
	var file := FileAccess.open(ITEMS_PATH, FileAccess.READ)
	var version := 1
	if file:
		var json := JSON.new()
		var err := json.parse(file.get_as_text())
		file.close()
		if err == OK and json.data is Dictionary:
			version = json.data.get("version", 1)
	var wrapper := {"version": version, "items": data}
	var wfile := FileAccess.open(ITEMS_PATH, FileAccess.WRITE)
	if wfile:
		wfile.store_string(JSON.stringify(wrapper, "\t"))
		wfile.close()
		print("[DevSync] 道具数据已保存, 共 ", data.size(), " 个道具")
		return true
	printerr("[DevSync] 无法保存道具数据")
	return false

## 生成装备ID
static func generate_equipment_id(existing: Array, sub_type: String) -> String:
	var type_map: Dictionary = {
		"glove": "eq_glove",
		"jersey": "eq_jersey",
		"shoes": "eq_shoes",
	}
	var prefix: String = type_map.get(sub_type, "eq_unk")
	var max_num := 0
	for item in existing:
		var id_str: String = str(item.get("id", ""))
		if id_str.begins_with(prefix + "_"):
			var rest := id_str.substr(prefix.length() + 1)
			var parts := rest.split("_")
			if parts.size() > 0:
				var num_str := parts[parts.size() - 1]
				var num := num_str.to_int()
				if num > max_num:
					max_num = num
	return "%s_%02d" % [prefix, max_num + 1]

## 生成食物ID
static func generate_food_id(existing: Array) -> String:
	var max_num := 0
	for item in existing:
		var id_str: String = str(item.get("id", ""))
		if id_str.begins_with("food_"):
			var rest := id_str.substr(5)
			var under_idx: int = rest.rfind("_")
			if under_idx >= 0:
				var num_part := rest.substr(0, under_idx)
				var num := 0
				var valid := true
				for i in range(num_part.length()):
					var c: String = num_part.substr(i, 1)
					if c >= "0" and c <= "9":
						num = num * 10 + c.to_int()
					else:
						valid = false
						break
				if valid and num > max_num:
					max_num = num
	if max_num == 0:
		max_num = 100
	return "food_%d_new" % (max_num + 1)

## 创建装备模板
static func create_equipment_template(id: String, sub_type: String) -> Dictionary:
	var type_name_map: Dictionary = {
		"glove": "新手套",
		"jersey": "新球衣",
		"shoes": "新球鞋",
	}
	return {
		"id": id,
		"name": type_name_map.get(sub_type, "新装备"),
		"type": "equipment",
		"sub_type": sub_type,
		"rarity": "common",
		"icon": "res://assets/icons/items/equipment/" + sub_type + "_common.png",
		"description": "新建装备",
		"stack_max": 1,
		"sell_price": 100,
		"stats": {
			"attack_bonus": 0,
			"defense_bonus": 0,
			"speed_bonus": 0,
			"stamina_bonus": 0,
			"resilience_bonus": 0,
			"ball_speed_bonus": 0
		}
	}

## 创建食物模板
static func create_food_template(id: String) -> Dictionary:
	return {
		"id": id,
		"name": "新食物",
		"type": "consumable",
		"sub_type": "food",
		"rarity": "common",
		"icon": "res://assets/icons/items/food/food_common.png",
		"description": "新建食物",
		"stack_max": 99,
		"sell_price": 10,
		"effect": {
			"effect_type": "stat_buff",
			"attack_pct": 0,
			"defense_pct": 0,
			"speed_pct": 0,
			"stamina_max_pct": 0,
			"resilience_pct": 0,
			"stamina_restore": 0,
			"duration": 300
		}
	}

## 稀有度列表
static func get_rarities() -> PackedStringArray:
	return ["common", "good", "rare", "epic", "legendary"]

## 稀有度中文名
static func get_rarity_name(rarity: String) -> String:
	var names: Dictionary = {
		"common": "普通",
		"good": "良好",
		"rare": "稀有",
		"epic": "史诗",
		"legendary": "传说",
	}
	return names.get(rarity, rarity)

## 稀有度颜色
static func get_rarity_color(rarity: String) -> Color:
	var colors: Dictionary = {
		"common": Color(0.8, 0.8, 0.8),
		"good": Color(0.3, 0.9, 0.3),
		"rare": Color(0.3, 0.6, 1.0),
		"epic": Color(0.8, 0.4, 1.0),
		"legendary": Color(1.0, 0.8, 0.2),
	}
	return colors.get(rarity, Color.WHITE)

## 装备部位列表
static func get_equipment_subtypes() -> PackedStringArray:
	return ["glove", "jersey", "shoes"]

## 装备部位中文名
static func get_subtype_name(sub_type: String) -> String:
	var names: Dictionary = {
		"glove": "手套",
		"jersey": "球衣",
		"shoes": "球鞋",
		"food": "食物",
	}
	return names.get(sub_type, sub_type)

## 保存道具图标
static func save_item_icon(source_path: String, item_id: String, item_type: String) -> String:
	if source_path.strip_edges() == "":
		return ""
	if not FileAccess.file_exists(source_path):
		printerr("[DevDataSync] 道具图标源文件不存在: %s" % source_path)
		return ""
	var sub_dir := "equipment" if item_type == "equipment" else "food"
	var dir_path := ITEM_ICONS_DIR + "/" + sub_dir
	DirAccess.make_dir_recursive_absolute(dir_path)
	var ext := source_path.get_extension().to_lower()
	if ext not in ["png", "jpg", "jpeg", "webp"]:
		ext = "png"
	var dest_path := "%s/%s.%s" % [dir_path, item_id, ext]
	var err := DirAccess.copy_absolute(source_path, dest_path)
	if err != OK:
		printerr("[DevDataSync] 道具图标复制失败: %s → %s (err=%d)" % [source_path, dest_path, err])
		return ""
	print("[DevDataSync] 道具图标已保存: %s" % dest_path)
	return dest_path
