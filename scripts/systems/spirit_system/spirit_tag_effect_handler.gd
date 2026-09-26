extends "res://scripts/systems/spirit_system/handler/field_route.gd"
class_name SpiritTagEffectHandler

## 元灵技能标签效果处理器
## 负责执行所有标签的对应效果

# 引用
func _ready() -> void:
	battle_manager = get_node_or_null("/root/BattleManager")
	_init_priority_table()


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
