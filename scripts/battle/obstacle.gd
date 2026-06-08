## 障碍物节点
## 放置在场上的障碍物，可阻挡球的攻击
## 特征值：防御生命值、降低球速值、抵消消耗速率

extends StaticBody2D
class_name Obstacle

## ==================== 参数 ====================

var obstacle_hp: float = 50.0
var max_obstacle_hp: float = 50.0
var attack_consume_rate: float = 20.0  # 球攻击力消耗速率（/s），同时消耗障碍物HP
var speed_consume_rate: float = 20.0   # 球速消耗速率（px/s）
var source_skill: String = ""
var remaining_duration: float = 10.0
var shape_type: String = "rect"
var element_color: Color = Color(1.0, 1.0, 0.5)
var _cached_hit_radius: float = 44.0  # 缓存碰撞半径
var _cached_width: float = 80.0  # 缓存矩形宽度
var _cached_height: float = 30.0  # 缓存矩形高度
var _cached_radius: float = 40.0  # 缓存圆形/月牙半径

## ==================== 节点引用 ====================

var visual_node: Node2D = null
var hp_bar: ProgressBar = null
var duration_timer: Timer = null

## ==================== 信号 ====================

signal obstacle_destroyed(obstacle: StaticBody2D)
signal obstacle_expired(obstacle: StaticBody2D)


## ==================== 初始化 ====================

func setup(params: Dictionary) -> void:
	"""初始化障碍物参数和视觉"""
	obstacle_hp = params.get("hp", 50.0)
	max_obstacle_hp = obstacle_hp
	# 新参数优先，旧参数兼容
	attack_consume_rate = params.get("attack_consume_rate", params.get("consume_rate", 20.0))
	speed_consume_rate = params.get("speed_consume_rate", params.get("speed_reduction", 20.0))
	source_skill = params.get("source_skill", "")
	remaining_duration = params.get("duration", 10.0)
	shape_type = params.get("shape", "rect")
	element_color = params.get("element_color", Color(1.0, 1.0, 0.5))

	# 创建碰撞形状
	_create_collision(params)
	# 创建视觉
	_create_visual(params)
	# 创建HP条
	_create_hp_bar()
	# 创建持续时间计时器
	_create_duration_timer()


func _create_collision(params: Dictionary) -> void:
	"""创建碰撞形状"""
	if shape_type == "crescent":
		# 月牙形用 CollisionPolygon2D 直接支持凹多边形
		var radius: float = params.get("radius", 40.0)
		var arc_angle: float = deg_to_rad(params.get("arc_angle", 120.0))
		var raw_points := _build_crescent_points(radius, arc_angle)
		var poly := CollisionPolygon2D.new()
		poly.name = "CrescentCollision"
		var packed: PackedVector2Array = []
		for p in raw_points:
			packed.append(Vector2(p.x, p.y))
		poly.polygon = packed
		add_child(poly)
		return

	var collision := CollisionShape2D.new()
	match shape_type:
		"rect":
			var shape := RectangleShape2D.new()
			shape.size = Vector2(params.get("width", 80.0), params.get("height", 30.0))
			collision.shape = shape
		"circle":
			var shape := CircleShape2D.new()
			shape.radius = params.get("radius", 40.0)
			collision.shape = shape
		_:
			var shape := RectangleShape2D.new()
			shape.size = Vector2(80.0, 30.0)
			collision.shape = shape
	add_child(collision)

	# 缓存碰撞半径（用于球距离检测）
	match shape_type:
		"rect":
			_cached_width = params.get("width", 80.0)
			_cached_height = params.get("height", 30.0)
			_cached_hit_radius = sqrt(_cached_width * _cached_width + _cached_height * _cached_height) / 2.0 + 14.0
		"circle":
			_cached_radius = params.get("radius", 40.0)
			_cached_hit_radius = _cached_radius + 14.0
		"crescent":
			_cached_radius = params.get("radius", 40.0)
			_cached_hit_radius = _cached_radius + 14.0
		_:
			_cached_hit_radius = 44.0


func _build_crescent_points(radius: float, arc_angle: float) -> Array:
	"""构建月牙形点集"""
	var points: Array = []
	var segments: int = 12
	var half_arc: float = arc_angle / 2.0
	# 外弧
	for i in range(segments + 1):
		var angle: float = -half_arc + (arc_angle * i / segments)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	# 内弧（反向，半径小一些）
	var inner_radius: float = radius * 0.6
	for i in range(segments + 1):
		var angle: float = half_arc - (arc_angle * i / segments)
		points.append(Vector2(cos(angle), sin(angle)) * inner_radius)
	return points


func _create_visual(params: Dictionary) -> void:
	"""创建视觉节点"""
	visual_node = Node2D.new()
	visual_node.name = "Visual"
	add_child(visual_node)

	var color_with_alpha: Color = Color(element_color.r, element_color.g, element_color.b, 0.7)

	match shape_type:
		"rect":
			var rect := ColorRect.new()
			var w: float = params.get("width", 80.0)
			var h: float = params.get("height", 30.0)
			rect.size = Vector2(w, h)
			rect.position = Vector2(-w / 2.0, -h / 2.0)
			rect.color = color_with_alpha
			# 圆角
			var style := StyleBoxFlat.new()
			style.bg_color = color_with_alpha
			style.set_corner_radius_all(4)
			rect.add_theme_stylebox_override("normal", style)
			visual_node.add_child(rect)
		"circle":
			var circle := Node2D.new()
			var r: float = params.get("radius", 40.0)
			# 用多个小矩形近似圆形视觉效果
			var points: Array = []
			for i in range(24):
				var angle: float = TAU * i / 24.0
				points.append(Vector2(cos(angle), sin(angle)) * r)
			var polygon := Polygon2D.new()
			polygon.polygon = PackedVector2Array(points)
			polygon.color = color_with_alpha
			circle.add_child(polygon)
			visual_node.add_child(circle)
		"crescent":
			var crescent := Node2D.new()
			var r: float = params.get("radius", 40.0)
			var arc_angle: float = deg_to_rad(params.get("arc_angle", 120.0))
			var points := _build_crescent_points(r, arc_angle)
			var polygon := Polygon2D.new()
			polygon.polygon = PackedVector2Array(points)
			polygon.color = color_with_alpha
			crescent.add_child(polygon)
			visual_node.add_child(crescent)

	# 边框
	_create_border(params)


func _create_border(params: Dictionary) -> void:
	"""创建边框线"""
	var border_color: Color = Color(element_color.r, element_color.g, element_color.b, 1.0)
	var line := Line2D.new()
	line.width = 2.0
	line.default_color = border_color

	match shape_type:
		"rect":
			var w: float = params.get("width", 80.0) / 2.0
			var h: float = params.get("height", 30.0) / 2.0
			line.add_point(Vector2(-w, -h))
			line.add_point(Vector2(w, -h))
			line.add_point(Vector2(w, h))
			line.add_point(Vector2(-w, h))
			line.add_point(Vector2(-w, -h))
		"circle":
			var r: float = params.get("radius", 40.0)
			for i in range(25):
				var angle: float = TAU * i / 24.0
				line.add_point(Vector2(cos(angle), sin(angle)) * r)
		"crescent":
			var r: float = params.get("radius", 40.0)
			var arc_angle: float = deg_to_rad(params.get("arc_angle", 120.0))
			var points := _build_crescent_points(r, arc_angle)
			for point in points:
				line.add_point(point)
			if points.size() > 0:
				line.add_point(points[0])

	visual_node.add_child(line)


func _create_hp_bar() -> void:
	"""创建HP条"""
	hp_bar = ProgressBar.new()
	hp_bar.min_value = 0.0
	hp_bar.max_value = 100.0
	hp_bar.value = 100.0
	hp_bar.size = Vector2(40, 5)
	hp_bar.position = Vector2(-20, -45)
	hp_bar.show_percentage = false
	# 样式
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	bg_style.set_corner_radius_all(2)
	hp_bar.add_theme_stylebox_override("background", bg_style)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.2, 0.9, 0.2)
	fill_style.set_corner_radius_all(2)
	hp_bar.add_theme_stylebox_override("fill", fill_style)
	add_child(hp_bar)


func _create_duration_timer() -> void:
	"""创建持续时间计时器"""
	if remaining_duration <= 0.0:
		return
	duration_timer = Timer.new()
	duration_timer.wait_time = remaining_duration
	duration_timer.one_shot = true
	duration_timer.timeout.connect(_on_duration_expired)
	add_child(duration_timer)
	duration_timer.start()


## ==================== 球碰撞处理 ====================

func consume_frame(delta: float) -> void:
	"""每帧消耗：球卡在障碍物上时调用

	逻辑：
	- 球的攻击力以 attack_consume_rate 速率消耗，同时消耗障碍物HP
	- 球速以 speed_consume_rate 速率消耗
	- 例: 球(70攻,300速) vs 墙(20HP, 攻击消耗20/s, 速度消耗20px/s)
	  → 1s后墙破, 球以(50攻, 280速)继续飞
	"""
	var atk_consumed: float = attack_consume_rate * delta
	var spd_consumed: float = speed_consume_rate * delta

	# 消耗障碍物HP（等于球攻击力的消耗量）
	obstacle_hp -= atk_consumed

	# 更新HP条
	_update_hp_bar()


func _update_hp_bar() -> void:
	"""更新HP条"""
	if hp_bar:
		var ratio: float = (obstacle_hp / max_obstacle_hp) * 100.0
		hp_bar.value = ratio
		# HP低时变红
		if ratio < 30.0:
			var fill_style := StyleBoxFlat.new()
			fill_style.bg_color = Color(0.9, 0.2, 0.2)
			fill_style.set_corner_radius_all(2)
			hp_bar.add_theme_stylebox_override("fill", fill_style)
		elif ratio < 60.0:
			var fill_style := StyleBoxFlat.new()
			fill_style.bg_color = Color(0.9, 0.7, 0.2)
			fill_style.set_corner_radius_all(2)
			hp_bar.add_theme_stylebox_override("fill", fill_style)


## ==================== 生命周期 ====================

func _destroy() -> void:
	"""障碍物被摧毁"""
	obstacle_destroyed.emit(self)
	queue_free()


func _on_duration_expired() -> void:
	"""持续时间结束"""
	obstacle_expired.emit(self)
	queue_free()


func remove() -> void:
	"""外部调用移除（清除标签用）"""
	queue_free()


## ==================== 查询 ====================

func is_alive() -> bool:
	"""障碍物是否存活"""
	return obstacle_hp > 0.0 and is_instance_valid(self)


func get_hp_ratio() -> float:
	"""获取HP百分比"""
	if max_obstacle_hp <= 0.0:
		return 0.0
	return obstacle_hp / max_obstacle_hp


func get_hit_radius() -> float:
	"""获取碰撞半径（球检测用）"""
	return _cached_hit_radius
