extends Node
## 道具背包管理器 - Autoload 单例
## 负责：道具静态数据加载 + 玩家背包增删改查
## 背包数据存在 PlayerSaveManager.save_data.inventory 里

const MAX_SLOTS := 50
const ITEMS_JSON_PATH := "res://data/items/items.json"

var _item_defs: Dictionary = {}
var _item_list: Array = []

signal inventory_changed
signal item_added(item_id: String, count: int)
signal item_removed(item_id: String, count: int)


func _ready() -> void:
	_load_item_definitions()
	PlayerSaveManager.save_loaded.connect(_on_save_loaded)


func _load_item_definitions() -> void:
	if not FileAccess.file_exists(ITEMS_JSON_PATH):
		push_error("[InventoryManager] 道具数据文件不存在: %s" % ITEMS_JSON_PATH)
		return
	
	var file := FileAccess.open(ITEMS_JSON_PATH, FileAccess.READ)
	if file == null:
		push_error("[InventoryManager] 无法打开道具数据文件")
		return
	
	var text := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("[InventoryManager] 道具数据解析失败")
		return
	
	var data: Dictionary = json.data
	var items: Array = data.get("items", [])
	for item in items:
		var id: String = item.get("id", "")
		if id == "":
			continue
		_item_defs[id] = item
		_item_list.append(item)
	
	print("[InventoryManager] 加载道具定义: %d 个" % _item_list.size())


func _on_save_loaded(_slot: int) -> void:
	_ensure_inventory_structure()


## 重新加载道具定义数据（管理员修改数据后调用，确保玩家端实时同步）
func reload_item_defs() -> void:
	_item_defs.clear()
	_item_list.clear()
	_load_item_definitions()


func _ensure_inventory_structure() -> void:
	var save: Dictionary = PlayerSaveManager.save_data
	if not save.has("inventory"):
		save["inventory"] = {"items": [], "max_slots": MAX_SLOTS}
		return
	var inv: Dictionary = save["inventory"]
	if not inv.has("items"):
		inv["items"] = []
	if not inv.has("max_slots"):
		inv["max_slots"] = MAX_SLOTS


func get_item_def(item_id: String) -> Dictionary:
	if _item_defs.has(item_id):
		return _item_defs[item_id]
	return {}


func get_all_items() -> Array:
	return _item_list.duplicate()


func get_items_by_type(item_type: String) -> Array:
	var result: Array = []
	for item in _item_list:
		if item.get("type", "") == item_type:
			result.append(item)
	return result


func get_items_by_sub_type(sub_type: String) -> Array:
	var result: Array = []
	for item in _item_list:
		if item.get("sub_type", "") == sub_type:
			result.append(item)
	return result


func get_items_by_rarity(rarity: String) -> Array:
	var result: Array = []
	for item in _item_list:
		if item.get("rarity", "") == rarity:
			result.append(item)
	return result


func get_backpack_items() -> Array:
	_ensure_inventory_structure()
	var inv: Dictionary = PlayerSaveManager.save_data.get("inventory", {})
	return inv.get("items", []).duplicate()


func get_item_count(item_id: String) -> int:
	_ensure_inventory_structure()
	var items: Array = PlayerSaveManager.save_data.get("inventory", {}).get("items", [])
	var total: int = 0
	for entry in items:
		if entry.get("item_id", "") == item_id:
			total += int(entry.get("count", 0))
	return total


func has_item(item_id: String, count: int = 1) -> bool:
	return get_item_count(item_id) >= count


func get_max_slots() -> int:
	_ensure_inventory_structure()
	var inv: Dictionary = PlayerSaveManager.save_data.get("inventory", {})
	return int(inv.get("max_slots", MAX_SLOTS))


func get_used_slots() -> int:
	_ensure_inventory_structure()
	var items: Array = PlayerSaveManager.save_data.get("inventory", {}).get("items", [])
	return items.size()


func is_full() -> bool:
	return get_used_slots() >= get_max_slots()


func add_item(item_id: String, count: int = 1, initial_durability: float = -1.0) -> bool:
	if count <= 0:
		return false
	var def: Dictionary = get_item_def(item_id)
	if def.is_empty():
		push_error("[InventoryManager] 未知道具ID: %s" % item_id)
		return false

	_ensure_inventory_structure()
	var inv: Dictionary = PlayerSaveManager.save_data["inventory"]
	var items: Array = inv["items"]
	var is_equip: bool = str(def.get("type", "")) == "equipment"
	var stack_max: int = int(def.get("stack_max", 1))
	if is_equip:
		stack_max = 1
	var remaining: int = count

	var default_dur: float = 0.0
	if is_equip:
		default_dur = float(def.get("max_durability", 50))
	if initial_durability >= 0:
		default_dur = initial_durability

	if stack_max > 1 and not is_equip:
		for entry in items:
			if entry.get("item_id", "") == item_id:
				var current_count: int = int(entry.get("count", 0))
				var can_add: int = stack_max - current_count
				if can_add > 0:
					var add_amount: int = min(can_add, remaining)
					entry["count"] = current_count + add_amount
					remaining -= add_amount
					if remaining <= 0:
						break

	while remaining > 0:
		if items.size() >= get_max_slots():
			if remaining < count:
				PlayerSaveManager.save_slot()
				inventory_changed.emit()
				item_added.emit(item_id, count - remaining)
			push_warning("[InventoryManager] 背包已满，只添加了%d个%s" % [count - remaining, def.get("name", "")])
			return false

		var add_amount: int = remaining
		if stack_max > 0:
			add_amount = min(remaining, stack_max)
		var new_entry: Dictionary = {"item_id": item_id, "count": add_amount}
		if is_equip:
			new_entry["durability"] = default_dur
		items.append(new_entry)
		remaining -= add_amount

	PlayerSaveManager.save_slot()
	inventory_changed.emit()
	item_added.emit(item_id, count)
	return true


func remove_item(item_id: String, count: int = 1) -> bool:
	if count <= 0:
		return false
	if not has_item(item_id, count):
		return false
	
	_ensure_inventory_structure()
	var inv: Dictionary = PlayerSaveManager.save_data["inventory"]
	var items: Array = inv["items"]
	var remaining: int = count
	
	for i in range(items.size() - 1, -1, -1):
		if remaining <= 0:
			break
		var entry: Dictionary = items[i]
		if entry.get("item_id", "") == item_id:
			var entry_count: int = int(entry.get("count", 0))
			var remove_amount: int = min(entry_count, remaining)
			entry["count"] = entry_count - remove_amount
			remaining -= remove_amount
			if int(entry["count"]) <= 0:
				items.remove_at(i)
	
	PlayerSaveManager.save_slot()
	inventory_changed.emit()
	item_removed.emit(item_id, count)
	return true


func get_backpack_by_type(item_type: String) -> Array:
	var result: Array = []
	var items: Array = get_backpack_items()
	for entry in items:
		var def: Dictionary = get_item_def(entry.get("item_id", ""))
		if def.get("type", "") == item_type:
			result.append(entry)
	return result


func get_backpack_equipment() -> Array:
	return get_backpack_by_type("equipment")


func get_backpack_consumables() -> Array:
	return get_backpack_by_type("consumable")


func clear_all() -> void:
	_ensure_inventory_structure()
	var inv: Dictionary = PlayerSaveManager.save_data["inventory"]
	inv["items"] = []
	PlayerSaveManager.save_slot()
	inventory_changed.emit()


func get_rarity_color(rarity: String) -> Color:
	match rarity:
		"common":
			return Color(0.85, 0.85, 0.85)
		"good":
			return Color(0.3, 0.9, 0.3)
		"rare":
			return Color(0.3, 0.5, 1.0)
		"epic":
			return Color(0.8, 0.3, 1.0)
		"legendary":
			return Color(1.0, 0.85, 0.2)
		_:
			return Color(1, 1, 1)


func get_rarity_name(rarity: String) -> String:
	match rarity:
		"common":
			return "普通"
		"good":
			return "良好"
		"rare":
			return "稀有"
		"epic":
			return "史诗"
		"legendary":
			return "传说"
		_:
			return "未知"


func get_all_rarities() -> Array[String]:
	return ["common", "good", "rare", "epic", "legendary"]


## ==================== 装备穿戴系统 ====================

## 从背包移除一件装备，返回其耐久值（-1表示失败）
func _remove_one_equipment(item_id: String) -> float:
	_ensure_inventory_structure()
	var inv: Dictionary = PlayerSaveManager.save_data["inventory"]
	var items: Array = inv["items"]
	for i in range(items.size() - 1, -1, -1):
		var entry: Dictionary = items[i]
		if entry.get("item_id", "") == item_id:
			var dur: float = float(entry.get("durability", 0))
			var entry_count: int = int(entry.get("count", 0))
			if entry_count <= 1:
				items.remove_at(i)
			else:
				entry["count"] = entry_count - 1
			return dur
	return -1.0


## 穿戴装备：从背包扣1个，记录到角色装备槽
## 如果该槽位原本有装备，先把旧装备加回背包
## 返回 true=成功，false=背包没这个装备
func equip_to_character(char_id: String, slot: String, item_id: String) -> bool:
	var def: Dictionary = get_item_def(item_id)
	if def.is_empty():
		return false
	# 检查部位匹配
	if str(def.get("sub_type", "")) != slot:
		return false
	# 检查背包有没有
	if not has_item(item_id, 1):
		return false
	# 从背包移除一件装备，获取其耐久值
	var dur: float = _remove_one_equipment(item_id)
	if dur < 0:
		return false
	# 记录到装备槽（如果原来有装备，旧装备回背包）
	var old_item_id: String = PlayerSaveManager.get_equipped_item(char_id, slot)
	var old_dur: float = 0.0
	if old_item_id != "":
		old_dur = PlayerSaveManager.get_equipped_durability(char_id, slot)
	PlayerSaveManager.equip_item(char_id, slot, item_id, dur)
	if old_item_id != "":
		add_item(old_item_id, 1, old_dur)
	PlayerSaveManager.save_slot()
	inventory_changed.emit()
	print("[Inventory] %s 穿戴 %s 槽位 %s (耐久: %.1f)" % [char_id, slot, item_id, dur])
	return true


## 卸下装备：从角色装备槽清空，装备加回背包
func unequip_from_character(char_id: String, slot: String) -> bool:
	var item_id: String = PlayerSaveManager.get_equipped_item(char_id, slot)
	if item_id == "":
		return false
	# 获取当前耐久值
	var dur: float = PlayerSaveManager.get_equipped_durability(char_id, slot)
	# 清空槽位
	PlayerSaveManager.unequip_item(char_id, slot)
	# 加回背包，传入当前耐久值
	add_item(item_id, 1, dur)
	inventory_changed.emit()
	print("[Inventory] %s 卸下 %s 槽位 %s (耐久: %.1f)" % [char_id, slot, item_id, dur])
	return true


## 获取背包里指定部位的装备列表 [{item_id, count, def}]
func get_backpack_by_slot(slot: String) -> Array:
	var result: Array = []
	var items: Array = get_backpack_items()
	for entry in items:
		var iid: String = str(entry.get("item_id", ""))
		var def: Dictionary = get_item_def(iid)
		if def.is_empty():
			continue
		if str(def.get("type", "")) != "equipment":
			continue
		if str(def.get("sub_type", "")) != slot:
			continue
		result.append({
			"item_id": iid,
			"count": int(entry.get("count", 0)),
			"def": def
		})
	return result
