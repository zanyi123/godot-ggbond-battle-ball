extends Node2D
## 场地区域管理器
## 场地结构：蓝色禁区 + 凹字形外场 + 矩形内场
## 外场形状：主体（竖长）+ 上下包裹臂（向内场方向延伸）
## 内外场直接相接，内场中线分割两队半场，中圈发球区域

# 场地总尺寸（蓝色外框）
const FIELD_WIDTH: float = 1300.0
const FIELD_HEIGHT: float = 780.0

# 内场（黄色）- 比赛主区域
const INNER: Dictionary = {
	"x": -380.0, "y": -260.0,
	"width": 760.0, "height": 520.0,
	"color": Color(0.65, 0.65, 0.65)
}

# 中圈半径（篮球中圈样式）
const CENTER_CIRCLE_RADIUS: float = 60.0

# 左外场（橙黄，队B那边）- 凹字形，直接与内场相接
const LEFT_OUTER: Dictionary = {
	"main": {"x": -510.0, "y": -325.0, "width": 130.0, "height": 650.0},
	"top_arm": {"x": -380.0, "y": -325.0, "width": 130.0, "height": 65.0},
	"bot_arm": {"x": -380.0, "y": 260.0, "width": 130.0, "height": 65.0},
	"color": Color(0.9, 0.6, 0.2),
	"team": "b"
}

# 右外场（橙黄，队A那边）- 凹字形，直接与内场右侧相接
const RIGHT_OUTER: Dictionary = {
	"main": {"x": 380.0, "y": -325.0, "width": 130.0, "height": 650.0},
	"top_arm": {"x": 250.0, "y": -325.0, "width": 130.0, "height": 65.0},
	"bot_arm": {"x": 250.0, "y": 260.0, "width": 130.0, "height": 65.0},
	"color": Color(0.9, 0.6, 0.2),
	"team": "a"
}

# 换场配置
const TRANSITION_DURATION: float = 0.5

enum ZoneType {
	BLUE_BOUNDARY,
	INNER_FIELD,
	OUTER_LEFT,
	OUTER_RIGHT
}

enum ViolationType {
	NONE,
	BLUE_BOUNDARY,           # 越出蓝色禁区
	CROSS_MIDLINE,            # 越过中线进入对方内场
	CROSS_FIELD_BOUNDARY      # 越过内外场边界进入外场（同侧）
}

# 信号：球员越线
signal player_violated(player: CharacterBody2D, violation_type: ViolationType)
signal player_transition_completed(player: CharacterBody2D)

var transitioning_players: Dictionary = {}


func _ready() -> void:
	_build_visual_field()


func _process(delta: float) -> void:
	var to_remove: Array[CharacterBody2D] = []
	for player: CharacterBody2D in transitioning_players:
		var info: Dictionary = transitioning_players[player]
		info.elapsed += delta
		var t: float = clampf(info.elapsed / TRANSITION_DURATION, 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)  # smoothstep
		player.global_position = info.start.lerp(info.target, t)
		player.set_physics_process(false)
		
		if info.elapsed >= TRANSITION_DURATION:
			to_remove.append(player)
	
	for player: CharacterBody2D in to_remove:
		transitioning_players.erase(player)
		player.set_physics_process(true)
		player_transition_completed.emit(player)


# ===== 区域判定 =====

func get_zone_at(pos: Vector2) -> int:
	if _is_in_inner(pos):
		return ZoneType.INNER_FIELD
	if _is_in_outer(pos, LEFT_OUTER):
		return ZoneType.OUTER_LEFT
	if _is_in_outer(pos, RIGHT_OUTER):
		return ZoneType.OUTER_RIGHT
	return ZoneType.BLUE_BOUNDARY


func is_in_playable_area(pos: Vector2) -> bool:
	return get_zone_at(pos) != ZoneType.BLUE_BOUNDARY


func check_boundary_violation(player: CharacterBody2D) -> bool:
	"""检查是否进入蓝色禁区（越界失分）"""
	return get_zone_at(player.global_position) == ZoneType.BLUE_BOUNDARY


func check_midline_violation(player: CharacterBody2D) -> ViolationType:
	"""检查是否越过中线进入对方内场"""
	var pos: Vector2 = player.global_position
	
	# 必须在内场中才检查越中线（被惩罚的球员在外场，不检查）
	if not _is_in_inner(pos):
		return ViolationType.NONE
	
	# 内场中线位置 x = 0
	# 队A不能进入 x > 0（右半场），队B不能进入 x < 0（左半场）
	if player.team == "a" and pos.x > 0:
		return ViolationType.CROSS_MIDLINE
	elif player.team == "b" and pos.x < 0:
		return ViolationType.CROSS_MIDLINE
	
	return ViolationType.NONE


func check_field_boundary_violation(player: CharacterBody2D) -> ViolationType:
	"""检查是否越过内外场边界进入外场（同侧）"""
	# 被惩罚的球员可以在外场内移动，不检查
	var penalized_val = player.get("is_penalized")
	if penalized_val != null and penalized_val:
		return ViolationType.NONE
	
	var pos: Vector2 = player.global_position
	
	# 队A不能进入左外场（x < -380）
	# 队B不能进入右外场（x > 380）
	if player.team == "a" and pos.x < -380:
		return ViolationType.CROSS_FIELD_BOUNDARY
	elif player.team == "b" and pos.x > 380:
		return ViolationType.CROSS_FIELD_BOUNDARY
	
	return ViolationType.NONE


func check_zone_violation(player: CharacterBody2D) -> ViolationType:
	"""检查所有场地违规（蓝色禁区 + 越中线 + 越内外场边界）"""
	# 优先检查蓝色禁区
	if check_boundary_violation(player):
		return ViolationType.BLUE_BOUNDARY
	
	# 检查越内外场边界（未惩罚球员不能进入外场）
	var field_boundary_violation := check_field_boundary_violation(player)
	if field_boundary_violation != ViolationType.NONE:
		return field_boundary_violation
	
	# 检查越中线
	var midline_violation := check_midline_violation(player)
	if midline_violation != ViolationType.NONE:
		return midline_violation
	
	return ViolationType.NONE


func start_field_transition(player: CharacterBody2D, offset_index: int = 0) -> void:
	"""失分球员平移到自己的外场（支持防重叠偏移）"""
	var target: Vector2
	var outer: Dictionary
	if player.team == "a":
		outer = RIGHT_OUTER  # 队A去右外场（自己的外场）
	else:
		outer = LEFT_OUTER   # 队B去左外场（自己的外场）
	
	# 计算外场中心，并根据偏移量计算不重叠位置
	var base_center: Vector2 = _rect_center(outer.main)
	target = _calc_non_overlapping_pos(base_center, offset_index)
	
	transitioning_players[player] = {
		"start": player.global_position,
		"target": target,
		"elapsed": 0.0
	}
	print("[Field] %s 换场 → 自己的外场 (偏移%d)" % [(player.char_data.get("name") if player.char_data.has("name") else ""), offset_index])


func _calc_non_overlapping_pos(base: Vector2, index: int) -> Vector2:
	"""计算不重叠的传送位置（围绕中心呈圆形分布）"""
	const SPACING: float = 50.0  # 间距
	var angle: float = index * (PI / 3.0)  # 每60度一个位置
	var spacing: float = SPACING if index > 0 else 0.0
	return base + Vector2(cos(angle), sin(angle)) * spacing


func is_player_transitioning(player: CharacterBody2D) -> bool:
	return player in transitioning_players


# ===== 中心点查询 =====

func get_inner_center() -> Vector2:
	return _rect_center(INNER)

func get_outer_center(outer: Dictionary) -> Vector2:
	return _rect_center(outer.main)

func get_left_outer_center() -> Vector2:
	return _rect_center(LEFT_OUTER.main)

func get_right_outer_center() -> Vector2:
	return _rect_center(RIGHT_OUTER.main)

func get_opponent_outer_center(team: String) -> Vector2:
	if team == "a":
		return _rect_center(LEFT_OUTER.main)  # 队A的对手外场（左）
	return _rect_center(RIGHT_OUTER.main)   # 队B的对手外场（右）


# ===== 包含检测 =====

func _is_in_inner(pos: Vector2) -> bool:
	return _in_rect(pos, INNER)

func _is_in_outer(pos: Vector2, outer: Dictionary) -> bool:
	# 凹字形 = 主体 + 上臂 + 下臂，三块任一命中即可
	return _in_rect(pos, outer.main) or _in_rect(pos, outer.top_arm) or _in_rect(pos, outer.bot_arm)


# ===== 视觉构建 =====

func _build_visual_field() -> void:
	# 1. 蓝色禁区背景
	var blue := ColorRect.new()
	blue.size = Vector2(FIELD_WIDTH, FIELD_HEIGHT)
	blue.position = Vector2(-FIELD_WIDTH / 2, -FIELD_HEIGHT / 2)
	blue.color = Color(0.15, 0.25, 0.55)
	add_child(blue)
	
	# 2. 内场（黄色）
	_draw_zone(INNER, INNER.color)
	
	# 3. 左外场（凹字形：主体 + 上臂 + 下臂）
	_draw_zone(LEFT_OUTER.main, LEFT_OUTER.color)
	_draw_zone(LEFT_OUTER.top_arm, LEFT_OUTER.color)
	_draw_zone(LEFT_OUTER.bot_arm, LEFT_OUTER.color)
	
	# 4. 右外场（凹字形：主体 + 上臂 + 下臂）
	_draw_zone(RIGHT_OUTER.main, RIGHT_OUTER.color)
	_draw_zone(RIGHT_OUTER.top_arm, RIGHT_OUTER.color)
	_draw_zone(RIGHT_OUTER.bot_arm, RIGHT_OUTER.color)
	
	# 5. 中线
	var mid := ColorRect.new()
	mid.size = Vector2(4, INNER.height)
	mid.position = Vector2(-2, INNER.y)
	mid.color = Color.WHITE
	add_child(mid)
	
	# 6. 中圈圆（白色圆环）
	_draw_center_circle()
	
	# 6. 白色框线
	_draw_border_rect(INNER, 2.0)
	_draw_border_rect(LEFT_OUTER.main, 2.0)
	_draw_border_rect(LEFT_OUTER.top_arm, 2.0)
	_draw_border_rect(LEFT_OUTER.bot_arm, 2.0)
	_draw_border_rect(RIGHT_OUTER.main, 2.0)
	_draw_border_rect(RIGHT_OUTER.top_arm, 2.0)
	_draw_border_rect(RIGHT_OUTER.bot_arm, 2.0)
	_draw_border_rect({"x": -FIELD_WIDTH / 2, "y": -FIELD_HEIGHT / 2, "width": FIELD_WIDTH, "height": FIELD_HEIGHT}, 3.0)
	
	# 7. 队伍标签
	_label("← 队B外场", Vector2(-510, -345), Color(0.9, 0.6, 0.2))
	_label("队A半场", Vector2(-200, -275), Color.YELLOW)
	_label("队B半场", Vector2(100, -275), Color.YELLOW)
	_label("队A外场 →", Vector2(400, -345), Color(0.9, 0.6, 0.2))


func _draw_zone(zone: Dictionary, color: Color) -> void:
	var rect := ColorRect.new()
	rect.size = Vector2(zone.width, zone.height)
	rect.position = Vector2(zone.x, zone.y)
	rect.color = color
	add_child(rect)


func _draw_border_rect(zone: Dictionary, border_width: float) -> void:
	var x: float = zone.x
	var y: float = zone.y
	var rw: float = zone.width
	var rh: float = zone.height
	var bw: float = border_width
	var c := Color.WHITE
	# 上
	var t := ColorRect.new()
	t.size = Vector2(rw, bw)
	t.position = Vector2(x, y)
	t.color = c
	add_child(t)
	# 下
	var b := ColorRect.new()
	b.size = Vector2(rw, bw)
	b.position = Vector2(x, y + rh - bw)
	b.color = c
	add_child(b)
	# 左
	var l := ColorRect.new()
	l.size = Vector2(bw, rh)
	l.position = Vector2(x, y)
	l.color = c
	add_child(l)
	# 右
	var r := ColorRect.new()
	r.size = Vector2(bw, rh)
	r.position = Vector2(x + rw - bw, y)
	r.color = c
	add_child(r)


func _label(text: String, pos: Vector2, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", 12)
	add_child(lbl)


func _draw_center_circle() -> void:
	"""绘制白色中圈圆环（类似篮球中圈）"""
	var circle_center := Vector2(0, 0)  # 内场中心
	var segments := 64
	
	# 绘制圆环外圈（白色线条）
	for i in range(segments):
		var angle1 := deg_to_rad(float(i) * 360.0 / float(segments))
		var angle2 := deg_to_rad(float(i + 1) * 360.0 / float(segments))
		
		var p1 := circle_center + Vector2(cos(angle1), sin(angle1)) * CENTER_CIRCLE_RADIUS
		var p2 := circle_center + Vector2(cos(angle2), sin(angle2)) * CENTER_CIRCLE_RADIUS
		
		var line := Line2D.new()
		line.width = 3.0
		line.default_color = Color.WHITE
		line.add_point(p1)
		line.add_point(p2)
		add_child(line)


# ===== 工具 =====

func _in_rect(pos: Vector2, r: Dictionary) -> bool:
	return pos.x >= r.x and pos.x <= r.x + r.width and pos.y >= r.y and pos.y <= r.y + r.height

func _rect_center(r: Dictionary) -> Vector2:
	return Vector2(r.x + r.width / 2.0, r.y + r.height / 2.0)
