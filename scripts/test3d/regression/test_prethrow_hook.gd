## 22-B S3 消费验证：投球窗口事件钩子——持球<0.5s 短窗口出手对照（诊断仪模式，11/14号先例）
## 工单：22_深度优化路线 22-B（P2 抢球秒投）；运行：
##   Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_prethrow_hook.gd
## 纪律：开关注入走真实 switches.json 改写+还原（本套件专属键 event_hook_priority，结束还原全关）
extends SceneTree

const RealSpiritSys = preload("res://scripts/systems/spirit_system/spirit_system_manager.gd")
const SWITCHES := "res://data/systems/spirit_ai/switches.json"

var _pass: int = 0
var _fail: int = 0


class StubPlayer extends CharacterBody2D:
	var character_id: String = ""
	var team: String = "a"
	var is_defeated: bool = false
	var is_penalized: bool = false
	var is_carrying_ball: bool = false
	var facing_direction: Vector2 = Vector2.RIGHT
	var stamina: float = 100.0
	var max_stamina: float = 100.0
	var spirit_energy: float = 100.0
	var max_spirit_energy: float = 100.0
	var attack_power: float = 10.0
	var defense: float = 10.0
	var speed: float = 10.0
	var resilience: float = 10.0


class StubBall extends Area2D:
	signal ball_caught(player)
	var is_active: bool = false
	var owner_player: CharacterBody2D = null
	var ball_direction: Vector2 = Vector2.RIGHT
	var ball_speed: float = 400.0


class StubSpiritSystem extends RealSpiritSys:
	var calls: Array = []
	func use_skill(player_id: int, skill_id: String, target_data: Dictionary = {}) -> bool:
		calls.append(skill_id)
		return true
	func get_skill_cooldown(player_id: int, skill_id: String) -> float:
		return 0.0


func _initialize() -> void:
	_run()


func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  ✓ " + name)
	else:
		_fail += 1
		print("  ✗ " + name)


func _write_flag(flag: bool) -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(SWITCHES))
	d["event_hook_priority"] = flag
	var f = FileAccess.open(SWITCHES, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "\t"))
	f.close()


func _make_sam(ball: StubBall, sys: StubSpiritSystem, p: StubPlayer, profile) -> Node:
	var sam = load("res://scripts/battle/spirit_ai_manager.gd").new()
	sam.spirit_system = sys
	sam.ball_node = ball   # 钩子路径不依赖 battle_manager（决策链对其全空安全）
	var analysis := {
		"skill_id": "skill_e2e_ball_boost", "skill_data": {"id": "skill_e2e_ball_boost",
			"type": "active", "energy_cost": 20, "tags": ["ball_dmg_up_pct"], "tag_params": {"ball_dmg_up_pct": {"value": 30.0}}},
		"tags": ["on_ball"] as Array[String], "raw_tags": ["ball_dmg_up_pct"] as Array[String],
		"has_ball_tag": true, "has_player_tag": false, "has_field_tag": false,
		"base_value": 60.0, "intents": {"attack": 0.8, "defense": 0.0, "support": 0.0, "control": 0.0},
		"primary_intent": "attack", "synergy_level": "low", "synergy_bonus": 1.0,
	}
	var sad_arr: Array[Dictionary] = [{
		"player": p, "profile": profile, "skill_think_timer": 0.0,
		"skill_decide_count": 0, "skill_exec_count": 0, "mistake_hold": {},
		"ai_input_attached": true, "last_skill_use_time": 0.0,
		"player_analysis": {}, "skills_analysis": [analysis],
	}]
	sam.spirit_ai_data = sad_arr
	return sam


func _run() -> void:
	print("\n========== 22-B S3：投球窗口事件钩子消费验证 ==========\n")
	for i in range(3):
		await process_frame
	var watchdog := create_timer(60.0).timeout.connect(func() -> void:
		print("❌ WATCHDOG 超时")
		quit(3))
	var profile = load("res://scripts/battle/ai_profile.gd").new()
	profile.skill_mistake_chance = 0.0   # 诊断确定性：排除失误骰干扰（出厂0.15）

	# ===== 场景：抢球瞬间（持球 0 秒，轮询窗口未到）=====
	var catcher: StubPlayer = StubPlayer.new()
	catcher.character_id = "t_catcher"
	catcher.team = "a"
	root.add_child(catcher)
	var ball: StubBall = StubBall.new()
	root.add_child(ball)
	var sys: StubSpiritSystem = StubSpiritSystem.new()

	# --- 钩子关（默认）：ball_caught 不触发立即评估 ---
	_write_flag(false)
	var sam_off: Node = _make_sam(ball, sys, catcher, profile)
	root.add_child(sam_off)
	catcher.is_carrying_ball = true
	ball.ball_caught.emit(catcher)
	await process_frame
	_check((sys.calls as Array).is_empty(), "H1 钩子关：持球开始不触发立即评估（轮询旧路径逐位）")
	sam_off.queue_free()

	# --- 钩子开：持球开始瞬间立即评估（出手）---
	_write_flag(true)
	var sys2: StubSpiritSystem = StubSpiritSystem.new()
	var sam_on: Node = _make_sam(ball, sys2, catcher, profile)
	root.add_child(sam_on)
	catcher.is_carrying_ball = true   # ball_caught 语义=已持球（决策前提）
	sam_on._ensure_catch_hook()      # 建立钩子连接（开关开）
	ball.ball_caught.emit(catcher)   # 抢球瞬间事件
	await process_frame
	_check(not (sys2.calls as Array).is_empty(), "H2 钩子开：持球开始瞬间立即出手（P2 短窗口闭合） 实际出手=%s" % str(sys2.calls))
	# 轮询相位重置（防同窗双评）：think_timer 归零
	var sad: Dictionary = sam_on.spirit_ai_data[0]
	_check(is_equal_approx(float(sad.get("skill_think_timer", 1.0)), 0.0), "H3 立即评估后轮询相位重置")
	sam_on.queue_free()
	_write_flag(false)

	print("\n========== 结果：%d 通过 / %d 失败 ==========" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
