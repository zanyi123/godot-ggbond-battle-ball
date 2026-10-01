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
	HEAL,     # 波5 #3 治疗区（持续回血）
	VISION,   # 波6 #9 视野迷雾（敌方 AI 感知削弱；视觉迷雾归美术）
	ENERGY_PATH,  # 工单23 F4 能量快道（条带型带方向；持续注能维持；路径增益下发召唤物）
}

## ==================== 配置 ====================

const ZONE_COLORS: Dictionary = {
	ZoneType.BOOST: {"fill": Color(0.2, 0.8, 0.2, 0.25), "border": Color(0.3, 1.0, 0.3, 0.8)},
	ZoneType.SLOW: {"fill": Color(0.2, 0.2, 0.8, 0.25), "border": Color(0.3, 0.3, 1.0, 0.8)},
	ZoneType.DANGER: {"fill": Color(0.8, 0.2, 0.2, 0.25), "border": Color(1.0, 0.3, 0.3, 0.8)},
	ZoneType.SAFE: {"fill": Color(0.2, 0.8, 0.8, 0.25), "border": Color(0.3, 1.0, 1.0, 0.8)},
	ZoneType.HEAL: {"fill": Color(0.4, 0.9, 0.4, 0.22), "border": Color(0.5, 1.0, 0.5, 0.8)},
	ZoneType.VISION: {"fill": Color(0.15, 0.1, 0.25, 0.35), "border": Color(0.4, 0.3, 0.6, 0.8)},
	ZoneType.ENERGY_PATH: {"fill": Color(0.1, 0.55, 0.75, 0.22), "border": Color(0.35, 0.9, 1.0, 0.85)},
}

const ZONE_NAMES: Dictionary = {
	ZoneType.BOOST: "加速区",
	ZoneType.SLOW: "减速区",
	ZoneType.DANGER: "危险区",
	ZoneType.SAFE: "安全区",
	ZoneType.HEAL: "治疗区",
	ZoneType.VISION: "视野迷雾",
	ZoneType.ENERGY_PATH: "能量快道",
}

# 波5 #12 zone 作用于球：穿越信号（皮影原则——zone 只发信号，球侧消费）
signal zone_ball_passed(zone_type: int, mods: Dictionary)

# 工单23 F4：能量快道——召唤物进出转发信号（entity=入 "summon" 分组的实体，F1 定稿前约定）
# 球员/球不广播（路径增益对象=召唤物）；manager 层聚合转发（F1 只订一处）
signal entity_entered_path(entity: Node2D)
signal entity_exited_path(entity: Node2D)
signal path_depleted(zone: FieldEffectZone)  # 注能耗尽/施法者失效 → 提前消散（23a §2.4 已批语义）

## ==================== 状态 ====================

var zone_type: int = ZoneType.BOOST
var zone_size: Vector2 = Vector2(120.0, 120.0)
var duration: float = 10.0
var remaining: float = 10.0
var zone_id: String = ""
var source_skill: String = ""

## 效果参数
var effect_value: float = 1.5    # 加速/减速倍率 或 每秒伤害值 或 每秒治疗值
var zone_active: bool = true
# 波5 #12 zone 作用于球
var affect_ball: Dictionary = {}         # {dmg_pct, speed_pct}（空=不作用于球）
var ball_ref: Node2D = null              # 球引用（manager 注入）
var _ball_inside: bool = false           # 球在区内状态（重复穿越判定）
var perception_scale: float = 0.5        # 波6 #9：雾内敌方感知倍率
var caster_team: String = ""             # 波6 #9 P1修正：施法者队伍（本方不受迷雾影响）

## 工单23 F4 能量快道参数
var path_from: Vector2 = Vector2.ZERO    # 条带起点（世界坐标）
var path_to: Vector2 = Vector2.ZERO      # 条带终点
var path_width: float = 48.0             # 条带宽
var energy_per_sec: float = 2.0          # 持续注能速率（从施法者 spirit_energy 扣）
var path_buffs: Dictionary = {}          # 路径增益参数表（原样下发 summon_manager，zone 不解释）
var owner_node: Node2D = null            # 注能主体（施法者；失效/被击败=路径消散）
var has_owner: bool = false              # 是否曾有主（区分"无主自然到期"与"有主已失效消散"——freed 对象 == null 恒真，不能靠空判）

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
	# 波5 #12 zone 作用于球：affect_ball={dmg_pct, speed_pct}（可选）
	affect_ball = params.get("affect_ball", {}) if params.get("affect_ball", {}) is Dictionary else {}
	# 波6 #9 视野迷雾：雾内感知倍率（<1 削弱）
	perception_scale = float(params.get("perception_scale", 0.5))
	caster_team = str(params.get("caster_team", ""))

	# 工单23 F4 能量快道：条带化（缺 path 参数 → 退化短道 fail-closed，不崩）
	if zone_type == ZoneType.ENERGY_PATH:
		var pf: Variant = params.get("path_from", null)
		var pt: Variant = params.get("path_to", null)
		path_from = pf if typeof(pf) == TYPE_VECTOR2 else global_position
		path_to = pt if typeof(pt) == TYPE_VECTOR2 else global_position + Vector2(0, -120.0)
		path_width = maxf(float(params.get("path_width", 48.0)), 12.0)
		energy_per_sec = maxf(float(params.get("energy_per_sec", 2.0)), 0.0)
		path_buffs = params.get("path_buffs", {}) if params.get("path_buffs", {}) is Dictionary else {}
		var on: Variant = params.get("owner_node", null)
		owner_node = on if on != null and is_instance_valid(on) and on is Node2D else null
		has_owner = owner_node != null
		# 条带：中心=(from+to)/2，长=|to-from|，宽=path_width，rotation 对齐连线
		var seg: Vector2 = path_to - path_from
		if seg.length() < 1.0:
			path_to = path_from + Vector2(0, -120.0)  # 零长防退化
			seg = path_to - path_from
		zone_size = Vector2(seg.length(), path_width)
		rotation = seg.angle()
		global_position = (path_from + path_to) * 0.5

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
		"heal", "治疗", "治疗区":
			return ZoneType.HEAL
		"vision", "迷雾", "视野迷雾":
			return ZoneType.VISION
		"energy_path", "energy", "快道", "能量快道":
			return ZoneType.ENERGY_PATH
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

	# 工单23 F4：能量快道方向箭头（本地 x 正向两枚 V 形，指示 from→to 流向）
	if zone_type == ZoneType.ENERGY_PATH:
		for ax in [zone_size.x * 0.2, zone_size.x * 0.42]:
			var arrow := Line2D.new()
			arrow.width = 2.0
			arrow.default_color = colors.border
			arrow.z_index = 1
			var s: float = minf(path_width * 0.28, 12.0)
			arrow.points = PackedVector2Array([
				Vector2(ax - s, -s), Vector2(ax + s, 0), Vector2(ax - s, s),
			])
			add_child(arrow)


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
	# 波5 #3 治疗区：每帧回血（走 player 公开 heal，禁疗自动生效）
	elif zone_type == ZoneType.HEAL:
		_process_heal_tick(delta)
	# 工单23 F4 能量快道：持续注能维持（耗尽/施法者失效=提前消散，23a §2.4 已批）
	elif zone_type == ZoneType.ENERGY_PATH:
		_process_energy_path_tick(delta)

	# 波5 #12 zone 作用于球：球穿越感应（一次性；离开后可重复触发）
	if not affect_ball.is_empty() and ball_ref and is_instance_valid(ball_ref) and ball_ref.is_active:
		var half: Vector2 = zone_size * 0.5
		var local: Vector2 = ball_ref.global_position - global_position
		var inside: bool = absf(local.x) <= half.x and absf(local.y) <= half.y
		if inside and not _ball_inside:
			_ball_inside = true
			zone_ball_passed.emit(zone_type, affect_ball.duplicate())
			print("[FieldZone] 球穿越区域! type=%d mods=%s" % [zone_type, str(affect_ball)])
		elif not inside and _ball_inside:
			_ball_inside = false

	# 倒计时结束
	if remaining <= 0.0:
		_expire()


func _process_danger_tick(delta: float) -> void:
	"""危险区：每秒对区域内球员造成伤害（P2-5：走 player 公开接口，无越权直调）"""
	var dps: float = effect_value
	if _players_inside.is_empty():
		return
	for player_id in _players_inside:
		var info: Dictionary = _players_inside[player_id]
		var player: CharacterBody2D = info.get("player", null)
		if player and is_instance_valid(player) and not player.is_defeated:
			var defense_resist: float = player.get_defense_resist()
			var reduction_rate: float = minf(defense_resist / 100.0, 0.8)
			var dmg: float = dps * delta * (1.0 - reduction_rate)
			player.drain_stamina(dmg)


## 波5 #3 治疗区：区域内球员每秒回血（走 player 公开 heal——禁疗灯/heal_block 自动生效）
func _process_heal_tick(delta: float) -> void:
	if _players_inside.is_empty():
		return
	for player_id in _players_inside:
		var info: Dictionary = _players_inside[player_id]
		var player: CharacterBody2D = info.get("player", null)
		if player and is_instance_valid(player) and not player.is_defeated:
			player.heal(effect_value * delta)


## 工单23 F4 能量快道：持续注能维持（23a §2.4 已批语义）
## 施法者 spirit_energy 每秒扣 energy_per_sec；扣尽/施法者失效或被击败 → 路径提前消散
## 无 owner_node（fail-closed 缺引用）→ 不扣能，按 duration 自然到期
func _process_energy_path_tick(delta: float) -> void:
	if not has_owner:
		return  # 无主路径（建道即无引用）：不扣能，自然到期
	if not is_instance_valid(owner_node) or owner_node.is_defeated:
		_deplete("施法者失效")
		return
	var energy: float = float(owner_node.get("spirit_energy"))
	if energy <= 0.0:
		_deplete("能量耗尽")
		return
	var left := maxf(energy - energy_per_sec * delta, 0.0)
	owner_node.set("spirit_energy", left)
	if left <= 0.0:
		_deplete("能量耗尽")


## 注能终止 → 提前消散（走统一 _expire 管线：先清球员效果再 emit expired）
func _deplete(reason: String) -> void:
	path_depleted.emit(self)
	var oname := "?"
	if owner_node != null and is_instance_valid(owner_node):
		oname = str(owner_node.get("character_id"))
	print("[FieldZone] 能量快道消散: %s (owner=%s)" % [reason, oname])
	_expire()


## 条带几何查询（纯几何，供 summon_manager/融合判定调用；to_local 自带旋转）
func contains_point(pos: Vector2) -> bool:
	if zone_type != ZoneType.ENERGY_PATH:
		return false
	var local: Vector2 = to_local(pos)
	return absf(local.x) <= zone_size.x * 0.5 and absf(local.y) <= zone_size.y * 0.5


## 路径方向（from→to 单位向量；零长防护）
func direction() -> Vector2:
	var seg: Vector2 = path_to - path_from
	return seg.normalized() if seg.length() >= 1.0 else Vector2.UP


## ==================== 进出区域 ====================

func _on_body_entered(body: Node2D) -> void:
	"""球员进入区域"""
	if not zone_active:
		return
	# 工单23 F4：召唤物进入能量快道 → 转发信号（summon 分组约定=F1 实体入组；球员/球不广播）
	if zone_type == ZoneType.ENERGY_PATH and body.is_in_group("summon"):
		entity_entered_path.emit(body)
		print("[FieldZone] 召唤物进入能量快道: %s" % body.name)
		return
	if not body is CharacterBody2D:
		return
	if not body.has_method("get_defense_resist"):
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
		if body is CharacterBody2D and body.has_method("get_defense_resist"):
			_on_body_entered(body)
	if bodies.size() > 0:
		print("[FieldZone] 初始检测到%d个物体" % bodies.size())


func _on_body_exited(body: Node2D) -> void:
	"""球员离开区域"""
	# 工单23 F4：召唤物离开能量快道 → 转发信号（与 entered 对称；不进球员移除逻辑）
	if zone_type == ZoneType.ENERGY_PATH and body.is_in_group("summon"):
		entity_exited_path.emit(body)
		return
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
			if buff_id != "":
				player.remove_buff(buff_id)  # P2-5：走公开接口，不直删 _buffs

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
