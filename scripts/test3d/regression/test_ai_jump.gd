## M5 验收测试：AI 跳跃反应（躲敌球；headless 可跑）
## ① 时机窗内敌球来袭→起跳 ② 球不朝我→不跳 ③ 队友来球→不跳
## ④ 自己发的球→不跳 ⑤ 待接球→不跳 ⑥ 球太远→不跳 ⑦ 球太快(<0.22s)→不跳
## ⑧ 弹道不经过我→不跳 ⑨ 高飞球打不到→不跳 ⑩ 冷却中→不跳
## 运行：Godot_console.exe --headless res://scenes/test3d/test_ai_jump.tscn
extends Node3D

var _fails: int = 0
var _arena = null
var _ball = null
var _p_a = null


func _ready() -> void:
	var arena_scene: PackedScene = load("res://scenes/battle/battle_arena.tscn")
	_arena = arena_scene.instantiate()
	add_child(_arena)
	await get_tree().create_timer(1.5).timeout

	var ai = _arena.get_node_or_null("AIManager")
	if ai == null:
		for c in _arena.get_children():
			if c.get_script() and str(c.get_script().resource_path).contains("ai_manager"):
				ai = c
				break
	_report("AIManager 存在", ai != null, "")
	if ai == null:
		print("[M5] RESULT: FAIL")
		get_tree().quit(1)
		return

	var p_b = _arena.team_a_players[1]   # 队友（发球队友用）
	var attacker = _arena.team_b_players[0]
	_p_a = _arena.team_a_players[0]
	_ball = _arena.ball_node
	ai.ball_node = _ball  # 对局未开赛时 ai 内部缓存为 null，直接注入引用

	# ① 时机窗内敌球来袭 → 行为与概率模型一致（白盒断言）：
	# base=1.0、满血 → P_dodge=0.95（上限），跳 ⟺ 骰子 < 0.95
	# 先遍历 6 名球员找骰子<0.95 的组合（全截断概率 0.05^6≈0），保证正通路被真实执行
	_reset(attacker)
	_p_a.stamina = _p_a.max_stamina
	var brave_profile := AIProfile.new()
	brave_profile.jump_dodge_base = 1.0
	var dodger = _p_a
	for cand in _arena.team_a_players:
		if ai._dodge_roll(hash(str(cand.character_id)), _ball.flight_seq) < 0.95:
			dodger = cand
			break
	_p_a = dodger
	_reset(attacker)
	_p_a.stamina = _p_a.max_stamina
	var ap := {"player": _p_a, "team": "a", "profile": brave_profile}
	var roll: float = ai._dodge_roll(hash(str(_p_a.character_id)), _ball.flight_seq)
	ai._update_jump_reaction(ap)
	_report("时机窗内敌球→骰子通过则起跳", roll < 0.95 and _p_a.z_height > 0.0,
		"roll=%.4f z=%.2f" % [roll, _p_a.z_height])

	# ①b 概率门：base=0 → 必不跳（确定性骰子 ≥ 0 恒拦截）
	_reset(attacker)
	var coward_profile := AIProfile.new()
	coward_profile.jump_dodge_base = 0.0
	var ap2 := {"player": _p_a, "team": "a", "profile": coward_profile}
	ai._update_jump_reaction(ap2)
	_report("base=0概率门→必不跳", _p_a.z_height == 0.0, "")

	# ①c 确定性骰子：同参恒同值、∈[0,1)、不同输入可区分
	var r1: float = ai._dodge_roll(12345, 678)
	var r2: float = ai._dodge_roll(12345, 678)
	var r3: float = ai._dodge_roll(12346, 678)
	_report("骰子确定且∈[0,1)", r1 == r2 and r1 >= 0.0 and r1 < 1.0, "r=%.4f" % r1)
	_report("不同输入结果可变", r3 != r1, "r3=%.4f" % r3)

	# ② 球不朝我（反向飞）→ 不跳
	_reset(attacker)
	_ball.ball_direction = Vector2(-1, 0)
	ai._update_jump_reaction(ap)
	_report("球反向飞→不跳", _p_a.z_height == 0.0, "")

	# ③ 队友来球 → 不跳
	_reset(p_b)
	ai._update_jump_reaction(ap)
	_report("队友来球→不跳", _p_a.z_height == 0.0, "")

	# ④ 自己发的球 → 不跳
	_reset(_p_a)
	ai._update_jump_reaction(ap)
	_report("自己发的球→不跳", _p_a.z_height == 0.0, "")

	# ⑤ 待接球姿态 → 不跳（选择接球承担风险）
	_reset(attacker)
	_p_a.is_ready_to_catch = true
	ai._update_jump_reaction(ap)
	_report("待接球→不跳", _p_a.z_height == 0.0, "")

	# ⑥ 球太远 → 不跳
	_reset(attacker)
	_ball.global_position = Vector2(-400, 0)
	ai._update_jump_reaction(ap)
	_report("球太远→不跳", _p_a.z_height == 0.0, "")

	# ⑦ 球太快（t_arrive<0.22 躲不开）→ 不跳
	_reset(attacker)
	_ball.global_position = Vector2(-30, 0)  # 30/300=0.1s
	ai._update_jump_reaction(ap)
	_report("球太快→不跳", _p_a.z_height == 0.0, "")

	# ⑧ 弹道不经过我（平行飞过 80px 外）→ 不跳
	_reset(attacker)
	_p_a.global_position = Vector2(0, 80)
	ai._update_jump_reaction(ap)
	_report("弹道不经过我→不跳", _p_a.z_height == 0.0, "")

	# ⑨ 高飞球打不到站立的我 → 不跳
	_reset(attacker)
	_ball.ball_z = 120.0
	ai._update_jump_reaction(ap)
	_report("高飞球打不到→不跳", _p_a.z_height == 0.0, "")

	# ⑩ 冷却中 → 不跳
	_reset(attacker)
	_p_a._jump_cooldown_left = 1.0
	ai._update_jump_reaction(ap)
	_report("冷却中→不跳", _p_a.z_height == 0.0, "")

	if _fails == 0:
		print("[M5] RESULT: PASS")
		get_tree().quit(0)
	else:
		print("[M5] RESULT: FAIL (fails=%d)" % _fails)
		get_tree().quit(1)


func _reset(attacker) -> void:
	_p_a.z_height = 0.0
	_p_a.z_vel = 0.0
	_p_a.is_jumping = false
	_p_a._jump_cooldown_left = 0.0
	_p_a.endurance = 100.0
	_p_a.is_ready_to_catch = false
	_p_a._knockback_timer = 0.0
	_p_a._stagger_timer = 0.0
	_p_a.global_position = Vector2(0, 0)
	_ball.is_active = true
	_ball.owner_player = null
	_ball.attacker_player = attacker
	_ball.trajectory_type = "straight"
	_ball.ball_speed = 300.0
	_ball.ball_direction = Vector2(1, 0)
	_ball.global_position = Vector2(-100, 0)
	_ball.ball_z = 55.0


func _report(test_name: String, ok: bool, detail: String) -> void:
	if ok:
		print("[M5] ✓ %s %s" % [test_name, detail])
	else:
		_fails += 1
		print("[M5] ✗ %s %s" % [test_name, detail])
