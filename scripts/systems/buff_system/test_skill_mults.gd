## 折扣卡系统独立测试
##
## 运行方式：
##   godot --headless --script scripts/systems/buff_system/test_skill_mults.gd
##
## 测试：消耗折扣/CD折扣/效果倍率叠加/到期/覆盖/使用次数

extends SceneTree

var _pass_count: int = 0
var _fail_count: int = 0


func _init() -> void:
	print("\n========== 折扣卡系统测试 ==========\n")

	test_cost_single_discount()
	test_cost_increase()
	test_cost_stack()
	test_cost_expire()
	test_cd_single_discount()
	test_cd_expire()
	test_effect_single()
	test_effect_consume_reset()
	test_effect_diminishing()
	test_effect_mixed_mults()
	test_bonus_uses()
	test_default_no_cards()
	test_overwrite_same_id()
	test_manual_remove()

	_total()
	quit()


# ============================================================
# 测试用例
# ============================================================

func test_cost_single_discount() -> void:
	## 消耗打折 0.5
	var p := _make_player()
	p.add_skill_cost_mult("c1", 0.5, 5.0)
	_assert_eq("消耗打折×0.5", p.get_skill_cost_mult(), 0.5)


func test_cost_increase() -> void:
	## 消耗涨价 1.5
	var p := _make_player()
	p.add_skill_cost_mult("c1", 1.5, 5.0)
	_assert_eq("消耗涨价×1.5", p.get_skill_cost_mult(), 1.5)


func test_cost_stack() -> void:
	## 消耗叠加：1.5 × 0.5 = 0.75
	var p := _make_player()
	p.add_skill_cost_mult("c1", 1.5, 5.0)
	p.add_skill_cost_mult("c2", 0.5, 5.0)
	_assert_eq("消耗叠加×0.75", p.get_skill_cost_mult(), 0.75)


func test_cost_expire() -> void:
	## 消耗卡到期
	var p := _make_player()
	p.add_skill_cost_mult("c1", 0.5, 2.0)
	p._process_discount_cards(2.0)
	_assert_eq("消耗卡到期后=1.0", p.get_skill_cost_mult(), 1.0)


func test_cd_single_discount() -> void:
	## CD打折 0.5
	var p := _make_player()
	p.add_skill_cd_mult("cd1", 0.5, 5.0)
	_assert_eq("CD打折×0.5", p.get_skill_cd_mult(), 0.5)


func test_cd_expire() -> void:
	## CD卡到期
	var p := _make_player()
	p.add_skill_cd_mult("cd1", 0.5, 3.0)
	p._process_discount_cards(3.0)
	_assert_eq("CD卡到期后=1.0", p.get_skill_cd_mult(), 1.0)


func test_effect_single() -> void:
	## 单张效果倍率卡：2.0
	var p := _make_player()
	p.add_next_skill_mult(2.0)
	var result: float = p.get_and_consume_next_skill_mult()
	_assert_eq("单张双倍=2.0", result, 2.0)


func test_effect_consume_reset() -> void:
	## 消费后归1.0
	var p := _make_player()
	p.add_next_skill_mult(2.0)
	p.get_and_consume_next_skill_mult()
	var result: float = p.get_and_consume_next_skill_mult()
	_assert_eq("消费后=1.0", result, 1.0)


func test_effect_diminishing() -> void:
	## 两张相同1.5倍卡 → 1.5 + 1.5×0.1 = 1.65
	var p := _make_player()
	p.add_next_skill_mult(1.5)
	p.add_next_skill_mult(1.5)
	var result: float = p.get_and_consume_next_skill_mult()
	_assert_eq("两张1.5倍衰减=1.65", result, 1.65)


func test_effect_mixed_mults() -> void:
	## 两张不同倍率：2.0 + 0.5×0.1 = 2.05
	var p := _make_player()
	p.add_next_skill_mult(2.0)
	p.add_next_skill_mult(0.5)
	var result: float = p.get_and_consume_next_skill_mult()
	_assert_eq("2.0+0.5衰减=2.05", result, 2.05)

	## 三张：3.0 + 1.5×0.1 + 2.0×0.1 = 3.35
	var p2 := _make_player()
	p2.add_next_skill_mult(3.0)
	p2.add_next_skill_mult(1.5)
	p2.add_next_skill_mult(2.0)
	var result2: float = p2.get_and_consume_next_skill_mult()
	_assert_eq("三张衰减=3.35", result2, 3.35)


func test_bonus_uses() -> void:
	## 使用次数
	var p := _make_player()
	p.add_skill_bonus_uses("skill_1", 2)
	_assert_eq("次数=2", float(p.get_skill_bonus_uses("skill_1")), 2.0)
	p.add_skill_bonus_uses("skill_1", 1)
	_assert_eq("追加后=3", float(p.get_skill_bonus_uses("skill_1")), 3.0)
	_assert_eq("其他技能=0", float(p.get_skill_bonus_uses("skill_2")), 0.0)


func test_default_no_cards() -> void:
	## 无卡时默认值
	var p := _make_player()
	_assert_eq("无消耗卡=1.0", p.get_skill_cost_mult(), 1.0)
	_assert_eq("无CD卡=1.0", p.get_skill_cd_mult(), 1.0)
	_assert_eq("无效果卡=1.0", p.get_and_consume_next_skill_mult(), 1.0)


func test_overwrite_same_id() -> void:
	## 同id覆盖
	var p := _make_player()
	p.add_skill_cost_mult("c1", 0.5, 5.0)
	p.add_skill_cost_mult("c1", 0.3, 5.0)
	_assert_eq("消耗覆盖=0.3", p.get_skill_cost_mult(), 0.3)


func test_manual_remove() -> void:
	## 手动移除
	var p := _make_player()
	p.add_skill_cost_mult("c1", 0.5, 5.0)
	p.add_skill_cd_mult("cd1", 0.5, 5.0)

	var ok1: bool = p.remove_skill_cost_mult("c1")
	_assert_eq("移除消耗卡", float(ok1), 1.0)
	_assert_eq("消耗回到1.0", p.get_skill_cost_mult(), 1.0)

	var ok2: bool = p.remove_skill_cd_mult("cd1")
	_assert_eq("移除CD卡", float(ok2), 1.0)
	_assert_eq("CD回到1.0", p.get_skill_cd_mult(), 1.0)


# ============================================================
# 辅助方法
# ============================================================

func _make_player() -> CharacterBody2D:
	var p := CharacterBody2D.new()
	var script := GDScript.new()
	script.source_code = _get_player_code()
	script.reload()
	p.set_script(script)
	p.set("_skill_cost_mults", {})
	p.set("_skill_cd_mults", {})
	p.set("_next_skill_mults", [])
	p.set("_skill_bonus_uses", {})
	return p


func _get_player_code() -> String:
	return '''
extends CharacterBody2D

var _skill_cost_mults: Dictionary = {}
var _skill_cd_mults: Dictionary = {}
var _next_skill_mults: Array = []
var _skill_bonus_uses: Dictionary = {}

func add_skill_cost_mult(id: String, mult: float, duration: float) -> void:
	_skill_cost_mults[id] = {"mult": mult, "remaining": duration}

func get_skill_cost_mult() -> float:
	var m: float = 1.0
	for id in _skill_cost_mults:
		m *= _skill_cost_mults[id].get("mult", 1.0)
	return m

func add_skill_cd_mult(id: String, mult: float, duration: float) -> void:
	_skill_cd_mults[id] = {"mult": mult, "remaining": duration}

func get_skill_cd_mult() -> float:
	var m: float = 1.0
	for id in _skill_cd_mults:
		m *= _skill_cd_mults[id].get("mult", 1.0)
	return m

func add_next_skill_mult(mult: float) -> void:
	_next_skill_mults.append(mult)

func get_and_consume_next_skill_mult() -> float:
	if _next_skill_mults.is_empty():
		return 1.0
	var total: float = 0.0
	for i in range(_next_skill_mults.size()):
		var m: float = _next_skill_mults[i]
		if i == 0:
			total = m
		else:
			total += m * 0.1
	_next_skill_mults.clear()
	return total

func remove_skill_cost_mult(id: String) -> bool:
	return _skill_cost_mults.erase(id)

func remove_skill_cd_mult(id: String) -> bool:
	return _skill_cd_mults.erase(id)

func add_skill_bonus_uses(skill_id: String, bonus: int) -> void:
	if not _skill_bonus_uses.has(skill_id):
		_skill_bonus_uses[skill_id] = 0
	_skill_bonus_uses[skill_id] += bonus

func get_skill_bonus_uses(skill_id: String) -> int:
	return _skill_bonus_uses.get(skill_id, 0)

func _process_discount_cards(delta: float) -> void:
	_tick_mult_dict(_skill_cost_mults, delta)
	_tick_mult_dict(_skill_cd_mults, delta)

func _tick_mult_dict(d: Dictionary, delta: float) -> void:
	var to_remove: PackedStringArray = []
	for id in d:
		d[id]["remaining"] = d[id].get("remaining", 0.0) - delta
		if d[id].get("remaining", 0.0) <= 0.0:
			to_remove.append(id)
	for id in to_remove:
		d.erase(id)
'''


func _assert_eq(test_name: String, actual: float, expected: float) -> void:
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
