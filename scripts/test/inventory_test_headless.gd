extends Node
## 背包系统 - headless 自动测试
## 用法: Godot --headless res://scenes/test/inventory_test_headless.tscn

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	print("================================================")
	print("背包系统 - Headless 自动测试")
	print("================================================")
	print("")
	
	await get_tree().process_frame
	
	_run_all_tests()
	_print_summary()
	get_tree().quit()


func _run_all_tests() -> void:
	InventoryManager.clear_all()
	_test_item_definitions()
	_test_empty_inventory()
	_test_add_equipment()
	_test_add_consumable_stack()
	_test_remove_item()
	_test_full_inventory()
	_test_inventory_persistence()
	_test_rarity_helpers()
	InventoryManager.clear_all()


func _test_item_definitions() -> void:
	_print_header("测试1: 道具定义加载")
	
	var all_items: Array = InventoryManager.get_all_items()
	_assert_eq(all_items.size(), 20, "总道具数=20 (15装备+5食物)")
	
	var equipment: Array = InventoryManager.get_items_by_type("equipment")
	_assert_eq(equipment.size(), 15, "装备数=15 (5手套+5球衣+5球鞋)")
	
	var food: Array = InventoryManager.get_items_by_type("consumable")
	_assert_eq(food.size(), 5, "食物数=5 (各稀有度1个)")
	
	var gloves: Array = InventoryManager.get_items_by_sub_type("glove")
	_assert_eq(gloves.size(), 5, "手套数=5")
	
	var legendary: Array = InventoryManager.get_items_by_rarity("legendary")
	_assert_eq(legendary.size(), 4, "传说级道具=4 (手套+球衣+球鞋+糖果)")
	
	var def: Dictionary = InventoryManager.get_item_def("eq_glove_rare_01")
	_assert_eq(def.is_empty(), false, "能查到赛博手套")
	_assert_eq(def.get("name", ""), "赛博手套", "名称正确")
	_assert_eq(def.get("rarity", ""), "rare", "稀有度=rare")
	
	var not_found: Dictionary = InventoryManager.get_item_def("nonexistent")
	_assert_eq(not_found.is_empty(), true, "查不到的道具返回空字典")
	print("")


func _test_empty_inventory() -> void:
	_print_header("测试2: 初始背包状态")
	
	var items: Array = InventoryManager.get_backpack_items()
	_assert_eq(items.size(), 0, "初始背包为空")
	
	_assert_eq(InventoryManager.get_used_slots(), 0, "已用格数=0")
	_assert_eq(InventoryManager.get_max_slots(), 50, "最大格数=50")
	_assert_eq(InventoryManager.is_full(), false, "不满")
	_assert_eq(InventoryManager.has_item("eq_glove_common_01"), false, "没有训练手套")
	_assert_eq(InventoryManager.get_item_count("food_bread_common"), 0, "面包数量=0")
	print("")


func _test_add_equipment() -> void:
	_print_header("测试3: 添加装备（不可堆叠）")
	
	var ok := InventoryManager.add_item("eq_glove_common_01", 1)
	_assert_eq(ok, true, "添加1个训练手套成功")
	_assert_eq(InventoryManager.get_item_count("eq_glove_common_01"), 1, "数量=1")
	_assert_eq(InventoryManager.get_used_slots(), 1, "用了1格")
	
	var ok2 := InventoryManager.add_item("eq_glove_common_01", 1)
	_assert_eq(ok2, true, "再加1个同装备（占新格）")
	_assert_eq(InventoryManager.get_item_count("eq_glove_common_01"), 2, "总数量=2")
	_assert_eq(InventoryManager.get_used_slots(), 2, "占2格(装备不可堆叠)")
	
	var equip_list: Array = InventoryManager.get_backpack_equipment()
	_assert_eq(equip_list.size(), 2, "装备列表有2项")
	
	InventoryManager.remove_item("eq_glove_common_01", 2)
	_assert_eq(InventoryManager.get_used_slots(), 0, "清理完回到0格")
	print("")


func _test_add_consumable_stack() -> void:
	_print_header("测试4: 添加消耗品（可堆叠）")
	
	var ok := InventoryManager.add_item("food_bread_common", 1)
	_assert_eq(ok, true, "加1个面包成功")
	_assert_eq(InventoryManager.get_item_count("food_bread_common"), 1, "数量=1")
	_assert_eq(InventoryManager.get_used_slots(), 1, "用了1格")
	
	var ok2 := InventoryManager.add_item("food_bread_common", 50)
	_assert_eq(ok2, true, "再加50个面包成功")
	_assert_eq(InventoryManager.get_item_count("food_bread_common"), 51, "总数量=51")
	_assert_eq(InventoryManager.get_used_slots(), 1, "仍然1格(堆叠)")
	
	var ok3 := InventoryManager.add_item("food_bread_common", 50)
	_assert_eq(ok3, true, "再加50个(超99, 分2格)")
	_assert_eq(InventoryManager.get_item_count("food_bread_common"), 101, "总数量=101")
	_assert_eq(InventoryManager.get_used_slots(), 2, "占2格(99+2)")
	
	var food_list: Array = InventoryManager.get_backpack_consumables()
	_assert_eq(food_list.size(), 2, "食物列表2个堆叠格")
	
	InventoryManager.remove_item("food_bread_common", 101)
	_assert_eq(InventoryManager.get_used_slots(), 0, "清理完回到0格")
	print("")


func _test_remove_item() -> void:
	_print_header("测试5: 移除道具")
	
	InventoryManager.add_item("eq_jersey_good_01", 1)
	InventoryManager.add_item("food_lollipop_rare", 10)
	_assert_eq(InventoryManager.get_used_slots(), 2, "准备: 2格")
	
	var ok_rm := InventoryManager.remove_item("eq_jersey_good_01", 1)
	_assert_eq(ok_rm, true, "移除球衣成功")
	_assert_eq(InventoryManager.has_item("eq_jersey_good_01"), false, "球衣已无")
	_assert_eq(InventoryManager.get_used_slots(), 1, "剩1格")
	
	var ok_part := InventoryManager.remove_item("food_lollipop_rare", 3)
	_assert_eq(ok_part, true, "移除3个棒棒糖成功")
	_assert_eq(InventoryManager.get_item_count("food_lollipop_rare"), 7, "剩7个")
	_assert_eq(InventoryManager.get_used_slots(), 1, "仍然1格(堆叠内)")
	
	var ok_over := InventoryManager.remove_item("food_lollipop_rare", 100)
	_assert_eq(ok_over, false, "移除超额应失败")
	_assert_eq(InventoryManager.get_item_count("food_lollipop_rare"), 7, "数量不变")
	
	var ok_neg := InventoryManager.remove_item("food_lollipop_rare", -1)
	_assert_eq(ok_neg, false, "移除负数应失败")
	
	InventoryManager.remove_item("food_lollipop_rare", 7)
	_assert_eq(InventoryManager.get_used_slots(), 0, "清理完")
	print("")


func _test_full_inventory() -> void:
	_print_header("测试6: 背包满了")
	
	var test_item_id := "eq_glove_common_01"
	for i in range(50):
		InventoryManager.add_item(test_item_id, 1)
	_assert_eq(InventoryManager.get_used_slots(), 50, "塞满50格")
	_assert_eq(InventoryManager.is_full(), true, "is_full=true")
	
	var ok := InventoryManager.add_item("food_bread_common", 1)
	_assert_eq(ok, false, "满了再加失败")
	
	InventoryManager.remove_item(test_item_id, 50)
	_assert_eq(InventoryManager.is_full(), false, "清理完不满了")
	print("")


func _test_inventory_persistence() -> void:
	_print_header("测试7: 存档持久化")
	
	InventoryManager.add_item("eq_shoes_rare_01", 1)
	InventoryManager.add_item("food_lollipop_rare", 5)
	var count_shoes := InventoryManager.get_item_count("eq_shoes_rare_01")
	var count_lollipop := InventoryManager.get_item_count("food_lollipop_rare")
	_assert_eq(count_shoes, 1, "存前: 球鞋=1")
	_assert_eq(count_lollipop, 5, "存前: 棒棒糖=5")
	
	var orig_slot := PlayerSaveManager.current_slot
	PlayerSaveManager.load_slot(2)
	_assert_eq(InventoryManager.get_item_count("eq_shoes_rare_01"), 0, "切存档2: 球鞋=0")
	
	PlayerSaveManager.load_slot(orig_slot)
	_assert_eq(InventoryManager.get_item_count("eq_shoes_rare_01"), 1, "切回存档1: 球鞋=1")
	_assert_eq(InventoryManager.get_item_count("food_lollipop_rare"), 5, "切回存档1: 棒棒糖=5")
	
	InventoryManager.remove_item("eq_shoes_rare_01", 1)
	InventoryManager.remove_item("food_lollipop_rare", 5)
	_assert_eq(InventoryManager.get_used_slots(), 0, "清理完")
	print("")


func _test_rarity_helpers() -> void:
	_print_header("测试8: 稀有度辅助函数")
	
	var rarities: Array[String] = InventoryManager.get_all_rarities()
	_assert_eq(rarities.size(), 5, "5档稀有度")
	_assert_eq(rarities[0], "common", "第一档=common")
	_assert_eq(rarities[4], "legendary", "最后一档=legendary")
	
	_assert_eq(InventoryManager.get_rarity_name("common"), "普通", "common=普通")
	_assert_eq(InventoryManager.get_rarity_name("good"), "良好", "good=良好")
	_assert_eq(InventoryManager.get_rarity_name("rare"), "稀有", "rare=稀有")
	_assert_eq(InventoryManager.get_rarity_name("epic"), "史诗", "epic=史诗")
	_assert_eq(InventoryManager.get_rarity_name("legendary"), "传说", "legendary=传说")
	
	var color_legendary: Color = InventoryManager.get_rarity_color("legendary")
	_assert_eq(color_legendary.r > 0.9, true, "传说级红色分量高(金色)")
	_assert_eq(color_legendary.g > 0.7, true, "传说级绿色分量高(金色)")
	print("")


func _print_header(title: String) -> void:
	print("--- " + title + " ---")


func _assert_eq(actual: Variant, expected: Variant, msg: String) -> void:
	if actual == expected:
		print("  PASS " + msg)
		_pass_count += 1
	else:
		print("  FAIL " + msg + " (actual: " + str(actual) + ", expected: " + str(expected) + ")")
		_fail_count += 1


func _print_summary() -> void:
	print("================================================")
	print("测试结果: %d 通过, %d 失败" % [_pass_count, _fail_count])
	if _fail_count == 0:
		print("=== 全部通过 ===")
	else:
		print("=== 有失败项 ===")
	print("================================================")
