extends Node
## 快捷设置系统面板加载测试
## 验证装备面板和食物面板能正常加载

var passed: int = 0
var failed: int = 0


func _ready() -> void:
	print("=== 快捷设置面板加载测试 ===")
	print()
	
	_test_equipment_panel()
	_test_food_panel()
	_test_dev_data_sync()
	
	print()
	print("测试结果: %d 通过, %d 失败" % [passed, failed])
	if failed == 0:
		print("=== 全部通过 ===")
	else:
		print("=== 有失败项 ===")
	
	get_tree().quit(failed)


func _test_equipment_panel() -> void:
	print("--- 装备面板加载测试 ---")
	var script = load("res://scripts/dev_tools/dev_equipment_panel.gd")
	_assert(script != null, "装备面板脚本加载成功")
	
	if script:
		var panel = script.new()
		_assert(panel != null, "装备面板实例创建成功")
		if panel:
			add_child(panel)
			await get_tree().process_frame
			var has_method = panel.has_method("_ready")
			_assert(has_method, "装备面板有_ready方法")
			panel.queue_free()


func _test_food_panel() -> void:
	print("--- 食物面板加载测试 ---")
	var script = load("res://scripts/dev_tools/dev_food_panel.gd")
	_assert(script != null, "食物面板脚本加载成功")
	
	if script:
		var panel = script.new()
		_assert(panel != null, "食物面板实例创建成功")
		if panel:
			add_child(panel)
			await get_tree().process_frame
			var has_method = panel.has_method("_ready")
			_assert(has_method, "食物面板有_ready方法")
			panel.queue_free()


func _test_dev_data_sync() -> void:
	print("--- DevDataSync 道具函数测试 ---")
	var items := DevDataSync.load_items()
	_assert(items.size() > 0, "能加载道具数据，数量=%d" % items.size())
	
	var rarities := DevDataSync.get_rarities()
	_assert(rarities.size() == 5, "稀有度有5档")
	
	var subtypes := DevDataSync.get_equipment_subtypes()
	_assert(subtypes.size() == 3, "装备有3个部位")
	
	var rarity_name := DevDataSync.get_rarity_name("rare")
	_assert(rarity_name == "稀有", "稀有度中文名正确: %s" % rarity_name)
	
	var subtype_name := DevDataSync.get_subtype_name("glove")
	_assert(subtype_name == "手套", "部位中文名正确: %s" % subtype_name)
	
	var rarity_color := DevDataSync.get_rarity_color("legendary")
	_assert(rarity_color != Color.WHITE, "传说稀有度有颜色")
	
	var eq_template := DevDataSync.create_equipment_template("eq_test_99", "jersey")
	_assert(eq_template.get("type", "") == "equipment", "装备模板type正确")
	_assert(eq_template.has("stats"), "装备模板有stats")
	
	var food_template := DevDataSync.create_food_template("food_test_999")
	_assert(food_template.get("type", "") == "consumable", "食物模板type正确")
	_assert(food_template.has("effect"), "食物模板有effect")
	
	var eq_id := DevDataSync.generate_equipment_id(items, "shoes")
	_assert(eq_id.begins_with("eq_shoes_"), "生成装备ID格式正确: %s" % eq_id)
	
	var food_id := DevDataSync.generate_food_id(items)
	_assert(food_id.begins_with("food_"), "生成食物ID格式正确: %s" % food_id)


func _assert(condition: bool, msg: String) -> void:
	if condition:
		print("  PASS ", msg)
		passed += 1
	else:
		print("  FAIL ", msg)
		failed += 1
