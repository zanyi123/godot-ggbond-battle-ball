## 区域效果节点
## 场地上的效果区域：加速/减速/危险/安全
## 球员进入区域触发效果，离开区域移除效果
## 倒计时结束后自动消失

extends Area2D
class_name FieldEffectZone

## ==================== 信号 ====================

signal zone_expired(zone: FieldEffectZone)

## ==================== 效果类型枚举 ====================

enum ZoneType {
	BOOST,    # 加速区
	SLOW,     # 减速区
	DANGER,   # 危险区（持续伤害）
	SAFE,     # 安全区（免疫伤害）
}

## ==================== 配置 ====================

const ZONE_COLORS: Dictionary = {
	ZoneType.BOOST: {"fill": Color(0.2, 0.8, 0.2, 0.25), "border": Color(0.3, 1.0, 0.3, 0.8)},
	ZoneType.SLOW: {"fill": Color(0.2, 0.2, 0.8, 0.25), "border": Color(0.3, 0.3, 1.0, 0.8)},
	ZoneType.DANGER: {"fill": Color(0.8, 0.2, 0.2, 0.25), "border": Color(1.0, 0.3, 0.3, 0.8)},
	ZoneType.SAFE: {"fill": Color(0.2, 0.8, 0.8, 0.25), "border": Color(0.3, 1.0, 1.0, 0.8)},
}

const ZONE_NAMES: Dictionary = {
	ZoneType.BOOST: "加速区",
	ZoneType.SLOW: "减速区",
	ZoneType.DANGER: "危险区",
	ZoneType.SAFE: "安全区",
}

## ==================== 状态 ====================

var zone_type: int = ZoneType.BOOST
var zone_size: Vector2 = Vector2(120.0, 120.0)
var duration: float = 10.0
var remaining: float = 10.0
var zone_id: String = ""
var source_skill: String = ""

## 效果参数
var effect_value: float = 1.5    # 加速/减速倍率 或 每秒伤害值
var zone_active: bool = true

## 正在区域内的球员 → 挂载的效果数据
var _players_inside: Dictionary = {}  # player_instance_id → {buff_id, ...}

## 视觉节点引用
var _fill_rect: ColorRect
var _border_line: Line2D
var _timer_label: Label
var _type_label: Label


## ==================== 初始化 ====================

func setup(params: Dictionary) -> void:
	"""初始化区域效果"""
	# 参数读取
	zone_type = _parse_zone_type(params.get("zone_type", ZoneType.BOOST))
	zone_size = Vector2(float(params.get("width", 120.0)), float(params.get("height", 120.0)))
	duration = float(params.get("duration", 10.0))
	remaining = duration
	zone_id = str(params.get("zone_id", ""))
	source_skill = str(params.get("source_skill", ""))
	effect_value = float(params.get("effect_value", 1.5))

	# 碰撞设置：检测 layer 1 (球员)
	collision_layer = 0
	collision_mask = 1  # 检测 layer 1 的物体
	monitoring = true
	monitorable = false

	# 创建碰撞形状
	var shape := RectangleShape2D.new()
	shape.size = zone_size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	add_child(collision)

	# 监控进入/离开
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# 视觉
	_build_visual()

	# 补检测：区域创建时已在内部的物体（body_entered不会触发）
	_check_initial_overlaps()


func _parse_zone_type(val) -> int:
	"""解析区域类型"""
	if val is int:
		return val
	var s: String = str(val).to_lower()
	match s:
		"boost", "加速", "加速区":
			return ZoneType.BOOST
		"slow", "减速", "减速区":
			return ZoneType.SLOW
		"danger", "危险", "危险区":
			return ZoneType.DANGER
		"safe", "安全", "安全区":
			return ZoneType.SAFE
	return ZoneType.BOOST


## ==================== 视觉 ====================

func _build_visual() -> void:
	"""创建区域视觉效果"""
	var colors: Dictionary = ZONE_COLORS.get(zone_type, ZONE_COLORS[ZoneType.BOOST])
	var half_w: float = zone_size.x / 2.0
	var half_h: float = zone_size.y / 2.0

	# 填充
	_fill_rect = ColorRect.new()
	_fill_rect.size = zone_size
	_fill_rect.position = Vector2(-half_w, -half_h)
	_fill_rect.color = colors.fill
	_fill_rect.z_index = -1
	add_child(_fill_rect)

	# 边框
	_border_line = Line2D.new()
	_border_line.width = 2.5
	_border_line.default_color = colors.border
	_border_line.z_index = 0
	var points: PackedVector2Array = [
		Vector2(-half_w, -half_h),
		Vector2(half_w, -half_h),
		Vector2(half_w, half_h),
		Vector2(-half_w, half_h),
		Vector2(-half_w, -half_h),
	]
	_border_line.points = points
	add_child(_border_line)

	# 类型标签
	_type_label = Label.new()
	_type_label.text = ZONE_NAMES.get(zone_type, "?")
	_type_label.position = Vector2(-30, -half_h - 18)
	_type_label.size = Vector2(60, 18)
	_type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_type_label.add_theme_font_size_override("font_size", 12)
	_type_label.add_theme_color_override("font_color", colors.border)
	add_child(_type_label)

	# 倒计时标签
	_timer_label = Label.new()
	_timer_label.position = Vector2(-20, -8)
	_timer_label.size = Vector2(40, 18)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 14)
	_timer_label.add_theme_color_override("font_color", Color.WHITE)
	add_child(_timer_label)


func _update_visual() -> void:
	"""更新倒计时显示"""
	if _timer_label and is_instance_valid(_timer_label):
		_timer_label.text = "%.1f" % remaining

	# 即将消失时闪烁
	if remaining < 3.0 and _fill_rect and is_instance_valid(_fill_rect):
		var flash: float = sin(remaining * 8.0) * 0.15 + 0.25
		var colors: Dictionary = ZONE_COLORS.get(zone_type, ZONE_COLORS[ZoneType.BOOST])
		var c: Color = colors.fill
		_fill_rect.color = Color(c.r, c.g, c.b, flash)


## ==================== 帧处理 ====================

func _process(delta: float) -> void:
	if not zone_active:
		return

	remaining -= delta
	_update_visual()

	# 危险区：每帧扣血
	if zone_type == ZoneType.DANGER:
		_process_danger_tick(delta)

	# 倒计时结束
	if remaining <= 0.0:
		_expire()


func _process_danger_tick(delta: float) -> void:
	"""危险区：每秒对区域内球员造成伤害"""
	var dps: float = effect_value
	if _players_inside.is_empty():
		return
	for player_id in _players_inside:
		var info: Dictionary = _players_inside[player_id]
		var player: CharacterBody2D = info.get("player", null)
		if player and is_instance_valid(player) and not player.is_defeated:
			if player.is_status_active("invincible"):
				continue
			var dmg: float = dps * delta
			var defense_resist: float = player._get_effective_value("defense", player.defense) * player.defense_factor
			var reduction_rate: float = minf(defense_resist / 100.0, 0.8)
			dmg *= (1.0 - reduction_rate)
			player.stamina = maxf(0.0, player.stamina - dmg)
			if player.stamina <= 0.0 and not player.is_defeated:
				player._on_defeated()


## ==================== 进出区域 ====================

func _on_body_entered(body: Node2D) -> void:
	"""球员进入区域"""
	if not zone_active:
		return
	if not body is CharacterBody2D:
		return
	if not body.has_method("_get_effective_value"):
		return
	var player: CharacterBody2D = body
	if player.is_defeated:
		return
	if _players_inside.has(player.get_instance_id()):
		return

	# 应用效果
	var effect_data := _apply_effect(player)
	_players_inside[player.get_instance_id()] = {
		"player": player,
		"effect_data": effect_data,
	}

	print("[FieldZone] %s 进入 %s" % [player.char_data.get("name", "?"), ZONE_NAMES.get(zone_type, "?")])


func _check_initial_overlaps() -> void:
	"""区域创建时检查已在内部的物体"""
	# 需要延迟一帧让物理引擎初始化碰撞检测
	await get_tree().physics_frame
	if not zone_active or not is_instance_valid(self):
		return
	var bodies: Array = get_overlapping_bodies()
	for body in bodies:
		if body is CharacterBody2D and body.has_method("_get_effective_value"):
			_on_body_entered(body)
	if bodies.size() > 0:
		print("[FieldZone] 初始检测到%d个物体" % bodies.size())


func _on_body_exited(body: Node2D) -> void:
	"""球员离开区域"""
	if not body is CharacterBody2D:
		return
	var player: CharacterBody2D = body
	var pid: int = player.get_instance_id()

	if not _players_inside.has(pid):
		return

	# 移除效果
	var info: Dictionary = _players_inside[pid]
	_remove_effect(player, info.get("effect_data", {}))
	_players_inside.erase(pid)

	print("[FieldZone] %s 离开 %s" % [player.char_data.get("name", "?"), ZONE_NAMES.get(zone_type, "?")])


## ==================== 效果应用/移除 ====================

func _apply_effect(player: CharacterBody2D) -> Dictionary:
	"""对进入区域的球员应用效果"""
	var result: Dictionary = {}

	match zone_type:
		ZoneType.BOOST:
			# 加速：挂速度 buff（mult = effect_value）
			var buff_id: String = "zone_boost_%d_%d" % [get_instance_id(), player.get_instance_id()]
			player.add_buff(buff_id, "speed", effect_value, 0.0, remaining + 1.0, "field_zone_boost")
			result["buff_id"] = buff_id

		ZoneType.SLOW:
			# 减速：挂速度 buff（mult = 1/effect_value）
			var buff_id: String = "zone_slow_%d_%d" % [get_instance_id(), player.get_instance_id()]
			player.add_buff(buff_id, "speed", 1.0 / max(0.01, effect_value), 0.0, remaining + 1.0, "field_zone_slow")
			result["buff_id"] = buff_id

		ZoneType.DANGER:
			# 危险区：不做buff，由 _process_danger_tick 逐帧扣血
			result["tick"] = true

		ZoneType.SAFE:
			# 安全区：挂无敌灯
			player.turn_on_light("invincible", remaining + 1.0)
			result["light"] = "invincible"

	return result


func _remove_effect(player: CharacterBody2D, effect_data: Dictionary) -> void:
	"""对离开区域的球员移除效果"""
	if not player or not is_instance_valid(player):
		return

	match zone_type:
		ZoneType.BOOST, ZoneType.SLOW:
			var buff_id: String = str(effect_data.get("buff_id", ""))
			if buff_id != "" and player._buffs.has(buff_id):
				player._buffs.erase(buff_id)

		ZoneType.DANGER:
			pass  # 逐帧扣血，离开自动停止

		ZoneType.SAFE:
			# 关闭无敌灯（安全区赋予的）
			player.turn_off_light("invincible")


## ==================== 生命周期 ====================

func _expire() -> void:
	"""倒计时结束，移除所有效果并消失"""
	zone_active = false

	# 移除所有区域内球员的效果
	for pid in _players_inside:
		var info: Dictionary = _players_inside[pid]
		var player: CharacterBody2D = info.get("player", null)
		_remove_effect(player, info.get("effect_data", {}))
	_players_inside.clear()

	zone_expired.emit(self)
	queue_free()
	print("[FieldZone] %s 已消失" % ZONE_NAMES.get(zone_type, "?"))


func force_remove() -> void:
	"""外部强制移除"""
	_expire()


func get_zone_info() -> String:
	"""获取区域信息文本"""
	return "%s | %.0f×%.0f | %.1fs | 值=%.1f | 内%d人" % [
		ZONE_NAMES.get(zone_type, "?"),
		zone_size.x, zone_size.y,
		remaining,
		effect_value,
		_players_inside.size()
	]
