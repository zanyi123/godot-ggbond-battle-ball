## 3D 球场测试平台
## 独立测试场景,验证 3D Blender球场 + 场地线规则 + 球员交互

extends Node3D

const FIELD_WIDTH: float = 1300.0
const FIELD_HEIGHT: float = 780.0

var _camera_mode: int = 1
const MODE_TOP: int = 0
const MODE_ANGLED: int = 1
const MODE_FOLLOW: int = 2

var player_a: CharacterBody3D
var player_b: CharacterBody3D
var controlled_player: CharacterBody3D
var debug_label: Label
var camera_3d: Camera3D
var field_model: Node3D

# 场地线管理器
var field_zone: Node3D

# 比分
var score_a: int = 0
var score_b: int = 0
var score_label: Label

# 违规状态
var violating_players: Dictionary = {}  # {player: violation_type}
var pending_transfers: Array = []  # [{player, offset_index, timer}]
const TRANSFER_DELAY: float = 1.0
var match_paused: bool = false
var pause_timer: float = 0.0

# 球队颜色
const TEAM_A_COLOR := Color(0.2, 0.6, 1.0)
const TEAM_B_COLOR := Color(1.0, 0.3, 0.2)

var start_a: Vector3 = Vector3(-200, 0, 0)
var start_b: Vector3 = Vector3(200, 0, 0)


func _ready() -> void:
	field_model = $BattleFieldModel
	print("=== 3D 球场测试平台 (含场地线规则) ===")
	
	# 创建场地线管理器
	field_zone = Node3D.new()
	field_zone.set_script(load("res://scripts/test/field_zone_3d.gd"))
	add_child(field_zone)
	
	_apply_field_materials()
	_create_players()
	_register_players()
	_setup_camera()
	_create_ui()
	print("场地线规则已启用")


func _apply_field_materials() -> void:
	var grass_mat := StandardMaterial3D.new()
	grass_mat.albedo_color = Color(0.12, 0.38, 0.12, 1)
	grass_mat.roughness = 0.9
	grass_mat.metallic = 0.0

	var street_mat := StandardMaterial3D.new()
	street_mat.albedo_color = Color(0.45, 0.45, 0.42, 1)
	street_mat.roughness = 0.95
	street_mat.metallic = 0.0

	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.0, 0.65, 0.75, 1)
	wall_mat.roughness = 0.3
	wall_mat.metallic = 0.1

	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.0, 0.7, 0.8, 1)
	line_mat.roughness = 0.5
	line_mat.metallic = 0.0

	var foliage_dark_mat := StandardMaterial3D.new()
	foliage_dark_mat.albedo_color = Color(0.05, 0.32, 0.08, 1)
	foliage_dark_mat.roughness = 0.85
	foliage_dark_mat.metallic = 0.0

	var foliage_mid_mat := StandardMaterial3D.new()
	foliage_mid_mat.albedo_color = Color(0.08, 0.42, 0.12, 1)
	foliage_mid_mat.roughness = 0.8
	foliage_mid_mat.metallic = 0.0

	var foliage_light_mat := StandardMaterial3D.new()
	foliage_light_mat.albedo_color = Color(0.12, 0.52, 0.15, 1)
	foliage_light_mat.roughness = 0.75
	foliage_light_mat.metallic = 0.0

	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.45, 0.28, 0.12, 1)
	trunk_mat.roughness = 0.9
	trunk_mat.metallic = 0.0

	var lamp_pole_mat := StandardMaterial3D.new()
	lamp_pole_mat.albedo_color = Color(0.12, 0.12, 0.15, 1)
	lamp_pole_mat.roughness = 0.2
	lamp_pole_mat.metallic = 0.9

	var lamp_head_mat := StandardMaterial3D.new()
	lamp_head_mat.albedo_color = Color(1.0, 0.88, 0.45, 1)
	lamp_head_mat.roughness = 0.5
	lamp_head_mat.metallic = 0.0

	for child in field_model.get_children():
		_apply_materials_recursive(child, grass_mat, street_mat, wall_mat, line_mat, foliage_dark_mat, foliage_mid_mat, foliage_light_mat, trunk_mat, lamp_pole_mat, lamp_head_mat)

	var env: Environment = $WorldEnvironment.environment as Environment
	if env:
		env.ambient_light_color = Color(1.0, 1.0, 1.0, 1.0)
		env.ambient_light_energy = 0.5


func _apply_materials_recursive(node: Node, grass_mat: Material, street_mat: Material, wall_mat: Material, line_mat: Material, foliage_dark_mat: Material, foliage_mid_mat: Material, foliage_light_mat: Material, trunk_mat: Material, lamp_pole_mat: Material, lamp_head_mat: Material) -> void:
	if node is MeshInstance3D:
		var node_name: String = node.name
		var mat: Material = null
		if "Grass" in node_name:
			mat = grass_mat
		elif "Street" in node_name:
			mat = street_mat
		elif "Wall" in node_name:
			mat = wall_mat
		elif "Trunk" in node_name:
			mat = trunk_mat
		elif "F1" in node_name or "Foliage_1" in node_name:
			mat = foliage_dark_mat
		elif "F2" in node_name or "Foliage_2" in name:
			mat = foliage_mid_mat
		elif "F3" in node_name or "Foliage_3" in node_name:
			mat = foliage_light_mat
		elif "Tree" in node_name or "Foliage" in node_name:
			mat = foliage_mid_mat
		elif "Pole" in node_name or "Post" in node_name:
			mat = lamp_pole_mat
		elif "Head" in node_name or "Bulb" in node_name:
			mat = lamp_head_mat
		elif "Lamp" in node_name:
			mat = lamp_head_mat
		else:
			mat = line_mat
		if mat and node.mesh:
			node.mesh.surface_set_material(0, mat)
	for child in node.get_children():
		_apply_materials_recursive(child, grass_mat, street_mat, wall_mat, line_mat, foliage_dark_mat, foliage_mid_mat, foliage_light_mat, trunk_mat, lamp_pole_mat, lamp_head_mat)


func _create_players() -> void:
	player_a = CharacterBody3D.new()
	player_a.name = "PlayerA"
	player_a.position = start_a
	add_child(player_a)
	var cs_a = CollisionShape3D.new()
	var s_a = CapsuleShape3D.new()
	s_a.radius = 20.0
	s_a.height = 60.0
	cs_a.shape = s_a
	player_a.add_child(cs_a)
	var m_a = MeshInstance3D.new()
	m_a.mesh = _make_mesh(TEAM_A_COLOR)
	player_a.add_child(m_a)

	player_b = CharacterBody3D.new()
	player_b.name = "PlayerB"
	player_b.position = start_b
	add_child(player_b)
	var cs_b = CollisionShape3D.new()
	var s_b = CapsuleShape3D.new()
	s_b.radius = 20.0
	s_b.height = 60.0
	cs_b.shape = s_b
	player_b.add_child(cs_b)
	var m_b = MeshInstance3D.new()
	m_b.mesh = _make_mesh(TEAM_B_COLOR)
	player_b.add_child(m_b)

	controlled_player = player_a
	print("Players created")


func _register_players() -> void:
	field_zone.register_player(player_a, "a")
	field_zone.register_player(player_b, "b")
	print("球员注册到场地系统: 队A(PlayerA), 队B(PlayerB)")


func _make_mesh(color: Color) -> Mesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(40, 60, 40)
	mesh.material = StandardMaterial3D.new()
	mesh.material.albedo_color = color
	return mesh


func _setup_camera() -> void:
	camera_3d = Camera3D.new()
	add_child(camera_3d)
	camera_3d.current = true
	_set_camera_mode(MODE_ANGLED)


func _set_camera_mode(mode: int) -> void:
	_camera_mode = mode
	match mode:
		MODE_TOP:
			camera_3d.position = Vector3(0, 800, 0)
			camera_3d.rotation_degrees = Vector3(-90, 0, 0)
			camera_3d.fov = 50
		MODE_ANGLED:
			camera_3d.position = Vector3(0, 500, 500)
			camera_3d.rotation_degrees = Vector3(-45, 0, 0)
			camera_3d.fov = 60
		MODE_FOLLOW:
			if controlled_player:
				var t := controlled_player.position
				camera_3d.position = Vector3(t.x + 300, 150, t.z + 200)
				camera_3d.look_at(t)


func _create_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	
	debug_label = Label.new()
	debug_label.position = Vector2(20, 20)
	debug_label.add_theme_font_size_override("font_size", 16)
	canvas.add_child(debug_label)
	
	score_label = Label.new()
	score_label.position = Vector2(20, 50)
	score_label.add_theme_font_size_override("font_size", 20)
	score_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.0))
	canvas.add_child(score_label)
	
	var hint := Label.new()
	hint.position = Vector2(20, 100)
	hint.add_theme_font_size_override("font_size", 14)
	hint.text = "WASD:Move | TAB:Switch | F4:Camera | F5:Reset"
	canvas.add_child(hint)
	
	var rule_hint := Label.new()
	rule_hint.position = Vector2(20, 125)
	rule_hint.add_theme_font_size_override("font_size", 12)
	rule_hint.text = "场地规则: 不能越过中线 | 不能进入对方外场 | 不能越出禁区"
	canvas.add_child(rule_hint)


func _process(delta: float) -> void:
	_handle_input()
	_update_movement(delta)
	_update_camera()
	_check_violations()
	_update_transfers(delta)
	_update_pause(delta)
	_update_ui()


func _handle_input() -> void:
	if Input.is_action_just_pressed("ui_cancel") or Input.is_key_pressed(KEY_TAB):
		if controlled_player == player_a:
			controlled_player = player_b
		else:
			controlled_player = player_a
	if Input.is_key_pressed(KEY_F4):
		_set_camera_mode((_camera_mode + 1) % 3)
	if Input.is_key_pressed(KEY_F5):
		player_a.position = start_a
		player_b.position = start_b
		score_a = 0
		score_b = 0
		violating_players.clear()
		pending_transfers.clear()
		match_paused = false
		field_zone.set_player_penalized(player_a, false)
		field_zone.set_player_penalized(player_b, false)


func _update_movement(delta: float) -> void:
	if not controlled_player or match_paused:
		return
	
	# 正在传送的球员不能移动
	if field_zone.is_player_transitioning(controlled_player):
		return
	
	# 被惩罚的球员限制在外场内
	var is_penalized: bool = field_zone.is_player_penalized(controlled_player)
	
	var speed: float = 300.0
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_A):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		dir.x += 1
	if Input.is_key_pressed(KEY_W):
		dir.z -= 1
	if Input.is_key_pressed(KEY_S):
		dir.z += 1
	if dir != Vector3.ZERO:
		dir = dir.normalized()
		controlled_player.position += dir * speed * delta
	
	# 约束边界
	if is_penalized:
		# 被惩罚球员只能在对手那侧外场内移动
		var team: String = field_zone.get_player_team(controlled_player)
		var pos: Vector3 = controlled_player.position
		
		if team == "a":
			# 队A(左)犯规后 → 右外场 x ∈ [250, 510]，z ∈ [-325, 325]
			pos.x = clampf(pos.x, 250, 510)
			pos.z = clampf(pos.z, -325, 325)
			if pos.x >= 250 and pos.x <= 380 and pos.z > -260 and pos.z < 260:
				var dist_to_body: float = 380 - pos.x
				var dist_to_top: float = pos.z - (-325)
				var dist_to_bot: float = 325 - pos.z
				if dist_to_body <= dist_to_top and dist_to_body <= dist_to_bot:
					pos.x = 380.0
				elif dist_to_top <= dist_to_bot:
					pos.z = -325.0
				else:
					pos.z = 325.0
		else:
			# 队B(右)犯规后 → 左外场 x ∈ [-510, -250]，z ∈ [-325, 325]
			pos.x = clampf(pos.x, -510, -250)
			pos.z = clampf(pos.z, -325, 325)
			if pos.x >= -380 and pos.x <= -250 and pos.z > -260 and pos.z < 260:
				var dist_to_body: float = pos.x - (-380)
				var dist_to_top: float = pos.z - (-325)
				var dist_to_bot: float = 325 - pos.z
				if dist_to_body <= dist_to_top and dist_to_body <= dist_to_bot:
					pos.x = -380.0
				elif dist_to_top <= dist_to_bot:
					pos.z = -325.0
				else:
					pos.z = 325.0
		
		controlled_player.position = pos
	else:
		# 正常球员在整个场地内移动
		controlled_player.position.x = clampf(controlled_player.position.x, -FIELD_WIDTH/2 + 30, FIELD_WIDTH/2 - 30)
		controlled_player.position.z = clampf(controlled_player.position.z, -FIELD_HEIGHT/2 + 30, FIELD_HEIGHT/2 - 30)
	
	controlled_player.position.y = 0


func _update_camera() -> void:
	if _camera_mode == MODE_FOLLOW and controlled_player:
		var t := controlled_player.position
		camera_3d.position = Vector3(t.x + 300, 150, t.z + 200)
		camera_3d.look_at(Vector3(t.x, 0, t.z))


var last_debug_pos: Dictionary = {}

func _check_violations() -> void:
	var players_to_clear: Array[CharacterBody3D] = []
	
	for player: CharacterBody3D in [player_a, player_b]:
		if not player or not is_instance_valid(player):
			players_to_clear.append(player)
			continue
		
		# 正在传送的球员跳过
		if field_zone.is_player_transitioning(player):
			players_to_clear.append(player)
			continue
		
		var is_penalized: bool = field_zone.is_player_penalized(player)
		var pos: Vector3 = player.global_position
		var team: String = field_zone.get_player_team(player)
		
		# 调试：只在位置变化时打印
		if not is_penalized:
			var key: String = player.name
			var last_pos: Vector3 = last_debug_pos.get(key, Vector3(-9999, 0, -9999))
			if pos.distance_to(last_pos) > 50:
				var zone: int = field_zone.get_zone_at(pos)
				var zone_names := ["禁区", "内场", "左外场", "右外场"]
				print("[调试] %s(队%s) 位置:(%.0f,%.0f) 区域:%s 惩罚:%s" % [
					player.name, team, pos.x, pos.z, zone_names[zone], str(is_penalized)])
				last_debug_pos[key] = pos
		
		if is_penalized:
			players_to_clear.append(player)
			continue
		
		var violation: int = field_zone.check_zone_violation(player)
		
		if violation != field_zone.ViolationType.NONE:
			if player not in violating_players:
				_handle_violation(player, violation)
				violating_players[player] = violation
		else:
			if player in violating_players:
				violating_players.erase(player)
	
	for player in players_to_clear:
		violating_players.erase(player)


func _handle_violation(player: CharacterBody3D, violation_type: int) -> void:
	# 暂停比赛
	match_paused = true
	pause_timer = 0.0
	
	# 计算对手得分
	var team: String = field_zone.get_player_team(player)
	var scoring_team: String = "b" if team == "a" else "a"
	if scoring_team == "a":
		score_a += 1
	else:
		score_b += 1
	
	# 播报违规
	var violation_text: String = field_zone.get_violation_text(violation_type)
	var player_name: String = player.name
	print("[违规] %s (%s队) %s! %s队得分" % [player_name, team.to_upper(), violation_text, scoring_team.to_upper()])
	
	# 安排传送
	_schedule_transfer(player, violation_type)


func _schedule_transfer(player: CharacterBody3D, violation_type: int) -> void:
	var offset_index: int = 0
	for item in pending_transfers:
		var p: CharacterBody3D = item["player"]
		if p and field_zone.get_player_team(p) == field_zone.get_player_team(player):
			offset_index += 1
	
	pending_transfers.append({
		"player": player,
		"offset_index": offset_index,
		"timer": TRANSFER_DELAY
	})


func _update_transfers(delta: float) -> void:
	# 处理待传送的球员
	var all_done: bool = true
	for item in pending_transfers:
		var p: CharacterBody3D = item["player"]
		var offset: int = item.get("offset_index", 0)
		
		if p and is_instance_valid(p):
			item["timer"] -= delta
			if item["timer"] <= 0:
				field_zone.start_field_transition(p, offset)
				field_zone.set_player_penalized(p, true)
				pending_transfers.erase(item)
			else:
				all_done = false
	
	if all_done:
		pending_transfers.clear()


func _update_pause(delta: float) -> void:
	if match_paused:
		pause_timer += delta
		# 暂停2秒后自动恢复
		if pause_timer >= 2.0:
			match_paused = false
			pause_timer = 0.0
			print("[比赛] 恢复进行")


func _update_ui() -> void:
	if debug_label:
		var mode_name: String = ["TopDown", "Angled45", "Follow"][_camera_mode]
		var zone_name: String = _get_zone_name(controlled_player)
		var penalized: bool = field_zone.is_player_penalized(controlled_player)
		var status: String = " [被惩罚]" if penalized else ""
		debug_label.text = "Player: " + controlled_player.name + " | Mode: " + mode_name + " | Zone: " + zone_name + status
	
	if score_label:
		var team_a_color: String = "队A"
		var team_b_color: String = "队B"
		var paused_text: String = " [暂停中]" if match_paused else ""
		score_label.text = "%s: %d  |  %s: %d%s" % [team_a_color, score_a, team_b_color, score_b, paused_text]


func _get_zone_name(player: CharacterBody3D) -> String:
	var zone: int = field_zone.get_zone_at(player.global_position)
	match zone:
		field_zone.ZoneType.INNER_FIELD:
			return "内场"
		field_zone.ZoneType.OUTER_LEFT:
			return "左外场"
		field_zone.ZoneType.OUTER_RIGHT:
			return "右外场"
		_:
			return "禁区外"
