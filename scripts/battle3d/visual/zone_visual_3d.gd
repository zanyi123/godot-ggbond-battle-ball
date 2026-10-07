extends Node3D
class_name ZoneVisual3D
## 07工单·zone段（操控UI-0929-1 已批）：场地效果区 3D 镜像代理（3D 模式下 2D zone 色块被全屏贴图遮蔽）
## 同障碍/盾先例只读消费——颜色与文字直接读宿主 2D 视觉节点现状（_fill_rect 颜色含最后3秒闪烁后的
## alpha、_border_line 描边色、两个 Label 文字），零复制常量零复制公式（第二真相禁令）
## 位置由 bridge 每帧同步 2D zone（单位制铁律：(x, y) → (x, 高度, y) 1:1 零换算）

var _host: Node = null
var _fill_mat: StandardMaterial3D = null
var _type_label: Label3D = null
var _timer_label: Label3D = null
var _zone_w: float = 120.0
var _zone_h: float = 120.0


func setup(host: Node) -> void:
	_host = host
	var size = host.get("zone_size") if host.get("zone_size") != null else Vector2(120.0, 120.0)
	_zone_w = maxf(float(size.x), 8.0)
	_zone_h = maxf(float(size.y), 8.0)

	# 贴地薄盒（半透明填充，颜色/alpha 每帧镜像 2D fill 现状）
	var slab := MeshInstance3D.new()
	slab.name = "ZoneSlab"
	var bm := BoxMesh.new()
	bm.size = Vector3(_zone_w, 2.0, _zone_h)
	slab.mesh = bm
	slab.position.y = 1.0
	_fill_mat = StandardMaterial3D.new()
	_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fill_mat.albedo_color = Color(0.2, 0.8, 0.2, 0.25)
	slab.material_override = _fill_mat
	add_child(slab)

	# 四边框（亮色细盒，同 2D Line2D 描边语义）
	var border := Color(0.3, 1.0, 0.3, 0.85)
	_add_border_box(Vector3(_zone_w + 2.0, 4.0, 1.0), Vector3(0.0, 2.0, _zone_h / 2.0), border)
	_add_border_box(Vector3(_zone_w + 2.0, 4.0, 1.0), Vector3(0.0, 2.0, -_zone_h / 2.0), border)
	_add_border_box(Vector3(1.0, 4.0, _zone_h + 2.0), Vector3(_zone_w / 2.0, 2.0, 0.0), border)
	_add_border_box(Vector3(1.0, 4.0, _zone_h + 2.0), Vector3(-_zone_w / 2.0, 2.0, 0.0), border)

	# 类型名 + 倒计时牌（文字每帧镜像 2D Label 现状）
	_type_label = _make_label(Vector3(0.0, 22.0, 0.0))
	_timer_label = _make_label(Vector3(0.0, 10.0, 0.0), Color.WHITE)
	_refresh()


func _add_border_box(box_size: Vector3, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box_size
	mi.mesh = bm
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mi.material_override = mat
	add_child(mi)


func _make_label(pos: Vector3, color: Color = Color.WHITE) -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.3
	label.font_size = 32
	label.outline_size = 8
	label.position = pos
	label.modulate = color
	add_child(label)
	return label


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	if _fill_mat == null or _host == null or not is_instance_valid(_host):
		return
	# 只读消费 2D 视觉现状（fill 颜色含闪烁 alpha；border 色；名称/倒计时文字）
	var fill = _host.get("_fill_rect") if _host.get("_fill_rect") != null else null
	if fill != null and is_instance_valid(fill):
		_fill_mat.albedo_color = fill.color
	var line = _host.get("_border_line") if _host.get("_border_line") != null else null
	if line != null and is_instance_valid(line) and _type_label != null:
		_type_label.modulate = line.default_color
	var t_label = _host.get("_timer_label") if _host.get("_timer_label") != null else null
	if t_label != null and is_instance_valid(t_label) and _timer_label != null:
		_timer_label.text = t_label.text
	var type_label = _host.get("_type_label") if _host.get("_type_label") != null else null
	if type_label != null and is_instance_valid(type_label) and _type_label != null:
		_type_label.text = type_label.text


## bridge 每帧调用：贴 2D zone 位姿（单位制铁律 (x, 0, y)）
## D12：2D 角→3D rotation.y 须取负（(x,y)→(x,0,y) 映射下同向），否则斜条带方向左右镜像
func sync_from_2d(pos: Vector2, rot_y: float) -> void:
	global_position = Vector3(pos.x, 0.0, pos.y)
	rotation.y = -rot_y
