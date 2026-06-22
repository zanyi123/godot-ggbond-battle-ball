extends Node2D
## 技能轮廓绘制节点（2026-06-19）
## 挂在 Node2D（球/球员）下，用 _draw 自绘轮廓，避免 Control 节点坐标系混乱
## 不用 class_name（避免 Godot 类型注册时序问题），通过 preload 引用
##
## 两种绘制模式：
##   - ring: 圆环外膜（球/球员类标签），以父节点为中心绘制半透明圆 + 实色边
##   - strip: 朝向边缘条带（场地标签），在父节点朝向那一侧绘制色带


enum DrawMode { RING, STRIP }

var draw_mode: int = DrawMode.RING
var ring_radius: float = 28.0
var ring_width: float = 5.0
var strip_dir: Vector2 = Vector2.RIGHT  # 条带方向（单位向量，四方向之一）
var strip_thickness: float = 8.0
var base_color: Color = Color(0.6, 0.6, 0.6, 0.55)
var border_color: Color = Color(0.6, 0.6, 0.6, 1.0)


## 配置为圆环模式
func setup_ring(radius: float, width: float, color: Color, alpha: float) -> void:
	draw_mode = DrawMode.RING
	ring_radius = radius
	ring_width = width
	base_color = Color(color.r, color.g, color.b, alpha)
	border_color = Color(color.r, color.g, color.b, 1.0)
	z_index = 5
	queue_redraw()


## 配置为朝向条带模式
func setup_strip(radius: float, facing: Vector2, color: Color, alpha: float) -> void:
	draw_mode = DrawMode.STRIP
	ring_radius = radius
	# 把朝向量化到四方向
	if abs(facing.x) >= abs(facing.y):
		strip_dir = Vector2(1.0 if facing.x >= 0 else -1.0, 0.0)
	else:
		strip_dir = Vector2(0.0, 1.0 if facing.y >= 0 else -1.0)
	base_color = Color(color.r, color.g, color.b, alpha)
	border_color = Color(color.r, color.g, color.b, 1.0)
	z_index = 6
	queue_redraw()


func _draw() -> void:
	match draw_mode:
		DrawMode.RING:
			_draw_ring()
		DrawMode.STRIP:
			_draw_strip()


## 绘制圆环外膜：中心半透明圆 + 实色边框
func _draw_ring() -> void:
	var outer_r: float = ring_radius + ring_width
	# 半透明填充圆
	draw_circle(Vector2.ZERO, outer_r, base_color)
	# 实色外边框（发光感）
	draw_arc(Vector2.ZERO, outer_r, 0.0, TAU, 48, border_color, 2.0)


## 绘制朝向条带：在朝向那一侧画一条圆角矩形色带
func _draw_strip() -> void:
	var half_len: float = ring_radius
	var half_thick: float = strip_thickness / 2.0
	# 条带中心 = 沿朝向方向偏移到边缘
	var center: Vector2 = strip_dir * ring_radius
	# 构造矩形（沿朝向方向的边在圆周外侧）
	var rect: Rect2
	if strip_dir.x != 0.0:
		# 左右朝向：竖条
		rect = Rect2(center.x - half_thick, -half_len, strip_thickness, half_len * 2.0)
	else:
		# 上下朝向：横条
		rect = Rect2(-half_len, center.y - half_thick, half_len * 2.0, strip_thickness)
	draw_rect(rect, base_color, true)
	draw_rect(rect, border_color, false, 1.5)
