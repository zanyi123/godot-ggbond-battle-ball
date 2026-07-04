extends Node
## 玩家存档系统 - headless 自动测试（场景版）
## 用法: Godot --headless res://scenes/test/player_save_test_headless.tscn

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	print("================================================")
	print("玩家存档系统 - Headless 自动测试")
	print("================================================")
	print("")
	
	# 等一帧确保所有 autoload 初始化完成
	await get_tree().process_frame
	
	_run_all_tests()
	_print_summary()
	get_tree().quit()


func _run_all_tests() -> void:
	_test_initial_state()
	_test_currency_ops()
	_test_training_data()
	_test_slot_switch()
	_test_corrupted_recovery()
	_test_character_unlock()


func _test_initial_state() -> void:
	_print_header("测试1: 初始状态")
	_assert_eq(PlayerSaveManager.current_slot, 1, "默认存档位=1")
	_assert_eq(PlayerSaveManager.is_dev_mode(), true, "开发模式=true")
	_assert_eq(PlayerSaveManager.get_currency("fairy_coin"), 1000, "初始童话币=1000")
	_assert_eq(PlayerSaveManager.get_currency("spirit_ore"), 50, "初始元灵矿石=50")
	_assert_eq(PlayerSaveManager.get_currency("crystal"), 20, "初始水晶=20")
	_assert_eq(PlayerSaveManager.get_field_level(), 1, "初始场地等级=1")
	_assert_eq(PlayerSaveManager.get_unlocked_characters().size(), 7, "开发模式解锁7个角色")
	print("")


func _test_currency_ops() -> void:
	_print_header("测试2: 货币操作")
	var before: int = PlayerSaveManager.get_currency("fairy_coin")
	
	_assert_eq(PlayerSaveManager.add_currency("fairy_coin", 500), true, "加500童话币成功")
	_assert_eq(PlayerSaveManager.get_currency("fairy_coin"), before + 500, "加完后=1500")
	
	_assert_eq(PlayerSaveManager.spend_currency("fairy_coin", 200), true, "花200童话币成功")
	_assert_eq(PlayerSaveManager.get_currency("fairy_coin"), before + 300, "花完后=1300")
	
	_assert_eq(PlayerSaveManager.spend_currency("fairy_coin", 99999), false, "超额消费应失败")
	_assert_eq(PlayerSaveManager.get_currency("fairy_coin"), before + 300, "失败后金额不变")
	
	_assert_eq(PlayerSaveManager.add_currency("fairy_coin", -100), false, "加负数应失败")
	_assert_eq(PlayerSaveManager.spend_currency("fairy_coin", -100), false, "花负数应失败")
	print("")


func _test_training_data() -> void:
	_print_header("测试3: 训练数据")
	var char_id := "char_001"
	
	var train_before: Dictionary = PlayerSaveManager.get_character_train(char_id)
	_assert_eq(train_before.get("attack_bonus", -1), 0, "初始攻击训练=0")
	_assert_eq(train_before.get("stamina_bonus", -1), 0, "初始体力训练=0")
	
	var new_train: Dictionary = train_before.duplicate()
	new_train["attack_bonus"] = 10
	new_train["stamina_bonus"] = 5
	PlayerSaveManager.set_character_train(char_id, new_train)
	
	var train_after: Dictionary = PlayerSaveManager.get_character_train(char_id)
	_assert_eq(train_after.get("attack_bonus", -1), 10, "训练后攻击+10")
	_assert_eq(train_after.get("stamina_bonus", -1), 5, "训练后体力+5")
	
	var base_attack: int = DataManager.get_character_by_id(char_id).get("attack", 0)
	var total_attack: int = PlayerSaveManager.get_total_stat(char_id, "attack")
	_assert_eq(total_attack, base_attack + 10, "总攻击=基础%d+训练10" % base_attack)
	
	var old_level: int = PlayerSaveManager.get_field_level()
	PlayerSaveManager.set_field_level(5)
	_assert_eq(PlayerSaveManager.get_field_level(), 5, "场地等级设为5")
	PlayerSaveManager.set_field_level(old_level)
	print("")


func _test_slot_switch() -> void:
	_print_header("测试4: 存档位切换")
	var original: int = PlayerSaveManager.current_slot
	
	PlayerSaveManager.add_currency("fairy_coin", 100)
	var slot1_coin: int = PlayerSaveManager.get_currency("fairy_coin")
	print("  存档1童话币: %d" % slot1_coin)
	
	PlayerSaveManager.load_slot(2)
	_assert_eq(PlayerSaveManager.current_slot, 2, "切到存档2")
	var slot2_coin: int = PlayerSaveManager.get_currency("fairy_coin")
	_assert_eq(slot2_coin, 1000, "存档2是默认值1000")
	
	PlayerSaveManager.add_currency("fairy_coin", 333)
	_assert_eq(PlayerSaveManager.get_currency("fairy_coin"), 1333, "存档2加333=1333")
	
	PlayerSaveManager.load_slot(original)
	_assert_eq(PlayerSaveManager.current_slot, original, "切回存档%d" % original)
	_assert_eq(PlayerSaveManager.get_currency("fairy_coin"), slot1_coin, "存档1数据不变")
	print("")


func _test_corrupted_recovery() -> void:
	_print_header("测试5: 坏档恢复")
	var test_slot := 3
	var save_path := "user://saves/save_3.json"
	var backup_path := "user://saves/save_3_corrupted_backup.json"
	
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string("this is not valid json [[[[")
		file.close()
	print("  已写入坏档到 save_3.json")
	
	PlayerSaveManager.load_slot(test_slot)
	_assert_eq(PlayerSaveManager.get_currency("fairy_coin"), 1000, "坏档恢复后=默认1000")
	
	var has_backup: bool = FileAccess.file_exists(backup_path)
	_assert_eq(has_backup, true, "坏档备份文件已生成")
	
	PlayerSaveManager.load_slot(1)
	print("")


func _test_character_unlock() -> void:
	_print_header("测试6: 角色解锁")
	
	_assert_eq(PlayerSaveManager.has_character("char_001"), true, "开发模式有猪猪侠")
	_assert_eq(PlayerSaveManager.has_character("char_999"), true, "开发模式有无角色也返回true")
	
	var all_chars: Array[String] = PlayerSaveManager.get_unlocked_characters()
	_assert_eq(all_chars.size(), 7, "开发模式解锁7个角色")
	
	_assert_eq(PlayerSaveManager.has_character("char_004"), true, "有小呆呆")
	_assert_eq(PlayerSaveManager.has_character("char_006"), true, "有迷糊老师")
	_assert_eq(PlayerSaveManager.has_character("char_007"), true, "有卜三")
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
