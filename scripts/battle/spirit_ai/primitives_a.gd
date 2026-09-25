class_name SpiritAIPrimitivesA
extends RefCounted
## 波A原语：纯增益/资源族（39标签）。契约见 元灵技能AI规划/06_原语接口规约.md
## 纪律：禁 randf/instance_id/直连 ai_manager 感知数据（感知走 ctx）；缩进 Tab

const TABLE_PATH := "res://data/systems/spirit_ai/primitives_a.json"

## 默认威胁半径（06 §三 self_threatened 判定用；manager 组装 ctx 时可覆盖）
const DEFAULT_THREAT_RADIUS := 200.0
## 强触发判定：self_threatened 且敌距离 < 该值 → bonus 1.25（两档制，禁更细）
const STRONG_THREAT_RADIUS := 100.0

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
		push_error("SpiritAIPrimitivesA: 原语表不存在 " + path)
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("SpiritAIPrimitivesA: 原语表为空 " + path)
		return {}
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("SpiritAIPrimitivesA: 原语表 JSON 解析失败 " + path)
		return {}
	var raw: Dictionary = parsed
	var descs = raw.get("descriptors", {})
	if not descs is Dictionary:
		push_error("SpiritAIPrimitivesA: descriptors 字段缺失或非法 " + path)
		return {}
	return descs


## 时机闸门。ctx 由 manager 组装（06 §4.1 冻结字段；可选扩展字段见各 gate 注释）：
## ctx = {
##   "player": CharacterBody2D,          # 施法者
##   "fov_ap": Dictionary,                # 02工单感知口 get_ap_for_player 结果（可能为空=fail-closed）
##   "visible_enemies": Array,            # FOV 内敌人引用列表（manager 算好，原语不算感知）
##   "stamina_ratio": float,
##   "energy_ratio": float,
##   "has_energy_blocked_burst": bool,    # pre_burst 用：manager 判断好
##   "threat_radius": float,              # 默认 200.0
##   可选："allies": Array（ally_injured 用）、"ball_in_flight": bool（ball_flight，操球窗口启用）、
##         "combo_setup_active": bool（ally_cast_setup，⑤协议启用）——缺省一律按 false/空 fail-closed
## 返回 {"ok": bool, "bonus": float}；未知 gate 键 → {"ok": false, "bonus": 1.0}（fail-closed）
static func timing_gate(descriptor: Dictionary, sad: Dictionary, ctx: Dictionary) -> Dictionary:
	var gate_key: String = str(descriptor.get("timing_gate", ""))
	var player = ctx.get("player", null)
	var visible_enemies: Array = ctx.get("visible_enemies", [])
	var stamina_ratio: float = float(ctx.get("stamina_ratio", 1.0))
	var threat_radius: float = float(ctx.get("threat_radius", DEFAULT_THREAT_RADIUS))

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
			var threatened: bool = nearest_dist < threat_radius or stamina_ratio < 0.4
			if not threatened:
				return {"ok": false, "bonus": 1.0}
			# 两档 bonus：强触发（敌贴脸 <100px）给 1.25，其余 1.0
			var bonus: float = 1.25 if nearest_dist < STRONG_THREAT_RADIUS else 1.0
			return {"ok": true, "bonus": bonus}
		"self_injured":
			return {"ok": stamina_ratio < 0.35, "bonus": 1.0}
		"ally_injured":
			# 支援目标评分最低的队友 stamina_ratio < 0.35；ctx.allies 由 manager 组装，缺省 fail-closed
			var allies: Array = ctx.get("allies", [])
			for ally in allies:
				if _ratio_of(ally) < 0.35:
					return {"ok": true, "bonus": 1.0}
			return {"ok": false, "bonus": 1.0}
		"calm_state":
			var calm: bool = not _player_holds_ball(player) \
					and visible_enemies.is_empty() and stamina_ratio > 0.5
			return {"ok": calm, "bonus": 1.0}
		"pre_burst":
			# 资源时机：自己最高 base_value 的技能当前被能量/冷却卡住（manager 判好）
			return {"ok": bool(ctx.get("has_energy_blocked_burst", false)), "bonus": 1.0}
		"ball_flight":
			# 本波不用，预留给操球窗口；ctx.ball_in_flight 缺省 fail-closed
			return {"ok": bool(ctx.get("ball_in_flight", false)), "bonus": 1.0}
		"ally_cast_setup":
			# 本波不用，预留给⑤协议；ctx.combo_setup_active 缺省 fail-closed
			return {"ok": bool(ctx.get("combo_setup_active", false)), "bonus": 1.0}
		_:
			# 未知 gate 键 / 空 descriptor：fail-closed
			return {"ok": false, "bonus": 1.0}


## 价值计算：value = clamp(params[value_param] × value_unit, value_min, value_cap)
## params 缺该键 → 返回 value_min（不猜参数名）
static func compute_value(descriptor: Dictionary, tag_params: Dictionary) -> float:
	var value_min: float = float(descriptor.get("value_min", 15.0))
	var value_param: String = str(descriptor.get("value_param", ""))
	if not tag_params.has(value_param):
		return value_min
	var value_unit: float = float(descriptor.get("value_unit", 0.0))
	var value_cap: float = float(descriptor.get("value_cap", 90.0))
	var raw: float = float(tag_params.get(value_param, 0.0))
	return clampf(raw * value_unit, value_min, value_cap)


## 本波无动态目标逻辑，target_mode 静态读表（预留动态化签名，后续波覆写）
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


## 安全读 stamina_ratio：Object.get() 只收 1 参（与 Dictionary.get 不同），属性缺失/来源非法一律 1.0
static func _ratio_of(source) -> float:
	if source is Dictionary:
		return float(source.get("stamina_ratio", 1.0))
	if source is Object and is_instance_valid(source):
		var v = source.get("stamina_ratio")
		if v != null:
			return float(v)
	return 1.0
