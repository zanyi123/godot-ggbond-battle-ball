## 3D 场地区域管理器
## 从 2.5D 版 field_zone.gd 移植，适配 3D 坐标（XZ平面，Y为高度）
## 场地结构：蓝色禁区 + 矩形内场 + 两侧外场

extends Node3D

# 场地总尺寸（蓝色外框）
const FIELD_WIDTH: float = 1300.0   # X 轴
const FIELD_LENGTH: float = 780.0   # Z 轴（对应 2D 的 Y 轴）

# 内场（黄色）- 比赛主区域
const INNER: Dictionary = {
	"x": -380.0, "z": -260.0,
	"width": 760.0, "length": 520.0
}

# 中圈半径
const CENTER_CIRCLE_RADIUS: float = 60.0

# 左外场（队B那边）- 主体 + 上臂 + 下臂
const LEFT_OUTER: Dictionary = {
	"main": {"x": -510.0, "z": -325.0, "width": 130.0, "length": 650.0},
	"top_arm": {"x": -380.0, "z": -325.0, "width": 130.0, "length": 65.0},
	"bot_arm": {"x": -380.0, "z": 260.0, "width": 130.0, "length": 65.0}
}

# 右外场（队A那边）- 主体 + 上臂 + 下臂
const RIGHT_OUTER: Dictionary = {
	"main": {"x": 380.0, "z": -325.0, "width": 130.0, "length": 650.0},
	"top_arm": {"x": 250.0, "z": -325.0, "width": 130.0, "length": 65.0},
	"bot_arm": {"x": 250.0, "z": 260.0, "width": 130.0, "length": 65.0}
}

# 换场配置
const TRANSITION_DURATION: float = 0.5

# 球员在场地的Y坐标（地面高度）
const GROUND_Y: float = 0.0

enum ZoneType {
	BLUE_BOUNDARY,
	INNER_FIELD,
	OUTER_LEFT,
	OUTER_RIGHT
}

enum ViolationType {
	NONE,
	BLUE_BOUNDARY,         # 越出蓝色禁区
	CROSS_MIDLINE,          # 越过中线进入对方内场
	CROSS_FIELD_BOUNDARY    # 越过内外场边界进入外场
}

# 信号
signal player_violated(player: CharacterBody3D, violation_type: int)
signal player_transition_completed(player: CharacterBody3D)

# 正在传送的球员
var transitioning_players: Dictionary = {}

# 球员数据扩展（队伍、惩罚状态）
var player_data: Dictionary = {}  # {player: {team: "a"/"b", is_penalized: bool}}


func _process(delta: float) -> void:
	var to_remove: Array[CharacterBody3D] = []
	for player: CharacterBody3D in transitioning_players:
		var info: Dictionary = transitioning_players[player]
		info.elapsed += delta
		var t: float = clampf(info.elapsed / TRANSITION_DURATION, 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)  # smoothstep
		player.global_position = info.start.lerp(info.target, t)
		player.set_physics_process(false)
		
		if info.elapsed >= TRANSITION_DURATION:
			to_remove.append(player)
	
	for player: CharacterBody3D in to_remove:
		transitioning_players.erase(player)
		player.set_physics_process(true)
		player_transition_completed.emit(player)


# ===== 注册球员 =====

func register_player(player: CharacterBody3D, team: String) -> void:
	player_data[player] = {
		"team": team,
		"is_penalized": false
	}


func get_player_team(player: CharacterBody3D) -> String:
	if player_data.has(player):
		return player_data[player].get("team", "a")
	return "a"


func is_player_penalized(player: CharacterBody3D) -> bool:
	if player_data.has(player):
		return player_data[player].get("is_penalized", false)
	return false


func set_player_penalized(player: CharacterBody3D, penalized: bool) -> void:
	if player_data.has(player):
		player_data[player]["is_penalized"] = penalized


# ===== 区域判定 =====

func get_zone_at(pos: Vector3) -> int:
	var pos_2d := Vector2(pos.x, pos.z)
	if _is_in_inner(pos_2d):
		return ZoneType.INNER_FIELD
	if _is_in_outer(pos_2d, LEFT_OUTER):
		return ZoneType.OUTER_LEFT
	if _is_in_outer(pos_2d, RIGHT_OUTER):
		return ZoneType.OUTER_RIGHT
	return ZoneType.BLUE_BOUNDARY


func is_in_playable_area(pos: Vector3) -> bool:
	return get_zone_at(pos) != ZoneType.BLUE_BOUNDARY


func check_boundary_violation(player: CharacterBody3D) -> bool:
	return get_zone_at(player.global_position) == ZoneType.BLUE_BOUNDARY


func check_midline_violation(player: CharacterBody3D) -> int:
	var pos: Vector3 = player.global_position
	var pos_2d := Vector2(pos.x, pos.z)
	
	if not _is_in_inner(pos_2d):
		return ViolationType.NONE
	
	var team := get_player_team(player)
	if team == "a" and pos.x > 0:
		return ViolationType.CROSS_MIDLINE
	elif team == "b" and pos.x < 0:
		return ViolationType.CROSS_MIDLINE
	
	return ViolationType.NONE


func check_field_boundary_violation(player: CharacterBody3D) -> int:
	if is_player_penalized(player):
		return ViolationType.NONE
	
	var pos: Vector3 = player.global_position
	var pos_2d := Vector2(pos.x, pos.z)
	var team := get_player_team(player)
	
	if _is_in_inner(pos_2d):
		return ViolationType.NONE
	
	if team == "a" and _is_in_outer(pos_2d, LEFT_OUTER):
		return ViolationType.CROSS_FIELD_BOUNDARY
	elif team == "b" and _is_in_outer(pos_2d, RIGHT_OUTER):
		return ViolationType.CROSS_FIELD_BOUNDARY
	
	return ViolationType.NONE


func check_zone_violation(player: CharacterBody3D) -> int:
	if check_boundary_violation(player):
		return ViolationType.BLUE_BOUNDARY
	
	var field_boundary_violation := check_field_boundary_violation(player)
	if field_boundary_violation != ViolationType.NONE:
		return field_boundary_violation
	
	var midline_violation := check_midline_violation(player)
	if midline_violation != ViolationType.NONE:
		return midline_violation
	
	return ViolationType.NONE


# ===== 换场传送 =====

func start_field_transition(player: CharacterBody3D, offset_index: int = 0) -> void:
	var team := get_player_team(player)
	var outer: Dictionary
	
	if team == "a":
		outer = RIGHT_OUTER  # 队A(左)犯规 → 送到右外场(对手内场背后那侧)
	else:
		outer = LEFT_OUTER   # 队B(右)犯规 → 送到左外场(对手内场背后那侧)
	
	var base_center: Vector2 = _rect_center_2d(outer.main)
	var target_2d: Vector2 = _calc_non_overlapping_pos(base_center, offset_index)
	var target := Vector3(target_2d.x, GROUND_Y, target_2d.y)
	
	transitioning_players[player] = {
		"start": player.global_position,
		"target": target,
		"elapsed": 0.0
	}
	print("[Field3D] 球员传送到对手的外场 (偏移%d)" % offset_index)


func is_player_transitioning(player: CharacterBody3D) -> bool:
	return player in transitioning_players


# ===== 中心点查询 =====

func get_inner_center() -> Vector3:
	var center_2d := _rect_center_2d(INNER)
	return Vector3(center_2d.x, GROUND_Y, center_2d.y)


func get_outer_center(outer: Dictionary) -> Vector3:
	var center_2d := _rect_center_2d(outer.main)
	return Vector3(center_2d.x, GROUND_Y, center_2d.y)


func get_left_outer_center() -> Vector3:
	return get_outer_center(LEFT_OUTER)


func get_right_outer_center() -> Vector3:
	return get_outer_center(RIGHT_OUTER)


# ===== 包含检测 =====

func _is_in_inner(pos: Vector2) -> bool:
	return _in_rect(pos, INNER)


func _is_in_outer(pos: Vector2, outer: Dictionary) -> bool:
	return _in_rect(pos, outer.main) or _in_rect(pos, outer.top_arm) or _in_rect(pos, outer.bot_arm)


# ===== 工具函数 =====

func _in_rect(pos: Vector2, r: Dictionary) -> bool:
	var rx: float = r.get("x", 0.0)
	var rz: float = r.get("z", r.get("y", 0.0))
	var rw: float = r.get("width", 0.0)
	var rl: float = r.get("length", r.get("height", 0.0))
	return pos.x >= rx and pos.x <= rx + rw and pos.y >= rz and pos.y <= rz + rl


func _rect_center_2d(r: Dictionary) -> Vector2:
	var rx: float = r.get("x", 0.0)
	var rz: float = r.get("z", r.get("y", 0.0))
	var rw: float = r.get("width", 0.0)
	var rl: float = r.get("length", r.get("height", 0.0))
	return Vector2(rx + rw / 2.0, rz + rl / 2.0)


func _calc_non_overlapping_pos(base: Vector2, index: int) -> Vector2:
	const SPACING: float = 50.0
	var angle: float = index * (PI / 3.0)
	var spacing: float = SPACING if index > 0 else 0.0
	return base + Vector2(cos(angle), sin(angle)) * spacing


# ===== 获取违规文本 =====

static func get_violation_text(violation_type: int) -> String:
	match violation_type:
		ViolationType.BLUE_BOUNDARY:
			return "越出禁区"
		ViolationType.CROSS_MIDLINE:
			return "越中线"
		ViolationType.CROSS_FIELD_BOUNDARY:
			return "越内外场边界"
		_:
			return "未知违规"
