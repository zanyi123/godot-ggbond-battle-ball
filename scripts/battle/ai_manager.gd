extends Node
## AI管理器 - 数据驱动的AI行为引擎
## 所有行为参数从 AIProfile 读取,不硬编码
## 包含:180度朝向视野感知系统、评分决策、阵型跑位

const AIProfile = preload("res://scripts/battle/ai_profile.gd")

var battle_manager: Node2D
var input_manager: Node
var ball_node: Area2D

enum State {
	IDLE,
	CHASE_BALL,
	GOTO_BALL,
	DRIBBLE,
	ATTACK,
	PASS,
	DEFEND,
	SUPPORT,
	PENALTY_MOVE,
	READY_CATCH
}

var ai_players: Array[Dictionary] = []

# 场地边界(内场)-- 不属于AI参数,保留常量
const FIELD_X_MIN: float = -380.0
const FIELD_X_MAX: float = 380.0
const FIELD_Y_MIN: float = -260.0
const FIELD_Y_MAX: float = 260.0

# 外场边界(左外场 - 队B) — 与 field_zone.gd LEFT_OUTER 对齐
const LEFT_OUTER_X_MIN: float = -510.0
const LEFT_OUTER_X_MAX: float = -250.0
const LEFT_OUTER_Y_MIN: float = -325.0
const LEFT_OUTER_Y_MAX: float = 325.0

# 外场边界(右外场 - 队A) — 与 field_zone.gd RIGHT_OUTER 对齐
const RIGHT_OUTER_X_MIN: float = 250.0
const RIGHT_OUTER_X_MAX: float = 510.0
const RIGHT_OUTER_Y_MIN: float = -325.0
const RIGHT_OUTER_Y_MAX: float = 325.0

# 凹字形缺口边界(上下臂之间的内场区域)
const GAP_Y_MIN: float = -260.0
const GAP_Y_MAX: float = 260.0
# 右外场臂范围(缺口x区间)
const RIGHT_ARM_X_MIN: float = 250.0
const RIGHT_ARM_X_MAX: float = 380.0
# 左外场臂范围(缺口x区间)
const LEFT_ARM_X_MIN: float = -380.0
const LEFT_ARM_X_MAX: float = -250.0

# 球门位置
const GOAL_A: Vector2 = Vector2(300.0, 0.0)
const GOAL_B: Vector2 = Vector2(-300.0, 0.0)

# 转身速度(弧度/秒)
const TURN_SPEED: float = 5.0


func _ready() -> void:
	set_physics_process(true)


func initialize(battle_mgr: Node2D, input_mgr: Node) -> void:
	battle_manager = battle_mgr
	input_manager = input_mgr
	print("[AI] 初始化完成")


func _physics_process(delta: float) -> void:
	if not battle_manager:
		return
	if not battle_manager.match_started:
		return

	if not ball_node:
		ball_node = battle_manager.ball_node
	if not ball_node:
		return

	for ap in ai_players:
		if not _is_valid(ap):
			continue

		# 感知更新(每帧调用,内部有计时控制)
		_update_awareness(ap, delta)

		# 每个AI有自己独立的决策间隔
		var profile: AIProfile = ap.profile
		ap.think_timer += delta
		var do_think: bool = ap.think_timer >= profile.think_interval
		if do_think:
			ap.think_timer = 0.0
			_decide(ap)

		# 朝向更新
		_update_facing(ap, delta)

		# 移动执行
		_move(ap, delta)


# ==============================
# ===== 注册 ===================
# ==============================

func register_player(player: CharacterBody2D, team_name: String, index: int, profile: AIProfile) -> void:
	# 初始朝向：队A朝右(向对方)，队B朝左(向对方)
	var initial_facing: Vector2 = Vector2(1, 0) if team_name == "a" else Vector2(-1, 0)
	player.facing_direction = initial_facing

	# 根据角色基础速度 * profile乘数 计算AI实际速度
	var base_speed: float = player.speed  # 已含SPEED_SCALE缩放
	profile.speed_chase = base_speed * profile.speed_chase_mult
	profile.speed_dribble = base_speed * profile.speed_dribble_mult
	profile.speed_move = base_speed * profile.speed_move_mult

	ai_players.append({
		"player": player,
		"team": team_name,
		"index": index,
		"state": State.IDLE,
		"target_pos": player.global_position,
		"home_pos": player.global_position,
		"profile": profile,
		"hold_timer": 0.0,
		"hold_duration": randf_range(profile.hold_duration_min, profile.hold_duration_max),
		"dribble_target": Vector2.ZERO,
		"total_carry_time": 0.0,
		"last_pos": player.global_position,
		"stuck_timer": 0.0,
		"think_timer": randf() * profile.think_interval,  # 错开初始决策时间
		"known_positions": {},
		"awareness_timer": 0.0,
		"last_shoot_target": null,
	})
	print("[AI] 注册 队%s 位置%d 角色=%s 弱点=%s base_speed=%.0f chase=%.0f" % [team_name, index, profile.role, profile.weakness, base_speed, profile.speed_chase])


func _is_valid(ap: Dictionary) -> bool:
	var p: CharacterBody2D = ap.player
	if not p or not is_instance_valid(p):
		return false
	if input_manager and input_manager.controlled_player == p:
		return false
	return true


func _is_penalized(ap: Dictionary) -> bool:
	var p: CharacterBody2D = ap.player
	if not p:
		return false
	var penalized_val = p.get("is_penalized")
	return penalized_val != null and penalized_val


# ==============================
# ===== 视野感知系统 ===========
# ==============================

func _is_in_field_of_view(ap: Dictionary, target_pos: Vector2) -> bool:
	"""判断目标位置是否在球员的视野锥内"""
	var my_pos: Vector2 = ap.player.global_position
	var to_target: Vector2 = (target_pos - my_pos).normalized()
	var facing: Vector2 = ap.player.facing_direction
	# 朝向未初始化时视为能看到（避免开局感知失败）
	if facing == Vector2.ZERO:
		return true
	facing = facing.normalized()
	var dot: float = facing.dot(to_target)
	var half_angle_rad: float = deg_to_rad(ap.profile.field_of_view / 2.0)
	return dot >= cos(half_angle_rad)


func _update_awareness(ap: Dictionary, delta: float) -> void:
	"""刷新AI对场上其他球员的感知"""
	var profile: AIProfile = ap.profile
	ap.awareness_timer += delta

	# 每隔 awareness_update_interval 秒刷新一次视野内的信息
	if ap.awareness_timer < profile.awareness_update_interval:
		_decay_memory(ap, delta)
		return
	ap.awareness_timer = 0.0

	var my_pos: Vector2 = ap.player.global_position

	# 遍历场上所有其他球员
	for other_ap in ai_players:
		if not _is_valid(other_ap):
			continue
		if other_ap.player == ap.player:
			continue
		var other: CharacterBody2D = other_ap.player
		var other_pos: Vector2 = other.global_position
		var dist: float = my_pos.distance_to(other_pos)
		var id: int = other.get_instance_id()

		# 在视野锥内 + 在视野距离内
		if _is_in_field_of_view(ap, other_pos) and dist <= profile.vision_range:
			var noise_scale: float = (1.0 - profile.awareness_accuracy) * 40.0
			var known_pos: Vector2 = other_pos + Vector2(
				randf_range(-noise_scale, noise_scale),
				randf_range(-noise_scale, noise_scale)
			)
			ap.known_positions[id] = {
				"pos": known_pos,
				"timer": 0.0,
				"team": other.team,
				"ref": other,
			}
		else:
			# 不在视野内:不刷新,让已有记忆自然衰减
			pass

	# 衰减记忆
	_decay_memory(ap, 0.0)


func _decay_memory(ap: Dictionary, delta: float) -> void:
	"""衰减不在视野内的已知信息"""
	var profile: AIProfile = ap.profile
	var expired_ids: Array = []
	for id in ap.known_positions:
		ap.known_positions[id]["timer"] += delta
		if ap.known_positions[id]["timer"] > profile.memory_duration:
			expired_ids.append(id)
	for id in expired_ids:
		ap.known_positions.erase(id)


func _get_known_enemies(ap: Dictionary) -> Array[Dictionary]:
	"""返回当前感知到的敌方球员列表 [{ref: CharacterBody2D, pos: Vector2}]"""
	var result: Array[Dictionary] = []
	var enemy_team: String = "b" if ap.team == "a" else "a"
	for id in ap.known_positions:
		var info: Dictionary = ap.known_positions[id]
		if info.get("team") == enemy_team and info.has("ref"):
			var ref = info["ref"]
			if is_instance_valid(ref) and not ref.is_defeated:
				result.append({"ref": ref, "pos": info["pos"]})
	return result


func _get_known_teammates(ap: Dictionary) -> Array[Dictionary]:
	"""返回当前感知到的己方AI队友列表"""
	var result: Array[Dictionary] = []
	for id in ap.known_positions:
		var info: Dictionary = ap.known_positions[id]
		if info.get("team") == ap.team and info.has("ref"):
			var ref = info["ref"]
			if is_instance_valid(ref) and ref != ap.player:
				result.append({"ref": ref, "pos": info["pos"]})
	return result


func _find_nearest_visible_enemy(ap: Dictionary) -> CharacterBody2D:
	"""找视野内最近的可见敌人(用于朝向和紧急判断)"""
	var enemies: Array[Dictionary] = _get_known_enemies(ap)
	var nearest: CharacterBody2D = null
	var nearest_dist: float = INF
	var my_pos: Vector2 = ap.player.global_position
	for e in enemies:
		var dist: float = my_pos.distance_to(e["pos"])
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = e["ref"]
	return nearest


# ==============================
# ===== 朝向系统 ===============
# ==============================

func _update_facing(ap: Dictionary, delta: float) -> void:
	"""根据当前状态和profile的朝向策略更新球员朝向"""
	# 如果还没有朝向（刚创建），先初始化
	if ap.player.facing_direction == Vector2.ZERO:
		ap.player.facing_direction = Vector2(1, 0) if ap.team == "a" else Vector2(-1, 0)

	var facing_mode: String = "move"
	match ap.state:
		State.CHASE_BALL, State.GOTO_BALL:
			facing_mode = ap.profile.facing_mode_chase
		State.DRIBBLE:
			facing_mode = ap.profile.facing_mode_dribble
		State.SUPPORT:
			facing_mode = ap.profile.facing_mode_support
		State.DEFEND, State.READY_CATCH:
			facing_mode = ap.profile.facing_mode_defend
		_:
			facing_mode = "move"

	var facing_target: Vector2 = _get_facing_target(ap, facing_mode)
	if facing_target == Vector2.ZERO:
		return

	# 平滑旋转(模拟转身速度)
	var current: Vector2 = ap.player.facing_direction.normalized()
	var angle_diff: float = current.angle_to(facing_target)
	var max_turn: float = TURN_SPEED * delta

	if abs(angle_diff) < max_turn:
		ap.player.facing_direction = facing_target.normalized()
	else:
		ap.player.facing_direction = current.rotated(sign(angle_diff) * max_turn).normalized()


func _get_facing_target(ap: Dictionary, mode: String) -> Vector2:
	"""根据模式计算目标朝向"""
	match mode:
		"ball":
			if ball_node:
				return (ball_node.global_position - ap.player.global_position).normalized()
			return ap.player.facing_direction
		"move":
			var vel: Vector2 = ap.player.velocity
			if vel.length() > 1.0:
				return vel.normalized()
			return ap.player.facing_direction
		"enemy":
			var nearest: CharacterBody2D = _find_nearest_visible_enemy(ap)
			if nearest and is_instance_valid(nearest):
				return (nearest.global_position - ap.player.global_position).normalized()
			if ball_node:
				return (ball_node.global_position - ap.player.global_position).normalized()
			return ap.player.facing_direction
		"goal":
			var goal: Vector2 = GOAL_A if ap.team == "a" else GOAL_B
			return (goal - ap.player.global_position).normalized()
		_:
			return ap.player.facing_direction


# ==============================
# ===== 决策(核心逻辑)========
# ==============================

func _decide(ap: Dictionary) -> void:
	var p: CharacterBody2D = ap.player
	var team: String = ap.team
	var profile: AIProfile = ap.profile

	# 被惩罚的球员：在外场内执行战术移动
	if _is_penalized(ap):
		_decide_penalty_move(ap)
		return

	# 持球：进入持球决策
	if p.is_carrying_ball:
		_decide_carrying(ap)
		return

	# 更新持球观察计时（未持球时重置）
	ap.hold_timer = 0.0

	var ball_pos: Vector2 = ball_node.global_position
	var ball_active: bool = ball_node.is_active
	var my_pos: Vector2 = p.global_position
	var dist_to_ball: float = my_pos.distance_to(ball_pos)
	var aggro: float = profile.aggro_range

	# === 防御接球判定 ===
	if ball_active:
		var ball_dir: Vector2 = ball_node.ball_direction
		if _should_enter_catch_state(ap, ball_pos, ball_dir):
			ap.state = State.READY_CATCH
			ap.target_pos = p.global_position
			if p.has_method("enter_catch_state"):
				p.enter_catch_state()
			return
	
	# === 通信系统：响应玩家指令 ===
	if battle_manager and battle_manager.comm_system:
		# 防守警报：对手持球时全员准备接球
		if battle_manager.comm_system.has_defend_alert(team):
			if not ball_node.owner_player or ball_node.owner_player.team != team:
				ap.state = State.READY_CATCH
				ap.target_pos = p.global_position
				if p.has_method("enter_catch_state"):
					p.enter_catch_state()
				return
		
		# 传球给我：持球的AI队友优先传球给发指令者
		if battle_manager.comm_system.has_pass_to_me(team) and p.is_carrying_ball:
			var pass_target: CharacterBody2D = battle_manager.comm_system.get_pass_to_me_sender(team)
			if pass_target and is_instance_valid(pass_target):
				ap.state = State.PASS
				ap.target_pos = pass_target.global_position
				ap.hold_timer = 0.0
				print("[AI] %s 响应'传我'指令" % _pname(p))
				return

	# === 状态防抖：如果在当前位置附近已到达目标，不要重复切换 ===
	var at_target: bool = my_pos.distance_to(ap.target_pos) < profile.arrive_threshold * 2.0
	var current_state: int = ap.state

	# 球在飞行中
	if ball_active:
		if _am_i_closest_to_ball(ap, team) and dist_to_ball < aggro:
			# over_chase 弱点：允许过半场追球
			var chase_pos: Vector2
			if profile.weakness_overextend:
				chase_pos = ball_pos  # 不限制半场
			else:
				chase_pos = _clamp_to_half_field(ball_pos, team)
			var new_state: int = State.CHASE_BALL
			if new_state != current_state or not at_target:
				ap.state = new_state
				ap.target_pos = chase_pos
		else:
				# 非追球球员：按角色分化
				_decide_off_ball_role(ap, ball_pos)
				if p.has_method("exit_catch_state"):
					p.exit_catch_state()
		return

	# 球落地没人拿
	if not ball_node.owner_player:
		if dist_to_ball < aggro:
			# over_chase 弱点：不管半场都追
			var should_chase: bool
			if profile.weakness_overextend:
				should_chase = true
			else:
				should_chase = (team == "a" and ball_pos.x <= 0) or (team == "b" and ball_pos.x >= 0)
			if should_chase:
				ap.state = State.GOTO_BALL
				ap.target_pos = _clamp_to_half_field(ball_pos, team)
			else:
				_decide_off_ball_role(ap, ball_pos)
		else:
			_decide_off_ball_role(ap, ball_pos)
			if p.has_method("exit_catch_state"):
				p.exit_catch_state()
		return

	# 球有人拿着：区分队友还是对手
	if ball_node.owner_player.team == team:
		# 球在队友手里：按角色分化跑位
		_decide_teammate_has_ball(ap)
	else:
		# 球在对手手里：防守站位+冲刺保护倾向
		_decide_enemy_has_ball(ap)
	if p.has_method("exit_catch_state"):
		p.exit_catch_state()


# ==============================
# ===== 角色分化行为 ===========
# ==============================

func _decide_off_ball_role(ap: Dictionary, ball_pos: Vector2) -> void:
	"""无球且不需要追球时，按角色选择行为"""
	var profile: AIProfile = ap.profile
	match profile.role:
		"defender":
			# 防御手：看球是否飞向己方，尝试拦截
			if ball_node.is_active:
				if _should_intercept_for_team(ap, ball_pos):
					ap.state = State.READY_CATCH
					ap.target_pos = ap.player.global_position
					if ap.player.has_method("enter_catch_state"):
						ap.player.enter_catch_state()
					return  # 无论有没有enter_catch_state，已决定拦截
			# 没有拦截机会：跑保护位
			ap.state = State.DEFEND
			ap.target_pos = _get_protect_pos(ap)
		"supporter":
			# 辅助手：看球是否飞向己方，尝试拦截
			if ball_node.is_active:
				if _should_intercept_for_team(ap, ball_pos):
					ap.state = State.READY_CATCH
					ap.target_pos = ap.player.global_position
					if ap.player.has_method("enter_catch_state"):
						ap.player.enter_catch_state()
					return  # 无论有没有enter_catch_state，已决定拦截
			# 跑接应位
			ap.state = State.SUPPORT
			ap.target_pos = _get_assist_pos(ap)
		_:
			# 主攻手：跑前方进攻位等待传球
			ap.state = State.SUPPORT
			ap.target_pos = _get_attack_wait_pos(ap)


func _decide_teammate_has_ball(ap: Dictionary) -> void:
	"""球在队友手里：按角色分化"""
	var profile: AIProfile = ap.profile
	match profile.role:
		"defender":
			# 防御手：跑到持球者与最近敌人之间，保护持球者
			ap.state = State.DEFEND
			ap.target_pos = _get_protect_pos(ap)
		"supporter":
			# 辅助手：跑到持球者侧面方便接应传球
			ap.state = State.SUPPORT
			ap.target_pos = _get_assist_pos(ap)
		_:
			# 主攻手：跑到前方等传球，准备进攻
			ap.state = State.SUPPORT
			ap.target_pos = _get_attack_wait_pos(ap)


func _decide_enemy_has_ball(ap: Dictionary) -> void:
	"""对手持球时：保持阵型站位，有冲刺保护/拦截倾向"""
	var p: CharacterBody2D = ap.player
	var team: String = ap.team
	var profile: AIProfile = ap.profile
	var my_pos: Vector2 = p.global_position
	var ball_pos: Vector2 = ball_node.global_position
	var enemy_carrier: CharacterBody2D = ball_node.owner_player
	var dist_to_ball: float = my_pos.distance_to(ball_pos)

	# === 角色分化拦截：近距离时冲刺逼抢 ===
	# 主攻手/辅助手：如果离对手持球者近，有冲刺逼抢倾向
	if profile.role != "defender":
		if dist_to_ball < profile.aggro_range * 0.8:
			# 检查是否是最接近对手持球者的己方球员
			if _am_i_closest_to_pos(ap, team, enemy_carrier.global_position):
				ap.state = State.CHASE_BALL
				var chase_pos: Vector2
				if profile.weakness_overextend:
					chase_pos = enemy_carrier.global_position
				else:
					chase_pos = _clamp_to_half_field(enemy_carrier.global_position, team)
				ap.target_pos = chase_pos
				return

	# === 防御手：如果对手逼近，上前保护 ===
	if profile.role == "defender":
		# 对手持球者在己方半场→上前保护
		var enemy_in_my_half: bool = false
		if team == "a" and enemy_carrier.global_position.x < 0:
			enemy_in_my_half = true
		elif team == "b" and enemy_carrier.global_position.x > 0:
			enemy_in_my_half = true
		if enemy_in_my_half and dist_to_ball < profile.aggro_range:
			# 冲向对手持球者（保持一定距离，不贴身）
			var dir_to_enemy: Vector2 = (enemy_carrier.global_position - my_pos).normalized()
			var press_pos: Vector2 = enemy_carrier.global_position - dir_to_enemy * 60.0
			ap.state = State.DEFEND
			ap.target_pos = _clamp_to_half_field(press_pos, team)
			return

	# === 默认：回到阵型站位（保持原有场上位置） ===
	ap.state = State.DEFEND
	ap.target_pos = _get_formation_hold_pos(ap)


func _get_protect_pos(ap: Dictionary) -> Vector2:
	"""防御手：站在持球者身后（朝己方球门方向），不挡发球路线"""
	var p: CharacterBody2D = ap.player
	var team: String = ap.team
	var my_pos: Vector2 = p.global_position
	var carrier: CharacterBody2D = _get_ball_carrier(team)

	if not carrier:
		return _get_smart_support_pos(ap)

	var carrier_pos: Vector2 = carrier.global_position
	var forward: Vector2 = Vector2(1, 0) if team == "a" else Vector2(-1, 0)

	# 基准位置：持球者身后60px（朝己方球门方向）
	var protect_pos: Vector2 = carrier_pos - forward * 60.0

	# 侧向偏移：偏向最近敌人所在的一侧，方便拦截侧方来球
	var nearest_enemy: CharacterBody2D = _find_nearest_enemy_to_target(ap, carrier_pos)
	if nearest_enemy:
		var to_enemy: Vector2 = nearest_enemy.global_position - carrier_pos
		# 只取横向分量（垂直于forward方向）
		var lateral: Vector2 = to_enemy - forward * forward.dot(to_enemy)
		if lateral.length() > 10.0:
			protect_pos += lateral.normalized() * 40.0

	return _clamp_to_half_field(protect_pos, team)


func _get_assist_pos(ap: Dictionary) -> Vector2:
	"""辅助手：持球者侧方偏后，保持传球距离和宽度"""
	var p: CharacterBody2D = ap.player
	var team: String = ap.team
	var carrier: CharacterBody2D = _get_ball_carrier(team)

	if not carrier:
		return _get_smart_support_pos(ap)

	var carrier_pos: Vector2 = carrier.global_position
	var forward: Vector2 = Vector2(1, 0) if team == "a" else Vector2(-1, 0)
	var side_sign: float = 1.0 if (ap.index % 2 == 0) else -1.0
	var lateral: Vector2 = Vector2(forward.y, -forward.x) * side_sign

	# 辅助手在持球者侧方偏后：横向100px + 稍微后退20px
	var assist_pos: Vector2 = carrier_pos + lateral * 100.0 - forward * 20.0

	return _clamp_to_half_field(assist_pos, team)


func _get_attack_wait_pos(ap: Dictionary) -> Vector2:
	"""主攻手：前方等球位，不贴中线，保持纵深"""
	var p: CharacterBody2D = ap.player
	var team: String = ap.team
	var forward: Vector2 = Vector2(1, 0) if team == "a" else Vector2(-1, 0)
	var my_pos: Vector2 = p.global_position
	var ball_pos: Vector2 = ball_node.global_position
	var side_sign: float = 1.0 if (ap.index % 2 == 0) else -1.0
	var lateral: Vector2 = Vector2(forward.y, -forward.x) * side_sign

	# 中线边界
	var midline_x: float = -10.0 if team == "a" else 10.0
	# 持球者到中线的距离
	var carrier_to_mid: float = abs(ball_pos.x - midline_x)

	var ahead_pos: Vector2
	if carrier_to_mid > 120.0:
		# 持球者离中线远：主攻手到前方+侧方
		ahead_pos = ball_pos + forward * 80.0 + lateral * 60.0
		return _clamp_forward_to_boundary(ahead_pos, team, forward)
	else:
		# 持球者已接近中线：主攻手不继续前压，拉开横向宽度等球
		var safe_x: float = midline_x - forward.x * 80.0  # 离中线80px纵深
		ahead_pos = Vector2(safe_x, ball_pos.y + lateral.y * 80.0)
		return _clamp_to_half_field(ahead_pos, team)


func _should_intercept_for_team(ap: Dictionary, ball_pos: Vector2) -> bool:
	"""判断是否应该为队友拦截飞来的球（防御手/辅助手用）"""
	if not ball_node.is_active:
		return false
	var ball_dir: Vector2 = ball_node.ball_direction
	if ball_dir == Vector2.ZERO:
		return false
	# 球来自对方
	if not ball_node.attacker_player or ball_node.attacker_player.team == ap.team:
		return false
	var my_pos: Vector2 = ap.player.global_position
	var dist_to_ball: float = my_pos.distance_to(ball_pos)
	if dist_to_ball > ap.profile.vision_range:
		return false
	# 球的轨迹是否经过我附近
	var ball_to_me: Vector2 = my_pos - ball_pos
	var ball_to_me_dir: Vector2 = ball_to_me.normalized()
	var dot: float = ball_dir.dot(ball_to_me_dir)
	if dot > 0.4 and dist_to_ball < 250.0:
		return true
	return false


func _get_ball_carrier(team: String) -> CharacterBody2D:
	"""获取指定队伍的持球者"""
	if not ball_node or not ball_node.owner_player:
		return null
	if ball_node.owner_player.team == team:
		return ball_node.owner_player
	return null


func _find_nearest_enemy_to_target(ap: Dictionary, target_pos: Vector2) -> CharacterBody2D:
	"""找离指定位置最近的可见敌人（用于保护站位）"""
	var known_enemies: Array[Dictionary] = _get_known_enemies(ap)
	var nearest: CharacterBody2D = null
	var nearest_dist: float = INF
	for e in known_enemies:
		var dist: float = target_pos.distance_to(e["pos"])
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = e["ref"]
	return nearest


func _decide_carrying(ap: Dictionary) -> void:
	var p: CharacterBody2D = ap.player
	var team: String = ap.team
	var profile: AIProfile = ap.profile
	var my_pos: Vector2 = p.global_position
	var goal: Vector2 = GOAL_A if team == "a" else GOAL_B
	var forward: Vector2 = Vector2(1, 0) if team == "a" else Vector2(-1, 0)

	# === 持球总时间检查 ===
	ap.total_carry_time += profile.think_interval
	if ap.total_carry_time >= profile.max_carry_time:
		var pass_result: Dictionary = _eval_best_pass(ap)
		var pass_target: CharacterBody2D = pass_result.get("target") as CharacterBody2D if pass_result.has("target") else null
		var shoot_target: CharacterBody2D = _find_nearest_enemy(ap)

		if pass_target and randf() < 0.7:
			ap.state = State.PASS
			ap.target_pos = pass_target.global_position
			print("[AI] %s 持球超时,强制传球" % _pname(p))
		elif shoot_target:
			ap.state = State.ATTACK
			ap.target_pos = shoot_target.global_position
			print("[AI] %s 持球超时,强制投球" % _pname(p))
		else:
			ap.state = State.ATTACK
			ap.target_pos = my_pos + forward * 200.0
			print("[AI] %s 持球超时,强制向前投球" % _pname(p))
		return

	# === 持球观察期：小幅向侧方移动保持活跃 ===
	ap.hold_timer += profile.think_interval
	if ap.hold_timer < ap.hold_duration:
		ap.state = State.DRIBBLE
		# 观察期不原地踏步，慢速侧移
		var side_step: Vector2 = Vector2(forward.y, -forward.x) * (30.0 if (ap.index % 2 == 0) else -30.0)
		ap.target_pos = _clamp_forward_to_boundary(my_pos + forward * 40.0 + side_step, team, forward)
		return

	# === 观察结束,做决策 ===
	var dist_to_goal: float = my_pos.distance_to(goal)
	var enemy_near: bool = _has_visible_enemy_nearby(ap, 120.0)
	var enemy_very_close: bool = _has_visible_enemy_nearby(ap, 60.0)

	# 检查是否贴中线（无法继续前进）
	var midline_x: float = -10.0 if team == "a" else 10.0
	var at_boundary: bool = abs(my_pos.x - midline_x) < 20.0

	# 评分
	var pass_result: Dictionary = _eval_best_pass(ap)
	var pass_target: CharacterBody2D = pass_result.get("target") as CharacterBody2D if pass_result.has("target") else null
	var pass_score: float = pass_result.get("score", -INF) if pass_result.has("score") else -INF

	var shoot_target: CharacterBody2D = _find_nearest_enemy(ap)
	var shoot_score: float = _eval_shoot(ap, shoot_target, dist_to_goal)

	var dribble_score: float = _eval_dribble(ap, dist_to_goal, enemy_near)

	# === 贴中线且看不到任何目标：朝敌方半场盲投 ===
	if at_boundary and shoot_target == null and pass_target == null:
		ap.state = State.ATTACK
		var blind_target: Vector2 = my_pos + forward * 300.0 + Vector2(0, randf() * 100.0 - 50.0)
		ap.target_pos = _clamp_to_field(blind_target)
		ap.hold_timer = 0.0
		ap.hold_duration = randf_range(profile.hold_duration_min, profile.hold_duration_max)
		print("[AI] %s 贴中线无目标，盲投" % _pname(p))
		return

	# === 贴中线且只有传球目标（太近）: 强制投球或远传 ===
	if at_boundary and shoot_target == null and pass_target:
		var pass_dist: float = my_pos.distance_to(pass_target.global_position)
		if pass_dist < 80.0:
			# 队友就在旁边，朝敌人方向盲投
			ap.state = State.ATTACK
			var blind_target2: Vector2 = my_pos + forward * 300.0 + Vector2(0, randf() * 100.0 - 50.0)
			ap.target_pos = _clamp_to_field(blind_target2)
			ap.hold_timer = 0.0
			print("[AI] %s 贴中线队友太近，盲投" % _pname(p))
			return

	# === 看不到任何敌人且不在边界：前压侦查（不盲投） ===
	if shoot_target == null and not at_boundary:
		# 还没看到敌人，继续向前推进获取视野
		dribble_score += 40.0  # 大幅提高推进优先级

	# 角色加权(已包含团队策略叠加)
	pass_score += profile.weight_pass
	shoot_score += profile.weight_shoot
	dribble_score += profile.weight_dribble

	# 被逼抢时紧急处理（ball_focused 弱点不会急）
	if enemy_very_close and not profile.weakness_ignore_flank:
		if pass_target:
			pass_score += 35.0
		shoot_score += 20.0
	elif enemy_very_close and profile.weakness_ignore_flank:
		# ball_focused: 被侧面近身也不知道躲
		pass_score -= 10.0
		shoot_score += 10.0  # 反而更想投球

	# 随机因子
	var rng: float = randf() * profile.random_factor * 2.0 - profile.random_factor
	pass_score += rng
	shoot_score += rng * 0.5
	dribble_score += rng * 0.3

	# === 带球目标根据角色差异 ===
	var dribble_target: Vector2
	match profile.role:
		"attacker":
			# 主攻手：直接向前推进，加随机偏移
			dribble_target = _clamp_forward_to_boundary(my_pos + forward * 120.0 + Vector2(0, randf() * 80.0 - 40.0), team, forward)
		"defender":
			# 防御者：横向/回传球位，不冒进
			dribble_target = _clamp_to_half_field(my_pos - forward * 30.0 + Vector2(0, randf() * 60.0 - 30.0), team)
		_:
			# 支援者：斜前方
			dribble_target = _clamp_forward_to_boundary(my_pos + forward * 70.0 + Vector2(0, randf() * 100.0 - 50.0), team, forward)

	if pass_score >= shoot_score and pass_score >= dribble_score and pass_target:
		ap.state = State.PASS
		ap.target_pos = pass_target.global_position
	elif shoot_score >= dribble_score and shoot_target:
		ap.state = State.ATTACK
		ap.target_pos = shoot_target.global_position
	else:
		ap.state = State.DRIBBLE
		ap.target_pos = dribble_target

	# 投球/传球后重置观察计时
	if ap.state == State.ATTACK or ap.state == State.PASS:
		ap.hold_timer = 0.0
		ap.hold_duration = randf_range(profile.hold_duration_min, profile.hold_duration_max)


func _decide_penalty_move(ap: Dictionary) -> void:
	"""外场球员AI：与内场同等角色分化+视野感知，只是空间在外场"""
	var p: CharacterBody2D = ap.player
	var team: String = ap.team
	var profile: AIProfile = ap.profile
	var my_pos: Vector2 = p.global_position

	# === 持球 ===
	if p.is_carrying_ball:
		ap.total_carry_time += profile.think_interval

		if ap.total_carry_time >= profile.max_carry_time:
			var pass_result: Dictionary = _eval_best_pass(ap)
			var pass_target: CharacterBody2D = pass_result.get("target") as CharacterBody2D if pass_result.has("target") else null
			var shoot_target: CharacterBody2D = _find_nearest_enemy(ap)

			if pass_target and randf() < 0.7:
				ap.state = State.PASS
				ap.target_pos = pass_target.global_position
			elif shoot_target:
				ap.state = State.ATTACK
				ap.target_pos = shoot_target.global_position
			else:
				var fwd: Vector2 = Vector2(1, 0) if team == "a" else Vector2(-1, 0)
				ap.state = State.ATTACK
				# 无目标时朝内场方向投（不是朝外场围墙）
				var fallback: Vector2 = Vector2(-190.0, 0.0) if team == "a" else Vector2(190.0, 0.0)
				ap.target_pos = fallback
			return

		# 观察期
		ap.hold_timer += profile.think_interval
		if ap.hold_timer < ap.hold_duration:
			var random_dir: Vector2 = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
			ap.state = State.PENALTY_MOVE
			ap.target_pos = _clamp_to_outer_field(my_pos + random_dir * 50.0, team)
			return

		# 决策传球或攻击
		var pass_result: Dictionary = _eval_best_pass(ap)
		var pass_target: CharacterBody2D = pass_result.get("target") as CharacterBody2D if pass_result.has("target") else null
		var pass_score: float = pass_result.get("score", -INF) if pass_result.has("score") else -INF
		var shoot_target: CharacterBody2D = _find_nearest_enemy(ap)
		var shoot_score: float = _eval_shoot(ap, shoot_target, my_pos.distance_to(Vector2.ZERO))

		pass_score += 20.0  # 外场偏向传球

		if pass_score >= shoot_score and pass_target:
			ap.state = State.PASS
			ap.target_pos = pass_target.global_position
		else:
			ap.state = State.ATTACK
			if shoot_target:
				ap.target_pos = shoot_target.global_position
			else:
				# 外场无目标：朝内场中心投
				var fallback: Vector2 = Vector2(-190.0, 0.0) if team == "a" else Vector2(190.0, 0.0)
				ap.target_pos = fallback
		return

	# === 无球 ===
	var ball_pos: Vector2 = ball_node.global_position
	var ball_active: bool = ball_node.is_active
	var dist_to_ball: float = my_pos.distance_to(ball_pos)

	# === 球飞向外场：根据角色判断行为 ===
	# 外场球员接球范围扩大（外场离内场远）
	var outer_aggro: float = profile.aggro_range * 1.5  # 外场追球范围1.5倍
	if ball_active:
		var ball_dir: Vector2 = ball_node.ball_direction
		if ball_dir == Vector2.ZERO:
			ball_dir = Vector2(-1, 0) if team == "a" else Vector2(1, 0)

		# 防御手/辅助手：尝试拦截飞经外场的球
		if profile.role == "defender" or profile.role == "supporter":
			if _should_intercept_for_team(ap, ball_pos):
				ap.state = State.READY_CATCH
				ap.target_pos = my_pos
				if p.has_method("enter_catch_state"):
					p.enter_catch_state()
				return

		# 所有角色：看球是否飞向外场方向，预测落点拦截
		for i in range(30):  # 增加预测步数
			var predicted_pos: Vector2 = ball_pos + ball_dir * (i * 30.0)
			if predicted_pos.distance_to(my_pos) < outer_aggro:
				var intercept_pos: Vector2 = ball_pos + ball_dir * 60.0
				ap.state = State.PENALTY_MOVE
				ap.target_pos = _clamp_to_outer_field(intercept_pos, team)
				return
			# 球飞出场地范围就停止预测
			if abs(predicted_pos.x) > 600.0 or abs(predicted_pos.y) > 400.0:
				break

	# 球落地没人拿且在外场附近（扩大追球范围）
	if not ball_node.owner_player:
		if dist_to_ball < outer_aggro:
			ap.state = State.GOTO_BALL
			ap.target_pos = _clamp_to_outer_field(ball_pos, team)
			return

	# === 按角色跑位（与内场同等逻辑） ===
	var outer_base: Vector2
	match profile.role:
		"defender":
			# 防御手：外场主体中心偏后，观察内场
			if team == "a":
				outer_base = Vector2(460.0, 0.0)
			else:
				outer_base = Vector2(-460.0, 0.0)
		"supporter":
			# 辅助手：外场主体偏侧，保持宽度
			if team == "a":
				outer_base = Vector2(450.0, 100.0) if (ap.index % 2 == 0) else Vector2(450.0, -100.0)
			else:
				outer_base = Vector2(-450.0, 100.0) if (ap.index % 2 == 0) else Vector2(-450.0, -100.0)
		_:
			# 主攻手：外场主体前侧(靠近主体内壁)
			if team == "a":
				outer_base = Vector2(400.0, 0.0)
			else:
				outer_base = Vector2(-400.0, 0.0)

	# 球吸引偏移
	var ball_pull: Vector2 = Vector2.ZERO
	var ball_coming_to_outer: bool = false
	var ball_dir_to_me: Vector2 = (ball_pos - my_pos)
	if ball_dir_to_me.length() > 0:
		ball_dir_to_me = ball_dir_to_me.normalized()
		if team == "a" and ball_dir_to_me.x > 0.3:
			ball_coming_to_outer = true
		elif team == "b" and ball_dir_to_me.x < -0.3:
			ball_coming_to_outer = true
	if ball_coming_to_outer and dist_to_ball < 300.0:
		ball_pull = ball_dir_to_me * 30.0 * profile.ball_attract_weight

	var smart_pos: Vector2 = outer_base + ball_pull
	var random_offset: Vector2 = Vector2(randf_range(-30.0, 30.0), randf_range(-40.0, 40.0))

	# 避让玩家控制球员（外场空间小，不要挡路）
	if input_manager and input_manager.controlled_player:
		var ctrl_p: CharacterBody2D = input_manager.controlled_player
		if ctrl_p.team == ap.team and ctrl_p != p:
			var to_ctrl: Vector2 = ctrl_p.global_position - smart_pos
			if to_ctrl.length() < 80.0 and to_ctrl.length() > 0.0:
				smart_pos -= to_ctrl.normalized() * (80.0 - to_ctrl.length()) * 0.8

	ap.state = State.PENALTY_MOVE
	ap.target_pos = _clamp_to_outer_field(smart_pos + random_offset, team)



# ==============================
# ===== 行动评分 ================
# ==============================

func _eval_best_pass(ap: Dictionary) -> Dictionary:
	"""评估最佳传球目标,返回 {target, score}"""
	var p: CharacterBody2D = ap.player
	var team: String = ap.team
	var profile: AIProfile = ap.profile
	var goal: Vector2 = GOAL_A if team == "a" else GOAL_B
	var forward: Vector2 = Vector2(1, 0) if team == "a" else Vector2(-1, 0)
	var best: CharacterBody2D = null
	var best_score: float = -INF

	# 获取感知到的队友
	var known_teammates: Array[Dictionary] = _get_known_teammates(ap)

	for tm_info in known_teammates:
		var tm: CharacterBody2D = tm_info["ref"]
		var tm_pos: Vector2 = tm_info["pos"]  # 可能带偏差的已知位置
		var dist: float = p.global_position.distance_to(tm_pos)

		if dist < 40.0 or dist > profile.pass_range:
			continue

		var score: float = 0.0

		# 1) 目标离对方球门越近越好
		var tm_goal_dist: float = tm_pos.distance_to(goal)
		score += (300.0 - tm_goal_dist) * 0.1

		# 2) 目标附近有无敌人(用感知数据)
		var tm_has_enemy: bool = false
		var known_enemies: Array[Dictionary] = _get_known_enemies(ap)
		for e_info in known_enemies:
			if tm_pos.distance_to(e_info["pos"]) < 80.0:
				tm_has_enemy = true
				break
		if not tm_has_enemy:
			score += 30.0
		else:
			score -= 20.0

		# 3) 传球方向偏好
		var to_tm: Vector2 = (tm_pos - p.global_position).normalized()
		if profile.prefer_forward_pass:
			score += forward.dot(to_tm) * 20.0
		else:
			score += abs(forward.dot(to_tm)) * 5.0

		# 4) 距离适中
		if dist > profile.prefer_distance_min and dist < profile.prefer_distance_max:
			score += 15.0
		elif dist < 80.0:
			score -= 10.0

		# 5) 不要传给刚传过来的人
		if ball_node and ball_node.attacker_player == tm:
			score -= 25.0

		# 6) 通信消息影响:传球给我 / 别传球
		if battle_manager and battle_manager.comm_system:
			score += battle_manager.comm_system.get_pass_to_me_bonus(tm)
			if battle_manager.comm_system.is_dont_pass_active(tm):
				score -= 30.0  # 有人喊了"别传"

		if score > best_score:
			best_score = score
			best = tm

	if best:
		return {"target": best, "score": best_score}
	return {}


func _eval_shoot(ap: Dictionary, target: CharacterBody2D, dist_to_goal: float) -> float:
	"""评估投球攻击评分"""
	if not target:
		return -INF

	var p: CharacterBody2D = ap.player
	var dist: float = p.global_position.distance_to(target.global_position)
	var score: float = 0.0

	# 距离评分（鼓励AI主动投球，远距离也有价值）
	if dist < 150.0:
		score += 45.0  # 近距离高价值
	elif dist < 250.0:
		score += 30.0
	elif dist < 350.0:
		score += 20.0
	else:
		score += 10.0  # 远距离也能打

	# 目标状态评分
	if not target.is_ready_to_catch:
		score += 25.0  # 目标没防备，更好打
	else:
		score -= 10.0  # 目标在待接球，有韧性减伤风险

	# 接近中线时投球更有价值（不能再带球了）
	if dist_to_goal < 200.0:
		score += 15.0

	# 角色修正：主攻手投球加分
	match ap.profile.role:
		"attacker":
			score += 10.0  # 主攻手更敢投
		"defender":
			score -= 5.0   # 防御手不太投

	return score


func _eval_dribble(ap: Dictionary, dist_to_goal: float, enemy_near: bool) -> float:
	"""评估带球推进评分"""
	var score: float = 10.0

	if dist_to_goal > 200.0:
		score += 15.0

	if not enemy_near:
		score += 20.0
	else:
		score -= 15.0

	return score


# ==============================
# ===== 移动执行 ================
# ==============================

func _move(ap: Dictionary, delta: float) -> void:
	var p: CharacterBody2D = ap.player

	# 击退中：不覆盖velocity，只执行move_and_slide
	if p._knockback_timer > 0.0:
		p.move_and_slide()
		return

	var profile: AIProfile = ap.profile
	# 目标位置先限制到合法范围
	var raw_target: Vector2 = ap.target_pos
	var target: Vector2
	if _is_penalized(ap):
		target = _clamp_to_outer_field(raw_target, ap.team)
	else:
		target = _clamp_to_half_field(raw_target, ap.team)
	ap.target_pos = target  # 回写合法化的目标
	var dist: float = p.global_position.distance_to(target)
	var arrive: float = profile.arrive_threshold

	match ap.state:
		State.IDLE:
			p.velocity = Vector2.ZERO

		State.CHASE_BALL, State.GOTO_BALL:
			if dist < arrive:
				_try_pickup_ball(ap)
				p.velocity = Vector2.ZERO
			else:
				p.velocity = (target - p.global_position).normalized() * profile.speed_chase
				p.move_and_slide()

		State.DRIBBLE:
			if not p.is_carrying_ball:
				ap.state = State.IDLE
				ap.total_carry_time = 0.0
				return

			# 卡住检测
			var current_pos: Vector2 = p.global_position
			var moved_distance: float = current_pos.distance_to(ap.get("last_pos", Vector2.ZERO))
			ap.last_pos = current_pos

			if moved_distance < 2.0 and dist > arrive:
				ap.stuck_timer = ap.get("stuck_timer", 0.0) + delta
			else:
				ap.stuck_timer = 0.0

			if ap.get("stuck_timer", 0.0) > 1.0:
				print("[AI] %s 卡住,改变策略" % _pname(p))
				var fwd: Vector2 = Vector2(1, 0) if ap.team == "a" else Vector2(-1, 0)
				var midline_x: float = -10.0 if ap.team == "a" else 10.0
				var at_boundary: bool = abs(current_pos.x - midline_x) < 30.0

				if at_boundary:
					# 贴中线卡死 → 强制投球（不再尝试移动）
					var shoot_target: CharacterBody2D = _find_nearest_enemy(ap)
					if shoot_target:
						ap.state = State.ATTACK
						ap.target_pos = shoot_target.global_position
					else:
						ap.state = State.ATTACK
						ap.target_pos = current_pos + fwd * 300.0
						print("[AI] %s 贴中线卡死，强制投球" % _pname(p))
					ap.stuck_timer = 0.0
				else:
					# 非中线卡死 → 尝试传球或换方向
					var pass_result: Dictionary = _eval_best_pass(ap)
					var pass_target: CharacterBody2D = pass_result.get("target") as CharacterBody2D if pass_result.has("target") else null
					if pass_target:
						ap.state = State.PASS
						ap.target_pos = pass_target.global_position
					else:
						var new_target: Vector2 = _clamp_forward_to_boundary(current_pos + fwd * 100.0 + Vector2(randf_range(-50.0, 50.0), randf_range(-80.0, 80.0)), ap.team, fwd)
						if new_target.distance_to(current_pos) < 30.0:
							var shoot_target2: CharacterBody2D = _find_nearest_enemy(ap)
							if shoot_target2:
								ap.state = State.ATTACK
								ap.target_pos = shoot_target2.global_position
							else:
								ap.state = State.ATTACK
								ap.target_pos = current_pos + fwd * 300.0
						else:
							ap.target_pos = new_target
					ap.stuck_timer = 0.0

			if dist < arrive:
				ap.hold_timer = 0.0
				ap.hold_duration = randf_range(profile.hold_duration_min, profile.hold_duration_max)
				p.velocity = Vector2.ZERO
				_force_redecide_if_at_boundary(ap)
			else:
				p.velocity = (target - p.global_position).normalized() * profile.speed_dribble
				p.move_and_slide()

		State.ATTACK:
			if p.is_carrying_ball:
				_do_shoot(ap)
				ap.total_carry_time = 0.0
			else:
				ap.state = State.IDLE

		State.PASS:
			if p.is_carrying_ball:
				_do_pass(ap)
				ap.total_carry_time = 0.0
			else:
				ap.state = State.IDLE

		State.DEFEND:
			if dist < arrive:
				p.velocity = Vector2.ZERO
				_force_redecide_if_at_boundary(ap)
			else:
				p.velocity = (target - p.global_position).normalized() * profile.speed_move
				p.move_and_slide()

		State.SUPPORT:
			if dist < arrive:
				p.velocity = Vector2.ZERO
				_force_redecide_if_at_boundary(ap)
			else:
				p.velocity = (target - p.global_position).normalized() * profile.speed_move
				p.move_and_slide()

		State.PENALTY_MOVE:
			if dist < arrive:
				p.velocity = Vector2.ZERO
				if randf() < 0.05:
					var base_pos: Vector2 = Vector2(450.0, 0.0) if ap.team == "a" else Vector2(-450.0, 0.0)
					var random_offset: Vector2 = Vector2(randf_range(-80.0, 80.0), randf_range(-120.0, 120.0))
					ap.target_pos = _clamp_to_outer_field(base_pos + random_offset, ap.team)
			else:
				var move_dir: Vector2 = (target - p.global_position).normalized()
				# 外场AI避让玩家控制球员
				if input_manager and input_manager.controlled_player:
					var ctrl_p: CharacterBody2D = input_manager.controlled_player
					if ctrl_p.team == ap.team and ctrl_p != p:
						var to_ctrl: Vector2 = ctrl_p.global_position - p.global_position
						var ctrl_dist: float = to_ctrl.length()
						if ctrl_dist < 70.0 and ctrl_dist > 0.0:
							# 玩家太近：添加避让力（反向推开）
							var avoid_dir: Vector2 = -to_ctrl.normalized()
							var avoid_strength: float = (70.0 - ctrl_dist) / 70.0  # 越近越强
							move_dir = (move_dir + avoid_dir * avoid_strength * 2.0).normalized()
				p.velocity = move_dir * profile.speed_move
				p.move_and_slide()

		State.READY_CATCH:
			p.velocity = Vector2.ZERO
			if not ball_node.is_active or ball_node.owner_player:
				ap.state = State.IDLE
				if p.has_method("exit_catch_state"):
					p.exit_catch_state()

	_clamp_player_position(p)


# ==============================
# ===== 传球和投球 ==============
# ==============================

func _do_pass(ap: Dictionary) -> void:
	var p: CharacterBody2D = ap.player
	if not p.is_carrying_ball or not ball_node:
		return

	var target_pos: Vector2 = ap.target_pos
	var direction: Vector2 = (target_pos - p.global_position).normalized()

	# 传球方向偏差
	var error: float = ap.profile.pass_angle_error
	if error > 0:
		direction = direction.rotated(deg_to_rad(randf_range(-error, error)))

	var distance: float = p.global_position.distance_to(target_pos)

	p.set_carrying_ball(false)
	ball_node.launch(p.global_position, direction, p.attack_power * 0.5, distance + 80.0, p, [] as Array[Dictionary])

	ap.state = State.DEFEND
	ap.target_pos = ap.home_pos
	print("[AI] %s 传球!" % _pname(p))


func _do_shoot(ap: Dictionary) -> void:
	var p: CharacterBody2D = ap.player
	if not p.is_carrying_ball or not ball_node:
		return

	var target_pos: Vector2 = ap.target_pos
	var my_pos: Vector2 = p.global_position
	var shoot_dir: Vector2
	var shoot_dist: float = 500.0  # 默认飞行距离

	if target_pos != Vector2.ZERO:
		var to_target: Vector2 = target_pos - my_pos
		shoot_dir = to_target.normalized()
		shoot_dist = clampf(to_target.length() + 80.0, 200.0, 600.0)  # 目标距离+余量，上限600
	else:
		# 无目标：朝对方半场中心方向投
		var fallback_target: Vector2 = Vector2(-190.0, 0.0) if p.team == "a" else Vector2(190.0, 0.0)
		shoot_dir = (fallback_target - my_pos).normalized()
		shoot_dist = 400.0

	# 投球方向偏差
	var error: float = ap.profile.shoot_angle_error
	if error > 0:
		shoot_dir = shoot_dir.rotated(deg_to_rad(randf_range(-error, error)))

	p.set_carrying_ball(false)
	ball_node.launch(p.global_position, shoot_dir, p.attack_power, shoot_dist, p, [] as Array[Dictionary])

	ap.state = State.DEFEND
	ap.target_pos = ap.home_pos
	print("[AI] %s 投球! 目标距离=%.0f 飞行距离=%.0f" % [_pname(p), my_pos.distance_to(target_pos), shoot_dist])


func _try_pickup_ball(ap: Dictionary) -> void:
	if not ball_node:
		return
	if ball_node.is_active:
		return
	if ball_node.owner_player:
		return
	ball_node.return_to_player(ap.player)
	ap.hold_timer = 0.0
	ap.hold_duration = randf_range(ap.profile.hold_duration_min, ap.profile.hold_duration_max)
	ap.total_carry_time = 0.0
	ap.stuck_timer = 0.0
	ap.last_pos = ap.player.global_position


func _get_formation_hold_pos(ap: Dictionary) -> Vector2:
	"""获取阵型站位（防守时保持站位用）"""
	var team: String = ap.team
	var profile: AIProfile = ap.profile

	# 获取阵型偏移
	var formation: Dictionary = AIProfile.get_formation_positions(profile.team_strategy_name)
	var role_name: String = profile.role
	var formation_pos: Vector2 = formation.get(role_name, Vector2.ZERO)
	if team == "b":
		formation_pos.x = -formation_pos.x

	# 己方半场中心 + 阵型偏移
	var half_center: Vector2 = Vector2(-190.0, 0.0) if team == "a" else Vector2(190.0, 0.0)
	var base_pos: Vector2 = half_center + formation_pos

	# 球位置微弱吸引（防守时只微微偏向球的方向）
	var ball_pos: Vector2 = ball_node.global_position
	var ball_in_my_half: bool = (team == "a" and ball_pos.x < 0) or (team == "b" and ball_pos.x > 0)
	if ball_in_my_half:
		var ball_pull: Vector2 = (ball_pos - base_pos).normalized() * 20.0 * profile.ball_attract_weight
		base_pos += ball_pull

	return _clamp_to_half_field(base_pos, team)


func _am_i_closest_to_pos(ap: Dictionary, team: String, target_pos: Vector2) -> bool:
	"""判断自己是否是己方离目标位置最近的AI球员"""
	var my_pos: Vector2 = ap.player.global_position
	var my_dist: float = my_pos.distance_to(target_pos)
	for other in ai_players:
		if other.team != team:
			continue
		if other.player == ap.player:
			continue
		if not _is_valid(other):
			continue
		var other_dist: float = other.player.global_position.distance_to(target_pos)
		if other_dist < my_dist:
			return false
	return true


# ==============================
# ===== 阵型跑位系统 ============
# ==============================

func _get_smart_support_pos(ap: Dictionary) -> Vector2:
	"""基于阵型模板的智能跑位"""
	var p: CharacterBody2D = ap.player
	var team: String = ap.team
	var profile: AIProfile = ap.profile
	var my_pos: Vector2 = p.global_position
	var ball_pos: Vector2 = ball_node.global_position

	# 获取阵型位置（相对偏移）
	var formation: Dictionary = AIProfile.get_formation_positions(profile.team_strategy_name)
	var role_name: String = profile.role
	var formation_pos: Vector2 = formation.get(role_name, Vector2.ZERO)

	# 队B的阵型x坐标取反
	if team == "b":
		formation_pos.x = -formation_pos.x

	# 己方半场中心
	var half_center: Vector2 = Vector2(-190.0, 0.0) if team == "a" else Vector2(190.0, 0.0)
	var base_pos: Vector2 = half_center + formation_pos

	# 球位置吸引（球在己方半场时被吸引，球在对方半场时微微靠近中线）
	var ball_in_my_half: bool = (team == "a" and ball_pos.x < 0) or (team == "b" and ball_pos.x > 0)
	if ball_in_my_half:
		var ball_pull: Vector2 = (ball_pos - base_pos).normalized() * 40.0 * profile.ball_attract_weight
		base_pos += ball_pull
	else:
		# 球在对方半场时，微微向中线靠近（准备接应）
		var midline_pull: Vector2 = Vector2(20.0, 0.0) if team == "a" else Vector2(-20.0, 0.0)
		base_pos += midline_pull

	# 队友散开力
	var spread_offset: Vector2 = Vector2.ZERO
	for other in ai_players:
		if other.team != team:
			continue
		if other.player == p:
			continue
		if not _is_valid(other):
			continue
		var other_pos: Vector2 = other.player.global_position
		var d: float = my_pos.distance_to(other_pos)
		if d < 120.0 and d > 0.0:
			spread_offset += (my_pos - other_pos).normalized() * (120.0 - d) * 0.6 * profile.spread_force

	base_pos += spread_offset

	# clamp到半场内
	return _clamp_to_half_field(base_pos, team)


# ==============================
# ===== 辅助函数 ================
# ==============================

func _should_enter_catch_state(ap: Dictionary, ball_pos: Vector2, ball_dir: Vector2) -> bool:
	"""判断是否应该进入待接球防御状态"""
	var p: CharacterBody2D = ap.player
	var my_pos: Vector2 = p.global_position
	var dist_to_ball: float = my_pos.distance_to(ball_pos)

	if dist_to_ball > ap.profile.vision_range * 0.6:
		return false

	if not ball_node.is_active:
		return false

	# 球来自敌队才需要防御
	var ball_from_enemy: bool = false
	if ball_node.attacker_player:
		ball_from_enemy = ball_node.attacker_player.team != ap.team
	if not ball_from_enemy:
		return false

	# 检查球是否在视野内
	if not _is_in_field_of_view(ap, ball_pos):
		# 球不在视野内,但如果很近也能感知(本能反应)
		if dist_to_ball > 80.0:
			return false

	var ball_to_me: Vector2 = my_pos - ball_pos
	var ball_to_me_dir: Vector2 = ball_to_me.normalized()
	var dot_product: float = ball_dir.dot(ball_to_me_dir)

	if dot_product > 0.5:
		return true

	return false


func _am_i_closest_to_ball(ap: Dictionary, team: String) -> bool:
	var p: CharacterBody2D = ap.player
	var ball_pos: Vector2 = ball_node.global_position
	var my_dist: float = p.global_position.distance_to(ball_pos)

	for other in ai_players:
		if other.team != team:
			continue
		if other.player == p:
			continue
		if not _is_valid(other):
			continue
		if other.player.global_position.distance_to(ball_pos) < my_dist:
			return false
	return true


func _find_nearest_enemy(ap: Dictionary) -> CharacterBody2D:
	"""基于感知系统找最近敌人，视野外全局兜底"""
	# 弱点:predictable_target
	if ap.profile.weakness == "predictable_target":
		var last: CharacterBody2D = ap.last_shoot_target
		if last and is_instance_valid(last) and not last.is_defeated:
			if randf() < 0.7:
				return last

	# 优先：视野感知内的敌人
	var known_enemies: Array[Dictionary] = _get_known_enemies(ap)
	var nearest: CharacterBody2D = null
	var nearest_dist: float = INF
	var my_pos: Vector2 = ap.player.global_position

	for e in known_enemies:
		var dist: float = my_pos.distance_to(e["pos"])
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = e["ref"]

	if nearest:
		ap.last_shoot_target = nearest
		return nearest

	# 兜底：视野内没有敌人，从全局找最近的活跃敌人
	var enemy_team: String = "b" if ap.team == "a" else "a"
	for other_ap in ai_players:
		if other_ap.team != enemy_team:
			continue
		var other: CharacterBody2D = other_ap.player
		if not other or not is_instance_valid(other):
			continue
		if other.is_defeated:
			continue
		var dist: float = my_pos.distance_to(other.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = other

	if nearest:
		ap.last_shoot_target = nearest
	return nearest


func _has_visible_enemy_nearby(ap: Dictionary, range_val: float) -> bool:
	"""基于感知系统判断是否有可见敌人在范围内"""
	var known_enemies: Array[Dictionary] = _get_known_enemies(ap)
	var my_pos: Vector2 = ap.player.global_position
	for e in known_enemies:
		if my_pos.distance_to(e["pos"]) < range_val:
			return true
	return false


func _clamp_to_field(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, FIELD_X_MIN, FIELD_X_MAX),
		clampf(pos.y, FIELD_Y_MIN, FIELD_Y_MAX)
	)


func _clamp_to_half_field(pos: Vector2, team: String) -> Vector2:
	"""限制在己方半场内(目标位置合法化,避免死循环)"""
	var x_min: float = FIELD_X_MIN
	var x_max: float = FIELD_X_MAX
	if team == "a":
		x_max = -10.0  # 队A不超过中线左侧10px
	elif team == "b":
		x_min = 10.0   # 队B不超过中线右侧10px
	return Vector2(
		clampf(pos.x, x_min, x_max),
		clampf(pos.y, FIELD_Y_MIN, FIELD_Y_MAX)
	)


func _clamp_forward_to_boundary(pos: Vector2, team: String, forward: Vector2, margin: float = 30.0) -> Vector2:
	"""将目标位置限制在半场内，如果目标越界则转为横向移动（不压回原地）"""
	var midline_x: float = -10.0 if team == "a" else 10.0
	var clamped: Vector2 = _clamp_to_half_field(pos, team)

	# 如果clamp后x坐标被截断（说明向前移动越过了中线）
	if abs(clamped.x - pos.x) > 5.0:
		# 不压回边界，改为横向拉开
		var lateral: Vector2 = Vector2(forward.y, -forward.x)  # 垂直于forward
		var side: float = 1.0 if (randi() % 2 == 0) else -1.0
		clamped = Vector2(
			midline_x - sign(forward.x) * margin,  # 离中线margin px纵深
			pos.y + lateral.y * side * 60.0
		)
		clamped = _clamp_to_half_field(clamped, team)

	return clamped


func _force_redecide_if_at_boundary(ap: Dictionary) -> void:
	"""到达目标位置后，如果贴中线则强制立即重新决策"""
	var p: CharacterBody2D = ap.player
	var midline_x: float = -10.0 if ap.team == "a" else 10.0
	if abs(p.global_position.x - midline_x) < 30.0:
		# 贴中线，下帧立即重新决策
		ap.think_timer = ap.profile.think_interval


func _clamp_to_outer_field(pos: Vector2, team: String) -> Vector2:
	"""将目标位置限制在凹字形外场内，避免落入臂间缺口(内场)"""
	var result := _clamp_to_outer_field_impl(pos, team)
	return result


func _clamp_to_outer_field_impl(pos: Vector2, team: String) -> Vector2:
	if team == "a":
		var cx: float = clampf(pos.x, RIGHT_OUTER_X_MIN, RIGHT_OUTER_X_MAX)
		var cy: float = clampf(pos.y, RIGHT_OUTER_Y_MIN, RIGHT_OUTER_Y_MAX)
		# 检查是否落入缺口(臂x区间 × 内场y区间)
		if cx >= RIGHT_ARM_X_MIN and cx <= RIGHT_ARM_X_MAX and cy > GAP_Y_MIN and cy < GAP_Y_MAX:
			# 推到缺口最近的边界：主体侧(x=380+) 或 臂y边界
			var dist_to_body: float = RIGHT_ARM_X_MAX - cx  # 到主体的距离
			var dist_to_top: float = cy - GAP_Y_MIN  # 到上臂的距离
			var dist_to_bot: float = GAP_Y_MAX - cy  # 到下臂的距离
			if dist_to_body <= dist_to_top and dist_to_body <= dist_to_bot:
				cx = RIGHT_ARM_X_MAX + 1.0  # 推入主体
			elif dist_to_top <= dist_to_bot:
				cy = GAP_Y_MIN  # 推入上臂
			else:
				cy = GAP_Y_MAX  # 推入下臂
		return Vector2(cx, cy)
	else:
		var cx: float = clampf(pos.x, LEFT_OUTER_X_MIN, LEFT_OUTER_X_MAX)
		var cy: float = clampf(pos.y, LEFT_OUTER_Y_MIN, LEFT_OUTER_Y_MAX)
		# 检查是否落入缺口
		if cx >= LEFT_ARM_X_MIN and cx <= LEFT_ARM_X_MAX and cy > GAP_Y_MIN and cy < GAP_Y_MAX:
			var dist_to_body: float = cx - LEFT_ARM_X_MIN  # 到主体的距离
			var dist_to_top: float = cy - GAP_Y_MIN
			var dist_to_bot: float = GAP_Y_MAX - cy
			if dist_to_body <= dist_to_top and dist_to_body <= dist_to_bot:
				cx = LEFT_ARM_X_MIN - 1.0  # 推入主体
			elif dist_to_top <= dist_to_bot:
				cy = GAP_Y_MIN  # 推入上臂
			else:
				cy = GAP_Y_MAX  # 推入下臂
		return Vector2(cx, cy)


func _clamp_player_position(p: CharacterBody2D) -> void:
	var pos: Vector2 = p.global_position
	var clamped: Vector2

	var penalized_val = p.get("is_penalized")
	var is_penalized: bool = penalized_val != null and penalized_val

	if is_penalized:
		# 使用凹字形感知的外场钳制
		clamped = _clamp_to_outer_field(pos, p.team)
	else:
		clamped = Vector2(
			clampf(pos.x, FIELD_X_MIN, FIELD_X_MAX),
			clampf(pos.y, FIELD_Y_MIN, FIELD_Y_MAX)
		)
		if p.team == "a" and pos.x > 0:
			clamped.x = 0.0
		elif p.team == "b" and pos.x < 0:
			clamped.x = 0.0

	if pos != clamped:
		p.global_position = clamped
		p.velocity = Vector2.ZERO


func _pname(p: CharacterBody2D) -> String:
	if p.char_data and p.char_data.has("name"):
		return str(p.char_data.name)
	return "Player"


# ==============================
# ===== 公开接口 ================
# ==============================

func update_player_profile(player_index: int, profile: AIProfile) -> void:
	"""更新指定球员的AI配置（含速度重算）"""
	for ap in ai_players:
		if ap.team == "a" and ap.index == player_index:
			var base_speed: float = ap.player.speed
			profile.speed_chase = base_speed * profile.speed_chase_mult
			profile.speed_dribble = base_speed * profile.speed_dribble_mult
			profile.speed_move = base_speed * profile.speed_move_mult
			ap.profile = profile
			print("[AI] 队A位置%d profile已更新 角色=%s 策略=%s chase=%.0f" % [player_index, profile.role, profile.team_strategy_name, profile.speed_chase])
			return


func get_player_profile(player_index: int) -> AIProfile:
	"""获取指定球员的AI配置"""
	for ap in ai_players:
		if ap.team == "a" and ap.index == player_index:
			return ap.profile
	return null
