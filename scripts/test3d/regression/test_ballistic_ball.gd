## M1+M2 验收测试：球的弹道物理 + 蓝墙反弹（headless 可跑）
## ① 弹道默认关（球暂不落地=旧观感，框架保留） ② 开启后重力下落 ③ 落地弹跳
## ④ e=0.5 衰减贴地 / ④b e=1.0 完全反弹 ⑤ 弧线=技能接管 ⑥ 直行=弹道
## ⑦ 关开关=零积分 ⑧ 弹性 e 语义 ⑨ 蓝墙反弹（默认开/四向反射/切向保持/开关）
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
		print("[M2] RESULT: FAIL")
		get_tree().quit(1)
		return

	# 摘出对局干扰：本测试全部单帧同步驱动，不等物理帧
	ball.is_active = false
	ball.owner_player = null
	ball.trajectory_type = "straight"

	# ① 弹道默认关闭（飞行球暂不落地）
	_report("弹道默认关闭", ball.use_ballistic_physics == false, str(ball.use_ballistic_physics))
	# ⑨a 蓝墙反弹默认开启
	_report("墙反弹默认开启", ball.use_wall_bounce == true, str(ball.use_wall_bounce))

	# === 显式开启弹道，驱动积分函数 ===
	ball.use_ballistic_physics = true

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
		fp.set_bounciness(0.3, "test_m2")
		var e_field: float = ball._get_effective_bounce_e()
		_report("场地弹性加成封顶(1.0+0.3=1.0)", absf(e_field - 1.0) < 0.001, "e=%.2f" % e_field)
		fp.restore_bounciness()
	else:
		_report("场地弹性加成封顶(1.0+0.3=1.0)", false, "FieldPhysicsManager 未找到")

	# ⑨ 蓝墙反弹（边界=3D蓝墙实测 ±650/±390；帧间越界检测：球心越过界线才夹回反射）
	ball.ball_direction = Vector2(-1, 0)
	ball.global_position = Vector2(-652, 0)
	ball._bounce_off_walls()
	_report("撞左墙夹回+反射(±650)", ball.global_position.x == -650.0 and ball.ball_direction.x > 0.0,
		"x=%.0f dx=%.2f" % [ball.global_position.x, ball.ball_direction.x])

	ball.ball_direction = Vector2(1, 0)
	ball.global_position = Vector2(652, 0)
	ball._bounce_off_walls()
	_report("撞右墙夹回+反射", ball.global_position.x == 650.0 and ball.ball_direction.x < 0.0,
		"x=%.0f dx=%.2f" % [ball.global_position.x, ball.ball_direction.x])

	ball.ball_direction = Vector2(0, -1)
	ball.global_position = Vector2(0, -392)
	ball._bounce_off_walls()
	_report("撞上墙夹回+反射(±390)", ball.global_position.y == -390.0 and ball.ball_direction.y > 0.0,
		"y=%.0f dy=%.2f" % [ball.global_position.y, ball.ball_direction.y])

	ball.ball_direction = Vector2(-0.70710678, 0.70710678).normalized()
	ball.global_position = Vector2(-652, 0)
	ball._bounce_off_walls()
	_report("斜撞墙切向保持", ball.ball_direction.x > 0.6 and ball.ball_direction.y > 0.6,
		"d=%s" % str(ball.ball_direction))

	ball.ball_direction = Vector2(1, 0)
	ball.global_position = Vector2(0, 0)
	ball._bounce_off_walls()
	_report("场内不受影响", ball.ball_direction == Vector2(1, 0) and ball.global_position == Vector2(0, 0), "")

	ball.use_wall_bounce = false
	ball.ball_direction = Vector2(-1, 0)
	ball.global_position = Vector2(-652, 0)
	ball._bounce_off_walls()
	_report("关墙反弹开关=不动", ball.global_position.x == -652.0 and ball.ball_direction.x < 0.0, "")
	ball.use_wall_bounce = true

	# ⑩ M4 高度命中窗口（用场上真实球员验证）
	var p0 = arena.team_a_players[0]
	p0.z_height = 0.0
	ball.ball_z = 55.0
	_report("恒高球打得到站立者", ball._can_hit_target_at(p0) == true, "z=55 vs [0,50]")
	p0.z_height = 77.0
	_report("跳跃顶点躲开恒高球", ball._can_hit_target_at(p0) == false, "z=55 vs [77,127]")
	p0.z_height = 30.0
	_report("起跳中仍会被击中", ball._can_hit_target_at(p0) == true, "z=55 vs [30,80]")
	p0.z_height = 0.0

	# ⑪ M4 高抛轨迹
	ball.trajectory_type = "straight"
	ball.ball_z = 55.0
	ball.ball_z_vel = 0.0
	ball.bounce_count = 0
	ball.set_lob_trajectory()
	_report("lob非技能接管(吃重力)", ball._is_skill_controlled() == false and ball.ball_z_vel > 0.0,
		"vz=%.0f" % ball.ball_z_vel)
	var lob_rose: bool = false
	var lob_bounced: bool = false
	for i in range(600):
		ball._step_ballistic_z(1.0 / 60.0)
		if ball.ball_z > 90.0:
			lob_rose = true
		if ball.bounce_count >= 1:
			lob_bounced = true
			break
	_report("lob高抛升顶点+落地弹跳", lob_rose and lob_bounced,
		"count=%d z=%.1f" % [ball.bounce_count, ball.ball_z])

	if _fails == 0:
		print("[M2] RESULT: PASS")
		get_tree().quit(0)
	else:
		print("[M2] RESULT: FAIL (fails=%d)" % _fails)
		get_tree().quit(1)


func _report(test_name: String, ok: bool, detail: String) -> void:
	if ok:
		print("[M2] ✓ %s %s" % [test_name, detail])
	else:
		_fails += 1
		print("[M2] ✗ %s %s" % [test_name, detail])
