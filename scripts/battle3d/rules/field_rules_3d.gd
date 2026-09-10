## 3D 侧白线规则镜像（battle3d/rules · Phase 3 类二验证）
## 常量与判定逻辑逐字镜像 scripts/battle/field_zone.gd（权威），仅改造成纯函数
## （不依赖 player 对象：team/pos/is_penalized 由 bridge 从 2D 层读出喂入）。
## 用途：① bridge 每帧与 2D field_zone.check_zone_violation 双轨比对（不一致 push_error）
##      ② 3D 画框叠画的常量来源
## 返回码与 field_zone.ViolationType 整数值一致：0=NONE 1=BLUE_BOUNDARY 2=CROSS_MIDLINE 3=CROSS_FIELD_BOUNDARY
class_name FieldRules3D
extends Object

## ==================== 常量（镜像 field_zone.gd，禁止另起数值） ====================
const FIELD_WIDTH: float = 1300.0
const FIELD_HEIGHT: float = 780.0
const INNER_X_MIN: float = -380.0
const INNER_X_MAX: float = 380.0
const INNER_Y_MIN: float = -260.0
const INNER_Y_MAX: float = 260.0
const CENTER_CIRCLE_RADIUS: float = 60.0
const MIDLINE_X: float = 0.0

## 左外场凹字形（队B 专属）：主体 + 上臂 + 下臂
const LEFT_OUTER_MAIN := Rect2(-510.0, -325.0, 130.0, 650.0)
const LEFT_OUTER_TOP_ARM := Rect2(-380.0, -325.0, 130.0, 65.0)
const LEFT_OUTER_BOT_ARM := Rect2(-380.0, 260.0, 130.0, 65.0)
## 右外场凹字形（队A 专属）
const RIGHT_OUTER_MAIN := Rect2(380.0, -325.0, 130.0, 650.0)
const RIGHT_OUTER_TOP_ARM := Rect2(250.0, -325.0, 130.0, 65.0)
const RIGHT_OUTER_BOT_ARM := Rect2(250.0, 260.0, 130.0, 65.0)

## ==================== 区域判定（边界闭区间，与 field_zone._is_in_* 一致；Rect2.has_point 右/下开区间不可用） ====================

static func _in_rect(pos: Vector2, r: Rect2) -> bool:
	return pos.x >= r.position.x and pos.x <= r.end.x \
		and pos.y >= r.position.y and pos.y <= r.end.y

static func is_in_inner(pos: Vector2) -> bool:
	return pos.x >= INNER_X_MIN and pos.x <= INNER_X_MAX \
		and pos.y >= INNER_Y_MIN and pos.y <= INNER_Y_MAX

static func is_in_left_outer(pos: Vector2) -> bool:
	return _in_rect(pos, LEFT_OUTER_MAIN) \
		or _in_rect(pos, LEFT_OUTER_TOP_ARM) \
		or _in_rect(pos, LEFT_OUTER_BOT_ARM)

static func is_in_right_outer(pos: Vector2) -> bool:
	return _in_rect(pos, RIGHT_OUTER_MAIN) \
		or _in_rect(pos, RIGHT_OUTER_TOP_ARM) \
		or _in_rect(pos, RIGHT_OUTER_BOT_ARM)

## 蓝色禁区 = 既不在内场也不在任一外场
static func is_in_blue_boundary(pos: Vector2) -> bool:
	return not is_in_inner(pos) and not is_in_left_outer(pos) and not is_in_right_outer(pos)

## ==================== 违规判定（镜像 check_zone_violation 三查顺序） ====================

## 返回 0=无违规 1=蓝色禁区 2=越中线 3=越内外场边界
static func check_violation(team: String, pos: Vector2, is_penalized: bool) -> int:
	# ① 蓝色禁区优先
	if is_in_blue_boundary(pos):
		return 1
	# ② 越内外场边界（被惩罚球员可在外场，不检查）
	if not is_penalized:
		if team == "a" and pos.x < INNER_X_MIN:
			return 3
		if team == "b" and pos.x > INNER_X_MAX:
			return 3
	# ③ 越中线（仅内场内检查）
	if is_in_inner(pos):
		if team == "a" and pos.x > MIDLINE_X:
			return 2
		elif team == "b" and pos.x < MIDLINE_X:
			return 2
	return 0
