class_name SpiritAIPrimitivesE
extends RefCounted
## 波E原语：长尾族（交互2/复制2/地形2/区域标注2/幻影2，共10标签）。契约见 元灵技能AI规划/06_原语接口规约.md
## 纪律：禁 randf/instance_id（骰子输入）/直连 ai_manager 感知数据（感知走 ctx）；缩进 Tab
## gate 判定与波A/B同构自包含（05§一 白名单分文件互斥设计，避免跨窗口类依赖）
## 波E增强：Q9 提案键 fail-closed 预实现（ctx 可选字段缺省一律 false，JSON 未引用无副作用，
## 规划窗口批准后 JSON 换键名即生效，无需再改本文件）：
##   "ally_skill_cast_recent" — 复制族理想时机：event_hooks 快照口报告近期有敌方技能释放
##   "ball_out_predicted"     — teleport 救球理想时机：M5 弹道预测球将出界（manager 供）

const TABLE_PATH := "res://data/systems/spirit_ai/primitives_e.json"

## 默认威胁半径（06 §三 self_threatened 判定用；manager 组装 ctx 时可覆盖）
const DEFAULT_THREAT_RADIUS := 200.0
## 强触发判定：self_threatened 且敌距离 < 该值 → bonus 1.25（两档制，禁更细）
const STRONG_THREAT_RADIUS := 100.0
## self_injured / ally_injured 阈值（06 §三）
const INJURED_RATIO := 0.35
## self_threatened 的体力低判定阈值（06 §三）
const LOW_STAMINA_RATIO := 0.4

static var _descriptors: Dictionary = {}
static var _loaded: bool = false


## 读表（进程内缓存一次；JSON 解析失败返回 {} 并 push_error，绝不崩溃）
static func get_descriptors() -> Dictionary:
	if _loaded:
		return _descriptors
	_descriptors = _load_table(TABLE_PATH)
	_loaded = true
	return _descriptors


## 内部读表（供套件对空表/坏 JSON 的不崩溃断言复用；路径参数化便于测试注入）
static func _load_table(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("SpiritAIPrimitivesE: 原语表不存在 " + path)
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("SpiritAIPrimitivesE: 原语表为空 " + path)
		return {}
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("SpiritAIPrimitivesE: 原语表 JSON 解析失败 " + path)
		return {}
	var raw: Dictionary = parsed
	var descs = raw.get("descriptors", {})
	if not descs is Dictionary:
		push_error("SpiritAIPrimitivesE: descriptors 字段缺失或非法 " + path)
		return {}
	return descs


## 时机闸门。ctx 由 manager 组装（06 §4.1 冻结字段；可选扩展字段见各 gate 注释）：
## ctx = {
##   "player": CharacterBody2D,          # 施法者
##   "fov_ap": Dictionary,                # 02工单感知口 get_ap_for_player 结果（可能为空=fail-closed）
##   "visible_enemies": Array,            # FOV 内敌人引用列表（manager 算好，原语不算感知）
##   "stamina_ratio": float,
##   "energy_ratio": float,
##   "has_energy_blocked_burst": bool,
##   "threat_radius": float,              # 默认 200.0
##   可选："allies" / "reaction_hot"（波B）/ "ball_in_flight"（操球）/ "combo_setup_active"（⑤协议）/
##         "ally_skill_cast_recent"（波E复制族，Q9）/ "ball_out_predicted"（波E救球，Q9）
##         ——缺省一律按 false/空 fail-closed
## 返回 {"ok": bool, "bonus": float}；未知 gate 键 → {"ok": false, "bonus": 1.0}（fail-closed）
static func timing_gate(descriptor: Dictionary, sad: Dictionary, ctx: Dictionary) -> Dictionary:
	var gate_key: String = str(descriptor.get("timing_gate", ""))
	var player = ctx.get("player", null)
	var visible_enemies: Array = ctx.get("visible_enemies", [])
	var stamina_ratio: float = float(ctx.get("stamina_ratio", 1.0))
	var threat_radius: float = float(ctx.get("threat_radius", DEFAULT_THREAT_RADIUS))
	var reaction_hot: bool = bool(ctx.get("reaction_hot", false))

	match gate_key:
		"always":
			return {"ok": true, "bonus": 1.0}
		"ball_hold":
			return {"ok": _player_holds_ball(player), "bonus": 1.0}
		"ball_hold_engage":
			var engaged: bool = _player_holds_ball(player) and not visible_enemies.is_empty()
			return {"ok": engaged, "bonus": 1.0}
		"enemy_visible":
			return {"ok": not visible_enemies.is_empty(), "bonus": 1.0}
		"enemy_carrying_visible":
			for enemy in visible_enemies:
				if is_instance_valid(enemy) and enemy.get("is_carrying_ball"):
					return {"ok": true, "bonus": 1.0}
			return {"ok": false, "bonus": 1.0}
		"self_threatened":
			var nearest_dist: float = _nearest_enemy_dist(ctx)
			var threatened: bool = nearest_dist < threat_radius or stamina_ratio < LOW_STAMINA_RATIO or reaction_hot
			if not threatened:
				return {"ok": false, "bonus": 1.0}
			var bonus: float = 1.25 if (nearest_dist < STRONG_THREAT_RADIUS or reaction_hot) else 1.0
			return {"ok": true, "bonus": bonus}
		"self_injured":
			return {"ok": stamina_ratio < INJURED_RATIO, "bonus": 1.0}
		"ally_injured":
			var allies: Array = ctx.get("allies", [])
			for ally in allies:
				if _ally_ratio(ally) < INJURED_RATIO:
					return {"ok": true, "bonus": 1.0}
			return {"ok": false, "bonus": 1.0}
		"calm_state":
			var calm: bool = not _player_holds_ball(player) \
					and visible_enemies.is_empty() and stamina_ratio > 0.5 and not reaction_hot
			return {"ok": calm, "bonus": 1.0}
		"pre_burst":
			return {"ok": bool(ctx.get("has_energy_blocked_burst", false)), "bonus": 1.0}
		"ball_flight":
			return {"ok": bool(ctx.get("ball_in_flight", false)), "bonus": 1.0}
		"ally_cast_setup":
			return {"ok": bool(ctx.get("combo_setup_active", false)), "bonus": 1.0}
		"ally_skill_cast_recent":
			# Q9 提案键：复制族理想时机（event_hooks 快照口供数；缺省 fail-closed）
			return {"ok": bool(ctx.get("ally_skill_cast_recent", false)), "bonus": 1.0}
		"ball_out_predicted":
			# Q9 提案键：teleport 救球（M5 弹道预测供数；缺省 fail-closed）
			return {"ok": bool(ctx.get("ball_out_predicted", false)), "bonus": 1.0}
		_:
			return {"ok": false, "bonus": 1.0}


## 价值计算：value = clamp(params[value_param] × value_unit, value_min, value_cap)
## params 缺该键 / 值非数值 → 返回 value_min（不猜参数名）
## value_param="none"（teleport/return/revert/clear 等引用型参数标签）恒回落 value_min
static func compute_value(descriptor: Dictionary, tag_params: Dictionary) -> float:
	var value_min: float = float(descriptor.get("value_min", 15.0))
	var value_param: String = str(descriptor.get("value_param", ""))
	if not tag_params.has(value_param):
		return value_min
	var raw_val = tag_params.get(value_param)
	if not (raw_val is float or raw_val is int):
		return value_min
	var value_unit: float = float(descriptor.get("value_unit", 0.0))
	var value_cap: float = float(descriptor.get("value_cap", 90.0))
	return clampf(float(raw_val) * value_unit, value_min, value_cap)


## 本波 target_mode 静态读表（场地类 JSON 占位 none，Q4 field_position 批后换表即生效）
static func resolve_target_mode(descriptor: Dictionary, sad: Dictionary) -> String:
	return str(descriptor.get("target_mode", "none"))


# ===== 私有工具（零感知直连，全部从 ctx 取）=====

static func _player_holds_ball(player) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	return bool(player.get("is_carrying_ball"))


## 最近可见敌距离；无敌可见返回 INF（ctx.visible_enemies 为 manager 的 FOV 过滤结果）
static func _nearest_enemy_dist(ctx: Dictionary) -> float:
	var caster = ctx.get("player", null)
	if caster == null or not is_instance_valid(caster):
		return INF
	var visible_enemies: Array = ctx.get("visible_enemies", [])
	var nearest: float = INF
	for enemy in visible_enemies:
		if is_instance_valid(enemy):
			nearest = minf(nearest, caster.position.distance_to(enemy.position))
	return nearest


## 队友体力比读取（兼容字典条目与球员对象条目；不可读返回 1.0=健康，fail-safe 不误触发支援）
static func _ally_ratio(ally) -> float:
	if ally is Dictionary:
		return float(ally.get("stamina_ratio", 1.0))
	if ally != null and is_instance_valid(ally):
		var ratio = ally.get("stamina_ratio")
		if ratio != null:
			return float(ratio)
		var max_st: float = float(ally.get("max_stamina", 0.0))
		if max_st > 0.0:
			return float(ally.get("stamina", 0.0)) / max_st
	return 1.0
