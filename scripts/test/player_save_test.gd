extends Control
## 玩家存档系统测试面板
## 验证：存读一致性、货币加减、坏档处理、存档位切换、训练数据

var _log_text: RichTextLabel


func _ready() -> void:
	_build_ui()
	_log("=== 存档系统测试面板 ===")
	_log("当前存档位: %d" % PlayerSaveManager.current_slot)
	_log("开发模式: %s" % str(PlayerSaveManager.is_dev_mode()))
	_log("初始童话币: %d" % PlayerSaveManager.get_currency("fairy_coin"))
	_log("初始元灵矿石: %d" % PlayerSaveManager.get_currency("spirit_ore"))
	_log("初始水晶: %d" % PlayerSaveManager.get_currency("crystal"))
	_log("场地等级: %d" % PlayerSaveManager.get_field_level())
	_log("解锁角色数: %d" % PlayerSaveManager.get_unlocked_characters().size())
	_log("")


func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	
	_log_text = RichTextLabel.new()
	_log_text.custom_minimum_size = Vector2(600, 400)
	_log_text.bbcode_enabled = true
	scroll.add_child(_log_text)
	
	var btn_row := HBoxContainer.new()
	btn_row.position = Vector2(20, 420)
	add_child(btn_row)
	
	_add_button(btn_row, "测试货币加减", _test_currency)
	_add_button(btn_row, "测试训练数据", _test_training)
	_add_button(btn_row, "测试存档切换", _test_slot_switch)
	_add_button(btn_row, "测试坏档恢复", _test_corrupted)
	_add_button(btn_row, "测试角色解锁", _test_character_unlock)


func _add_button(parent: Control, text: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(callback)
	parent.add_child(btn)


func _log(msg: String) -> void:
	_log_text.append_text(msg + "\n")


func _test_currency() -> void:
	_log("--- 货币加减测试 ---")
	var before := PlayerSaveManager.get_currency("fairy_coin")
	_log("测试前童话币: %d" % before)
	
	var ok_add := PlayerSaveManager.add_currency("fairy_coin", 500)
	var after_add := PlayerSaveManager.get_currency("fairy_coin")
	_log("加500童话币: ok=%s, 结果=%d" % [str(ok_add), after_add])
	assert(ok_add and after_add == before + 500, "货币加法错误")
	
	var ok_spend := PlayerSaveManager.spend_currency("fairy_coin", 200)
	var after_spend := PlayerSaveManager.get_currency("fairy_coin")
	_log("花200童话币: ok=%s, 结果=%d" % [str(ok_spend), after_spend])
	assert(ok_spend and after_spend == after_add - 200, "货币减法错误")
	
	var ok_overspend := PlayerSaveManager.spend_currency("fairy_coin", 99999)
	var after_over := PlayerSaveManager.get_currency("fairy_coin")
	_log("花99999童话币(超出): ok=%s, 结果=%d" % [str(ok_overspend), after_over])
	assert(not ok_overspend and after_over == after_spend, "超额花费应该失败")
	
	_log("✅ 货币测试通过")
	_log("")


func _test_training() -> void:
	_log("--- 训练数据测试 ---")
	var char_id := "char_001"
	var train_before := PlayerSaveManager.get_character_train(char_id)
	_log("猪猪侠训练前: 攻击+%d, 体力+%d" % [train_before.get("attack_bonus", 0), train_before.get("stamina_bonus", 0)])
	
	var new_train := train_before.duplicate()
	new_train["attack_bonus"] = 10
	new_train["stamina_bonus"] = 5
	PlayerSaveManager.set_character_train(char_id, new_train)
	
	var train_after := PlayerSaveManager.get_character_train(char_id)
	_log("猪猪侠训练后: 攻击+%d, 体力+%d" % [train_after.get("attack_bonus", 0), train_after.get("stamina_bonus", 0)])
	assert(train_after.get("attack_bonus", 0) == 10, "训练攻击加成错误")
	assert(train_after.get("stamina_bonus", 0) == 5, "训练体力加成错误")
	
	var total_attack := PlayerSaveManager.get_total_stat(char_id, "attack")
	var base_attack: int = DataManager.get_character_by_id(char_id).get("attack", 0)
	_log("猪猪侠总攻击 = 基础%d + 训练%d = %d" % [base_attack, 10, total_attack])
	assert(total_attack == base_attack + 10, "总属性计算错误")
	
	var old_level := PlayerSaveManager.get_field_level()
	PlayerSaveManager.set_field_level(3)
	_log("场地等级: %d -> %d" % [old_level, PlayerSaveManager.get_field_level()])
	assert(PlayerSaveManager.get_field_level() == 3, "场地等级设置错误")
	PlayerSaveManager.set_field_level(old_level)
	
	_log("✅ 训练测试通过")
	_log("")


func _test_slot_switch() -> void:
	_log("--- 存档位切换测试 ---")
	var original_slot := PlayerSaveManager.current_slot
	var test_slot := 2
	
	PlayerSaveManager.add_currency("fairy_coin", 100)
	var slot1_coin := PlayerSaveManager.get_currency("fairy_coin")
	_log("存档1童话币: %d" % slot1_coin)
	
	PlayerSaveManager.load_slot(test_slot)
	var slot2_coin := PlayerSaveManager.get_currency("fairy_coin")
	_log("存档2童话币: %d" % slot2_coin)
	assert(PlayerSaveManager.current_slot == test_slot, "存档位切换失败")
	
	PlayerSaveManager.add_currency("fairy_coin", 333)
	var slot2_after := PlayerSaveManager.get_currency("fairy_coin")
	_log("存档2加333后: %d" % slot2_after)
	
	PlayerSaveManager.load_slot(original_slot)
	var slot1_back := PlayerSaveManager.get_currency("fairy_coin")
	_log("切回存档1: %d (应该不变)" % slot1_back)
	assert(slot1_back == slot1_coin, "切回存档1数据应该不变")
	assert(PlayerSaveManager.current_slot == original_slot, "切回存档1失败")
	
	_log("✅ 存档切换测试通过")
	_log("")


func _test_corrupted() -> void:
	_log("--- 坏档恢复测试 ---")
	var test_slot := 3
	var save_path := "user://saves/save_3.json"
	
	var bad_content := "这不是有效的json{{{{"
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(bad_content)
		file.close()
		_log("已写入坏档到 save_3.json")
	
	PlayerSaveManager.load_slot(test_slot)
	var coin := PlayerSaveManager.get_currency("fairy_coin")
	_log("坏档恢复后童话币: %d (应该是默认1000)" % coin)
	assert(coin == 1000, "坏档恢复后应该是默认值")
	
	var backup_path := "user://saves/save_3_corrupted_backup.json"
	var has_backup := FileAccess.file_exists(backup_path)
	_log("坏档备份文件存在: %s" % str(has_backup))
	assert(has_backup, "应该生成坏档备份")
	
	PlayerSaveManager.load_slot(1)
	_log("✅ 坏档恢复测试通过")
	_log("")


func _test_character_unlock() -> void:
	_log("--- 角色解锁测试 ---")
	var all_chars := PlayerSaveManager.get_unlocked_characters()
	_log("解锁角色数: %d" % all_chars.size())
	_log("角色列表: %s" % str(all_chars))
	
	if PlayerSaveManager.is_dev_mode():
		_log("开发模式下应全部解锁: %d个" % all_chars.size())
		assert(all_chars.size() == 7, "开发模式应该解锁全部7个角色")
	
	var has_zhuzhuxia := PlayerSaveManager.has_character("char_001")
	_log("有猪猪侠(char_001): %s" % str(has_zhuzhuxia))
	assert(has_zhuzhuxia, "应该有猪猪侠")
	
	_log("✅ 角色解锁测试通过")
	_log("")


func _assert(condition: bool, msg: String) -> void:
	if not condition:
		_log("❌ 断言失败: " + msg)
	else:
		_log("✅ " + msg)
