## 闹钟纸条系统独立测试
##
## 运行方式：
##   godot --headless --script scripts/systems/buff_system/test_tick_effects.gd
##
## 测试：持续恢复/持续掉血/叠加/上限/下限/无敌挡dot/到期/覆盖

extends SceneTree

var _pass_count: int = 0
var _fail_count: int = 0


func _init() -> void:
	print("\n========== 闹钟纸条系统测试 ==========\n")

	test_regen()
	test_dot()
	test_expire()
	test_stack_regen_and_dot()
	test_stamina_cap()
	test_stamina_floor()
	test_overwrite_same_id()
	test_manual_remove()
	test_invincible_blocks_dot()
	test_dot_expire_under_invincible()
	test_total_tick_rate()

	_total()
	quit()


# ============================================================
# 测试用例
# ============================================================

func test_regen() -> void:
	## 持续恢复：5/s, tick 1秒 → +5
	var p := _make_player()
	p.set("stamina", 50.0)
	p.set("max_stamina", 100.0)
	p.add_tick_effect("regen1", "regen", 5.0, 5.0)
	p._process_tick_effects(1.0)
	_assert_eq("持续恢复 5/s ×1s", p.get("stamina"), 55.0)


func test_dot() -> void:
	## 持续掉血：8/s, tick 1秒 → -8
	var p := _make_player()
	p.set("stamina", 50.0)
	p.add_tick_effect("dot1", "dot", 8.0, 3.0)
	p._process_tick_effects(1.0)
	_assert_eq("持续掉血 8/s ×1s", p.get("stamina"), 42.0)


func test_expire() -> void:
	## 到期停止：regen 5/s, 2秒到期 → 纸条撕掉
	var p := _make_player()
	p.set("stamina", 50.0)
	p.set("max_stamina", 100.0)
	p.add_tick_effect("regen1", "regen", 5.0, 2.0)

	p._process_tick_effects(2.0)
	_assert_eq("2秒后stamina=60", p.get("stamina"), 60.0)
	_assert_eq("纸条已撕掉", float(p.has_tick_effect("regen1")), 0.0)

	# 再tick不应该继续恢复
	p._process_tick_effects(1.0)
	_assert_eq("过期后不再涨", p.get("stamina"), 60.0)


func test_stack_regen_and_dot() -> void:
	## 叠加：regen 5/s + dot 8/s → 净-3/s
	var p := _make_player()
	p.set("stamina", 50.0)
	p.set("max_stamina", 100.0)
	p.add_tick_effect("regen1", "regen", 5.0, 5.0)
	p.add_tick_effect("dot1", "dot", 8.0, 5.0)

	p._process_tick_effects(1.0)
	_assert_eq("叠加净效果 -3/s", p.get("stamina"), 47.0)


func test_stamina_cap() -> void:
	## 上限保护：stamina=98, regen 10/s → tick(1s) → 100
	var p := _make_player()
	p.set("stamina", 98.0)
	p.set("max_stamina", 100.0)
	p.add_tick_effect("regen1", "regen", 10.0, 5.0)

	p._process_tick_effects(1.0)
	_assert_eq("不超过max_stamina", p.get("stamina"), 100.0)


func test_stamina_floor() -> void:
	## 下限：stamina=5, dot 10/s → tick(1s) → 0, 击败
	var p := _make_player()
	p.set("stamina", 5.0)
	p.set("max_stamina", 100.0)
	p.set("is_defeated", false)
	# 模拟 _on_defeated：只标记 is_defeated
	p.add_tick_effect("dot1", "dot", 10.0, 5.0)

	p._process_tick_effects(1.0)
	_assert_eq("体力下限为0", p.get("stamina"), 0.0)
	_assert_eq("触发击败", float(p.get("is_defeated")), 1.0)


func test_overwrite_same_id() -> void:
	## 同id覆盖：先5/s，再10/s → 只剩10/s
	var p := _make_player()
	p.set("stamina", 50.0)
	p.set("max_stamina", 100.0)
	p.add_tick_effect("regen1", "regen", 5.0, 5.0)
	p.add_tick_effect("regen1", "regen", 10.0, 5.0)

	p._process_tick_effects(1.0)
	_assert_eq("覆盖后10/s", p.get("stamina"), 60.0)


func test_manual_remove() -> void:
	## 手动移除
	var p := _make_player()
	p.set("stamina", 50.0)
	p.set("max_stamina", 100.0)
	p.add_tick_effect("regen1", "regen", 10.0, 5.0)

	var ok: bool = p.remove_tick_effect("regen1")
	_assert_eq("移除返回true", float(ok), 1.0)

	p._process_tick_effects(1.0)
	_assert_eq("移除后不涨", p.get("stamina"), 50.0)


func test_invincible_blocks_dot() -> void:
	## 无敌挡dot：无敌灯亮 + dot → stamina不变，倒计时照跑
	var p := _make_player()
	p.set("stamina", 50.0)
	p.set("max_stamina", 100.0)
	p.set("is_defeated", false)
	p.turn_on_light("invincible", 5.0)
	p.add_tick_effect("dot1", "dot", 10.0, 3.0)

	p._process_tick_effects(1.0)
	_assert_eq("无敌挡dot: stamina不变", p.get("stamina"), 50.0)
	_assert_eq("dot纸条还在", float(p.has_tick_effect("dot1")), 1.0)

	# 倒计时照跑：再tick 2秒 → dot到期消失
	p._process_tick_effects(2.0)
	_assert_eq("dot到期消失", float(p.has_tick_effect("dot1")), 0.0)
	_assert_eq("无敌灯还在", float(p.is_status_active("invincible")), 1.0)


func test_dot_expire_under_invincible() -> void:
	## dot到期后无敌灯还在
	var p := _make_player()
	p.set("stamina", 50.0)
	p.set("max_stamina", 100.0)
	p.turn_on_light("invincible", 10.0)
	p.add_tick_effect("dot1", "dot", 10.0, 2.0)

	p._process_tick_effects(3.0)
	_assert_eq("dot消失后无敌还在", float(p.is_status_active("invincible")), 1.0)
	_assert_eq("stamina未受影响", p.get("stamina"), 50.0)


func test_total_tick_rate() -> void:
	## 查询总速率
	var p := _make_player()
	p.add_tick_effect("r1", "regen", 5.0, 5.0)
	p.add_tick_effect("r2", "regen", 3.0, 5.0)
	p.add_tick_effect("d1", "dot", 8.0, 5.0)

	_assert_eq("总regen速率", p.get_total_tick_rate("regen"), 8.0)
	_assert_eq("总dot速率", p.get_total_tick_rate("dot"), 8.0)


# ============================================================
# 辅助方法
# ============================================================

func _make_player() -> CharacterBody2D:
	var p := CharacterBody2D.new()
	var script := GDScript.new()
	script.source_code = _get_player_code()
	script.reload()
	p.set_script(script)
	p.set("_status_lights", {})
	p.set("_tick_effects", {})
	p.set("stamina", 100.0)
	p.set("max_stamina", 100.0)
	p.set("is_defeated", false)
	return p


func _get_player_code() -> String:
	return '''
extends CharacterBody2D

var stamina: float = 100.0
var max_stamina: float = 100.0
var is_defeated: bool = false

var _status_lights: Dictionary = {}
var _tick_effects: Dictionary = {}

const _CC_STATUSES: PackedStringArray = ["stunned", "silenced", "disarmed", "rooted"]

func is_status_active(status_name: String) -> bool:
	return _status_lights.has(status_name) and _status_lights[status_name].get("on", false)

func turn_on_light(status_name: String, duration: float, extra: Dictionary = {}) -> bool:
	if status_name in _CC_STATUSES:
		if is_status_active("cc_immune"):
			return false
	_status_lights[status_name] = {"on": true, "remaining": duration}
	for key in extra:
		_status_lights[status_name][key] = extra[key]
	return true

func turn_off_light(status_name: String) -> void:
	_status_lights.erase(status_name)

func add_tick_effect(id: String, type: String, rate: float, duration: float) -> void:
	_tick_effects[id] = {"type": type, "rate": rate, "remaining": duration}

func remove_tick_effect(id: String) -> bool:
	return _tick_effects.erase(id)

func has_tick_effect(id: String) -> bool:
	return _tick_effects.has(id)

func get_total_tick_rate(type: String) -> float:
	var total: float = 0.0
	for id in _tick_effects:
		if _tick_effects[id].get("type", "") == type:
			total += _tick_effects[id].get("rate", 0.0)
	return total

func _process_tick_effects(delta: float) -> void:
	var to_remove: PackedStringArray = []
	for id in _tick_effects:
		var effect: Dictionary = _tick_effects[id]
		var etype: String = effect.get("type", "")
		var rate: float = effect.get("rate", 0.0)
		if etype == "regen":
			stamina = minf(max_stamina, stamina + rate * delta)
		elif etype == "dot":
			if not is_status_active("invincible"):
				stamina = maxf(0.0, stamina - rate * delta)
				if stamina <= 0.0 and not is_defeated:
					is_defeated = true
		effect["remaining"] = effect.get("remaining", 0.0) - delta
		if effect.get("remaining", 0.0) <= 0.0:
			to_remove.append(id)
	for id in to_remove:
		_tick_effects.erase(id)
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
