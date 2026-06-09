extends Node2D
## BuffManager 独立测试
## 运行方式：Godot中把这个脚本挂到任意Node2D节点上，按F6运行场景
## 通过标准：所有测试项打印 ✅ PASS，无 ❌ FAIL

const BuffManager = preload("res://scripts/systems/buff_system/buff_manager.gd")
var buff_mgr
var pass_count: int = 0
var fail_count: int = 0

func _ready() -> void:
	print("\n========== BuffManager 独立测试 ==========\n")

	buff_mgr = BuffManager.new()
	add_child(buff_mgr)

	# 按顺序执行测试
	test_01_add_single_pct()
	test_02_add_single_flat()
	test_03_multiple_pct()
	test_04_pct_and_flat_combined()
	test_05_negative_buff()
	test_06_remove_by_id()
	test_07_remove_by_source()
	test_08_duration_expire()
	test_09_permanent_buff()
	test_10_clear_all()
	test_11_whitelist_reject()
	test_12_empty_calc()
	test_13_signal_emit()
	test_14_multiple_stats()
	test_15_zero_base_value()

	# 汇总
	print("\n==========================================")
	print("测试结果: %d ✅ PASS, %d ❌ FAIL" % [pass_count, fail_count])
	if fail_count == 0:
		print(">>> 全部通过 <<<")
	else:
		print(">>> 有失败项，请检查 <<<")
	print("==========================================\n")

# ============================================================
# 辅助断言
# ============================================================

func assert_eq(actual: Variant, expected: Variant, desc: String) -> void:
	if absf(float(actual) - float(expected)) < 0.01:
		pass_count += 1
		print("  ✅ PASS: %s (=%.2f)" % [desc, float(actual)])
	else:
		fail_count += 1
		print("  ❌ FAIL: %s (期望=%.2f 实际=%.2f)" % [desc, float(expected), float(actual)])

func assert_true(condition: bool, desc: String) -> void:
	if condition:
		pass_count += 1
		print("  ✅ PASS: %s" % desc)
	else:
		fail_count += 1
		print("  ❌ FAIL: %s" % desc)

# ============================================================
# 测试用例
# ============================================================

## T01: 单条百分比buff
func test_01_add_single_pct() -> void:
	print("[T01] 单条百分比buff: 基础50 +30%")
	buff_mgr.clear_all()
	buff_mgr.add_buff("attack_power", "pct", 0.3, 0.0, "test01")
	var result: float = buff_mgr.calc_stat(50.0, "attack_power")
	assert_eq(result, 65.0, "50 × 1.3 = 65")

## T02: 单条固定值buff
func test_02_add_single_flat() -> void:
	print("[T02] 单条固定值buff: 基础50 +15")
	buff_mgr.clear_all()
	buff_mgr.add_buff("attack_power", "flat", 15.0, 0.0, "test02")
	var result: float = buff_mgr.calc_stat(50.0, "attack_power")
	assert_eq(result, 65.0, "50 + 15 = 65")

## T03: 多条百分比连乘
func test_03_multiple_pct() -> void:
	print("[T03] 多条百分比: 基础50 +30% -20%")
	buff_mgr.clear_all()
	buff_mgr.add_buff("attack_power", "pct", 0.3, 0.0, "test03a")
	buff_mgr.add_buff("attack_power", "pct", -0.2, 0.0, "test03b")
	var result: float = buff_mgr.calc_stat(50.0, "attack_power")
	assert_eq(result, 52.0, "50 × 1.3 × 0.8 = 52")

## T04: 百分比+固定值混合
func test_04_pct_and_flat_combined() -> void:
	print("[T04] 混合: 基础50 +30% -20% +10固定")
	buff_mgr.clear_all()
	buff_mgr.add_buff("attack_power", "pct", 0.3, 0.0, "test04a")
	buff_mgr.add_buff("attack_power", "pct", -0.2, 0.0, "test04b")
	buff_mgr.add_buff("attack_power", "flat", 10.0, 0.0, "test04c")
	var result: float = buff_mgr.calc_stat(50.0, "attack_power")
	assert_eq(result, 62.0, "50 × 1.3 × 0.8 + 10 = 62")

## T05: 负值buff（减益）
func test_05_negative_buff() -> void:
	print("[T05] 负值: 基础100 -30固定")
	buff_mgr.clear_all()
	buff_mgr.add_buff("defense", "flat", -30.0, 0.0, "test05")
	var result: float = buff_mgr.calc_stat(100.0, "defense")
	assert_eq(result, 70.0, "100 + (-30) = 70")

## T06: 按ID移除
func test_06_remove_by_id() -> void:
	print("[T06] 按ID移除")
	buff_mgr.clear_all()
	var bid: String = buff_mgr.add_buff("speed", "pct", 0.5, 0.0, "test06")
	var before: float = buff_mgr.calc_stat(200.0, "speed")
	assert_eq(before, 300.0, "移除前 200×1.5=300")
	buff_mgr.remove_buff(bid)
	var after: float = buff_mgr.calc_stat(200.0, "speed")
	assert_eq(after, 200.0, "移除后 200")

## T07: 按来源批量移除
func test_07_remove_by_source() -> void:
	print("[T07] 按来源批量移除")
	buff_mgr.clear_all()
	buff_mgr.add_buff("speed", "pct", 0.3, 0.0, "source_A")
	buff_mgr.add_buff("speed", "flat", 20.0, 0.0, "source_A")
	buff_mgr.add_buff("speed", "pct", 0.1, 0.0, "source_B")
	assert_eq(buff_mgr.get_buff_count(), 3, "共3条buff")
	buff_mgr.remove_buffs_by_source("source_A")
	assert_eq(buff_mgr.get_buff_count(), 1, "移除source_A后剩1条")
	var result: float = buff_mgr.calc_stat(200.0, "speed")
	assert_eq(result, 220.0, "200×1.1=220 (只剩source_B)")

## T08: 持续时间到期
func test_08_duration_expire() -> void:
	print("[T08] 持续时间到期自动移除")
	buff_mgr.clear_all()
	buff_mgr.add_buff("resilience", "pct", 0.5, 2.0, "test08")
	assert_eq(buff_mgr.get_buff_count(), 1, "到期前1条")
	buff_mgr.process_buffs(1.0)
	assert_eq(buff_mgr.get_buff_count(), 1, "1秒后仍在")
	buff_mgr.process_buffs(1.5)  # total 2.5s > 2.0s
	assert_eq(buff_mgr.get_buff_count(), 0, "2.5秒后已过期移除")
	var result: float = buff_mgr.calc_stat(50.0, "resilience")
	assert_eq(result, 50.0, "到期后恢复基础值50")

## T09: 永久buff（duration=0）
func test_09_permanent_buff() -> void:
	print("[T09] 永久buff(duration=0)不自动过期")
	buff_mgr.clear_all()
	buff_mgr.add_buff("attack_power", "flat", 10.0, 0.0, "test09")
	buff_mgr.process_buffs(999.0)
	assert_eq(buff_mgr.get_buff_count(), 1, "999秒后仍在")
	var result: float = buff_mgr.calc_stat(50.0, "attack_power")
	assert_eq(result, 60.0, "50+10=60")

## T10: 清空所有
func test_10_clear_all() -> void:
	print("[T10] 清空所有")
	buff_mgr.clear_all()
	buff_mgr.add_buff("attack_power", "pct", 0.5, 0.0, "a")
	buff_mgr.add_buff("defense", "flat", 20.0, 0.0, "b")
	buff_mgr.add_buff("speed", "pct", 0.3, 0.0, "c")
	assert_eq(buff_mgr.get_buff_count(), 3, "清空前3条")
	buff_mgr.clear_all()
	assert_eq(buff_mgr.get_buff_count(), 0, "清空后0条")

## T11: 白名单拒绝非法属性
func test_11_whitelist_reject() -> void:
	print("[T11] 白名单拒绝非法属性")
	buff_mgr.clear_all()
	var bid: String = buff_mgr.add_buff("invalid_stat", "pct", 0.5, 0.0, "test11")
	assert_true(bid == "", "非法属性返回空ID")
	assert_eq(buff_mgr.get_buff_count(), 0, "未添加任何buff")

## T12: 无buff时计算返回基础值
func test_12_empty_calc() -> void:
	print("[T12] 无buff时返回基础值")
	buff_mgr.clear_all()
	var result: float = buff_mgr.calc_stat(75.0, "attack_power")
	assert_eq(result, 75.0, "无buff = 基础值75")

## T13: 信号正确发射
func test_13_signal_emit() -> void:
	print("[T13] 信号发射检测")
	buff_mgr.clear_all()
	var added_stat := ""
	var removed_stat := ""
	var expired_stat := ""
	buff_mgr.buff_added.connect(func(_bid, stat, _type, _val): added_stat = stat)
	buff_mgr.buff_removed.connect(func(_bid, stat): removed_stat = stat)
	buff_mgr.buff_expired.connect(func(_bid, stat): expired_stat = stat)

	var bid: String = buff_mgr.add_buff("defense", "flat", 10.0, 0.0, "test13")
	assert_true(added_stat == "defense", "buff_added信号发射，stat=defense")

	buff_mgr.remove_buff(bid)
	assert_true(removed_stat == "defense", "buff_removed信号发射，stat=defense")

	buff_mgr.add_buff("speed", "pct", 0.2, 0.5, "test13b")
	buff_mgr.process_buffs(1.0)
	assert_true(expired_stat == "speed", "buff_expired信号发射，stat=speed")

	# 断开信号避免影响后续测试
	buff_mgr.buff_added.disconnect_all()
	buff_mgr.buff_removed.disconnect_all()
	buff_mgr.buff_expired.disconnect_all()

## T14: 多属性互不干扰
func test_14_multiple_stats() -> void:
	print("[T14] 多属性互不干扰")
	buff_mgr.clear_all()
	buff_mgr.add_buff("attack_power", "pct", 0.5, 0.0, "a")
	buff_mgr.add_buff("defense", "flat", 20.0, 0.0, "b")
	buff_mgr.add_buff("speed", "pct", -0.3, 0.0, "c")

	assert_eq(buff_mgr.calc_stat(50.0, "attack_power"), 75.0, "攻击 50×1.5=75")
	assert_eq(buff_mgr.calc_stat(40.0, "defense"), 60.0, "防御 40+20=60")
	assert_eq(buff_mgr.calc_stat(200.0, "speed"), 140.0, "速度 200×0.7=140")
	assert_eq(buff_mgr.calc_stat(50.0, "resilience"), 50.0, "韧性 无buff=50")

## T15: 基础值为0时的计算
func test_15_zero_base_value() -> void:
	print("[T15] 基础值=0时的计算")
	buff_mgr.clear_all()
	buff_mgr.add_buff("attack_power", "pct", 0.5, 0.0, "test15")
	buff_mgr.add_buff("attack_power", "flat", 10.0, 0.0, "test15")
	var result: float = buff_mgr.calc_stat(0.0, "attack_power")
	assert_eq(result, 10.0, "0×1.5+10=10 (pct对0无效，flat有效)")
