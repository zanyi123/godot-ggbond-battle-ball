extends Node
## 玩家存档管理器 - 本地持久化存储
## 挂载为Autoload单例，全局访问
## 支持3个存档位、版本迁移、坏档备份、自动保存

const SAVE_VERSION := 2

## 装备耐久消耗常量
const DURABILITY_LOSS_PER_HIT := 0.1
const DURABILITY_LOSS_PER_CATCH := 0.1

## 稀有度对应的耐久衰减阈值（低于此值属性减半）
const RARITY_DURABILITY_THRESHOLD := {
	"common": 30,
	"good": 40,
	"rare": 50,
	"epic": 60,
	"legendary": 75
}

## 稀有度对应的最大耐久
const RARITY_MAX_DURABILITY := {
	"common": 50,
	"good": 80,
	"rare": 100,
	"epic": 120,
	"legendary": 150
}
const SAVE_DIR := "user://saves/"
const SAVE_FILE_PREFIX := "save_"
const SAVE_FILE_SUFFIX := ".json"

var current_slot: int = 1
var save_data: Dictionary = {}

signal save_loaded(slot: int)
signal save_saved(slot: int)
signal currency_changed


func _ready() -> void:
	_ensure_save_dir()
	load_slot(current_slot)


func _ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_absolute(SAVE_DIR)


func _get_save_path(slot: int) -> String:
	return SAVE_DIR + SAVE_FILE_PREFIX + str(slot) + SAVE_FILE_SUFFIX


func _get_backup_path(slot: int) -> String:
	return SAVE_DIR + SAVE_FILE_PREFIX + str(slot) + "_corrupted_backup.json"


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(_get_save_path(slot))


func load_slot(slot: int) -> void:
	current_slot = slot
	var path := _get_save_path(slot)
	
	if not FileAccess.file_exists(path):
		save_data = _create_default_save()
		_save_to_file()
		save_loaded.emit(slot)
		return
	
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[PlayerSaveManager] 无法打开存档: %s" % path)
		_backup_corrupted(slot, "")
		save_data = _create_default_save()
		_save_to_file()
		save_loaded.emit(slot)
		return
	
	var text := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK or not (json.data is Dictionary):
		push_error("[PlayerSaveManager] 存档%d解析失败，备份后重置" % slot)
		_backup_corrupted(slot, text)
		save_data = _create_default_save()
		_save_to_file()
		save_loaded.emit(slot)
		return
	
	var data: Dictionary = json.data
	var version: int = data.get("version", 0)
	if version < SAVE_VERSION:
		data = _migrate_save(data, version)
	
	save_data = data
	save_loaded.emit(slot)
	print("[PlayerSaveManager] 存档%d加载完成，版本%d" % [slot, save_data.get("version", 0)])


func save_slot() -> void:
	_save_to_file()
	save_saved.emit(current_slot)


func _save_to_file() -> void:
	var path := _get_save_path(current_slot)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[PlayerSaveManager] 无法写入存档: %s" % path)
		return
	
	save_data["last_save_time"] = Time.get_datetime_string_from_system()
	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()


func _backup_corrupted(slot: int, text: String) -> void:
	var backup_path := _get_backup_path(slot)
	var file := FileAccess.open(backup_path, FileAccess.WRITE)
	if file:
		file.store_string(text)
		file.close()
		print("[PlayerSaveManager] 坏档已备份到: %s" % backup_path)


func _create_default_save() -> Dictionary:
	var character_trains: Dictionary = {}
	for c in DataManager.characters:
		var char_id: String = c.get("id", "")
		if char_id == "":
			continue
		character_trains[char_id] = {
			"stamina_bonus": 0,
			"defense_bonus": 0,
			"speed_bonus": 0,
			"attack_bonus": 0,
			"resilience_bonus": 0,
			"ball_speed_bonus": 0
		}
	
	var unlocked: Array[String] = []
	unlocked.append("char_004")
	unlocked.append("char_006")
	unlocked.append("char_007")
	
	return {
		"version": SAVE_VERSION,
		"create_time": Time.get_datetime_string_from_system(),
		"last_save_time": Time.get_datetime_string_from_system(),
		"player_id": "",
		"player_name": "小虎队",
		"is_dev_mode": true,
		"currencies": {
			"fairy_coin": 1000,
			"spirit_ore": 50,
			"crystal": 20
		},
		"training": {
			"field_level": 1,
			"character_trains": character_trains
		},
		"equipment": {
			"equipped": {},
			"inventory": []
		},
		"inventory": {
			"items": [],
			"max_slots": 50
		},
		"nutrition": {
			"pre_match_food": []
		},
		"unlocked_characters": unlocked
	}


func _migrate_save(data: Dictionary, from_version: int) -> Dictionary:
	var result: Dictionary = data.duplicate(true)
	
	if from_version < 1:
		if not result.has("player_id"):
			result["player_id"] = ""
		if not result.has("is_dev_mode"):
			result["is_dev_mode"] = true
		if not result.has("nutrition"):
			result["nutrition"] = {"pre_match_food": []}
		if not result.has("equipment"):
			result["equipment"] = {"equipped": {}, "inventory": []}
	
	# v2: 装备耐久系统 - 旧格式 {slot: "item_id"} 迁移为新格式 {slot: {"item_id":"xxx", "durability": max}}
	if from_version < 2:
		var equipment: Dictionary = result.get("equipment", {})
		var equipped: Dictionary = equipment.get("equipped", {})
		for char_id in equipped.keys():
			var char_eq: Dictionary = equipped[char_id]
			for slot in EQUIP_SLOTS:
				var val = char_eq.get(slot, "")
				if val is String and val != "":
					var def: Dictionary = InventoryManager.get_item_def(val)
					var rarity: String = def.get("rarity", "common")
					var max_dur: int = RARITY_MAX_DURABILITY.get(rarity, 50)
					char_eq[slot] = {"item_id": val, "durability": float(max_dur)}
				elif val is String and val == "":
					char_eq[slot] = {"item_id": "", "durability": 0}
			equipped[char_id] = char_eq
		equipment["equipped"] = equipped
		result["equipment"] = equipment
	
	result["version"] = SAVE_VERSION
	print("[PlayerSaveManager] 存档迁移: v%d -> v%d" % [from_version, SAVE_VERSION])
	return result


func is_dev_mode() -> bool:
	return save_data.get("is_dev_mode", false)


func get_currency(currency_type: String) -> int:
	var currencies: Dictionary = save_data.get("currencies", {})
	return currencies.get(currency_type, 0)


func set_currency(currency_type: String, amount: int) -> void:
	var currencies: Dictionary = save_data.get("currencies", {})
	currencies[currency_type] = max(0, amount)
	save_data["currencies"] = currencies
	currency_changed.emit()
	save_slot()


func add_currency(currency_type: String, amount: int) -> bool:
	if amount <= 0:
		return false
	var currencies: Dictionary = save_data.get("currencies", {})
	var current: int = currencies.get(currency_type, 0)
	currencies[currency_type] = current + amount
	save_data["currencies"] = currencies
	currency_changed.emit()
	save_slot()
	return true


func spend_currency(currency_type: String, amount: int) -> bool:
	if amount <= 0:
		return false
	var currencies: Dictionary = save_data.get("currencies", {})
	var current: int = currencies.get(currency_type, 0)
	if current < amount:
		return false
	currencies[currency_type] = current - amount
	save_data["currencies"] = currencies
	currency_changed.emit()
	save_slot()
	return true


func has_character(char_id: String) -> bool:
	var unlocked: Array = save_data.get("unlocked_characters", [])
	if is_dev_mode():
		return true
	return unlocked.has(char_id)


func unlock_character(char_id: String) -> bool:
	var unlocked: Array = save_data.get("unlocked_characters", [])
	if unlocked.has(char_id):
		return false
	unlocked.append(char_id)
	save_data["unlocked_characters"] = unlocked
	save_slot()
	return true


func get_unlocked_characters() -> Array[String]:
	if is_dev_mode():
		var all: Array[String] = []
		for c in DataManager.characters:
			all.append(c.get("id", ""))
		return all
	var result: Array[String] = []
	for id in save_data.get("unlocked_characters", []):
		result.append(id)
	return result


func get_field_level() -> int:
	var training: Dictionary = save_data.get("training", {})
	return training.get("field_level", 1)


func set_field_level(level: int) -> void:
	var training: Dictionary = save_data.get("training", {})
	training["field_level"] = level
	save_data["training"] = training
	save_slot()


func get_character_train(char_id: String) -> Dictionary:
	var training: Dictionary = save_data.get("training", {})
	var char_trains: Dictionary = training.get("character_trains", {})
	if char_trains.has(char_id):
		return char_trains[char_id]
	var default_train := {
		"stamina_bonus": 0,
		"defense_bonus": 0,
		"speed_bonus": 0,
		"attack_bonus": 0,
		"resilience_bonus": 0,
		"ball_speed_bonus": 0
	}
	char_trains[char_id] = default_train
	training["character_trains"] = char_trains
	save_data["training"] = training
	return default_train


func set_character_train(char_id: String, train_data: Dictionary) -> void:
	var training: Dictionary = save_data.get("training", {})
	var char_trains: Dictionary = training.get("character_trains", {})
	char_trains[char_id] = train_data
	training["character_trains"] = char_trains
	save_data["training"] = training
	save_slot()


func set_training_bonus(char_id: String, bonus_key: String, value: int) -> void:
	var train: Dictionary = get_character_train(char_id)
	train[bonus_key] = max(0, value)
	set_character_train(char_id, train)


func get_data() -> Dictionary:
	return save_data


## ==================== 营养系统 ====================

## 设置当前已吃的赛前食物（空字符串=清除）
func set_active_food(food_id: String) -> void:
	if not save_data.has("nutrition"):
		save_data["nutrition"] = {"pre_match_food": ""}
	save_data["nutrition"]["pre_match_food"] = food_id
	_save_to_file()


## 获取当前已吃的赛前食物ID
func get_active_food() -> String:
	var nutrition: Dictionary = save_data.get("nutrition", {})
	var food = nutrition.get("pre_match_food", "")
	if food is Array:
		# 兼容旧数组格式
		if food.size() > 0:
			return String(food[0])
		return ""
	return String(food)


func get_total_stat(char_id: String, stat_key: String) -> int:
	var char_data: Dictionary = DataManager.get_character_by_id(char_id)
	if char_data.is_empty():
		return 0
	var base: int = char_data.get(stat_key, 0)
	var train: Dictionary = get_character_train(char_id)
	var bonus: int = train.get(stat_key + "_bonus", 0)
	return base + bonus


## ==================== 装备穿戴系统 ====================

const EQUIP_SLOTS := ["glove", "jersey", "shoes"]


## 获取某角色的全部已穿戴装备 {slot: {"item_id":"xxx", "durability": float}}
func get_equipped(char_id: String) -> Dictionary:
	var equipment: Dictionary = save_data.get("equipment", {})
	var equipped: Dictionary = equipment.get("equipped", {})
	if not equipped.has(char_id):
		var empty_eq := {}
		for slot in EQUIP_SLOTS:
			empty_eq[slot] = {"item_id": "", "durability": 0}
		equipped[char_id] = empty_eq
		equipment["equipped"] = equipped
		save_data["equipment"] = equipment
	return equipped.get(char_id, {})


## 获取某角色某槽位的装备ID（空字符串=未穿戴）
func get_equipped_item(char_id: String, slot: String) -> String:
	var eq: Dictionary = get_equipped(char_id)
	var slot_data = eq.get(slot, {"item_id": ""})
	if slot_data is String:
		return slot_data
	return slot_data.get("item_id", "")


## 获取某角色某槽位装备的耐久值
func get_equipped_durability(char_id: String, slot: String) -> float:
	var eq: Dictionary = get_equipped(char_id)
	var slot_data = eq.get(slot, {})
	if slot_data is Dictionary:
		return slot_data.get("durability", 0.0)
	return 0.0


## 开发者工具：直接设置某角色某槽位的装备耐久
func set_equipped_durability(char_id: String, slot: String, new_dur: float) -> void:
	var equipment: Dictionary = save_data.get("equipment", {})
	var equipped: Dictionary = equipment.get("equipped", {})
	if not equipped.has(char_id):
		return
	var char_eq: Dictionary = equipped[char_id]
	var slot_data = char_eq.get(slot, {})
	if slot_data is Dictionary:
		slot_data["durability"] = clamp(new_dur, 0.0, 9999.0)
		char_eq[slot] = slot_data
		equipped[char_id] = char_eq
		equipment["equipped"] = equipped
		save_data["equipment"] = equipment
		save_slot()


## 修复某角色全部装备耐久为最大值（开发者工具用）
func repair_all_equipment_max(char_id: String) -> void:
	var eq: Dictionary = get_equipped(char_id)
	for slot in EQUIP_SLOTS:
		var slot_data = eq.get(slot, {})
		if slot_data is Dictionary:
			var item_id: String = slot_data.get("item_id", "")
			if item_id != "":
				var def: Dictionary = InventoryManager.get_item_def(item_id)
				var rarity: String = def.get("rarity", "common")
				var max_dur: int = RARITY_MAX_DURABILITY.get(rarity, 50)
				slot_data["durability"] = float(max_dur)
				eq[slot] = slot_data
	save_data["equipment"]["equipped"][char_id] = eq
	save_slot()


func get_backpack_item_durability(item_id: String) -> float:
	var inv: Dictionary = save_data.get("inventory", {})
	var items: Array = inv.get("items", [])
	for entry in items:
		if entry.get("item_id", "") == item_id:
			return float(entry.get("durability", 0))
	return 0.0


func get_all_equipped() -> Dictionary:
	var equipment: Dictionary = save_data.get("equipment", {})
	return equipment.get("equipped", {}).duplicate(true)


## 清空所有已穿戴装备（开发者清空物资用）
func clear_all_equipment() -> void:
	var equipment: Dictionary = save_data.get("equipment", {})
	var equipped: Dictionary = equipment.get("equipped", {})
	for char_id in equipped.keys():
		var empty_eq := {}
		for s in EQUIP_SLOTS:
			empty_eq[s] = {"item_id": "", "durability": 0}
		equipped[char_id] = empty_eq
	equipment["equipped"] = equipped
	save_data["equipment"] = equipment
	save_slot()


## 穿戴装备：只更新存档里的装备记录，不操作背包
## 返回被替换下来的旧装备ID（空字符串=原本没穿）
## initial_durability >= 0 时使用指定耐久值，否则使用最大值
func equip_item(char_id: String, slot: String, item_id: String, initial_durability: float = -1.0) -> String:
	var equipment: Dictionary = save_data.get("equipment", {})
	var equipped: Dictionary = equipment.get("equipped", {})
	if not equipped.has(char_id):
		var empty_eq := {}
		for s in EQUIP_SLOTS:
			empty_eq[s] = {"item_id": "", "durability": 0}
		equipped[char_id] = empty_eq
	var char_eq: Dictionary = equipped[char_id]
	var old_slot = char_eq.get(slot, {"item_id": ""})
	var old_id: String = ""
	if old_slot is String:
		old_id = old_slot
	elif old_slot is Dictionary:
		old_id = old_slot.get("item_id", "")
	# 新装备耐久
	var dur: float = 0.0
	if item_id != "":
		if initial_durability >= 0:
			dur = initial_durability
		else:
			var def: Dictionary = InventoryManager.get_item_def(item_id)
			var rarity: String = def.get("rarity", "common")
			dur = float(RARITY_MAX_DURABILITY.get(rarity, 50))
	char_eq[slot] = {"item_id": item_id, "durability": dur}
	equipped[char_id] = char_eq
	equipment["equipped"] = equipped
	save_data["equipment"] = equipment
	save_slot()
	return old_id


## 卸下装备：清空槽位，返回被卸下的装备ID
func unequip_item(char_id: String, slot: String) -> String:
	return equip_item(char_id, slot, "")


## 消耗装备耐久（接球/被击中时调用）
## reason: "catch" 或 "hit"
func reduce_equipment_durability(char_id: String, reason: String) -> void:
	print("[PlayerSaveManager] reduce_equipment_durability 被调用: char=%s reason=%s" % [char_id, reason])
	var equipment: Dictionary = save_data.get("equipment", {})
	var equipped: Dictionary = equipment.get("equipped", {})
	if not equipped.has(char_id):
		print("[PlayerSaveManager] 角色 %s 无装备记录，跳过" % char_id)
		return
	var char_eq: Dictionary = equipped[char_id]
	var loss: float = DURABILITY_LOSS_PER_HIT if reason == "hit" else DURABILITY_LOSS_PER_CATCH
	var changed: bool = false
	for slot in EQUIP_SLOTS:
		var slot_data = char_eq.get(slot, {})
		if slot_data is Dictionary:
			var item_id: String = slot_data.get("item_id", "")
			if item_id == "":
				continue
			var cur_dur: float = float(slot_data.get("durability", 0.0))
			var new_dur: float = max(0, cur_dur - loss)
			print("[PlayerSaveManager] 装备损耗: %s[%s] %s: %.2f → %.2f" % [char_id, slot, item_id, cur_dur, new_dur])
			if new_dur <= 0:
				# 装备耐久为0，消失
				print("[PlayerSaveManager] 装备 %s 耐久归零，已消失 (char=%s slot=%s)" % [item_id, char_id, slot])
				char_eq[slot] = {"item_id": "", "durability": 0}
			else:
				char_eq[slot] = {"item_id": item_id, "durability": new_dur}
			changed = true
	if changed:
		equipped[char_id] = char_eq
		equipment["equipped"] = equipped
		save_data["equipment"] = equipment
		save_slot()
		print("[PlayerSaveManager] 装备耐久已保存到存档")
	else:
		print("[PlayerSaveManager] 角色 %s 无装备损耗" % char_id)


## 获取某角色的装备总加成 {stat_key: total_bonus}
## 衰减阈值仅在开局判断：低于阈值的装备属性减半
func get_equipment_bonuses(char_id: String) -> Dictionary:
	var result := {
		"stamina_bonus": 0,
		"defense_bonus": 0,
		"speed_bonus": 0,
		"attack_bonus": 0,
		"resilience_bonus": 0,
		"ball_speed_bonus": 0
	}
	var eq: Dictionary = get_equipped(char_id)
	for slot in EQUIP_SLOTS:
		var slot_data = eq.get(slot, {})
		var item_id: String = ""
		var durability: float = 0.0
		if slot_data is String:
			item_id = slot_data
		elif slot_data is Dictionary:
			item_id = slot_data.get("item_id", "")
			durability = slot_data.get("durability", 0.0)
		if item_id == "":
			continue
		var def: Dictionary = InventoryManager.get_item_def(item_id)
		if def.is_empty():
			continue
		var stats: Dictionary = def.get("stats", {})
		# 衰减阈值判断：低于阈值的装备属性减半
		var rarity: String = def.get("rarity", "common")
		var threshold: int = RARITY_DURABILITY_THRESHOLD.get(rarity, 30)
		var multiplier: float = 1.0
		if durability < threshold:
			multiplier = 0.5
		for key in stats:
			if result.has(key):
				result[key] += int(stats[key] * multiplier)
	return result
