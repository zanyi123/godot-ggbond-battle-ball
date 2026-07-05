extends Node
## 营养系统管理器
## 赛前吃1种食物，消耗1个，全队获得固定值加成，整场有效
## 整场只能吃1种1次，不叠加

signal food_consumed(food_id: String)
signal food_cleared()

# 食物数据缓存 {food_id: food_data}
var _foods_cache: Dictionary = {}
# 当前已吃的食物ID（空字符串=没吃）
var _active_food_id: String = ""

# 属性映射：食物effect.stat → player属性名
const STAT_MAP := {
	"stamina": "stamina",
	"defense": "defense",
	"speed": "speed",
	"attack": "attack",
	"resilience": "resilience",
	"ball_speed": "ball_speed",
}


func _ready() -> void:
	_load_foods_data()


func _load_foods_data() -> void:
	_foods_cache.clear()
	# 1. 先从 items.json 加载（管理员维护的数据源，优先级高）
	var items_path: String = "res://data/items/items.json"
	if FileAccess.file_exists(items_path):
		var ifile := FileAccess.open(items_path, FileAccess.READ)
		if ifile:
			var itext := ifile.get_as_text()
			ifile.close()
			var ijson = JSON.parse_string(itext)
			if ijson is Dictionary:
				var items: Array = ijson.get("items", [])
				for item in items:
					if str(item.get("sub_type", "")) == "food":
						var fid: String = item.get("id", "")
						if fid != "":
							_foods_cache[fid] = item
	# 2. 再从 foods.json 补充（兼容旧数据，不覆盖 items.json 已有的）
	var path: String = "res://data/items/foods.json"
	if not FileAccess.file_exists(path):
		push_warning("[NutritionManager] 食物数据文件不存在: " + path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[NutritionManager] 无法打开食物数据文件")
		return
	var text: String = file.get_as_text()
	file.close()
	var json = JSON.parse_string(text)
	if json == null:
		push_error("[NutritionManager] 食物数据JSON解析失败")
		return
	var foods: Array = json.get("foods", [])
	for food in foods:
		var fid: String = food.get("id", "")
		if fid != "" and not _foods_cache.has(fid):
			_foods_cache[fid] = food
	print("[NutritionManager] 食物数据加载完成: %d 个" % _foods_cache.size())


## 重新加载食物数据（管理员修改数据后调用，确保实时同步）
func reload_foods_data() -> void:
	_load_foods_data()


## 获取所有食物数据
func get_all_foods() -> Array:
	return _foods_cache.values()


## 按稀有度获取食物
func get_foods_by_rarity(rarity: String) -> Array:
	var result: Array = []
	for food in _foods_cache.values():
		if food.get("rarity", "") == rarity:
			result.append(food)
	return result


## 获取单个食物数据
func get_food(food_id: String) -> Dictionary:
	return _foods_cache.get(food_id, {})


## 吃食物：消耗1个，全队生效，整场1种1次
## 返回 true=成功，false=失败（已吃过/背包没有/食物无效）
func consume_food(food_id: String) -> bool:
	# 整场只能吃1种1次
	if _active_food_id != "":
		push_warning("[NutritionManager] 本场已吃过食物: " + _active_food_id + "，不能再吃")
		return false

	# 验证食物ID有效
	if not _foods_cache.has(food_id):
		push_warning("[NutritionManager] 无效的食物ID: " + food_id)
		return false

	# 从背包扣减1个（通过InventoryManager）
	if InventoryManager == null:
		push_error("[NutritionManager] InventoryManager未就绪")
		return false
	var removed: bool = InventoryManager.remove_item(food_id, 1)
	if not removed:
		push_warning("[NutritionManager] 背包中食物不足或不存在: " + food_id)
		return false

	# 记录已吃食物
	_active_food_id = food_id

	# 写入存档
	PlayerSaveManager.set_active_food(food_id)

	food_consumed.emit(food_id)
	return true


## 获取当前已激活的食物ID
func get_active_food_id() -> String:
	return _active_food_id


## 获取当前已激活的食物加成（返回 {stat: value} 或空字典）
func get_active_bonus() -> Dictionary:
	if _active_food_id == "":
		return {}
	var food: Dictionary = _foods_cache.get(_active_food_id, {})
	if food.is_empty():
		return {}
	var effect: Dictionary = food.get("effect", {})
	var stat: String = effect.get("stat", "")
	var value: float = float(effect.get("value", 0))
	if stat == "" or value == 0.0:
		return {}
	return {stat: value}


## 获取全队食物加成（给player.gd用，返回6项属性的加成字典）
func get_team_bonuses() -> Dictionary:
	var bonus: Dictionary = get_active_bonus()
	if bonus.is_empty():
		return {}
	var stat: String = bonus.keys()[0]
	var value: float = float(bonus[stat])
	# 映射到player属性名 + _bonus后缀
	var mapped: String = STAT_MAP.get(stat, stat)
	return {mapped + "_bonus": value}


## 清空已吃食物（比赛结束后调用）
func clear_active_food() -> void:
	_active_food_id = ""
	PlayerSaveManager.set_active_food("")
	food_cleared.emit()


## 比赛开始时从存档恢复已吃食物状态
func load_from_save() -> void:
	var save_data: Dictionary = PlayerSaveManager.get_data()
	var nutrition: Dictionary = save_data.get("nutrition", {})
	var raw = nutrition.get("pre_match_food", "")
	if typeof(raw) == TYPE_ARRAY:
		# 兼容旧格式（数组）
		if raw.size() > 0:
			_active_food_id = String(raw[0])
		else:
			_active_food_id = ""
	else:
		_active_food_id = String(raw)
