extends Node
## 技能视觉轮廓管理器
## 监听技能系统的触发/结束信号，按标签 target_type 分发到不同轮廓渲染：
##   - ball  → 球的外膜（半径外缘一圈半透明色环）
##   - player → 球员的外膜（半径外缘一圈半透明色环）
##   - field  → 球员朝向那一面的边缘条带
## 轮廓生命周期：技能激活时显示，效果结束时清除（球类标签特殊处理：球击中人后清除）

# 预加载轮廓绘制节点脚本（不用 class_name 避免类型注册时序问题）
const SkillOutlineScript = preload("res://scripts/systems/spirit_system/skill_outline_node.gd")


# === 引用（由 battle_manager.setup() 注入） ===
var battle_manager: Node = null
var ball_node: Area2D = null
var players: Array = []  # 全部球员（含双方）

# 活跃轮廓堆栈：{ outline_key: ColorRect }
# outline_key 规则：
#   - 球类: "ball"
#   - 球员类: "player:<player_id>"
#   - 场地类: "field:<player_id>"
var _active_outlines: Dictionary = {}

# 标签注册表缓存
var _tags_registry: Dictionary = {}


func _ready() -> void:
	_load_tags_registry()


## 加载标签注册表（target_type 字段从这里读）
func _load_tags_registry() -> void:
	var file := FileAccess.open("res://data/spirits/tags_registry.json", FileAccess.READ)
	if not file:
		printerr("[SkillVisual] 无法加载标签注册表")
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK:
		var data = json.data
		for tag in data.get("tags", []):
			_tags_registry[tag.get("id", "")] = tag
		print("[SkillVisual] 加载 %d 个标签" % _tags_registry.size())
	file.close()


## 注入战斗引用（由 battle_manager 调用）
func setup(battle_mgr: Node, ball: Area2D, all_players: Array) -> void:
	battle_manager = battle_mgr
	ball_node = ball
	players = all_players

	# 连接球击中信号（球类轮廓在击中人后清除）
	if ball_node and not ball_node.ball_hit_player.is_connected(_on_ball_hit_player):
		ball_node.ball_hit_player.connect(_on_ball_hit_player)
	if ball_node and not ball_node.ball_caught.is_connected(_on_ball_caught):
		ball_node.ball_caught.connect(_on_ball_caught)

	print("[SkillVisual] 初始化完成，监听 %d 个球员 registry=%d" % [players.size(), _tags_registry.size()])


## ==================== 外部入口 ====================

## 技能激活时调用：根据技能包含的标签，渲染对应轮廓
## 由 skill_triggered 信号或 battle_manager 直接调用
func on_skill_triggered(skill_id: String, caster: CharacterBody2D, tag_ids: Array) -> void:
	if not is_instance_valid(caster):
		return

	# 2026-06-20 诊断：定位轮廓不显示的断点
	print("[诊断轮廓] on_skill_triggered skill=%s tags=%d registry大小=%d" % [skill_id, tag_ids.size(), _tags_registry.size()])

	# 收集该技能所有标签涉及的目标类型（去重）
	var skill_data := _get_skill_data(skill_id)
	var element: String = skill_data.get("element", "")
	var outline_color := _get_element_color(element)

	# 遍历标签，按 target_type 分发
	for tag_id in tag_ids:
		var tag_data: Dictionary = _tags_registry.get(tag_id, {})
		if tag_data.is_empty():
			print("[诊断轮廓] ✗ tag '%s' 不在注册表（跳过）" % tag_id)
			continue
		var target_type: String = tag_data.get("target_type", "")
		print("[诊断轮廓] tag '%s' target_type='%s' → 渲染" % [tag_id, target_type])
		match target_type:
			"ball":
				_apply_ball_outline(outline_color)
			"player":
				_apply_player_outline(caster, outline_color)
			"field":
				_apply_field_outline(caster, outline_color)
			_:
				print("[诊断轮廓] ✗ 未知 target_type='%s'（不渲染）" % target_type)


## 效果结束时调用：清除指定球员关联的轮廓
func on_effect_finished(caster_id: int) -> void:
	# 清除该施法者关联的球员轮廓和场地轮廓
	var player_key := "player:%d" % caster_id
	var field_key := "field:%d" % caster_id
	_remove_outline(player_key)
	_remove_outline(field_key)


## 清空所有轮廓（比赛结束/重置时调用）
func clear_all() -> void:
	for key in _active_outlines.keys():
		_remove_outline(key)
	print("[SkillVisual] 已清空所有轮廓")


## ==================== 轮廓渲染 ====================

## 球类轮廓：在球节点下加一圈外膜（大于球本体）
func _apply_ball_outline(color: Color) -> void:
	if not is_instance_valid(ball_node):
		return
	# 球类轮廓全局唯一（球只有一个），直接覆盖
	_remove_outline("ball")
	var radius: float = ball_node.get_visual_radius()
	var outline: Node2D = _create_ring_panel(radius, 6.0, color, 0.55)
	outline.name = "BallSkillOutline"
	ball_node.add_child(outline)
	_active_outlines["ball"] = outline
	print("[SkillVisual] 球类轮廓已显示 color=%s" % str(color))


## 球员类轮廓：在球员节点下加一圈外膜
func _apply_player_outline(player: CharacterBody2D, color: Color) -> void:
	if not is_instance_valid(player):
		return
	var key := "player:%d" % player.get_instance_id()
	_remove_outline(key)
	var radius: float = player.get_visual_radius()
	var outline: Node2D = _create_ring_panel(radius, 5.0, color, 0.55)
	outline.name = "PlayerSkillOutline"
	player.add_child(outline)
	_active_outlines[key] = outline
	print("[SkillVisual] 球员轮廓已显示 %s color=%s" % [player.char_data.get("name", "?"), str(color)])


## 场地类轮廓：球员朝向那一面的边缘条带
func _apply_field_outline(player: CharacterBody2D, color: Color) -> void:
	if not is_instance_valid(player):
		return
	var key := "field:%d" % player.get_instance_id()
	_remove_outline(key)

	# 根据朝向决定条带位置（八方向近似为四方向：上/下/左/右）
	var facing: Vector2 = player.facing_direction
	if facing == Vector2.ZERO:
		facing = Vector2.RIGHT if player.team == "a" else Vector2.LEFT
	var radius: float = player.get_visual_radius()
	var strip: Node2D = _create_facing_strip(radius, facing, color, 0.75)
	strip.name = "FieldSkillStrip"
	player.add_child(strip)
	_active_outlines[key] = strip
	print("[SkillVisual] 场地朝向条带已显示 %s 朝向=%s" % [player.char_data.get("name", "?"), str(facing)])


## ==================== 视觉元素构造 ====================

## 创建一个圆环外膜节点（Node2D 自绘，避免 Control 坐标系混乱）
## 半径外缘一圈半透明色 + 实色边框，形成"外膜"视觉
func _create_ring_panel(base_radius: float, ring_width: float, color: Color, alpha: float) -> Node2D:
	var outline: Node2D = SkillOutlineScript.new()
	outline.setup_ring(base_radius, ring_width, color, alpha)
	return outline


## 创建球员朝向那一面的边缘条带（场地标签专用）
func _create_facing_strip(base_radius: float, facing: Vector2, color: Color, alpha: float) -> Node2D:
	var outline: Node2D = SkillOutlineScript.new()
	outline.setup_strip(base_radius, facing, color, alpha)
	return outline


## ==================== 轮廓移除 ====================

func _remove_outline(key: String) -> void:
	if not _active_outlines.has(key):
		return
	var outline = _active_outlines[key]
	if is_instance_valid(outline):
		outline.queue_free()
	_active_outlines.erase(key)


## ==================== 信号回调 ====================

## 球击中人 → 清除球类轮廓
func _on_ball_hit_player(_player: CharacterBody2D, _damage: float) -> void:
	_remove_outline("ball")


## 球被接住 → 清除球类轮廓
func _on_ball_caught(_player: CharacterBody2D) -> void:
	_remove_outline("ball")


## ==================== 数据与颜色 ====================

var _skills_cache: Dictionary = {}
var _skills_loaded: bool = false

func _load_skills_data() -> void:
	if _skills_loaded:
		return
	var file := FileAccess.open("res://data/spirits/skills.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK:
			var skills_array: Array = json.data.get("skills", []) if json.data is Dictionary else []
			for s in skills_array:
				_skills_cache[s.get("id", "")] = s
		file.close()
	_skills_loaded = true

func _get_skill_data(skill_id: String) -> Dictionary:
	_load_skills_data()
	return _skills_cache.get(skill_id, {})


## 元素颜色映射（与 battle_hud/handler 统一）
func _get_element_color(element: String) -> Color:
	var colors: Dictionary = {
		"金刚": Color(0.85, 0.75, 0.3),
		"大地": Color(0.7, 0.55, 0.35),
		"雷火": Color(1.0, 0.4, 0.2),
		"冰雪": Color(0.4, 0.8, 1.0),
		"草木": Color(0.3, 0.8, 0.3),
		"梦幻": Color(0.7, 0.5, 0.9),
	}
	return colors.get(element, Color(0.6, 0.6, 0.6))
