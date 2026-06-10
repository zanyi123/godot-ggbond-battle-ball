## 状态灯系统独立测试
##
## 运行方式：
##   godot --headless --script scripts/systems/buff_system/test_status_lights.gd
## 或在编辑器中打开 test_status_lights.tscn 按 F6
##
## 测试内容：点灯/关灯/自动灭/免控拦截/易伤倍率/覆盖/独立

extends SceneTree

var _pass_count: int = 0
var _fail_count: int = 0


func _init() -> void:
	print("\n========== 状态灯系统测试 ==========\n")

	test_turn_on()
	test_turn_off()
	test_auto_expire()
	test_tick_partial()
	test_cc_immune_blocks_cc()
	test_cc_immune_allows_non_cc()
	test_vulnerable_multiplier()
	test_overwrite_same_light()
	test_different_lights_independent()
	test_turn_off_by_type()

	_total()
	quit()


# ============================================================
# 测试用例
# ============================================================

func test_turn_on() -> void:
	## 点灯后应该亮
	var p := _make_player()
	var ok: bool = p.turn_on_light("stunned", 2.0)
	_assert_eq("点灯返回true", float(ok), 1.0)
	_assert_eq("灯亮了", float(p.is_status_active("stunned")), 1.0)


func test_turn_off() -> void:
	## 手动关灯
	var p := _make_player()
	p.turn_on_light("silenced", 3.0)
	p.turn_off_light("silenced")
	_assert_eq("关灯后不亮", float(p.is_status_active("silenced")), 0.0)


func test_auto_expire() -> void:
	## 到期自动灭
	var p := _make_player()
	p.turn_on_light("disarmed", 2.0)
	_assert_eq("灭前灯亮", float(p.is_status_active("disarmed")), 1.0)

	# 模拟2秒tick（通过直接调内部方法）
	p._tick_status_lights(2.0)
	_assert_eq("到期后灯灭", float(p.is_status_active("disarmed")), 0.0)


func test_tick_partial() -> void:
	## 分帧tick，灯不会提前灭
	var p := _make_player()
	p.turn_on_light("rooted", 1.0)

	p._tick_status_lights(0.5)
	_assert_eq("半帧后仍亮", float(p.is_status_active("rooted")), 1.0)

	p._tick_status_lights(0.5)
	_assert_eq("完整1秒后灭", float(p.is_status_active("rooted")), 0.0)


func test_cc_immune_blocks_cc() -> void:
	## 免控灯亮时，控制灯点不上去
	var p := _make_player()
	p.turn_on_light("cc_immune", 4.0)

	var ok1: bool = p.turn_on_light("stunned", 2.0)
	var ok2: bool = p.turn_on_light("silenced", 2.0)
	var ok3: bool = p.turn_on_light("disarmed", 2.0)
	var ok4: bool = p.turn_on_light("rooted", 2.0)

	_assert_eq("免控挡眩晕", float(ok1), 0.0)
	_assert_eq("免控挡沉默", float(ok2), 0.0)
	_assert_eq("免控挡缴械", float(ok3), 0.0)
	_assert_eq("免控挡定身", float(ok4), 0.0)
	_assert_eq("眩晕没亮", float(p.is_status_active("stunned")), 0.0)


func test_cc_immune_allows_non_cc() -> void:
	## 免控灯不拦非控制灯（无敌、隐身等）
	var p := _make_player()
	p.turn_on_light("cc_immune", 4.0)

	var ok1: bool = p.turn_on_light("invincible", 2.0)
	var ok2: bool = p.turn_on_light("stealthed", 2.0)

	_assert_eq("免控不挡无敌", float(ok1), 1.0)
	_assert_eq("免控不挡隐身", float(ok2), 1.0)


func test_vulnerable_multiplier() -> void:
	## 易伤灯亮时，倍率存对
	var p := _make_player()
	p.turn_on_light("vulnerable", 3.0, {"multiplier": 1.8})

	var mult: float = p._status_lights["vulnerable"].get("multiplier", 1.0)
	_assert_eq("易伤倍率=1.8", mult, 1.8)


func test_overwrite_same_light() -> void:
	## 同一盏灯重复点，刷新时间
	var p := _make_player()
	p.turn_on_light("stunned", 2.0)
	p.turn_on_light("stunned", 5.0)  # 覆盖

	var remaining: float = p._status_lights["stunned"].get("remaining", 0.0)
	_assert_eq("覆盖后时间=5", remaining, 5.0)
	_assert_eq("灯仍亮", float(p.is_status_active("stunned")), 1.0)


func test_different_lights_independent() -> void:
	## 不同灯独立开关
	var p := _make_player()
	p.turn_on_light("stunned", 2.0)
	p.turn_on_light("silenced", 3.0)

	p.turn_off_light("stunned")
	_assert_eq("眩晕灭了", float(p.is_status_active("stunned")), 0.0)
	_assert_eq("沉默还亮", float(p.is_status_active("silenced")), 1.0)


func test_turn_off_by_type() -> void:
	## 批量关灯
	var p := _make_player()
	p.turn_on_light("stunned", 2.0)
	p.turn_on_light("silenced", 2.0)
	p.turn_on_light("invincible", 2.0)

	p.turn_off_lights_by_type(["stunned", "silenced"])
	_assert_eq("眩晕已关", float(p.is_status_active("stunned")), 0.0)
	_assert_eq("沉默已关", float(p.is_status_active("silenced")), 0.0)
	_assert_eq("无敌还在", float(p.is_status_active("invincible")), 1.0)


# ============================================================
# 辅助方法
# ============================================================

func _make_player() -> CharacterBody2D:
	## 用 CharacterBody2D + 动态挂脚本，绕过 Autoload 依赖
	var p := CharacterBody2D.new()
	var script := GDScript.new()
	script.source_code = _get_player_status_code()
	script.reload()
	p.set_script(script)
	p.set("_status_lights", {})
	return p


func _get_player_status_code() -> String:
	## 只包含状态灯相关代码的最小脚本，不依赖 DataManager
	return '''
extends CharacterBody2D

var _status_lights: Dictionary = {}

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

func turn_off_lights_by_type(light_names: PackedStringArray) -> void:
	for name_str in light_names:
		_status_lights.erase(name_str)

func _tick_status_lights(delta: float) -> void:
	var to_remove: PackedStringArray = []
	for status in _status_lights:
		var remaining: float = _status_lights[status].get("remaining", 0.0) - delta
		if remaining <= 0.0:
			to_remove.append(status)
		else:
			_status_lights[status]["remaining"] = remaining
	for status in to_remove:
		_status_lights.erase(status)
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
