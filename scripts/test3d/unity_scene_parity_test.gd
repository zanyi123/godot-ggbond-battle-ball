## Phase 1 独立验证场：Unity TestBattle 场景复刻（battle3d/test3d · 不接主流程）
## 复刻内容（Unity 编排 ×50 像素制）：
##   球场 battle_field_3d_yup.glb scale=1（原生像素级）+ 根偏移
##   6 球员（char_001~006）摆位 ±450/∓200，B 队朝向 180°
##   决竞球 + 相机四模式（UNITY 默认 = Unity 观感 ×50）
## 验收：模型同框、白线框叠画肉眼对齐、动画 idle/run/throw 切换、相机四模式
## 运行：正常打开手动看（F4 切相机 / F5 白线框 / F6 演示动作 / ESC 退出）
##       命令行 --p1auto = 自动巡检 + 四模式截图 + 结果报告 + 自动退出
extends Node3D

const CFG = preload("res://scripts/battle3d/battle3d_const.gd")

## Unity TestBattle 摆位（米）×50 → 像素
const LAYOUT: Array[Vector3] = [
	Vector3(-450.0, 0.0, -200.0),  # TeamA player1（玩家位）
	Vector3(-450.0, 0.0, 0.0),     # TeamA player2
	Vector3(-450.0, 0.0, 200.0),   # TeamA player3
	Vector3(450.0, 0.0, -200.0),   # TeamB player4
	Vector3(450.0, 0.0, 0.0),      # TeamB player5
	Vector3(450.0, 0.0, 200.0),    # TeamB player6（Unity 里朝向180°）
]
const TEAM_CHARS: Array[String] = ["char_001", "char_002", "char_003", "char_004", "char_005", "char_006"]
const TEAM_A_COLOR := Color(0.2, 0.45, 0.95, 0.8)
const TEAM_B_COLOR := Color(0.95, 0.3, 0.3, 0.8)

const SCREENSHOT_DIR := "res://docs/img/3d_p1"

var camera_ctrl: Camera3DController = null
var ball_proxy: BallProxy3DV2 = null
var players: Array[PlayerProxy3D] = []
var frame_overlay: MeshInstance3D = null

var _demo_active: bool = false
var _demo_t: float = 0.0
var _run_seen: bool = false
var _hud_label: Label = null
var _hud_hint: Label = null
var _auto_mode: bool = false
var _static_shot_mode: bool = false
## F7 手动操控模式：WASD 移动主控球员（players[0]），球挂手上跟随
var _control_mode: bool = false
var _ctrl_pos: Vector2 = Vector2(-450, 0)

func _ready() -> void:
	for arg in OS.get_cmdline_args():
		if arg == "--p1auto":
			_auto_mode = true
		elif arg == "--p1shot":
			_static_shot_mode = true
	print("[P1] === Unity 场景复刻验证场启动 (auto=%s) ===" % _auto_mode)
	_build_environment()
	_build_field()
	_build_players()
	_build_ball()
	_build_camera()
	_build_frame_overlay()
	_build_hud()
	_reset_to_kickoff()
	if _auto_mode:
		_demo_active = true
		_run_auto_sequence()
	elif _static_shot_mode:
		_run_static_shot()

## ==================== 构建 ====================

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.38, 0.45, 0.55)
	sky_mat.sky_horizon_color = Color(0.65, 0.67, 0.7)
	sky_mat.ground_bottom_color = Color(0.2, 0.17, 0.13)
	sky_mat.ground_horizon_color = Color(0.65, 0.67, 0.7)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# 侧光场景下保底亮度（UNITY 视角背光问题：全靠天空环境光会太暗）
	env.ambient_light_color = Color(1.0, 1.0, 1.0)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

	# 太阳取侧光方位（yaw 90°），避免 UNITY/ANGLED 相机一侧全背光发黑
	var sun := DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.rotation_degrees = Vector3(-45.0, 90.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)

func _build_field() -> void:
	var scene: PackedScene = load(CFG.FIELD_GLB_PATH)
	if scene == null:
		push_error("[P1][FAIL] 球场 GLB 加载失败: %s" % CFG.FIELD_GLB_PATH)
		return
	var field := scene.instantiate()
	field.name = "BattleFieldModel"
	if field is Node3D:
		(field as Node3D).position = CFG.FIELD_ROOT_OFFSET
		(field as Node3D).scale = Vector3.ONE
	add_child(field)
	# GLB 材质按节点名分组重上（移植自 battle_field_3d_test._apply_field_materials，
	# 已知坑：不处理则内场草地等区域无材质/发灰）
	_apply_field_materials(field)
	var mesh_count := field.find_children("*", "MeshInstance3D", true, false).size()
	print("[P1] 球场模型实例化 mesh_count=%d offset=%s" % [mesh_count, CFG.FIELD_ROOT_OFFSET])

## 球场材质分组（battle_field_3d_test 验证过的 11 种材质，按节点名关键字匹配）
func _apply_field_materials(field: Node) -> void:
	var mats := {}
	_make_mat(mats, "grass", Color(0.12, 0.38, 0.12), 0.9, 0.0)
	_make_mat(mats, "street", Color(0.45, 0.45, 0.42), 0.95, 0.0)
	_make_mat(mats, "wall", Color(0.0, 0.65, 0.75), 0.3, 0.1)
	_make_mat(mats, "line", Color(0.0, 0.7, 0.8), 0.5, 0.0)
	_make_mat(mats, "foliage_dark", Color(0.05, 0.32, 0.08), 0.85, 0.0)
	_make_mat(mats, "foliage_mid", Color(0.08, 0.42, 0.12), 0.8, 0.0)
	_make_mat(mats, "foliage_light", Color(0.12, 0.52, 0.15), 0.75, 0.0)
	_make_mat(mats, "trunk", Color(0.45, 0.28, 0.12), 0.9, 0.0)
	_make_mat(mats, "lamp_pole", Color(0.12, 0.12, 0.15), 0.2, 0.9)
	_make_mat(mats, "lamp_head", Color(1.0, 0.88, 0.45), 0.5, 0.0)
	var rules := [
		["Grass", "grass"], ["Street", "street"], ["Wall", "wall"], ["Trunk", "trunk"],
		["F1", "foliage_dark"], ["Foliage_1", "foliage_dark"],
		["F2", "foliage_mid"], ["Foliage_2", "foliage_mid"],
		["F3", "foliage_light"], ["Foliage_3", "foliage_light"],
		["Tree", "foliage_mid"], ["Foliage", "foliage_mid"],
		["Pole", "lamp_pole"], ["Post", "lamp_pole"],
		["Head", "lamp_head"], ["Bulb", "lamp_head"], ["Lamp", "lamp_head"],
	]
	var counter := {"applied": 0}
	_apply_materials_recursive(field, mats, rules, counter)
	print("[P1] 球场材质分组完成 applied=%d" % counter["applied"])

func _make_mat(mats: Dictionary, key: String, color: Color, rough: float, metal: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.metallic = metal
	mats[key] = mat

func _apply_materials_recursive(node: Node, mats: Dictionary, rules: Array, counter: Dictionary) -> void:
	if node is MeshInstance3D:
		var node_name: String = node.name
		var mat: StandardMaterial3D = null
		for rule in rules:
			if rule[0] in node_name:
				mat = mats[rule[1]]
				break
		if mat == null:
			mat = mats["line"]
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for surf in range(mi.mesh.get_surface_count()):
				mi.mesh.surface_set_material(surf, mat)
			counter["applied"] += 1
	for child in node.get_children():
		_apply_materials_recursive(child, mats, rules, counter)

func _build_players() -> void:
	for i in range(LAYOUT.size()):
		var proxy := PlayerProxy3D.new()
		add_child(proxy)
		var color := TEAM_A_COLOR if i < 3 else TEAM_B_COLOR
		proxy.setup(TEAM_CHARS[i], color)
		proxy.global_position = LAYOUT[i]
		if i >= 3:
			proxy.rotation.y = PI
		players.append(proxy)

func _build_ball() -> void:
	ball_proxy = BallProxy3DV2.new()
	add_child(ball_proxy)
	ball_proxy.setup()
	ball_proxy.set_flight(Vector2(0.0, 0.0))

func _build_camera() -> void:
	camera_ctrl = Camera3DController.new()
	camera_ctrl.name = "Camera3DController"
	add_child(camera_ctrl)
	camera_ctrl.setup(Camera3DController.Mode.UNITY)
	if players.size() > 0:
		camera_ctrl.follow_target = players[0]

func _build_frame_overlay() -> void:
	# 白线判定框叠画（INNER/WALKABLE/中线/中圈），肉眼比对 GLB 白线贴图
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 0.3, 0.9)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var y := 6.0
	var inner := CFG.FIELD_INNER
	_draw_rect_lines(im, Vector2(inner.position.x, inner.position.y), Vector2(inner.end.x, inner.end.y), y)
	var walk := CFG.FIELD_WALKABLE
	_draw_rect_lines(im, Vector2(walk.position.x, walk.position.y), Vector2(walk.end.x, walk.end.y), y)
	# 中线（x=0，跨内场 z）
	im.surface_add_vertex(Vector3(0.0, y, inner.position.y))
	im.surface_add_vertex(Vector3(0.0, y, inner.end.y))
	# 中圈（半径 60，48 段）
	var segs := 48
	for i in range(segs):
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		im.surface_add_vertex(Vector3(cos(a0) * CFG.FIELD_CENTER_CIRCLE_R, y, sin(a0) * CFG.FIELD_CENTER_CIRCLE_R))
		im.surface_add_vertex(Vector3(cos(a1) * CFG.FIELD_CENTER_CIRCLE_R, y, sin(a1) * CFG.FIELD_CENTER_CIRCLE_R))
	im.surface_end()
	frame_overlay = MeshInstance3D.new()
	frame_overlay.name = "RuleFrameOverlay"
	frame_overlay.mesh = im
	frame_overlay.material_override = null
	add_child(frame_overlay)

static func _draw_rect_lines(im: ImmediateMesh, a: Vector2, b: Vector2, y: float) -> void:
	im.surface_add_vertex(Vector3(a.x, y, a.y))
	im.surface_add_vertex(Vector3(b.x, y, a.y))
	im.surface_add_vertex(Vector3(b.x, y, a.y))
	im.surface_add_vertex(Vector3(b.x, y, b.y))
	im.surface_add_vertex(Vector3(b.x, y, b.y))
	im.surface_add_vertex(Vector3(a.x, y, b.y))
	im.surface_add_vertex(Vector3(a.x, y, b.y))
	im.surface_add_vertex(Vector3(a.x, y, a.y))

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_hud_label = Label.new()
	_hud_label.position = Vector2(16, 12)
	_hud_label.add_theme_font_size_override("font_size", 22)
	_hud_label.add_theme_color_override("font_color", Color.WHITE)
	_hud_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud_label.add_theme_constant_override("outline_size", 4)
	layer.add_child(_hud_label)
	_hud_hint = Label.new()
	_hud_hint.position = Vector2(16, 44)
	_hud_hint.add_theme_font_size_override("font_size", 18)
	_hud_hint.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_hud_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud_hint.add_theme_constant_override("outline_size", 3)
	_hud_hint.text = "F4=切相机 F5=白线框 F6=演示 F7=WASD操控(%s) ESC=退出" % ("开" if _control_mode else "关")
	layer.add_child(_hud_hint)

## ==================== 演示驱动（假 2D 数据驱动 3D 代理） ====================

func _process(delta: float) -> void:
	_demo_t += delta
	if _control_mode:
		_drive_manual(delta)
	elif _demo_active:
		_drive_demo()
	_update_hud()

## F7 手动操控：WASD 移动主控球员（跑动动画自动触发），球挂手上
func _drive_manual(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S):
		dir.y += 1
	if Input.is_key_pressed(KEY_A):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		dir.x += 1
	var vel2d := dir.normalized() * 300.0
	_ctrl_pos += vel2d * delta
	players[0].sync_from_2d(_ctrl_pos, vel2d, dir.normalized() if dir.length() > 0.01 else Vector2(1, 0))
	ball_proxy.set_carried(players[0].get_hand_proxy())

## 演示：球员绕各自摆位点小圈跑动（触发 idle↔run），球挂在 A[0] 手上随跑（同 2D 持球）
func _drive_demo() -> void:
	for i in range(players.size()):
		var proxy := players[i]
		var base2d := Vector2(LAYOUT[i].x, LAYOUT[i].z)
		var ang := _demo_t * 1.4 + i * (TAU / 6.0)
		var radius := 80.0
		var pos2d := base2d + Vector2(cos(ang), sin(ang)) * radius
		var vel2d := Vector2(-sin(ang), cos(ang)) * radius * 1.4
		proxy.sync_from_2d(pos2d, vel2d, vel2d.normalized())
		if proxy.get_current_anim() == "run":
			_run_seen = true
	# 球随持球者手部移动（不乱飞）
	ball_proxy.set_carried(players[0].get_hand_proxy())

func _stop_demo() -> void:
	_demo_active = false
	for i in range(players.size()):
		players[i].sync_from_2d(Vector2(LAYOUT[i].x, LAYOUT[i].z), Vector2.ZERO, Vector2(1.0 if i < 3 else -1.0, 0.0))
	ball_proxy.set_carried(players[0].get_hand_proxy())

## 开局静止摆位（默认状态，同 2D 比赛开局）：全员 idle 站位，球挂在 A 队玩家位手上
func _reset_to_kickoff() -> void:
	_demo_active = false
	_control_mode = false
	for i in range(players.size()):
		players[i].sync_from_2d(Vector2(LAYOUT[i].x, LAYOUT[i].z), Vector2.ZERO, Vector2(1.0 if i < 3 else -1.0, 0.0))
	ball_proxy.set_carried(players[0].get_hand_proxy())

func _update_hud() -> void:
	if _hud_label == null:
		return
	var mode_name := camera_ctrl.get_mode_name() if camera_ctrl != null else "?"
	var anim0 := players[0].get_current_anim() if players.size() > 0 else "?"
	_hud_label.text = "[P1] cam=%s demo=%s anim0=%s run_seen=%s" % [mode_name, _demo_active, anim0, _run_seen]

## ==================== 手动按键 ====================

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).keycode
		match kc:
			KEY_F4:
				var m := camera_ctrl.next_mode()
				print("[P1] 相机模式 → %s" % Camera3DController.MODE_NAMES[m])
			KEY_F5:
				frame_overlay.visible = not frame_overlay.visible
				print("[P1] 白线框 %s" % ("显示" if frame_overlay.visible else "隐藏"))
			KEY_F6:
				if _demo_active:
					_reset_to_kickoff()
				else:
					_demo_active = true
				print("[P1] 演示 %s（F6 切回开局静止）" % ("开" if _demo_active else "停"))
			KEY_F8:
				var ts := Time.get_ticks_msec()
				await _capture("manual_%d" % ts)
			KEY_F9:
				# 朝向校准：全员静止，主控 facing=+X（屏幕右），斜视截图
				_demo_active = false
				_control_mode = false
				for i in range(players.size()):
					players[i].sync_from_2d(Vector2(LAYOUT[i].x, LAYOUT[i].z), Vector2.ZERO, Vector2(1, 0))
				camera_ctrl.set_mode(Camera3DController.Mode.ANGLED)
				await get_tree().create_timer(0.8).timeout
				await _capture("facing_calib")
				print("[P1] 朝向校准截图已存（主控 facing=+X/屏幕右，看面部朝右=公式对，朝左=公式反）")
			KEY_F7:
				_control_mode = not _control_mode
				if _control_mode:
					_demo_active = false
					_ctrl_pos = Vector2(LAYOUT[0].x, LAYOUT[0].z)
				print("[P1] 操控模式 %s（WASD 移动主控球员）" % ("开" if _control_mode else "关"))
			KEY_ESCAPE:
				get_tree().quit()

## ==================== 自动巡检 + 截图 ====================

## --p1shot：默认静止开局下截图一张即退（验证"无演示"画面）
func _run_static_shot() -> void:
	await get_tree().create_timer(3.0).timeout
	await _capture("kickoff_static")
	get_tree().quit(0)

func _run_auto_sequence() -> void:
	# 等场景稳定（模型加载 + 动画起步）
	await get_tree().create_timer(3.0).timeout
	# P5 性能采样：演示跑动中 3 秒平均帧率（6 GLB + 球场 + 球全渲染）
	var frames0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	await get_tree().create_timer(3.0).timeout
	var fps := float(Engine.get_frames_drawn() - frames0) / (float(Time.get_ticks_msec() - t0) / 1000.0)
	print("[P5][Perf] 3D场景平均FPS=%.1f (窗口1440x900)" % fps)
	# 演示期截图（run 动画可见）
	await _screenshot_mode(Camera3DController.Mode.UNITY, "unity")
	await _screenshot_mode(Camera3DController.Mode.TOP, "top")
	await _screenshot_mode(Camera3DController.Mode.ANGLED, "angled")
	await _screenshot_mode(Camera3DController.Mode.FOLLOW, "follow")
	# 停演示 → idle + 持球态再截一张
	_stop_demo()
	await get_tree().create_timer(1.2).timeout
	await _capture("idle_carried")
	_print_validation()
	var all_pass := _compute_pass()
	print("[P1] RESULT: %s" % ("PASS" if all_pass else "FAIL"))
	get_tree().quit(0 if all_pass else 1)

func _screenshot_mode(m: Camera3DController.Mode, tag: String) -> void:
	camera_ctrl.set_mode(m)
	await get_tree().create_timer(0.6).timeout
	await _capture(tag)

func _capture(tag: String) -> void:
	var dir := DirAccess.open("res://docs")
	if dir != null:
		dir.make_dir_recursive("img/3d_p1")
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_error("[P1][FAIL] 截图失败 img=null tag=%s" % tag)
		return
	var path := "%s/p1_%s.png" % [SCREENSHOT_DIR, tag]
	var err := img.save_png(path)
	if err == OK:
		print("[P1] 📷 截图: %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	else:
		push_error("[P1][FAIL] 截图保存失败 %s err=%d" % [path, err])

func _print_validation() -> void:
	var field := get_node_or_null("BattleFieldModel")
	var field_meshes := 0
	if field != null:
		field_meshes = field.find_children("*", "MeshInstance3D", true, false).size()
	_report("球场模型", field != null and field_meshes > 0, "meshes=%d" % field_meshes)
	var mesh_ok := 0
	var anim_ok := 0
	for p in players:
		if p.is_mesh_ok():
			mesh_ok += 1
		if p.get_anim_player() != null and p.is_anim_playing():
			anim_ok += 1
	_report("6球员模型", mesh_ok == 6, "%d/6 mesh" % mesh_ok)
	_report("6球员动画", anim_ok == 6, "%d/6 playing" % anim_ok)
	_report("run切换", _run_seen, "demo 期观察到 run")
	_report("球模型", ball_proxy != null and ball_proxy.is_mesh_ok(), "scale=%d" % CFG.BALL_SCALE)
	_report("相机", camera_ctrl != null and camera_ctrl.current, camera_ctrl.get_mode_name() if camera_ctrl != null else "?")

func _compute_pass() -> bool:
	var field := get_node_or_null("BattleFieldModel")
	var field_ok: bool = field != null and field.find_children("*", "MeshInstance3D", true, false).size() > 0
	var mesh_ok := 0
	var anim_ok := 0
	for p in players:
		if p.is_mesh_ok():
			mesh_ok += 1
		if p.get_anim_player() != null and p.is_anim_playing():
			anim_ok += 1
	return field_ok and mesh_ok == 6 and anim_ok == 6 and _run_seen \
		and ball_proxy != null and ball_proxy.is_mesh_ok() and camera_ctrl != null

func _report(item: String, ok: bool, detail: String) -> void:
	print("[P1][%s] %s (%s)" % ["PASS" if ok else "FAIL", item, detail])
