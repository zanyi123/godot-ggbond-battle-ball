extends Node
## 玩家存档管理器 - 本地持久化存储
## 挂载为Autoload单例，全局访问
## 支持3个存档位、版本迁移、坏档备份、自动保存

const SAVE_VERSION := 1
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


## 获取某角色的全部已穿戴装备 {slot: item_id}
func get_equipped(char_id: String) -> Dictionary:
	var equipment: Dictionary = save_data.get("equipment", {})
	var equipped: Dictionary = equipment.get("equipped", {})
	if not equipped.has(char_id):
		equipped[char_id] = {"glove": "", "jersey": "", "shoes": ""}
		equipment["equipped"] = equipped
		save_data["equipment"] = equipment
	return equipped.get(char_id, {"glove": "", "jersey": "", "shoes": ""})


## 获取某角色某槽位的装备ID（空字符串=未穿戴）
func get_equipped_item(char_id: String, slot: String) -> String:
	var eq: Dictionary = get_equipped(char_id)
	return eq.get(slot, "")


## 穿戴装备：只更新存档里的装备记录，不操作背包
## 返回被替换下来的旧装备ID（空字符串=原本没穿）
func equip_item(char_id: String, slot: String, item_id: String) -> String:
	var equipment: Dictionary = save_data.get("equipment", {})
	var equipped: Dictionary = equipment.get("equipped", {})
	if not equipped.has(char_id):
		equipped[char_id] = {"glove": "", "jersey": "", "shoes": ""}
	var old: String = equipped[char_id].get(slot, "")
	equipped[char_id][slot] = item_id
	equipment["equipped"] = equipped
	save_data["equipment"] = equipment
	save_slot()
	return old


## 卸下装备：清空槽位，返回被卸下的装备ID
func unequip_item(char_id: String, slot: String) -> String:
	return equip_item(char_id, slot, "")


## 获取某角色的装备总加成 {stat_key: total_bonus}
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
		var item_id: String = eq.get(slot, "")
		if item_id == "":
			continue
		var def: Dictionary = InventoryManager.get_item_def(item_id)
		if def.is_empty():
			continue
		var stats: Dictionary = def.get("stats", {})
		for key in stats:
			if result.has(key):
				result[key] += int(stats[key])
	return result
