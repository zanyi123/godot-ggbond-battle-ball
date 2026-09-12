## M1 验收测试：球的弹道物理（headless 可跑）
## ① 开关默认开 ② 重力下落 ③ 落地弹跳计数 ④ 弹跳耗尽贴地 ⑤ 弧线=技能接管
## ⑥ 直行+无标签=弹道 ⑦ 关开关=零积分（旧行为）⑧ 弹性 e 语义（天然基准+场地加成）
## 运行：Godot_console.exe --headless res://scenes/test3d/test_ballistic_ball.tscn
extends Node3D

var _fails: int = 0


func _ready() -> void:
	var arena_scene: PackedScene = load("res://scenes/battle/battle_arena.tscn")
	var arena = arena_scene.instantiate()
	add_child(arena)
	await get_tree().create_timer(1.5).timeout

	var ball = arena.ball_node
	_report("球存在", ball != null, "")
	if ball == null:
		print("[M1] RESULT: FAIL")
		get_tree().quit(1)
		return

	# 摘出对局干扰：本测试全部单帧同步驱动 _step，不等物理帧
	ball.is_active = false
	ball.owner_player = null
	ball.trajectory_type = "straight"

	# ① 开关默认开启
	_report("开关默认开启", ball.use_ballistic_physics == true, str(ball.use_ballistic_physics))

	# ② 重力下落：静止释放后 z 下降、vz 为负
	ball.ball_z = 55.0
	ball.ball_z_vel = 0.0
	ball._step_ballistic_z(0.1)
	_report("重力使z下降", ball.ball_z < 55.0 and ball.ball_z_vel < 0.0,
		"z=%.1f vz=%.1f" % [ball.ball_z, ball.ball_z_vel])

	# ③ 落地弹跳：反复步进直到第一次反弹（vz 变向上、计数>=1）
	var bounced: bool = false
	for i in range(600):
		ball._step_ballistic_z(1.0 / 60.0)
		if ball.bounce_count >= 1 and ball.ball_z_vel > 0.0:
			bounced = true
			break
	_report("落地弹跳(计数>=1,vz向上)", bounced,
		"count=%d z=%.1f vz=%.1f" % [ball.bounce_count, ball.ball_z, ball.ball_z_vel])

	# ④ 弹跳衰减→贴地：e=0.5 时覆盖衰减分支（默认 e=1.0 永不衰减）
	ball.bounce_coefficient = 0.5
	ball.ball_z = 55.0
	ball.ball_z_vel = 0.0
	ball.bounce_count = 0
	var settled: bool = false
	var z_under: bool = false
	for i in range(1200):
		ball._step_ballistic_z(1.0 / 60.0)
		if ball.ball_z < 0.0:
			z_under = true
		if ball.bounce_count > 0 and ball.ball_z <= 0.0 and ball.ball_z_vel == 0.0:
			settled = true
			break
	_report("弹跳耗尽贴地(e=0.5)", settled and not z_under,
		"count=%d z=%.2f vz=%.1f" % [ball.bounce_count, ball.ball_z, ball.ball_z_vel])

	# ④b 默认 e=1.0 完全反弹：持续弹跳不贴地（碰碰球）
	ball.bounce_coefficient = 1.0
	ball.ball_z = 55.0
	ball.ball_z_vel = 0.0
	ball.bounce_count = 0
	var bounce_kept: bool = true
	for i in range(600):
		ball._step_ballistic_z(1.0 / 60.0)
		if ball.ball_z_vel == 0.0 and ball.ball_z <= 0.0:
			bounce_kept = false
			break
	_report("完全反弹永不衰减(e=1.0)", bounce_kept and ball.bounce_count >= 1,
		"count=%d z=%.1f vz=%.1f" % [ball.bounce_count, ball.ball_z, ball.ball_z_vel])

	# ⑤ 弧线=技能接管（技能轨迹无视物理）
	ball.trajectory_type = "arc"
	_report("弧线=技能接管", ball._is_skill_controlled() == true, str(ball.trajectory_type))

	# ⑥ 直行+无标签=普通弹道球
	ball.trajectory_type = "straight"
	_report("直行+无标签=弹道", ball._is_skill_controlled() == false, "")

	# ⑦ 关开关：单步函数直接 no-op（旧版恒高直飞行为）
	ball.use_ballistic_physics = false
	ball.ball_z = 55.0
	ball.ball_z_vel = 0.0
	ball._step_ballistic_z(0.1)
	_report("关开关=零z积分", ball.ball_z == 55.0 and ball.ball_z_vel == 0.0,
		"z=%.1f vz=%.1f" % [ball.ball_z, ball.ball_z_vel])
	ball.use_ballistic_physics = true

	# ⑧ 弹性 e 语义
	ball.bounce_coefficient = 1.0
	var e_natural: float = ball._get_effective_bounce_e()
	_report("天然弹性默认1.0(完全反弹)", absf(e_natural - 1.0) < 0.001, "e=%.2f" % e_natural)

	ball.bounce_coefficient = 0.0
	var e_zero: float = ball._get_effective_bounce_e()
	_report("球e=0可完全禁弹", e_zero == 0.0, "e=%.2f" % e_zero)

	var fp = arena.get_node_or_null("FieldPhysicsManager")
	if fp:
		ball.bounce_coefficient = 1.0
		fp.set_bounciness(0.3, "test_m1")
		var e_field: float = ball._get_effective_bounce_e()
		_report("场地弹性加成封顶(1.0+0.3=1.0)", absf(e_field - 1.0) < 0.001, "e=%.2f" % e_field)
		fp.restore_bounciness()
	else:
		_report("场地弹性加成封顶(1.0+0.3=1.0)", false, "FieldPhysicsManager 未找到")

	if _fails == 0:
		print("[M1] RESULT: PASS")
		get_tree().quit(0)
	else:
		print("[M1] RESULT: FAIL (fails=%d)" % _fails)
		get_tree().quit(1)


func _report(test_name: String, ok: bool, detail: String) -> void:
	if ok:
		print("[M1] ✓ %s %s" % [test_name, detail])
	else:
		_fails += 1
		print("[M1] ✗ %s %s" % [test_name, detail])
