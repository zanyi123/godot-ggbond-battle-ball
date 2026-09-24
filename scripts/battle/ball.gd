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
var bounced_by_resilience: bool = false  # 韧性弹飞球：落地球权回攻击者（防半场白送，2026-09-11）
var _first_land_emitted: bool = false    # V1-3 首触地钩子：一次投球只发一次
var wall_bounce_count: int = 0           # 波4 #15：本次飞行已撞墙反弹次数
var is_clone: bool = false               # 波6 #8：子球克隆标记（不再分裂、停止即消散）
var mother_ref: Node = null              # 波6 #8：母球引用（子球被接时球权归还路径）
var _spread_done: bool = false           # 波6 #8：本次飞行已分裂
var _manual_active: bool = false         # 波6 #17：手动态
var _manual_time_left: float = 0.0       # 波6 #17：手动态剩余时长

var stuck_on_obstacle: StaticBody2D = null  # 球卡在障碍物上时引用

## 碰撞追踪：本次飞行已命中的球员instance_id，防止双重命中
var _hit_player_ids: Dictionary = {}

## ==================== 物理属性 ====================
## 球天然弹性（M1 弹道物理基准，默认1.0=完全反弹·碰碰球效果）
## 0=完全无弹跳（兼容旧"无反弹"语义）, 1=完全反弹
## 场地弹性系数（FieldPhysicsManager）作为技能加成叠加，见 _get_effective_bounce_e()
var bounce_coefficient: float = 1.0

## 空中斜线（P0）：z 随水平距离线性插值，触地贴地。直线不下坠原则保持——是直线，只是斜的
func _step_z_lerp() -> void:
	var z: float = z_lerp_start + flight_distance * z_lerp_tan
	if z <= 0.0:
		ball_z = 0.0  # 触地：贴地滑行
	else:
		ball_z = z


## a方案 耗尽下坠触发：距离耗尽且球在空中时调用（球权分配后播短抛物线落回地面）
func start_visual_fall() -> void:
	if ball_z > 0.0:
		visual_fall_left = 0.35
		ball_z_vel = -ball_z / 0.35 + 0.5 * GRAVITY_Z * 0.35  # 0.35s 恰好落到 z=0


## ==================== M4 高度命中 ====================

## 高度窗口：球垂直区间 [z-HALF, z+HALF] 与目标命中区间重叠才可命中/接球
## 恒高球(55±12)打得到站立者、打不到跳跃顶点者；lob 高飞段需跳起拦截
func _can_hit_target_at(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	# 波4 #22 必中：高度窗豁免（跳跃也躲不开）
	if ball_mods.get("sure_hit", false):
		return true
	if not target.has_method("get_hit_z_range"):
		return true  # 无高度接口的对象按旧规则可命中
	var r: Vector2 = target.get_hit_z_range()
	return (ball_z - BALL_HIT_HALF) < r.y and (ball_z + BALL_HIT_HALF) > r.x


## 命中预览（P1 双视角共用核心）：直线 z(L)=start_z+L·tanφ 与各球员命中窗口求交
## 返回会被路径击中的球员数组（提示用，非锁定）。players 元素需有 global_position/get_hit_z_range
static func preview_path_hits(from: Vector2, start_z: float, pitch_deg: float, max_dist: float, direction: Vector2, players: Array) -> Array:
	var hits: Array = []
	var tan_p: float = tan(deg_to_rad(clampf(pitch_deg, -60.0, 30.0)))
	var dir: Vector2 = direction.normalized()
	for p in players:
		if p == null or not is_instance_valid(p) or not p is Node2D:
			continue
		if p.get("is_defeated"):
			continue
		var to_p: Vector2 = p.global_position - from
		var L: float = to_p.dot(dir)              # 沿路径的水平距离
		if L <= 0.0 or L > max_dist:
			continue
		var miss: float = (to_p - dir * L).length()
		if miss > 42.0:
			continue                              # 不在路径走廊内
		var z_at: float = start_z + L * tan_p
		var hit_range: Vector2 = p.get_hit_z_range() if p.has_method("get_hit_z_range") else Vector2(0, 50)
		if (z_at - BALL_HIT_HALF) < hit_range.y and (z_at + BALL_HIT_HALF) > hit_range.x:
			hits.append(p)
	return hits


## ==================== M2 蓝墙反弹 ====================
const WALL_BOUNCE_E: float = 1.0  # 墙反弹恢复系数（1=完全反弹，与球天然弹性口径一致）

## 撞竖直蓝墙：越界即夹回边界并反射方向（v_n' = -e×v_n，切向保持）
## 边界=3D 蓝墙实测位（±650/±390），水平反射与 z 弹道/技能豁免无关——追踪/回旋球同样受墙约束
## 反弹后球恒在场内，"出界归还球权"仅作兜底不再触发（蓝墙内不出界）
func _bounce_off_walls() -> void:
	if not use_wall_bounce:
		return
	# 波4 #15 反弹增强：次数超限 → 不再反弹（球继续飞，出界兜底）
	var bounce_max: int = int(ball_mods.get("bounce_max", 0))
	if bounce_max > 0 and wall_bounce_count >= bounce_max:
		return
	var pos := global_position
	var d := ball_direction
	var hit_normal := Vector2.ZERO
	if pos.x < WALL_X_MIN and d.x < 0.0:
		pos.x = WALL_X_MIN
		d.x = -d.x
		hit_normal = Vector2.RIGHT
	elif pos.x > WALL_X_MAX and d.x > 0.0:
		pos.x = WALL_X_MAX
		d.x = -d.x
		hit_normal = Vector2.LEFT
	if pos.y < WALL_Y_MIN and d.y < 0.0:
		pos.y = WALL_Y_MIN
		d.y = -d.y
		hit_normal = Vector2.DOWN
	elif pos.y > WALL_Y_MAX and d.y > 0.0:
		pos.y = WALL_Y_MAX
		d.y = -d.y
		hit_normal = Vector2.UP
	if hit_normal != Vector2.ZERO:
		ball_direction = d.normalized()
		if WALL_BOUNCE_E < 1.0:
			ball_speed *= WALL_BOUNCE_E  # e<1 时每次撞墙衰减
		# 波4 #15：反弹速度倍率（>1=风暴弹珠加速型）
		var bounce_mult: float = float(ball_mods.get("bounce_speed_mult", 1.0))
		if bounce_mult != 1.0:
			ball_speed *= bounce_mult
		wall_bounce_count += 1
		global_position = pos
		print("[Ball] 撞蓝墙反弹! 法线%s 方向%s 第%d次" % [hit_normal, ball_direction, wall_bounce_count])


## ==================== M1 弹道物理（水平场地弹跳，2026-09-12） ====================
## z 单位=像素（单位制铁律：与 3D 世界 1:1）。出手高 55 与 3D 持球高一致。
## 总开关关闭时 z 完全不积分，行为=旧版恒高直飞。
var use_ballistic_physics: bool = false  # 总开关（默认关：飞行球暂不落地恒高飞行=旧观感；弹跳框架保留可随时开）
var ball_z: float = 0.0                  # 球离地高度（像素，向上为正）
var ball_z_vel: float = 0.0              # 垂直速度（px/s）

# 项1 空格迁移（操控规划/05 §1 主人裁决 2026-09-24）：手动态球高度双语义
# 贴地奔跑类=跳跃（冲量+重力回落）/ 飞行类=上升增量（无重力维持，params.space_mode="rise"）
const STEER_JUMP_VEL: float = 300.0      # 跳跃冲量 px/s
const STEER_RISE_STEP: float = 40.0      # 每次上升增量 px
const STEER_RISE_MAX: float = 240.0      # 上升上限 px
var _steer_jump_airborne: bool = false   # 跳跃滞空标志（走重力回落）
## E9 轨迹全记录（主人复测工具）：每次发球记录出手/途径/终止全链
var _traj_active: bool = false
var _traj_log: Array = []
var _traj_seq: int = 0
var bounce_count: int = 0               # 已落地弹跳次数
var flight_seq: int = 0                  # 发球序号（每次 launch+1；AI 躲球骰子的稳定威胁标识，跨运行可复现）
var use_wall_bounce: bool = true         # M2 蓝墙反弹开关（水平反射，与 z 弹道无关）

## 空中斜线发球（P0）：z 沿飞行距离线性插值，触地贴地
var z_lerp_active: bool = false
var z_lerp_start: float = 0.0
var z_lerp_tan: float = 0.0
var visual_fall_left: float = 0.0        # a方案：球权已分配后的下坠表现剩余时间（仅视觉）
const GRAVITY_Z: float = 900.0           # 重力加速度 px/s²
const BALL_HEIGHT_CARRY: float = 55.0    # 出手高度（3D铁律：持球55）
const BOUNCE_SPEED_MIN: float = 80.0     # 反弹速度低于此值→贴地滚动

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

# M2 蓝墙位置（3D 蓝墙 Border mesh 实测 x=±650 / z=±390，即蓝色禁区外框 1300×780；
# 注意区分 FIELD_* ±510/±325=外场白线——反弹必须贴 3D 蓝墙，不能用外场线）
const WALL_X_MIN: float = -650.0
const WALL_X_MAX: float = 650.0
const WALL_Y_MIN: float = -390.0
const WALL_Y_MAX: float = 390.0

# M4 高度命中（球垂直命中半高：球半径≈10.5+判定余量）
const BALL_HIT_HALF: float = 12.0
# M4 高抛轨迹（上抛初速：顶点≈55+50px，越过站立球员头顶，需跳跃拦截）
const LOB_INITIAL_VZ: float = 300.0

signal ball_caught(player: CharacterBody2D)
signal ball_hit_player(player: CharacterBody2D, damage: float)
signal ball_out_of_bounds()
# V1-3 区域触发钩子（06 文档）：只读事件，供"球落点生成区域"类技能消费
signal ball_first_land(pos: Vector2)   # 首次触地瞬时（弹道/lob 生效；恒高球不触发）
signal ball_stopped(pos: Vector2)      # 球停止结算点（距离耗尽/内场停回手）


## 返回球视觉半径，用于技能轮廓渲染（2026-06-19）
## 智能识别接口：未来3D化时只需改这里
func get_visual_radius() -> float:
	return 20.0  # 当前2D球半径，与 _setup_visuals 中 ball_visual 一致


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

	# 2026-09-20 P1-1：原"连接技能状态信号"死路径已删（组内无 skill_activated/cancelled 信号，
	# has_signal 防御致静默不连）；球技能光环由 player 侧主动通知（set_active_skill/cancel_active_skill）


func _physics_process(delta: float) -> void:
	# a方案 耗尽下坠表现：球权已即时分配（is_active=false），高度继续短抛物线落回 0
	if _manual_active and (ball_z > 0.0 or _steer_jump_airborne):
		# 项1 空格迁移：跳跃滞空走重力回落；上升增量高度无重力维持（飞行类贴语义）
		if _steer_jump_airborne:
			ball_z += ball_z_vel * delta
			ball_z_vel -= GRAVITY_Z * delta
			if ball_z <= 0.0:
				ball_z = 0.0
				ball_z_vel = 0.0
				_steer_jump_airborne = false
	if visual_fall_left > 0.0:
		visual_fall_left -= delta
		ball_z += ball_z_vel * delta
		ball_z_vel -= GRAVITY_Z * delta
		if ball_z <= 0.0:
			ball_z = 0.0
			visual_fall_left = 0.0
			# V1-3：恒高球（弹道关）无弹道触地，视觉落地即首触地（ball_land 类技能的恒高兜底）
			if not _first_land_emitted:
				_first_land_emitted = true
				ball_first_land.emit(global_position)
	elif not is_active:
		ball_z = 0.0
	# M1 弹道 2D 表现：球精灵随 z 上移、影子留地变淡
	var lift: float = ball_z if (is_active or visual_fall_left > 0.0) else 0.0
	if ball_visual:
		ball_visual.position.y = -11.0 - lift
	if ball_shadow:
		ball_shadow.modulate.a = clampf(1.0 - lift / 150.0, 0.25, 1.0)

	if not is_active:
		# 持球时跟随球员
		if not is_active and owner_player != null and is_instance_valid(owner_player):
			global_position = owner_player.global_position + Vector2(0, -40)
		return

	# 球卡在障碍物上：逐帧消耗
	if stuck_on_obstacle:
		_process_obstacle_stuck(delta)
		return

	# === M1 弹道物理：z 轴积分（技能接管球跳过——暂时无视物理，高度由技能定义）===
	if not _is_skill_controlled():
		if z_lerp_active:
			_step_z_lerp()
		else:
			_step_ballistic_z(delta)

	# === 追踪球状态（2026-09-19 快照化：全部读球私有快照）===
	var is_tracking: bool = ball_mods.get("tracking_target") != null and not ball_mods.get("lock_straight", false)

	# === 追踪：向目标转向 ===
	if is_tracking:
		var target: Node = ball_mods.get("tracking_target")
		if target and is_instance_valid(target) and not target.is_defeated:
			# 目标隐身 → 丢失目标，转直飞（波4 #22 必中球豁免：隐身也躲不开）
			if target.has_method("is_status_active") and target.is_status_active("stealthed") \
					and not ball_mods.get("sure_hit", false):
				ball_mods["tracking_target"] = null
			else:
				var desired_dir: Vector2 = (target.global_position - global_position).normalized()
				var turn_speed: float = ball_mods.get("tracking_turn_speed", 0.0)
				# 波4 #22 必中：追踪转向无速率限制（每帧直接对准目标=必达）
				if ball_mods.get("sure_hit", false):
					ball_direction = desired_dir
				else:
					ball_direction = ball_direction.move_toward(desired_dir, turn_speed * delta).normalized()
		else:
			ball_mods["tracking_target"] = null

	# === 回旋：飞到一半距离时返回（触发状态内联为球私有）===
	var is_boomerang: bool = ball_mods.get("boomerang", false) and not ball_mods.get("lock_straight", false)
	if is_boomerang:
		var trigger_ratio: float = ball_mods.get("boomerang_dist", 0.0)
		if trigger_ratio <= 0.0:
			trigger_ratio = 0.5
		if not _boomerang_triggered and flight_distance >= max_flight_distance * trigger_ratio:
			_boomerang_triggered = true
			_boomerang_return_dir = -ball_direction
			ball_direction = _boomerang_return_dir

	# 非直行时才允许弧线
	var allow_arc: bool = true
	if ball_mods.get("lock_straight", false):
		allow_arc = false

	var move_vector: Vector2 = ball_direction * ball_speed * delta

	if trajectory_type == "arc" and allow_arc:
		ball_direction = ball_direction.rotated(deg_to_rad(30) * delta)

	var prev_x := position.x
	position += move_vector
	flight_distance += move_vector.length()

	# 波6 #8 分裂：到达触发距离 → 分裂子球（母球存续；子球克隆不再分裂）
	if not is_clone and not _spread_done:
		var spread_count: int = int(ball_mods.get("spread_count", 0))
		var trigger_pct: float = float(ball_mods.get("spread_trigger_dist_pct", 0.6))
		if spread_count > 0 and flight_distance >= max_flight_distance * trigger_pct:
			_spread_done = true
			_spawn_clones(spread_count, float(ball_mods.get("spread_damage_ratio", 1.0)))

	# 波6 #17 手动制导：方向由 input_manager 每帧注入（manual_steer）；超时/能量尽回直线
	if _manual_active:
		_manual_time_left -= delta
		if attacker_player and is_instance_valid(attacker_player):
			attacker_player.spirit_energy = maxf(0.0, attacker_player.spirit_energy - float(ball_mods.get("manual_energy_per_sec", 3.0)) * delta)
		if _manual_time_left <= 0.0 or (attacker_player and is_instance_valid(attacker_player) and attacker_player.spirit_energy <= 0.0):
			_manual_active = false
			print("[Ball] 手动制导结束")
	# E9 轨迹采样：跨越中线瞬间记录
	if _traj_active and ((prev_x < 0.0 and position.x >= 0.0) or (prev_x > 0.0 and position.x <= 0.0)):
		_traj_log.append("过中线@%s 已飞%.0f" % [str(position.round()), flight_distance])

	# === 距离碰撞检测：补充 body_entered 可能漏检的情况 ===
	_check_player_collision_distance()

	# === 检测障碍物碰撞 ===
	_check_obstacle_collision()

	# === M2 蓝墙反弹：撞场界夹回反射（墙是场地实体，与 z 弹道/技能豁免无关）===
	if use_wall_bounce:
		_bounce_off_walls()

	# === 检测出界 ===
	if _is_out_of_bounds():
		_on_ball_out_of_field()
		return

	# 超出最大距离（追踪球不受距离限制，直到命中球员）
	if not is_tracking and flight_distance >= max_flight_distance:
		_on_ball_stopped()

	# 更新技能光环动画
	_process_aura(delta)


func _is_out_of_bounds() -> bool:
	# M2 墙反弹开启：蓝墙内不出界，判定边界=3D蓝墙位（仅兜底，反弹后正常永不触发）
	if use_wall_bounce:
		return global_position.x < WALL_X_MIN or global_position.x > WALL_X_MAX \
			or global_position.y < WALL_Y_MIN or global_position.y > WALL_Y_MAX
	return global_position.x < FIELD_X_MIN or global_position.x > FIELD_X_MAX \
		or global_position.y < FIELD_Y_MIN or global_position.y > FIELD_Y_MAX


func _on_ball_out_of_field() -> void:
	"""球出场地边界 → 按区域判定球回到对应队伍"""
	is_active = false
	_set_idle_visual()
	ball_out_of_bounds.emit()
	_traj_end("出界")

	# === 韧性弹飞球出界：球权回攻击者（弹飞朝防守方深处飞，按半场给=必白送防守方——攻防对称） ===
	if bounced_by_resilience:
		bounced_by_resilience = false
		if attacker_player and is_instance_valid(attacker_player):
			print("[Ball] 弹飞球出界,球权回攻击者 %s" % _pname(attacker_player))
			return_to_player(attacker_player)
		return

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

	# === M4 高度窗口：球从头顶飞过不触发命中/接球 ===
	if not _can_hit_target_at(body):
		return

	var player: CharacterBody2D = body

	# 不能击中发球者自己
	if player == attacker_player:
		return

	# 已被击败的球员不拦截球
	if player.is_defeated:
		return

	# 防止双重命中（body_entered + 距离检测）
	var pid: int = player.get_instance_id()
	if _hit_player_ids.has(pid):
		return
	_hit_player_ids[pid] = true

	# === 同队队友 → 直接接球,不造成伤害 ===
	if attacker_player and player.team == attacker_player.team:
		_catch_ball(player)
		return

	# === 幻象：击中只扣幻象体力，球继续飞（不当作击中真身）===
	if player.has_method("get") and player.get("is_illusion") == true:
		player.take_damage(ball_damage, attacker_player, _attacker_element())
		ball_hit_player.emit(player, ball_damage)
		# 穿透模式下继续飞；非穿透也继续飞（幻象是虚假目标，不挡球权流转）
		print("[Ball] 击中幻象 %s, 扣体力, 球继续飞行" % (player.illusion_id if player.get("illusion_id") else "?"))
		return

	# === 对方球员 → 击中造成伤害 ===
	var result: Dictionary = player.take_damage(ball_damage, attacker_player, _attacker_element())
	var actual_damage: int = result.get("damage", 0)
	var effect: String = result.get("effect", "none")
	ball_hit_player.emit(player, actual_damage)

	# 波6 #18 带人位移：命中结算附加拖拽（免控目标在 player 侧拒绝）
	var pull_speed: float = float(ball_mods.get("carry_pull_speed", 0.0))
	if pull_speed > 0.0 and actual_damage > 0 and player.has_method("begin_carry_push"):
		player.begin_carry_push(ball_direction, pull_speed, float(ball_mods.get("carry_max_duration", 1.0)), self)
	
	# 上报个人数据：待接球时被击中视为截球尝试
	if player.is_ready_to_catch:
		var mps = _get_match_stats()
		if mps and mps.is_recording():
			mps.report_ball_intercepted(player)

	# === AOE范围伤害：以被击中球员为圆心，对范围内敌方球员造成伤害 ===
	# 2026-09-20 P0-2 修复：索敌从 "players" 组（生产仅幻象注册→命中恒空）改为权威名册
	# _get_all_players_array()（GameManager.team_a/b，与 handler/trigger 注入名册同源）
	if ball_mods.get("aoe_radius", 0.0) > 0.0:
		var aoe_radius: float = ball_mods.get("aoe_radius", 0.0)
		var aoe_pct: float = ball_mods.get("aoe_damage_pct", 0.5)
		var aoe_damage: float = ball_damage * aoe_pct
		var hit_count: int = 0
		if attacker_player and is_instance_valid(attacker_player):
			var enemy_team: String = "b" if attacker_player.team == "a" else "a"
			for p in _collect_aoe_targets(player, enemy_team, aoe_radius):
				p.take_damage(aoe_damage, attacker_player, _attacker_element())
				hit_count += 1
		print("[Ball] AOE范围伤害: 半径=%.0f 范围伤害=%.1f 命中%d人" % [aoe_radius, aoe_damage, hit_count])

	# E2 事件：HIT_TAKEN（含接球姿态命中，effect 供订阅者区分结果）
	var _bus = _event_bus()
	if _bus:
		_bus.emit_event(BattleEventBus.GameEvent.HIT_TAKEN, {"attacker": attacker_player, "defender": player, "damage": actual_damage, "effect": effect, "was_ready_to_catch": player.is_ready_to_catch})

	# === 待接球姿态：韧性判定决定接球成败（2026-09-11 补回 GD 缺失的接球机制）===
	# roll 结果映射：knockback1(一段轻击退)=接住球拿球权 / knockback2(二段)=脱手 / 弹飞=球飞走
	# 韧性越高 p_knockback 越高且二段概率越低 → 接住率随韧性提升（roll 概率表零改动）
	if player.is_ready_to_catch and effect == "knockback1" and not player.is_defeated:
		_catch_ball(player)
		print("[Ball] %s 待接球接住来球! 球权转换→队%s" % [_pname(player), player.team.to_upper()])
		return

	# === 状态标记（2026-09-19 快照化：读球私有快照）===
	var is_penetrating: bool = ball_mods.get("penetrate", false)
	var is_tracking: bool = ball_mods.get("tracking_target") != null and not ball_mods.get("lock_straight", false)

	# === 被击败 ===
	if player.is_defeated:
		if is_penetrating:
			print("[Ball] 穿透击中 %s(被击败),球继续飞行" % _pname(player))
			return
		is_active = false
		if is_tracking:
			# 追踪球：球权归受击方 → 回到受击者同队最近存活球员
			_return_to_nearest_team_player(player.team)
			print("[Ball] 追踪球击败 %s! 球回到队%s最近球员" % [_pname(player), player.team.to_upper()])
		elif attacker_player and is_instance_valid(attacker_player):
			return_to_player(attacker_player)
			print("[Ball] %s 被击败! 球回到 %s" % [_pname(player), _pname(attacker_player)])
		return

	# === 韧性效果响应 ===
	if effect == "ball_fly" or effect == "knockback_and_fly":
		# 弹飞方向以"远离攻击者"为基准（球沿来路继续向前弹），±60° 小偏转
		# 旧版沿当前方向 ±90° 随机会横向扫进受击者人群/弹回攻击者脸
		var away_dir: Vector2 = ball_direction
		if attacker_player and is_instance_valid(attacker_player):
			var to_hit: Vector2 = global_position - attacker_player.global_position
			if to_hit.length_squared() > 1.0:
				away_dir = to_hit.normalized()
		var random_angle: float = randf_range(-60.0, 60.0)
		ball_direction = away_dir.rotated(deg_to_rad(random_angle))
		bounced_by_resilience = true
		flight_distance = 0.0
		if _bus:
			_bus.emit_event(BattleEventBus.GameEvent.DEFEND_BOUNCED, {"defender": player, "direction": ball_direction})
		if is_tracking:
			# 追踪球：弹飞后继续追踪，不受距离限制
			print("[Ball] 追踪球-韧性弹飞! 方向偏转%.0f度,继续追踪" % random_angle)
		else:
			max_flight_distance = 600.0
			print("[Ball] %s 韧性弹飞! 方向偏转%.0f度" % [_pname(player), random_angle])
		return

	# === 追踪球：击中即停，球权归受击者 ===
	if is_tracking:
		is_active = false
		_catch_ball(player)
		print("[Ball] 追踪球击中 %s,球归受击者" % _pname(player))
		return

	# === 穿透：球不回攻击者，继续飞行 ===
	if is_penetrating:
		print("[Ball] 穿透击中 %s,球继续飞行" % _pname(player))
		return

	# === 普通球：球回到攻击者手上 ===
	if attacker_player and is_instance_valid(attacker_player):
		is_active = false
		_traj_end("命中%s回手" % _pname(player))
		return_to_player(attacker_player)
		print("[Ball] 击中 %s,球回到 %s" % [_pname(player), _pname(attacker_player)])


func _catch_ball(player: CharacterBody2D) -> void:
	# 波6 #8 子球：被接=球权转移给接住者（母球回手），克隆消散（F1 同规则）
	if is_clone:
		print("[Ball] 子球被 %s 接住! 球权转移" % _pname(player))
		if mother_ref and is_instance_valid(mother_ref) and mother_ref.has_method("return_to_player"):
			mother_ref.return_to_player(player)
		queue_free()
		return
	is_active = false
	owner_player = player
	player.set_carrying_ball(true)
	_set_idle_visual()
	ball_caught.emit(player)
	# 上报个人数据：接球
	var mps = _get_match_stats()
	if mps and mps.is_recording():
		mps.report_ball_caught(player)
	# 装备耐久消耗（接球）
	PlayerSaveManager.reduce_equipment_durability(player.character_id, "catch")
	print("[Ball] %s 接住球!" % _pname(player))


## E9 轨迹终止记录并打印完整链
func _traj_end(reason: String) -> void:
	if not _traj_active:
		return
	_traj_active = false
	_traj_log.append("终止[%s]@%s 已飞%.0f" % [reason, str(global_position.round()), flight_distance])
	print("[轨迹#%d] %s" % [_traj_seq, " → ".join(_traj_log)])


func _on_ball_stopped() -> void:
	"""球停止(超出距离但未出界)
	先检查附近是否有球员（视为命中），否则按半场分配球权
	"""
	# a方案：球在空中耗尽 → 球权照常即时分配，高度走视觉下坠（0.35s 抛物线）
	start_visual_fall()
	is_active = false
	_set_idle_visual()
	# V1-3 停球钩子：落点/停点生成区域类技能消费（含首触地兜底）
	_emit_stop_hooks()

	# === 球落地前，检查附近60px内是否有球员 ===
	var all_players := _get_all_players_array()
	var nearest_player: CharacterBody2D = null
	var nearest_dist: float = 60.0  # 命中判定范围

	for p in all_players:
		if not p or not is_instance_valid(p):
			continue
		if not p is CharacterBody2D:
			continue
		if p == attacker_player:
			continue
		if p.is_defeated:
			continue
		if _hit_player_ids.has(p.get_instance_id()):
			continue
		# M4 高度窗口：跳起者躲过贴地滚球
		if not _can_hit_target_at(p):
			continue
		var dist: float = global_position.distance_to(p.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_player = p

	if nearest_player:
		# 球停在球员附近 → 视为命中，走正常伤害判定
		print("[Ball] 球停在 %s 附近(%.0fpx),视为命中!" % [_pname(nearest_player), nearest_dist])
		is_active = true  # 临时恢复，让 _on_body_entered 正常执行
		_traj_end("60px近停命中")
		_on_body_entered(nearest_player)
		return

	# === E7v2 球权分层（吸附本意恢复+攻防对称）===
	# ① 停止在外场（凹字形判罚区）→ 吸附给该侧外场所属队（吸附本意，双方对称）
	# ② 停止在内场（比赛区，未命中任何人）→ 攻击失败，球权回攻击者（内场不白送）
	var pos := global_position
	var in_outer_zone: bool = absf(pos.x) > 380.0 or absf(pos.y) > 260.0
	if in_outer_zone:
		var outer_team := "a" if pos.x < 0 else "b"  # 左外场区归A / 右外场区归B（吸附本意）
		print("[Ball] 球停在外场(%.0f,%.0f) → 吸附给队%s" % [pos.x, pos.y, outer_team.to_upper()])
		_return_to_nearest_team_player(outer_team)
		return
	# 内场停止：攻击失败球回手（不白送防守方）
	if attacker_player and is_instance_valid(attacker_player):
		print("[Ball] 球停在内场(%s)未命中,球权回攻击者 %s | 攻击方位置=%s 停止位置=%s" % [str(int(flight_distance)) + "px", _pname(attacker_player), str(attacker_player.global_position), str(pos)])
		_traj_end("内场停回手")
		return_to_player(attacker_player)
		return
	# 兜底：无攻击者引用（异常态）按半场分配
	print("[Ball] 球落地,飞行距离: %.1f" % flight_distance)
	if global_position.x < 0:
		_return_to_nearest_team_player("a")
	else:
		_return_to_nearest_team_player("b")


## 标签效果处理器引用（2026-09-19 快照化：ball 只调其公开只读接口，不再依赖具体类型）
var tag_effect_handler: Node = null

# 2026-09-19 快照化：球私有修饰符快照（launch 时从 handler 领取）+ 回旋飞行状态（内联自 handler）
var ball_mods: Dictionary = {}
var _boomerang_triggered: bool = false
var _boomerang_return_dir: Vector2 = Vector2.ZERO

func launch(from: Vector2, direction: Vector2, damage: float, max_dist: float, attacker: CharacterBody2D, skills: Array[Dictionary] = [], start_z: float = -1.0, pitch_deg: float = 0.0) -> void:
	global_position = from
	ball_direction = direction.normalized()
	ball_damage = damage
	
	# === 获取攻击者的发球基础球速 ===
	var base_ball_speed: float = 400.0
	if attacker and attacker.has_method("get_base_ball_speed"):
		base_ball_speed = attacker.get_base_ball_speed()
	ball_speed = base_ball_speed  # 使用球员个性化球速
	
	max_flight_distance = max_dist
	attacker_player = attacker
	injected_skills = skills
	is_active = true
	flight_distance = 0.0
	owner_player = null
	bounced_by_resilience = false
	_first_land_emitted = false
	wall_bounce_count = 0
	_spread_done = false
	if is_clone:
		_manual_active = false  # 克隆继承保护（launch 重置兜底）
	trajectory_type = "straight"
	element_type = ""
	_hit_player_ids = {}
	flight_seq += 1
	# 空中斜线发球（P0）：start_z>=0 时启用 z 线性插值（直线，只是斜的）：
	# z(L) = start_z + L·tanφ，触地后贴地滑行至距离耗尽。默认 -1=恒高（现行为）
	z_lerp_active = start_z >= 0.0
	z_lerp_start = maxf(start_z, BALL_HEIGHT_CARRY)
	z_lerp_tan = tan(deg_to_rad(clampf(pitch_deg, -60.0, 30.0))) if z_lerp_active else 0.0
	ball_z = z_lerp_start if z_lerp_active else BALL_HEIGHT_CARRY
	ball_z_vel = 0.0
	bounce_count = 0
	visual_fall_left = 0.0
	# E9 轨迹记录：出手点
	_traj_seq += 1
	_traj_active = true
	_traj_log = []
	_traj_log.append("出手@%s 攻=%s 方向=%s 速=%.0f 距=%.0f" % [str(global_position.round()), _pname(attacker) if attacker else "?", str(ball_direction.round()), ball_speed, max_flight_distance])

	# 获取标签效果处理器
	if not tag_effect_handler:
		tag_effect_handler = _get_tag_effect_handler()

	# 显示已激活技能的光环
	if not injected_skills.is_empty():
		_show_skill_aura(injected_skills[0])

	# 技能标签在投球前已写入施法者的准备区（trigger._fire_skill 开头只清施法者自己的残留）；
	# 下方 launch 时领取该投球者的快照（过期字段回落默认值，取走即清）

	# 应用旧式技能
	for skill in skills:
		var tag: String = skill.get("tag") if skill.has("tag") else ""
		if tag == "on_ball":
			_apply_ball_skill(skill)

	# E2 事件：ATTACK_LAUNCHED
	var _bus = _event_bus()
	if _bus:
		_bus.emit_event(BattleEventBus.GameEvent.ATTACK_LAUNCHED, {"attacker": attacker, "direction": ball_direction, "damage": ball_damage, "max_dist": max_flight_distance, "skills": injected_skills})

	# 标签修饰符应用到球属性（2026-09-19 快照化：领取快照后按快照计算，ball 不再直读 handler）
	ball_mods = _default_ball_mods()
	_boomerang_triggered = false
	_boomerang_return_dir = Vector2.ZERO
	if tag_effect_handler:
		ball_mods = tag_effect_handler.take_ball_mods_snapshot(attacker.get_instance_id() if attacker else -1)
		ball_damage = tag_effect_handler.get_modified_ball_damage(ball_damage, ball_mods)
		ball_speed = tag_effect_handler.get_modified_ball_speed(ball_speed, ball_mods)

		# 精准锁定：修正发球方向指向最近敌人
		var lockon_target: Node = ball_mods.get("lockon_target")
		if lockon_target and is_instance_valid(lockon_target) and not lockon_target.is_defeated:
			ball_direction = (lockon_target.global_position - from).normalized()

	# 波4 #23 球形态：视觉同步缩放（工单明确要求；判定半径在 _check_player_collision_distance 消费同一字段）
	if ball_visual:
		ball_visual.scale = Vector2.ONE * maxf(float(ball_mods.get("size_scale", 1.0)), 0.01)

	# 波6 #17 手动制导：玩家路径进手动态（AI 退化为直线直飞）
	if ball_mods.get("manual_steering", false) and attacker and attacker.is_player_controlled:
		begin_manual_steering()

	var attack_style := StyleBoxFlat.new()
	attack_style.bg_color = Color(1, 0.3, 0.3)
	attack_style.set_corner_radius_all(11)
	ball_visual.add_theme_stylebox_override("normal", attack_style)

	visible = true
	print("[Ball] 发球! 伤害:%.1f 速度:%.1f 距离:%.1f" % [ball_damage, ball_speed, max_flight_distance])

	# 发球时清除光环（能量已注入到球属性中）
	_clear_skill_aura()


func _get_tag_effect_handler() -> Node:
	var tree := get_tree()
	if tree:
		for node in tree.get_nodes_in_group("spirit_system"):
			if node.has_method("take_ball_mods_snapshot"):
				return node
		# 备用：遍历根节点
		for node in tree.root.get_children():
			var h = node.get("tag_effect_handler")
			if h != null:
				return h
	return null


## 球修饰符快照默认值（与 handler reset_ball_mods 同源；ball 侧兜底）
func _default_ball_mods() -> Dictionary:
	return {
		"dmg_mult": 1.0, "dmg_flat": 0.0,
		"speed_mult": 1.0, "speed_flat": 0.0,
		"range_mult": 1.0, "range_flat": 0.0,
		"penetrate": false, "armor": 0.0,
		"tracking_target": null, "tracking_turn_speed": 0.0,
		"boomerang": false, "boomerang_triggered": false,
		"boomerang_return_dir": Vector2.ZERO, "boomerang_dist": 0.0,
		"lock_straight": false, "spread_done": false,
		"aoe_radius": 0.0, "aoe_damage_pct": 0.5,
		"lockon_target": null,
		"bounce_max": 0, "bounce_speed_mult": 1.0,   # 波4 #15 反弹增强（0=无限）
		"sure_hit": false,                            # 波4 #22 必中
		"size_scale": 1.0,                            # 波4 #23 球形态（碰撞半径倍率）
		"hidden_from_enemies": false,                 # 波4 #7 球隐身
		"spread_count": 0, "spread_damage_ratio": 1.0, "spread_trigger_dist_pct": 0.6,  # 波6 #8 分裂
		"manual_steering": false,                     # 波6 #17 手动制导
		"carry_pull_speed": 0.0, "carry_max_duration": 0.0,  # 波6 #18 带人位移
	}


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
	ball_mods = _default_ball_mods()
	_boomerang_triggered = false
	_boomerang_return_dir = Vector2.ZERO
	if ball_visual:
		ball_visual.scale = Vector2.ONE  # 波4 #23：恢复原尺寸
	ball_z = 0.0
	ball_z_vel = 0.0
	bounce_count = 0
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
	"""获取元素对应的颜色（与 spirits.json 的 icon_color 保持一致）"""
	var colors: Dictionary = {
		"金刚": Color("#FFD700"),
		"大地": Color("#8B4513"),
		"雷火": Color("#FF4500"),
		"冰雪": Color("#87CEEB"),
		"草木": Color("#32CD32"),
		"梦幻": Color("#DA70D6"),
	}
	return colors.get(element, Color("#FFFF00"))


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


## 2026-09-20 P1-1：以下死路径已删除——
## _connect_skill_signals/_do_connect_skill_signals（订阅组内不存在的信号，静默不连）
## _on_spirit_skill_activated/_on_spirit_skill_cancelled（对应回调）
## _get_skill_data（仅被上述回调调用，连带孤儿；它也是 P2-2 记录的"每次调用即IO"点）
## 信号 skill_activated/skill_cancelled 真实属于 SkillStateManager（input_manager 创建持有），
## 未经修复的注入链不可达；球技能光环改由 player 侧主动通知（set_active_skill/cancel_active_skill）。


## ==================== 物理系统 ====================

## 技能接管判定（M0 球侧豁免）：技能定义轨迹的球暂时无视重力/弹跳
## 接管 = 弧线等非直行轨迹、追踪、回旋；穿透/精准锁定/直行保护仍是普通弹道球
## lob 高抛（M4）吃重力走抛物线+落地弹跳，不算接管
func _is_skill_controlled() -> bool:
	if trajectory_type == "lob":
		return false
	if trajectory_type != "straight":
		return true
	# 2026-09-19 快照化：读球私有快照（无追踪无回旋=普通弹道）
	if ball_mods.get("tracking_target") != null and not ball_mods.get("lock_straight", false):
		return true
	if ball_mods.get("boomerang", false) and not ball_mods.get("lock_straight", false):
		return true
	return false


## M4 高抛轨迹：launch() 后由技能/调用方调用——上抛初速+抛物线+落地弹跳
## 高飞段（z>62）越过站立球员头顶，需跳起拦截；落地转碰碰球
func set_lob_trajectory() -> void:
	trajectory_type = "lob"
	ball_z = maxf(ball_z, BALL_HEIGHT_CARRY)
	ball_z_vel = LOB_INITIAL_VZ


## z 轴重力积分 + 落地弹跳。只动 z，不改变水平规则（max_flight_distance 照旧），
## 水平飞行与球权流转与旧版完全一致。
## 解析式积分（非欧拉）：触地时刻与触地速度精确求解，e=1.0 时能量严格守恒（完全反弹不衰减）
func _step_ballistic_z(delta: float) -> void:
	if not use_ballistic_physics and trajectory_type != "lob":
		return
	var remaining: float = delta
	var guard: int = 0
	while remaining > 0.0 and guard < 8:  # guard: 一帧内最多弹跳8次（极小delta下防死循环）
		guard += 1
		var vz0: float = ball_z_vel
		var z0: float = ball_z
		# 抛物线 z(t)=z0+vz0·t-½g·t² 触地正根
		var t_land: float = (vz0 + sqrt(vz0 * vz0 + 2.0 * GRAVITY_Z * z0)) / GRAVITY_Z
		if t_land <= remaining:
			var vz_land: float = vz0 - GRAVITY_Z * t_land
			ball_z = 0.0
			# V1-3 首触地钩子：一次投球只发一次（E2 弹跳不重复）
			if not _first_land_emitted:
				_first_land_emitted = true
				ball_first_land.emit(global_position)
			var e: float = _get_effective_bounce_e()
			var vz_next: float = -vz_land * e
			if vz_next >= BOUNCE_SPEED_MIN:
				ball_z_vel = vz_next
				bounce_count += 1
				remaining -= t_land
			else:
				ball_z_vel = 0.0  # 弹跳耗尽→贴地滚动
				remaining = 0.0
		else:
			ball_z_vel = vz0 - GRAVITY_Z * remaining
			ball_z = z0 + vz0 * remaining - 0.5 * GRAVITY_Z * remaining * remaining
			remaining = 0.0


## 有效弹性 e：球天然弹性为基准，场地弹性系数为技能加成（叠加后夹在 0~1）
func _get_effective_bounce_e() -> float:
	var e: float = bounce_coefficient
	var fp: Node = get_parent().get_node_or_null("FieldPhysicsManager") if get_parent() else null
	if fp and fp.has_method("get_bounciness"):
		var field_e: float = fp.get_bounciness()
		if field_e > 0.0:
			e = clampf(e + field_e, 0.0, 1.0)
	return e


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
	
	注意：M1 弹道物理已接入——落地弹跳按本系数与场地弹性加成计算；
	设为 0 可完全禁弹（保留旧"无反弹"语义）
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

func _check_player_collision_distance() -> void:
	"""距离碰撞检测：补充 body_entered 可能漏检的情况
	命中距离 = 球半径(14) + 球员半径(28) + 球速帧移动距离
	E8 高速子步进：沿本帧移动方向细分采样，防一帧飞越目标（主人实测复现）
	"""
	if not is_active:
		return

	var delta_val: float = get_process_delta_time()
	var step_len: float = ball_speed * delta_val  # 本帧移动距离
	# 波4 #23 球形态：碰撞判定半径 ×size_scale（巨型雪球=2.0 易命中；视觉缩放=美术线消费）
	var size_scale: float = float(ball_mods.get("size_scale", 1.0))
	var detection_range: float = (42.0 + step_len) * size_scale

	var all_players := _get_all_players_array()
	var move_dir: Vector2 = ball_direction.normalized() if ball_direction.length_squared() > 0.001 else Vector2.ZERO
	# 高速子步进：球速>840(42px*60帧换算) 时按 42px 步长细分采样点（上限16子步）
	var substeps: int = 1
	if step_len > 42.0:
		substeps = mini(int(ceil(step_len / 42.0)), 16)

	for p in all_players:
		if not p or not is_instance_valid(p):
			continue
		if not p is CharacterBody2D:
			continue
		var pid: int = p.get_instance_id()
		if _hit_player_ids.has(pid):
			continue
		if p == attacker_player:
			continue
		if p.is_defeated:
			continue
		# M4 高度窗口：跳起的球员从球上方掠过不命中
		if not _can_hit_target_at(p):
			continue
		# 子步进采样：0=当前位，1..substeps=沿移动方向的中间/末端点
		for s in range(substeps + 1):
			var sample: Vector2 = global_position + move_dir * (step_len * float(s) / float(substeps))
			if sample.distance_to(p.global_position) <= detection_range:
				_on_body_entered(p)
				return

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
			# V1-2：通知盾实体"被撞一次"（uses 次数制盾在此扣次）
			if obs.has_method("on_ball_hit"):
				obs.on_ball_hit()
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
	# 波6 #8 子球：不回手，直接消散（命中伤害已在命中点结算）
	if is_clone:
		queue_free()
		return
	is_active = false
	_set_idle_visual()
	# V1-3 停球钩子（内场停止/耗尽路径；含首触地兜底）
	_emit_stop_hooks()
	if attacker_player and is_instance_valid(attacker_player):
		return_to_player(attacker_player)


## V1-3 停球钩子组：停球=球贴地，首触地未发时兜底补发（ball_land 类技能的最终保险）
func _emit_stop_hooks() -> void:
	if not _first_land_emitted:
		_first_land_emitted = true
		ball_first_land.emit(global_position)
	ball_stopped.emit(global_position)


func _get_all_players_array() -> Array:
	"""获取场上所有球员数组"""
	var all_players: Array = []
	if GameManager:
		var team_a = GameManager.get("team_a")
		var team_b = GameManager.get("team_b")
		if team_a:
			all_players.append_array(team_a)
		if team_b:
			all_players.append_array(team_b)
	# 兜底：名册为空（测试场景自行注册 "players" 组）时回退组遍历；生产两队必有值走不到
	if all_players.is_empty() and get_tree():
		all_players = get_tree().get_nodes_in_group("players")
	return all_players


## 波4 #7 球隐身（10 工单）：该球员是否看得见本球（施法者同队可见，敌方不可见；表现层消费同一接口）
func is_ball_visible_to(p: Node) -> bool:
	if not ball_mods.get("hidden_from_enemies", false):
		return true
	if attacker_player and is_instance_valid(attacker_player) and p is CharacterBody2D \
			and (p as CharacterBody2D).team == attacker_player.team:
		return true
	return false


## 波4 #7 球隐身（规划版接口名）：球是否处于隐身态（表现层消费）
func is_stealthed() -> bool:
	return ball_mods.get("hidden_from_enemies", false)


## 波5 #12：消费 zone 穿越信号——瞬时强化（快照 dmg/speed 乘区追加；zone 不直改球，皮影原则）
func _on_zone_ball_passed(_zone_type: int, mods: Dictionary) -> void:
	if not is_active:
		return
	var dmg_pct: float = float(mods.get("dmg_pct", 0.0))
	var speed_pct: float = float(mods.get("speed_pct", 0.0))
	if dmg_pct != 0.0:
		ball_damage *= (1.0 + dmg_pct)
	if speed_pct != 0.0:
		ball_speed *= (1.0 + speed_pct)
	print("[Ball] 穿越区域强化: 伤害%.1f 速度%.1f" % [ball_damage, ball_speed])


## ==================== 波6 高难收官（12 工单）====================

## #8 分裂：在当前位置扇形生成子球克隆（伤害×ratio；克隆 is_clone=true 不再分裂）
func _spawn_clones(count: int, damage_ratio: float) -> void:
	var spread_angle: float = deg_to_rad(25.0)
	var empty_skills: Array[Dictionary] = []
	for i in range(count):
		var clone := Area2D.new()
		clone.set_script(load("res://scripts/battle/ball.gd"))
		clone.name = "BallClone_%d_%d" % [get_instance_id(), i]
		var offset_dir: Vector2 = ball_direction.rotated(spread_angle * (i + 1.0) / (count + 1.0) * 2.0 - spread_angle)
		get_parent().add_child(clone)
		clone.is_clone = true
		clone.mother_ref = self
		clone.launch(global_position, offset_dir, ball_damage * damage_ratio, max_flight_distance - flight_distance, attacker_player, empty_skills)
	print("[Ball] 分裂! %d 个子球 (伤害×%.2f)" % [count, damage_ratio])


## #14 飞行中球操作：瞬时推进（伤害/速度乘区追加）
func boost_in_flight(mods: Dictionary) -> void:
	if not is_active:
		return
	ball_damage *= (1.0 + float(mods.get("dmg_pct", 0.0)))
	ball_speed *= (1.0 + float(mods.get("speed_pct", 0.0)))
	print("[Ball] 飞行推进: 伤害%.1f 速度%.1f" % [ball_damage, ball_speed])


## #14 拉回：球朝投掷者转向（次数由调用方扣减）
func recall_ball(_max_times: int = 1) -> void:
	if not is_active:
		return
	if attacker_player and is_instance_valid(attacker_player):
		ball_direction = (attacker_player.global_position - global_position).normalized()
		print("[Ball] 拉回! 朝投掷者转向")


## #17 手动制导：开启手动态（玩家路径；AI 的球 attacker.is_player_controlled=false 不进入=直线直飞）
func begin_manual_steering() -> void:
	if is_clone or not is_active:
		return
	if attacker_player and is_instance_valid(attacker_player) and not attacker_player.is_player_controlled:
		return  # AI 无操控，退化为直线直飞
	_manual_active = true
	_manual_time_left = float(ball_mods.get("manual_max_duration", 3.0))
	print("[Ball] 手动制导开启")


## #17 手动制导：外部（input_manager）每帧注入方向
func manual_steer(direction: Vector2) -> void:
	if _manual_active and direction.length_squared() > 0.001:
		ball_direction = direction.normalized()


## 项1 空格迁移（操控规划/05 §1 主人裁决）：贴地奔跑类=跳跃冲量 / 飞行类=上升增量
func steer_space_action(mode: String) -> void:
	if mode == "rise":
		ball_z = minf(ball_z + STEER_RISE_STEP, STEER_RISE_MAX)
	else:
		ball_z_vel = STEER_JUMP_VEL
		_steer_jump_airborne = true


## P0-2（2026-09-20）：AOE 目标筛选——数据源=权威名册；幻象维持"不吃 AOE"设计现状## （名册本无幻象，该过滤条为纯防御+设计意图声明）
## source 缺省时内部取 _get_all_players_array()；测试可注入名册数组做纯筛选断言
func _collect_aoe_targets(center_player: Node2D, enemy_team: String, radius: float, source: Array = []) -> Array:
	var targets: Array = []
	var candidates: Array = source if not source.is_empty() else _get_all_players_array()
	for p in candidates:
		if p == center_player:
			continue
		if not p is CharacterBody2D:
			continue
		if p.team != enemy_team:
			continue
		if p.is_defeated:
			continue
		# 隐身者不受AOE影响（看不到就不会被波及）
		if p.has_method("is_status_active") and p.is_status_active("stealthed"):
			continue
		# 幻象不受AOE影响（虚假目标，不计入范围伤害）
		if p.get("is_illusion") == true:
			continue
		if center_player.global_position.distance_to(p.global_position) <= radius:
			targets.append(p)
	return targets

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


## 获取 MatchPlayerStats 实例
func _get_match_stats() -> Node:
	var mps = get_node_or_null("/root/MatchPlayerStats")
	if mps:
		return mps
	var bm = get_parent()
	if bm and bm.has_node("MatchPlayerStats"):
		return bm.get_node("MatchPlayerStats")
	return null


## E4 攻击方元素（装备元灵 element）
func _attacker_element() -> String:
	if attacker_player and is_instance_valid(attacker_player):
		var sid = attacker_player.get("spirit_id")
		if sid == null:
			sid = ""
		if sid != "":
			var sd: Dictionary = DataManager.get_spirit_by_id(sid)
			return str(sd.get("element", ""))
	return ""

## E2 事件总线获取（group 免注入）
func _event_bus() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("battle_event_bus")
