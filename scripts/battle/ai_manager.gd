extends Node
## AI管理器 - 控制所有非玩家操作球员的行为
## 设计思路：
##   - 持球后有观察期，不立即动作
##   - 传球评分：看目标的进攻位置、是否空位、离球门距离
##   - 跑位散开，避免扎堆
##   - 加入随机因子，行为不可完全预测

var battle_manager: Node2D
var input_manager: Node
var ball_node: Area2D

enum State {
	IDLE,
	CHASE_BALL,
	GOTO_BALL,
	DRIBBLE,     # 带球推进（持球移动寻找机会）
	ATTACK,      # 投球攻击
	PASS,        # 传球
	DEFEND,
	SUPPORT
}

enum PlayerStrategy { BREAKTHROUGH, DEFENSE, PASSING }
enum TeamStrategy { OFFENSIVE, DEFENSIVE, BALANCED }

var ai_players: Array[Dictionary] = []

var team_a_strategy: int = TeamStrategy.BALANCED
var team_b_strategy: int = TeamStrategy.BALANCED

# 速度
const MOVE_SPEED: float = 150.0
const CHASE_SPEED: float = 190.0
const DRIBBLE_SPEED: float = 140.0

# 范围
const AGGRO_RANGE: float = 400.0
const PASS_RANGE: float = 320.0
const SHOOT_DIST: float = 100.0
const ARRIVE_THRESHOLD: float = 15.0

# 决策
const THINK_INTERVAL: float = 0.2
var think_timer: float = 0.0

# 场地边界
const FIELD_X_MIN: float = -380.0
const FIELD_X_MAX: float = 380.0
const FIELD_Y_MIN: float = -260.0
const FIELD_Y_MAX: float = 260.0

# 球门位置
const GOAL_A: Vector2 = Vector2(300.0, 0.0)    # 队A进攻方向（右）
const GOAL_B: Vector2 = Vector2(-300.0, 0.0)   # 队B进攻方向（左）


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
	
	think_timer += delta
	var do_think: bool = think_timer >= THINK_INTERVAL
	if do_think:
		think_timer = 0.0
	
	for ap in ai_players:
		if not _is_valid(ap):
			continue
		if do_think:
			_decide(ap)
		_move(ap, delta)


# ===== 注册 =====

func register_player(player: CharacterBody2D, team_name: String, index: int) -> void:
	ai_players.append({
		"player": player,
		"team": team_name,
		"index": index,
		"state": State.IDLE,
		"target_pos": player.global_position,
		"home_pos": player.global_position,
		"personal_strategy": PlayerStrategy.PASSING,
		"hold_timer": 0.0,            # 持球观察计时
		"hold_duration": 0.5,         # 本次需要观察多久
		"dribble_target": Vector2.ZERO,
	})
	print("[AI] 注册 队%s 位置%d" % [team_name, index])


func _is_valid(ap: Dictionary) -> bool:
	var p: CharacterBody2D = ap.player
	if not p or not is_instance_valid(p):
		return false
	if p.is_defeated:
		return false
	if p.get("is_penalized") == true:
		return false
	if input_manager and input_manager.controlled_player == p:
		return false
	return true


# ==============================
# ===== 决策（核心逻辑）========
# ==============================

func _decide(ap: Dictionary) -> void:
	var p: CharacterBody2D = ap.player
	var team: String = ap.team
	var strategy: int = team_a_strategy if team == "a" else team_b_strategy
	var personal: int = ap.personal_strategy
	
	# 持球：进入持球决策
	if p.is_carrying_ball:
		_decide_carrying(ap, strategy, personal)
		return
	
	# 更新持球观察计时（未持球时重置）
	ap.hold_timer = 0.0
	
	var ball_pos: Vector2 = ball_node.global_position
	var ball_active: bool = ball_node.is_active
	var my_pos: Vector2 = p.global_position
	var dist_to_ball: float = my_pos.distance_to(ball_pos)
	
	# 球在飞行中
	if ball_active:
		if _am_i_closest_to_ball(ap, team) and dist_to_ball < AGGRO_RANGE:
			ap.state = State.CHASE_BALL
			ap.target_pos = ball_pos
		else:
			ap.state = State.SUPPORT
			ap.target_pos = _get_smart_support_pos(ap, strategy)
		return
	
	# 球落地没人拿
	if not ball_node.owner_player:
		if dist_to_ball < AGGRO_RANGE:
			ap.state = State.GOTO_BALL
			ap.target_pos = ball_pos
		else:
			ap.state = State.SUPPORT
			ap.target_pos = _get_smart_support_pos(ap, strategy)
		return
	
	# 球在队友手里：跑位
	ap.state = State.SUPPORT
	ap.target_pos = _get_smart_support_pos(ap, strategy)


func _decide_carrying(ap: Dictionary, strategy: int, personal: int) -> void:
	var p: CharacterBody2D = ap.player
	var team: String = ap.team
	var my_pos: Vector2 = p.global_position
	var goal: Vector2 = GOAL_A if team == "a" else GOAL_B
	var forward: Vector2 = Vector2(1, 0) if team == "a" else Vector2(-1, 0)
	
	# === 持球观察期：拿球后不立即动作 ===
	ap.hold_timer += THINK_INTERVAL
	if ap.hold_timer < ap.hold_duration:
		# 观察期间带球慢推进
		ap.state = State.DRIBBLE
		ap.target_pos = _clamp_to_field(my_pos + forward * 60.0)
		return
	
	# === 观察结束，做决策 ===
	
	# 1) 评估当前局势
	var dist_to_goal: float = my_pos.distance_to(goal)
	var enemy_near: bool = _has_enemy_nearby(ap, 120.0)
	var enemy_very_close: bool = _has_enemy_nearby(ap, 60.0)
	
	# 2) 找最佳传球目标（带评分）
	var pass_result: Dictionary = _eval_best_pass(ap)
	var pass_target: CharacterBody2D = pass_result.get("target") as CharacterBody2D if pass_result.has("target") else null
	var pass_score: float = pass_result.get("score", -INF) if pass_result.has("score") else -INF
	
	# 3) 找投球目标（敌人）
	var shoot_target: CharacterBody2D = _find_nearest_enemy(ap)
	var shoot_score: float = _eval_shoot(ap, shoot_target, dist_to_goal)
	
	# 4) 带球推进评分
	var dribble_score: float = _eval_dribble(ap, dist_to_goal, enemy_near)
	
	# 5) 根据个人策略加权
	match personal:
		PlayerStrategy.BREAKTHROUGH:
			dribble_score += 25.0
			shoot_score += 10.0
		PlayerStrategy.DEFENSE:
			pass_score += 20.0
			dribble_score -= 15.0
		PlayerStrategy.PASSING:
			pass_score += 10.0
			# 只有传球目标位置确实更好才加分
			if pass_target:
				var my_goal_dist: float = my_pos.distance_to(goal)
				var tm_goal_dist: float = pass_target.global_position.distance_to(goal)
				if tm_goal_dist < my_goal_dist - 50.0:
					pass_score += 20.0  # 目标更靠近球门
				else:
					pass_score -= 10.0  # 目标不比你好，别传
	
	# 团队策略加权
	match strategy:
		TeamStrategy.OFFENSIVE:
			dribble_score += 10.0
			shoot_score += 10.0
		TeamStrategy.DEFENSIVE:
			pass_score += 10.0
			dribble_score -= 10.0
	
	# 被逼抢时紧急处理
	if enemy_very_close:
		if pass_target:
			pass_score += 30.0  # 紧急传球
		shoot_score += 15.0  # 或紧急投球
	
	# 加一点随机性（±8分），避免行为完全可预测
	var rng: float = randf() * 16.0 - 8.0
	pass_score += rng
	shoot_score += rng * 0.5
	dribble_score += rng * 0.3
	
	# 6) 选最高分的行动
	if pass_score >= shoot_score and pass_score >= dribble_score and pass_target:
		ap.state = State.PASS
		ap.target_pos = pass_target.global_position
	elif shoot_score >= dribble_score and shoot_target:
		ap.state = State.ATTACK
		ap.target_pos = shoot_target.global_position
	else:
		ap.state = State.DRIBBLE
		ap.target_pos = _clamp_to_field(my_pos + forward * 100.0 + Vector2(0, randf() * 60.0 - 30.0))
	
	# 投球后重置观察计时
	if ap.state == State.ATTACK or ap.state == State.PASS:
		ap.hold_timer = 0.0
		ap.hold_duration = randf_range(0.3, 0.7)


# ==============================
# ===== 行动评分 ================
# ==============================

func _eval_best_pass(ap: Dictionary) -> Dictionary:
	"""评估最佳传球目标，返回 {target, score}"""
	var p: CharacterBody2D = ap.player
	var team: String = ap.team
	var goal: Vector2 = GOAL_A if team == "a" else GOAL_B
	var best: CharacterBody2D = null
	var best_score: float = -INF
	
	for other in ai_players:
		if other.team != team:
			continue
		if other.player == p:
			continue
		if not _is_valid(other):
			continue
		
		var tm: CharacterBody2D = other.player
		var dist: float = p.global_position.distance_to(tm.global_position)
		
		# 距离检查
		if dist < 40.0 or dist > PASS_RANGE:
			continue
		
		var score: float = 0.0
		
		# 1) 目标离对方球门越近越好
		var tm_goal_dist: float = tm.global_position.distance_to(goal)
		score += (300.0 - tm_goal_dist) * 0.1
		
		# 2) 目标前方有空当（目标附近无敌人）
		var tm_has_enemy: bool = false
		for enemy in ai_players:
			if enemy.team == team:
				continue
			if not is_instance_valid(enemy.player):
				continue
			if tm.global_position.distance_to(enemy.player.global_position) < 80.0:
				tm_has_enemy = true
				break
		if not tm_has_enemy:
			score += 30.0  # 空位加分
		else:
			score -= 20.0  # 有人盯防减分
		
		# 3) 传球方向是向前的加分
		var forward: Vector2 = Vector2(1, 0) if team == "a" else Vector2(-1, 0)
		var to_tm: Vector2 = (tm.global_position - p.global_position).normalized()
		score += forward.dot(to_tm) * 20.0
		
		# 4) 距离适中（100~250最佳）
		if dist > 100.0 and dist < 250.0:
			score += 15.0
		elif dist < 80.0:
			score -= 10.0  # 太近没意义
		
		# 5) 不要传给刚传过来的人（避免来回传）
		if ball_node and ball_node.attacker_player == tm:
			score -= 25.0
		
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
	
	# 越近越容易命中
	if dist < 150.0:
		score += 40.0
	elif dist < 250.0:
		score += 20.0
	else:
		score += 5.0
	
	# 目标没在待接球状态更容易命中
	if not target.is_ready_to_catch:
		score += 15.0
	
	# 离球门近时更倾向投球
	if dist_to_goal < 200.0:
		score += 20.0
	
	return score


func _eval_dribble(ap: Dictionary, dist_to_goal: float, enemy_near: bool) -> float:
	"""评估带球推进评分"""
	var score: float = 10.0  # 基础分：带球推进是合理的默认选择
	
	# 离球门远时更适合带球推进
	if dist_to_goal > 200.0:
		score += 15.0
	
	# 附近没敌人时适合带球
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
	var target: Vector2 = _clamp_to_field(ap.target_pos)
	var dist: float = p.global_position.distance_to(target)
	
	match ap.state:
		State.IDLE:
			p.velocity = Vector2.ZERO
		
		State.CHASE_BALL, State.GOTO_BALL:
			if dist < ARRIVE_THRESHOLD:
				_try_pickup_ball(ap)
				p.velocity = Vector2.ZERO
			else:
				p.velocity = (target - p.global_position).normalized() * CHASE_SPEED
				p.move_and_slide()
		
		State.DRIBBLE:
			if not p.is_carrying_ball:
				ap.state = State.IDLE
				return
			if dist < ARRIVE_THRESHOLD:
				# 到了推进目标，重置观察期重新决策
				ap.hold_timer = 0.0
				ap.hold_duration = randf_range(0.2, 0.5)
				p.velocity = Vector2.ZERO
			else:
				p.velocity = (target - p.global_position).normalized() * DRIBBLE_SPEED
				p.move_and_slide()
		
		State.ATTACK:
			if p.is_carrying_ball:
				_do_shoot(ap)
			else:
				ap.state = State.IDLE
		
		State.PASS:
			if p.is_carrying_ball:
				_do_pass(ap)
			else:
				ap.state = State.IDLE
		
		State.DEFEND:
			if dist < ARRIVE_THRESHOLD:
				p.velocity = Vector2.ZERO
			else:
				p.velocity = (target - p.global_position).normalized() * MOVE_SPEED
				p.move_and_slide()
		
		State.SUPPORT:
			if dist < ARRIVE_THRESHOLD:
				p.velocity = Vector2.ZERO
			else:
				p.velocity = (target - p.global_position).normalized() * MOVE_SPEED
				p.move_and_slide()
	
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
	var shoot_dir: Vector2
	if target_pos != Vector2.ZERO:
		shoot_dir = (target_pos - p.global_position).normalized()
	else:
		shoot_dir = Vector2(1, 0) if p.team == "a" else Vector2(-1, 0)
	
	p.set_carrying_ball(false)
	ball_node.launch(p.global_position, shoot_dir, p.attack_power, 600.0, p, [] as Array[Dictionary])
	
	ap.state = State.DEFEND
	ap.target_pos = ap.home_pos
	print("[AI] %s 投球!" % _pname(p))


func _try_pickup_ball(ap: Dictionary) -> void:
	if not ball_node:
		return
	if ball_node.is_active:
		return
	if ball_node.owner_player:
		return
	ball_node.return_to_player(ap.player)
	# 拿到球后设置随机观察期
	ap.hold_timer = 0.0
	ap.hold_duration = randf_range(0.3, 0.8)


# ==============================
# ===== 跑位系统 ================
# ==============================

func _get_smart_support_pos(ap: Dictionary, strategy: int) -> Vector2:
	"""智能跑位：散开、靠近球但不过度聚集"""
	var p: CharacterBody2D = ap.player
	var team: String = ap.team
	var home: Vector2 = ap.home_pos
	var ball_pos: Vector2 = ball_node.global_position
	var forward: Vector2 = Vector2(1, 0) if team == "a" else Vector2(-1, 0)
	
	# 基础：从home向球方向偏移
	var base_pos: Vector2 = home.lerp(ball_pos, 0.25)
	
	# 团队策略偏移
	match strategy:
		TeamStrategy.OFFENSIVE:
			base_pos += forward * 80.0
		TeamStrategy.DEFENSIVE:
			base_pos -= forward * 40.0
	
	# 散开：计算与队友的距离，太近则偏移
	var spread_offset: Vector2 = Vector2.ZERO
	for other in ai_players:
		if other.team != team:
			continue
		if other.player == p:
			continue
		if not _is_valid(other):
			continue
		var dist: float = p.global_position.distance_to(other.player.global_position)
		if dist < 100.0 and dist > 0.0:
			# 离队友太近，反方向偏移
			spread_offset += (p.global_position - other.player.global_position).normalized() * (100.0 - dist) * 0.5
	
	base_pos += spread_offset
	
	return _clamp_to_field(base_pos)


# ==============================
# ===== 辅助函数 ================
# ==============================

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
	var p: CharacterBody2D = ap.player
	var enemy_team: String = "b" if ap.team == "a" else "a"
	var nearest: CharacterBody2D = null
	var nearest_dist: float = INF
	for other in ai_players:
		if other.team != enemy_team:
			continue
		if not is_instance_valid(other.player):
			continue
		var dist: float = p.global_position.distance_to(other.player.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = other.player
	return nearest


func _has_enemy_nearby(ap: Dictionary, range: float) -> bool:
	var p: CharacterBody2D = ap.player
	var enemy_team: String = "b" if ap.team == "a" else "a"
	for other in ai_players:
		if other.team != enemy_team:
			continue
		if not is_instance_valid(other.player):
			continue
		if p.global_position.distance_to(other.player.global_position) < range:
			return true
	return false


func _clamp_to_field(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, FIELD_X_MIN, FIELD_X_MAX),
		clampf(pos.y, FIELD_Y_MIN, FIELD_Y_MAX)
	)


func _clamp_player_position(p: CharacterBody2D) -> void:
	var pos: Vector2 = p.global_position
	var clamped := Vector2(
		clampf(pos.x, FIELD_X_MIN, FIELD_X_MAX),
		clampf(pos.y, FIELD_Y_MIN, FIELD_Y_MAX)
	)
	if pos != clamped:
		p.global_position = clamped
		p.velocity = Vector2.ZERO


func _pname(p: CharacterBody2D) -> String:
	if p.char_data and p.char_data.has("name"):
		return str(p.char_data.name)
	return "Player"


# ===== 公开方法 =====

func set_player_strategy(player_index: int, strategy: int) -> void:
	for ap in ai_players:
		if ap.team == "a" and ap.index == player_index:
			ap.personal_strategy = strategy
			break


func set_team_strategy(team_name: String, strategy: int) -> void:
	if team_name == "a":
		team_a_strategy = strategy
	else:
		team_b_strategy = strategy
