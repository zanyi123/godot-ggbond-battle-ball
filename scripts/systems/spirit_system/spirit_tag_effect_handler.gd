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

# 球的临时修饰符（发球时生效，球落地/回收时清空）
var _ball_mods: Dictionary = {
	"dmg_mult": 1.0,        # 伤害倍率
	"dmg_flat": 0.0,        # 伤害固定加减
	"speed_mult": 1.0,      # 速度倍率
	"speed_flat": 0.0,      # 速度固定加减
	"range_mult": 1.0,      # 飞行距离倍率
	"range_flat": 0.0,      # 飞行距离固定加减
	"penetrate": false,      # 穿透
	"armor": 0.0,           # 护甲值（抵消伤害）
	"tracking_target": null, # 追踪目标节点
	"tracking_turn_speed": 0.0,
	"boomerang": false,      # 回旋
	"boomerang_triggered": false,
	"boomerang_return_dir": Vector2.ZERO,
	"boomerang_dist": 0.0,
	"lock_straight": false,  # 直行（禁用其他轨迹）
	"spread_done": false,    # 扩散已触发
	"aoe_radius": 0.0,       # AOE半径
	"aoe_damage_pct": 0.5,   # AOE伤害百分比
	"lockon_target": null,   # 精准锁定目标
}


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
	# B-30 穿透/范围层
	_tag_priority["ball_penetrate"] = 31
	_tag_priority["ball_range_up"] = 32
	_tag_priority["ball_range_down"] = 33

	# === FIELD类 ===
	# F-10 障碍层
	_tag_priority["field_obs_add"] = 101
	_tag_priority["field_obs_clear"] = 102
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

## 发球前重置所有修饰符
func reset_ball_mods() -> void:
	_ball_mods = {
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
	}

## 获取修饰后的球伤害
func get_modified_ball_damage(base_damage: float) -> float:
	var result: float = (base_damage + _ball_mods.dmg_flat) * _ball_mods.dmg_mult
	result = max(0.0, result - _ball_mods.armor)
	return result

## 获取修饰后的球速度
func get_modified_ball_speed(base_speed: float) -> float:
	return (base_speed + _ball_mods.speed_flat) * _ball_mods.speed_mult

## 获取修饰后的飞行距离
func get_modified_ball_range(base_range: float) -> float:
	return (base_range + _ball_mods.range_flat) * _ball_mods.range_mult

## 球是否穿透
func is_ball_penetrating() -> bool:
	return _ball_mods.penetrate

## 球是否回旋
func is_ball_boomerang() -> bool:
	return _ball_mods.boomerang and not _ball_mods.lock_straight

## 球是否追踪
func is_ball_tracking() -> bool:
	return _ball_mods.tracking_target != null and not _ball_mods.lock_straight

## 获取追踪目标
func get_tracking_target() -> Node:
	return _ball_mods.tracking_target

## 获取追踪转向速度
func get_tracking_turn_speed() -> float:
	return _ball_mods.tracking_turn_speed

## 球是否有AOE范围伤害
func has_ball_aoe() -> bool:
	return _ball_mods.has("aoe_radius") and _ball_mods.aoe_radius > 0.0

## 获取AOE半径
func get_ball_aoe_radius() -> float:
	return _ball_mods.get("aoe_radius", 0.0)

## 获取AOE伤害百分比
func get_ball_aoe_damage_pct() -> float:
	return _ball_mods.get("aoe_damage_pct", 0.5)

## 球回旋触发（ball.gd 飞到一半距离时调用）
func trigger_boomerang(current_dir: Vector2) -> Vector2:
	if _ball_mods.boomerang_triggered:
		return Vector2.ZERO
	_ball_mods.boomerang_triggered = true
	_ball_mods.boomerang_return_dir = -current_dir
	return _ball_mods.boomerang_return_dir


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

	# === 对球效果 ===
	match tag_id:
		# 数值类 (01-08)
		"ball_dmg_up_pct":
			_apply_ball_dmg_up(params)
			success = true
		"ball_dmg_down_pct":
			_apply_ball_dmg_down(params)
			success = true
		"ball_dmg_up_flat":
			var flat_params_up: Dictionary = params.duplicate()
			flat_params_up["value_type"] = "flat"
			_apply_ball_dmg_up(flat_params_up)
			success = true
		"ball_dmg_down_flat":
			var flat_params_down: Dictionary = params.duplicate()
			flat_params_down["value_type"] = "flat"
			_apply_ball_dmg_down(flat_params_down)
			success = true
		"ball_speed_up_pct":
			_apply_ball_speed_up(params)
			success = true
		"ball_speed_down_pct":
			_apply_ball_speed_down(params)
			success = true
		"ball_speed_up_flat":
			_apply_ball_speed_up(params)
			success = true
		"ball_speed_down_flat":
			_apply_ball_speed_down(params)
			success = true
		# 飞行行为类 (09-14)
		"ball_tracking":
			_apply_ball_tracking(params, caster_id)
			success = true
		"ball_avoid":
			success = true  # 避障待场地系统
		"ball_boomerang":
			_apply_ball_boomerang(params)
			success = true
		"ball_straight":
			_apply_ball_straight(params)
			success = true
		"ball_lockon":
			_apply_ball_lockon(params, caster_id)
			success = true
		"ball_spread":
			success = true  # 扩散在球碰撞时处理
		# 穿透/范围类 (15-17)
		"ball_penetrate":
			_apply_ball_penetrate(params)
			success = true
		"ball_range_up":
			_apply_ball_range_up(params)
			success = true
		"ball_range_down":
			_apply_ball_range_down(params)
			success = true
		# 对场地标签 (已实现2个 + 预留10个)
		"field_obs_add":
			_apply_field_obs_add(params)
			success = true
		"field_obs_clear":
			_apply_field_obs_clear(params)
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
	# 优先级队列窗口计时
	if _flush_timer > 0.0:
		_flush_timer -= delta
		if _flush_timer <= 0.0:
			_flush_pending_tags()

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
func _apply_ball_dmg_up(params: Dictionary) -> void:
	var val: float = float(params.get("value", 0))
	var vtype: String = str(params.get("value_type", "percentage"))
	var dur: float = float(params.get("duration", 0))

	if vtype == "percentage":
		_ball_mods.dmg_mult += val / 100.0
	else:
		_ball_mods.dmg_flat += val
	print("[TagEffect] 增伤: type=%s val=%.1f mult=%.2f flat=%.1f" % [vtype, val, _ball_mods.dmg_mult, _ball_mods.dmg_flat])

## 02 减伤
func _apply_ball_dmg_down(params: Dictionary) -> void:
	var val: float = float(params.get("value", 0))
	var vtype: String = str(params.get("value_type", "percentage"))

	if vtype == "percentage":
		_ball_mods.dmg_mult -= val / 100.0
	else:
		_ball_mods.dmg_flat -= val
	_ball_mods.dmg_mult = max(0.0, _ball_mods.dmg_mult)
	print("[TagEffect] 减伤: mult=%.2f flat=%.1f" % [_ball_mods.dmg_mult, _ball_mods.dmg_flat])

## 03 穿透 — params: {duration}
func _apply_ball_penetrate(params: Dictionary) -> void:
	_ball_mods.penetrate = true
	print("[TagEffect] 穿透: 启用")

## 04 护甲 — params: {value_type, value, duration}
func _apply_ball_armor(params: Dictionary) -> void:
	var val: float = float(params.get("value", 0))
	_ball_mods.armor += val
	print("[TagEffect] 护甲: armor=%.1f" % _ball_mods.armor)

## 05 加速 — params: {multiplier, value(固定值), duration}
func _apply_ball_speed_up(params: Dictionary) -> void:
	var mult: float = float(params.get("multiplier", 0))
	# 兼容 registry 的 value 字段(ball_speed_up_flat 用 value)
	var fixed: float = float(params.get("value", params.get("fixed_value", 0)))

	if mult > 0:
		_ball_mods.speed_mult *= mult
	if fixed != 0:
		_ball_mods.speed_flat += fixed
	print("[TagEffect] 球加速: mult=%.2f flat=%.1f" % [_ball_mods.speed_mult, _ball_mods.speed_flat])

## 06 减速
func _apply_ball_speed_down(params: Dictionary) -> void:
	var mult: float = float(params.get("multiplier", 0))
	var fixed: float = float(params.get("value", params.get("fixed_value", 0)))

	if mult > 0:
		_ball_mods.speed_mult /= mult
	if fixed != 0:
		_ball_mods.speed_flat -= fixed
	_ball_mods.speed_mult = max(0.1, _ball_mods.speed_mult)
	print("[TagEffect] 球减速: mult=%.2f flat=%.1f" % [_ball_mods.speed_mult, _ball_mods.speed_flat])

## 07 范围扩大/AOE — params: {radius, damage_pct, multiplier(兼容)}
## registry 定义: radius=AOE半径, damage_pct=范围伤害比(0-1)
func _apply_ball_range_up(params: Dictionary) -> void:
	var radius: float = float(params.get("radius", 0))
	var dmg_pct: float = float(params.get("damage_pct", 0))
	var mult: float = float(params.get("multiplier", 0))
	# 设置 AOE 半径和伤害比(供 ball.gd 的 has_ball_aoe/get_ball_aoe_radius 使用)
	if radius > 0:
		_ball_mods.aoe_radius = radius
	if dmg_pct > 0:
		_ball_mods.aoe_damage_pct = dmg_pct
	if mult > 0:
		_ball_mods.range_mult *= mult
	print("[TagEffect] 范围扩大/AOE: radius=%.1f dmg_pct=%.2f mult=%.2f" % [_ball_mods.aoe_radius, _ball_mods.aoe_damage_pct, _ball_mods.range_mult])

## 08 范围缩小
func _apply_ball_range_down(params: Dictionary) -> void:
	var mult: float = float(params.get("multiplier", 0))
	if mult > 0:
		_ball_mods.range_mult /= mult
	_ball_mods.range_mult = max(0.1, _ball_mods.range_mult)
	print("[TagEffect] 范围缩小: mult=%.2f" % _ball_mods.range_mult)

## 09 精准锁定 — 锁定最近敌人方向
func _apply_ball_lockon(params: Dictionary, caster_id: int) -> void:
	# 锁定在发球时处理：设置 ball_direction 指向最近敌人
	var caster := _get_caster(caster_id)
	if caster:
		var target := _get_nearest_enemy(caster)
		if target:
			_ball_mods.lockon_target = target
			print("[TagEffect] 精准锁定: 目标=%s" % target.char_data.get("name", "?"))
		else:
			print("[TagEffect] 精准锁定: 无目标")
	else:
		print("[TagEffect] 精准锁定: 找不到施法者")

## 10 扩散效果 — 碰撞时分裂
## 扩散标记已设，ball.gd 碰撞时检查 _ball_mods.spread_done

## 11 追踪 — 持续追踪目标
func _apply_ball_tracking(params: Dictionary, caster_id: int) -> void:
	var caster := _get_caster(caster_id)
	if not caster:
		print("[TagEffect] 追踪: 找不到施法者")
		return
	var target := _get_nearest_enemy(caster)
	if target:
		_ball_mods.tracking_target = target
		_ball_mods.tracking_turn_speed = float(params.get("turn_speed", 3.0))
		print("[TagEffect] 追踪: 目标=%s 转速=%.1f" % [target.char_data.get("name", "?"), _ball_mods.tracking_turn_speed])
	else:
		print("[TagEffect] 追踪: 无目标")

## 12 避障 — 待场地系统实现
## 标记已存在，ball.gd 可检查 _ball_mods["avoid"]

## 13 回旋 — 飞到一半距离时返回
func _apply_ball_boomerang(params: Dictionary) -> void:
	_ball_mods.boomerang = true
	_ball_mods.boomerang_dist = float(params.get("return_distance", 0.5))
	print("[TagEffect] 回旋: 启用 返回点=%.0f%%" % (_ball_mods.boomerang_dist * 100))

## 14 直行 — 禁用所有轨迹修改
func _apply_ball_straight(params: Dictionary) -> void:
	_ball_mods.lock_straight = true
	# 清除追踪和回旋
	_ball_mods.tracking_target = null
	_ball_mods.boomerang = false
	print("[TagEffect] 直行: 启用，禁用追踪/回旋")


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
	"""区域效果标签通用函数：进入鼠标放置模式
	zone_type: 0=加速 1=减速 2=危险 3=安全"""
	var manager = _get_field_zone_manager()
	if not manager:
		push_error("[TagEffectHandler] 找不到 FieldZoneManager")
		return

	# 构建区域参数
	var zone_params: Dictionary = {}
	zone_params["zone_type"] = zone_type
	zone_params["width"] = float(params.get("width", 120.0))
	zone_params["height"] = float(params.get("height", 120.0))
	zone_params["duration"] = float(params.get("duration", 10.0))

	# 效果值：加速/减速=倍率，危险=每秒伤害，安全=无
	match zone_type:
		0:  # 加速
			zone_params["effect_value"] = float(params.get("boost_multiplier", 1.5))
		1:  # 减速
			zone_params["effect_value"] = float(params.get("slow_multiplier", 1.5))
		2:  # 危险
			zone_params["effect_value"] = float(params.get("damage_value", 10.0))
		3:  # 安全
			zone_params["effect_value"] = 0.0

	# 补充来源技能
	if not params.has("source_skill"):
		zone_params["source_skill"] = params.get("skill_id", "")

	var mouse_ops: int = int(params.get("mouse_ops", 1))
	manager.start_placing(zone_params, mouse_ops)

	var type_names: Array = ["加速区", "减速区", "危险区", "安全区"]
	print("[TagEffectHandler] 区域效果: %s size=%.0f×%.0f dur=%.1fs mouse_ops=%d" % [
		type_names[zone_type],
		zone_params["width"], zone_params["height"],
		zone_params["duration"], mouse_ops
	])
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
	for target in targets:
		var ok: bool = target.turn_on_light(status, duration)
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


## === 体力恢复/扣除(%) ===
func _apply_player_hp_heal_pct(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var pct: float = float(params.get("value", 20)) / 100.0
	for target in targets:
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
