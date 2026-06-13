## 障碍物放置/清除系统
## 处理鼠标操作：光环跟随、点击放置、点击选中清除
## 挂载在 ObstacleManager 下

extends Node

## ==================== 状态枚举 ====================

enum Mode {
	NONE,       # 无操作
	PLACING,    # 放置模式（创造障碍）
	CLEARING    # 清除模式（清除障碍）
}

## ==================== 状态变量 ====================

var current_mode: int = Mode.NONE
var place_params: Dictionary = {}
var remaining_ops: int = 0
var clear_count: int = 0
var selected_for_clear: Array = []  # 已选中待清除的障碍物

## ==================== 视觉节点 ====================

var preview_node: Node2D = null      # 放置预览（光环跟随鼠标）
var highlight_nodes: Array = []      # 清除时的高亮选中框

## ==================== 信号 ====================

signal operation_finished()


## ==================== 放置模式 ====================

func start_placing(params: Dictionary, mouse_ops: int = 1) -> void:
	"""进入放置模式"""
	_cancel_internal()
	current_mode = Mode.PLACING
	place_params = params
	remaining_ops = mouse_ops
	_create_preview(params)
	set_process(true)
	print("[ObstaclePlacer] 进入放置模式: shape=" + str(params.get("shape", "rect")) + " 操作次数=" + str(mouse_ops))


func _create_preview(params: Dictionary) -> void:
	"""创建鼠标跟随预览"""
	if preview_node and is_instance_valid(preview_node):
		preview_node.queue_free()

	preview_node = Node2D.new()
	preview_node.name = "PlacementPreview"
	preview_node.z_index = 100

	var element_color: Color = params.get("element_color", Color(1.0, 1.0, 0.5))
	var color_alpha: Color = Color(element_color.r, element_color.g, element_color.b, 0.4)
	var shape_type: String = params.get("shape", "rect")

	match shape_type:
		"rect":
			var w: float = params.get("width", 80.0)
			var h: float = params.get("height", 30.0)
			var points: Array = [
				Vector2(-w / 2.0, -h / 2.0),
				Vector2(w / 2.0, -h / 2.0),
				Vector2(w / 2.0, h / 2.0),
				Vector2(-w / 2.0, h / 2.0)
			]
			var polygon := Polygon2D.new()
			polygon.polygon = PackedVector2Array(points)
			polygon.color = color_alpha
			preview_node.add_child(polygon)
			var line := Line2D.new()
			line.width = 2.0
			line.default_color = element_color
			for p in points:
				line.add_point(p)
			line.add_point(points[0])
			preview_node.add_child(line)
		"circle":
			var r: float = params.get("radius", 40.0)
			var points: Array = []
			for i in range(25):
				var angle: float = TAU * i / 24.0
				points.append(Vector2(cos(angle), sin(angle)) * r)
			var polygon := Polygon2D.new()
			polygon.polygon = PackedVector2Array(points)
			polygon.color = color_alpha
			preview_node.add_child(polygon)
			var line := Line2D.new()
			line.width = 2.0
			line.default_color = element_color
			for p in points:
				line.add_point(p)
			preview_node.add_child(line)
		"crescent":
			var r: float = params.get("radius", 40.0)
			var arc_angle: float = deg_to_rad(params.get("arc_angle", 120.0))
			var points := _build_crescent_points(r, arc_angle)
			var polygon := Polygon2D.new()
			polygon.polygon = PackedVector2Array(points)
			polygon.color = color_alpha
			preview_node.add_child(polygon)
			var line := Line2D.new()
			line.width = 2.0
			line.default_color = element_color
			for p in points:
				line.add_point(p)
			if points.size() > 0:
				line.add_point(points[0])
			preview_node.add_child(line)

	get_tree().current_scene.add_child(preview_node)


func _build_crescent_points(radius: float, arc_angle: float) -> Array:
	"""构建月牙形点集"""
	var points: Array = []
	var segments: int = 12
	var half_arc: float = arc_angle / 2.0
	for i in range(segments + 1):
		var angle: float = -half_arc + (arc_angle * i / segments)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	var inner_radius: float = radius * 0.6
	for i in range(segments + 1):
		var angle: float = half_arc - (arc_angle * i / segments)
		points.append(Vector2(cos(angle), sin(angle)) * inner_radius)
	return points


## ==================== 清除模式 ====================

func start_clearing(clear_count_val: int, mouse_ops: int = 1) -> void:
	"""进入清除模式"""
	_cancel_internal()
	current_mode = Mode.CLEARING
	self.clear_count = clear_count_val
	remaining_ops = mouse_ops
	selected_for_clear.clear()
	set_process(true)
	print("[ObstaclePlacer] 进入清除模式: 清除数=" + str(clear_count_val) + " 操作次数=" + str(mouse_ops))


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
	"""放置模式：光环跟随鼠标"""
	if preview_node and is_instance_valid(preview_node):
		var mouse_pos: Vector2 = _get_mouse_position()
		preview_node.global_position = mouse_pos
		# 月牙形：实时旋转凹面朝向释放球员
		if place_params.get("shape", "") == "crescent":
			var caster_pos_variant = place_params.get("caster_position", null)
			if caster_pos_variant != null:
				var caster_pos: Vector2 = Vector2(float(caster_pos_variant.x), float(caster_pos_variant.y))
				if mouse_pos.distance_to(caster_pos) > 1.0:
					var dir: Vector2 = (mouse_pos - caster_pos).normalized()
					preview_node.rotation = dir.angle()


func _process_clearing() -> void:
	"""清除模式：鼠标悬停高亮障碍物"""
	# 清除旧高亮
	_clear_highlights()

	# 查找鼠标下的障碍物
	var mouse_pos: Vector2 = _get_mouse_position()
	var manager = _get_manager()
	if not manager:
		return

	var hovered: StaticBody2D = manager.get_obstacle_at_position(mouse_pos, 50.0)
	if hovered and not selected_for_clear.has(hovered):
		_create_highlight(hovered, false)  # 悬停高亮（蓝色）

	# 已选中的高亮（红色）
	for obs in selected_for_clear:
		if is_instance_valid(obs):
			_create_highlight(obs, true)


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
	"""左键点击"""
	if current_mode == Mode.PLACING:
		_place_obstacle()
		get_viewport().set_input_as_handled()
	elif current_mode == Mode.CLEARING:
		_clear_step()
		if current_mode == Mode.NONE:  # 刚完成最后一次操作
			get_viewport().set_input_as_handled()


func _place_obstacle() -> void:
	"""放置障碍物"""
	var mouse_pos: Vector2 = _get_mouse_position()
	var manager = _get_manager()
	if not manager:
		return

	# 月牙形：内环（凹面）朝向释放技能的球员
	var rotation: float = 0.0
	var caster_pos_variant = place_params.get("caster_position", null)
	if caster_pos_variant != null and place_params.get("shape", "") == "crescent":
		# 默认月牙凹面朝左(-x)，需要旋转使凹面朝向球员
		# 方向：从球员到障碍物 = 障碍物的朝向
		var caster_pos: Vector2 = Vector2(float(caster_pos_variant.x), float(caster_pos_variant.y))
		if mouse_pos.distance_to(caster_pos) > 1.0:
			var dir: Vector2 = (mouse_pos - caster_pos).normalized()
			rotation = dir.angle()

	manager.create_obstacle(place_params, mouse_pos, rotation)
	remaining_ops -= 1

	print("[ObstaclePlacer] 放置障碍物 pos=(" + str(snapped(mouse_pos.x, 1.0)) + "," + str(snapped(mouse_pos.y, 1.0)) + ") 剩余操作=" + str(remaining_ops))

	if remaining_ops <= 0:
		_finish_operation()


func _clear_step() -> void:
	"""清除步骤：选中或落实"""
	var mouse_pos: Vector2 = _get_mouse_position()
	var manager = _get_manager()
	if not manager:
		return

	# 检查是否点在障碍物上
	var clicked: StaticBody2D = manager.get_obstacle_at_position(mouse_pos, 50.0)

	if clicked and not selected_for_clear.has(clicked):
		# 选中障碍物（添加到待清除列表）
		if selected_for_clear.size() < clear_count:
			selected_for_clear.append(clicked)
			print("[ObstaclePlacer] 选中障碍物 (" + str(selected_for_clear.size()) + "/" + str(clear_count) + ")")
		return

	# 点在场地任意地方（非障碍物）→ 落实清除
	if selected_for_clear.size() > 0:
		manager.remove_obstacles(selected_for_clear)
		print("[ObstaclePlacer] 清除 %d 个障碍物" % selected_for_clear.size())
		selected_for_clear.clear()
		remaining_ops -= 1

		_clear_highlights()

		if remaining_ops <= 0:
			_finish_operation()


func _on_right_click() -> void:
	"""右键：取消已选中的最后一个（清除模式）"""
	if current_mode == Mode.CLEARING and selected_for_clear.size() > 0:
		var removed = selected_for_clear.pop_back()
		print("[ObstaclePlacer] 取消选中 (" + str(selected_for_clear.size()) + "/" + str(clear_count) + ")")


## ==================== 操作控制 ====================

func cancel_operation() -> void:
	"""取消当前操作"""
	_cancel_internal()
	operation_finished.emit()
	print("[ObstaclePlacer] 操作已取消")


func is_operating() -> bool:
	"""是否在操作模式中"""
	return current_mode != Mode.NONE


func _cancel_internal() -> void:
	"""内部清理"""
	current_mode = Mode.NONE
	place_params = {}
	remaining_ops = 0
	clear_count = 0
	selected_for_clear.clear()
	_clear_highlights()
	_remove_preview()
	set_process(false)


func _finish_operation() -> void:
	"""完成操作"""
	_cancel_internal()
	operation_finished.emit()
	print("[ObstaclePlacer] 操作完成")


## ==================== 视觉辅助 ====================

func _create_highlight(obstacle: StaticBody2D, is_selected: bool) -> void:
	"""创建高亮框"""
	var highlight := Line2D.new()
	highlight.name = "Highlight"
	highlight.width = 3.0
	var color: Color = Color(1.0, 0.3, 0.3, 0.8) if is_selected else Color(0.3, 0.6, 1.0, 0.6)
	highlight.default_color = color
	highlight.z_index = 99

	# 简单的方形包围框
	var extent: float = 50.0
	var pos: Vector2 = obstacle.global_position
	highlight.add_point(pos + Vector2(-extent, -extent))
	highlight.add_point(pos + Vector2(extent, -extent))
	highlight.add_point(pos + Vector2(extent, extent))
	highlight.add_point(pos + Vector2(-extent, extent))
	highlight.add_point(pos + Vector2(-extent, -extent))

	get_tree().current_scene.add_child(highlight)
	highlight_nodes.append(highlight)


func _clear_highlights() -> void:
	"""清除所有高亮"""
	for node in highlight_nodes:
		if is_instance_valid(node):
			node.queue_free()
	highlight_nodes.clear()


func _remove_preview() -> void:
	"""移除预览"""
	if preview_node and is_instance_valid(preview_node):
		preview_node.queue_free()
	preview_node = null


## ==================== 工具方法 ====================

func _get_mouse_position() -> Vector2:
	"""获取鼠标在游戏世界中的位置"""
	var viewport = get_viewport()
	if viewport:
		return viewport.get_mouse_position() - Vector2(
			viewport.get_visible_rect().size.x / 2.0,
			viewport.get_visible_rect().size.y / 2.0
		)
	return Vector2.ZERO


func _get_manager() -> Node:
	"""获取 ObstacleManager"""
	var parent = get_parent()
	if parent and parent.has_method("create_obstacle"):
		return parent
	return null
