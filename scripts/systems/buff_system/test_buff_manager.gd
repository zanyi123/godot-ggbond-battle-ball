## Buff堆栈独立测试
##
## 运行方式：
##   godot --path . --script scripts/systems/buff_system/test_buff_manager.gd
## 或在编辑器中打开 test_buff_manager.tscn 按 F6
##
## 全部通过输出：XX/XX PASS
## 失败会打印：❌ FAIL: 测试名 - 预期X 实际Y

extends SceneTree

var _pass_count: int = 0
var _fail_count: int = 0


func _init() -> void:
	print("\n========== Buff堆栈测试 ==========\n")

	test_single_mult_buff()
	test_single_flat_buff()
	test_mixed_buffs()
	test_multiple_mult()
	test_tick_expire()
	test_manual_remove()
	test_same_stat_multiple_flat()
	test_overwrite_same_id()
	test_different_stats()
	test_empty_no_buff()
	test_permanent_buff()
	test_tick_partial()

	_total()
	quit()


# ============================================================
# 测试用例
# ============================================================

func test_single_mult_buff() -> void:
	## 单个乘法buff
	var bm := BuffManager.new()
	bm.add_buff("b1", "attack", 1.3, 0.0, 5.0, "player_atk_up_pct")
	var result: float = bm.get_effective_value("attack", 50.0)
	_assert_eq("单个乘法buff(+30%)", result, 65.0)


func test_single_flat_buff() -> void:
	## 单个加法buff
	var bm := BuffManager.new()
	bm.add_buff("b1", "attack", 1.0, 10.0, 5.0, "player_atk_up_flat")
	var result: float = bm.get_effective_value("attack", 50.0)
	_assert_eq("单个加法buff(+10)", result, 60.0)


func test_mixed_buffs() -> void:
	## 混合：50 × (1.3 × 0.8) + 10 = 50 × 1.04 + 10 = 62
	var bm := BuffManager.new()
	bm.add_buff("b1", "attack", 1.3, 0.0, 5.0)
	bm.add_buff("b2", "attack", 0.8, 0.0, 3.0)
	bm.add_buff("b3", "attack", 1.0, 10.0, 4.0)
	var result: float = bm.get_effective_value("attack", 50.0)
	_assert_eq("混合叠加(乘×2+加)", result, 62.0)


func test_multiple_mult() -> void:
	## 多个乘法：1.3 × 0.8 → 50×1.04 = 52
	var bm := BuffManager.new()
	bm.add_buff("b1", "attack", 1.3, 0.0, 5.0)
	bm.add_buff("b2", "attack", 0.8, 0.0, 5.0)
	var result: float = bm.get_effective_value("attack", 50.0)
	_assert_eq("多个乘法叠加", result, 52.0)


func test_tick_expire() -> void:
	## 模拟过期：3秒后b1(+30%)过期，只剩b2(+10)
	var bm := BuffManager.new()
	bm.add_buff("b1", "attack", 1.3, 0.0, 3.0)  # 3秒后过期
	bm.add_buff("b2", "attack", 1.0, 10.0, 5.0)  # 5秒后过期

	# 过期前：50×1.3 + 10 = 75
	var before: float = bm.get_effective_value("attack", 50.0)
	_assert_eq("过期前", before, 75.0)

	# 模拟3秒tick
	bm.tick(3.0)

	# b1过期后：50 + 10 = 60
	var after: float = bm.get_effective_value("attack", 50.0)
	_assert_eq("过期后", after, 60.0)

	# buff数量应为1
	_assert_eq("过期后buff数", float(bm.get_buff_count()), 1.0)


func test_manual_remove() -> void:
	## 手动移除buff
	var bm := BuffManager.new()
	bm.add_buff("b1", "attack", 1.3, 0.0, 5.0)
	var before: float = bm.get_effective_value("attack", 50.0)
	_assert_eq("移除前", before, 65.0)

	var removed: bool = bm.remove_buff("b1")
	_assert_eq("移除返回true", float(removed), 1.0)

	var after: float = bm.get_effective_value("attack", 50.0)
	_assert_eq("移除后恢复基础值", after, 50.0)

	# 移除不存在的buff返回false
	var removed2: bool = bm.remove_buff("b1")
	_assert_eq("移除不存在返回false", float(removed2), 0.0)


func test_same_stat_multiple_flat() -> void:
	## 同属性多个加法：50 + 10 + 20 = 80
	var bm := BuffManager.new()
	bm.add_buff("b1", "attack", 1.0, 10.0, 5.0)
	bm.add_buff("b2", "attack", 1.0, 20.0, 5.0)
	var result: float = bm.get_effective_value("attack", 50.0)
	_assert_eq("多个加法叠加", result, 80.0)


func test_overwrite_same_id() -> void:
	## 同id覆盖：先+10，再+30 → 应该只剩+30
	var bm := BuffManager.new()
	bm.add_buff("b1", "attack", 1.0, 10.0, 5.0)
	bm.add_buff("b1", "attack", 1.0, 30.0, 5.0)  # 覆盖
	var result: float = bm.get_effective_value("attack", 50.0)
	_assert_eq("同id覆盖", result, 80.0)
	_assert_eq("覆盖后buff数", float(bm.get_buff_count()), 1.0)


func test_different_stats() -> void:
	## 不同属性互不干扰
	var bm := BuffManager.new()
	bm.add_buff("b1", "attack", 1.3, 0.0, 5.0)
	bm.add_buff("b2", "defense", 1.0, 15.0, 5.0)

	var atk: float = bm.get_effective_value("attack", 50.0)
	var def: float = bm.get_effective_value("defense", 30.0)

	_assert_eq("攻击独立", atk, 65.0)
	_assert_eq("防御独立", def, 45.0)


func test_empty_no_buff() -> void:
	## 无buff时返回基础值
	var bm := BuffManager.new()
	var result: float = bm.get_effective_value("attack", 50.0)
	_assert_eq("空buff返回基础值", result, 50.0)


func test_permanent_buff() -> void:
	## 永久buff（duration<=0）不会过期
	var bm := BuffManager.new()
	bm.add_buff("perm", "attack", 1.5, 0.0, -1.0)  # 永久
	bm.tick(999.0)  # 模拟超长时间
	var result: float = bm.get_effective_value("attack", 50.0)
	_assert_eq("永久buff不过期", result, 75.0)


func test_tick_partial() -> void:
	## 分帧tick，buff不会提前过期
	var bm := BuffManager.new()
	bm.add_buff("b1", "attack", 2.0, 0.0, 1.0)  # 1秒

	# tick 0.5秒两次 = 1秒
	bm.tick(0.5)
	_assert_eq("半帧后仍生效", bm.get_effective_value("attack", 50.0), 100.0)
	bm.tick(0.5)
	_assert_eq("完整1秒后过期", bm.get_effective_value("attack", 50.0), 50.0)


# ============================================================
# 辅助方法
# ============================================================

func _assert_eq(test_name: String, actual: float, expected: float) -> void:
	# 浮点比较，容差0.01
	if absf(actual - expected) < 0.01:
		_pass_count += 1
		print("  ✅ PASS: %s" % test_name)
	else:
		_fail_count += 1
		print("  ❌ FAIL: %s - 预期 %.2f 实际 %.2f" % [test_name, expected, actual])


func _total() -> void:
	var total: int = _pass_count + _fail_count
	print("\n========== 结果: %d/%d PASS ==========" % [_pass_count, total])
	if _fail_count > 0:
		print("⚠️  %d 个测试失败！" % _fail_count)
	else:
		print("🎉 全部通过！")
	print()
