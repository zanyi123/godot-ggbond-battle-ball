class_name SpiritAIInputSource
extends RefCounted
## 波C AI虚拟操作者（03主题③方案a定案）：AI 产生与玩家等价的操作意图（方向/确认时机），
## 经 skill_state_manager 同一套激活状态机推进——禁旁路直调技能释放入口。
## 职责边界：本文件=意图生成器+应用器（操球窗口交付）；接入技能AI决策管理器归集成窗口
## 接线工单（接线前生产路径零调用，主游戏行为=现状）。
## 纪律：禁随机流/不稳定标识/直连决策管理器感知数据（一律 ctx）；操作时机用决策周期
## 计数（02工单骰子范式），禁墙钟；缩进 Tab。

## 同键再按最小间隔（决策周期数）：0.5s/周期 × 2 = 1.0s > 300ms 双击窗，
## 防操控族高频再按误触发状态机双击自动释放语义（确定性节流，无状态）
const PRESS_COOLDOWN_CYCLES := 2

## operation_mode 合法词表（与 primitives_c.gd 的 OPERATION_MODES 保持一致，套件断言两表恒同；
## 本地副本避免跨文件 class_name 引用——新脚本类名未进全局缓存时按名引用会解析失败）
const OPERATION_MODES: Array[String] = ["none", "steer", "midfly"]

## recall 时机常量（04矩阵波C行"操作余量"判定，保守取值可调）
const RECALL_FAR_DISTANCE := 350.0   # 球离投掷者超过此距离 → 回收保球权
const RECALL_ENEMY_NEAR_RADIUS := 120.0  # 敌距球小于此半径 → 回收防截

## 生成操控族操作意图（激活期每决策周期调用；注入族/未知一律 none=AUTO 语义零操作）
## ctx = {
##   "player": CharacterBody2D,      # 施法者（AI 球员）
##   "ball_position": Vector2,       # 本方飞行球位置（操控族必需，缺省 fail-closed）
##   "ball_velocity": Vector2,       # 球速度向量（boost 朝向判定用）
##   "enemy_goal": Vector2,          # 敌方球门（steer 进攻向/boost 朝向优先源）
##   "visible_enemies": Array,       # FOV 内敌人引用列表（manager 算好，禁自算感知）
## }
## 返回 {"op": "none"|"steer"|"midfly", "aim_direction": Vector2,
##       "should_press": bool, "reason": String}
static func generate_operation_intent(descriptor: Dictionary, sad: Dictionary, ctx: Dictionary) -> Dictionary:
	var none_intent: Dictionary = {"op": "none", "aim_direction": Vector2.ZERO, "should_press": false, "reason": ""}
	if descriptor.is_empty():
		none_intent["reason"] = "empty_descriptor"
		return none_intent
	var mode := str(descriptor.get("operation_mode", "none"))
	if not OPERATION_MODES.has(mode):
		none_intent["reason"] = "unknown_mode"
		return none_intent
	match mode:
		"none":
			# 注入族：投前一次性注入，AUTO 直调语义（现状保留），激活期零操作
			none_intent["reason"] = "inject_auto"
			return none_intent
		"steer":
			# OP_STEER 激活窗：AI 转向意图=玩家鼠标等价物
			return {"op": "steer", "aim_direction": _compute_steer_aim(ctx), "should_press": false, "reason": "steer_window"}
		"midfly":
			# OP_MIDFLY 飞行中干预：同键再按（公开入口），时机策略按 op_policy 分发
			return _compute_midfly_intent(descriptor, sad, ctx, none_intent)
	none_intent["reason"] = "unreachable_mode"
	return none_intent


## 应用操作意图：把生成意图经 skill_state_manager 公开入口推进（同一激活状态机）。
## state_manager 用松类型+has_method 守卫（fail-closed：旧状态机无 AI 口时静默不操作）。
## slot：操控族技能槽位（midfly 再按需定位 RELEASING 态技能，由接线方传入；steer 不用）
## 返回是否产生了实际操作。
static func apply_operation(intent: Dictionary, state_manager: Variant, player_id: int, caster: Node, slot: int = -1) -> bool:
	if intent.is_empty() or caster == null or not is_instance_valid(caster):
		return false
	var op := str(intent.get("op", "none"))
	match op:
		"steer":
			var aim: Vector2 = intent.get("aim_direction", Vector2.ZERO)
			if aim == Vector2.ZERO:
				return false  # 零向量=不干预（球走直线，registry：AI路径退化为直线）
			# 球侧消费口与条件同 input_manager.inject_steer_to_ball（玩家等价路径）
			var ball = caster.get("ball_ref")
			if ball == null or not is_instance_valid(ball):
				return false
			if not bool(ball.get("is_active")) or not bool(ball.get("_manual_active")):
				return false
			if not ball.has_method("manual_steer"):
				return false
			if state_manager != null and state_manager.has_method("set_ai_aim"):
				state_manager.set_ai_aim(player_id, aim)
			ball.manual_steer(aim)
			return true
		"midfly":
			if not bool(intent.get("should_press", false)):
				return false
			if state_manager == null or slot < 0:
				return false
			if not state_manager.has_method("on_skill_key_pressed"):
				return false
			# RELEASING 态同键再按 → 状态机 _trigger_midfly（拉回/推进，公开入口非旁路）
			return bool(state_manager.on_skill_key_pressed(player_id, slot))
	return false


## 登记/注销 AI 输入源（接线口：集成窗口经此挂接；旧状态机无此方法时 fail-closed 返回 false）
static func attach(state_manager: Variant, player_id: int, caster: Node) -> bool:
	if state_manager == null or not state_manager.has_method("register_ai_input_source"):
		return false
	state_manager.register_ai_input_source(player_id, caster)
	return true


static func detach(state_manager: Variant, player_id: int) -> void:
	if state_manager != null and state_manager.has_method("clear_ai_input_source"):
		state_manager.clear_ai_input_source(player_id)


# ===== 私有工具（零感知直连，全部从 ctx 取；平局取遍历序首个=确定性） =====

## steer 瞄准优先级：敌门方向 > 最近敌（拦截向） > 保持当前航向 > 零向量（不干预）
static func _compute_steer_aim(ctx: Dictionary) -> Vector2:
	var ball_pos: Variant = ctx.get("ball_position")
	if typeof(ball_pos) != TYPE_VECTOR2:
		return Vector2.ZERO
	var enemy_goal: Variant = ctx.get("enemy_goal")
	if typeof(enemy_goal) == TYPE_VECTOR2:
		var to_goal: Vector2 = enemy_goal - ball_pos
		if to_goal.length_squared() > 1.0:
			return to_goal.normalized()
	var enemies: Array = _valid_enemies(ctx)
	if not enemies.is_empty():
		var nearest: Node2D = _nearest_node_to(ball_pos, enemies)
		if nearest != null:
			var to_enemy: Vector2 = nearest.global_position - ball_pos
			if to_enemy.length_squared() > 1.0:
				return to_enemy.normalized()
	var velocity: Variant = ctx.get("ball_velocity")
	if typeof(velocity) == TYPE_VECTOR2 and (velocity as Vector2).length_squared() > 1.0:
		return (velocity as Vector2).normalized()
	return Vector2.ZERO


## midfly 时机策略（Q8 ③ op_policy 分发；确定性+周期节流）
static func _compute_midfly_intent(descriptor: Dictionary, sad: Dictionary, ctx: Dictionary, none_intent: Dictionary) -> Dictionary:
	# 周期节流：exec_count 非间隔倍点不按（1.0s 间隔>双击窗，确定性无状态）
	var cycle := int(sad.get("skill_exec_count", 0))
	if cycle % PRESS_COOLDOWN_CYCLES != 0:
		none_intent["reason"] = "cadence_hold"
		return none_intent
	var policy := str(descriptor.get("op_policy", ""))
	var ball_pos: Variant = ctx.get("ball_position")
	if typeof(ball_pos) != TYPE_VECTOR2:
		none_intent["reason"] = "no_ball_ctx"
		return none_intent
	var player: Variant = ctx.get("player")
	if player == null or not is_instance_valid(player):
		none_intent["reason"] = "no_player_ctx"
		return none_intent
	var enemies: Array = _valid_enemies(ctx)
	match policy:
		"recall":
			# 回收时机=球远离投掷者 或 敌近球（防截保球权）
			var ball_dist: float = (ball_pos as Vector2).distance_to(player.global_position)
			if ball_dist > RECALL_FAR_DISTANCE:
				return {"op": "midfly", "aim_direction": Vector2.ZERO, "should_press": true, "reason": "ball_far"}
			for e in enemies:
				if (e as Node2D).global_position.distance_to(ball_pos) < RECALL_ENEMY_NEAR_RADIUS:
					return {"op": "midfly", "aim_direction": Vector2.ZERO, "should_press": true, "reason": "enemy_near_ball"}
			none_intent["reason"] = "recall_hold"
			return none_intent
		"boost":
			# 推进时机=球正朝敌门（无门信息则朝最近敌）飞行的进攻窗
			var velocity: Variant = ctx.get("ball_velocity")
			if typeof(velocity) != TYPE_VECTOR2:
				none_intent["reason"] = "no_velocity_ctx"
				return none_intent
			var vel: Vector2 = velocity
			if vel.length_squared() < 1.0:
				none_intent["reason"] = "ball_stalled"
				return none_intent
			var enemy_goal: Variant = ctx.get("enemy_goal")
			if typeof(enemy_goal) == TYPE_VECTOR2 and (enemy_goal - ball_pos).dot(vel) > 0.0:
				return {"op": "midfly", "aim_direction": Vector2.ZERO, "should_press": true, "reason": "toward_goal"}
			if not enemies.is_empty():
				var nearest: Node2D = _nearest_node_to(ball_pos, enemies)
				if nearest != null and (nearest.global_position - ball_pos).dot(vel) > 0.0:
					return {"op": "midfly", "aim_direction": Vector2.ZERO, "should_press": true, "reason": "toward_enemy"}
			none_intent["reason"] = "boost_hold"
			return none_intent
	none_intent["reason"] = "unknown_policy"
	return none_intent


static func _valid_enemies(ctx: Dictionary) -> Array:
	var enemies: Variant = ctx.get("visible_enemies", [])
	if typeof(enemies) != TYPE_ARRAY:
		return []
	var valid: Array = []
	for e in enemies as Array:
		if e != null and is_instance_valid(e) and e is Node2D:
			valid.append(e)
	return valid


static func _nearest_node_to(from: Vector2, nodes: Array) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for n in nodes:
		var d: float = from.distance_to((n as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = n
	return best
