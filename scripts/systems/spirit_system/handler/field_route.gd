extends "res://scripts/systems/spirit_system/handler/player_route.gd"
## handler/field_route.gd —— FIELD 路线：障碍/区域/迷雾/落点桥（13 拆分步骤4）

## ==================== 对场地效果 (预留) ====================

## Q12（11号工单"AI放置数据链补齐"，主人批 2026-09-27）：AI 直生分支。
## AI 施法经 _execute_skill 携带 _target_data.field_position（经 trigger 注入 params._target_data），
## 但 AI 无鼠标——原 start_placing 鼠标放置模式对 AI 永不落地（白放白烧能）。
## 有坐标 → 直接生成（与玩家左键同一 create_obstacle/create_zone 管线）；无坐标 → 原鼠标路径不变。
## 返回 true=直生已处理；false=走调用方原鼠标路径
func _ai_direct_place_field(params: Dictionary, manager) -> bool:
	var target_data: Dictionary = params.get("_target_data", {})
	var ai_pos: Variant = target_data.get("field_position", null)
	if not (ai_pos is Vector2):
		return false
	if manager == null or not manager.has_method("create_obstacle"):
		return false
	if params.has("obstacle_script"):
		manager.create_obstacle(params, ai_pos, 0.0, str(params["obstacle_script"]))
	else:
		manager.create_obstacle(params, ai_pos)
	print("[TagEffectHandler] AI直生障碍: pos=%s shape=%s hp=%.0f%s" % [
		str(ai_pos), str(params.get("shape", "rect")), float(params.get("hp", 50.0)),
		(" script=" + str(params.get("obstacle_script")) if params.has("obstacle_script") else "")
	])
	return true


func _apply_field_obs_add(params: Dictionary) -> void:
	"""创造障碍标签：AI 直生 / 玩家进鼠标放置模式"""
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

	# Q12 AI直生：field_position 有坐标直接生成，跳过鼠标模式
	if _ai_direct_place_field(params, manager):
		return

	var mouse_ops: int = int(params.get("mouse_ops", 1))
	manager.start_placing(params, mouse_ops)

	print("[TagEffectHandler] 创造障碍: shape=%s hp=%.0f atk_consume=%.0f/s spd_consume=%.0fpx/s mouse_ops=%d" % [
		params.get("shape", "rect"), params.get("hp", 50.0),
		params.get("attack_consume_rate", 20.0), params.get("speed_consume_rate", 20.0),
		mouse_ops
	])


## 波7 #6b 管道接线（2026-09-24 小工单，主人批准）：削能墙标签 → drain_wall.gd 障碍
## 交互=放置态（同 field_obs_add：鼠移预览→左键生成，01 检验单"风之屏障"行）
## 障碍生成与 drain 参数注入由 obstacle_manager.create_obstacle 统一完成（obstacle_script 覆盖+setup_drain 钩子）
func _apply_field_drain_wall(params: Dictionary, caster_id: int) -> void:
	var manager = _get_obstacle_manager()
	if not manager:
		push_error("[TagEffectHandler] 找不到 ObstacleManager")
		return

	if not params.has("element_color"):
		params["element_color"] = _get_element_color(str(params.get("element", "")))
	if not params.has("source_skill"):
		params["source_skill"] = str(params.get("skill_id", ""))
	var caster_node = _get_caster(caster_id)
	if caster_node:
		params["caster_position"] = caster_node.global_position
	params["obstacle_script"] = "res://scripts/battle/drain_wall.gd"

	# Q12 AI直生：field_position 有坐标直接生成（create_obstacle 内部走 setup_drain 注入）
	if _ai_direct_place_field(params, manager):
		return

	var mouse_ops: int = int(params.get("mouse_ops", 1))
	manager.start_placing(params, mouse_ops)
	print("[TagEffectHandler] 削能墙: capture=%.0f pull=%.0f hold=%.1fs dur=%.0fs mouse_ops=%d" % [
		float(params.get("capture_radius", 90.0)), float(params.get("absorb_pull", 240.0)),
		float(params.get("drain_hold", 2.0)), float(params.get("duration", 10.0)),
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

	# 工单23 F4 能量快道：注能主体/条带起点注入（施法者=起点；AI 直生落点=终点）
	if zone_type == 6:
		var caster_for_path = _get_caster(params.get("caster_id", 0))
		if caster_for_path:
			zone_params["owner_node"] = caster_for_path
			zone_params["owner_team"] = str(caster_for_path.team)
			if not zone_params.has("path_from"):
				zone_params["path_from"] = caster_for_path.global_position

	# Q12 AI直生：field_position 有坐标直接生成区域（与 placer 左键同走 create_zone 管线；
	# spawn_at 落点路径已在上方短路，此处兜无 spawn_at 的 AI 区域技）
	var target_data: Dictionary = params.get("_target_data", {})
	var ai_pos: Variant = target_data.get("field_position", null)
	if ai_pos is Vector2:
		if zone_type == 6 and zone_params.has("owner_node"):
			zone_params["path_to"] = ai_pos  # F4：AI 快道终点=放置语义落点，起点=施法者（23a §三）
		manager.create_zone(zone_params, ai_pos)
		var type_names_ai: Array = ["加速区", "减速区", "危险区", "安全区", "治疗区", "视野迷雾", "能量快道"]
		print("[TagEffectHandler] AI直生区域: %s pos=%s size=%.0f×%.0f dur=%.1fs" % [
			type_names_ai[zone_type] if zone_type < type_names_ai.size() else str(zone_type),
			str(ai_pos), float(zone_params["width"]),
			float(zone_params["height"]), float(zone_params["duration"])
		])
		return

	var mouse_ops: int = int(params.get("mouse_ops", 1))
	manager.start_placing(zone_params, mouse_ops)

	var type_names: Array = ["加速区", "减速区", "危险区", "安全区", "治疗区", "视野迷雾", "能量快道"]
	print("[TagEffectHandler] 区域效果: %s size=%.0f×%.0f dur=%.1fs mouse_ops=%d" % [
		type_names[zone_type] if zone_type < type_names.size() else str(zone_type),
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
		6:
			# 工单23 F4 能量快道：条带/注能/增益参数透传（owner_node 由 _apply_field_zone_effect 注入）
			zone_params["effect_value"] = 0.0
			zone_params["path_width"] = maxf(float(params.get("path_width", 48.0)), 12.0)
			zone_params["energy_per_sec"] = maxf(float(params.get("energy_per_sec", 2.0)), 0.0)
			var buffs_v: Variant = params.get("path_buffs", null)
			if buffs_v is Dictionary and not (buffs_v as Dictionary).is_empty():
				zone_params["path_buffs"] = buffs_v
	# 波5 #12 zone 作用于球：affect_ball 透传（可选）
	if params.has("affect_ball"):
		zone_params["affect_ball"] = params.get("affect_ball")
	if not params.has("source_skill"):
		zone_params["source_skill"] = params.get("_skill_id", params.get("skill_id", ""))
	return zone_params


## ==================== V1-3 落点区域 pending（06 文档）====================

# 波6 #14 飞行中球操作 pending {caster_id: {mods, expires_at}}（无在场球时登记，ATTACK_LAUNCHED 消费）


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
	# 19号任务B上报断点2（Q12同族，主人令领取）：AI 直生——ai_mode 或 _target_data.field_position
	# → 幻象直接生成（指定位置/施法者自身），跳过鼠标放置模式；否则原鼠标路径不变
	var il_target_data: Dictionary = params.get("_target_data", {})
	var il_ai_pos: Variant = il_target_data.get("field_position", null)
	if bool(params.get("ai_mode", false)) or il_ai_pos is Vector2:
		var base_pos: Vector2 = (il_ai_pos as Vector2) if il_ai_pos is Vector2 else source.global_position
		for i in range(mouse_ops):
			manager.create_illusion(source, params, base_pos)
		print("[TagEffectHandler] AI直生幻象: pos=%s count=%d" % [str(base_pos), mouse_ops])
		return

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


