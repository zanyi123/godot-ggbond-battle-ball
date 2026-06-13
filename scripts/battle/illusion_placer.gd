## 幻象放置/清除系统
## 处理鼠标操作：两种放置模式 + 清除模式
## 挂载在 IllusionManager 下
##
## 放置模式：
##   1. any（任意放置）：鼠标为半径生成预放置圆，可放置在场地内
##      - 左键1次生成1个，连续可放多个（mouse_ops=上限）
##      - 不在场地内→预放置圆消失（禁止放置）
##   2. near（近身放置）：强制生成1个
##      - 鼠标悬停球员→球员边缘高亮（预选择）
##      - 以球员为中心生成180度预放置扇形（半径固定100px）
##      - 鼠标控制扇形转动（可360）
##      - 左键确认→该扇形内随机位置生成幻象
##
## 清除模式：鼠标选中幻象（高亮框）→ 左键确认清除

extends Node

## ==================== 状态枚举 ====================

enum Mode { NONE, PLACING_ANY, PLACING_NEAR, CLEARING }

## ==================== 场地边界（与 ball.gd 一致）====================

const FIELD_X_MIN: float = -510.0
const FIELD_X_MAX: float = 510.0
const FIELD_Y_MIN: float = -325.0
const FIELD_Y_MAX: float = 325.0

const PLACE_RADIUS: float = 30.0   # 任意放置预览圆半径
const NEAR_RADIUS: float = 100.0   # 近身扇形半径
const NEAR_HALF_ARC: float = 90.0  # 扇形半弧度（180度）

## ==================== 状态变量 ====================

var current_mode: int = Mode.NONE
var place_params: Dictionary = {}
var remaining_ops: int = 0
var source_player: CharacterBody2D = null

## ==================== 视觉节点 ====================

var preview_node: Node2D = null       # 预放置圆
var sector_node: Node2D = null        # 近身扇形
var highlight_circle: Line2D = null   # 球员高亮
var clear_highlights: Array = []      # 清除选中高亮框
var selected_for_clear: Array = []

## ==================== 信号 ====================

signal operation_finished()


## ==================== 放置模式 ====================

func start_placing(params: Dictionary, mouse_ops: int = 1) -> void:
	_cancel_internal()
	source_player = params.get("source_player", null)
	if not source_player or not is_instance_valid(source_player):
		push_error("[IllusionPlacer] 无效的源球员")
		return

	var mode_str: String = str(params.get("place_mode", "any"))
	place_params = params
	remaining_ops = mouse_ops

	if mode_str == "near":
		current_mode = Mode.PLACING_NEAR
		remaining_ops = 1  # 近身强制1个
		_create_sector_preview()
	else:
		current_mode = Mode.PLACING_ANY
		_create_circle_preview()

	set_process(true)
	print("[IllusionPlacer] 进入放置模式: mode=%s ops=%d source=%s" % [
		mode_str, remaining_ops, source_player.team
	])


func _create_circle_preview(params_unused: Dictionary = {}) -> void:
	"""任意放置：鼠标跟随的预放置圆"""
	_remove_preview()
	preview_node = Node2D.new()
	preview_node.name = "IllusionCirclePreview"
	preview_node.z_index = 100

	# 外圆（边框）
	var line := Line2D.new()
	line.width = 2.0
	line.default_color = Color(0.7, 0.7, 1.0, 0.7)
	var pts: PackedVector2Array = _circle_points(PLACE_RADIUS, 24)
	line.points = pts
	preview_node.add_child(line)

	# 填充
	var fill := ColorRect.new()
	fill.size = Vector2(PLACE_RADIUS * 2, PLACE_RADIUS * 2)
	fill.position = Vector2(-PLACE_RADIUS, -PLACE_RADIUS)
	fill.color = Color(0.5, 0.5, 1.0, 0.2)
	var style := StyleBoxFlat.new()
	style.bg_color = fill.color
	style.set_corner_radius_all(int(PLACE_RADIUS))
	fill.add_theme_stylebox_override("normal", style)
	preview_node.add_child(fill)

	get_tree().current_scene.add_child(preview_node)


func _create_sector_preview() -> void:
	"""近身放置：以球员为中心的扇形预览"""
	_remove_preview()
	sector_node = Node2D.new()
	sector_node.name = "IllusionSectorPreview"
	sector_node.z_index = 99
	get_tree().current_scene.add_child(sector_node)
	# 扇形内容在 _process 里随鼠标方向实时重建


## ==================== 清除模式 ====================

func start_clearing(mouse_ops: int = 1) -> void:
	_cancel_internal()
	current_mode = Mode.CLEARING
	remaining_ops = mouse_ops
	selected_for_clear.clear()
	set_process(true)
	print("[IllusionPlacer] 进入清除模式: ops=%d" % mouse_ops)


## ==================== 帧处理 ====================

func _ready() -> void:
	set_process(false)


func _process(_delta: float) -> void:
	if current_mode == Mode.NONE:
		return

	match current_mode:
		Mode.PLACING_ANY:
			_process_placing_any()
		Mode.PLACING_NEAR:
			_process_placing_near()
		Mode.CLEARING:
			_process_clearing()


func _process_placing_any() -> void:
	if not preview_node or not is_instance_valid(preview_node):
		return
	var mouse_pos: Vector2 = _get_mouse_position()
	preview_node.global_position = mouse_pos
	# 场地内判定：超出则隐藏（预放置圆消失）
	var in_field: bool = _is_in_field(mouse_pos)
	preview_node.visible = in_field


func _process_placing_near() -> void:
	if not source_player or not is_instance_valid(source_player):
		return
	var mouse_pos: Vector2 = _get_mouse_position()
	var player_pos: Vector2 = source_player.global_position
	var hover_dist: float = player_pos.distance_to(mouse_pos)

	# 鼠标悬停球员判定（半径40）
	var hovering_player: bool = hover_dist <= 40.0
	_update_player_highlight(hovering_player)

	# 扇形方向：球员→鼠标
	var dir: Vector2 = (mouse_pos - player_pos).normalized()
	var angle_deg: float = rad_to_deg(dir.angle())

	# 重建扇形多边形
	_rebuild_sector(player_pos, angle_deg)


func _process_clearing() -> void:
	_clear_highlights()
	var mouse_pos: Vector2 = _get_mouse_position()
	var manager = _get_manager()
	if not manager:
		return

	var hovered = manager.get_illusion_at_position(mouse_pos, 60.0)
	if hovered and not selected_for_clear.has(hovered):
		_create_clear_highlight(hovered, false)

	for ill in selected_for_clear:
		if is_instance_valid(ill):
			_create_clear_highlight(ill, true)


## ==================== 输入 ====================

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


func _on_left_click() -> void:
	match current_mode:
		Mode.PLACING_ANY:
			_place_any()
		Mode.PLACING_NEAR:
			_place_near()
		Mode.CLEARING:
			_clear_step()
	get_viewport().set_input_as_handled()


func _on_right_click() -> void:
	if current_mode == Mode.CLEARING and selected_for_clear.size() > 0:
		selected_for_clear.pop_back()
	elif current_mode == Mode.PLACING_ANY or current_mode == Mode.PLACING_NEAR:
		cancel_operation()


func _place_any() -> void:
	"""任意放置：左键1次生成1个"""
	var mouse_pos: Vector2 = _get_mouse_position()
	if not _is_in_field(mouse_pos):
		return  # 不在场地内，禁止放置
	var manager = _get_manager()
	if not manager:
		return
	manager.create_illusion(source_player, place_params, mouse_pos)
	remaining_ops -= 1
	print("[IllusionPlacer] 任意放置 pos=(%.0f,%.0f) 剩余=%d" % [mouse_pos.x, mouse_pos.y, remaining_ops])
	if remaining_ops <= 0:
		_finish_operation()


func _place_near() -> void:
	"""近身放置：扇形内随机位置生成1个"""
	if not source_player or not is_instance_valid(source_player):
		return
	var mouse_pos: Vector2 = _get_mouse_position()
	var player_pos: Vector2 = source_player.global_position
	var dir: Vector2 = (mouse_pos - player_pos).normalized()
	var base_angle: float = dir.angle()
	# 在 ±NEAR_HALF_ARC 内随机角度
	var random_offset: float = deg_to_rad(randf_range(-NEAR_HALF_ARC, NEAR_HALF_ARC))
	var final_angle: float = base_angle + random_offset
	# 随机半径（0.4~1.0 倍）
	var random_r: float = NEAR_RADIUS * randf_range(0.4, 1.0)
	var pos: Vector2 = player_pos + Vector2(cos(final_angle), sin(final_angle)) * random_r

	# 场地内判定
	if not _is_in_field(pos):
		print("[IllusionPlacer] 近身放置位置超出场地，取消")
		_finish_operation()
		return

	var manager = _get_manager()
	if not manager:
		return
	manager.create_illusion(source_player, place_params, pos)
	remaining_ops = 0
	_finish_operation()


func _clear_step() -> void:
	var mouse_pos: Vector2 = _get_mouse_position()
	var manager = _get_manager()
	if not manager:
		return

	var clicked = manager.get_illusion_at_position(mouse_pos, 60.0)
	if clicked and not selected_for_clear.has(clicked):
		selected_for_clear.append(clicked)
		return

	if selected_for_clear.size() > 0:
		for ill in selected_for_clear:
			if is_instance_valid(ill):
				manager.remove_illusion(ill)
		print("[IllusionPlacer] 清除 %d 个幻象" % selected_for_clear.size())
		selected_for_clear.clear()
		remaining_ops -= 1
		_clear_highlights()
		if remaining_ops <= 0:
			_finish_operation()


## ==================== 操作控制 ====================

func cancel_operation() -> void:
	_cancel_internal()
	operation_finished.emit()
	print("[IllusionPlacer] 操作已取消")


func is_operating() -> bool:
	return current_mode != Mode.NONE


func _cancel_internal() -> void:
	current_mode = Mode.NONE
	place_params = {}
	remaining_ops = 0
	source_player = null
	selected_for_clear.clear()
	_remove_preview()
	_remove_sector()
	_remove_player_highlight()
	_clear_highlights()
	set_process(false)


func _finish_operation() -> void:
	_cancel_internal()
	operation_finished.emit()
	print("[IllusionPlacer] 操作完成")


## ==================== 视觉辅助 ====================

func _update_player_highlight(hovering: bool) -> void:
	if hovering:
		if not highlight_circle or not is_instance_valid(highlight_circle):
			highlight_circle = Line2D.new()
			highlight_circle.width = 3.0
			highlight_circle.default_color = Color(1.0, 1.0, 0.3, 0.9)
			highlight_circle.z_index = 100
			highlight_circle.points = _circle_points(34.0, 28)
			get_tree().current_scene.add_child(highlight_circle)
		highlight_circle.global_position = source_player.global_position
	else:
		_remove_player_highlight()


func _rebuild_sector(center: Vector2, angle_deg: float) -> void:
	"""重建扇形预览（中心+朝向）"""
	if not sector_node or not is_instance_valid(sector_node):
		return
	for c in sector_node.get_children():
		c.queue_free()
	sector_node.global_position = center

	# 扇形多边形点集
	var pts: PackedVector2Array = [Vector2.ZERO]
	var segments: int = 16
	for i in range(segments + 1):
		var a: float = deg_to_rad(angle_deg - NEAR_HALF_ARC + (180.0 * i / segments))
		pts.append(Vector2(cos(a), sin(a)) * NEAR_RADIUS)

	var poly := _make_polygon(pts, Color(0.7, 0.7, 1.0, 0.2), Color(0.7, 0.7, 1.0, 0.6))
	sector_node.add_child(poly)


func _make_polygon(points: PackedVector2Array, fill_color: Color, border_color: Color) -> Node:
	"""构造填充多边形 + 边框线"""
	var container := Node2D.new()
	var poly := Polygon2D.new()
	poly.polygon = points
	poly.color = fill_color
	container.add_child(poly)

	var line := Line2D.new()
	line.width = 2.0
	line.default_color = border_color
	var line_pts: PackedVector2Array = points.duplicate()
	line_pts.append(points[1] if points.size() > 1 else Vector2.ZERO)  # 闭合
	line.points = line_pts
	container.add_child(line)
	return container


func _create_clear_highlight(ill: Illusion, is_selected: bool) -> void:
	var hl := Line2D.new()
	hl.width = 3.0
	hl.default_color = Color(1.0, 0.3, 0.3, 0.9) if is_selected else Color(1.0, 1.0, 0.3, 0.7)
	hl.z_index = 99
	hl.points = _circle_points(32.0, 24)
	hl.global_position = ill.global_position
	get_tree().current_scene.add_child(hl)
	clear_highlights.append(hl)


func _clear_highlights() -> void:
	for n in clear_highlights:
		if is_instance_valid(n):
			n.queue_free()
	clear_highlights.clear()


func _remove_preview() -> void:
	if preview_node and is_instance_valid(preview_node):
		preview_node.queue_free()
	preview_node = null


func _remove_sector() -> void:
	if sector_node and is_instance_valid(sector_node):
		sector_node.queue_free()
	sector_node = null


func _remove_player_highlight() -> void:
	if highlight_circle and is_instance_valid(highlight_circle):
		highlight_circle.queue_free()
	highlight_circle = null


## ==================== 工具 ====================

func _circle_points(radius: float, segments: int) -> PackedVector2Array:
	var pts: PackedVector2Array = []
	for i in range(segments + 1):
		var a: float = TAU * i / segments
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts


func _is_in_field(pos: Vector2) -> bool:
	return pos.x >= FIELD_X_MIN and pos.x <= FIELD_X_MAX and pos.y >= FIELD_Y_MIN and pos.y <= FIELD_Y_MAX


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
	if parent and parent.has_method("create_illusion"):
		return parent
	return null
