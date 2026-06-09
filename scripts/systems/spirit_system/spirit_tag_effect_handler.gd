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
	print("[TagEffect] 执行标签: %s params=%s" % [tag_id, params])

	var success := false

	# === 对球效果 ===
	match tag_id:
		# 数值类 (01-08)
		"ball_dmg_up_pct":
			_apply_ball_dmg_up_pct(params)
			success = true
		"ball_dmg_down_pct":
			_apply_ball_dmg_down_pct(params)
			success = true
		"ball_dmg_up_flat":
			_apply_ball_dmg_up_flat(params)
			success = true
		"ball_dmg_down_flat":
			_apply_ball_dmg_down_flat(params)
			success = true
		"ball_speed_up_pct":
			_apply_ball_speed_up_pct(params)
			success = true
		"ball_speed_down_pct":
			_apply_ball_speed_down_pct(params)
			success = true
		"ball_speed_up_flat":
			_apply_ball_speed_up_flat(params)
			success = true
		"ball_speed_down_flat":
			_apply_ball_speed_down_flat(params)
			success = true
		# 飞行行为类 (09-15)
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
		"ball_penetrate":
			_apply_ball_penetrate(params)
			success = true
		# 范围类 (16-17)
		"ball_range_up":
			_apply_ball_range_up(params)
			success = true
		"ball_range_down":
			_apply_ball_range_down(params)
			success = true
		# 对场地标签 - 障碍
		"field_obs_add":
			_apply_field_obs_add(params)
			success = true
		"field_obs_clear":
			_apply_field_obs_clear(params)
			success = true
		# 对场地标签 - 地形/区域/幻象
		"field_terra_change":
			_apply_field_terra_change(params)
			success = true
		"field_terra_revert":
			_apply_field_terra_revert(params)
			success = true
		"field_zone_mark":
			_apply_field_zone_mark(params)
			success = true
		"field_zone_clear":
			_apply_field_zone_clear(params)
			success = true
		"field_zone_boost":
			_apply_field_zone_boost(params)
			success = true
		"field_zone_slow":
			_apply_field_zone_slow(params)
			success = true
		"field_zone_danger":
			_apply_field_zone_danger(params)
			success = true
		"field_zone_safe":
			_apply_field_zone_safe(params)
			success = true
		"field_illusion_add":
			_apply_field_illusion_add(params)
			success = true
		"field_illusion_clear":
			_apply_field_illusion_clear(params)
			success = true
		# === 对球员标签 - 属性(01-16) ===
		"player_atk_up_pct":
			_apply_player_stat_buff(params, caster_id, "attack", 1.0 + float(params.get("value", 0)) / 100.0, 0.0)
			success = true
		"player_atk_down_pct":
			_apply_player_stat_buff(params, caster_id, "attack", 1.0 / max(0.01, float(params.get("value", 0)) / 100.0 + 1.0), 0.0)
			success = true
		"player_atk_up_flat":
			_apply_player_stat_buff(params, caster_id, "attack", 1.0, float(params.get("value", 0)))
			success = true
		"player_atk_down_flat":
			_apply_player_stat_buff(params, caster_id, "attack", 1.0, -float(params.get("value", 0)))
			success = true
		"player_def_up_pct":
			_apply_player_stat_buff(params, caster_id, "defense", 1.0 + float(params.get("value", 0)) / 100.0, 0.0)
			success = true
		"player_def_down_pct":
			_apply_player_stat_buff(params, caster_id, "defense", 1.0 / max(0.01, float(params.get("value", 0)) / 100.0 + 1.0), 0.0)
			success = true
		"player_def_up_flat":
			_apply_player_stat_buff(params, caster_id, "defense", 1.0, float(params.get("value", 0)))
			success = true
		"player_def_down_flat":
			_apply_player_stat_buff(params, caster_id, "defense", 1.0, -float(params.get("value", 0)))
			success = true
		"player_spd_up_pct":
			_apply_player_stat_buff(params, caster_id, "speed", 1.0 + float(params.get("value", 0)) / 100.0, 0.0)
			success = true
		"player_spd_down_pct":
			_apply_player_stat_buff(params, caster_id, "speed", 1.0 / max(0.01, float(params.get("value", 0)) / 100.0 + 1.0), 0.0)
			success = true
		"player_spd_up_flat":
			_apply_player_stat_buff(params, caster_id, "speed", 1.0, float(params.get("value", 0)))
			success = true
		"player_spd_down_flat":
			_apply_player_stat_buff(params, caster_id, "speed", 1.0, -float(params.get("value", 0)))
			success = true
		"player_res_up_pct":
			_apply_player_stat_buff(params, caster_id, "resilience", 1.0 + float(params.get("value", 0)) / 100.0, 0.0)
			success = true
		"player_res_down_pct":
			_apply_player_stat_buff(params, caster_id, "resilience", 1.0 / max(0.01, float(params.get("value", 0)) / 100.0 + 1.0), 0.0)
			success = true
		"player_res_up_flat":
			_apply_player_stat_buff(params, caster_id, "resilience", 1.0, float(params.get("value", 0)))
			success = true
		"player_res_down_flat":
			_apply_player_stat_buff(params, caster_id, "resilience", 1.0, -float(params.get("value", 0)))
			success = true
		# === 对球员标签 - 状态(17-20) ===
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
		# === 对球员标签 - 体力(21-26) ===
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
		# === 对球员标签 - 运动(27-30) ===
		"player_move_slow":
			_apply_player_stat_buff(params, caster_id, "speed", 1.0, -float(params.get("value", 50)))
			success = true
		"player_move_boost":
			_apply_player_stat_buff(params, caster_id, "speed", 1.0, float(params.get("value", 50)))
			success = true
		"player_root":
			_apply_player_status(params, caster_id, "rooted")
			success = true
		"player_unroot":
			_apply_player_unroot(params, caster_id)
			success = true
		# === 对球员标签 - 能量(31-38) ===
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
			_apply_player_stat_buff(params, caster_id, "max_energy", 1.0 + float(params.get("value", 0)) / 100.0, 0.0)
			success = true
		"player_energy_max_down_pct":
			_apply_player_stat_buff(params, caster_id, "max_energy", 1.0 / max(0.01, float(params.get("value", 0)) / 100.0 + 1.0), 0.0)
			success = true
		"player_energy_max_up_flat":
			_apply_player_stat_buff(params, caster_id, "max_energy", 1.0, float(params.get("value", 0)))
			success = true
		"player_energy_max_down_flat":
			_apply_player_stat_buff(params, caster_id, "max_energy", 1.0, -float(params.get("value", 0)))
			success = true
		# === 对球员标签 - 元灵(39-45) ===
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
		# === 对球员标签 - 控制(46-49) ===
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
		# === 对球员标签 - 交互(50-51) ===
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


## ==================== 对球效果实现 (17个) ====================

## 01 增伤(%) — params: {value}
func _apply_ball_dmg_up_pct(params: Dictionary) -> void:
	var val: float = float(params.get("value", 0))
	_ball_mods.dmg_mult += val / 100.0
	print("[TagEffect] 增伤(%%): val=%.1f mult=%.2f" % [val, _ball_mods.dmg_mult])

## 02 减伤(%) — params: {value}
func _apply_ball_dmg_down_pct(params: Dictionary) -> void:
	var val: float = float(params.get("value", 0))
	_ball_mods.dmg_mult -= val / 100.0
	_ball_mods.dmg_mult = max(0.0, _ball_mods.dmg_mult)
	print("[TagEffect] 减伤(%%): val=%.1f mult=%.2f" % [val, _ball_mods.dmg_mult])

## 03 增伤(固定) — params: {value}
func _apply_ball_dmg_up_flat(params: Dictionary) -> void:
	var val: float = float(params.get("value", 0))
	_ball_mods.dmg_flat += val
	print("[TagEffect] 增伤(固定): val=%.1f flat=%.1f" % [val, _ball_mods.dmg_flat])

## 04 减伤(固定) — params: {value}
func _apply_ball_dmg_down_flat(params: Dictionary) -> void:
	var val: float = float(params.get("value", 0))
	_ball_mods.dmg_flat -= val
	print("[TagEffect] 减伤(固定): val=%.1f flat=%.1f" % [val, _ball_mods.dmg_flat])

## 05 加速(%) — params: {multiplier}
func _apply_ball_speed_up_pct(params: Dictionary) -> void:
	var mult: float = float(params.get("multiplier", 0))
	if mult > 0:
		_ball_mods.speed_mult *= mult
	print("[TagEffect] 加速(%%): mult=%.2f speed_mult=%.2f" % [mult, _ball_mods.speed_mult])

## 06 减速(%) — params: {multiplier}
func _apply_ball_speed_down_pct(params: Dictionary) -> void:
	var mult: float = float(params.get("multiplier", 0))
	if mult > 0:
		_ball_mods.speed_mult /= mult
	_ball_mods.speed_mult = max(0.1, _ball_mods.speed_mult)
	print("[TagEffect] 减速(%%): mult=%.2f speed_mult=%.2f" % [mult, _ball_mods.speed_mult])

## 07 加速(固定) — params: {value}
func _apply_ball_speed_up_flat(params: Dictionary) -> void:
	var val: float = float(params.get("value", 0))
	_ball_mods.speed_flat += val
	print("[TagEffect] 加速(固定): val=%.1f speed_flat=%.1f" % [val, _ball_mods.speed_flat])

## 08 减速(固定) — params: {value}
func _apply_ball_speed_down_flat(params: Dictionary) -> void:
	var val: float = float(params.get("value", 0))
	_ball_mods.speed_flat -= val
	print("[TagEffect] 减速(固定): val=%.1f speed_flat=%.1f" % [val, _ball_mods.speed_flat])

## 15 穿透 — params: {duration}
func _apply_ball_penetrate(params: Dictionary) -> void:
	_ball_mods.penetrate = true
	print("[TagEffect] 穿透: 启用")

## 07 范围扩大 — params: {multiplier, duration}
func _apply_ball_range_up(params: Dictionary) -> void:
	var mult: float = float(params.get("multiplier", 0))
	if mult > 0:
		_ball_mods.range_mult *= mult
	print("[TagEffect] 范围扩大: mult=%.2f" % _ball_mods.range_mult)

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
func _apply_field_zone_boost(params: Dictionary) -> void:
	pass
func _apply_field_zone_slow(params: Dictionary) -> void:
	pass
func _apply_field_zone_danger(params: Dictionary) -> void:
	pass
func _apply_field_zone_safe(params: Dictionary) -> void:
	pass
func _apply_field_illusion_add(params: Dictionary) -> void:
	pass
func _apply_field_illusion_clear(params: Dictionary) -> void:
	pass


## ==================== 对球员效果实现 ====================

## 通用属性buff（内部调用，不直接match）
func _apply_player_stat_buff(params: Dictionary, caster_id: int, stat: String, mult: float, flat: float) -> void:
	"""通用属性buff：给施法者/目标添加属性修正
	stat: attack/defense/speed/resilience/max_energy
	mult: 乘法修正（>1提升, <1降低）
	flat: 加法修正（>0提升, <0降低）
	"""
	var targets := _get_player_targets(params, caster_id)
	var duration: float = float(params.get("duration", 5.0))
	for target in targets:
		target.add_buff("player_%s_buff" % stat, stat, mult, flat, duration)
	print("[TagEffect] 属性buff: stat=%s mult=%.2f flat=%.1f dur=%.1fs targets=%d" % [stat, mult, flat, duration, targets.size()])


## 状态类（通用）
func _apply_player_status(params: Dictionary, caster_id: int, status: String) -> void:
	"""给目标添加状态标记（眩晕/定身/沉默/缴械/无敌/隐身/免疫控制）"""
	var targets := _get_player_targets(params, caster_id)
	var duration: float = float(params.get("duration", 3.0))
	for target in targets:
		target.add_status_buff("player_%s" % status, status, duration)
	print("[TagEffect] 状态buff: status=%s dur=%.1fs targets=%d" % [status, duration, targets.size()])


## 获取目标球员列表
func _get_player_targets(params: Dictionary, caster_id: int) -> Array:
	"""根据 params 的 target 决定目标
	- 默认: 施法者自己
	- target="enemies": 敌方全体
	- target="allies": 己方全体
	- target="nearest_enemy": 最近敌方
	"""
	var target_mode: String = str(params.get("target", "self"))
	var caster := _get_caster(caster_id)
	var result: Array = []
	match target_mode:
		"self":
			if caster:
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
			if caster:
				result.append(caster)
	return result


## === 17-18: 无敌 / 易伤 ===
func _apply_player_vulnerable(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var duration: float = float(params.get("duration", 3.0))
	var mult: float = float(params.get("damage_mult", 1.5))
	for target in targets:
		target.set_vulnerable(true, mult)
		# 注册到期恢复
		target.add_status_buff("player_vulnerable", "vulnerable_dummy", duration)
		# 覆盖 on_expire 让它恢复易伤
	print("[TagEffect] 易伤: mult=%.1f dur=%.1fs targets=%d" % [mult, duration, targets.size()])


## === 19-20: 隐身 / 显形 ===
func _apply_player_reveal(params: Dictionary, caster_id: int) -> void:
	# 显形：敌方所有隐身球员强制现身
	var caster := _get_caster(caster_id)
	var enemies := _get_enemies(caster)
	var count: int = 0
	for e in enemies:
		if e.is_stealthed():
			e.add_status_buff("player_reveal", "stealthed", 0.01)  # 短暂标记立即过期，解除隐身
			count += 1
	print("[TagEffect] 显形: %d个隐身目标" % count)


## === 21-26: 体力 ===
func _apply_player_hp_heal_pct(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var pct: float = float(params.get("value", 20)) / 100.0
	for target in targets:
		var heal: float = target.max_stamina * pct
		target.stamina = min(target.max_stamina, target.stamina + heal)
		print("[TagEffect] 恢复(%%): %s +%.0f HP" % [target._pname(), heal])

func _apply_player_hp_damage_pct(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var pct: float = float(params.get("value", 20)) / 100.0
	for target in targets:
		var dmg: float = target.max_stamina * pct
		target.stamina = max(0.0, target.stamina - dmg)
		if target.stamina <= 0.0 and not target.is_defeated:
			target._on_defeated()
		print("[TagEffect] 掉血(%%): %s -%.0f HP" % [target._pname(), dmg])

func _apply_player_hp_heal_flat(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var val: float = float(params.get("value", 30))
	for target in targets:
		target.stamina = min(target.max_stamina, target.stamina + val)
		print("[TagEffect] 恢复(固定): %s +%.0f HP" % [target._pname(), val])

func _apply_player_hp_damage_flat(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var val: float = float(params.get("value", 30))
	for target in targets:
		target.stamina = max(0.0, target.stamina - val)
		if target.stamina <= 0.0 and not target.is_defeated:
			target._on_defeated()
		print("[TagEffect] 掉血(固定): %s -%.0f HP" % [target._pname(), val])

func _apply_player_hp_regen(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var rate: float = float(params.get("value", 5))
	var duration: float = float(params.get("duration", 5.0))
	for target in targets:
		target.set_hp_regen(rate)
		# 注册到期清除
		target.add_status_buff("player_hp_regen", "hp_regen_dummy", duration)
	print("[TagEffect] 持续恢复: rate=%.1f/s dur=%.1fs" % [rate, duration])

func _apply_player_hp_dot(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var rate: float = float(params.get("value", 5))
	var duration: float = float(params.get("duration", 5.0))
	for target in targets:
		target.set_hp_dot(rate)
		target.add_status_buff("player_hp_dot", "hp_dot_dummy", duration)
	print("[TagEffect] 持续掉血: rate=%.1f/s dur=%.1fs" % [rate, duration])


## === 30: 解除定身 ===
func _apply_player_unroot(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	for target in targets:
		# 移除所有 root 状态的 buff
		var to_remove: PackedStringArray = []
		for bid in target._buffs:
			if target._buffs[bid].get("status", "") == "rooted":
				to_remove.append(bid)
		for bid in to_remove:
			target.remove_buff(bid)
	print("[TagEffect] 解除定身: targets=%d" % targets.size())


## === 31-34: 能量 ===
func _apply_player_energy_pct(params: Dictionary, caster_id: int, is_gain: bool) -> void:
	var targets := _get_player_targets(params, caster_id)
	var pct: float = float(params.get("value", 20)) / 100.0
	for target in targets:
		var amt: float = target.max_spirit_energy * pct
		if is_gain:
			target.spirit_energy = min(target.get_effective_max_energy(), target.spirit_energy + amt)
			print("[TagEffect] 能量恢复(%%): %s +%.0f" % [target._pname(), amt])
		else:
			target.spirit_energy = max(0.0, target.spirit_energy - amt)
			print("[TagEffect] 能量消耗(%%): %s -%.0f" % [target._pname(), amt])

func _apply_player_energy_flat(params: Dictionary, caster_id: int, is_gain: bool) -> void:
	var targets := _get_player_targets(params, caster_id)
	var val: float = float(params.get("value", 20))
	for target in targets:
		if is_gain:
			target.spirit_energy = min(target.get_effective_max_energy(), target.spirit_energy + val)
			print("[TagEffect] 能量恢复(固定): %s +%.0f" % [target._pname(), val])
		else:
			target.spirit_energy = max(0.0, target.spirit_energy - val)
			print("[TagEffect] 能量消耗(固定): %s -%.0f" % [target._pname(), val])


## === 39-40: 技能消耗增减 ===
func _apply_player_spirit_cost(params: Dictionary, caster_id: int, is_down: bool) -> void:
	var targets := _get_player_targets(params, caster_id)
	var val: float = float(params.get("value", 20)) / 100.0
	var duration: float = float(params.get("duration", 5.0))
	for target in targets:
		var new_mult: float
		if is_down:
			new_mult = target.get_skill_cost_mult() * (1.0 - val)
		else:
			new_mult = target.get_skill_cost_mult() * (1.0 + val)
		target.set_skill_cost_mult(max(0.1, new_mult))
		target.add_status_buff("spirit_cost", "spirit_cost_dummy", duration)
	print("[TagEffect] 技能消耗%s: val=%.0f%% dur=%.1fs" % ["减少" if is_down else "增加", val * 100.0, duration])


## === 41: 技能使用次数增加 ===
func _apply_player_spirit_uses(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var bonus: int = int(params.get("value", 1))
	for target in targets:
		target.add_skill_uses(bonus)
	print("[TagEffect] 技能使用次数+%d" % bonus)


## === 42-43: 技能CD增减 ===
func _apply_player_spirit_cd(params: Dictionary, caster_id: int, is_down: bool) -> void:
	var targets := _get_player_targets(params, caster_id)
	var val: float = float(params.get("value", 20)) / 100.0
	var duration: float = float(params.get("duration", 5.0))
	for target in targets:
		var new_mult: float
		if is_down:
			new_mult = target.get_skill_cd_mult() * (1.0 - val)
		else:
			new_mult = target.get_skill_cd_mult() * (1.0 + val)
		target.set_skill_cd_mult(max(0.1, new_mult))
		target.add_status_buff("spirit_cd", "spirit_cd_dummy", duration)
	print("[TagEffect] 技能CD%s: val=%.0f%% dur=%.1fs" % ["缩短" if is_down else "延长", val * 100.0, duration])


## === 44-45: 双倍/减半 ===
func _apply_player_spirit_double(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	for target in targets:
		target.set_next_skill_double(true)
	print("[TagEffect] 下次技能效果翻倍")

func _apply_player_spirit_half(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	for target in targets:
		target.set_next_skill_half(true)
	print("[TagEffect] 下次技能效果减半")


## === 50-51: 传送 / 返回 ===
func _apply_player_teleport(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var pos_x: float = float(params.get("pos_x", 0))
	var pos_y: float = float(params.get("pos_y", 0))
	for target in targets:
		target.teleport_to(Vector2(pos_x, pos_y))

func _apply_player_return(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	for target in targets:
		target.return_to_previous()


## ==================== 辅助方法 ====================

func _get_obstacle_manager() -> Node:
	"""获取障碍物管理器"""
	if battle_manager and battle_manager.has_node("ObstacleManager"):
		return battle_manager.get_node("ObstacleManager")
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
