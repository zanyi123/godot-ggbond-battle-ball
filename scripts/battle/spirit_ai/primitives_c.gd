class_name SpiritAIPrimitivesC
extends RefCounted
## 波C原语：球行为族（飞行行为+命中+范围）17标签。契约见 元灵技能AI规划/06_原语接口规约.md
## 波C扩展（看板Q8待批）：family=ball_flight|ball_hit|ball_range /
## 描述符新增 operation_mode（none=注入族AUTO / steer=OP_STEER / midfly=OP_MIDFLY）与
## op_policy（recall/boost）——均纯分类元数据，契约三函数不消费，仅供 ai_input_source.gd 分发
## 纪律：禁随机数流与不稳定标识（确定性骰子范式，02工单A）；感知一律走 ctx；缩进 Tab

const TABLE_PATH := "res://data/systems/spirit_ai/primitives_c.json"

## operation_mode 枚举（ai_input_source 分发键，Q8 ②）
const OPERATION_MODES: Array[String] = ["none", "steer", "midfly"]

## op_policy 枚举（midfly 时机策略，Q8 ③；steer/none 标签为空串）
const OP_POLICIES: Array[String] = ["", "recall", "boost"]

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
		push_error("[SpiritAIPrimitivesC] 原语表缺失或为空: %s（视同空表 fail-closed）" % TABLE_PATH)
		return {}
	_cached = _parse_descriptors(text)
	return _cached


## JSON 文本 → descriptors（容错层，供坏表单测；非字典/缺 descriptors 一律空表）
static func _parse_descriptors(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[SpiritAIPrimitivesC] 原语表 JSON 解析失败（视同空表 fail-closed）")
		return {}
	var descriptors: Variant = parsed.get("descriptors", {})
	if typeof(descriptors) != TYPE_DICTIONARY:
		push_error("[SpiritAIPrimitivesC] 原语表缺 descriptors 字典（视同空表 fail-closed）")
		return {}
	return descriptors


## 时机闸门。descriptor 里取 timing_gate 分发；ctx 由 manager 组装（键见 06§4.1，波C扩展键见 Q8）：
## ctx = { player, fov_ap, visible_enemies, stamina_ratio, energy_ratio,
##         has_energy_blocked_burst, threat_radius,
##         波C启用: ball_in_flight（ball_flight 操控族时机，manager 填充）}
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
			# 投前注入时机：持球且视野内有敌（注入族14标签主闸门）
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
			# 支援目标评分最低的队友体力比 < 0.35（评分由 manager 算好经 allies/ally_stamina_ratios 传入）
			var ratios: Variant = ctx.get("ally_stamina_ratios", ctx.get("allies", []))
			if typeof(ratios) != TYPE_ARRAY or (ratios as Array).is_empty():
				return {"ok": false, "bonus": 1.0}
			var lowest := INF
			for r in ratios as Array:
				lowest = minf(lowest, _ratio_of(r))
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
			# 操控族（in_flight_boost/recall）时机：本方飞行球在场；ctx.ball_in_flight 缺省 fail-closed
			return {"ok": bool(ctx.get("ball_in_flight", false)), "bonus": 1.0}
		"ally_cast_setup":
			return {"ok": bool(ctx.get("combo_setup_active", false)), "bonus": 1.0}
	return {"ok": false, "bonus": 1.0}


## 价值计算：value = clamp(params[value_param] × value_unit, value_min, value_cap)
## params 缺该键（或 value_param=none/空）→ 返回 value_min（不猜参数名；波B口径）
static func compute_value(descriptor: Dictionary, tag_params: Dictionary) -> float:
	var value_min := float(descriptor.get("value_min", 15.0))
	var value_cap := float(descriptor.get("value_cap", 90.0))
	var param_name := str(descriptor.get("value_param", ""))
	if param_name.is_empty() or param_name == "none" or not tag_params.has(param_name):
		return value_min
	var raw := float(tag_params.get(param_name, 0.0))
	return clampf(raw * float(descriptor.get("value_unit", 0.0)), value_min, value_cap)


## 本波 target_mode 静态读表（全部=ball，06§2.1 冻结枚举）；空缺回落 "none"
static func resolve_target_mode(descriptor: Dictionary, _sad: Dictionary) -> String:
	var mode := str(descriptor.get("target_mode", ""))
	return "none" if mode.is_empty() else mode


# ===== 私有工具（只消费 ctx 与其携带的节点引用，禁直连管理器原始感知） =====

## ctx.player 优先（契约允许 manager 未注入时的最低保底）
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
	for e in _get_visible_enemies(ctx):
		if bool(e.is_carrying_ball):
			return true
	return false


static func _nearest_enemy_distance(from: Vector2, enemies: Array) -> float:
	var nearest := -1.0
	for e in enemies:
		var d: float = from.distance_to(e.global_position)
		if nearest < 0.0 or d < nearest:
			nearest = d
	return nearest


## 体力比安全读取（Object.get 只收单参，与 Dictionary.get 不同；兼容数值/字典/对象条目）
static func _ratio_of(source: Variant) -> float:
	if source is float or source is int:
		return float(source)
	if source is Dictionary:
		return float(source.get("stamina_ratio", 1.0))
	if source is Object and is_instance_valid(source):
		var v = source.get("stamina_ratio")
		if v != null:
			return float(v)
	return 1.0
