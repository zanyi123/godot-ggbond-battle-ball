extends "res://scripts/systems/spirit_system/handler/base_route.gd"
## handler/ball_route.gd —— BALL 路线：球修饰符 apply（13 拆分步骤2）

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
	var caster := _get_caster(caster_id)
	if caster:
		p["caster_team"] = str(caster.team)  # 波6 P1 修正：本方不受迷雾影响
	call("_apply_field_zone_effect", p, 5)  # 兄弟层调用走动态（运行时实例可解析）
	print("[TagEffect] 视野迷雾: perception_scale=%.2f (caster=%d)" % [float(params.get("perception_scale", 0.5)), caster_id])

