## 3D 技能特效适配器（battle3d/visual · Phase 4 类一）
## 与 2D skill_visual_manager 同源信号双订阅（不干扰 2D 分发）：
##   player.skill_used / spirit_system effect_finished / ball_caught / ball_hit_player
## 按 tags_registry 的 target_type 分发三类 3D 视觉：
##   ball→球膜环  player→脚下环  field→朝向条带；元素色取 skill_data.element
## 由 bridge 创建并喂引用（player_2d→proxy 映射、ball 代理、tags 缓存）。
class_name SkillFx3DAdapter
extends Node

const CFG = preload("res://scripts/battle3d/battle3d_const.gd")

## 六元素色板（镜像 player.gd::_ELEMENT_COLORS）
const ELEMENT_COLORS: Dictionary = {
	"金刚": Color("#FFD700"),
	"大地": Color("#8B4513"),
	"雷火": Color("#FF4500"),
	"冰雪": Color("#87CEEB"),
	"草木": Color("#32CD32"),
	"梦幻": Color("#DA70D6"),
}
const DEFAULT_COLOR := Color(1.0, 1.0, 0.5)

var _player_proxies: Dictionary = {}   # player_2d -> PlayerProxy3D
var _ball_proxy: BallProxy3DV2 = null
var _ball_2d: Node = null
var _tag_cache: Dictionary = {}        # tag_id -> target_type
var _active_outlines: Dictionary = {}  # caster_player -> Array[SkillOutline3D]

func setup(player_proxies: Dictionary, ball_proxy: BallProxy3DV2, ball_2d: Node, spirit_system: Node) -> void:
	_player_proxies = player_proxies
	_ball_proxy = ball_proxy
	_ball_2d = ball_2d
	_load_tag_types()
	_connect_signals(spirit_system)
	print("[Fx3D] ✅ 特效适配器就绪 (tags=%d)" % _tag_cache.size())

func _load_tag_types() -> void:
	var path := "res://data/spirits/tags_registry.json"
	if not FileAccess.file_exists(path):
		push_warning("[Fx3D] tags_registry 缺失: %s" % path)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null:
		push_error("[Fx3D] tags_registry 解析失败")
		return
	# 实际结构：{"tags": [{id, target_type, ...}, ...]}
	if parsed is Dictionary and parsed.has("tags") and parsed["tags"] is Array:
		for td in parsed["tags"]:
			if td is Dictionary and td.has("id"):
				_tag_cache[str(td["id"])] = str(td.get("target_type", ""))
	elif parsed is Dictionary:
		for tag_id in parsed:
			var td = parsed[tag_id]
			if td is Dictionary:
				_tag_cache[str(tag_id)] = str(td.get("target_type", ""))
	elif parsed is Array:
		for td in parsed:
			if td is Dictionary and td.has("id"):
				_tag_cache[str(td["id"])] = str(td.get("target_type", ""))

func _connect_signals(spirit_system: Node) -> void:
	# 全路径必经点：spirit_system.skill_trigger.skill_triggered（玩家按键与 AI 释放都经过）
	# 注：player.skill_used 只有玩家路径会发，AI 直调 spirit_system.use_skill 绕过它
	var trigger = spirit_system.get("skill_trigger")
	if trigger != null and trigger.has_signal("skill_triggered"):
		trigger.skill_triggered.connect(_on_any_skill_triggered)
	if _ball_2d != null and is_instance_valid(_ball_2d):
		if _ball_2d.has_signal("ball_caught"):
			_ball_2d.ball_caught.connect(_on_ball_caught)
		if _ball_2d.has_signal("ball_hit_player"):
			_ball_2d.ball_hit_player.connect(_on_ball_hit)

## ==================== 分发（镜像 skill_visual_manager.on_skill_triggered 语义） ====================

func _on_any_skill_triggered(skill_id: String, caster_id: int, _target_data: Dictionary) -> void:
	# caster_id = 2D player 实例 id
	var player_2d: Node = null
	for p in _player_proxies:
		if p != null and is_instance_valid(p) and p.get_instance_id() == caster_id:
			player_2d = p
			break
	if player_2d == null:
		return
	var skill_data: Dictionary = DataManager.get_skill_by_id(str(skill_id))
	if skill_data.is_empty():
		return
	var element = str(skill_data.get("element", ""))
	var color: Color = ELEMENT_COLORS.get(element, DEFAULT_COLOR)
	var tag_ids: Array = skill_data.get("tags", [])
	# 取该技能第一个可识别 target_type
	var target_type := ""
	for tag_id in tag_ids:
		var tt: String = _tag_cache.get(str(tag_id), "")
		if tt in ["ball", "player", "field"]:
			target_type = tt
			break
	if target_type == "":
		return
	var proxy = _player_proxies[player_2d]
	# 清旧环再挂新（同 caster 单活动轮廓，2D 同语义）
	_clear_caster(player_2d)
	var outline: SkillOutline3D
	match target_type:
		"ball":
			outline = SkillOutline3D.make_ring(20.0 + 6.0, color, 0.0)  # 球膜（挂球代理）
			_ball_proxy.add_child(outline)
		"player":
			outline = SkillOutline3D.make_ring(28.0 + 5.0, color, 3.0)  # 脚下环
			proxy.add_child(outline)
		"field":
			outline = SkillOutline3D.make_strip(40.0, color)  # 朝向条带
			proxy.add_child(outline)
		_:
			return
	if not _active_outlines.has(player_2d):
		_active_outlines[player_2d] = []
	_active_outlines[player_2d].append(outline)
	print("[Fx3D] %s 释放 %s (%s/%s) → %s 轮廓" % [proxy.char_id, skill_id, element, target_type, "球膜" if target_type == "ball" else "场上"])

func _on_ball_caught(player: Node) -> void:
	_clear_ball_outline()
	# 接球脉冲：球代理缩放正弦（Tween 在球代理上）
	if _ball_proxy != null:
		var tw := _ball_proxy.create_tween()
		tw.tween_property(_ball_proxy, "scale", Vector3(1.5, 1.5, 1.5), 0.1).set_trans(Tween.TRANS_SINE)
		tw.tween_property(_ball_proxy, "scale", Vector3.ONE, 0.1).set_trans(Tween.TRANS_SINE)

func _on_ball_hit(_player: Node, _damage: float) -> void:
	_clear_ball_outline()

func _clear_ball_outline() -> void:
	for n in _ball_proxy.get_children():
		if n is SkillOutline3D:
			n.queue_free()

func _clear_caster(player_2d: Node) -> void:
	if not _active_outlines.has(player_2d):
		return
	for outline in _active_outlines[player_2d]:
		if outline != null and is_instance_valid(outline):
			outline.queue_free()
	_active_outlines.erase(player_2d)

func clear_all() -> void:
	for p in _active_outlines:
		_clear_caster(p)
	_clear_ball_outline()
