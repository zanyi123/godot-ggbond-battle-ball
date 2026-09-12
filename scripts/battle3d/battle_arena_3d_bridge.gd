## 3D 场景桥接总线（battle3d · Phase 2）
## 2D 逻辑层（权威） → 3D 视觉代理层（只读），单向不回写。
## 由 battle_manager._ready 末尾在 USE_3D_SCENE=true 时 spawn，setup() 同步建层。
## 2D 层零逻辑改动：显隐信标 = field_zone.visible（battle_manager 全部显隐块都包含它）；
## 2D 占位视觉（field_zone 场线子节点 / player avatar×3 / ball visual×2）由本层隐藏，碰撞/逻辑不动。
extends Node

const CFG = preload("res://scripts/battle3d/battle3d_const.gd")

var battle_mgr: Node2D = null

var _vp: SubViewport = null            # 3D 渲染视口（独立 World3D）
var _world: Node3D = null              # SubViewport 内世界根
var _cam: Camera3DController = null    # 四模式相机
var _display_layer: CanvasLayer = null # 3D 画面贴回层
var _display_rect: TextureRect = null

var _player_proxies: Dictionary = {}   # player_2d(Node) -> PlayerProxy3D
var _ball_proxy: BallProxy3DV2 = null
var _ball_2d: Node2D = null
var _field_zone: Node2D = null

var _placeholders_hidden: bool = false
var _last_field_visible: bool = false
var _hud_label: Label = null
var _fps_timer: float = 0.0  # P5 性能验收：开赛后每 10 秒打印帧率

## P3：白线双轨实时校验（每帧 6 球员比对 2D field_zone vs 3D FieldRules3D）
const PARITY_CHECK := true
var _field_zone_script: GDScript = null
var _parity_error_count: int = 0
## P4：特效适配器
var _fx_adapter: SkillFx3DAdapter = null

## ==================== 构建 ====================

func setup(mgr: Node2D) -> void:
	battle_mgr = mgr
	_field_zone = battle_mgr.field_zone
	_ball_2d = battle_mgr.ball_node
	_build_display()
	_build_world()
	_spawn_field_model()
	_spawn_player_proxies()
	_spawn_ball_proxy()
	_setup_fx_adapter()
	_setup_parity_check()
	print("[Bridge3D] ✅ 3D 场景层构建完成 (players=%d)" % _player_proxies.size())

func _setup_fx_adapter() -> void:
	var adapter_script: GDScript = load("res://scripts/battle3d/visual/skill_fx_3d_adapter.gd")
	_fx_adapter = adapter_script.new()
	_fx_adapter.name = "SkillFx3DAdapter"
	add_child(_fx_adapter)
	_fx_adapter.setup(_player_proxies, _ball_proxy, _ball_2d, battle_mgr.spirit_system)

func _setup_parity_check() -> void:
	if PARITY_CHECK and _field_zone != null:
		_field_zone_script = _field_zone.get_script()
		print("[Bridge3D] P3 双轨白线校验已开启")

func _build_display() -> void:
	_display_layer = CanvasLayer.new()
	_display_layer.name = "Bridge3DDisplay"
	_display_layer.layer = 1  # HUD(layer=10)之下、2D 场景之上
	add_child(_display_layer)
	_display_rect = TextureRect.new()
	_display_rect.name = "Bridge3DRect"
	_display_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_display_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_display_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不挡鼠标（瞄准/UI 依赖）
	_display_layer.add_child(_display_rect)

func _build_world() -> void:
	_vp = SubViewport.new()
	_vp.name = "Bridge3DViewport"
	# 踩坑三件套：独立 World3D + Environment + UPDATE_ALWAYS
	_vp.world_3d = World3D.new()
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var win := DisplayServer.window_get_size()
	_vp.size = Vector2i(maxi(win.x, 64), maxi(win.y, 64))  # headless 下窗口尺寸为 0，兜底
	_vp.handle_input_locally = false
	add_child(_vp)

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
	env.ambient_light_color = Color(1.0, 1.0, 1.0)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	_world = Node3D.new()
	_world.name = "Bridge3DWorld"
	_vp.add_child(_world)
	_world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.rotation_degrees = Vector3(-45.0, 90.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	_world.add_child(sun)

	var cam_script: GDScript = load("res://scripts/battle3d/visual/camera_3d_controller.gd")
	_cam = cam_script.new()
	_world.add_child(_cam)
	_cam.setup(Camera3DController.Mode.UNITY)
	_display_rect.texture = _vp.get_texture()

func _spawn_field_model() -> void:
	var scene: PackedScene = load(CFG.FIELD_GLB_PATH)
	if scene == null:
		push_error("[Bridge3D] 球场 GLB 加载失败")
		return
	var field := scene.instantiate()
	field.name = "BattleFieldModel"
	if field is Node3D:
		(field as Node3D).position = CFG.FIELD_ROOT_OFFSET
		(field as Node3D).scale = Vector3.ONE
	_world.add_child(field)
	_apply_field_materials(field)

func _spawn_player_proxies() -> void:
	var all: Array = battle_mgr.team_a_players + battle_mgr.team_b_players
	for p in all:
		if p == null or not is_instance_valid(p):
			continue
		var proxy := PlayerProxy3D.new()
		_world.add_child(proxy)
		var team_color := TEAM_COLOR_A if p.team == "a" else TEAM_COLOR_B
		proxy.setup(str(p.character_id), team_color)
		_attach_name_label(proxy, p)
		proxy.sync_from_2d(p.global_position, Vector2.ZERO, Vector2(1.0 if p.team == "a" else -1.0, 0.0))
		_player_proxies[p] = proxy

const TEAM_COLOR_A := Color(0.2, 0.45, 0.95, 0.8)
const TEAM_COLOR_B := Color(0.95, 0.3, 0.3, 0.8)

func _spawn_ball_proxy() -> void:
	if _ball_2d == null:
		push_warning("[Bridge3D] ball_node 为空，跳过球代理")
		return
	_ball_proxy = BallProxy3DV2.new()
	_world.add_child(_ball_proxy)
	_ball_proxy.setup()
	_ball_proxy.set_idle(_ball_2d.global_position)

## 球场材质分组（P1 验证过的 17 规则，同 unity_scene_parity_test）
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
	_apply_materials_recursive(field, mats, rules)

func _make_mat(mats: Dictionary, key: String, color: Color, rough: float, metal: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.metallic = metal
	mats[key] = mat

func _apply_materials_recursive(node: Node, mats: Dictionary, rules: Array) -> void:
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
	for child in node.get_children():
		_apply_materials_recursive(child, mats, rules)

## ==================== 每帧：显隐信标 + 同步 ====================

func _process(delta: float) -> void:
	if battle_mgr == null or _field_zone == null:
		return
	# 换人重建检测：不受 field_visible 限制（备战阶段换人也要重建，开赛即正确）
	_check_roster_rebuild()
	var field_visible: bool = _field_zone.visible
	if field_visible != _last_field_visible:
		_last_field_visible = field_visible
		_on_battle_visuals_changed(field_visible)
	if not field_visible:
		return  # 备战/中场/结算：3D 层已隐，跳过同步
	_sync_players()
	_sync_ball()
	_sync_camera()
	_fps_timer += delta
	if _fps_timer >= 10.0:
		_fps_timer = 0.0
		print("[P5][Perf] FPS=%d proxies=%d 双轨错误=%d" % [
			Engine.get_frames_per_second(), _player_proxies.size(), _parity_error_count])
	if PARITY_CHECK:
		_parity_tick()

## 名单同步：迟到球员补建（dev 模式球员在开赛回调才创建，晚于 bridge）
## + 已销毁球员清理 + character_id 变化重建（同 key 覆盖，遍历安全）
func _check_roster_rebuild() -> void:
	# 补建：battle_mgr 中存在但代理表缺失的球员
	var all: Array = battle_mgr.team_a_players + battle_mgr.team_b_players
	for p in all:
		if p == null or not is_instance_valid(p):
			continue
		if _player_proxies.has(p):
			continue
		var team_color := TEAM_COLOR_A if p.team == "a" else TEAM_COLOR_B
		var proxy := PlayerProxy3D.new()
		_world.add_child(proxy)
		proxy.setup(str(p.character_id), team_color)
		_attach_name_label(proxy, p)
		_player_proxies[p] = proxy
		print("[Bridge3D] ➕ 球员 3D 代理补建 → %s" % str(p.character_id))
	# 清理：代理表中已销毁的 2D 球员
	var dead: Array = []
	for p in _player_proxies:
		if p == null or not is_instance_valid(p):
			dead.append(p)
	for p in dead:
		if _player_proxies[p] != null and is_instance_valid(_player_proxies[p]):
			_player_proxies[p].queue_free()
		_player_proxies.erase(p)
	# 换人重建：2D 球员 character_id 与 3D 代理不一致时重建代理
	for p in _player_proxies:
		if p == null or not is_instance_valid(p):
			continue
		var proxy = _player_proxies[p]
		if is_instance_valid(proxy) and proxy.char_id == str(p.character_id):
			continue
		proxy.queue_free()
		var team_color := TEAM_COLOR_A if p.team == "a" else TEAM_COLOR_B
		var rebuilt := PlayerProxy3D.new()
		_world.add_child(rebuilt)
		rebuilt.setup(str(p.character_id), team_color)
		_attach_name_label(rebuilt, p)
		_player_proxies[p] = rebuilt
		print("[Bridge3D] 🔄 换人重建 3D 代理 → %s" % str(p.character_id))

## P3 双轨：每帧比对 2D field_zone 判定 vs 3D FieldRules3D 判定（不一致报错计数）
func _parity_tick() -> void:
	var all: Array = battle_mgr.team_a_players + battle_mgr.team_b_players
	for p in all:
		if p == null or not is_instance_valid(p):
			continue
		var is_penalized: bool = bool(p.get("is_penalized"))
		var r2d: int = int(_field_zone.check_zone_violation(p))
		var r3d: int = FieldRules3D.check_violation(str(p.team), p.global_position, is_penalized)
		if r2d != r3d:
			_parity_error_count += 1
			push_error("[P3][FAIL] 双轨不一致 %s pos=%s → 2D=%d 3D=%d (累计%d)" % [
				p.name, str(p.global_position), r2d, r3d, _parity_error_count])

## 球员头顶名字标签（3D 下消除"谁是谁"歧义；玩家位金色，其余白色）
func _attach_name_label(proxy: Node3D, p: Node2D) -> void:
	var label := Label3D.new()
	label.name = "NameLabel"
	label.text = str(p.char_data.get("name", p.character_id)) if p.get("char_data") != null else str(p.character_id)
	label.position = Vector3(0.0, 62.0, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.35
	label.font_size = 40
	label.outline_size = 10
	label.modulate = Color(1.0, 0.85, 0.3) if input_mgr_is_controlled(p) else Color.WHITE
	proxy.add_child(label)

func input_mgr_is_controlled(p: Node2D) -> bool:
	return battle_mgr != null and battle_mgr.input_mgr != null and battle_mgr.input_mgr.controlled_player == p

func _sync_players() -> void:
	var input_mgr = battle_mgr.input_mgr
	for p in _player_proxies:
		var proxy = _player_proxies[p]
		if p == null or not is_instance_valid(p):
			continue
		var facing: Vector2 = p.facing_direction
		# 玩家控制位：直接用鼠标世界坐标定向（p.facing_direction 会被 player 移动时
		# 的 velocity 覆盖，导致"鼠标不引导朝向"；2.5D 语义=正面始终朝鼠标）
		if input_mgr != null and input_mgr.controlled_player == p:
			var mouse_world = input_mgr.get("mouse_world_pos")
			if mouse_world != null and mouse_world != Vector2.ZERO:
				var to_mouse: Vector2 = mouse_world - p.global_position
				if to_mouse.length_squared() > 1.0:
					facing = to_mouse.normalized()
		if facing.length_squared() < 0.001:
			var vel: Vector2 = p.velocity
			if vel.length_squared() > 0.01:
				facing = vel.normalized()
			else:
				facing = Vector2(1.0, 0.0) if p.team == "a" else Vector2(-1.0, 0.0)
		proxy.sync_from_2d(p.global_position, p.velocity, facing, p.get("z_height") if p.get("z_height") != null else 0.0)
		proxy.set_defeated_visual(bool(p.is_defeated))

func _sync_ball() -> void:
	if _ball_proxy == null or _ball_2d == null or not is_instance_valid(_ball_2d):
		return
	var owner_p = _ball_2d.owner_player
	if owner_p != null and is_instance_valid(owner_p) and _player_proxies.has(owner_p):
		var proxy = _player_proxies[owner_p]
		_ball_proxy.set_carried(proxy.get_hand_proxy())
	elif _ball_2d.is_active:
		# M1 弹道：3D 球高度跟随 2D 层 ball_z（属性缺失时回退常量，由 proxy 内部处理）
		var flight_z: float = _ball_2d.get("ball_z") if _ball_2d.get("ball_z") != null else -1.0
		_ball_proxy.set_flight(_ball_2d.global_position, flight_z)
	else:
		_ball_proxy.set_idle(_ball_2d.global_position)

func _sync_camera() -> void:
	if _cam == null or _cam.mode != Camera3DController.Mode.FOLLOW:
		return
	var input_mgr = battle_mgr.input_mgr
	if input_mgr != null and input_mgr.controlled_player != null:
		if _player_proxies.has(input_mgr.controlled_player):
			_cam.follow_target = _player_proxies[input_mgr.controlled_player]

## ==================== 显隐切换 ====================

## field_zone.visible 变化时触发（battle_manager 的备战/开赛/中场/结算显隐块都改它）
func _on_battle_visuals_changed(field_visible: bool) -> void:
	# 3D 层显隐
	_display_rect.visible = field_visible
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if field_visible else SubViewport.UPDATE_DISABLED
	if field_visible and not _placeholders_hidden:
		_hide_2d_placeholders()
		_placeholders_hidden = true
		_auto_capture_deferred()  # 开赛 2.5 秒后自动截图（验证 3D 层显示）
	print("[Bridge3D] 比赛视觉 → %s" % ("3D 场景" if field_visible else "隐藏(备战/中场)"))

func _auto_capture_deferred() -> void:
	await get_tree().create_timer(2.5).timeout
	if _display_rect == null or not _display_rect.visible:
		return
	var img := _vp.get_texture().get_image()
	if img != null:
		var path := "res://docs/img/3d_p2/p2_smoke.png"
		DirAccess.open("res://docs").make_dir_recursive("img/3d_p2")
		img.save_png(path)
		print("[Bridge3D] 📷 %s (%dx%d)" % [path, img.get_width(), img.get_height()])

## 隐藏 2D 占位视觉（只动 visible，不动碰撞/坐标/逻辑节点）
func _hide_2d_placeholders() -> void:
	# field_zone 场线视觉（_build_visual_field 产物的直接 CanvasItem 子节点）
	if _field_zone != null:
		for child in _field_zone.get_children():
			if child is CanvasItem:
				(child as CanvasItem).visible = false
	# player 2D 占位（avatar_bg/avatar_label/state_indicator）
	for p in _player_proxies:
		if p == null or not is_instance_valid(p):
			continue
		for node_name in ["avatar_bg", "avatar_label", "state_indicator"]:
			var n: Node = p.get_node_or_null(NodePath(node_name))
			if n != null and n is CanvasItem:
				(n as CanvasItem).visible = false
	# ball 2D 占位（ball_visual/ball_shadow/skill_aura）
	if _ball_2d != null and is_instance_valid(_ball_2d):
		for node_name in ["ball_visual", "ball_shadow", "skill_aura"]:
			var bn: Node = _ball_2d.get_node_or_null(NodePath(node_name))
			if bn != null and bn is CanvasItem:
				(bn as CanvasItem).visible = false
	print("[Bridge3D] 2D 占位视觉已隐藏（场线/球员头像/球外观）")

## ==================== 手动按键（F4 切相机 / F8 截图） ====================

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).keycode
		match kc:
			KEY_F4:
				if _cam != null and _display_rect.visible:
					var m = _cam.next_mode()
					print("[Bridge3D] 相机模式 → %s" % Camera3DController.MODE_NAMES[m])
			KEY_F8:
				if _display_rect.visible:
					var img := _vp.get_texture().get_image()
					if img != null:
						var path := "res://docs/img/3d_p2/manual_%d.png" % Time.get_ticks_msec()
						img.save_png(path)
						print("[Bridge3D] 📷 %s" % path)
			KEY_ESCAPE:
				get_tree().quit()
