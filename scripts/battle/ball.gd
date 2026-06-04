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

	# === 追踪：向目标转向 ===
	if tag_effect_handler and tag_effect_handler.is_ball_tracking():
		var target: Node = tag_effect_handler.get_tracking_target()
		if target and is_instance_valid(target) and not target.is_defeated:
			var desired_dir := (target.global_position - global_position).normalized()
			var turn_speed: float = tag_effect_handler.get_tracking_turn_speed()
			ball_direction = ball_direction.move_toward(desired_dir, turn_speed * delta).normalized()
		else:
			tag_effect_handler._ball_mods.tracking_target = null

	# === 回旋：飞到一半距离时返回 ===
	if tag_effect_handler and tag_effect_handler.is_ball_boomerang():
		var trigger_ratio: float = tag_effect_handler._ball_mods.boomerang_dist
		if trigger_ratio <= 0.0:
			trigger_ratio = 0.5
		if not tag_effect_handler._ball_mods.boomerang_triggered and flight_distance >= max_flight_distance * trigger_ratio:
			var return_dir := tag_effect_handler.trigger_boomerang(ball_direction)
			if return_dir != Vector2.ZERO:
				ball_direction = return_dir

	# 非直行时才允许弧线
	var allow_arc: bool = true
	if tag_effect_handler and tag_effect_handler._ball_mods.lock_straight:
		allow_arc = false

	var move_vector: Vector2 = ball_direction * ball_speed * delta

	if trajectory_type == "arc" and allow_arc:
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

	# === 对方球员 → 击中造成伤害 ===
	var result: Dictionary = player.take_damage(ball_damage, attacker_player)
	var actual_damage: int = result.get("damage", 0)
	var effect: String = result.get("effect", "none")
	ball_hit_player.emit(player, actual_damage)

	# === AOE范围伤害：以被击中球员为圆心，对范围内敌方球员造成伤害 ===
	if tag_effect_handler and tag_effect_handler.has_ball_aoe():
		var aoe_radius: float = tag_effect_handler.get_ball_aoe_radius()
		var aoe_pct: float = tag_effect_handler.get_ball_aoe_damage_pct()
		var aoe_damage: float = ball_damage * aoe_pct
		var hit_count: int = 0
		if attacker_player and is_instance_valid(attacker_player):
			var enemy_team: String = "b" if attacker_player.team == "a" else "a"
			for p in get_tree().get_nodes_in_group("players") if get_tree() else []:
				if p == player:
					continue
				if not p is CharacterBody2D:
					continue
				if p.team != enemy_team:
					continue
				if p.is_defeated:
					continue
				var dist: float = player.global_position.distance_to(p.global_position)
				if dist <= aoe_radius:
					p.take_damage(aoe_damage, attacker_player)
					hit_count += 1
		print("[Ball] AOE范围伤害: 半径=%.0f 范围伤害=%.1f 命中%d人" % [aoe_radius, aoe_damage, hit_count])

	# === 穿透：击中后不停止，继续飞行 ===
	var is_penetrating: bool = tag_effect_handler and tag_effect_handler.is_ball_penetrating()

	# 被击败:球回到攻击者手上
	if player.is_defeated:
		if is_penetrating:
			print("[Ball] 穿透击中 %s(被击败),球继续飞行" % _pname(player))
			return  # 穿透球继续飞
		is_active = false
		if attacker_player and is_instance_valid(attacker_player):
			return_to_player(attacker_player)
			print("[Ball] %s 被击败! 球回到 %s" % [_pname(player), _pname(attacker_player)])
		return

	# === 韧性效果响应 ===
	if effect == "ball_fly" or effect == "knockback_and_fly":
		var random_angle: float = randf_range(-90.0, 90.0)
		ball_direction = ball_direction.rotated(deg_to_rad(random_angle))
		flight_distance = 0.0
		max_flight_distance = 600.0
		print("[Ball] %s 韧性弹飞! 方向偏转%.0f度" % [_pname(player), random_angle])
		return

	# 穿透：球不回攻击者，继续飞行
	if is_penetrating:
		print("[Ball] 穿透击中 %s,球继续飞行" % _pname(player))
		return

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


## 标签效果处理器引用
var tag_effect_handler: SpiritTagEffectHandler = null

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

	# 获取标签效果处理器
	if not tag_effect_handler:
		tag_effect_handler = _get_tag_effect_handler()

	# 不在这里reset_ball_mods，因为技能标签在投球前已经执行过了
	# reset在 skill_trigger.trigger_skill() 开头完成

	# 应用旧式技能
	for skill in skills:
		var tag: String = skill.get("tag") if skill.has("tag") else ""
		if tag == "on_ball":
			_apply_ball_skill(skill)

	# 标签修饰符应用到球属性
	if tag_effect_handler:
		ball_damage = tag_effect_handler.get_modified_ball_damage(ball_damage)
		ball_speed = tag_effect_handler.get_modified_ball_speed(ball_speed)

		# 精准锁定：修正发球方向指向最近敌人
		if tag_effect_handler.is_ball_lockon() and tag_effect_handler._ball_mods.has("lockon_target"):
			var lockon_target: Node = tag_effect_handler._ball_mods.get("lockon_target")
			if lockon_target and is_instance_valid(lockon_target) and not lockon_target.is_defeated:
				ball_direction = (lockon_target.global_position - from).normalized()

	var attack_style := StyleBoxFlat.new()
	attack_style.bg_color = Color(1, 0.3, 0.3)
	attack_style.set_corner_radius_all(11)
	ball_visual.add_theme_stylebox_override("normal", attack_style)

	visible = true
	print("[Ball] 发球! 伤害:%.1f 速度:%.1f 距离:%.1f" % [ball_damage, ball_speed, max_flight_distance])


func _get_tag_effect_handler() -> SpiritTagEffectHandler:
	var tree := get_tree()
	if tree:
		for node in tree.get_nodes_in_group("spirit_system"):
			if node is SpiritTagEffectHandler:
				return node
		# 备用：遍历根节点
		for node in tree.root.get_children():
			if node is SpiritSystemManager:
				return node.tag_effect_handler
	return null


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
