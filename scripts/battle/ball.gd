extends Area2D
## 决竞球 - 全局唯一实球
## 球始终可见:持球时跟随球员头顶,发球时飞行

var ball_speed: float = 400.0
var ball_damage: float = 0.0
var ball_direction: Vector2 = Vector2.RIGHT
var is_active: bool = false
var owner_player: CharacterBody2D = null
var attacker_player: CharacterBody2D = null
var flight_distance: float = 0.0
var max_flight_distance: float = 500.0

var injected_skills: Array[Dictionary] = []
var element_type: String = ""
var trajectory_type: String = "straight"

var ball_visual: ColorRect
var ball_shadow: ColorRect

# 场地边界(与field_zone一致)
const FIELD_X_MIN: float = -510.0
const FIELD_X_MAX: float = 510.0
const FIELD_Y_MIN: float = -325.0
const FIELD_Y_MAX: float = 325.0

signal ball_caught(player: CharacterBody2D)
signal ball_hit_player(player: CharacterBody2D, damage: float)
signal ball_out_of_bounds()


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1

	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 14.0
	collision.shape = circle
	add_child(collision)

	ball_shadow = ColorRect.new()
	ball_shadow.size = Vector2(24, 10)
	ball_shadow.position = Vector2(-12, 5)
	ball_shadow.color = Color(0, 0, 0, 0.3)
	add_child(ball_shadow)

	ball_visual = ColorRect.new()
	ball_visual.size = Vector2(22, 22)
	ball_visual.position = Vector2(-11, -11)
	ball_visual.color = Color.WHITE
	var ball_style := StyleBoxFlat.new()
	ball_style.bg_color = Color.WHITE
	ball_style.set_corner_radius_all(11)
	ball_visual.add_theme_stylebox_override("normal", ball_style)
	add_child(ball_visual)

	# 碰撞检测
	body_entered.connect(_on_body_entered)

	monitorable = true
	monitoring = true


func _physics_process(delta: float) -> void:
	if not is_active:
		# 持球时跟随球员
		if not is_active and owner_player != null and is_instance_valid(owner_player):
			global_position = owner_player.global_position + Vector2(0, -40)
		return

	var move_vector: Vector2 = ball_direction * ball_speed * delta

	if trajectory_type == "arc":
		ball_direction = ball_direction.rotated(deg_to_rad(30) * delta)

	position += move_vector
	flight_distance += move_vector.length()

	# === 检测出界 ===
	if _is_out_of_bounds():
		_on_ball_out_of_field()
		return

	# 超出最大距离
	if flight_distance >= max_flight_distance:
		_on_ball_stopped()


func _is_out_of_bounds() -> bool:
	return global_position.x < FIELD_X_MIN or global_position.x > FIELD_X_MAX or global_position.y < FIELD_Y_MIN or global_position.y > FIELD_Y_MAX


func _on_ball_out_of_field() -> void:
	"""球出场地边界 → 按区域判定球回到对应队伍"""
	is_active = false
	_set_idle_visual()
	ball_out_of_bounds.emit()

	var ball_x: float = global_position.x

	# 球在左半场(x < 0)→ 回到队A(玩家队)最近球员
	# 球在右半场(x >= 0)→ 回到队B(对手队)最近球员
	var target_team: String
	if ball_x < 0:
		target_team = "a"
	else:
		target_team = "b"

	_return_to_nearest_team_player(target_team)
	print("[Ball] 球出界! x=%.0f → 回到队%s最近球员" % [ball_x, target_team.to_upper()])


func _return_to_nearest_team_player(team: String) -> void:
	"""球回到指定队伍最近的球员"""
	var team_players: Array = []

	if GameManager:
		var team_a_val = GameManager.get("team_a")
		var team_b_val = GameManager.get("team_b")
		if team_a_val and team_b_val:
			if team == "a":
				team_players = team_a_val
			else:
				team_players = team_b_val

	if team_players.is_empty():
		# 备用:找所有球员
		var parent_node = get_parent()
		if parent_node:
			team_players = parent_node.get_children()

	var nearest: CharacterBody2D = null
	var nearest_dist: float = INF

	for p in team_players:
		if not p or not is_instance_valid(p):
			continue
		if not p is CharacterBody2D:
			continue
		if p.team != team:
			continue
		if p.is_defeated:
			continue
		var dist: float = global_position.distance_to(p.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = p

	if nearest:
		return_to_player(nearest)
		print("[Ball] 球回到 %s" % _pname(nearest))
	else:
		print("[Ball] 找不到队%s的球员!" % team)


func _on_body_entered(body: Node2D) -> void:
	if not is_active:
		return

	if not body.has_method("take_damage"):
		return

	var player: CharacterBody2D = body

	# 不能击中发球者自己
	if player == attacker_player:
		return

	# 已被击败的球员不拦截球
	if player.is_defeated:
		return

	# === 同队队友 → 直接接球,不造成伤害 ===
	if attacker_player and player.team == attacker_player.team:
		_catch_ball(player)
		return

	# === 对方球员 → 击中造成伤害（待接球走韧性系统，非待接球全额伤害） ===
	var result: Dictionary = player.take_damage(ball_damage, attacker_player)
	var actual_damage: int = result.get("damage", 0)
	var effect: String = result.get("effect", "none")
	ball_hit_player.emit(player, actual_damage)

	# 被击败:球回到攻击者手上
	if player.is_defeated:
		is_active = false
		if attacker_player and is_instance_valid(attacker_player):
			return_to_player(attacker_player)
			print("[Ball] %s 被击败! 球回到 %s" % [_pname(player), _pname(attacker_player)])
		return

	# === 韧性效果响应 ===
	if effect == "ball_fly" or effect == "knockback_and_fly":
		# 球弹飞:保持原速,随机方向
		var random_angle: float = randf_range(-90.0, 90.0)
		ball_direction = ball_direction.rotated(deg_to_rad(random_angle))
		flight_distance = 0.0
		max_flight_distance = 600.0
		# 球继续飞行,不回攻击者,落地后最近球员拾球
		print("[Ball] %s 韧性弹飞! 方向偏转%.0f度" % [_pname(player), random_angle])
		return  # 球继续飞行

	# 无弹飞效果:球回到攻击者手上
	if attacker_player and is_instance_valid(attacker_player):
		is_active = false
		return_to_player(attacker_player)
		print("[Ball] 击中 %s,球回到 %s" % [_pname(player), _pname(attacker_player)])


func _catch_ball(player: CharacterBody2D) -> void:
	is_active = false
	owner_player = player
	player.set_carrying_ball(true)
	_set_idle_visual()
	ball_caught.emit(player)
	print("[Ball] %s 接住球!" % _pname(player))


func _on_ball_stopped() -> void:
	"""球停止(超出距离但未出界)→ 最近球员拾球"""
	is_active = false
	_set_idle_visual()
	print("[Ball] 球落地,飞行距离: %.1f" % flight_distance)
	# 弹飞球落地:离哪队近就给哪队最近球员
	if global_position.x < 0:
		_return_to_nearest_team_player("a")
	else:
		_return_to_nearest_team_player("b")


func launch(from: Vector2, direction: Vector2, damage: float, max_dist: float, attacker: CharacterBody2D, skills: Array[Dictionary] = []) -> void:
	global_position = from
	ball_direction = direction.normalized()
	ball_damage = damage
	max_flight_distance = max_dist
	attacker_player = attacker
	injected_skills = skills
	is_active = true
	flight_distance = 0.0
	owner_player = null

	for skill in skills:
		var tag: String = skill.get("tag") if skill.has("tag") else ""
		if tag == "on_ball":
			_apply_ball_skill(skill)

	var attack_style := StyleBoxFlat.new()
	attack_style.bg_color = Color(1, 0.3, 0.3)
	attack_style.set_corner_radius_all(11)
	ball_visual.add_theme_stylebox_override("normal", attack_style)

	visible = true
	print("[Ball] 发球! 伤害:%.1f" % ball_damage)


func return_to_player(player: CharacterBody2D) -> void:
	is_active = false
	owner_player = player
	player.set_carrying_ball(true)
	_set_idle_visual()
	global_position = player.global_position + Vector2(0, -40)


func reset() -> void:
	is_active = false
	owner_player = null
	attacker_player = null
	injected_skills = []
	trajectory_type = "straight"
	element_type = ""
	ball_damage = 0.0
	flight_distance = 0.0
	_set_idle_visual()


func _set_idle_visual() -> void:
	var idle_style := StyleBoxFlat.new()
	idle_style.bg_color = Color.WHITE
	idle_style.set_corner_radius_all(11)
	ball_visual.add_theme_stylebox_override("normal", idle_style)


func _apply_ball_skill(skill: Dictionary) -> void:
	var s_type: String = skill.get("type") if skill.has("type") else ""
	match s_type:
		"fire":
			element_type = "fire"
			trajectory_type = "straight"
			ball_speed = 500.0
		"ice":
			element_type = "ice"
			trajectory_type = "arc"
			ball_speed = 350.0
		_:
			ball_speed = 400.0


func _pname(p: CharacterBody2D) -> String:
	if p and p.char_data and p.char_data.has("name"):
		return str(p.char_data.name)
	return "Player"
