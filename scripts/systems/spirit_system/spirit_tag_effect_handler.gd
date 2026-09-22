extends Node
class_name SpiritTagEffectHandler

## 元灵技能标签效果处理器
## 负责执行所有标签的对应效果

signal effect_applied(tag_id: String, effect_data: Dictionary)
signal effect_finished(tag_id: String, effect_data: Dictionary)

# 引用
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


func _ready() -> void:
	battle_manager = get_node_or_null("/root/BattleManager")
	_init_priority_table()


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


## ==================== 主入口 ====================

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
			_apply_ball_dmg_up(params, caster_id)
			success = true
		"ball_dmg_down_pct":
			_apply_ball_dmg_down(params, caster_id)
			success = true
		"ball_dmg_up_flat":
			var flat_params_up: Dictionary = params.duplicate()
			flat_params_up["value_type"] = "flat"
			_apply_ball_dmg_up(flat_params_up, caster_id)
			success = true
		"ball_dmg_down_flat":
			var flat_params_down: Dictionary = params.duplicate()
			flat_params_down["value_type"] = "flat"
			_apply_ball_dmg_down(flat_params_down, caster_id)
			success = true
		"ball_speed_up_pct":
			_apply_ball_speed_up(params, caster_id)
			success = true
		"ball_speed_down_pct":
			_apply_ball_speed_down(params, caster_id)
			success = true
		"ball_speed_up_flat":
			_apply_ball_speed_up(params, caster_id)
			success = true
		"ball_speed_down_flat":
			_apply_ball_speed_down(params, caster_id)
			success = true
		# 飞行行为类 (09-14)
		"ball_tracking":
			_apply_ball_tracking(params, caster_id)
			success = true
		"ball_avoid":
			success = true  # 避障待场地系统
		"ball_boomerang":
			_apply_ball_boomerang(params, caster_id)
			success = true
		"ball_straight":
			_apply_ball_straight(params, caster_id)
			success = true
		"ball_lockon":
			_apply_ball_lockon(params, caster_id)
			success = true
		"ball_spread":
			_apply_ball_spread(params, caster_id)  # 波6 #8 空壳转正
			success = true
		"ball_in_flight_boost":
			_apply_ball_in_flight_boost(params, caster_id)
			success = true
		"ball_recall":
			_apply_ball_recall(params, caster_id)
			success = true
		"ball_manual_steering":
			_apply_ball_manual_steering(params, caster_id)
			success = true
		"ball_carry_push":
			_apply_ball_carry_push(params, caster_id)
			success = true
		"field_vision_block":
			_apply_field_vision_block(params, caster_id)
			success = true
		# 波4 球类参数化（10 工单）
		"ball_bounce_enhance":
			_apply_ball_bounce_enhance(params, caster_id)
			success = true
		"ball_sure_hit":
			_apply_ball_sure_hit(params, caster_id)
			success = true
		"ball_transform":
			_apply_ball_transform(params, caster_id)
			success = true
		"ball_stealth":
			_apply_ball_stealth(params, caster_id)
			success = true
		# 穿透/范围类 (15-17)
		"ball_penetrate":
			_apply_ball_penetrate(params, caster_id)
			success = true
		"ball_range_up":
			_apply_ball_range_up(params, caster_id)
			success = true
		"ball_range_down":
			_apply_ball_range_down(params, caster_id)
			success = true
		# 对场地标签 (已实现2个 + 预留10个)
		"field_obs_add":
			_apply_field_obs_add(params)
			success = true
		"field_obs_clear":
			_apply_field_obs_clear(params)
			success = true
		"player_shield_obstacle":
			_apply_player_shield_obstacle(params, caster_id)
			success = true
		# === 场地标签 - 区域效果(07-10) ===
		"field_zone_boost":
			_apply_field_zone_effect(params, 0)
			success = true
		"field_zone_slow":
			_apply_field_zone_effect(params, 1)
			success = true
		"field_zone_danger":
			_apply_field_zone_effect(params, 2)
			success = true
		"field_zone_safe":
			_apply_field_zone_effect(params, 3)
			success = true
		"field_zone_heal":
			_apply_field_zone_effect(params, 4)  # 波5 #3 治疗区
			success = true
		# 对球员标签暂不实现（第1步只做buff堆栈）
		# === 球员标签 - 属性(01-16) ===
		"player_atk_up_pct":
			_apply_player_stat_buff(params, caster_id, "attack", 1.0 + float(params.get("value", 30)) / 100.0, 0.0)
			success = true
		"player_atk_down_pct":
			_apply_player_stat_buff(params, caster_id, "attack", 1.0 / max(0.01, 1.0 + float(params.get("value", 30)) / 100.0), 0.0)
			success = true
		"player_atk_up_flat":
			_apply_player_stat_buff(params, caster_id, "attack", 1.0, float(params.get("value", 10)))
			success = true
		"player_atk_down_flat":
			_apply_player_stat_buff(params, caster_id, "attack", 1.0, -float(params.get("value", 10)))
			success = true
		"player_def_up_pct":
			_apply_player_stat_buff(params, caster_id, "defense", 1.0 + float(params.get("value", 30)) / 100.0, 0.0)
			success = true
		"player_def_down_pct":
			_apply_player_stat_buff(params, caster_id, "defense", 1.0 / max(0.01, 1.0 + float(params.get("value", 30)) / 100.0), 0.0)
			success = true
		"player_def_up_flat":
			_apply_player_stat_buff(params, caster_id, "defense", 1.0, float(params.get("value", 10)))
			success = true
		"player_def_down_flat":
			_apply_player_stat_buff(params, caster_id, "defense", 1.0, -float(params.get("value", 10)))
			success = true
		"player_spd_up_pct":
			_apply_player_stat_buff(params, caster_id, "speed", 1.0 + float(params.get("value", 30)) / 100.0, 0.0)
			success = true
		"player_spd_down_pct":
			_apply_player_stat_buff(params, caster_id, "speed", 1.0 / max(0.01, 1.0 + float(params.get("value", 30)) / 100.0), 0.0)
			success = true
		"player_spd_up_flat":
			_apply_player_stat_buff(params, caster_id, "speed", 1.0, float(params.get("value", 30)))
			success = true
		"player_spd_down_flat":
			_apply_player_stat_buff(params, caster_id, "speed", 1.0, -float(params.get("value", 30)))
			success = true
		"player_res_up_pct":
			_apply_player_stat_buff(params, caster_id, "resilience", 1.0 + float(params.get("value", 30)) / 100.0, 0.0)
			success = true
		"player_res_down_pct":
			_apply_player_stat_buff(params, caster_id, "resilience", 1.0 / max(0.01, 1.0 + float(params.get("value", 30)) / 100.0), 0.0)
			success = true
		"player_res_up_flat":
			_apply_player_stat_buff(params, caster_id, "resilience", 1.0, float(params.get("value", 10)))
			success = true
		"player_res_down_flat":
			_apply_player_stat_buff(params, caster_id, "resilience", 1.0, -float(params.get("value", 10)))
			success = true
		# === 球员标签 - 状态(17-20) ===
		"player_invincible":
			_apply_player_status(params, caster_id, "invincible")
			success = true
		"player_vulnerable":
			_apply_player_vulnerable(params, caster_id)
			success = true
		"player_stealth":
			_apply_player_status(params, caster_id, "stealthed")
			success = true
		"player_reveal":
			_apply_player_reveal(params, caster_id)
			success = true
		# === 波3 球员管道变体（09 工单）===
		"player_heal_block":
			_apply_player_heal_block(params, caster_id)
			success = true
		"player_energy_block":
			# 规划版命名：单禁能别名
			_apply_player_heal_block({"duration": params.get("duration", 3.0), "block": "energy"}, caster_id)
			success = true
		"player_damage_reflect":
			_apply_player_reflect(params, caster_id)
			success = true
		"player_element_immune":
			_apply_player_element_shield(params, caster_id)
			success = true
		"player_element_weak":
			# 规划版命名：弱点档（multiplier 默认 1.5）
			var weak_params: Dictionary = params.duplicate()
			weak_params["multiplier"] = params.get("multiplier", 1.5)
			_apply_player_element_shield(weak_params, caster_id)
			success = true
		"player_energy_share":
			_apply_player_energy_share(params, caster_id)
			success = true
		"player_charge_stock":
			_apply_player_charge_stock(params, caster_id)
			success = true
		"player_on_hit_expire":
			_apply_player_on_hit_expire(params, caster_id)
			success = true
		# === 波5（11 工单）===
		"player_mark_apply":
			_apply_player_mark_apply(params, caster_id)
			success = true
		# === 球员标签 - 体力(21-26) ===
		"player_hp_heal_pct":
			_apply_player_hp_heal_pct(params, caster_id)
			success = true
		"player_hp_damage_pct":
			_apply_player_hp_damage_pct(params, caster_id)
			success = true
		"player_hp_heal_flat":
			_apply_player_hp_heal_flat(params, caster_id)
			success = true
		"player_hp_damage_flat":
			_apply_player_hp_damage_flat(params, caster_id)
			success = true
		"player_hp_regen":
			_apply_player_hp_regen(params, caster_id)
			success = true
		"player_hp_dot":
			_apply_player_hp_dot(params, caster_id)
			success = true
		# === 球员标签 - 运动(27-30) ===
		"player_move_slow":
			_apply_player_stat_buff(params, caster_id, "speed", 1.0 / max(0.01, float(params.get("multiplier", 1.5))), 0.0)
			success = true
		"player_move_boost":
			_apply_player_stat_buff(params, caster_id, "speed", float(params.get("multiplier", 1.5)), 0.0)
			success = true
		"player_root":
			_apply_player_status(params, caster_id, "rooted")
			success = true
		"player_unroot":
			_apply_player_unroot(params, caster_id)
			success = true
		# === 球员标签 - 能量(31-38) ===
		"player_energy_gain_pct":
			_apply_player_energy_pct(params, caster_id, true)
			success = true
		"player_energy_cost_pct":
			_apply_player_energy_pct(params, caster_id, false)
			success = true
		"player_energy_gain_flat":
			_apply_player_energy_flat(params, caster_id, true)
			success = true
		"player_energy_cost_flat":
			_apply_player_energy_flat(params, caster_id, false)
			success = true
		"player_energy_max_up_pct":
			_apply_player_stat_buff(params, caster_id, "max_energy", 1.0 + float(params.get("value", 30)) / 100.0, 0.0)
			success = true
		"player_energy_max_down_pct":
			_apply_player_stat_buff(params, caster_id, "max_energy", 1.0 / max(0.01, 1.0 + float(params.get("value", 30)) / 100.0), 0.0)
			success = true
		"player_energy_max_up_flat":
			_apply_player_stat_buff(params, caster_id, "max_energy", 1.0, float(params.get("value", 20)))
			success = true
		"player_energy_max_down_flat":
			_apply_player_stat_buff(params, caster_id, "max_energy", 1.0, -float(params.get("value", 20)))
			success = true
		# === 球员标签 - 元灵(39-45) ===
		"player_spirit_cost_down":
			_apply_player_spirit_cost(params, caster_id, true)
			success = true
		"player_spirit_cost_up":
			_apply_player_spirit_cost(params, caster_id, false)
			success = true
		"player_spirit_uses_up":
			_apply_player_spirit_uses(params, caster_id)
			success = true
		"player_spirit_cd_down":
			_apply_player_spirit_cd(params, caster_id, true)
			success = true
		"player_spirit_cd_up":
			_apply_player_spirit_cd(params, caster_id, false)
			success = true
		"player_spirit_double":
			_apply_player_spirit_double(params, caster_id)
			success = true
		"player_spirit_half":
			_apply_player_spirit_half(params, caster_id)
			success = true
		# === 球员标签 - 控制(46-49) ===
		"player_stun":
			_apply_player_status(params, caster_id, "stunned")
			success = true
		"player_cc_immune":
			_apply_player_status(params, caster_id, "cc_immune")
			success = true
		"player_silence":
			_apply_player_status(params, caster_id, "silenced")
			success = true
		"player_disarm":
			_apply_player_status(params, caster_id, "disarmed")
			success = true
		# === 球员标签 - 交互(50-51) ===
		"player_teleport":
			_apply_player_teleport(params, caster_id)
			success = true
		"player_return":
			_apply_player_return(params, caster_id)
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


func _process(delta: float) -> void:
	# 比赛时钟（快照有效期基准；Engine.time_scale/暂停自动同步）
	_match_clock += delta

	# 优先级队列窗口计时
	if _flush_timer > 0.0:
		_flush_timer -= delta
		if _flush_timer <= 0.0:
			_flush_pending_tags()

	# 球修饰符准备区过期清扫（兜底；正常由投球取走即清回收）
	var expired_casters: Array = []
	for cid in _ball_mods_by_caster:
		var expires: Dictionary = _ball_mods_by_caster[cid].get("_expires", {})
		if expires.is_empty():
			continue
		var all_expired: bool = true
		for f in expires:
			if _match_clock <= float(expires[f]):
				all_expired = false
				break
		if all_expired:
			expired_casters.append(cid)
	for cid in expired_casters:
		_ball_mods_by_caster.erase(cid)

	# V1-3 落点区域 pending 过期清理（球被接住/未落地 30s 兜底）
	_cleanup_expired_zone_spawns()
	# 波6 #14 飞行球 pending 过期清理 + 订阅一次
	_cleanup_pending_in_flight()

	# 活跃效果倒计时
	var to_remove: PackedStringArray = []
	for eid in _active_effects:
		var effect: Dictionary = _active_effects[eid]
		effect.remaining -= delta
		# 每帧 tick
		if effect.on_tick.is_valid():
			effect.on_tick.call(delta)
		if effect.remaining <= 0.0:
			to_remove.append(eid)
	for eid in to_remove:
		remove_tag_effect(eid)


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


## ==================== 对球效果实现 (14个) ====================

## 01 增伤 — params: {value_type, value, duration}
func _apply_ball_dmg_up(params: Dictionary, caster_id: int) -> void:
	var mods: Dictionary = _ensure_ball_mods(caster_id)
	var val: float = float(params.get("value", 0))
	var vtype: String = str(params.get("value_type", "percentage"))
	var fields: Array = []
	if vtype == "percentage":
		mods.dmg_mult += val / 100.0
		fields = ["dmg_mult"]
	else:
		mods.dmg_flat += val
		fields = ["dmg_flat"]
	_mark_expiry(mods, fields, float(params.get("duration", 0)))
	print("[TagEffect] 增伤: type=%s val=%.1f mult=%.2f flat=%.1f (caster=%d)" % [vtype, val, mods.dmg_mult, mods.dmg_flat, caster_id])

## 02 减伤
func _apply_ball_dmg_down(params: Dictionary, caster_id: int) -> void:
	var mods: Dictionary = _ensure_ball_mods(caster_id)
	var val: float = float(params.get("value", 0))
	var vtype: String = str(params.get("value_type", "percentage"))
	var fields: Array = []
	if vtype == "percentage":
		mods.dmg_mult -= val / 100.0
		fields = ["dmg_mult"]
	else:
		mods.dmg_flat -= val
		fields = ["dmg_flat"]
	mods.dmg_mult = max(0.0, mods.dmg_mult)
	_mark_expiry(mods, fields, float(params.get("duration", 0)))
	print("[TagEffect] 减伤: mult=%.2f flat=%.1f (caster=%d)" % [mods.dmg_mult, mods.dmg_flat, caster_id])

## 03 穿透 — params: {duration}
func _apply_ball_penetrate(params: Dictionary, caster_id: int) -> void:
	var mods: Dictionary = _ensure_ball_mods(caster_id)
	mods.penetrate = true
	_mark_expiry(mods, ["penetrate"], float(params.get("duration", 0)))
	print("[TagEffect] 穿透: 启用 (caster=%d)" % caster_id)

## 04 护甲 — params: {value_type, value, duration}
func _apply_ball_armor(params: Dictionary, caster_id: int) -> void:
	var mods: Dictionary = _ensure_ball_mods(caster_id)
	var val: float = float(params.get("value", 0))
	mods.armor += val
	_mark_expiry(mods, ["armor"], float(params.get("duration", 0)))
	print("[TagEffect] 护甲: armor=%.1f (caster=%d)" % [mods.armor, caster_id])

## 05 加速 — params: {multiplier, value(固定值), duration}
func _apply_ball_speed_up(params: Dictionary, caster_id: int) -> void:
	var mods: Dictionary = _ensure_ball_mods(caster_id)
	var mult: float = float(params.get("multiplier", 0))
	# 兼容 registry 的 value 字段(ball_speed_up_flat 用 value)
	var fixed: float = float(params.get("value", params.get("fixed_value", 0)))
	var fields: Array = []
	if mult > 0:
		mods.speed_mult *= mult
		fields.append("speed_mult")
	if fixed != 0:
		mods.speed_flat += fixed
		fields.append("speed_flat")
	_mark_expiry(mods, fields, float(params.get("duration", 0)))
	print("[TagEffect] 球加速: mult=%.2f flat=%.1f (caster=%d)" % [mods.speed_mult, mods.speed_flat, caster_id])

## 06 减速
func _apply_ball_speed_down(params: Dictionary, caster_id: int) -> void:
	var mods: Dictionary = _ensure_ball_mods(caster_id)
	var mult: float = float(params.get("multiplier", 0))
	var fixed: float = float(params.get("value", params.get("fixed_value", 0)))
	var fields: Array = []
	if mult > 0:
		mods.speed_mult /= mult
		fields.append("speed_mult")
	if fixed != 0:
		mods.speed_flat -= fixed
		fields.append("speed_flat")
	mods.speed_mult = max(0.1, mods.speed_mult)
	_mark_expiry(mods, fields, float(params.get("duration", 0)))
	print("[TagEffect] 球减速: mult=%.2f flat=%.1f (caster=%d)" % [mods.speed_mult, mods.speed_flat, caster_id])

## 07 范围扩大/AOE — params: {radius, damage_pct, multiplier(兼容)}
## registry 定义: radius=AOE半径, damage_pct=范围伤害比(0-1)
func _apply_ball_range_up(params: Dictionary, caster_id: int) -> void:
	var mods: Dictionary = _ensure_ball_mods(caster_id)
	var radius: float = float(params.get("radius", 0))
	var dmg_pct: float = float(params.get("damage_pct", 0))
	var mult: float = float(params.get("multiplier", 0))
	var fields: Array = []
	# 设置 AOE 半径和伤害比(供球侧快照 aoe_radius 使用)
	if radius > 0:
		mods.aoe_radius = radius
		fields.append("aoe_radius")
	if dmg_pct > 0:
		mods.aoe_damage_pct = dmg_pct
		fields.append("aoe_damage_pct")
	if mult > 0:
		mods.range_mult *= mult
		fields.append("range_mult")
	_mark_expiry(mods, fields, float(params.get("duration", 0)))
	print("[TagEffect] 范围扩大/AOE: radius=%.1f dmg_pct=%.2f mult=%.2f (caster=%d)" % [mods.aoe_radius, mods.aoe_damage_pct, mods.range_mult, caster_id])

## 08 范围缩小
func _apply_ball_range_down(params: Dictionary, caster_id: int) -> void:
	var mods: Dictionary = _ensure_ball_mods(caster_id)
	var mult: float = float(params.get("multiplier", 0))
	if mult > 0:
		mods.range_mult /= mult
		_mark_expiry(mods, ["range_mult"], float(params.get("duration", 0)))
	mods.range_mult = max(0.1, mods.range_mult)
	print("[TagEffect] 范围缩小: mult=%.2f (caster=%d)" % [mods.range_mult, caster_id])

## 09 精准锁定 — 锁定最近敌人方向
func _apply_ball_lockon(params: Dictionary, caster_id: int) -> void:
	# 锁定在发球时处理：设置 ball_direction 指向最近敌人
	var caster := _get_caster(caster_id)
	if caster:
		var target := _get_nearest_enemy(caster)
		if target:
			var mods: Dictionary = _ensure_ball_mods(caster_id)
			mods.lockon_target = target
			_mark_expiry(mods, ["lockon_target"], float(params.get("duration", 0)))
			print("[TagEffect] 精准锁定: 目标=%s (caster=%d)" % [target.char_data.get("name", "?"), caster_id])
		else:
			print("[TagEffect] 精准锁定: 无目标")
	else:
		print("[TagEffect] 精准锁定: 找不到施法者")

## 10 扩散效果 — 碰撞时分裂
## 扩散标记 spread_done 存于各 caster 准备区（当前 ball 侧未消费）

## 11 追踪 — 持续追踪目标
func _apply_ball_tracking(params: Dictionary, caster_id: int) -> void:
	var caster := _get_caster(caster_id)
	if not caster:
		print("[TagEffect] 追踪: 找不到施法者")
		return
	var target := _get_nearest_enemy(caster)
	if target:
		var mods: Dictionary = _ensure_ball_mods(caster_id)
		mods.tracking_target = target
		mods.tracking_turn_speed = float(params.get("turn_speed", 3.0))
		_mark_expiry(mods, ["tracking_target", "tracking_turn_speed"], float(params.get("duration", 0)))
		print("[TagEffect] 追踪: 目标=%s 转速=%.1f (caster=%d)" % [target.char_data.get("name", "?"), mods.tracking_turn_speed, caster_id])
	else:
		print("[TagEffect] 追踪: 无目标")

## 12 避障 — 待场地系统实现
## 标记已存在，ball 侧可检查快照["avoid"]

## 13 回旋 — 飞到一半距离时返回
func _apply_ball_boomerang(params: Dictionary, caster_id: int) -> void:
	var mods: Dictionary = _ensure_ball_mods(caster_id)
	mods.boomerang = true
	mods.boomerang_dist = float(params.get("return_distance", 0.5))
	_mark_expiry(mods, ["boomerang", "boomerang_dist"], float(params.get("duration", 0)))
	print("[TagEffect] 回旋: 启用 返回点=%.0f%% (caster=%d)" % [mods.boomerang_dist * 100, caster_id])

## 14 直行 — 禁用所有轨迹修改
func _apply_ball_straight(params: Dictionary, caster_id: int) -> void:
	var mods: Dictionary = _ensure_ball_mods(caster_id)
	mods.lock_straight = true
	# 清除追踪和回旋
	mods.tracking_target = null
	mods.boomerang = false
	_mark_expiry(mods, ["lock_straight"], float(params.get("duration", 0)))
	print("[TagEffect] 直行: 启用，禁用追踪/回旋 (caster=%d)" % caster_id)


## ==================== 波4 球类参数化（10 工单）====================

## #15 反弹增强：撞墙反弹次数上限 + 每次反弹速度保持率（规划版命名）
func _apply_ball_bounce_enhance(params: Dictionary, caster_id: int) -> void:
	var mods: Dictionary = _ensure_ball_mods(caster_id)
	mods.bounce_max = maxi(0, int(params.get("max_bounces", params.get("bounce_max", 0))))
	mods.bounce_speed_mult = maxf(0.1, float(params.get("speed_keep_pct", params.get("speed_mult", 1.0))))
	_mark_expiry(mods, ["bounce_max", "bounce_speed_mult"], float(params.get("duration", 0)))
	print("[TagEffect] 反弹增强: max=%d speed_keep=%.2f (caster=%d)" % [mods.bounce_max, mods.bounce_speed_mult, caster_id])

## #22 必中：高度窗豁免 + 追踪目标隐身不丢（瞄准沿用 lockon 组合）
func _apply_ball_sure_hit(params: Dictionary, caster_id: int) -> void:
	var mods: Dictionary = _ensure_ball_mods(caster_id)
	mods.sure_hit = true
	_mark_expiry(mods, ["sure_hit"], float(params.get("duration", 0)))
	print("[TagEffect] 必中: 启用 (caster=%d)" % caster_id)

## #23 球形态变换：碰撞判定半径倍率（视觉缩放=美术线消费 size_scale 查询）
func _apply_ball_transform(params: Dictionary, caster_id: int) -> void:
	var mods: Dictionary = _ensure_ball_mods(caster_id)
	mods.size_scale = clampf(float(params.get("size_scale", 1.0)), 0.25, 4.0)
	_mark_expiry(mods, ["size_scale"], float(params.get("duration", 0)))
	print("[TagEffect] 球形态: size_scale=%.2f (caster=%d)" % [mods.size_scale, caster_id])

## #7 球隐身：球对敌方不可见（AI 躲球感知跳过；表现消费 is_stealthed() 接口）
func _apply_ball_stealth(params: Dictionary, caster_id: int) -> void:
	var mods: Dictionary = _ensure_ball_mods(caster_id)
	mods.hidden_from_enemies = true
	_mark_expiry(mods, ["hidden_from_enemies"], float(params.get("duration", 0)))
	print("[TagEffect] 球隐身: 启用 (caster=%d)" % caster_id)


## ==================== 波6 高难收官（12 工单）====================

## #8 分裂（空壳转正）：母球在飞行距离比例点分裂 count 个子球（伤害×ratio）
func _apply_ball_spread(params: Dictionary, caster_id: int) -> void:
	var mods: Dictionary = _ensure_ball_mods(caster_id)
	mods.spread_count = maxi(0, int(params.get("split_count", 0)))
	mods.spread_damage_ratio = clampf(float(params.get("split_damage_ratio", 1.0)), 0.1, 2.0)
	mods.spread_trigger_dist_pct = clampf(float(params.get("trigger_dist_pct", 0.6)), 0.1, 1.0)
	_mark_expiry(mods, ["spread_count", "spread_damage_ratio", "spread_trigger_dist_pct"], float(params.get("duration", 0)))
	print("[TagEffect] 分裂: count=%d ratio=%.2f trigger@%.0f%% (caster=%d)" % [mods.spread_count, mods.spread_damage_ratio, mods.spread_trigger_dist_pct * 100, caster_id])

## #14 飞行中球操作：场上本方飞行球直接作用；无则 pending（V1-3 桥同款，30s 过期）
func _apply_ball_in_flight_boost(params: Dictionary, caster_id: int) -> void:
	var mods: Dictionary = {}
	mods["dmg_pct"] = float(params.get("dmg_pct", 0.0))
	mods["speed_pct"] = float(params.get("speed_pct", 0.0))
	if _apply_to_caster_ball(caster_id, mods):
		return
	_pending_in_flight[caster_id] = {"mods": mods, "expires_at": _match_clock + 30.0}
	print("[TagEffect] 飞行球推进: 无在场球，登记 pending (caster=%d)" % caster_id)

## #14 拉回：本方飞行球朝投掷者拉回（max_times 次数在 pending/直接作用中各扣一次）
func _apply_ball_recall(params: Dictionary, caster_id: int) -> void:
	var max_times: int = maxi(1, int(params.get("max_times", 1)))
	var mods: Dictionary = {"recall": true, "max_times": max_times}
	if _apply_to_caster_ball(caster_id, mods):
		return
	_pending_in_flight[caster_id] = {"mods": mods, "expires_at": _match_clock + 30.0}
	print("[TagEffect] 拉回: 无在场球，登记 pending (caster=%d)" % caster_id)

## 波6 #14/#17 内部：把操作作用到施法者当前飞行球（存在且本方=true）
func _apply_to_caster_ball(caster_id: int, mods: Dictionary) -> bool:
	var caster := _get_caster(caster_id)
	var bm = battle_manager
	if bm == null:
		bm = get_node_or_null("/root/BattleManager")
	if caster == null or bm == null or bm.get("ball_node") == null:
		return false
	var ball = bm.get("ball_node")
	if not ball.is_active:
		return false
	if ball.attacker_player != caster:
		return false  # 非本人飞行球不作用
	if mods.has("recall"):
		if ball.has_method("recall_ball"):
			ball.recall_ball(int(mods.get("max_times", 1)))
			print("[TagEffect] 拉回: 作用中 (caster=%d)" % caster_id)
			return true
		return false
	if ball.has_method("boost_in_flight"):
		ball.boost_in_flight(mods)
		print("[TagEffect] 飞行球推进: dmg+%d%% speed+%d%% (caster=%d)" % [int(mods.get("dmg_pct", 0) * 100), int(mods.get("speed_pct", 0) * 100), caster_id])
		return true
	return false

## #17 手动制导：投球进入手动态（AI 路径=直线直飞，球侧按 is_player_controlled 分流）
func _apply_ball_manual_steering(params: Dictionary, caster_id: int) -> void:
	var mods: Dictionary = _ensure_ball_mods(caster_id)
	mods.manual_steering = true
	mods.manual_energy_per_sec = maxf(0.5, float(params.get("energy_per_sec", 3.0)))
	mods.manual_max_duration = maxf(0.5, float(params.get("max_duration", 3.0)))
	_mark_expiry(mods, ["manual_steering", "manual_energy_per_sec", "manual_max_duration"], float(params.get("duration", 0)))
	print("[TagEffect] 手动制导: 耗能=%.1f/s max=%.1fs (caster=%d)" % [mods.manual_energy_per_sec, mods.manual_max_duration, caster_id])

## #18 带人位移：命中后拖拽目标沿球方向位移
func _apply_ball_carry_push(params: Dictionary, caster_id: int) -> void:
	var mods: Dictionary = _ensure_ball_mods(caster_id)
	mods.carry_pull_speed = maxf(0.0, float(params.get("pull_speed", 200.0)))
	mods.carry_max_duration = maxf(0.1, float(params.get("max_duration", 1.0)))
	_mark_expiry(mods, ["carry_pull_speed", "carry_max_duration"], float(params.get("duration", 0)))
	print("[TagEffect] 带人位移: speed=%.0f max=%.1fs (caster=%d)" % [mods.carry_pull_speed, mods.carry_max_duration, caster_id])

## #9 视野迷雾：区域标记（AI 感知削弱消费）；spawn_at 可选，缺省鼠标路径
func _apply_field_vision_block(params: Dictionary, caster_id: int) -> void:
	var p: Dictionary = params.duplicate()
	p["zone_type"] = 5  # FieldEffectZone.ZoneType.VISION
	_apply_field_zone_effect(p, 5)
	print("[TagEffect] 视野迷雾: perception_scale=%.2f (caster=%d)" % [float(params.get("perception_scale", 0.5)), caster_id])


## ==================== 对场地效果 (预留) ====================

func _apply_field_obs_add(params: Dictionary) -> void:
	"""创造障碍标签：进入鼠标放置模式"""
	var manager = _get_obstacle_manager()
	if not manager:
		push_error("[TagEffectHandler] 找不到 ObstacleManager")
		return

	# 补充元素颜色
	if not params.has("element_color"):
		var element: String = params.get("element", "")
		params["element_color"] = _get_element_color(element)

	# 补充来源技能
	if not params.has("source_skill"):
		params["source_skill"] = params.get("skill_id", "")

	# 补充释放球员位置（月牙朝向用）
	var caster_node = _get_caster(params.get("caster_id", 0))
	if caster_node:
		params["caster_position"] = caster_node.global_position

	var mouse_ops: int = int(params.get("mouse_ops", 1))
	manager.start_placing(params, mouse_ops)

	print("[TagEffectHandler] 创造障碍: shape=%s hp=%.0f atk_consume=%.0f/s spd_consume=%.0fpx/s mouse_ops=%d" % [
		params.get("shape", "rect"), params.get("hp", 50.0),
		params.get("attack_consume_rate", 20.0), params.get("speed_consume_rate", 20.0),
		mouse_ops
	])


func _apply_field_obs_clear(params: Dictionary) -> void:
	"""清除障碍标签：进入鼠标清除模式"""
	var manager = _get_obstacle_manager()
	if not manager:
		push_error("[TagEffectHandler] 找不到 ObstacleManager")
		return

	var clear_count: int = int(params.get("clear_count", 1))
	var mouse_ops: int = int(params.get("mouse_ops", 1))
	manager.start_clearing(clear_count, mouse_ops)

	print("[TagEffectHandler] 清除障碍: clear_count=%d mouse_ops=%d" % [
		clear_count, mouse_ops
	])
	pass


## V1-2 体外实体盾（05 文档）：贴身自动生成，不走鼠标放置
## D1/D2 follow_mode=follow 跟随释放者/static 固定；D3 挡所有球；D4 durability_mode=uses|hp
func _apply_player_shield_obstacle(params: Dictionary, caster_id: int) -> void:
	var manager = _get_obstacle_manager()
	if not manager:
		push_error("[TagEffectHandler] 找不到 ObstacleManager")
		return
	var caster := _get_caster(caster_id)
	if not caster:
		print("[TagEffectHandler] 护盾: 找不到施法者")
		return

	var p: Dictionary = params.duplicate()
	p["caster_id"] = caster_id
	if not p.has("element_color"):
		p["element_color"] = _get_element_color(str(params.get("_element", params.get("element", ""))))
	if not p.has("source_skill"):
		p["source_skill"] = str(params.get("_skill_id", params.get("skill_id", "")))

	manager.create_player_shield(p, caster)
	print("[TagEffectHandler] 生成护盾: caster=%d follow=%s durability=%s hp=%.0f uses=%d duration=%.1f" % [
		caster_id, str(p.get("follow_mode", "follow")), str(p.get("durability_mode", "hp")),
		float(p.get("hp", 50.0)), int(p.get("uses", 1)), float(p.get("duration", 10.0))])
func _apply_field_obs_move(params: Dictionary) -> void:
	pass
func _apply_field_obs_lock(params: Dictionary) -> void:
	pass
func _apply_field_terra_change(params: Dictionary) -> void:
	pass
func _apply_field_terra_revert(params: Dictionary) -> void:
	pass
func _apply_field_zone_mark(params: Dictionary) -> void:
	pass
func _apply_field_zone_clear(params: Dictionary) -> void:
	pass
func _apply_field_zone_effect(params: Dictionary, zone_type: int) -> void:
	"""区域效果标签通用函数
	zone_type: 0=加速 1=减速 2=危险 3=安全
	V1-3（06 文档）：params.spawn_at="ball_land"|"ball_stop" → 登记落点 pending，球触地/停球时在落点生成；
	缺省 = 鼠标放置路径（原行为不变，E4）"""
	var manager = _get_field_zone_manager()
	if not manager:
		push_error("[TagEffectHandler] 找不到 FieldZoneManager")
		return

	var spawn_at: String = str(params.get("spawn_at", ""))
	if spawn_at == "ball_land" or spawn_at == "ball_stop":
		_register_pending_zone_spawn(params, zone_type, spawn_at)
		return

	var zone_params := _build_zone_params(params, zone_type)
	var mouse_ops: int = int(params.get("mouse_ops", 1))
	manager.start_placing(zone_params, mouse_ops)

	var type_names: Array = ["加速区", "减速区", "危险区", "安全区"]
	print("[TagEffectHandler] 区域效果: %s size=%.0f×%.0f dur=%.1fs mouse_ops=%d" % [
		type_names[zone_type],
		zone_params["width"], zone_params["height"],
		zone_params["duration"], mouse_ops
	])


## V1-3：构建区域参数（鼠标路径与落点路径共用；radius 兼容映射为方形尺寸）
func _build_zone_params(params: Dictionary, zone_type: int) -> Dictionary:
	var zone_params: Dictionary = {}
	zone_params["zone_type"] = zone_type
	var width: float = float(params.get("width", 0.0))
	var height: float = float(params.get("height", 0.0))
	if width <= 0.0 and height <= 0.0 and float(params.get("radius", 0.0)) > 0.0:
		width = float(params.get("radius", 0.0)) * 2.0
		height = width
	zone_params["width"] = width if width > 0.0 else 120.0
	zone_params["height"] = height if height > 0.0 else 120.0
	zone_params["duration"] = float(params.get("duration", 10.0))
	# 效果值：加速/减速=倍率，危险=每秒伤害，安全=无
	match zone_type:
		0:
			zone_params["effect_value"] = float(params.get("boost_multiplier", 1.5))
		1:
			zone_params["effect_value"] = float(params.get("slow_multiplier", 1.5))
		2:
			zone_params["effect_value"] = float(params.get("damage_value", 10.0))
		3:
			zone_params["effect_value"] = 0.0
		4:
			zone_params["effect_value"] = float(params.get("heal_per_sec", 5.0))  # 波5 #3 治疗区
	# 波5 #12 zone 作用于球：affect_ball 透传（可选）
	if params.has("affect_ball"):
		zone_params["affect_ball"] = params.get("affect_ball")
	if not params.has("source_skill"):
		zone_params["source_skill"] = params.get("_skill_id", params.get("skill_id", ""))
	return zone_params


## ==================== V1-3 落点区域 pending（06 文档）====================

var _pending_zone_spawns: Array[Dictionary] = []  # [{zone_type, zone_params, spawn_at, expires_at}]
var _ball_hooks_connected: bool = false
# 波6 #14 飞行中球操作 pending {caster_id: {mods, expires_at}}（无在场球时登记，ATTACK_LAUNCHED 消费）
var _pending_in_flight: Dictionary = {}
var _in_flight_hooks_connected: bool = false


func _register_pending_zone_spawn(params: Dictionary, zone_type: int, spawn_at: String) -> void:
	_ensure_ball_landing_hooks()
	_pending_zone_spawns.append({
		"zone_type": zone_type,
		"zone_params": _build_zone_params(params, zone_type),
		"spawn_at": spawn_at,
		"expires_at": _match_clock + 30.0,
	})
	print("[TagEffectHandler] 登记落点区域: type=%d spawn_at=%s pending=%d" % [zone_type, spawn_at, _pending_zone_spawns.size()])


## 惰性连接球落点钩子（经 battle_manager 注入的 ball_node，与 spirit_system 既有引用链一致）
func _ensure_ball_landing_hooks() -> void:
	if _ball_hooks_connected:
		return
	var bm = battle_manager
	if bm == null:
		bm = get_node_or_null("/root/BattleManager")
	if bm == null or bm.get("ball_node") == null:
		return
	var ball = bm.get("ball_node")
	if ball.has_signal("ball_first_land") and not ball.ball_first_land.is_connected(_on_ball_first_land):
		ball.ball_first_land.connect(_on_ball_first_land)
	if ball.has_signal("ball_stopped") and not ball.ball_stopped.is_connected(_on_ball_stopped):
		ball.ball_stopped.connect(_on_ball_stopped)
	_ball_hooks_connected = true
	print("[TagEffectHandler] 已连接球落点钩子")


func _on_ball_first_land(pos: Vector2) -> void:
	_consume_pending_zone_spawns("ball_land", pos)


func _on_ball_stopped(pos: Vector2) -> void:
	_consume_pending_zone_spawns("ball_stop", pos)


func _consume_pending_zone_spawns(trigger: String, pos: Vector2) -> void:
	var manager = _get_field_zone_manager()
	if not manager:
		return
	var remaining: Array[Dictionary] = []
	for item in _pending_zone_spawns:
		if item["spawn_at"] == trigger:
			manager.spawn_zone_at(int(item["zone_type"]), pos, item["zone_params"].duplicate())
			print("[TagEffectHandler] 落点区域生成: type=%d at=%s" % [int(item["zone_type"]), str(pos.round())])
		else:
			remaining.append(item)
	_pending_zone_spawns = remaining


## pending 过期清理（球被接住/未落地 30s 兜底，防泄漏；06 断言4）
func _cleanup_expired_zone_spawns() -> void:
	var remaining: Array[Dictionary] = []
	for item in _pending_zone_spawns:
		if _match_clock < float(item["expires_at"]):
			remaining.append(item)
	_pending_zone_spawns = remaining


## 波6 #14：飞行球 pending 过期清理 + ATTACK_LAUNCHED 订阅（一次）
func _cleanup_pending_in_flight() -> void:
	_ensure_in_flight_hooks()
	var to_del: Array = []
	for caster_id in _pending_in_flight:
		if _match_clock >= float(_pending_in_flight[caster_id]["expires_at"]):
			to_del.append(caster_id)
	for c in to_del:
		_pending_in_flight.erase(c)


func _ensure_in_flight_hooks() -> void:
	if _in_flight_hooks_connected:
		return
	var bus = get_tree().get_first_node_in_group("battle_event_bus") if is_inside_tree() else null
	if bus == null:
		return
	bus.subscribe(BattleEventBus.GameEvent.ATTACK_LAUNCHED, _on_attack_launched)
	_in_flight_hooks_connected = true


## 波6 #14：本方球飞出 → 消费 pending（作用到刚出发的球）
func _on_attack_launched(payload: Dictionary) -> void:
	var attacker = payload.get("attacker", null)
	if attacker == null:
		return
	var caster_id: int = attacker.get_instance_id()
	if not _pending_in_flight.has(caster_id):
		return
	var mods: Dictionary = _pending_in_flight[caster_id]["mods"]
	_pending_in_flight.erase(caster_id)
	var ball = null
	var bm = battle_manager
	if bm == null:
		bm = get_node_or_null("/root/BattleManager")
	if bm != null and bm.get("ball_node") != null:
		ball = bm.get("ball_node")
	elif attacker.get("ball_ref") != null:
		ball = attacker.get("ball_ref")
	if ball == null:
		return
	if mods.has("recall"):
		if ball.has_method("recall_ball"):
			ball.recall_ball(int(mods.get("max_times", 1)))
	else:
		if ball.has_method("boost_in_flight"):
			ball.boost_in_flight(mods)
	# 连带清理过期项
	_cleanup_pending_in_flight()


func _apply_field_illusion_add(params: Dictionary) -> void:
	"""幻象生成标签：进入鼠标放置模式
	params: place_mode(any/near), count, stamina, duration, ai_mode, source_player"""
	var manager = _get_illusion_manager()
	if not manager:
		push_error("[TagEffectHandler] 找不到 IllusionManager")
		return

	var source: CharacterBody2D = params.get("source_player", null)
	if not source or not is_instance_valid(source):
		push_error("[TagEffectHandler] 幻象缺少 source_player")
		return

	var mouse_ops: int = int(params.get("count", 1))
	manager.start_placing(params, mouse_ops)

	print("[TagEffectHandler] 幻象生成: mode=%s count=%d stamina=%.0f dur=%.1fs ai=%s" % [
		str(params.get("place_mode", "any")), mouse_ops,
		float(params.get("stamina", source.max_stamina)),
		float(params.get("duration", 10.0)),
		str(params.get("ai_mode", false))
	])


func _apply_field_illusion_clear(params: Dictionary) -> void:
	"""幻象破除标签：释放后直接清除场上所有幻象（无鼠标系统）"""
	var manager = _get_illusion_manager()
	if not manager:
		push_error("[TagEffectHandler] 找不到 IllusionManager")
		return
	manager.clear_all_illusions()
	print("[TagEffectHandler] 幻象破除: 清除场上所有幻象")


## ==================== 辅助方法 ====================

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


## === ①属性类通用 ===
func _apply_player_stat_buff(params: Dictionary, caster_id: int, stat: String, mult: float, flat: float) -> void:
	var targets := _get_player_targets(params, caster_id)
	var duration: float = float(params.get("duration", 5.0))
	for target in targets:
		# 读取并消费双倍/减半倍率（来自 player_spirit_double/half 标签）
		var skill_mult: float = target.get_and_consume_next_skill_mult()
		var final_mult: float = 1.0 + (mult - 1.0) * skill_mult
		var final_flat: float = flat * skill_mult
		_effect_counter += 1
		var buff_id: String = "stat_%d_%s_%d" % [_effect_counter, stat, target.get_instance_id()]
		target.add_buff(buff_id, stat, final_mult, final_flat, duration, params.get("_tag_id", ""))
		if skill_mult != 1.0:
			print("[TagEffect] 双倍/减半生效: skill_mult=%.2f -> mult=%.2f flat=%.1f" % [skill_mult, final_mult, final_flat])
		print("[TagEffect] 属性buff: stat=%s mult=%.2f flat=%.1f dur=%.1fs target=%s" % [stat, final_mult, final_flat, duration, target.char_data.get("name", "?")])


## === ②状态类通用 ===
func _apply_player_status(params: Dictionary, caster_id: int, status: String) -> void:
	var targets := _get_player_targets(params, caster_id)
	var duration: float = float(params.get("duration", 3.0))
	# 波3 #21 受击解除（参数式组合用法）：状态自带 break_on_hit:true → 受击即解
	var extra: Dictionary = {}
	if params.get("break_on_hit", false):
		extra["break_on_hit"] = true
	for target in targets:
		var ok: bool = target.turn_on_light(status, duration, extra)
		if not ok:
			print("[TagEffect] %s 被免控挡住: target=%s" % [status, target.char_data.get("name", "?")])
	print("[TagEffect] 状态: %s dur=%.1fs targets=%d" % [status, duration, targets.size()])


## === 易伤 ===
func _apply_player_vulnerable(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var duration: float = float(params.get("duration", 3.0))
	var mult: float = float(params.get("multiplier", 1.5))
	for target in targets:
		target.turn_on_light("vulnerable", duration, {"multiplier": mult})
	print("[TagEffect] 易伤: mult=%.1f dur=%.1fs targets=%d" % [mult, duration, targets.size()])


## === 显形 ===
func _apply_player_reveal(params: Dictionary, caster_id: int) -> void:
	var caster := _get_caster(caster_id)
	if not caster:
		return
	var enemies := _get_all_enemies(caster)
	var count: int = 0
	for e in enemies:
		if e.is_status_active("stealthed"):
			e.turn_off_light("stealthed")
			count += 1
	print("[TagEffect] 显形: %d个隐身目标" % count)


## ==================== 波3 球员管道变体（09 工单）====================

## #11 禁疗/禁能：block="heal"/"energy"/"both"（默认 both，蝰蛇毒咬口径）
func _apply_player_heal_block(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var duration: float = float(params.get("duration", 3.0))
	var block: String = str(params.get("block", "both"))
	for target in targets:
		if block == "heal" or block == "both":
			target.turn_on_light("heal_block", duration)
		if block == "energy" or block == "both":
			target.turn_on_light("energy_block", duration)
	print("[TagEffect] 禁疗/禁能: block=%s dur=%.1fs targets=%d" % [block, duration, targets.size()])

## #5 反伤：攻击者受伤 = value 固定 + 实际伤害×pct
func _apply_player_reflect(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var duration: float = float(params.get("duration", 4.0))
	var value: float = float(params.get("value", 0.0))
	var pct: float = float(params.get("pct", 0.0))
	for target in targets:
		target.turn_on_light("reflect", duration, {"value": value, "pct": pct})
	print("[TagEffect] 反伤: value=%.0f pct=%.2f dur=%.1fs targets=%d" % [value, pct, duration, targets.size()])

## #16 元素免疫/弱点：对指定元素攻击 ×multiplier（0=免疫，1.5=弱点）
func _apply_player_element_shield(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var duration: float = float(params.get("duration", 4.0))
	var elements: Array = params.get("elements", [])
	var multiplier: float = float(params.get("multiplier", 0.0))
	for target in targets:
		target.turn_on_light("element_immune", duration, {"elements": elements, "multiplier": multiplier})
	print("[TagEffect] 元素免疫/弱点: elements=%s mult=%.1f dur=%.1fs targets=%d" % [str(elements), multiplier, duration, targets.size()])

## #19 能量分摊：队友替施法者分摊能耗（trigger._consume_energy 消费）
func _apply_player_energy_share(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var duration: float = float(params.get("duration", 5.0))
	var share_pct: float = float(params.get("share_pct", 0.5))
	for target in targets:
		target.turn_on_light("energy_share", duration, {"share_pct": share_pct})
	print("[TagEffect] 能量分摊: share=%.0f%% dur=%.1fs targets=%d" % [share_pct * 100.0, duration, targets.size()])

## #20 储存多段：充能容器（消费时机由技能组合层定，本原语只造容器）
func _apply_player_charge_stock(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var duration: float = float(params.get("duration", 10.0))
	var charges: int = maxi(1, int(params.get("charges", 1)))
	for target in targets:
		target.turn_on_light("charge_stock", duration, {"charges": charges})
	print("[TagEffect] 充能容器: charges=%d dur=%.1fs targets=%d" % [charges, duration, targets.size()])

## #21 受击解除：给目标已在亮的匹配状态打 break_on_hit 标记（statuses 空=全部控制类）
func _apply_player_on_hit_expire(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var statuses: Array = params.get("statuses", [])
	var total: int = 0
	for target in targets:
		total += target.mark_lights_break_on_hit(statuses)
	print("[TagEffect] 受击解除标记: statuses=%s marked=%d targets=%d" % [str(statuses), total, targets.size()])


## ==================== 波5（11 工单）====================

## #10 叠层印记：命中目标 +1 层（封顶刷新）；达阈值触发引用标签；触发后按参数清层
func _apply_player_mark_apply(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var mark_id: String = str(params.get("mark_id", "mark"))
	var max_stacks: int = maxi(1, int(params.get("max_stacks", 3)))
	var duration: float = float(params.get("duration", 5.0))
	var threshold_count: int = int(params.get("threshold_count", 0))
	var threshold_tag: String = str(params.get("threshold_tag", ""))
	var clear_on_trigger: bool = bool(params.get("clear_on_trigger", false))
	var threshold_params: Dictionary = params.get("threshold_params", {})
	for target in targets:
		if not target.has_method("apply_mark"):
			continue
		var count: int = target.apply_mark(mark_id, max_stacks, duration)
		print("[TagEffect] 印记: %s 第%d/%d层 target=%s" % [mark_id, count, max_stacks, target.char_data.get("name", "?")])
		if threshold_count > 0 and count >= threshold_count and threshold_tag != "":
			# 阈值触发：对带印记目标触发引用标签（递归走统一入口）
			apply_tag_effect(threshold_tag, threshold_params.duplicate(), target.get_instance_id())
			print("[TagEffect] 印记阈值触发: %s ×%d → %s" % [mark_id, count, threshold_tag])
			if clear_on_trigger:
				target.clear_mark(mark_id)

## #13 toggle：状态标签 → 状态灯名映射（toggle 开关用；v1 仅支持状态灯类标签可精确撤销）
const TOGGLE_STATUS_MAP: Dictionary = {
	"player_stealth": "stealthed",
	"player_invincible": "invincible",
	"player_atk_up_pct": "atk_up_toggle",
	"player_def_up_pct": "def_up_toggle",
	"player_spd_up_pct": "spd_up_toggle",
}


## #3 治疗区：zone_type=4 由 _apply_field_zone_effect 构建映射消费（heal_per_sec）


## === 体力恢复/扣除(%) ===
func _apply_player_hp_heal_pct(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var pct: float = float(params.get("value", 20)) / 100.0
	for target in targets:
		if target.is_status_active("heal_block"):
			continue  # 波3 #11 禁疗：灯亮治疗无效
		var skill_mult: float = target.get_and_consume_next_skill_mult()
		var heal: float = target.max_stamina * pct * skill_mult
		target.stamina = min(target.max_stamina, target.stamina + heal)

func _apply_player_hp_damage_pct(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var pct: float = float(params.get("value", 20)) / 100.0
	for target in targets:
		if target.is_status_active("invincible"):
			continue
		var skill_mult: float = target.get_and_consume_next_skill_mult()
		var dmg: float = target.max_stamina * pct * skill_mult
		target.stamina = max(0.0, target.stamina - dmg)
		if target.stamina <= 0.0 and not target.is_defeated:
			target._on_defeated()


## === 体力恢复/扣除(固定) ===
func _apply_player_hp_heal_flat(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var val: float = float(params.get("value", 30))
	for target in targets:
		if target.is_status_active("heal_block"):
			continue  # 波3 #11 禁疗：灯亮治疗无效
		var skill_mult: float = target.get_and_consume_next_skill_mult()
		target.stamina = min(target.max_stamina, target.stamina + val * skill_mult)

func _apply_player_hp_damage_flat(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var val: float = float(params.get("value", 30))
	for target in targets:
		if target.is_status_active("invincible"):
			continue
		var skill_mult: float = target.get_and_consume_next_skill_mult()
		target.stamina = max(0.0, target.stamina - val * skill_mult)
		if target.stamina <= 0.0 and not target.is_defeated:
			target._on_defeated()


## === ③持续类 ===
func _apply_player_hp_regen(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var rate: float = float(params.get("value", 5))
	var duration: float = float(params.get("duration", 5.0))
	for target in targets:
		# 读取并消费双倍/减半倍率（来自 player_spirit_double/half 标签）
		var skill_mult: float = target.get_and_consume_next_skill_mult()
		target.add_tick_effect("hp_regen_%d" % target.get_instance_id(), "regen", rate * skill_mult, duration)
		if skill_mult != 1.0:
			print("[TagEffect] 持续恢复双倍/减半生效: rate=%.1f × %.2f = %.1f/s" % [rate, skill_mult, rate * skill_mult])
	print("[TagEffect] 持续恢复: rate=%.1f/s dur=%.1fs" % [rate, duration])

func _apply_player_hp_dot(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var rate: float = float(params.get("value", 5))
	var duration: float = float(params.get("duration", 5.0))
	for target in targets:
		# 读取并消费双倍/减半倍率（来自 player_spirit_double/half 标签）
		var skill_mult: float = target.get_and_consume_next_skill_mult()
		# 思想2：数值层相互影响 - 绑定攻击力属性
		target.add_tick_effect("hp_dot_%d" % target.get_instance_id(), "dot", rate * skill_mult, duration, ["attack"])
		if skill_mult != 1.0:
			print("[TagEffect] 持续掉血双倍/减半生效: rate=%.1f × %.2f = %.1f/s" % [rate, skill_mult, rate * skill_mult])
	print("[TagEffect] 持续掉血: rate=%.1f/s dur=%.1fs" % [rate, duration])


## === 解控 ===
func _apply_player_unroot(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	for target in targets:
		target.turn_off_light("rooted")
	print("[TagEffect] 解控: targets=%d" % targets.size())


## === 能量恢复/消耗(%) ===
func _apply_player_energy_pct(params: Dictionary, caster_id: int, is_gain: bool) -> void:
	var targets := _get_player_targets(params, caster_id)
	var pct: float = float(params.get("value", 20)) / 100.0
	for target in targets:
		var skill_mult: float = target.get_and_consume_next_skill_mult()
		var amt: float = target.max_spirit_energy * pct * skill_mult
		if is_gain:
			target.spirit_energy = min(target._get_effective_value("max_energy", target.max_spirit_energy), target.spirit_energy + amt)
		else:
			target.spirit_energy = max(0.0, target.spirit_energy - amt)


## === 能量恢复/消耗(固定) ===
func _apply_player_energy_flat(params: Dictionary, caster_id: int, is_gain: bool) -> void:
	var targets := _get_player_targets(params, caster_id)
	var val: float = float(params.get("value", 20))
	for target in targets:
		var skill_mult: float = target.get_and_consume_next_skill_mult()
		if is_gain:
			target.spirit_energy = min(target._get_effective_value("max_energy", target.max_spirit_energy), target.spirit_energy + val * skill_mult)
		else:
			target.spirit_energy = max(0.0, target.spirit_energy - val * skill_mult)


## === ④折扣类 ===
## multiplier 直接代表最终倍率: down传<1(如0.8减耗20%), up传>1(如1.2增耗20%)
## is_down 仅用于日志显示, 不再反转数值(避免传入>1值时算反)
func _apply_player_spirit_cost(params: Dictionary, caster_id: int, is_down: bool) -> void:
	var targets := _get_player_targets(params, caster_id)
	var mult: float = float(params.get("multiplier", 0.8 if is_down else 1.2))
	var duration: float = float(params.get("duration", 5.0))
	for target in targets:
		target.add_skill_cost_mult("spirit_cost_%d" % target.get_instance_id(), max(0.1, mult), duration)
	print("[TagEffect] 消耗%s: mult=%.2f dur=%.1fs" % ["减少" if is_down else "增加", mult, duration])

func _apply_player_spirit_cd(params: Dictionary, caster_id: int, is_down: bool) -> void:
	var targets := _get_player_targets(params, caster_id)
	var mult: float = float(params.get("multiplier", 0.8 if is_down else 1.2))
	var duration: float = float(params.get("duration", 5.0))
	for target in targets:
		target.add_skill_cd_mult("spirit_cd_%d" % target.get_instance_id(), max(0.1, mult), duration)
	print("[TagEffect] CD%s: mult=%.2f dur=%.1fs" % ["缩短" if is_down else "延长", mult, duration])

func _apply_player_spirit_uses(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var bonus: int = int(params.get("bonus_uses", 1))
	var skill_id: String = str(params.get("skill_id", ""))
	for target in targets:
		if skill_id != "":
			target.add_skill_bonus_uses(skill_id, bonus)
		else:
			for sid in target.equipped_skills:
				target.add_skill_bonus_uses(str(sid), bonus)

func _apply_player_spirit_double(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	for target in targets:
		target.add_next_skill_mult(2.0)
	print("[TagEffect] 下次技能效果翻倍")

func _apply_player_spirit_half(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	for target in targets:
		target.add_next_skill_mult(0.5)
	print("[TagEffect] 下次技能效果减半")


## === ⑤交互类 ===
func _apply_player_teleport(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var pos_x: float = float(params.get("pos_x", 0))
	var pos_y: float = float(params.get("pos_y", 0))
	for target in targets:
		if target.has_method("teleport_to"):
			target.teleport_to(Vector2(pos_x, pos_y))

func _apply_player_return(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	for target in targets:
		if target.has_method("return_to_previous"):
			target.return_to_previous()


## 获取所有敌方（含隐身，用于显形等不需要过滤的场景）
func _get_all_enemies(caster: CharacterBody2D) -> Array:
	var result: Array = []
	var enemy_team: String = "b" if caster.team == "a" else "a"
	for p in players:
		if p and is_instance_valid(p) and p.team == enemy_team and not p.is_defeated:
			result.append(p)
	return result
