extends Node
## handler/base_route.gd —— 基座：共享成员状态 + 球修饰符兼容接口 + 通用工具（13 拆分步骤1）
## extends 链：base_route ← ball_route ← player_route ← field_route ← spirit_tag_effect_handler(facade)
## 全部状态/方法在同一实例上解析（继承链拼接），对外类名与行为与拆分前 100% 等价。

signal effect_applied(tag_id: String, effect_data: Dictionary)
signal effect_finished(tag_id: String, effect_data: Dictionary)

# 波5/波6 pending 状态（声明在基座，供各层 route 引用）
var _pending_zone_spawns: Array[Dictionary] = []  # [{zone_type, zone_params, spawn_at, expires_at}]
var _ball_hooks_connected: bool = false
var _pending_in_flight: Dictionary = {}
var _in_flight_hooks_connected: bool = false

var battle_manager: Node
var ball_node: Node
var field_node: Node
var players: Array[Node] = []

# 活跃效果堆栈 {effect_uuid: {tag_id, params, duration, remaining, on_tick, on_expire}}
var _active_effects: Dictionary = {}
var _effect_counter: int = 0

# ==================== 优先级队列 ====================
# 多标签并发时(间隔<0.1s)按优先级排序执行,让比赛状态更真实
# 详见 docs/tag_priority.md

## 标签优先级字典: tag_id → 优先级数字(越小越先执行)
var _tag_priority: Dictionary = {}

## 待执行队列: [{tag_id, params, caster_id, priority}]
var _pending_tags: Array = []

## 累积窗口计时器(秒)
var _flush_timer: float = 0.0

## 窗口时长(秒): 多个标签在此时间内到达会排队
const FLUSH_WINDOW: float = 0.1

## 是否启用优先级队列(测试平台可关闭)
var priority_queue_enabled: bool = true

# 球的临时修饰符准备区（2026-09-19 Step2：按投球者隔离+有效期，修全局串味/覆盖/无期限）
# 每个 caster 一张纸；写入带 expires_at（比赛时钟，无 duration=投球前不过期）；投球取走即清
var _ball_mods_by_caster: Dictionary = {}   # {caster_id: mods_dict}
var _last_ball_caster: int = -1             # 最近写入者（兼容旧 getter 视图）
var _match_clock: float = 0.0               # 比赛时钟（_process 累计，time_scale/暂停自动同步）

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

## 取/建该施法者的修饰符准备区
func _ensure_ball_mods(caster_id: int) -> Dictionary:
	if not _ball_mods_by_caster.has(caster_id):
		_ball_mods_by_caster[caster_id] = _default_ball_mods()
	_last_ball_caster = caster_id
	return _ball_mods_by_caster[caster_id]

## 标记字段有效期（duration<=0 = 投球前不过期）
func _mark_expiry(mods: Dictionary, fields: Array, duration: float) -> void:
	if duration <= 0.0:
		return
	var expires: Dictionary = mods.get("_expires", {})
	for f in fields:
		expires[f] = _match_clock + duration
	mods["_expires"] = expires

## ==================== 球修饰符接口（供 ball.gd 调用）====================

## 兼容全清（测试面板用）；生产路径请用 reset_ball_mods_for（按 caster 清）
func reset_ball_mods() -> void:
	_ball_mods_by_caster.clear()
	_last_ball_caster = -1

## 清指定施法者的准备区（trigger._fire_skill 开头调用，不再全清别人的）
func reset_ball_mods_for(caster_id: int) -> void:
	_ball_mods_by_caster.erase(caster_id)

## 2026-09-19 Step2：取该投球者的快照——过期字段回落默认值，取走即清该准备区
func take_ball_mods_snapshot(caster_id: int) -> Dictionary:
	var mods: Dictionary = _ball_mods_by_caster.get(caster_id, {})
	_ball_mods_by_caster.erase(caster_id)
	var snap: Dictionary = _default_ball_mods()
	if not mods.is_empty():
		snap.merge(mods, true)
		var expires: Dictionary = mods.get("_expires", {})
		var fresh: Dictionary = _default_ball_mods()
		for f in expires:
			if _match_clock > float(expires[f]):
				snap[f] = fresh.get(f)
	return snap

## 兼容视图：最近活跃 caster 的准备区（过期字段回落）；供旧 getter / AI / 测试面板读取
func _view_ball_mods() -> Dictionary:
	var mods: Dictionary = _ball_mods_by_caster.get(_last_ball_caster, {})
	var snap: Dictionary = _default_ball_mods()
	if not mods.is_empty():
		snap.merge(mods, true)
		var expires: Dictionary = mods.get("_expires", {})
		var fresh: Dictionary = _default_ball_mods()
		for f in expires:
			if _match_clock > float(expires[f]):
				snap[f] = fresh.get(f)
		snap.erase("_expires")
	return snap

## 获取修饰后的球伤害（mods 缺省时读兼容视图；ball 传自己的快照）
func get_modified_ball_damage(base_damage: float, mods: Dictionary = {}) -> float:
	var m: Dictionary = mods if not mods.is_empty() else _view_ball_mods()
	var result: float = (base_damage + m.dmg_flat) * m.dmg_mult
	result = max(0.0, result - m.armor)
	return result

## 获取修饰后的球速度（mods 缺省时读兼容视图；ball 传自己的快照）
func get_modified_ball_speed(base_speed: float, mods: Dictionary = {}) -> float:
	var m: Dictionary = mods if not mods.is_empty() else _view_ball_mods()
	return (base_speed + m.speed_flat) * m.speed_mult

## 获取修饰后的飞行距离（mods 缺省时读兼容视图）
func get_modified_ball_range(base_range: float, mods: Dictionary = {}) -> float:
	var m: Dictionary = mods if not mods.is_empty() else _view_ball_mods()
	return (base_range + m.range_flat) * m.range_mult

## 球是否穿透（兼容视图）
func is_ball_penetrating() -> bool:
	return _view_ball_mods().penetrate

## 球是否回旋（兼容视图）
func is_ball_boomerang() -> bool:
	var m: Dictionary = _view_ball_mods()
	return m.boomerang and not m.lock_straight

## 球是否追踪（兼容视图）
func is_ball_tracking() -> bool:
	var m: Dictionary = _view_ball_mods()
	return m.tracking_target != null and not m.lock_straight

## 获取追踪目标（兼容视图）
func get_tracking_target() -> Node:
	return _view_ball_mods().tracking_target

## 获取追踪转向速度（兼容视图）
func get_tracking_turn_speed() -> float:
	return _view_ball_mods().tracking_turn_speed

## 球是否有AOE范围伤害（兼容视图）
func has_ball_aoe() -> bool:
	var m: Dictionary = _view_ball_mods()
	return m.has("aoe_radius") and m.aoe_radius > 0.0

## 获取AOE半径（兼容视图）
func get_ball_aoe_radius() -> float:
	return _view_ball_mods().get("aoe_radius", 0.0)

## 获取AOE伤害百分比（兼容视图）
func get_ball_aoe_damage_pct() -> float:
	return _view_ball_mods().get("aoe_damage_pct", 0.5)

## 球回旋触发（兼容保留：ball 已内联此逻辑，不再调用）
func trigger_boomerang(current_dir: Vector2) -> Vector2:
	var m: Dictionary = _ensure_ball_mods(_last_ball_caster)
	if m.boomerang_triggered:
		return Vector2.ZERO
	m.boomerang_triggered = true
	m.boomerang_return_dir = -current_dir
	return m.boomerang_return_dir

## ==================== 效果堆栈 ====================

## 注册持续效果
func _register_timed_effect(tag_id: String, params: Dictionary, duration: float, on_tick: Callable = Callable(), on_expire: Callable = Callable()) -> String:
	_effect_counter += 1
	var eid: String = "eff_%d" % _effect_counter
	_active_effects[eid] = {
		"tag_id": tag_id,
		"params": params,
		"duration": duration,
		"remaining": duration,
		"on_tick": on_tick,
		"on_expire": on_expire,
	}
	return eid


func remove_tag_effect(effect_id: String) -> void:
	if _active_effects.has(effect_id):
		var effect: Dictionary = _active_effects[effect_id]
		if effect.on_expire.is_valid():
			effect.on_expire.call()
		_active_effects.erase(effect_id)
		effect_finished.emit(effect.tag_id, effect)

## ==================== 辅助函数 ====================

## 获取施法者球员节点
func _get_caster(caster_id: int) -> CharacterBody2D:
	for p in players:
		if p and is_instance_valid(p) and p.get_instance_id() == caster_id:
			return p
	# 备用：从 battle_manager 获取
	if battle_manager and battle_manager.has_method("get_all_players"):
		for p in battle_manager.get_all_players():
			if p and is_instance_valid(p) and p.get_instance_id() == caster_id:
				return p
	return null

## 获取敌方球员列表
func _get_enemies(caster: CharacterBody2D) -> Array:
	var result: Array = []
	var enemy_team: String = "b" if caster.team == "a" else "a"
	for p in players:
		if p and is_instance_valid(p) and p.team == enemy_team and not p.is_defeated:
			# 隐身者不在敌方索敌列表中（锁定/追踪/索敌跳过）
			if p.is_status_active("stealthed"):
				continue
			result.append(p)
	return result

## 获取敌方最近球员
func _get_nearest_enemy(caster: CharacterBody2D) -> CharacterBody2D:
	var enemies := _get_enemies(caster)
	var nearest: CharacterBody2D = null
	var min_dist: float = INF
	for e in enemies:
		var dist: float = caster.global_position.distance_to(e.global_position)
		if dist < min_dist:
			min_dist = dist
			nearest = e
	return nearest

## ==================== 辅助方法 ====================

## 波6 #1 复制系：经 battle_manager→spirit_system→skill_trigger 链取触发器（拿不到=null）
## trigger_ref：显式注入口（测试/特殊挂接用），优先于链式查找
var trigger_ref: Node = null

func _get_trigger() -> Node:
	if trigger_ref != null and is_instance_valid(trigger_ref):
		return trigger_ref
	var bm = battle_manager
	if bm == null:
		bm = get_node_or_null("/root/BattleManager")
	if bm == null:
		return null
	var ss = bm.get("spirit_system")
	if ss != null and ss.get("skill_trigger") != null:
		return ss.get("skill_trigger")
	return null


func _get_obstacle_manager() -> Node:
	"""获取障碍物管理器"""
	if battle_manager and battle_manager.has_node("ObstacleManager"):
		return battle_manager.get_node("ObstacleManager")
	# 独立测试 fallback：通过组查找
	var om = get_tree().get_first_node_in_group("obstacle_managers")
	if om:
		return om
	return null


func _get_field_zone_manager() -> Node:
	"""获取场地区域管理器"""
	if battle_manager and battle_manager.has_node("FieldZoneManager"):
		return battle_manager.get_node("FieldZoneManager")
	# 独立测试 fallback：通过组查找
	var zm = get_tree().get_first_node_in_group("field_zone_managers")
	if zm:
		return zm
	return null


## 波7 #6a：场地区域物理管理器查找
func _get_field_physics_manager() -> Node:
	if battle_manager and battle_manager.has_node("FieldPhysicsManager"):
		return battle_manager.get_node("FieldPhysicsManager")
	var parent = get_parent()
	while parent:
		if parent.has_node("FieldPhysicsManager"):
			return parent.get_node("FieldPhysicsManager")
		parent = parent.get_parent()
	return null


func _get_illusion_manager() -> Node:
	"""获取幻象管理器"""
	if battle_manager and battle_manager.has_node("IllusionManager"):
		return battle_manager.get_node("IllusionManager")
	# 独立测试 fallback：通过组查找
	var im = get_tree().get_first_node_in_group("illusion_managers")
	if im:
		return im
	return null


func _get_element_color(element: String) -> Color:
	"""获取元素颜色"""
	var colors: Dictionary = {
		"金刚": Color(0.85, 0.75, 0.3),
		"大地": Color(0.7, 0.55, 0.35),
		"雷火": Color(1.0, 0.4, 0.2),
		"冰雪": Color(0.4, 0.8, 1.0),
		"草木": Color(0.3, 0.8, 0.3),
		"梦幻": Color(0.7, 0.5, 0.9),
	}
	return colors.get(element, Color(1.0, 1.0, 0.5))

## ==================== 球员标签通用函数 ====================


## 获取目标球员列表
func _get_player_targets(params: Dictionary, caster_id: int) -> Array:
	var target_mode: String = str(params.get("target", "self"))
	var caster := _get_caster(caster_id)
	var result: Array = []
	if not caster:
		return result
	match target_mode:
		"self":
			result.append(caster)
		"enemies":
			result = _get_enemies(caster)
		"allies":
			for p in players:
				if p and is_instance_valid(p) and p.team == caster.team and not p.is_defeated:
					result.append(p)
		"nearest_enemy":
			var nearest := _get_nearest_enemy(caster)
			if nearest:
				result.append(nearest)
			else:
				result = _get_enemies(caster)
		_:
			result.append(caster)
	return result

## 操3 坚果盾 toggle（操控规划/06 矩阵修复）：盾标签纳入 toggle 生命周期
## open/切形态=应用盾参数组（先撤旧盾保证形态干净轮换）；close=撤销该施法者当前盾
func apply_toggle_shield(caster_id: int, params: Dictionary) -> bool:
	remove_toggle_shield(caster_id)
	var p = _get_caster(caster_id)
	if p == null:
		return false
	call("_apply_player_shield_obstacle", params.duplicate(true), caster_id)
	var mgr = _get_obstacle_manager()
	if mgr == null:
		return false
	var shield = mgr.get_player_shield(caster_id)
	return shield != null and is_instance_valid(shield)


func remove_toggle_shield(caster_id: int) -> void:
	var mgr = _get_obstacle_manager()
	if mgr == null:
		return
	var shield = mgr.get_player_shield(caster_id)
	if shield != null and is_instance_valid(shield):
		mgr.remove_obstacle(shield)


## 获取所有敌方（含隐身，用于显形等不需要过滤的场景）
func _get_all_enemies(caster: CharacterBody2D) -> Array:
	var result: Array = []
	var enemy_team: String = "b" if caster.team == "a" else "a"
	for p in players:
		if p and is_instance_valid(p) and p.team == enemy_team and not p.is_defeated:
			result.append(p)
	return result



func apply_tag_effect(tag_id: String, params: Dictionary, caster_id: int) -> Dictionary:
	"""标签效果入口:启用队列时入队,否则直接执行"""
	if priority_queue_enabled and not _pending_tags.is_empty():
		# 队列中已有等待标签,新标签入队
		queue_tag_effect(tag_id, params, caster_id)
		return {"success": true, "tag_id": tag_id, "queued": true}
	elif priority_queue_enabled:
		# 队列为空,入队并启动窗口
		queue_tag_effect(tag_id, params, caster_id)
		return {"success": true, "tag_id": tag_id, "queued": true}
	else:
		# 不启用队列,直接执行
		return _do_apply_tag(tag_id, params, caster_id)


func _do_apply_tag(tag_id: String, params: Dictionary, caster_id: int) -> Dictionary:
	"""实际执行标签效果(原 match 逻辑)"""
	print("[TagEffect] 执行标签: %s params=%s" % [tag_id, params])

	var success := false

	# === 对球效果（2026-09-19 Step2：全部带 caster_id，写入该施法者自己的准备区）===
	match tag_id:
		# 数值类 (01-08)
		"ball_dmg_up_pct":
			call("_apply_ball_dmg_up", params, caster_id)
			success = true
		"ball_dmg_down_pct":
			call("_apply_ball_dmg_down", params, caster_id)
			success = true
		"ball_dmg_up_flat":
			var flat_params_up: Dictionary = params.duplicate()
			flat_params_up["value_type"] = "flat"
			call("_apply_ball_dmg_up", flat_params_up, caster_id)
			success = true
		"ball_dmg_down_flat":
			var flat_params_down: Dictionary = params.duplicate()
			flat_params_down["value_type"] = "flat"
			call("_apply_ball_dmg_down", flat_params_down, caster_id)
			success = true
		"ball_speed_up_pct":
			call("_apply_ball_speed_up", params, caster_id)
			success = true
		"ball_speed_down_pct":
			call("_apply_ball_speed_down", params, caster_id)
			success = true
		"ball_speed_up_flat":
			call("_apply_ball_speed_up", params, caster_id)
			success = true
		"ball_speed_down_flat":
			call("_apply_ball_speed_down", params, caster_id)
			success = true
		# 飞行行为类 (09-14)
		"ball_tracking":
			call("_apply_ball_tracking", params, caster_id)
			success = true
		"ball_avoid":
			success = true  # 避障待场地系统
		"ball_boomerang":
			call("_apply_ball_boomerang", params, caster_id)
			success = true
		"ball_straight":
			call("_apply_ball_straight", params, caster_id)
			success = true
		"ball_lockon":
			call("_apply_ball_lockon", params, caster_id)
			success = true
		"ball_spread":
			call("_apply_ball_spread", params, caster_id)  # 波6 #8 空壳转正
			success = true
		"ball_in_flight_boost":
			call("_apply_ball_in_flight_boost", params, caster_id)
			success = true
		"ball_recall":
			call("_apply_ball_recall", params, caster_id)
			success = true
		"ball_manual_steering":
			call("_apply_ball_manual_steering", params, caster_id)
			success = true
		"ball_carry_push":
			call("_apply_ball_carry_push", params, caster_id)
			success = true
		"field_vision_block":
			call("_apply_field_vision_block", params, caster_id)
			success = true
		# 波7 补遗（16 工单）
		"field_drain_wall":
			call("_apply_field_drain_wall", params, caster_id)
			success = true
		"field_terra_change":
			call("_apply_field_terra_change", params, caster_id)
			success = true
		# 波4 球类参数化（10 工单）
		"ball_bounce_enhance":
			call("_apply_ball_bounce_enhance", params, caster_id)
			success = true
		"ball_sure_hit":
			call("_apply_ball_sure_hit", params, caster_id)
			success = true
		"ball_transform":
			call("_apply_ball_transform", params, caster_id)
			success = true
		"ball_stealth":
			call("_apply_ball_stealth", params, caster_id)
			success = true
		# 穿透/范围类 (15-17)
		"ball_penetrate":
			call("_apply_ball_penetrate", params, caster_id)
			success = true
		"ball_range_up":
			call("_apply_ball_range_up", params, caster_id)
			success = true
		"ball_range_down":
			call("_apply_ball_range_down", params, caster_id)
			success = true
		# 对场地标签 (已实现2个 + 预留10个)
		"field_obs_add":
			call("_apply_field_obs_add", params)
			success = true
		"field_obs_clear":
			call("_apply_field_obs_clear", params)
			success = true
		"player_shield_obstacle":
			call("_apply_player_shield_obstacle", params, caster_id)
			success = true
		# === 场地标签 - 区域效果(07-10) ===
		"field_zone_boost":
			call("_apply_field_zone_effect", params, 0)
			success = true
		"field_zone_slow":
			call("_apply_field_zone_effect", params, 1)
			success = true
		"field_zone_danger":
			call("_apply_field_zone_effect", params, 2)
			success = true
		"field_zone_safe":
			call("_apply_field_zone_effect", params, 3)
			success = true
		"field_zone_heal":
			call("_apply_field_zone_effect", params, 4)  # 波5 #3 治疗区
			success = true
		# 对球员标签暂不实现（第1步只做buff堆栈）
		# === 球员标签 - 属性(01-16) ===
		"player_atk_up_pct":
			call("_apply_player_stat_buff", params, caster_id, "attack", 1.0 + float(params.get("value", 30)) / 100.0, 0.0)
			success = true
		"player_atk_down_pct":
			call("_apply_player_stat_buff", params, caster_id, "attack", 1.0 / max(0.01, 1.0 + float(params.get("value", 30)) / 100.0), 0.0)
			success = true
		"player_atk_up_flat":
			call("_apply_player_stat_buff", params, caster_id, "attack", 1.0, float(params.get("value", 10)))
			success = true
		"player_atk_down_flat":
			call("_apply_player_stat_buff", params, caster_id, "attack", 1.0, -float(params.get("value", 10)))
			success = true
		"player_def_up_pct":
			call("_apply_player_stat_buff", params, caster_id, "defense", 1.0 + float(params.get("value", 30)) / 100.0, 0.0)
			success = true
		"player_def_down_pct":
			call("_apply_player_stat_buff", params, caster_id, "defense", 1.0 / max(0.01, 1.0 + float(params.get("value", 30)) / 100.0), 0.0)
			success = true
		"player_def_up_flat":
			call("_apply_player_stat_buff", params, caster_id, "defense", 1.0, float(params.get("value", 10)))
			success = true
		"player_def_down_flat":
			call("_apply_player_stat_buff", params, caster_id, "defense", 1.0, -float(params.get("value", 10)))
			success = true
		"player_spd_up_pct":
			call("_apply_player_stat_buff", params, caster_id, "speed", 1.0 + float(params.get("value", 30)) / 100.0, 0.0)
			success = true
		"player_spd_down_pct":
			call("_apply_player_stat_buff", params, caster_id, "speed", 1.0 / max(0.01, 1.0 + float(params.get("value", 30)) / 100.0), 0.0)
			success = true
		"player_spd_up_flat":
			call("_apply_player_stat_buff", params, caster_id, "speed", 1.0, float(params.get("value", 30)))
			success = true
		"player_spd_down_flat":
			call("_apply_player_stat_buff", params, caster_id, "speed", 1.0, -float(params.get("value", 30)))
			success = true
		"player_res_up_pct":
			call("_apply_player_stat_buff", params, caster_id, "resilience", 1.0 + float(params.get("value", 30)) / 100.0, 0.0)
			success = true
		"player_res_down_pct":
			call("_apply_player_stat_buff", params, caster_id, "resilience", 1.0 / max(0.01, 1.0 + float(params.get("value", 30)) / 100.0), 0.0)
			success = true
		"player_res_up_flat":
			call("_apply_player_stat_buff", params, caster_id, "resilience", 1.0, float(params.get("value", 10)))
			success = true
		"player_res_down_flat":
			call("_apply_player_stat_buff", params, caster_id, "resilience", 1.0, -float(params.get("value", 10)))
			success = true
		# === 球员标签 - 状态(17-20) ===
		"player_invincible":
			call("_apply_player_status", params, caster_id, "invincible")
			success = true
		"player_vulnerable":
			call("_apply_player_vulnerable", params, caster_id)
			success = true
		"player_stealth":
			call("_apply_player_status", params, caster_id, "stealthed")
			success = true
		"player_reveal":
			call("_apply_player_reveal", params, caster_id)
			success = true
		# === 波3 球员管道变体（09 工单）===
		"player_heal_block":
			call("_apply_player_heal_block", params, caster_id)
			success = true
		"player_energy_block":
			# 规划版命名：单禁能别名
			call("_apply_player_heal_block", {"duration": params.get("duration", 3.0), "block": "energy"}, caster_id)
			success = true
		"player_damage_reflect":
			call("_apply_player_reflect", params, caster_id)
			success = true
		"player_element_immune":
			call("_apply_player_element_shield", params, caster_id)
			success = true
		"player_element_weak":
			# 规划版命名：弱点档（multiplier 默认 1.5）
			var weak_params: Dictionary = params.duplicate()
			weak_params["multiplier"] = params.get("multiplier", 1.5)
			call("_apply_player_element_shield", weak_params, caster_id)
			success = true
		"player_energy_share":
			call("_apply_player_energy_share", params, caster_id)
			success = true
		"player_charge_stock":
			call("_apply_player_charge_stock", params, caster_id)
			success = true
		"player_on_hit_expire":
			call("_apply_player_on_hit_expire", params, caster_id)
			success = true
		# === 波5（11 工单）===
		"skill_copy_last":
			call("_apply_player_skill_copy_last", params, caster_id)
			success = true
		"skill_share_copy":
			call("_apply_player_skill_share_copy", params, caster_id)
			success = true
		"player_mark_apply":
			call("_apply_player_mark_apply", params, caster_id)
			success = true
		# === 球员标签 - 体力(21-26) ===
		"player_hp_heal_pct":
			call("_apply_player_hp_heal_pct", params, caster_id)
			success = true
		"player_hp_damage_pct":
			call("_apply_player_hp_damage_pct", params, caster_id)
			success = true
		"player_hp_heal_flat":
			call("_apply_player_hp_heal_flat", params, caster_id)
			success = true
		"player_hp_damage_flat":
			call("_apply_player_hp_damage_flat", params, caster_id)
			success = true
		"player_hp_regen":
			call("_apply_player_hp_regen", params, caster_id)
			success = true
		"player_hp_dot":
			call("_apply_player_hp_dot", params, caster_id)
			success = true
		# === 球员标签 - 运动(27-30) ===
		"player_move_slow":
			call("_apply_player_stat_buff", params, caster_id, "speed", 1.0 / max(0.01, float(params.get("multiplier", 1.5))), 0.0)
			success = true
		"player_move_boost":
			call("_apply_player_stat_buff", params, caster_id, "speed", float(params.get("multiplier", 1.5)), 0.0)
			success = true
		"player_root":
			call("_apply_player_status", params, caster_id, "rooted")
			success = true
		"player_unroot":
			call("_apply_player_unroot", params, caster_id)
			success = true
		# === 球员标签 - 能量(31-38) ===
		"player_energy_gain_pct":
			call("_apply_player_energy_pct", params, caster_id, true)
			success = true
		"player_energy_cost_pct":
			call("_apply_player_energy_pct", params, caster_id, false)
			success = true
		"player_energy_gain_flat":
			call("_apply_player_energy_flat", params, caster_id, true)
			success = true
		"player_energy_cost_flat":
			call("_apply_player_energy_flat", params, caster_id, false)
			success = true
		"player_energy_max_up_pct":
			call("_apply_player_stat_buff", params, caster_id, "max_energy", 1.0 + float(params.get("value", 30)) / 100.0, 0.0)
			success = true
		"player_energy_max_down_pct":
			call("_apply_player_stat_buff", params, caster_id, "max_energy", 1.0 / max(0.01, 1.0 + float(params.get("value", 30)) / 100.0), 0.0)
			success = true
		"player_energy_max_up_flat":
			call("_apply_player_stat_buff", params, caster_id, "max_energy", 1.0, float(params.get("value", 20)))
			success = true
		"player_energy_max_down_flat":
			call("_apply_player_stat_buff", params, caster_id, "max_energy", 1.0, -float(params.get("value", 20)))
			success = true
		# === 球员标签 - 元灵(39-45) ===
		"player_spirit_cost_down":
			call("_apply_player_spirit_cost", params, caster_id, true)
			success = true
		"player_spirit_cost_up":
			call("_apply_player_spirit_cost", params, caster_id, false)
			success = true
		"player_spirit_uses_up":
			call("_apply_player_spirit_uses", params, caster_id)
			success = true
		"player_spirit_cd_down":
			call("_apply_player_spirit_cd", params, caster_id, true)
			success = true
		"player_spirit_cd_up":
			call("_apply_player_spirit_cd", params, caster_id, false)
			success = true
		"player_spirit_double":
			call("_apply_player_spirit_double", params, caster_id)
			success = true
		"player_spirit_half":
			call("_apply_player_spirit_half", params, caster_id)
			success = true
		# === 球员标签 - 控制(46-49) ===
		"player_stun":
			call("_apply_player_status", params, caster_id, "stunned")
			success = true
		"player_cc_immune":
			call("_apply_player_status", params, caster_id, "cc_immune")
			success = true
		"player_silence":
			call("_apply_player_status", params, caster_id, "silenced")
			success = true
		"player_disarm":
			call("_apply_player_status", params, caster_id, "disarmed")
			success = true
		# === 球员标签 - 交互(50-51) ===
		"player_teleport":
			call("_apply_player_teleport", params, caster_id)
			success = true
		"player_return":
			call("_apply_player_return", params, caster_id)
			success = true
		_:
			print("[TagEffect] 标签未实现: %s" % tag_id)

	var effect_data: Dictionary = {
		"tag_id": tag_id,
		"params": params,
		"caster_id": caster_id,
	}

	if success:
		effect_applied.emit(tag_id, effect_data)

	return {"success": success, "tag_id": tag_id}


## ==================== 优先级表初始化 ====================

func _init_priority_table() -> void:
	"""初始化所有标签的优先级数字,越小越先执行"""
	# === BALL类 ===
	# B-10 数值修改层
	_tag_priority["ball_dmg_up_pct"] = 11
	_tag_priority["ball_dmg_down_pct"] = 12
	_tag_priority["ball_dmg_up_flat"] = 13
	_tag_priority["ball_dmg_down_flat"] = 14
	_tag_priority["ball_speed_up_pct"] = 15
	_tag_priority["ball_speed_down_pct"] = 16
	_tag_priority["ball_speed_up_flat"] = 17
	_tag_priority["ball_speed_down_flat"] = 18
	# B-20 飞行行为层
	_tag_priority["ball_tracking"] = 21
	_tag_priority["ball_avoid"] = 22
	_tag_priority["ball_boomerang"] = 23
	_tag_priority["ball_straight"] = 24
	_tag_priority["ball_lockon"] = 25
	_tag_priority["ball_spread"] = 26
	# 波4 球类参数化（10 工单）
	_tag_priority["ball_bounce_enhance"] = 27
	_tag_priority["ball_sure_hit"] = 28
	_tag_priority["ball_transform"] = 29
	_tag_priority["ball_stealth"] = 30
	# 波6 高难收官（12 工单）
	_tag_priority["ball_spread"] = 31
	_tag_priority["ball_in_flight_boost"] = 32
	_tag_priority["ball_recall"] = 33
	_tag_priority["ball_manual_steering"] = 34
	_tag_priority["ball_carry_push"] = 35
	_tag_priority["field_vision_block"] = 141  # FIELD 感知层
	# B-30 穿透/范围层
	_tag_priority["ball_penetrate"] = 31
	_tag_priority["ball_range_up"] = 32
	_tag_priority["ball_range_down"] = 33

	# === FIELD类 ===
	# F-10 障碍层
	_tag_priority["field_obs_add"] = 101
	_tag_priority["field_obs_clear"] = 102
	_tag_priority["player_shield_obstacle"] = 103
	# F-20 地形层
	_tag_priority["field_terra_change"] = 121
	_tag_priority["field_terra_revert"] = 122
	_tag_priority["field_zone_mark"] = 123
	_tag_priority["field_zone_clear"] = 124
	# F-30 区域效果层
	_tag_priority["field_zone_boost"] = 131
	_tag_priority["field_zone_slow"] = 132
	_tag_priority["field_zone_danger"] = 133
	_tag_priority["field_zone_safe"] = 134
	# F-40 视觉层
	_tag_priority["field_illusion_add"] = 141
	_tag_priority["field_illusion_clear"] = 142

	# === PLAYER类 ===
	# P-10 规则修改层(最先执行,影响后续标签结算)
	_tag_priority["player_spirit_cost_down"] = 201
	_tag_priority["player_spirit_cost_up"] = 202
	_tag_priority["player_spirit_cd_down"] = 203
	_tag_priority["player_spirit_cd_up"] = 204
	_tag_priority["player_spirit_double"] = 205
	_tag_priority["player_spirit_half"] = 206
	_tag_priority["player_spirit_uses_up"] = 207
	# P-20 属性Buff层
	_tag_priority["player_atk_up_pct"] = 221
	_tag_priority["player_atk_down_pct"] = 222
	_tag_priority["player_atk_up_flat"] = 223
	_tag_priority["player_atk_down_flat"] = 224
	_tag_priority["player_def_up_pct"] = 225
	_tag_priority["player_def_down_pct"] = 226
	_tag_priority["player_def_up_flat"] = 227
	_tag_priority["player_def_down_flat"] = 228
	_tag_priority["player_spd_up_pct"] = 229
	_tag_priority["player_spd_down_pct"] = 230
	_tag_priority["player_spd_up_flat"] = 231
	_tag_priority["player_spd_down_flat"] = 232
	_tag_priority["player_res_up_pct"] = 233
	_tag_priority["player_res_down_pct"] = 234
	_tag_priority["player_res_up_flat"] = 235
	_tag_priority["player_res_down_flat"] = 236
	_tag_priority["player_energy_max_up_pct"] = 237
	_tag_priority["player_energy_max_down_pct"] = 238
	_tag_priority["player_energy_max_up_flat"] = 239
	_tag_priority["player_energy_max_down_flat"] = 240
	# P-30 状态灯层
	_tag_priority["player_invincible"] = 301
	_tag_priority["player_vulnerable"] = 302
	_tag_priority["player_stealth"] = 303
	_tag_priority["player_reveal"] = 304
	# 波3 球员管道变体（09 工单，命名对齐规划版）
	_tag_priority["player_heal_block"] = 311
	_tag_priority["player_energy_block"] = 312
	_tag_priority["player_damage_reflect"] = 313
	_tag_priority["player_element_immune"] = 314
	_tag_priority["player_element_weak"] = 315
	_tag_priority["player_energy_share"] = 316
	_tag_priority["player_charge_stock"] = 317
	_tag_priority["player_on_hit_expire"] = 361  # 排在状态/控制层后，标记已在亮的灯
	# 波5 管道/zone 扩展（11 工单）
	_tag_priority["player_mark_apply"] = 341
	# P-40 运动控制层
	_tag_priority["player_move_slow"] = 401
	_tag_priority["player_move_boost"] = 402
	_tag_priority["player_root"] = 403
	_tag_priority["player_unroot"] = 404
	# P-50 控制层
	_tag_priority["player_stun"] = 501
	_tag_priority["player_cc_immune"] = 502
	_tag_priority["player_silence"] = 503
	_tag_priority["player_disarm"] = 504
	# P-60 即时效果层(依赖前面所有buff的最终值)
	_tag_priority["player_hp_heal_pct"] = 601
	_tag_priority["player_hp_damage_pct"] = 602
	_tag_priority["player_hp_heal_flat"] = 603
	_tag_priority["player_hp_damage_flat"] = 604
	_tag_priority["player_hp_regen"] = 605
	_tag_priority["player_hp_dot"] = 606
	_tag_priority["player_energy_gain_pct"] = 607
	_tag_priority["player_energy_cost_pct"] = 608
	_tag_priority["player_energy_gain_flat"] = 609
	_tag_priority["player_energy_cost_flat"] = 610
	# P-70 交互层
	_tag_priority["player_teleport"] = 701
	_tag_priority["player_return"] = 702


func get_tag_priority(tag_id: String) -> int:
	"""获取标签优先级,未注册的返回999(最后执行)"""
	return _tag_priority.get(tag_id, 999)


func queue_tag_effect(tag_id: String, params: Dictionary, caster_id: int) -> void:
	"""将标签加入待执行队列,重置窗口计时器"""
	var pri: int = get_tag_priority(tag_id)
	_pending_tags.append({"tag_id": tag_id, "params": params, "caster_id": caster_id, "priority": pri})
	_flush_timer = FLUSH_WINDOW
	print("[TagQueue] 排队: %s (优先级=%d, 队列=%d)" % [tag_id, pri, _pending_tags.size()])


func _flush_pending_tags() -> void:
	"""按优先级排序后批量执行队列中的标签"""
	if _pending_tags.is_empty():
		return
	# 按优先级排序(小数字先执行)
	_pending_tags.sort_custom(func(a, b): return a.priority < b.priority)
	print("[TagQueue] 开始按优先级执行 %d 个标签" % _pending_tags.size())
	for entry in _pending_tags:
		_do_apply_tag(entry.tag_id, entry.params, entry.caster_id)
	_pending_tags.clear()
	_flush_timer = 0.0

## ==================== 主入口 ====================

