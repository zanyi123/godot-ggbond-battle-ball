## P2 验收测试：第一人称准星模式（headless 可跑）
## ① toggle_fp_mode 进出状态 ② 进入时以 facing 初始化 yaw、pitch 清平视
## ③ 鼠标 motion 转 yaw/pitch 且 pitch 夹取 [-60°,+30°] ④ FP 发球参数=视线（非投影）
## ⑤ 地面第三人称发球仍恒高（回归） ⑥ 准星高亮=视线命中预览
## 运行：Godot_console.exe --headless res://scenes/test3d/test_fp_mode.tscn
extends Node3D

var _fails: int = 0


func _ready() -> void:
	var arena_scene: PackedScene = load("res://scenes/battle/battle_arena.tscn")
	var arena = arena_scene.instantiate()
	add_child(arena)
	await get_tree().create_timer(1.5).timeout

	var input_mgr = arena.get_node_or_null("InputManager")
	var bm = arena
	_report("input/battle 管理器存在", input_mgr != null and bm != null, "")
	if input_mgr == null or bm == null:
		print("[FP] RESULT: FAIL")
		get_tree().quit(1)
		return

	var p = arena.team_a_players[0]
	input_mgr.set_controlled_player(p)
	input_mgr.match_started = true  # headless 未开赛，手动放行输入
	p.facing_direction = Vector2(1, 0)
	var ball = arena.ball_node

	# ① E 键切换状态（toggle 即 input 侧唯一入口）
	input_mgr.fp_mode = false
	input_mgr.toggle_fp_mode()
	var entered: bool = input_mgr.fp_mode == true
	input_mgr.toggle_fp_mode()
	var exited: bool = input_mgr.fp_mode == false
	_report("E键进出FP", entered and exited, "")

	# ② 进入时 facing 初始化 yaw
	input_mgr.fp_mode = false
	p.facing_direction = Vector2(0, 1)  # 朝 +y，yaw=π/2
	input_mgr.toggle_fp_mode()
	_report("facing初始化yaw", absf(input_mgr.fp_yaw - PI / 2.0) < 0.01,
		"yaw=%.2f" % input_mgr.fp_yaw)
	_report("pitch清平视", input_mgr.fp_pitch == 0.0, "")

	# ③ 鼠标 motion：yaw 累积（右移=右转）、pitch 夹取
	input_mgr.fp_yaw = 0.0
	input_mgr.fp_pitch = 0.0
	var ev := InputEventMouseMotion.new()
	ev.relative = Vector2(100, -50)
	input_mgr._input(ev)
	var yaw_ok: bool = absf(input_mgr.fp_yaw - (100.0 * 0.003)) < 0.001
	var pitch_up: bool = absf(input_mgr.fp_pitch - (50.0 * 0.003)) < 0.001
	_report("鼠标右转+抬头", yaw_ok and pitch_ok_str(pitch_up, true),
		"yaw=%.3f pitch=%.3f" % [input_mgr.fp_yaw, input_mgr.fp_pitch])
	# 鼠标捕获：FP 进入=CAPTURED，退出=VISIBLE
	# （headless 无窗口引擎会拒绝 CAPTURED——真机行为，测试只验退出恢复+注明）
	var captured: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	input_mgr.toggle_fp_mode()
	var restored: bool = Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
	input_mgr.toggle_fp_mode()  # 回到 FP 继续后续测试
	if DisplayServer.get_name() == "headless":
		_report("FP鼠标捕获(headless跳过)", restored, "headless 下 CAPTURED 不可设，仅验退出恢复")
	else:
		_report("FP鼠标捕获/退出恢复", captured and restored,
			"captured=%s restored=%s" % [str(captured), str(restored)])
	# pitch 夹取：连续大幅下压
	for i in range(50):
		ev = InputEventMouseMotion.new()
		ev.relative = Vector2(0, 500)
		input_mgr._input(ev)
	_report("pitch下压夹-60°", absf(input_mgr.fp_pitch - deg_to_rad(-60.0)) < 0.001,
		"pitch=%.3f" % input_mgr.fp_pitch)

	# ④ FP 发球参数：release 走视线（模拟持球瞄准释放链）
	p.is_carrying_ball = true
	input_mgr.is_aiming = true
	input_mgr.fp_mode = true
	input_mgr.fp_yaw = 0.0
	input_mgr.fp_pitch = deg_to_rad(-30.0)
	p.z_height = 0.0
	input_mgr._on_left_click_release()
	_report("FP发球=视线俯仰", absf(input_mgr.last_throw_pitch_deg - (-30.0)) < 0.01 \
		and input_mgr.last_throw_start_z > 0.0,
		"pitch=%.1f start_z=%.0f" % [input_mgr.last_throw_pitch_deg, input_mgr.last_throw_start_z])

	# ⑤ 地面第三人称发球恒高（回归）
	input_mgr.fp_mode = false
	input_mgr.is_aiming = true
	p.is_carrying_ball = true
	input_mgr.mouse_world_pos = p.global_position + Vector2(200, 0)
	input_mgr._on_left_click_release()
	_report("地面第三人称恒高", input_mgr.last_throw_start_z == -1.0,
		"start_z=%.0f" % input_mgr.last_throw_start_z)

	# ⑥ 准星高亮=视线命中预览（纯函数；眼高 80：平射越顶、俯 -20° 在 200px 处 z=80-73=7 命中）
	var target = arena.team_b_players[0]
	target.global_position = p.global_position + Vector2(200, 0)
	target.z_height = 0.0
	p.z_height = 0.0
	var eye_z: float = 80.0
	var hits_flat: Array = ball.preview_path_hits(p.global_position, eye_z, 0.0, 600.0, Vector2(1, 0), [p, target])
	var hits_down: Array = ball.preview_path_hits(p.global_position, eye_z, -20.0, 600.0, Vector2(1, 0), [p, target])
	_report("平射越过站立者/俯射命中", not hits_flat.has(target) and hits_down.has(target),
		"flat=%d down=%d" % [hits_flat.size(), hits_down.size()])
	target.z_height = 0.0

	# ⑥b 相机前移出模型：yaw=0 朝 +x，位置应在球员前方 35px；yaw=π/2 朝 +y(z)
	var cam := Camera3DController.new()
	add_child(cam)
	cam.set_mode(Camera3DController.Mode.FIRST_PERSON)
	cam.fp_pos2d = Vector2(0, 0)
	cam.fp_height_z = 60.0
	cam.fp_yaw = 0.0
	cam.fp_pitch = 0.0
	cam._update_fp()
	var fwd_x: bool = absf(cam.global_position.x - 35.0) < 0.01 and absf(cam.global_position.z) < 0.01
	cam.fp_yaw = PI / 2.0
	cam._update_fp()
	var fwd_z: bool = absf(cam.global_position.z - 35.0) < 0.01 and absf(cam.global_position.x) < 0.01
	cam.queue_free()
	_report("相机沿视线前移35px", fwd_x and fwd_z,
		"x=%.1f z=%.1f" % [cam.global_position.x, cam.global_position.z])

	# ⑥c FP 移动映射（视角相对）：yaw=0 朝+x → W=+x, D=+y(右侧), A=-y；转 90° 后随之旋转
	input_mgr.fp_yaw = 0.0
	var mv_w: Vector2 = input_mgr.compute_fp_move(0.0, -1.0)
	var mv_d: Vector2 = input_mgr.compute_fp_move(1.0, 0.0)
	var mv_a: Vector2 = input_mgr.compute_fp_move(-1.0, 0.0)
	var map0: bool = mv_w.distance_to(Vector2(1, 0)) < 0.01 \
		and mv_d.distance_to(Vector2(0, 1)) < 0.01 \
		and mv_a.distance_to(Vector2(0, -1)) < 0.01
	input_mgr.fp_yaw = PI / 2.0
	var mv_w2: Vector2 = input_mgr.compute_fp_move(0.0, -1.0)
	var map90: bool = mv_w2.distance_to(Vector2(0, 1)) < 0.01
	var mv_idle: Vector2 = input_mgr.compute_fp_move(0.0, 0.0)
	_report("FP移动视角相对(W前D右A左)", map0 and map90 and mv_idle == Vector2.ZERO,
		"W=%s D=%s W(90°)=%s" % [str(mv_w.round()), str(mv_d.round()), str(mv_w2.round())])

	if _fails == 0:
		print("[FP] RESULT: PASS")
		get_tree().quit(0)
	else:
		print("[FP] RESULT: FAIL (fails=%d)" % _fails)
		get_tree().quit(1)


func pitch_ok_str(got: bool, want: bool) -> bool:
	return got == want


func _report(test_name: String, ok: bool, detail: String) -> void:
	if ok:
		print("[FP] ✓ %s %s" % [test_name, detail])
	else:
		_fails += 1
		print("[FP] ✗ %s %s" % [test_name, detail])
