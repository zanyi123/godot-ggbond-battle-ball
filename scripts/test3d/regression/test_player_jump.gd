## M3 验收测试：球员跳跃（headless 可跑）
## ① 起跳成功与耐力扣减（血量不受影响） ② 跳到顶点高度合理 ③ 落地归位
## ④ 落地冷却拦截 ⑤ 耐力不足禁跳+自动恢复 ⑥ 击退打断 ⑦ 击退/僵直中禁跳 ⑧ is_airborne 状态
## 运行：Godot_console.exe --headless res://scenes/test3d/test_player_jump.tscn
extends Node3D

var _fails: int = 0


func _ready() -> void:
	var arena_scene: PackedScene = load("res://scenes/battle/battle_arena.tscn")
	var arena = arena_scene.instantiate()
	add_child(arena)
	await get_tree().create_timer(1.5).timeout

	var p = arena.team_a_players[0]
	_report("球员存在", p != null, "")
	if p == null:
		print("[M3] RESULT: FAIL")
		get_tree().quit(1)
		return

	# 归零干扰源（本测试全部单帧同步驱动，不等物理帧）
	p._knockback_timer = 0.0
	p._stagger_timer = 0.0
	p.z_height = 0.0
	p.z_vel = 0.0
	p.is_jumping = false
	p._jump_cooldown_left = 0.0
	p.endurance = 100.0

	# ① 起跳成功 + 耐力扣减（血量 stamina 不参与跳跃）
	var endurance_before: float = p.endurance
	var stamina_before: float = p.stamina
	var jumped: bool = p.try_jump()
	_report("起跳成功", jumped and p.z_height > 0.0 and p.is_jumping,
		"z=%.2f vz=%.0f" % [p.z_height, p.z_vel])
	_report("耐力扣减8", absf(p.endurance - (endurance_before - 8.0)) < 0.001,
		"%.0f→%.0f" % [endurance_before, p.endurance])
	_report("血量stamina不受影响", absf(p.stamina - stamina_before) < 0.001,
		"%.0f→%.0f" % [stamina_before, p.stamina])

	# ② 顶点高度合理（理论≈80px，容差 60~90）
	var z_max: float = 0.0
	for i in range(120):
		p._step_jump_z(1.0 / 60.0)
		z_max = maxf(z_max, p.z_height)
	_report("顶点高度≈80px", z_max > 60.0 and z_max < 90.0, "z_max=%.1f" % z_max)

	# ③ 落地归位
	var landed: bool = false
	for i in range(120):
		p._step_jump_z(1.0 / 60.0)
		if p.z_height == 0.0 and p.z_vel == 0.0 and not p.is_jumping:
			landed = true
			break
	_report("落地归位", landed and not p.is_airborne(),
		"z=%.2f vz=%.1f airborne=%s" % [p.z_height, p.z_vel, str(p.is_airborne())])

	# ④ 落地后冷却内禁跳，清冷却后可再跳
	var blocked: bool = (not p.can_jump()) and (not p.try_jump())
	p._jump_cooldown_left = 0.0
	var retried: bool = p.try_jump()
	_report("冷却拦截→清零可再跳", blocked and retried,
		"blocked=%s retried=%s" % [str(blocked), str(retried)])

	# ⑤ 清理第二次跳跃，测耐力不足禁跳
	for i in range(240):
		p._step_jump_z(1.0 / 60.0)
	p._jump_cooldown_left = 0.0
	p.endurance = 1.0
	var poor_blocked: bool = (not p.can_jump()) and (not p.try_jump())
	_report("耐力不足禁跳", poor_blocked, "endurance=1 cost=8")

	# ⑤b 耐力自动恢复（12/s；恢复到 ≥8 即可再跳）
	p._regen_endurance(1.0)
	_report("耐力自动恢复12/s", absf(p.endurance - 13.0) < 0.001,
		"endurance=%.0f" % p.endurance)
	p.endurance = 100.0

	# ⑥ 击退打断：跳到空中后强制落地
	p.try_jump()
	for i in range(20):
		p._step_jump_z(1.0 / 60.0)
	var was_air: bool = p.is_airborne()
	p._interrupt_jump()
	_report("击退打断强制落地", was_air and p.z_height == 0.0 and not p.is_airborne(),
		"was_air=%s z=%.2f" % [str(was_air), p.z_height])

	# ⑦ 击退计时中禁跳
	p._knockback_timer = 0.5
	var kb_blocked: bool = not p.can_jump()
	p._knockback_timer = 0.0
	# ⑧ 僵直中禁跳
	p._stagger_timer = 0.5
	var stag_blocked: bool = not p.can_jump()
	p._stagger_timer = 0.0
	_report("击退/僵直中禁跳", kb_blocked and stag_blocked,
		"kb=%s stag=%s" % [str(kb_blocked), str(stag_blocked)])

	if _fails == 0:
		print("[M3] RESULT: PASS")
		get_tree().quit(0)
	else:
		print("[M3] RESULT: FAIL (fails=%d)" % _fails)
		get_tree().quit(1)


func _report(test_name: String, ok: bool, detail: String) -> void:
	if ok:
		print("[M3] ✓ %s %s" % [test_name, detail])
	else:
		_fails += 1
		print("[M3] ✗ %s %s" % [test_name, detail])
