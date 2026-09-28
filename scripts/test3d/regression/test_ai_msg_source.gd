## 23-4 UI信号→AI个体消息源验收（主人裁 2026-09-28）：开关/订阅/三类消息/环形上限/解绑
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_ai_msg_source.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0

func _initialize() -> void:
	_run()

func _run() -> void:
	print("\n========== 23-4 AI消息源验收 ==========\n")
	for i in range(3):
		await process_frame
	var player: CharacterBody2D = load("res://scripts/battle/player.gd").new()
	player.team = "a"
	player.spirit_energy = 100.0
	root.add_child(player)
	await process_frame

	var hub: Node = load("res://scripts/systems/spirit_system/ai_msg_source.gd").new()
	root.add_child(hub)

	# ===== ① 开关：默认关=零订阅零消息 =====
	hub.start_tracking([player])
	await process_frame
	player.turn_on_light("heal_block", 3.0)
	await process_frame
	_assert("①: 默认关→不订阅不广播", hub.get_msgs().is_empty())
	hub.enabled = true
	hub.start_tracking([player])   # 重新订阅
	player.turn_off_light("heal_block")
	await process_frame
	_assert("①: 开启后状态变化→消息广播", hub.get_msgs("status_changed").size() >= 1)

	# ===== ② 三类消息：状态/印记/开关 =====
	hub.recent.clear()
	player.apply_mark("frost", 5, 6.0)
	player.apply_mark("frost", 5, 6.0)
	await process_frame
	var marks: Array[Dictionary] = hub.get_msgs("mark_changed")
	_assert("②: mark_changed→消息携带层数(2)", marks.size() >= 1 and int(marks[marks.size()-1]["data"]["count"]) == 2)
	player.open_toggle("t_msg", [], 1.0)
	await process_frame
	var toggles: Array[Dictionary] = hub.get_msgs("toggle_changed")
	_assert("②: toggle_changed→开消息(open=true)", toggles.size() >= 1 and bool(toggles[toggles.size()-1]["data"]["open"]) == true)
	player.close_toggle("t_msg")
	await process_frame
	_assert("②: 关闭→关消息", hub.get_msgs("toggle_changed").size() >= 2 and bool(hub.get_msgs("toggle_changed")[hub.get_msgs("toggle_changed").size()-1]["data"]["open"]) == false)

	# ===== ③ 环形日志上限 =====
	for i in range(80):
		player.apply_mark("loop", 3, 5.0)
		player.clear_mark("loop")
	await process_frame
	_assert("③: 环形日志≤上限64", hub.recent.size() <= 64)

	# ===== ④ 解绑：stop_tracking 后不再广播 =====
	hub.stop_tracking()
	hub.recent.clear()
	player.turn_on_light("heal_block", 2.0)
	await process_frame
	_assert("④: 解绑后零广播", hub.get_msgs("status_changed").is_empty())
	player.turn_off_light("heal_block")

	# ===== ⑤ 多球员：消息带 player_id 归属 =====
	var p2: CharacterBody2D = load("res://scripts/battle/player.gd").new()
	p2.team = "b"
	root.add_child(p2)
	await process_frame
	hub.start_tracking([player, p2])
	player.turn_on_light("heal_block", 2.0)
	p2.turn_on_light("heal_block", 2.0)
	await process_frame
	var last_two: Array = hub.get_msgs("status_changed")
	_assert("⑤: 多球员消息带归属 id", last_two.size() >= 2 \
		and int(last_two[last_two.size()-2]["player_id"]) == player.get_instance_id() \
		and int(last_two[last_two.size()-1]["player_id"]) == p2.get_instance_id())
	hub.stop_tracking()

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 AI 消息源全部通过！（默认关；显式开启后为 AI 个体提供状态/印记/开关消息流）")
	quit(1 if _fail > 0 else 0)

func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)
