class_name SpiritAIPrimitivesD
extends RefCounted
## 波D原语：场地族（区域+障碍）10标签位置原语。契约见 元灵技能AI规划/06_原语接口规约.md
## 波D扩展（看板Q4待批）：target_mode=field_position / family=field_area|field_obstacle /
## 描述符新增 position_intent 字段（供 select_field_position 分发，契约三函数不消费）
## 纪律：禁随机数流与不稳定标识（确定性骰子范式，02工单A）；感知一律走 ctx；缩进 Tab

const TABLE_PATH := "res://data/systems/spirit_ai/primitives_d.json"

## position_intent 枚举（select_field_position 分发键，Q4 ③）
const POSITION_INTENTS: Array[String] = [
	"none", "goal_ball_line", "enemy_carrier_path", "enemy_cluster",
	"shoot_line_block", "advance_lane", "defensive_anchor",
]

## 12 个时机闸门键（06§三冻结，各波共用）
const GATE_KEYS: Array[String] = [
	"always", "ball_hold", "ball_hold_engage", "enemy_visible",
	"enemy_carrying_visible", "self_threatened", "self_injured", "ally_injured",
	"calm_state", "pre_burst", "ball_flight", "ally_cast_setup",
]

static var _cached: Dictionary = {}


## 读表（进程内缓存一次；JSON 解析失败返回 {} 并 push_error，绝不崩溃）
static func get_descriptors() -> Dictionary:
	if not _cached.is_empty():
		return _cached
	var text := FileAccess.get_file_as_string(TABLE_PATH)
	if text.is_empty():
		push_error("[SpiritAIPrimitivesD] 原语表缺失或为空: %s（视同空表 fail-closed）" % TABLE_PATH)
		return {}
	_cached = _parse_descriptors(text)
	return _cached


## JSON 文本 → descriptors（容错层，供坏表单测；非字典/缺 descriptors 一律空表）
static func _parse_descriptors(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[SpiritAIPrimitivesD] 原语表 JSON 解析失败（视同空表 fail-closed）")
		return {}
	var descriptors: Variant = parsed.get("descriptors", {})
	if typeof(descriptors) != TYPE_DICTIONARY:
		push_error("[SpiritAIPrimitivesD] 原语表缺 descriptors 字典（视同空表 fail-closed）")
		return {}
	return descriptors


## 时机闸门。descriptor 里取 timing_gate 分发；ctx 由 manager 组装（键见 06§4.1，波D扩展键见 Q5）：
## ctx = { player, fov_ap, visible_enemies, stamina_ratio, energy_ratio,
##         has_energy_blocked_burst, threat_radius,
##         波D扩展: ball_position/own_goal/enemy_goal/enemy_carrier/enemy_carrier_visible/
##                  allies/ally_stamina_ratios/ball_in_flight/combo_setup_active }
## 返回 {"ok": bool, "bonus": float}；未知 gate 键 → {"ok": false, "bonus": 1.0}（fail-closed）
static func timing_gate(descriptor: Dictionary, _sad: Dictionary, ctx: Dictionary) -> Dictionary:
	var gate := str(descriptor.get("timing_gate", ""))
	if not GATE_KEYS.has(gate):
		return {"ok": false, "bonus": 1.0}
	match gate:
		"always":
			return {"ok": true, "bonus": 1.0}
		"ball_hold":
			var p_hold: Variant = _get_player(ctx)
			if p_hold == null:
				return {"ok": false, "bonus": 1.0}
			return {"ok": bool(p_hold.is_carrying_ball), "bonus": 1.0}
		"ball_hold_engage":
			var p_engage: Variant = _get_player(ctx)
			if p_engage == null:
				return {"ok": false, "bonus": 1.0}
			var engaged: bool = bool(p_engage.is_carrying_ball) and not _get_visible_enemies(ctx).is_empty()
			return {"ok": engaged, "bonus": 1.0}
		"enemy_visible":
			return {"ok": not _get_visible_enemies(ctx).is_empty(), "bonus": 1.0}
		"enemy_carrying_visible":
			return {"ok": _has_visible_carrier(ctx), "bonus": 1.0}
		"self_threatened":
			# 视野内敌距 < threat_radius（默认200px）或体力比 < 0.4；强触发（敌距<100px）bonus=1.25
			var p_threat: Variant = _get_player(ctx)
			if p_threat == null:
				return {"ok": false, "bonus": 1.0}
			var threat_radius := float(ctx.get("threat_radius", 200.0))
			var nearest := _nearest_enemy_distance(p_threat.global_position, _get_visible_enemies(ctx))
			var threatened := (nearest >= 0.0 and nearest < threat_radius) or float(ctx.get("stamina_ratio", 1.0)) < 0.4
			var bonus := 1.25 if (nearest >= 0.0 and nearest < 100.0) else 1.0
			return {"ok": threatened, "bonus": bonus}
		"self_injured":
			return {"ok": float(ctx.get("stamina_ratio", 1.0)) < 0.35, "bonus": 1.0}
		"ally_injured":
			# 支援目标评分最低的队友体力比 < 0.35（评分由 manager 算好经 allies 传入，本层只看体力）
			var ratios: Variant = ctx.get("ally_stamina_ratios", [])
			if typeof(ratios) != TYPE_ARRAY or (ratios as Array).is_empty():
				return {"ok": false, "bonus": 1.0}
			var lowest := INF
			for r in ratios as Array:
				lowest = minf(lowest, float(r))
			return {"ok": lowest < 0.35, "bonus": 1.0}
		"calm_state":
			var p_calm: Variant = _get_player(ctx)
			if p_calm == null:
				return {"ok": false, "bonus": 1.0}
			var calm: bool = not bool(p_calm.is_carrying_ball) \
					and _get_visible_enemies(ctx).is_empty() \
					and float(ctx.get("stamina_ratio", 1.0)) > 0.5
			return {"ok": calm, "bonus": 1.0}
		"pre_burst":
			return {"ok": bool(ctx.get("has_energy_blocked_burst", false)), "bonus": 1.0}
		"ball_flight":
			return {"ok": bool(ctx.get("ball_in_flight", false)), "bonus": 1.0}
		"ally_cast_setup":
			return {"ok": bool(ctx.get("combo_setup_active", false)), "bonus": 1.0}
	return {"ok": false, "bonus": 1.0}


## 价值计算：value = clamp(params[value_param] × value_unit, value_min, value_cap)
## params 缺该键（或 value_param=none/空）→ 返回 value_min（不猜参数名）
static func compute_value(descriptor: Dictionary, tag_params: Dictionary) -> float:
	var value_min := float(descriptor.get("value_min", 15.0))
	var value_cap := float(descriptor.get("value_cap", 90.0))
	var param_name := str(descriptor.get("value_param", ""))
	if param_name.is_empty() or param_name == "none" or not tag_params.has(param_name):
		return value_min
	var raw := float(tag_params.get(param_name, 0.0))
	return clampf(raw * float(descriptor.get("value_unit", 0.0)), value_min, value_cap)


## 本波 target_mode 静态读表（含 Q4 扩展枚举 field_position）；空缺回落 "none"
static func resolve_target_mode(descriptor: Dictionary, _sad: Dictionary) -> String:
	var mode := str(descriptor.get("target_mode", ""))
	return "none" if mode.is_empty() else mode


## 波D扩展：场地位置选择原语（Q4 ③分发 + Q5 ctx 扩展）。
## 把 manager 现有 _select_wall/_select_aoe/_select_area 三雏形参数化精化（不推倒重来），
## 缺 ctx 键一律 fail-closed 回落施法者自站位；全程确定性（无随机、平局取遍历序首个）。
static func select_field_position(descriptor: Dictionary, sad: Dictionary, ctx: Dictionary) -> Vector2:
	var p: Variant = _get_player(ctx)
	if p == null:
		p = sad.get("player")
	if p == null or not is_instance_valid(p):
		return Vector2.ZERO
	var self_pos: Vector2 = p.global_position
	var intent := str(descriptor.get("position_intent", "none"))
	if not POSITION_INTENTS.has(intent):
		return self_pos
	var ball_pos: Variant = ctx.get("ball_position")
	var own_goal: Variant = ctx.get("own_goal")
	var enemy_goal: Variant = ctx.get("enemy_goal")
	var enemies := _get_visible_enemies(ctx)

	match intent:
		"goal_ball_line":
			# 精化自 _select_wall_position 防守支：球门-球连线方向，0.6 系数上限 80
			if typeof(ball_pos) != TYPE_VECTOR2 or typeof(own_goal) != TYPE_VECTOR2:
				return self_pos
			var to_ball: Vector2 = ball_pos - own_goal
			if to_ball.length() < 1.0:
				return self_pos
			return own_goal + to_ball.normalized() * minf(to_ball.length() * 0.6, 80.0)
		"enemy_carrier_path":
			# 精化自 _select_wall_position 进攻支：球门→敌持球者连线，0.4 系数上限 60（07§③：drain_wall=敌持球路径）
			var carrier: Variant = _pick_carrier(ctx, enemies)
			if carrier == null or typeof(own_goal) != TYPE_VECTOR2:
				return self_pos
			var to_carrier: Vector2 = carrier.global_position - own_goal
			if to_carrier.length() < 1.0:
				return self_pos
			return own_goal + to_carrier.normalized() * minf(to_carrier.length() * 0.4, 60.0)
		"enemy_cluster":
			# 精化自 _select_aoe_position：defense=最近敌，其余=最残血敌（按描述符 intent 分档）
			var target_enemy: Variant = _pick_aoe_enemy(str(descriptor.get("intent", "")), self_pos, enemies)
			return target_enemy.global_position if target_enemy != null else self_pos
		"shoot_line_block":
			# 新增语义（07§③：vision_block=挡射手视线）：球门→持球敌（无则最近敌）连线中段
			var shooter: Variant = _pick_carrier(ctx, enemies)
			if shooter == null:
				shooter = _pick_closest_enemy(self_pos, enemies)
			if shooter == null or typeof(own_goal) != TYPE_VECTOR2:
				return self_pos
			var to_shooter: Vector2 = shooter.global_position - own_goal
			if to_shooter.length() < 1.0:
				return self_pos
			return own_goal + to_shooter.normalized() * minf(to_shooter.length() * 0.5, 100.0)
		"advance_lane":
			# 精化自 _select_wall_position 进攻无持球者支：自位朝敌门方向铺区
			if typeof(enemy_goal) != TYPE_VECTOR2:
				return self_pos
			var to_goal: Vector2 = enemy_goal - self_pos
			if to_goal.length() < 1.0:
				return self_pos
			return self_pos + to_goal.normalized() * 60.0
		"defensive_anchor":
			# 精化自 _select_area_position 防守支：己方球门前锚点
			if typeof(own_goal) != TYPE_VECTOR2:
				return self_pos
			return own_goal + Vector2(0, 20)
	return self_pos


# ===== 私有工具（只消费 ctx 与其携带的节点引用，禁直连管理器原始感知） =====

## ctx.player 优先，sad.player 兜底（契约允许 manager 未注入时的最低保底）
static func _get_player(ctx: Dictionary) -> Variant:
	var p: Variant = ctx.get("player")
	if p != null and is_instance_valid(p):
		return p
	return null


static func _get_visible_enemies(ctx: Dictionary) -> Array:
	var enemies: Variant = ctx.get("visible_enemies", [])
	if typeof(enemies) != TYPE_ARRAY:
		return []
	var valid: Array = []
	for e in enemies as Array:
		if e != null and is_instance_valid(e):
			valid.append(e)
	return valid


## 敌持球者可见判定：ctx.enemy_carrier_visible 优先（manager 单口提供），
## 否则扫 visible_enemies 的 is_carrying_ball 节点属性（fail-closed=无）
static func _has_visible_carrier(ctx: Dictionary) -> bool:
	if ctx.has("enemy_carrier_visible"):
		return bool(ctx.get("enemy_carrier_visible"))
	return _pick_carrier(ctx, _get_visible_enemies(ctx)) != null


## 取敌持球者：ctx.enemy_carrier 优先，其次扫 visible_enemies；平局取遍历序首个
static func _pick_carrier(ctx: Dictionary, enemies: Array) -> Variant:
	var explicit_carrier: Variant = ctx.get("enemy_carrier")
	if explicit_carrier != null and is_instance_valid(explicit_carrier):
		return explicit_carrier
	for e in enemies:
		if bool(e.is_carrying_ball):
			return e
	return null


static func _nearest_enemy_distance(from: Vector2, enemies: Array) -> float:
	var nearest := -1.0
	for e in enemies:
		var d: float = from.distance_to(e.global_position)
		if nearest < 0.0 or d < nearest:
			nearest = d
	return nearest


static func _pick_closest_enemy(from: Vector2, enemies: Array) -> Variant:
	var best: Variant = null
	var best_d := INF
	for e in enemies:
		var d: float = from.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


## aoe 选敌（精化 _select_aoe_position）：defense=最近敌，其余=体力比最低敌
static func _pick_aoe_enemy(intent: String, from: Vector2, enemies: Array) -> Variant:
	if enemies.is_empty():
		return null
	if intent == "defense":
		return _pick_closest_enemy(from, enemies)
	var best: Variant = null
	var best_ratio := INF
	for e in enemies:
		var ratio := float(e.stamina) / float(maxf(float(e.max_stamina), 1.0))
		if ratio < best_ratio:
			best_ratio = ratio
			best = e
	return best
