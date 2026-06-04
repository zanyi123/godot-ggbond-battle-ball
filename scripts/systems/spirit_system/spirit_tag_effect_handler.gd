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
	"penetrate": false,      # 穿透
	"tracking_target": null, # 追踪目标节点
	"tracking_turn_speed": 0.0,
	"boomerang": false,      # 回旋
	"boomerang_triggered": false,
	"boomerang_return_dir": Vector2.ZERO,
	"boomerang_dist": 0.0,
	"lock_straight": false,  # 直行（禁用其他轨迹）
	"aoe_radius": 0.0,       # AOE范围伤害半径（0=无AOE）
	"aoe_damage_pct": 0.5,   # AOE伤害占原伤害比例
	"lockon": false,         # 精准锁定
	"spread": false,          # 扩散
}


func _ready() -> void:
	battle_manager = get_node_or_null("/root/BattleManager")


## ==================== 球修饰符接口（供 ball.gd 调用）====================

## 发球前重置所有修饰符
func reset_ball_mods() -> void:
	_ball_mods = {
		"dmg_mult": 1.0, "dmg_flat": 0.0,
		"speed_mult": 1.0, "speed_flat": 0.0,
		"penetrate": false,
		"tracking_target": null, "tracking_turn_speed": 0.0,
		"boomerang": false, "boomerang_triggered": false,
		"boomerang_return_dir": Vector2.ZERO, "boomerang_dist": 0.0,
		"lock_straight": false,
		"aoe_radius": 0.0, "aoe_damage_pct": 0.5,
		"lockon": false, "spread": false,
	}

## 获取修饰后的球伤害
func get_modified_ball_damage(base_damage: float) -> float:
	return max(0.0, (base_damage + _ball_mods.dmg_flat) * _ball_mods.dmg_mult)

## 获取修饰后的球速度
func get_modified_ball_speed(base_speed: float) -> float:
	return (base_speed + _ball_mods.speed_flat) * _ball_mods.speed_mult

## 是否有AOE范围伤害
func has_ball_aoe() -> bool:
	return _ball_mods.aoe_radius > 0.0

## 获取AOE半径
func get_ball_aoe_radius() -> float:
	return _ball_mods.aoe_radius

## 获取AOE伤害比例
func get_ball_aoe_damage_pct() -> float:
	return _ball_mods.aoe_damage_pct

## 是否精准锁定
func is_ball_lockon() -> bool:
	return _ball_mods.lockon

## 是否扩散
func is_ball_spread() -> bool:
	return _ball_mods.spread

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
		"ball_dmg_up":
			_apply_ball_dmg_up(params)
			success = true
		"ball_dmg_down":
			_apply_ball_dmg_down(params)
			success = true
		"ball_speed_up":
			_apply_ball_speed_up(params)
			success = true
		"ball_speed_down":
			_apply_ball_speed_down(params)
			success = true
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
			_apply_ball_spread(params)
			success = true
		"ball_penetrate":
			_apply_ball_penetrate(params)
			success = true
		"ball_range_up":
			_apply_ball_range_up(params)
			success = true
		"ball_range_down":
			_apply_ball_range_down(params)
			success = true
		# 对场地/球员标签暂不实现
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


## ==================== 对球效果实现 (13个) ====================

## BALL-01 增伤 — params: {value_type, value}
func _apply_ball_dmg_up(params: Dictionary) -> void:
	var val: float = float(params.get("value", 0))
	var vtype: String = str(params.get("value_type", "percentage"))
	if vtype == "percentage":
		_ball_mods.dmg_mult += val / 100.0
	else:
		_ball_mods.dmg_flat += val
	print("[TagEffect] 增伤: type=%s val=%.1f → mult=%.2f flat=%.1f" % [vtype, val, _ball_mods.dmg_mult, _ball_mods.dmg_flat])

## BALL-02 减伤
func _apply_ball_dmg_down(params: Dictionary) -> void:
	var val: float = float(params.get("value", 0))
	var vtype: String = str(params.get("value_type", "percentage"))
	if vtype == "percentage":
		_ball_mods.dmg_mult -= val / 100.0
	else:
		_ball_mods.dmg_flat -= val
	_ball_mods.dmg_mult = max(0.0, _ball_mods.dmg_mult)
	print("[TagEffect] 减伤: → mult=%.2f flat=%.1f" % [_ball_mods.dmg_mult, _ball_mods.dmg_flat])

## BALL-03 加速 — params: {multiplier, fixed_value}
func _apply_ball_speed_up(params: Dictionary) -> void:
	var mult: float = float(params.get("multiplier", 0))
	var fixed: float = float(params.get("fixed_value", 0))
	if mult > 0:
		_ball_mods.speed_mult *= mult
	if fixed != 0:
		_ball_mods.speed_flat += fixed
	print("[TagEffect] 球加速: → mult=%.2f flat=%.1f" % [_ball_mods.speed_mult, _ball_mods.speed_flat])

## BALL-04 减速
func _apply_ball_speed_down(params: Dictionary) -> void:
	var mult: float = float(params.get("multiplier", 0))
	var fixed: float = float(params.get("fixed_value", 0))
	if mult > 0:
		_ball_mods.speed_mult /= mult
	if fixed != 0:
		_ball_mods.speed_flat -= fixed
	_ball_mods.speed_mult = max(0.1, _ball_mods.speed_mult)
	print("[TagEffect] 球减速: → mult=%.2f flat=%.1f" % [_ball_mods.speed_mult, _ball_mods.speed_flat])

## BALL-05 追踪 — 持续转向目标
func _apply_ball_tracking(params: Dictionary, caster_id: int) -> void:
	var caster := _get_caster(caster_id)
	if not caster:
		return
	var target := _get_nearest_enemy(caster)
	if target:
		_ball_mods.tracking_target = target
		_ball_mods.tracking_turn_speed = float(params.get("turn_speed", 3.0))
		print("[TagEffect] 追踪: 目标=%s 转速=%.1f" % [target.char_data.get("name", "?"), _ball_mods.tracking_turn_speed])

## BALL-06 避障 — 待场地系统

## BALL-07 回旋 — 飞到一半返回
func _apply_ball_boomerang(params: Dictionary) -> void:
	_ball_mods.boomerang = true
	_ball_mods.boomerang_dist = float(params.get("return_distance", 0.5))
	print("[TagEffect] 回旋: 返回点=%.0f%%" % (_ball_mods.boomerang_dist * 100))

## BALL-08 直行 — 禁用所有轨迹修改
func _apply_ball_straight(params: Dictionary) -> void:
	_ball_mods.lock_straight = true
	_ball_mods.tracking_target = null
	_ball_mods.boomerang = false
	print("[TagEffect] 直行: 禁用追踪/回旋")

## BALL-09 精准锁定 — 发球时自动瞄准最近敌人
func _apply_ball_lockon(params: Dictionary, caster_id: int) -> void:
	_ball_mods.lockon = true
	var caster := _get_caster(caster_id)
	if caster:
		var target := _get_nearest_enemy(caster)
		if target:
			_ball_mods["lockon_target"] = target
			print("[TagEffect] 精准锁定: 目标=%s" % target.char_data.get("name", "?"))
			return
	print("[TagEffect] 精准锁定: 标记（无目标）")

## BALL-10 扩散 — 碰撞时分裂
func _apply_ball_spread(params: Dictionary) -> void:
	_ball_mods.spread = true
	print("[TagEffect] 扩散: 启用")

## BALL-11 穿透 — 击中后不停止
func _apply_ball_penetrate(params: Dictionary) -> void:
	_ball_mods.penetrate = true
	print("[TagEffect] 穿透: 启用")

## BALL-13 范围扩大 — 球命中敌人时以该球员为圆心造成AOE伤害
func _apply_ball_range_up(params: Dictionary) -> void:
	_ball_mods.aoe_radius = float(params.get("radius", 80.0))
	_ball_mods.aoe_damage_pct = float(params.get("damage_pct", 0.5))
	print("[TagEffect] 范围扩大: AOE半径=%.0f 伤害比例=%.0f%%" % [_ball_mods.aoe_radius, _ball_mods.aoe_damage_pct * 100])

## BALL-14 范围缩小 — 减小AOE半径
func _apply_ball_range_down(params: Dictionary) -> void:
	var mult: float = float(params.get("multiplier", 0.5))
	if mult > 0:
		_ball_mods.aoe_radius *= mult
	print("[TagEffect] 范围缩小: AOE半径=%.0f" % _ball_mods.aoe_radius)


## ==================== 对场地效果 (预留) ====================

func _apply_field_obs_add(params: Dictionary) -> void:
	pass
func _apply_field_obs_clear(params: Dictionary) -> void:
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


## ==================== 对球员效果 (预留) ====================

func _apply_player_atk_up(params: Dictionary) -> void:
	pass
func _apply_player_atk_down(params: Dictionary) -> void:
	pass
func _apply_player_def_up(params: Dictionary) -> void:
	pass
func _apply_player_def_down(params: Dictionary) -> void:
	pass
func _apply_player_spd_up(params: Dictionary) -> void:
	pass
func _apply_player_spd_down(params: Dictionary) -> void:
	pass
func _apply_player_res_up(params: Dictionary) -> void:
	pass
func _apply_player_res_down(params: Dictionary) -> void:
	pass
func _apply_player_invincible(params: Dictionary) -> void:
	pass
func _apply_player_vulnerable(params: Dictionary) -> void:
	pass
func _apply_player_stealth(params: Dictionary) -> void:
	pass
func _apply_player_reveal(params: Dictionary) -> void:
	pass
func _apply_player_hp_heal(params: Dictionary) -> void:
	pass
func _apply_player_hp_damage(params: Dictionary) -> void:
	pass
func _apply_player_hp_regen(params: Dictionary) -> void:
	pass
func _apply_player_hp_dot(params: Dictionary) -> void:
	pass
func _apply_player_move_slow(params: Dictionary) -> void:
	pass
func _apply_player_move_boost(params: Dictionary) -> void:
	pass
func _apply_player_root(params: Dictionary) -> void:
	pass
func _apply_player_unroot(params: Dictionary) -> void:
	pass
func _apply_player_energy_gain(params: Dictionary) -> void:
	pass
func _apply_player_energy_cost(params: Dictionary) -> void:
	pass
func _apply_player_energy_max_up(params: Dictionary) -> void:
	pass
func _apply_player_energy_max_down(params: Dictionary) -> void:
	pass
func _apply_player_spirit_cost_down(params: Dictionary) -> void:
	pass
func _apply_player_spirit_cost_up(params: Dictionary) -> void:
	pass
func _apply_player_spirit_uses_up(params: Dictionary) -> void:
	pass
func _apply_player_spirit_cd_down(params: Dictionary) -> void:
	pass
func _apply_player_spirit_cd_up(params: Dictionary) -> void:
	pass
func _apply_player_spirit_double(params: Dictionary) -> void:
	pass
func _apply_player_spirit_half(params: Dictionary) -> void:
	pass
func _apply_player_stun(params: Dictionary) -> void:
	pass
func _apply_player_cc_immune(params: Dictionary) -> void:
	pass
func _apply_player_silence(params: Dictionary) -> void:
	pass
func _apply_player_disarm(params: Dictionary) -> void:
	pass
func _apply_player_teleport(params: Dictionary) -> void:
	pass
func _apply_player_return(params: Dictionary) -> void:
	pass