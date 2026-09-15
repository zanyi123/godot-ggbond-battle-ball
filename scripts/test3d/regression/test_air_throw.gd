## P0+P1 验收测试：空中斜线发球 + 命中预览（headless 可跑）
## ① launch(start_z,pitch) 启用斜线且 z 随距离线性下降 ② 触地后贴地滑行
## ③ pitch=0 恒高（与旧行为一致） ④ 默认参数恒高不变（sim 基线零影响）
## ⑤ 命中预览：站立者在斜线落地段被标记 ⑥ 跳起者在下坠段被跳过
## ⑦ 路径外不标记 ⑧ 耗尽下坠：visual_fall 驱动 z 回 0
## 运行：Godot_console.exe --headless res://scenes/test3d/test_air_throw.tscn
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
		print("[AT] RESULT: FAIL")
		get_tree().quit(1)
		return

	ball.is_active = false
	ball.owner_player = null

	# ① 斜线：出手高 135（跳顶点 80+55）、俯角 -30°，z 随距离下降
	ball.launch(Vector2(0, 0), Vector2(1, 0), 20.0, 500.0, null, _empty_skills(), 135.0, -30.0)
	_report("斜线模式启用", ball.z_lerp_active and absf(ball.ball_z - 135.0) < 0.01,
		"z=%.1f" % ball.ball_z)
	var z_start: float = ball.ball_z
	ball.flight_distance = 100.0
	ball._step_z_lerp()
	var expect: float = 135.0 + 100.0 * tan(deg_to_rad(-30.0))
	_report("z随距离线性下降", absf(ball.ball_z - expect) < 0.1,
		"z=%.1f expect=%.1f" % [ball.ball_z, expect])

	# ② 触地贴地：飞过触地点后 z 钉 0
	ball.flight_distance = 500.0
	ball._step_z_lerp()
	_report("触地后贴地", ball.ball_z == 0.0, "z=%.1f" % ball.ball_z)

	# ③ pitch=0 恒高
	ball.launch(Vector2(0, 0), Vector2(1, 0), 20.0, 500.0, null, _empty_skills(), 135.0, 0.0)
	ball.flight_distance = 200.0
	ball._step_z_lerp()
	_report("pitch=0恒高", absf(ball.ball_z - 135.0) < 0.01, "z=%.1f" % ball.ball_z)

	# ④ 默认参数恒高（不变行为）
	ball.launch(Vector2(0, 0), Vector2(1, 0), 20.0, 500.0, null, _empty_skills())
	_report("默认恒高不变", ball.z_lerp_active == false and ball.ball_z == 55.0,
		"z=%.1f" % ball.ball_z)

	# ⑤⑥⑦ 命中预览（真实球员）
	var shooter = arena.team_a_players[0]
	var target = arena.team_b_players[0]
	var jumper = arena.team_b_players[1]
	shooter.global_position = Vector2(-200, 0)
	target.global_position = Vector2(0, 0)       # 路径上 200px 处
	jumper.global_position = Vector2(100, 0)     # 路径上 100px 处
	target.z_height = 0.0
	jumper.z_height = 77.0                       # 顶点，窗口 [77,127]

	var origin_z: float = 135.0
	# 斜线俯角按 135→0 落在 250px 处：tanφ = -135/250
	# shooter 在 (-200,0)：jumper 摆到路径 L=100（即 x=-100），z(100)=81 落在其窗口 [77,127]
	jumper.global_position = Vector2(-100, 0)
	var pitch: float = -rad_to_deg(atan2(135.0, 250.0))
	var players := [shooter, target, jumper]
	var hits: Array = ball.preview_path_hits(shooter.global_position, origin_z, pitch, 500.0, Vector2(1, 0), players)
	_report("下坠段穿过跳起者窗口(打空中目标)", hits.has(jumper),
		"z(100px)=%.0f" % (135.0 + 100.0 * tan(deg_to_rad(pitch))))
	_report("落地段站立者被标记", hits.has(target),
		"hits=%d" % hits.size())

	# ⑦ 路径外不标记
	target.global_position = Vector2(0, 200)  # 垂直偏出走廊
	hits = ball.preview_path_hits(shooter.global_position, origin_z, pitch, 500.0, Vector2(1, 0), players)
	_report("路径外不标记", not hits.has(target), "hits=%d" % hits.size())
	target.z_height = 0.0

	# ⑧ 耗尽下坠视觉：空中停球后 z 在 0.35s 内回 0
	ball.launch(Vector2(0, 0), Vector2(1, 0), 20.0, 100.0, null, _empty_skills(), 135.0, 0.0)
	ball.flight_distance = 100.0
	ball.is_active = true
	ball._on_ball_stopped()
	_report("停球触发下坠表现", ball.visual_fall_left > 0.0 and not ball.is_active,
		"fall=%.2f" % ball.visual_fall_left)
	var guard: bool = false
	for i in range(60):
		ball._physics_process(1.0 / 60.0)
		if ball.ball_z == 0.0:
			guard = true
			break
	_report("下坠落回地面", guard and ball.ball_z == 0.0, "z=%.1f" % ball.ball_z)

	if _fails == 0:
		print("[AT] RESULT: PASS")
		get_tree().quit(0)
	else:
		print("[AT] RESULT: FAIL (fails=%d)" % _fails)
		get_tree().quit(1)


func _empty_skills() -> Array[Dictionary]:
	return []


func _report(test_name: String, ok: bool, detail: String) -> void:
	if ok:
		print("[AT] ✓ %s %s" % [test_name, detail])
	else:
		_fails += 1
		print("[AT] ✗ %s %s" % [test_name, detail])
