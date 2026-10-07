extends Node3D
class_name EnemyMarker3D
## 23号工单：敌方作用对象头顶状态标记·3D 主轨（09-24 世界空间裁定：3D 主/2D 兜底双轨）
## 简约功能性显示：单 Label3D 文字串（如「印2 晕3」），红色=敌我区分；粒子化/美术归 M2
## 数据源=宿主球员只读信号（status_lights_changed/mark_changed），事件驱动零轮询；UI 零判定
## 白名单单一事实源=EnemyStatusMarker.ENEMY_KEYS / EXTRA_ICONS（2D 组件，只读引用）

var _host: Node = null
var _label: Label3D = null
var _mark_counts: Dictionary = {}   # mark_id → count（mark_changed 信号维护快照）


func setup(host: Node) -> void:
	_host = host
	_label = Label3D.new()
	_label.name = "EnemyMarkerLabel"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.3
	_label.font_size = 30
	_label.outline_size = 8
	_label.position = Vector3(0.0, 80.0, 0.0)  # 名字标签(y=62)上方
	_label.modulate = Color(1.0, 0.45, 0.4)    # 红色系=敌我区分
	add_child(_label)

	if _host.has_signal("status_lights_changed") and not _host.status_lights_changed.is_connected(_rebuild):
		_host.status_lights_changed.connect(_rebuild)
	if _host.has_signal("mark_changed") and not _host.mark_changed.is_connected(_on_mark_changed):
		_host.mark_changed.connect(_on_mark_changed)
	visible = false
	_rebuild()


func _on_mark_changed(mark_id: String, count: int) -> void:
	if count <= 0:
		_mark_counts.erase(mark_id)
	else:
		_mark_counts[mark_id] = count
	_rebuild()


func _rebuild() -> void:
	if _label == null or _host == null or not is_instance_valid(_host):
		return
	var MarkerScript: GDScript = load("res://scripts/battle/enemy_status_marker.gd")
	var keys: Array = MarkerScript.ENEMY_KEYS
	var extra: Dictionary = MarkerScript.EXTRA_ICONS
	var icons: Dictionary = MarkerScript.STATUS_ICONS
	var parts: PackedStringArray = []
	var view: Dictionary = _host.get_status_lights_view()
	# 灯类减益（键序=白名单序，输出稳定）
	for key in keys:
		if not view.has(key):
			continue
		var secs := int(ceil(float(view[key].get("remaining", 0.0))))
		var icon: Dictionary = extra.get(key, icons.get(key, {"char": key.substr(0, 1)}))
		parts.append("%s%d" % [str(icon["char"]), secs])
	# 印记层数
	for mark_id in _mark_counts:
		var icon: Dictionary = icons.get("mark", {"char": "印"})
		parts.append("%s%d" % [str(icon["char"]), int(_mark_counts[mark_id])])
	var text := " ".join(parts)
	_label.text = text
	var has := text != ""
	if visible != has:
		visible = has
