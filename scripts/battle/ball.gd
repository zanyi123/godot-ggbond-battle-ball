extends Area2D
## 决竞球 - 全局唯一实球
## 球始终可见:持球时跟随球员头顶,发球时飞行

## ==================== 物理常量 ====================
const BALL_MASS: float = 1.0  # 球质量（符号，力驱动用）

## ==================== 运动属性 ====================
var ball_speed: float = 400.0
var ball_damage: float = 0.0
var ball_direction: Vector2 = Vector2.RIGHT
var is_active: bool = false
var owner_player: CharacterBody2D = null
var attacker_player: CharacterBody2D = null
var flight_distance: float = 0.0
var max_flight_distance: float = 500.0

## ==================== 技能系统 ====================
var injected_skills: Array[Dictionary] = []
var element_type: String = ""
var trajectory_type: String = "straight"

var stuck_on_obstacle: StaticBody2D = null  # 球卡在障碍物上时引用

## ==================== 物理属性 ====================
var bounce_coefficient: float = 0.0  # 弹性系数 e（0=无反弹, 1=完全反弹）

## ==================== 视觉节点 ====================
var ball_visual: ColorRect
var ball_shadow: ColorRect

# 技能光环（显示已激活的技能）
var skill_aura: Sprite2D = null
var active_skill_data: Dictionary = {}
const AURA_PULSE_SPEED: float = 2.0
var aura_pulse_time: float = 0.0

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

	# 创建技能光环
	_create_skill_aura()

	monitorable = true
	monitoring = true

	# 连接到技能状态信号
	call_deferred("_connect_skill_signals")


func _physics_process(delta: float) -> void:
	if not is_active:
		# 持球时跟随球员
		if not is_active and owner_player != null and is_instance_valid(owner_player):
			global_position = owner_player.global_position + Vector2(0, -40)
		return

	# 球卡在障碍物上：逐帧消耗
	if stuck_on_obstacle:
		_process_obstacle_stuck(delta)
		return

	# === 追踪：向目标转向 ===
	if tag_effect_handler and tag_effect_handler.is_ball_tracking():
		var target: Node = tag_effect_handler.get_tracking_target()
		if target and is_instance_valid(target) and not target.is_defeated:
			var desired_dir: Vector2 = (target.global_position - global_position).normalized()
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

	# === 检测障碍物碰撞 ===
	_check_obstacle_collision()

	# === 检测出界 ===
	if _is_out_of_bounds():
		_on_ball_out_of_field()
		return

	# 超出最大距离
	if flight_distance >= max_flight_distance:
		_on_ball_stopped()

	# 更新技能光环动画
	_process_aura(delta)


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
	ball_speed = 400.0  # 重置球速（上次碰撞可能修改过）
	max_flight_distance = max_dist
	attacker_player = attacker
	injected_skills = skills
	is_active = true
	flight_distance = 0.0
	owner_player = null
	trajectory_type = "straight"
	element_type = ""

	# 获取标签效果处理器
	if not tag_effect_handler:
		tag_effect_handler = _get_tag_effect_handler()

	# 显示已激活技能的光环
	if not injected_skills.is_empty():
		_show_skill_aura(injected_skills[0])

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
		if tag_effect_handler._ball_mods.get("lockon_target") != null:
			var lockon_target: Node = tag_effect_handler._ball_mods.get("lockon_target")
			if lockon_target and is_instance_valid(lockon_target) and not lockon_target.is_defeated:
				ball_direction = (lockon_target.global_position - from).normalized()

	var attack_style := StyleBoxFlat.new()
	attack_style.bg_color = Color(1, 0.3, 0.3)
	attack_style.set_corner_radius_all(11)
	ball_visual.add_theme_stylebox_override("normal", attack_style)

	visible = true
	print("[Ball] 发球! 伤害:%.1f 速度:%.1f 距离:%.1f" % [ball_damage, ball_speed, max_flight_distance])

	# 发球时清除光环（能量已注入到球属性中）
	_clear_skill_aura()


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
	active_skill_data = {}
	_clear_skill_aura()
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


## ==================== 技能光环系统 ====================

func _create_skill_aura() -> void:
	"""创建技能光环节点"""
	skill_aura = Sprite2D.new()
	skill_aura.name = "SkillAura"
	skill_aura.z_index = -1  # 在球下方
	skill_aura.visible = false
	add_child(skill_aura)


func _show_skill_aura(skill: Dictionary) -> void:
	"""显示技能光环
	skill: {id, name, element, tags, ...}
	"""
	if skill_aura == null:
		_create_skill_aura()

	active_skill_data = skill

	# 根据元素设置光环颜色
	var element: String = skill.get("element", "")
	var aura_color: Color = _get_element_color(element)

	# 创建光环纹理
	var texture := _create_aura_texture(aura_color)
	skill_aura.texture = texture
	skill_aura.modulate = aura_color
	skill_aura.scale = Vector2(2.0, 2.0)  # 光环大小
	skill_aura.visible = true

	print("[Ball] 显示技能光环: 元素=%s, 颜色=%s" % [element, aura_color])


func _clear_skill_aura() -> void:
	"""清除技能光环"""
	if skill_aura:
		skill_aura.visible = false
	active_skill_data = {}


func _process_aura(delta: float) -> void:
	"""更新光环动画（脉冲效果）"""
	if skill_aura and skill_aura.visible:
		aura_pulse_time += delta * AURA_PULSE_SPEED
		var pulse = 1.0 + 0.2 * sin(aura_pulse_time)
		skill_aura.scale = Vector2(2.0 * pulse, 2.0 * pulse)


func _get_element_color(element: String) -> Color:
	"""获取元素对应的颜色"""
	var colors: Dictionary = {
		"金刚": Color(0.85, 0.75, 0.3),
		"大地": Color(0.7, 0.55, 0.35),
		"雷火": Color(1.0, 0.4, 0.2),
		"冰雪": Color(0.4, 0.8, 1.0),
		"草木": Color(0.3, 0.8, 0.3),
		"梦幻": Color(0.7, 0.5, 0.9),
	}
	return colors.get(element, Color(1.0, 1.0, 0.5))


func _create_aura_texture(color: Color) -> Texture2D:
	"""创建光环纹理（圆形渐变）"""
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)

	var center := Vector2(size / 2, size / 2)
	var radius := size / 2

	for x in range(size):
		for y in range(size):
			var dist := center.distance_to(Vector2(x, y))
			if dist < radius:
				var alpha = 1.0 - (dist / radius)
				alpha *= 0.6  # 最大透明度
				image.set_pixel(x, y, Color(color.r, color.g, color.b, alpha))
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))

	return ImageTexture.create_from_image(image)


## 设置激活的技能（外部调用）
func set_active_skill(skill: Dictionary) -> void:
	"""设置当前激活的技能，显示光环"""
	_show_skill_aura(skill)


## 取消激活技能（外部调用）
func cancel_active_skill() -> void:
	"""取消当前激活的技能，清除光环"""
	_clear_skill_aura()


## 连接技能信号（延迟调用）
func _connect_skill_signals() -> void:
	"""连接技能系统的激活/取消信号"""
	call_deferred("_do_connect_skill_signals")


func _do_connect_skill_signals() -> void:
	"""实际执行信号连接"""
	var spirit_systems = get_tree().get_nodes_in_group("spirit_system")
	for node in spirit_systems:
		if node.has_signal("skill_activated"):
			if not node.skill_activated.is_connected(_on_spirit_skill_activated):
				node.skill_activated.connect(_on_spirit_skill_activated)
				print("[Ball] 已连接 skill_activated 信号")
		if node.has_signal("skill_cancelled"):
			if not node.skill_cancelled.is_connected(_on_spirit_skill_cancelled):
				node.skill_cancelled.connect(_on_spirit_skill_cancelled)
				print("[Ball] 已连接 skill_cancelled 信号")


func _on_spirit_skill_activated(skill_id: String, player_id: int) -> void:
	"""技能激活时显示光环（持球且发球前）"""
	# 只有持球且是当前玩家激活的技能才显示光环
	if owner_player and owner_player.get_instance_id() == player_id:
		var skill_data = _get_skill_data(skill_id)
		if not skill_data.is_empty():
			set_active_skill(skill_data)


func _on_spirit_skill_cancelled(skill_id: String, player_id: int) -> void:
	"""技能取消时清除光环"""
	cancel_active_skill()


func _get_skill_data(skill_id: String) -> Dictionary:
	"""获取技能数据"""
	if not FileAccess.file_exists("res://data/spirits/skills.json"):
		return {}

	var file = FileAccess.open("res://data/spirits/skills.json", FileAccess.READ)
	if not file:
		return {}

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_text) != OK:
		return {}

	var skills_array = json.data.get("skills", [])
	for skill in skills_array:
		if skill.get("id", "") == skill_id:
			return skill

	return {}


## ==================== 物理系统 ====================

## 设置弹性系数
func set_bounce_coefficient(e: float) -> void:
	"""设置球的弹性系数
	
	参数：
	- e: 弹性系数（0~1）
	  - 0.0: 无反弹（球撞墙停止或出界）
	  - 0.3: 弱反弹（仅30%速度反弹）
	  - 0.5: 中等反弹（一半速度反弹）
	  - 0.8: 强反弹（80%速度反弹）
	  - 1.0: 完全反弹（100%速度反弹）
	
	注意：当前只存储值，碰撞系统未实现
	"""
	bounce_coefficient = clamp(e, 0.0, 1.0)
	print("[Ball] 弹性系数设置为 %.2f" % bounce_coefficient)


## 获取弹性系数
func get_bounce_coefficient() -> float:
	"""获取球的弹性系数"""
	return bounce_coefficient


## 预留：碰撞边界反弹接口
func _on_collision_with_boundary(normal: Vector2) -> void:
	"""碰撞边界反弹（预留接口）
	
	参数：
	- normal: 碰撞平面的法线向量（归一化）
	
	物理公式：
	v'_法线 = -e × v_法线
	v'_切线 = v_切线
	
	说明：
	- 当前只预留接口，碰撞检测系统未实现
	- 未来碰撞系统搭建后，球撞墙/障碍时调用此方法
	- 需要配合场地物理管理器的弹性系数
	"""
	if bounce_coefficient <= 0.0:
		return  # 无反弹，直接停止或出界
	
	# TODO: 实现碰撞反弹逻辑
	# 1. 分解速度为法线分量和切线分量
	# 2. 法线速度反射：v'_法线 = -e × v_法线
	# 3. 切线速度保持：v'_切线 = v_切线
	# 4. 合成新速度和方向
	
	print("[Ball] 预留：碰撞反弹 (e=%.2f, normal=%s)" % [bounce_coefficient, normal])


## 预留：施加冲量
func apply_impulse(force: Vector2, delta_time: float = 0.1) -> void:
	"""施加冲量（预留接口）"""
	var acceleration: Vector2 = force / BALL_MASS
	var speed_change: float = acceleration.length() * delta_time
	ball_speed += speed_change
	
	print("[Ball] 预留：施加冲量 F=%s, a=%.1f, v_change=%.1f" % [
		force, acceleration.length(), speed_change
	])


## ==================== 障碍物碰撞检测 ====================

func _check_obstacle_collision() -> void:
	"""每帧检测球是否碰到障碍物"""
	if not is_active:
		return
	if stuck_on_obstacle:
		return  # 已卡在障碍物上，由 _process_obstacle_stuck 处理
	
	var obs_manager = _find_obstacle_manager()
	if not obs_manager:
		return
	
	var obstacles: Array = obs_manager.get_all_obstacles()
	for obs in obstacles:
		if not is_instance_valid(obs):
			continue
		if not obs.has_method("consume_frame"):
			continue
		
		var dist: float = global_position.distance_to(obs.global_position)
		var hit_radius: float = _get_obstacle_hit_radius(obs)
		
		if dist <= hit_radius:
			# 球卡在障碍物上，开始逐帧消耗
			stuck_on_obstacle = obs
			print("[Ball] 球撞上障碍物! 开始消耗 HP=" + str(snappedf(obs.obstacle_hp, 1.0)))
			return


func _process_obstacle_stuck(delta: float) -> void:
	"""球卡在障碍物上，每帧消耗攻击力和球速"""
	if not stuck_on_obstacle or not is_instance_valid(stuck_on_obstacle):
		stuck_on_obstacle = null
		return
	
	var obs: StaticBody2D = stuck_on_obstacle
	
	# 读取消耗速率
	var atk_rate: float = obs.get("attack_consume_rate") if obs.get("attack_consume_rate") != null else 20.0
	var spd_rate: float = obs.get("speed_consume_rate") if obs.get("speed_consume_rate") != null else 20.0
	
	# 逐帧消耗
	var atk_consumed: float = atk_rate * delta
	var spd_consumed: float = spd_rate * delta
	
	ball_damage -= atk_consumed
	ball_speed -= spd_consumed
	
	# 障碍物消耗HP
	obs.consume_frame(delta)
	
	# 判断结果
	if obs.obstacle_hp <= 0.0:
		# 障碍物被击穿
		stuck_on_obstacle = null
		obs._destroy()
		if ball_speed <= 0.0 or ball_damage <= 0.0:
			# 球也耗尽
			print("[Ball] 击穿障碍物，但球也耗尽")
			_stop_and_return()
			return
		print("[Ball] 击穿障碍物! 继续飞 攻击=" + str(snappedf(ball_damage, 0.1)) + " 速度=" + str(snappedf(ball_speed, 0.1)))
		# 球继续飞行（is_active 仍为 true，下一帧恢复移动）
		return
	
	if ball_damage <= 0.0 or ball_speed <= 0.0:
		# 球攻击力或速度耗尽，被障碍物完全挡住
		stuck_on_obstacle = null
		print("[Ball] 球被障碍物耗尽!")
		_stop_and_return()


func _stop_and_return() -> void:
	"""球停止飞行并回到攻击者"""
	is_active = false
	_set_idle_visual()
	if attacker_player and is_instance_valid(attacker_player):
		return_to_player(attacker_player)


func _find_obstacle_manager() -> Node:
	"""查找障碍物管理器"""
	var tree = get_tree()
	if tree:
		# 从场景根节点查找
		for node in tree.get_nodes_in_group("obstacle_managers"):
			return node
		# 备用：从父节点查找
		var parent = get_parent()
		if parent:
			var om = parent.get_node_or_null("ObstacleManager")
			if om:
				return om
	return null


func _get_obstacle_hit_radius(obs: Node) -> float:
	"""获取障碍物的碰撞半径（简化为圆形判定）"""
	if obs.has_method("get_hit_radius"):
		return obs.get_hit_radius()
	# 默认基于碰撞形状估算
	return 40.0
