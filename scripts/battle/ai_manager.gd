extends Node
## AI管理器 - 数据驱动的AI行为引擎
## 所有行为参数从 AIProfile 读取,不硬编码
## 包含:180度朝向视野感知系统、评分决策、阵型跑位

const AIProfile = preload("res://scripts/battle/ai_profile.gd")

var battle_manager: Node2D
var input_manager: Node
var ball_node: Area2D
var match_stats: Node = null  # P1方案A：指标采集器引用（可选，sim模式用）

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
			var _prev_state: int = ap.state  # P1方案A：采集决策驱动的状态切换（抖动指标）
			_decide(ap)
			if match_stats and ap.state != _prev_state:
				match_stats.record_state_change(ap.team)

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
		"last_state": State.IDLE,  # P0：Hysteresis 防抖用，记录上次状态
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
		# 2026-06-17：球在对方半场时不主动追（避免被中线 clamp 卡死）
		# 对方半场的飞球由 _should_enter_catch_state 接球状态处理，或球进己方半场后再追
		var ball_reachable: bool = _ball_in_reachable_half(ball_pos, team)
		if ball_reachable and _am_i_closest_to_ball(ap, team) and dist_to_ball < aggro:
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


# ============================================================================
# 【P2 影响力地图（简化版）2026-06-17】
# 借鉴 tactical-intuition（Unity）影响力地图思路：无球站位时避开敌人密集区
# 决竞球适配：不建全场网格（小场不需要），用反平方排斥叠加到阵型基准位
# 参考 _calc_separation 的反平方公式，但针对敌人（站位移开而非物理避让）
# ============================================================================

## 无球站位时，在基准位置上叠加「远离附近敌人」的偏移
## base_pos: 阵型基准位 / avoid_radius: 多远内的敌人要躲 / push: 最大偏移距离
## 注意：排斥力要保守，过强会把球员推到墙角卡住或反复抖动（2026-06-17 调试）
func _avoid_enemies(ap: Dictionary, base_pos: Vector2, avoid_radius: float = 80.0, push: float = 30.0) -> Vector2:
	var p: CharacterBody2D = ap.player
	var offset := Vector2.ZERO
	var radius_sq: float = avoid_radius * avoid_radius
	for other in ai_players:
		if other.team == ap.team or other.player == p or not _is_valid(other):
			continue  # 只躲敌人
		if other.player.is_defeated:
			continue
		var to_base: Vector2 = base_pos - other.player.global_position
		var d_sq: float = to_base.length_squared()
		if d_sq >= radius_sq or d_sq < 1.0:
			continue
		# 反平方衰减：敌人越近，基准位被推开越远（系数保守）
		var strength: float = 300.0 / d_sq
		offset += to_base.normalized() * strength
	return base_pos + offset.limit_length(push)


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

	# === P0 Hysteresis 防抖：当前状态对应的行为需达到 margin 才被顶替 ===
	# 决竞球场景：pass/shoot 分数接近时反复切换会造成出手节奏乱，按角色给容差
	var hysteresis: float = profile.decision_hysteresis
	if ap.state == State.ATTACK:
		shoot_score += hysteresis  # 当前投球，射击需高出 margin 才会被抢走优先
	elif ap.state == State.PASS:
		pass_score += hysteresis
	elif ap.state == State.DRIBBLE:
		dribble_score += hysteresis

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


# ============================================================================
# 【外场AI重写 2026-06-15】效用驱动版
# 背景：原逻辑"内场思维残留"（靠距离抢球、追球到隔离墙卡线、跑位基准固定）
# 设计原则（主人定）：
#   1. 团队策略权重>个人策略，但极端情况允许个人反超（无固定上下限）
#   2. 接不接球=全局评估（体力撑比赛+球权价值+球威胁），不是看距离
#   3. 外场互转概率顺应场上变化（非固定减分），极端情况反而+概率
#   4. 主动技能就绪度影响决策（自己+队友的 active 技能）
# 数据依赖：ball.active_skill_data/ball_damage、player.stamina/skill_cooldowns
# 日后优化点：
#   - 局势因子可加入"分差"（落后方进攻权重提升）
#   - 效用公式系数可按难度 profile 化（当前写在函数内）
# ============================================================================

## 外场AI主决策（替代内场思维，基于态势效用计算）
func _decide_penalty_move(ap: Dictionary) -> void:
	var p: CharacterBody2D = ap.player
	var team: String = ap.team
	var profile: AIProfile = ap.profile
	var my_pos: Vector2 = p.global_position

	# 每决策周期计算一次态势因子（省性能，够用）
	var situation: Dictionary = _evaluate_situation(ap)

	# === ① 持球：效用计算选 PASS 还是 ATTACK ===
	if p.is_carrying_ball:
		ap.total_carry_time += profile.think_interval
		# 观察期未满：在外场内游走寻找机会
		ap.hold_timer += profile.think_interval
		if ap.hold_timer < ap.hold_duration and ap.total_carry_time < profile.max_carry_time:
			var random_dir: Vector2 = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
			ap.state = State.PENALTY_MOVE
			ap.target_pos = _clamp_to_outer_field(my_pos + random_dir * 50.0, team)
			return

		# 效用计算：pass_utility vs shoot_utility
		var carry_util: Dictionary = _utility_carrying(ap, situation)
		if carry_util.pass_score >= carry_util.shoot_score:
			# PASS：传内场队友（外场互转概率低，_eval_best_pass 内部已修正）
			var pass_result: Dictionary = _eval_best_pass(ap)
			var pass_target: CharacterBody2D = pass_result.get("target") as CharacterBody2D if pass_result.has("target") else null
			if pass_target:
				ap.state = State.PASS
				ap.target_pos = pass_target.global_position
			else:
				# 无可传目标：退化为 ATTACK 朝内场对方
				ap.state = State.ATTACK
				ap.target_pos = _nearest_inner_enemy_pos(ap)
		else:
			# ATTACK：投内场对方（球员自己留外场，目标点=敌人位置）
			ap.state = State.ATTACK
			ap.target_pos = _nearest_inner_enemy_pos(ap)
		return

	# === 无球 ===
	var ball_pos: Vector2 = ball_node.global_position
	var ball_active: bool = ball_node.is_active

	# === ①.5 队友传球优先识别（2026-06-17：修复外场接不到队友传球）===
	# 决竞球场景：内场队友主动传球给外场队友是合法战术（守转攻/二次进攻）
	# 原bug：传球方向偏垂直时 ball_dir.x<0.3 不触发"飞向外场"判定，
	#        或 catch_util≤0 误判危险球拒接→飞到脸上也躲开
	# 修复：只要 attacker_player 是同队队友 + 球朝我附近飞→直接 READY_CATCH
	#       （物理层 _on_body_entered 同队碰球即接住，只需 AI 摆出接球姿态）
	if ball_active and ball_node.attacker_player:
		var passer: CharacterBody2D = ball_node.attacker_player
		if passer.team == team and passer != p:
			# 球朝我方向飞（球→我 的向量与球飞行方向同向）或球已在我附近
			var to_me: Vector2 = p.global_position - ball_pos
			var ball_dir_vec: Vector2 = ball_node.ball_direction
			var approaching: bool = false
			if ball_dir_vec != Vector2.ZERO and to_me != Vector2.ZERO:
				approaching = ball_dir_vec.dot(to_me.normalized()) > 0.3
			var ball_near_me: bool = to_me.length() < 200.0
			if approaching or ball_near_me:
				ap.state = State.READY_CATCH
				ap.target_pos = p.global_position  # 原地接球，不预测落点（防跑过头）
				if p.has_method("enter_catch_state"):
					p.enter_catch_state()
				return

	# === ② 球激活飞向外场→先评估球威胁，再判定接不接 ===
	if ball_active:
		var threat: float = _eval_ball_threat(ap)
		var catch_util: float = _utility_catch(ap, situation, threat, ball_pos)
		# 球的方向是否指向我方外场（预判会进来）
		var ball_to_outer: bool = _is_ball_heading_to_outer(team)
		if ball_to_outer and catch_util > 0.0:
			# 安全球 + 飞向外场→预判落点待接
			var intercept_pos: Vector2 = _predict_outer_intercept_pos(ap)
			ap.state = State.READY_CATCH
			ap.target_pos = intercept_pos
			if p.has_method("enter_catch_state"):
				p.enter_catch_state()
			return
		elif ball_to_outer and catch_util <= 0.0:
			# 危险球→拒绝接，转跑位让位（不浪费体力/不被击倒）
			_move_to_outer_hold(ap, situation)
			return
		# 球不飞向外场→继续往下走

	# === ③ 球在外场（落地/持球者在外场）→评估接不接 ===
	var ball_in_outer: bool = _is_pos_in_outer(ball_pos, team)
	if ball_in_outer and not ball_node.owner_player:
		var threat2: float = _eval_ball_threat(ap)
		var catch_util2: float = _utility_catch(ap, situation, threat2, ball_pos)
		if catch_util2 > 0.0 and _am_i_closest_in_outer(ap, ball_pos):
			# 安全球 + 我是外场最近者→追球（仅在外场内）
			ap.state = State.PENALTY_MOVE
			ap.target_pos = _clamp_to_outer_field(ball_pos, team)
		else:
			_move_to_outer_hold(ap, situation)
		return

	# === ④ 无球跑位（球不在外场）→按球权+团队策略 ===
	_move_to_outer_hold(ap, situation)


## 外场无球跑位（按球权归属 + 团队策略动态站边，不再用固定 outer_base）
func _move_to_outer_hold(ap: Dictionary, situation: Dictionary) -> void:
	var team: String = ap.team
	var profile: AIProfile = ap.profile
	var ball_owner_team: String = _get_ball_owner_team()
	var base_x_inner: float = 400.0   # 靠近内场边（接应用）
	var base_x_deep: float = 460.0    # 退守外场深处
	var base_x_mid: float = 430.0     # 待机位
	if team == "b":
		base_x_inner = -400.0
		base_x_deep = -460.0
		base_x_mid = -430.0

	# 主球权状态决定站位区域
	var hold_x: float = base_x_mid
	if ball_owner_team == team:
		# 我方持球→靠近内场边接应（准备接回传）
		hold_x = base_x_inner
	elif ball_owner_team != "" and ball_owner_team != team:
		# 对方持球→按团队策略：defensive 退守，其他观察
		if profile.team_strategy_name == "defensive":
			hold_x = base_x_deep
		else:
			hold_x = base_x_mid

	# y 偏移按角色（防御/辅助保持宽度，主攻中）
	var hold_y: float = 0.0
	match profile.role:
		"defender":
			hold_y = 0.0
		"supporter":
			hold_y = 100.0 if (ap.index % 2 == 0) else -100.0
		_:
			hold_y = 0.0

	var smart_pos: Vector2 = Vector2(hold_x, hold_y)
	var random_offset: Vector2 = Vector2(randf_range(-30.0, 30.0), randf_range(-40.0, 40.0))

	# 避让玩家控制球员（外场空间小不挡路）
	var p: CharacterBody2D = ap.player
	if input_manager and input_manager.controlled_player:
		var ctrl_p: CharacterBody2D = input_manager.controlled_player
		if ctrl_p.team == team and ctrl_p != p:
			var to_ctrl: Vector2 = ctrl_p.global_position - smart_pos
			if to_ctrl.length() < 80.0 and to_ctrl.length() > 0.0:
				smart_pos -= to_ctrl.normalized() * (80.0 - to_ctrl.length()) * 0.8

	ap.state = State.PENALTY_MOVE
	ap.target_pos = _clamp_to_outer_field(smart_pos + random_offset, team)


# ============================================================================
# 【态势感知系统】返回全局动态因子字典（内外场可共用）
# ============================================================================

func _evaluate_situation(ap: Dictionary) -> Dictionary:
	var p: CharacterBody2D = ap.player
	var team: String = ap.team
	var s: Dictionary = {}

	# 因子1：比赛进度 0~1（上半场0~0.5，下半场0.5~1）
	var total_time: float = 600.0  # FIRST_HALF+SECOND_HALF（P1方案A：读真实时长避免 sim 缩短后失真）
	if GameManager:
		total_time = GameManager.get_first_half_duration() + GameManager.get_second_half_duration()
	var elapsed: float = 0.0
	if GameManager:
		elapsed = (GameManager.FIRST_HALF_DURATION + GameManager.SECOND_HALF_DURATION) - maxf(GameManager.match_time, 0.0)
		if GameManager.match_phase == GameManager.MatchPhase.FIRST_HALF:
			elapsed = GameManager.FIRST_HALF_DURATION - maxf(GameManager.match_time, 0.0)
	s["match_progress"] = clampf(elapsed / total_time, 0.0, 1.0)

	# 因子2：自身体力健康度（按比赛进度预留）
	var my_stam_ratio: float = p.stamina / p.max_stamina if p.max_stamina > 0.0 else 0.0
	var reserve: float = (1.0 - s.match_progress) * 0.3  # 后半段预留30%
	s["my_stamina_health"] = clampf(my_stam_ratio - reserve, -0.5, 1.0)

	# 因子3：球权价值 0~1
	s["possession_value"] = _eval_possession_value(ap)

	# 因子4：队友状态（仅算内场存活）
	s["team_state"] = _eval_team_state(team)

	# 因子5：对手状态
	s["enemy_state"] = _eval_team_state("b" if team == "a" else "a")

	# 因子6：主动技能就绪度（自己+内场队友的 active 技能）
	s["active_skill_ready"] = _eval_active_skill_ready(ap)

	return s


## 球权价值：己方控球多→接球意愿低，对方控球→急需夺回
func _eval_possession_value(ap: Dictionary) -> float:
	var team: String = ap.team
	if not ball_node:
		return 0.5
	# 球有人持
	if ball_node.owner_player:
		if ball_node.owner_player.team != team:
			return 0.9  # 对方持球→急需夺回
		else:
			return 0.3  # 己方持球→不缺球权
	# 球飞行中：按攻击者归属
	if ball_node.attacker_player:
		if ball_node.attacker_player.team != team:
			return 0.8
		else:
			return 0.5
	# 球完全无人持→看半场人数优势
	var my_count: int = _count_alive_in_inner(team)
	var enemy_count: int = _count_alive_in_inner("b" if team == "a" else "a")
	if my_count > enemy_count:
		return 0.9
	elif my_count < enemy_count:
		return 0.5
	return 0.7


## 队伍状态：内场存活球员平均体力比 × (1 - 被击败人数*0.2)
func _eval_team_state(team: String) -> float:
	var players: Array = ai_players
	var total_stam: float = 0.0
	var alive_inner: int = 0
	var defeated: int = 0
	for ap in players:
		if ap.team != team:
			continue
		if not _is_valid(ap):
			continue
		if ap.player.is_defeated or ap.player.is_penalized:
			defeated += 1
			continue
		total_stam += ap.player.stamina / ap.player.max_stamina if ap.player.max_stamina > 0.0 else 0.0
		alive_inner += 1
	if alive_inner == 0:
		return 0.1
	var avg: float = total_stam / float(alive_inner)
	return clampf(avg * (1.0 - defeated * 0.2), 0.0, 1.0)


## 主动技能就绪度：自己+内场队友的 active 技能冷却全0的比例
func _eval_active_skill_ready(ap: Dictionary) -> float:
	var team: String = ap.team
	var total_active: int = 0
	var ready_active: int = 0
	for entry in ai_players:
		if entry.team != team:
			continue
		if not _is_valid(entry):
			continue
		if entry.player.is_defeated or entry.player.is_penalized:
			continue
		for sid in entry.player.equipped_skills:
			var sk: Dictionary = DataManager.get_skill_by_id(str(sid))
			if str(sk.get("type", "active")) != "active":
				continue
			total_active += 1
			var cd: float = entry.player.skill_cooldowns.get(str(sid), 0.0)
			if cd <= 0.0:
				ready_active += 1
	if total_active == 0:
		return 0.5
	return float(ready_active) / float(total_active)


# ============================================================================
# 【效用计算函数】
# ============================================================================

## Response Curve：把 0~1 的因子过曲线，让决策更拟人（P1，参考 Dave Mark Utility AI）
## 决竞球场景：线性加权会让对手残血 50%→60% 和 90%→100% 反应一样，不像真人
## 过曲线后，特定阈值才有明显变化（如对手残血到 70% 才开始猛攻）
## linear=线性 / logistic=S形（中段急升，适合有阈值的因子）/
## exp=凸（越高越极端，无饱和，适合“越好越极端”）/ inv_log=反S（高忽略低急升）
func _curve(x: float, type: String, k: float = 1.0) -> float:
	x = clampf(x, 0.0, 1.0)
	match type:
		"logistic":
			# S形：x=0.5时y=0.5，k越大越陡；低值压低、高值拉高、中段急转
			return 1.0 / (1.0 + exp(-k * (x - 0.5) * 8.0))
		"exp":
			# 凸：y=x²，高值变化快、低值平缓（无上端饱和）
			return x * x
		"inv_log":
			# 反S：高值压低、低值拉高（用于“领先松懈”等反向场景）
			return 1.0 - 1.0 / (1.0 + exp(-k * (x - 0.5) * 8.0))
		_:  # linear 默认
			return x


## 持球效用：返回 {pass_score, shoot_score}，极端情况允许个人反超团队
## P1：situation 因子过 Response Curve + 系数从 profile 读（原魔法数字 50/60/30/40/20）
func _utility_carrying(ap: Dictionary, situation: Dictionary) -> Dictionary:
	var profile: AIProfile = ap.profile
	var boost: float = profile.outer_personal_boost  # 外场增益
	var k: float = profile.curve_k

	# 因子过曲线（enemy_state 用 logistic：对手残血到阈值才影响决策）
	var team_factor: float = situation.get("team_state", 0.5)  # 队友状态保持线性
	var enemy_factor: float = _curve(situation.get("enemy_state", 0.5), profile.curve_enemy_state, k)
	var skill_factor: float = situation.get("active_skill_ready", 0.5)  # 技能就绪保持线性

	var pass_score: float = float(profile.weight_pass)
	pass_score += team_factor * profile.util_pass_team_w      # 队友强→多传
	pass_score += enemy_factor * profile.util_pass_enemy_w    # 对手弱→少传直接打
	pass_score += skill_factor * profile.util_pass_skill_w    # 技能好→配合

	var shoot_score: float = float(profile.weight_shoot)
	shoot_score += enemy_factor * profile.util_shoot_enemy_w  # 对手弱→猛打
	shoot_score += team_factor * profile.util_shoot_team_w    # 队友强→传给他们

	# 个人策略加权（外场增益放大，允许反超）
	match profile.player_strategy_name:
		"breakthrough":
			shoot_score += 30.0 * boost
		"passing":
			pass_score += 30.0 * boost
		"defense":
			pass_score += 20.0 * boost  # 防守反击偏稳传

	return {"pass_score": pass_score, "shoot_score": shoot_score}


## 接球效用：< 0 拒绝接球（体力撑不住/球威胁大/球权本在己方）
## P1：因子过曲线 + 系数从 profile 读
func _utility_catch(ap: Dictionary, situation: Dictionary, ball_threat: float, _ball_pos: Vector2) -> float:
	var profile: AIProfile = ap.profile
	var k: float = profile.curve_k
	var util: float = 0.0

	# 因子过曲线
	var possession_factor: float = situation.get("possession_value", 0.5)  # 球权价值保持线性
	var stamina_factor: float = _curve(situation.get("my_stamina_health", 0.5), profile.curve_stamina, k)
	var threat_factor: float = _curve(ball_threat, profile.curve_threat, k)

	util += possession_factor * profile.util_catch_possession_w  # 球权价值（急需夺回→积极接）
	util += stamina_factor * profile.util_catch_stamina_w        # 体力撑得住
	util += threat_factor * profile.util_catch_threat_w          # 球威胁（技能/伤害，负值）
	# 角色加分：防御/辅助主动接，主攻看个人策略
	match profile.role:
		"defender", "supporter":
			util += 30.0
		"attacker":
			if profile.player_strategy_name == "breakthrough":
				util += 10.0
	return util


## 球的威胁评估：伤害占体力比 + 主动技能加成 + 投球者归属
func _eval_ball_threat(ap: Dictionary) -> float:
	if not ball_node:
		return 0.2
	var p: CharacterBody2D = ap.player
	var dmg_ratio: float = 0.0
	if p.max_stamina > 0.0:
		dmg_ratio = ball_node.ball_damage / p.max_stamina
	var threat: float = clampf(dmg_ratio, 0.0, 1.0)
	# 球带主动技能→更危险
	if ball_node.active_skill_data.size() > 0:
		threat += 0.3
	# 投球者是对方→更危险
	if ball_node.attacker_player and ball_node.attacker_player.team != ap.team:
		threat += 0.2
	return clampf(threat, 0.0, 1.0)


# ============================================================================
# 【外场辅助判定函数】
# ============================================================================

## 球的方向是否指向我方外场（不再用距离判据）
func _is_ball_heading_to_outer(team: String) -> bool:
	if not ball_node or not ball_node.is_active:
		return false
	var ball_dir: Vector2 = ball_node.ball_direction
	if ball_dir == Vector2.ZERO:
		return false
	# 队A外场在右(x>0)，球向右飞→指向队A外场；队B同理
	if team == "a":
		return ball_dir.x > 0.3
	else:
		return ball_dir.x < -0.3


## 预判球进入外场的接球点（沿球方向投到外场边界内侧）
func _predict_outer_intercept_pos(ap: Dictionary) -> Vector2:
	var team: String = ap.team
	var my_pos: Vector2 = ap.player.global_position
	if not ball_node or not ball_node.is_active:
		return my_pos
	var ball_pos: Vector2 = ball_node.global_position
	var ball_dir: Vector2 = ball_node.ball_direction
	if ball_dir == Vector2.ZERO:
		return my_pos
	# 沿球方向推进，找第一个落在外场内的点
	for i in range(20):
		var pred: Vector2 = ball_pos + ball_dir * (i * 30.0)
		if _is_pos_in_outer(pred, team):
			return _clamp_to_outer_field(pred, team)
		if abs(pred.x) > 600.0 or abs(pred.y) > 400.0:
			break
	return my_pos


## 坐标是否在我方外场矩形内
func _is_pos_in_outer(pos: Vector2, team: String) -> bool:
	if team == "a":
		return pos.x >= RIGHT_OUTER_X_MIN and pos.x <= RIGHT_OUTER_X_MAX and pos.y >= RIGHT_OUTER_Y_MIN and pos.y <= RIGHT_OUTER_Y_MAX
	else:
		return pos.x >= LEFT_OUTER_X_MIN and pos.x <= LEFT_OUTER_X_MAX and pos.y >= LEFT_OUTER_Y_MIN and pos.y <= LEFT_OUTER_Y_MAX


## 我是外场内距球最近者（只在同队外场球员中比）
func _am_i_closest_in_outer(ap: Dictionary, ball_pos: Vector2) -> bool:
	var my_dist: float = ap.player.global_position.distance_to(ball_pos)
	for other in ai_players:
		if other.team != ap.team or other.player == ap.player:
			continue
		if not _is_valid(other):
			continue
		if not other.player.is_penalized:
			continue  # 只和同样在外场的队友比
		if other.player.global_position.distance_to(ball_pos) < my_dist:
			return false
	return true


## 球权归属队伍（""=无人持）
func _get_ball_owner_team() -> String:
	if not ball_node:
		return ""
	if ball_node.owner_player:
		return ball_node.owner_player.team
	if ball_node.attacker_player:
		return ball_node.attacker_player.team
	return ""


## 内场存活球员数（外场/被击败不算）
func _count_alive_in_inner(team: String) -> int:
	var n: int = 0
	for ap in ai_players:
		if ap.team != team:
			continue
		if not _is_valid(ap):
			continue
		if not ap.player.is_defeated and not ap.player.is_penalized:
			n += 1
	return n


## 内场最近敌方位置（外场投球目标，找不到则朝内场中心）
func _nearest_inner_enemy_pos(ap: Dictionary) -> Vector2:
	var nearest: CharacterBody2D = _find_nearest_enemy(ap)
	if nearest and is_instance_valid(nearest):
		return nearest.global_position
	# 无目标→朝内场中心（确保球回内场，不是撞外场墙）
	return Vector2(-190.0, 0.0) if ap.team == "a" else Vector2(190.0, 0.0)


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

		# 7) 【外场互转 2026-06-15】目标也在外场→动态减分（顺应场上变化）
		# 默认低概率：-60；但内场全被击败/内场全超出传球范围时回补（必须外场互转）
		if tm.is_penalized:
			var inner_alive: int = _count_alive_in_inner(team)
			var inner_reachable: bool = false
			for other_info in known_teammates:
				var other_tm: CharacterBody2D = other_info["ref"]
				if other_tm == tm or other_tm.is_penalized:
					continue
				if p.global_position.distance_to(other_info["pos"]) <= profile.pass_range:
					inner_reachable = true
					break
			if inner_alive == 0:
				score += 100.0   # 内场全灭→必须外场互转
			elif not inner_reachable:
				score += 50.0    # 内场传不到→退而求其次
			else:
				score -= 60.0    # 默认低概率（有内场选项时优先内场）

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


# ============================================================================
# 【P0 Steering 避障工具函数 2026-06-17】
# 借鉴 GDQuest godot-steering-ai-framework（GSAISeparation/GSAIAvoidCollisions），
# 结合决竞球规则改造：
#   - 内/外场分离力不同（外场狭小，需更强排斥防卡死）
#   - 仅对队友施分离力（敌人是攻击目标，不能排斥开）
#   - 带球状态额外做碰撞预测绕行（避开截球敌人）
# ============================================================================

## 计算分离力（排斥向量）：内场弱、外场强，仅施于队友
## 参考 GSAISeparation._report_neighbor：strength = decay_coeff / distance²（反平方）
func _calc_separation(ap: Dictionary) -> Vector2:
	var p: CharacterBody2D = ap.player
	var profile: AIProfile = ap.profile
	var penalized: bool = _is_penalized(ap)
	# 内场弱、外场强（外场狭小需强力排斥）
	var coeff: float = profile.separation_outer if penalized else profile.separation_inner
	var radius: float = profile.separation_radius
	var radius_sq: float = radius * radius
	var sep := Vector2.ZERO
	for other in ai_players:
		if other.player == p or not _is_valid(other):
			continue
		# 仅对同队队友施分离力（敌人是攻击目标，不能排斥）
		if other.team != ap.team:
			continue
		var to_me: Vector2 = p.global_position - other.player.global_position
		var d_sq: float = to_me.length_squared()
		if d_sq >= radius_sq or d_sq < 1.0:
			continue  # 超出感知半径 / 重叠异常跳过
		# 反平方衰减：越近排斥越强
		var strength: float = coeff / d_sq
		sep += to_me.normalized() * strength
	# 封顶：避免极端情况加速度炸裂
	return sep.limit_length(profile.speed_move * 1.5)


## 带球碰撞预测绕行：预测前方 avoid_lookahead 秒会撞到的敌人，提前偏转
## 参考 GSAIAvoidCollisions：计算 time_to_collision，加侧向避让力
func _calc_avoid_velocity(ap: Dictionary, base_vel: Vector2) -> Vector2:
	var p: CharacterBody2D = ap.player
	var profile: AIProfile = ap.profile
	var lookahead: float = profile.avoid_lookahead
	var my_speed: float = base_vel.length()
	if my_speed < 1.0:
		return base_vel
	# 预测前方位置
	var future_pos: Vector2 = p.global_position + base_vel * lookahead
	var avoid := Vector2.ZERO
	for other in ai_players:
		if other.player == p or not _is_valid(other):
			continue
		var enemy: CharacterBody2D = other.player
		# 敌人提前预测（包括对手）
		var enemy_future: Vector2 = enemy.global_position
		if other.team != ap.team and enemy.velocity:
			enemy_future = enemy.global_position + enemy.velocity * lookahead
		var to_enemy: Vector2 = enemy_future - future_pos
		var d_sq: float = to_enemy.length_squared()
		# 预测点距敌人 < 50 像素 → 需避让
		if d_sq < 50.0 * 50.0 and d_sq > 1.0:
			# 侧向避让：取 base_vel 的垂直方向（哪侧更远走哪侧）
			var perp: Vector2 = Vector2(-base_vel.y, base_vel.x).normalized()
			var side_dot: float = perp.dot(to_enemy)
			if side_dot > 0.0:
				perp = -perp  # 选远离敌人的一侧
			avoid += perp * my_speed * 0.6
	return (base_vel + avoid).limit_length(my_speed)


## 应用分离力到速度（通用：所有 _move 移动分支可调用）
## 仅在非击退/非僵直/非接球状态下叠加
func _apply_steering(ap: Dictionary, base_velocity: Vector2, use_avoid: bool = false) -> Vector2:
	# 应用速度buff（buff系统对AI也生效：最终速度 = 基础 × buff倍率 + buff固定值）
	var p: CharacterBody2D = ap.player
	var base_speed: float = base_velocity.length()
	var buffed_speed: float = p._get_effective_value("speed", base_speed)
	var buffed_velocity: Vector2 = base_velocity
	if base_speed > 1.0:
		buffed_velocity = base_velocity.normalized() * buffed_speed
	
	var sep := _calc_separation(ap)
	var vel := buffed_velocity + sep
	# 带球时额外做碰撞预测绕行
	if use_avoid and ap.player.is_carrying_ball:
		vel = _calc_avoid_velocity(ap, vel)
	# 保持原速度上限（不超速）
	var max_speed: float = buffed_velocity.length()
	if max_speed > 1.0:
		vel = vel.limit_length(max_speed)
	return vel

# ==============================
# ===== 移动执行 ================
# ==============================

func _move(ap: Dictionary, delta: float) -> void:
	var p: CharacterBody2D = ap.player

	# 击退中：不覆盖velocity，只执行move_and_slide
	if p._knockback_timer > 0.0:
		p.move_and_slide()
		return

	# 记录 last_state 供 Hysteresis 防抖用（P0）
	var _prev_state: int = ap.state

	# 僵直中：无法移动
	if p._stagger_timer > 0.0:
		p.velocity = Vector2.ZERO
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
				# 2026-06-20：追到目标但球被敌人拿着（clamp后够不到对方半场的敌人）
				# → 立即放弃追球转防守回阵型位，不再磁铁吸中线
				# 修复菲菲压发球线：追→pickup失败空转→重决策又追→死循环
				if ball_node.owner_player and ball_node.owner_player != p:
					ap.state = State.DEFEND
					ap.target_pos = _get_formation_hold_pos(ap)
				p.velocity = Vector2.ZERO
			else:
				p.velocity = _apply_steering(ap, (target - p.global_position).normalized() * profile.speed_chase)
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
				if match_stats:
					match_stats.record_stuck(ap.team)  # P1方案A：卡死指标采集
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
						# P0 Hysteresis：新目标距当前位置太近→跳过，避免抽搂（用 profile 字段）
						if new_target.distance_to(current_pos) < profile.stuck_redecide_margin:
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
				# P0：带球时启用碰撞预测绕行 + 队友分离力，避免被堵卡死
				p.velocity = _apply_steering(ap, (target - p.global_position).normalized() * profile.speed_dribble, true)
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
				p.velocity = _apply_steering(ap, (target - p.global_position).normalized() * profile.speed_move)
				p.move_and_slide()

		State.SUPPORT:
			if dist < arrive:
				p.velocity = Vector2.ZERO
				_force_redecide_if_at_boundary(ap)
			else:
				p.velocity = _apply_steering(ap, (target - p.global_position).normalized() * profile.speed_move)
				p.move_and_slide()

		State.PENALTY_MOVE:
			# 【卡死检测 2026-06-15】外场空间小易被隔离墙/队友挡，卡住则换镜像位
			var pm_current_pos: Vector2 = p.global_position
			var pm_moved: float = pm_current_pos.distance_to(ap.get("last_pos", Vector2.ZERO))
			ap.last_pos = pm_current_pos
			if pm_moved < 2.0 and dist > arrive:
				ap.stuck_timer = ap.get("stuck_timer", 0.0) + delta
			else:
				ap.stuck_timer = 0.0
			if ap.get("stuck_timer", 0.0) > 1.0:
				if match_stats:
					match_stats.record_stuck(ap.team)  # P1方案A：卡死指标采集
				# 外场卡住→切换到 y 镜像待机位（避开当前阻挡物）
				var hold_x: float = 430.0 if ap.team == "a" else -430.0
				var mirror_y: float = -pm_current_pos.y
				var candidate: Vector2 = _clamp_to_outer_field(Vector2(hold_x, mirror_y + randf_range(-60.0, 60.0)), ap.team)
				# P0 Hysteresis：新位置距当前位置必须 > margin，否则保持原状（避免镜像抽搂）
				if candidate.distance_to(pm_current_pos) > profile.stuck_redecide_margin:
					ap.target_pos = candidate
					print("[AI] %s 外场卡住,切镜像位" % _pname(p))
				ap.stuck_timer = 0.0
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
				p.velocity = _apply_steering(ap, move_dir * profile.speed_move)
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
	ball_node.launch(p.global_position, direction, p._get_effective_value("attack", p.attack_power) * 0.5, distance + 80.0, p, [] as Array[Dictionary])

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
	ball_node.launch(p.global_position, shoot_dir, p._get_effective_value("attack", p.attack_power), shoot_dist, p, [] as Array[Dictionary])

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


# ============================================================================
# 【中线抢球分工优化 2026-06-15】
# 背景：球落在中线(x≈0)时，两队最近球员判定都该追→挤到同一点→物理碰撞
#       推搡→抢到球又被碰掉→死循环抽搐。
# 设计原则（6大原则之行为/战术原则）：
#   1. 职责分工：防御手守转攻第一点 > 辅助手 > 主攻手（保留前压威胁）
#   2. 让位原则：球飞向对方或对手更近→放弃前压，保持防守站位
#   3. 球权确定：让位后由调用方_decide自动走_decide_off_ball_role防守站位
# 日后优化点：
#   - 可加入球飞行方向(ball_direction)精确预判"飞向对方"
#   - ENEMY_ADVANTAGE_DIST阈值可按难度/平衡性调整
# ============================================================================

## 内场中线抢球的职责优先级（数值越小越优先抢球）
const ROLE_CHASE_PRIORITY: Dictionary = {
	"defender": 0,   # 防御手最优先（最靠后，守转攻抢第一点）
	"supporter": 1,  # 辅助手次之
	"attacker": 2,   # 主攻手最后（保留前压进攻威胁，不回撤抢球）
}

## 对方距离优势阈值：对方最近者比我近超过此值→球权倾向对方→我放弃
const ENEMY_ADVANTAGE_DIST: float = 60.0


## 预测球的落点（2026-06-19：简单版，只处理直线轨迹）
## 非飞行状态或非直线轨迹 → 返回当前位置
func _predict_ball_landing_simple() -> Vector2:
	if ball_node == null:
		return Vector2.ZERO

	# 非飞行状态，直接返回当前位置
	if not ball_node.is_active:
		return ball_node.global_position

	# 只处理直线轨迹
	if ball_node.trajectory_type != "straight":
		return ball_node.global_position

	# 计算剩余飞行距离
	var remaining_distance = ball_node.max_flight_distance - ball_node.flight_distance

	# 落点 = 当前位置 + 飞行方向 * 剩余距离
	return ball_node.global_position + ball_node.ball_direction * remaining_distance


## 球是否在己方可达的半场范围内（2026-06-17：避免追到对方半场球时被中线 clamp 卡死）
## 2026-06-19：飞行中基于落点判断，落地基于当前位置判断（解决球飞行中跨半场导致的状态横跳）
## 决竞球规则：球员不能过中线，追对方半场的球→目标被clamp到中线→够不到→卡线
## 球在己方半场（含中线）才值得主动追；对方半场的球交给接球状态处理
func _ball_in_reachable_half(ball_pos: Vector2, team: String) -> bool:
	# 飞行中：用落点判断
	if ball_node.is_active:
		var landing_pos = _predict_ball_landing_simple()
		if team == "a":
			return landing_pos.x <= 0.0  # 队A可达中线及左侧己方半场
		else:
			return landing_pos.x >= 0.0  # 队B可达中线及右侧己方半场
	# 落地：用当前位置判断
	else:
		if team == "a":
			return ball_pos.x <= 0.0
		else:
			return ball_pos.x >= 0.0


## 判断我是否应该去抢球（含职责分工 + 让位原则）
func _am_i_closest_to_ball(ap: Dictionary, team: String) -> bool:
	var p: CharacterBody2D = ap.player
	var ball_pos: Vector2 = ball_node.global_position
	var my_dist: float = p.global_position.distance_to(ball_pos)
	var my_priority: int = ROLE_CHASE_PRIORITY.get(ap.profile.role, 1)

	# === 1. 同队职责优先级判定（2026-06-17 加强：按职责分工，不看抢球范围）===
	# 决竞球规则：主攻手(priority=2)不该亲自回撤抢球，球应来自防御手/辅助手传球
	# 只要更高优先级队友(数值更小)有效存活且在内场→我让位
	# 原bug：仅当队友在aggro_range内才让位→发球时队友站位靠后→主攻手自己抢球
	for other in ai_players:
		if other.team != team:
			continue
		if other.player == p:
			continue
		if not _is_valid(other):
			continue
		# 队友被击败/外场惩罚→视为不可用，不据此让位（让主攻手能补位）
		if other.player.is_defeated or other.player.is_penalized:
			continue
		var other_priority: int = ROLE_CHASE_PRIORITY.get(other.profile.role, 1)
		if other_priority < my_priority:
			return false  # 更高优先级队友在场，我让位（职责分工优先，不看距离）

	# === 2. 同职责比距离（原逻辑保留）===
	# 同优先级队友中，我必须是最近的才去抢
	for other in ai_players:
		if other.team != team:
			continue
		if other.player == p:
			continue
		if not _is_valid(other):
			continue
		var other_priority: int = ROLE_CHASE_PRIORITY.get(other.profile.role, 1)
		if other_priority == my_priority:
			if other.player.global_position.distance_to(ball_pos) < my_dist:
				return false  # 同级队友更近，我让位

	# === 3. 对方优势判定（球权倾向对方→放弃前压，转防守站位）===
	# 找对方最近者。若对方明显比我近(优势>阈值)→球权将稳定在对方
	# →我前压无意义且会造成挤兑，返回false走_decide_off_ball_role防守
	var best_enemy_dist: float = INF
	for other in ai_players:
		if other.team == team:
			continue
		if not _is_valid(other):
			continue
		var ed: float = other.player.global_position.distance_to(ball_pos)
		if ed < best_enemy_dist:
			best_enemy_dist = ed
	if best_enemy_dist < my_dist - ENEMY_ADVANTAGE_DIST:
		return false  # 球权倾向对方，我放弃抢球转防守站位

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


## 刷新所有AI球员的速度profile（player.speed变化后调用，比如换装备/吃食物后）
func refresh_all_speeds() -> void:
	for ap in ai_players:
		var base_speed: float = ap.player.speed
		var profile: AIProfile = ap.profile
		profile.speed_chase = base_speed * profile.speed_chase_mult
		profile.speed_dribble = base_speed * profile.speed_dribble_mult
		profile.speed_move = base_speed * profile.speed_move_mult
	print("[AI] 所有球员速度profile已刷新")


func get_player_profile(player_index: int) -> AIProfile:
	"""获取指定球员的AI配置"""
	for ap in ai_players:
		if ap.team == "a" and ap.index == player_index:
			return ap.profile
	return null
