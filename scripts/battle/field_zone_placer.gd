## 场地效果区域放置/清除系统
## 处理鼠标操作：预览跟随、点击放置、点击选中清除
## 挂载在 FieldZoneManager 下

extends Node

## ==================== 状态枚举 ====================

enum Mode {
	NONE,
	PLACING,
	CLEARING,
}

## ==================== 状态变量 ====================

var current_mode: int = Mode.NONE
var place_params: Dictionary = {}
var remaining_ops: int = 0
var selected_for_clear: Array = []

# 工单23 F4 · D14（2026-10-04 主人裁定）：快道释放形态——预释放 600×80 预览跟随施法者，
# 单击释放=从施法者位置朝瞄准方向铺开固定长道，位置释放即固定不再跟人
const PATH_LENGTH: float = 600.0

## ==================== 视觉节点 ====================

var preview_node: Node2D = null
var highlight_nodes: Array = []
# 工单23 F4：能量快道两点绘制（OP_PLACE：第一次点击=起点，第二次=终点生成；预览实时拉伸）
var _preview_fill: ColorRect = null
var _preview_line: Line2D = null

## ==================== 信号 ====================

signal operation_finished()


## ==================== 放置模式 ====================

func start_placing(params: Dictionary, mouse_ops: int = 1) -> void:
	_cancel_internal()
	current_mode = Mode.PLACING
	place_params = params
	remaining_ops = mouse_ops
	_create_preview(params)
	set_process(true)
	print("[ZonePlacer] 进入放置模式: type=%s size=%.0f×%.0f ops=%d" % [
		str(params.get("zone_type", "?")),
		float(params.get("width", 120.0)),
		float(params.get("height", 120.0)),
		mouse_ops
	])


func _create_preview(params: Dictionary) -> void:
	"""创建鼠标跟随预览"""
	if preview_node and is_instance_valid(preview_node):
		preview_node.queue_free()

	preview_node = Node2D.new()
	preview_node.name = "ZonePlacementPreview"
	preview_node.z_index = 100

	var zone_type: int = _parse_zone_type(params.get("zone_type", 0))
	var w: float = float(params.get("width", 120.0))
	var h: float = float(params.get("height", 120.0))
	# D14：快道预览=固定 600×path_width（方向瞄准型，长度不随鼠标距离变化）
	if zone_type == 6:
		w = PATH_LENGTH
		h = maxf(float(params.get("path_width", 48.0)), 12.0)
	var half_w: float = w / 2.0
	var half_h: float = h / 2.0

	# 颜色
	var colors: Dictionary = _get_zone_colors(zone_type)
	var fill_color: Color = Color(colors.fill.r, colors.fill.g, colors.fill.b, 0.35)
	var border_color: Color = colors.border

	# 填充
	var fill := ColorRect.new()
	fill.size = Vector2(w, h)
	fill.position = Vector2(-half_w, -half_h)
	fill.color = fill_color
	preview_node.add_child(fill)
	_preview_fill = fill

	# 边框
	var line := Line2D.new()
	line.width = 2.5
	line.default_color = border_color
	var points: PackedVector2Array = [
		Vector2(-half_w, -half_h),
		Vector2(half_w, -half_h),
		Vector2(half_w, half_h),
		Vector2(-half_w, half_h),
		Vector2(-half_w, -half_h),
	]
	line.points = points
	preview_node.add_child(line)
	_preview_line = line

	# 标签
	var label := Label.new()
	label.text = _get_zone_name(zone_type)
	label.position = Vector2(-30, -half_h - 18)
	label.size = Vector2(60, 18)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", border_color)
	preview_node.add_child(label)

	get_tree().current_scene.add_child(preview_node)


## ==================== 清除模式 ====================

func start_clearing(mouse_ops: int = 1) -> void:
	_cancel_internal()
	current_mode = Mode.CLEARING
	remaining_ops = mouse_ops
	selected_for_clear.clear()
	set_process(true)
	print("[ZonePlacer] 进入清除模式: ops=%d" % mouse_ops)


## ==================== 帧处理 ====================

func _ready() -> void:
	set_process(false)


func _process(_delta: float) -> void:
	if current_mode == Mode.NONE:
		return

	if current_mode == Mode.PLACING:
		_process_placing()
	elif current_mode == Mode.CLEARING:
		_process_clearing()


func _process_placing() -> void:
	if preview_node and is_instance_valid(preview_node):
		# D14：快道预览=锚定施法者、朝瞄准方向、固定 600 长（跟随施法者直到释放）
		if _is_path_mode():
			var owner_node: Node2D = place_params.get("owner_node", null) if place_params.get("owner_node", null) != null else null
			if owner_node != null and is_instance_valid(owner_node):
				var pp: Vector2 = owner_node.global_position
				var seg: Vector2 = _get_mouse_position() - pp
				if seg.length() < 1.0:
					seg = Vector2.RIGHT
				preview_node.rotation = seg.angle()
				preview_node.global_position = pp + seg.normalized() * (PATH_LENGTH * 0.5)
				return
			# 兜底（无施法者）：旧两点绘制预览
			preview_node.global_position = _get_mouse_position()
			if place_params.has("path_from") and _preview_fill and is_instance_valid(_preview_fill):
				var from: Vector2 = place_params["path_from"]
				var seg2: Vector2 = _get_mouse_position() - from
				var length: float = maxf(seg2.length(), 1.0)
				var width: float = maxf(float(place_params.get("path_width", 48.0)), 12.0)
				preview_node.rotation = seg2.angle()
				preview_node.global_position = from + seg2 * 0.5
				_preview_fill.size = Vector2(length, width)
				_preview_fill.position = Vector2(-length * 0.5, -width * 0.5)
				if _preview_line and is_instance_valid(_preview_line):
					var hw: float = length * 0.5
					var hh: float = width * 0.5
					_preview_line.points = PackedVector2Array([
						Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh), Vector2(-hw, -hh),
					])
			return
		preview_node.global_position = _get_mouse_position()


## 工单23 F4：能量快道模式判定（zone_type=6 → 两点绘制语义）
func _is_path_mode() -> bool:
	return int(place_params.get("zone_type", -1)) == 6


func _process_clearing() -> void:
	_clear_highlights()
	var mouse_pos: Vector2 = _get_mouse_position()
	var manager = _get_manager()
	if not manager:
		return

	var hovered: Area2D = manager.get_zone_at_position(mouse_pos, 80.0)
	if hovered and not selected_for_clear.has(hovered):
		_create_highlight(hovered, false)

	for zone in selected_for_clear:
		if is_instance_valid(zone):
			_create_highlight(zone, true)


func _input(event: InputEvent) -> void:
	if current_mode == Mode.NONE:
		return

	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_on_left_click()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_on_right_click()

	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE:
			cancel_operation()


## ==================== 点击处理 ====================

func _on_left_click() -> void:
	if current_mode == Mode.PLACING:
		_place_zone()
		get_viewport().set_input_as_handled()
	elif current_mode == Mode.CLEARING:
		_clear_step()
		if current_mode == Mode.NONE:  # 刚清完最后一个
			get_viewport().set_input_as_handled()


func _place_zone(aim_pos: Variant = null) -> void:
	var mouse_pos: Vector2 = aim_pos if aim_pos is Vector2 else _get_mouse_position()
	var manager = _get_manager()
	if not manager:
		return

	# D14：快道释放=单击即放，从施法者位置朝瞄准方向铺开固定长道（释放即固定不跟人）；
	# 无施法者时兜底旧两点绘制（第一次点击=记起点，第二次=终点生成）
	if _is_path_mode():
		var owner_node: Node2D = place_params.get("owner_node", null) if place_params.get("owner_node", null) != null else null
		if owner_node != null and is_instance_valid(owner_node):
			var pts: Dictionary = path_release_points(owner_node.global_position, mouse_pos)
			place_params["path_from"] = pts["from"]
			place_params["path_to"] = pts["to"]
			manager.create_zone(place_params, pts["from"])
			remaining_ops -= 1
			print("[ZonePlacer] 快道释放 from=(%.0f,%.0f) to=(%.0f,%.0f) 剩余操作=%d" % [
				pts["from"].x, pts["from"].y, pts["to"].x, pts["to"].y, remaining_ops])
			if remaining_ops <= 0:
				_finish_operation()
			return
		if not place_params.has("path_from"):
			place_params["path_from"] = mouse_pos
			print("[ZonePlacer] 能量快道起点 (%.0f,%.0f) — 再点一次确认终点" % [mouse_pos.x, mouse_pos.y])
			return

	manager.create_zone(place_params, mouse_pos)
	remaining_ops -= 1

	print("[ZonePlacer] 放置区域 pos=(%.0f,%.0f) 剩余操作=%d" % [mouse_pos.x, mouse_pos.y, remaining_ops])

	if remaining_ops <= 0:
		_finish_operation()


## D14：快道释放点计算（纯函数可测）——从施法者位置朝瞄准方向铺开固定长度；
## 瞄准点与施法者重合（退化）时朝正右方（fail-closed 不零向量）
static func path_release_points(player_pos: Vector2, aim_pos: Vector2, length: float = PATH_LENGTH) -> Dictionary:
	var dir: Vector2 = aim_pos - player_pos
	if dir.length() < 1.0:
		dir = Vector2.RIGHT
	var to: Vector2 = player_pos + dir.normalized() * length
	return {"from": player_pos, "to": to}


func _clear_step() -> void:
	var mouse_pos: Vector2 = _get_mouse_position()
	var manager = _get_manager()
	if not manager:
		return

	var clicked: Area2D = manager.get_zone_at_position(mouse_pos, 80.0)

	if clicked and not selected_for_clear.has(clicked):
		selected_for_clear.append(clicked)
		print("[ZonePlacer] 选中区域 (%d个)" % selected_for_clear.size())
		return

	if selected_for_clear.size() > 0:
		for zone in selected_for_clear:
			if is_instance_valid(zone):
				manager.remove_zone(zone)
		print("[ZonePlacer] 清除 %d 个区域" % selected_for_clear.size())
		selected_for_clear.clear()
		remaining_ops -= 1
		_clear_highlights()

		if remaining_ops <= 0:
			_finish_operation()


func _on_right_click() -> void:
	if current_mode == Mode.CLEARING and selected_for_clear.size() > 0:
		selected_for_clear.pop_back()
	elif current_mode == Mode.PLACING:
		cancel_operation()


## ==================== 操作控制 ====================

func cancel_operation() -> void:
	_cancel_internal()
	operation_finished.emit()
	print("[ZonePlacer] 操作已取消")


func is_operating() -> bool:
	return current_mode != Mode.NONE


func _cancel_internal() -> void:
	current_mode = Mode.NONE
	place_params = {}
	remaining_ops = 0
	selected_for_clear.clear()
	_clear_highlights()
	_remove_preview()
	set_process(false)


func _finish_operation() -> void:
	_cancel_internal()
	operation_finished.emit()
	print("[ZonePlacer] 操作完成")


## ==================== 视觉辅助 ====================

func _create_highlight(zone: Area2D, is_selected: bool) -> void:
	var highlight := Line2D.new()
	highlight.width = 3.0
	var color: Color = Color(1.0, 0.3, 0.3, 0.9) if is_selected else Color(1.0, 1.0, 0.3, 0.7)
	highlight.default_color = color
	highlight.z_index = 99

	var half_w: float = zone.zone_size.x / 2.0 + 4.0
	var half_h: float = zone.zone_size.y / 2.0 + 4.0
	var pos: Vector2 = zone.global_position
	highlight.add_point(pos + Vector2(-half_w, -half_h))
	highlight.add_point(pos + Vector2(half_w, -half_h))
	highlight.add_point(pos + Vector2(half_w, half_h))
	highlight.add_point(pos + Vector2(-half_w, half_h))
	highlight.add_point(pos + Vector2(-half_w, -half_h))

	get_tree().current_scene.add_child(highlight)
	highlight_nodes.append(highlight)


func _clear_highlights() -> void:
	for node in highlight_nodes:
		if is_instance_valid(node):
			node.queue_free()
	highlight_nodes.clear()


func _remove_preview() -> void:
	if preview_node and is_instance_valid(preview_node):
		preview_node.queue_free()
	preview_node = null


## ==================== 工具 ====================

func _get_mouse_position() -> Vector2:
	var viewport = get_viewport()
	if viewport:
		return viewport.get_mouse_position() - Vector2(
			viewport.get_visible_rect().size.x / 2.0,
			viewport.get_visible_rect().size.y / 2.0
		)
	return Vector2.ZERO


func _get_manager() -> Node:
	var parent = get_parent()
	if parent and parent.has_method("create_zone"):
		return parent
	return null


func _parse_zone_type(val) -> int:
	if val is int:
		return val
	var s: String = str(val).to_lower()
	match s:
		"boost", "加速":
			return 0
		"slow", "减速":
			return 1
		"danger", "危险":
			return 2
		"safe", "安全":
			return 3
	return 0


func _get_zone_colors(zone_type: int) -> Dictionary:
	var colors: Dictionary = {
		0: {"fill": Color(0.2, 0.8, 0.2, 0.25), "border": Color(0.3, 1.0, 0.3, 0.8)},
		1: {"fill": Color(0.2, 0.2, 0.8, 0.25), "border": Color(0.3, 0.3, 1.0, 0.8)},
		2: {"fill": Color(0.8, 0.2, 0.2, 0.25), "border": Color(1.0, 0.3, 0.3, 0.8)},
		3: {"fill": Color(0.2, 0.8, 0.8, 0.25), "border": Color(0.3, 1.0, 1.0, 0.8)},
		# 6=能量快道（水色系，与 field_effect_zone ZONE_COLORS 同源；区别于加速区绿）
		6: {"fill": Color(0.1, 0.55, 0.75, 0.3), "border": Color(0.35, 0.9, 1.0, 0.85)},
	}
	return colors.get(zone_type, colors[0])


func _get_zone_name(zone_type: int) -> String:
	var names: Dictionary = {0: "加速区", 1: "减速区", 2: "危险区", 3: "安全区", 6: "能量快道"}
	return names.get(zone_type, "?")
