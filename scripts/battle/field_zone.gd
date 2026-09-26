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
	_draw_outer_field_border(LEFT_OUTER, 2.0)
	_draw_outer_field_border(RIGHT_OUTER, 2.0)
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


func _draw_outer_field_border(outer: Dictionary, border_width: float) -> void:
	"""绘制凹字形外场整体边框（不画内部子区域之间的分隔线）"""
	var m: Dictionary = outer.main    # 主体
	var ta: Dictionary = outer.top_arm  # 上臂
	var ba: Dictionary = outer.bot_arm  # 下臂
	var bw: float = border_width
	var c := Color.WHITE

	# 计算整体外包围盒
	var all_x: Array[float] = [m.x, m.x + m.width, ta.x, ta.x + ta.width, ba.x, ba.x + ba.width]
	var all_y: Array[float] = [m.y, m.y + m.height, ta.y, ta.y + ta.height, ba.y, ba.y + ba.height]
	var min_x: float = all_x.min()
	var max_x: float = all_x.max()
	var min_y: float = all_y.min()
	var max_y: float = all_y.max()

	# 判断臂在哪一侧（左外场：主体在左，臂在右；右外场：主体在右，臂在左）
	var arms_on_right: bool = (ta.x > m.x)

	# 用Line2D绘制外轮廓（凹字形路径）
	var line := Line2D.new()
	line.width = bw * 2.0  # Line2D宽度是全宽
	line.default_color = c

	var points: PackedVector2Array = []

	if arms_on_right:
		# 左外场形状：主体左侧 → 主体上侧 → 上臂上侧 → 上臂右侧 → 上臂下侧(回到主体范围) →
		# 主体内侧上部 → 主体内侧下部 → 下臂上侧 → 下臂右侧 → 下臂下侧 → 主体下侧 → 主体左侧
		var main_left: float = m.x
		var main_right: float = m.x + m.width
		var arm_right: float = ta.x + ta.width
		var arm_top_top: float = ta.y
		var arm_top_bot: float = ta.y + ta.height
		var arm_bot_top: float = ba.y
		var arm_bot_bot: float = ba.y + ba.height

		points.append(Vector2(main_left, m.y))           # 左上角
		points.append(Vector2(main_right, m.y))          # 主体右上角
		points.append(Vector2(main_right, arm_top_top))  # 到上臂顶
		points.append(Vector2(arm_right, arm_top_top))   # 上臂右上
		points.append(Vector2(arm_right, arm_top_bot))   # 上臂右下
		points.append(Vector2(main_right, arm_top_bot))  # 回到主体右侧
		points.append(Vector2(main_right, arm_bot_top))  # 到下臂顶
		points.append(Vector2(arm_right, arm_bot_top))   # 下臂右上
		points.append(Vector2(arm_right, arm_bot_bot))   # 下臂右下
		points.append(Vector2(main_right, arm_bot_bot))  # 回到主体右侧
		points.append(Vector2(main_right, m.y + m.height))  # 主体右下角
		points.append(Vector2(main_left, m.y + m.height))   # 左下角
		points.append(Vector2(main_left, m.y))              # 回到左上角
	else:
		# 右外场形状（镜像）
		var main_right: float = m.x + m.width
		var main_left: float = m.x
		var arm_left: float = ta.x
		var arm_top_top: float = ta.y
		var arm_top_bot: float = ta.y + ta.height
		var arm_bot_top: float = ba.y
		var arm_bot_bot: float = ba.y + ba.height

		points.append(Vector2(main_right, m.y))          # 右上角
		points.append(Vector2(main_left, m.y))           # 主体左上角
		points.append(Vector2(main_left, arm_top_top))   # 到上臂顶
		points.append(Vector2(arm_left, arm_top_top))    # 上臂左上
		points.append(Vector2(arm_left, arm_top_bot))    # 上臂左下
		points.append(Vector2(main_left, arm_top_bot))   # 回到主体左侧
		points.append(Vector2(main_left, arm_bot_top))   # 到下臂顶
		points.append(Vector2(arm_left, arm_bot_top))    # 下臂左上
		points.append(Vector2(arm_left, arm_bot_bot))    # 下臂左下
		points.append(Vector2(main_left, arm_bot_bot))   # 回到主体左侧
		points.append(Vector2(main_left, m.y + m.height))   # 主体左下角
		points.append(Vector2(main_right, m.y + m.height))  # 右下角
		points.append(Vector2(main_right, m.y))              # 回到右上角

	line.points = points
	add_child(line)


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


# =====================================================================
# ===== 场地知识库（13号工单：技能AI与球员AI共用的场地认知共享层）=====
# =====================================================================
## 设计要点（13工单§二/§三）：
## - 纯增量静态查询层：只读本文件上方权威常量，不改任何执法逻辑（第二真相禁令）
## - 全静态零状态 → 技能AI原语/球员AI/测试可经 preload 直查（确定性，无感知收口问题）；
##   个体场地语义（my_zone/in_outer 等）仍走 ctx 单口由 manager 组装（红线延伸，Q9）
## - 语义口径：own/enemy 以执法权威（check_midline/check_field_boundary）为准：
##   队a半场=x≤0（左）、队b半场=x≥0（右）；流放区 a=右外场、b=左外场（start_field_transition）
## - 球门锚点（GOAL_A/GOAL_B）现存 ai_manager/spirit_ai_manager 两份重复定义且与中线规则
##   存在语义疑点（a锚(300,0)在敌半侧），知识库暂不收录，待集成窗口统一后迁移（Q9登记）

## 区域通行规则语义表（zone 语义名 → 规则一句话；AI 可查询）
const KNOWLEDGE_ZONE_RULES: Dictionary = {
	"inner_own": "己方半场：自由通行",
	"inner_enemy": "对方半场：未流放球员越中线违规",
	"outer_own": "己方流放区：仅流放/转移球员可驻留",
	"outer_enemy": "对方流放区：未流放球员越界违规",
	"center_circle": "中圈发球区（内场语义）",
	"out_of_bounds": "蓝色禁区：越界失分",
}

## 球门区纵深默认值（放置语义用，像素=GD单位铁律）
const KNOWLEDGE_GOAL_DEPTH: float = 60.0
## 己方白线内侧默认贴线内缩
const KNOWLEDGE_LINE_INSET: float = 12.0


## 语义区域归属（team 给出时输出 own/enemy 语义，缺省输出方位语义）
static func knowledge_zone_of(pos: Vector2, team: String = "") -> String:
	var in_inner := _k_in_rect(pos, INNER)
	var in_left := _k_in_outer_static(pos, LEFT_OUTER)
	var in_right := _k_in_outer_static(pos, RIGHT_OUTER)
	if not (in_inner or in_left or in_right):
		return "out_of_bounds"
	if in_left:
		if team == "b":
			return "outer_own"
		return "outer_enemy" if team == "a" else "outer_left"
	if in_right:
		if team == "a":
			return "outer_own"
		return "outer_enemy" if team == "b" else "outer_right"
	# 内场：中圈优先（子语义）
	if pos.distance_to(Vector2.ZERO) <= CENTER_CIRCLE_RADIUS:
		return "center_circle"
	if team == "a":
		return "inner_own" if pos.x <= 0.0 else "inner_enemy"
	if team == "b":
		return "inner_own" if pos.x >= 0.0 else "inner_enemy"
	return "inner"


## 白线/关键线段表（line_id → {a,b}；由权威常量推导，非手抄坐标）
static func _knowledge_lines() -> Dictionary:
	var ix: float = INNER.x
	var iy: float = INNER.y
	var ix2: float = INNER.x + INNER.width
	var iy2: float = INNER.y + INNER.height
	var lm: Dictionary = LEFT_OUTER.main
	var rm: Dictionary = RIGHT_OUTER.main
	var lt: Dictionary = LEFT_OUTER.top_arm
	var rt: Dictionary = RIGHT_OUTER.top_arm
	var lb: Dictionary = LEFT_OUTER.bot_arm
	var rb: Dictionary = RIGHT_OUTER.bot_arm
	return {
		"midline": {"a": Vector2(0, iy), "b": Vector2(0, iy2)},
		"inner_top": {"a": Vector2(ix, iy), "b": Vector2(ix2, iy)},
		"inner_bottom": {"a": Vector2(ix, iy2), "b": Vector2(ix2, iy2)},
		"inner_left": {"a": Vector2(ix, iy), "b": Vector2(ix, iy2)},
		"inner_right": {"a": Vector2(ix2, iy), "b": Vector2(ix2, iy2)},
		# 左外场（队b流放区）凹字形轮廓
		"outer_left_face": {"a": Vector2(lm.x, lm.y), "b": Vector2(lm.x, lm.y + lm.height)},
		"outer_left_top": {"a": Vector2(lm.x, lm.y), "b": Vector2(lt.x + lt.width, lt.y)},
		"outer_left_bottom": {"a": Vector2(lm.x, lm.y + lm.height), "b": Vector2(lb.x + lb.width, lb.y + lb.height)},
		"outer_left_arm_gate_top": {"a": Vector2(lt.x + lt.width, lt.y), "b": Vector2(lt.x + lt.width, lt.y + lt.height)},
		"outer_left_arm_gate_bot": {"a": Vector2(lb.x + lb.width, lb.y), "b": Vector2(lb.x + lb.width, lb.y + lb.height)},
		"outer_left_arm_base_top": {"a": Vector2(lt.x, lt.y + lt.height), "b": Vector2(lt.x + lt.width, lt.y + lt.height)},
		"outer_left_arm_base_bot": {"a": Vector2(lb.x, lb.y), "b": Vector2(lb.x + lb.width, lb.y)},
		# 右外场（队a流放区）凹字形轮廓（镜像）
		"outer_right_face": {"a": Vector2(rm.x + rm.width, rm.y), "b": Vector2(rm.x + rm.width, rm.y + rm.height)},
		"outer_right_top": {"a": Vector2(rm.x + rm.width, rm.y), "b": Vector2(rt.x, rt.y)},
		"outer_right_bottom": {"a": Vector2(rm.x + rm.width, rm.y + rm.height), "b": Vector2(rb.x, rb.y + rb.height)},
		"outer_right_arm_gate_top": {"a": Vector2(rt.x, rt.y), "b": Vector2(rt.x, rt.y + rt.height)},
		"outer_right_arm_gate_bot": {"a": Vector2(rb.x, rb.y), "b": Vector2(rb.x, rb.y + rb.height)},
		"outer_right_arm_base_top": {"a": Vector2(rt.x, rt.y + rt.height), "b": Vector2(rt.x + rt.width, rt.y + rt.height)},
		"outer_right_arm_base_bot": {"a": Vector2(rb.x, rb.y), "b": Vector2(rb.x + rb.width, rb.y)},
	}


## 到任意白线/关键线的距离（像素；未知 line_id 返回 -1）
static func knowledge_dist_to_line(pos: Vector2, line_id: String) -> float:
	var lines := _knowledge_lines()
	if not lines.has(line_id):
		return -1.0
	var seg: Dictionary = lines[line_id]
	return pos.distance_to(_k_seg_closest(pos, seg["a"], seg["b"]))


## 走位是否越过指定线段（含端点接触；平行/共线按不交叉处理）
static func knowledge_would_cross_line(from: Vector2, to: Vector2, line_id: String) -> bool:
	var lines := _knowledge_lines()
	if not lines.has(line_id):
		return false
	var seg: Dictionary = lines[line_id]
	return _k_seg_intersect(from, to, seg["a"], seg["b"])


## 外场通道口（两臂之间的开口，救援/回流规则的几何接入点；side="left"/"right"）
static func knowledge_outer_gate_segment(side: String) -> Dictionary:
	if side == "left":
		return {"a": Vector2(-250.0, INNER.y), "b": Vector2(-250.0, INNER.y + INNER.height)}
	return {"a": Vector2(250.0, INNER.y), "b": Vector2(250.0, INNER.y + INNER.height)}


static func knowledge_outer_gate_point(side: String) -> Vector2:
	var seg := knowledge_outer_gate_segment(side)
	return ((seg["a"] as Vector2) + (seg["b"] as Vector2)) * 0.5


## 己方流放区入口（队a=右外场口(250,0)、队b=左外场口(-250,0)；start_field_transition 口径）
static func knowledge_own_gate_point(team: String) -> Vector2:
	return knowledge_outer_gate_point("right") if team == "a" else knowledge_outer_gate_point("left")


## 敌方流放区入口（队a→左口、队b→右口；"堵外场入口"放置语义用）
static func knowledge_enemy_gate_point(team: String) -> Vector2:
	return knowledge_outer_gate_point("left") if team == "a" else knowledge_outer_gate_point("right")


## 最近通道口（返回 pos/side/dist）
static func knowledge_nearest_gate(pos: Vector2) -> Dictionary:
	var left := knowledge_outer_gate_point("left")
	var right := knowledge_outer_gate_point("right")
	if pos.distance_to(left) <= pos.distance_to(right):
		return {"pos": left, "side": "left", "dist": pos.distance_to(left)}
	return {"pos": right, "side": "right", "dist": pos.distance_to(right)}


## 球门区纵深点：己方半场底线内侧 depth 处（执法权威口径：a=左底线、b=右底线）
static func knowledge_goal_area_point(team: String, depth: float = KNOWLEDGE_GOAL_DEPTH) -> Vector2:
	if team == "a":
		return Vector2(INNER.x + depth, 0)
	return Vector2(INNER.x + INNER.width - depth, 0)


## 贴己方白线内侧点（沿己方底线内缩 inset；y 跟随目标点并夹回内场纵深带）
static func knowledge_own_line_inner_point(team: String, y: float = 0.0, inset: float = KNOWLEDGE_LINE_INSET) -> Vector2:
	var y_clamped := clampf(y, INNER.y + 40.0, INNER.y + INNER.height - 40.0)
	if team == "a":
		return Vector2(INNER.x + inset, y_clamped)
	return Vector2(INNER.x + INNER.width - inset, y_clamped)


## 规则问答：该走位是否违规（几何口径；返回 ""/"out_of_bounds"/"cross_midline"/"cross_field_boundary"）
## 注意：流放豁免由调用方按 player.is_penalized 处理（与实例侧执法函数同口径），本层只看几何
static func knowledge_would_violate(team: String, from: Vector2, to: Vector2) -> String:
	var zone_to := knowledge_zone_of(to)
	if zone_to == "out_of_bounds":
		return "out_of_bounds"
	var semantic := knowledge_zone_of(to, team)
	if semantic == "outer_enemy":
		return "cross_field_boundary"
	if semantic == "inner_enemy":
		return "cross_midline"
	return ""


## 规则问答：流放球员当前能否回内场（救援规则接入点；现版无回流实装=false）
static func knowledge_rescue_rule_active() -> bool:
	return false


static func _k_in_rect(pos: Vector2, r: Dictionary) -> bool:
	return pos.x >= float(r.x) and pos.x <= float(r.x) + float(r.width) \
			and pos.y >= float(r.y) and pos.y <= float(r.y) + float(r.height)


static func _k_in_outer_static(pos: Vector2, outer: Dictionary) -> bool:
	return _k_in_rect(pos, outer.main) or _k_in_rect(pos, outer.top_arm) or _k_in_rect(pos, outer.bot_arm)


static func _k_seg_closest(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.0001:
		return a
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return a + ab * t


static func _k_seg_intersect(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) -> bool:
	var d1 := p2 - p1
	var d2 := p4 - p3
	var denom := d1.cross(d2)
	if absf(denom) < 0.0001:
		return false
	var t := (p3 - p1).cross(d2) / denom
	var u := (p3 - p1).cross(d1) / denom
	return t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0
