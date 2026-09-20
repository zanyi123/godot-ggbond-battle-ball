## P0-2 验收：AOE 目标筛选（headless 可跑）
## 筛选逻辑纯断言（注入名册 source，不依赖 autoload 时序）：
## 敌队存活近距目标入选；本人/超距/被击败/隐身排除；边界距离=半径入选
## 数据源接线（_get_all_players_array ← GameManager.team_a/b）由 grep 断言 + run_sim 集成覆盖
## 运行：Godot_console.exe --headless --script res://scripts/test3d/regression/test_aoe_targets.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0


## 轻量球员桩：满足筛选所需的 team/is_defeated/is_status_active/global_position
class StubPlayer extends CharacterBody2D:
	var team: String = "b"
	var is_defeated: bool = false
	func is_status_active(_s: String) -> bool:
		return false


## 隐身桩
class StealthyPlayer extends StubPlayer:
	func is_status_active(_s: String) -> bool:
		return true


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== AOE 目标筛选测试 ==========\n")
	var ball = load("res://scripts/battle/ball.gd").new()
	root.add_child(ball)

	# 造球员：ally 我方；B1 敌队近距；B2 敌队超距；B3 敌队被击败；B4 敌队隐身
	var ally := StubPlayer.new(); ally.team = "a"; ally.position = Vector2(0, 0)
	var b1 := StubPlayer.new(); b1.team = "b"; b1.position = Vector2(50, 0)
	var b2 := StubPlayer.new(); b2.team = "b"; b2.position = Vector2(5000, 0)
	var b3 := StubPlayer.new(); b3.team = "b"; b3.position = Vector2(60, 0); b3.is_defeated = true
	var b4 := StealthyPlayer.new(); b4.team = "b"; b4.position = Vector2(70, 0)
	for n in [ally, b1, b2, b3, b4]:
		root.add_child(n)
	await process_frame

	# 名册（模拟 GameManager.team_a/b 合并结果）注入 source
	var roster: Array = [ally, b1, b2, b3, b4]
	var targets: Array = ball._collect_aoe_targets(ally, "b", 100.0, roster)
	_assert("敌队存活近距目标入选 (命中=1)", targets.size() == 1 and targets[0] == b1)
	_assert("我方本人不被炸", not ally in targets)
	_assert("超距目标排除", not b2 in targets)
	_assert("被击败目标排除", not b3 in targets)
	_assert("隐身目标排除", not b4 in targets)

	# 边界：距离恰等于半径仍入选
	var edge: Array = ball._collect_aoe_targets(ally, "b", 5000.0, [b2])
	_assert("距离=半径边界入选", edge.size() == 1 and edge[0] == b2)

	# 距离略超半径排除
	var near_edge: Array = ball._collect_aoe_targets(ally, "b", 49.0, [b1])
	_assert("距离略超半径排除", near_edge.is_empty())

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 全部通过！")
	quit(1 if _fail > 0 else 0)


func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)
