extends Node3D
class_name ObstacleVisual3D
## 07工单：障碍物 3D 镜像代理（3D 模式下 2D 色块被全屏贴图遮蔽的修复，同盾 shield_visual_3d 先例）
## 只读消费宿主障碍公开数据（shape_type/element_color/_cached_*/obstacle_hp），零判定逻辑
## 位置由 bridge 每帧同步 2D 障碍体（单位制铁律：(x, y) → (x, 高度, y) 1:1 零换算）
## 形状语义按原作技能表（填写版）：rect=长墙盒 / circle=圆柱图腾 / crescent=弧形分段墙

var _host: Node = null
var _mat: StandardMaterial3D = null
var _hp_label: Label3D = null
var _element_color: Color = Color(1.0, 1.0, 0.5)
var _max_hp: float = 1.0


func setup(host: Node) -> void:
	_host = host
	var shape: String = str(host.get("shape_type") if host.get("shape_type") != null else "rect")
	_element_color = host.get("element_color") if host.get("element_color") != null else _element_color
	_max_hp = maxf(float(host.get("max_obstacle_hp") if host.get("max_obstacle_hp") != null else 1.0), 1.0)
	var width: float = float(host.get("_cached_width") if host.get("_cached_width") != null else 80.0)
	var height: float = float(host.get("_cached_height") if host.get("_cached_height") != null else 30.0)
	var radius: float = float(host.get("_cached_radius") if host.get("_cached_radius") != null else 40.0)

	match shape:
		"circle":
			# 圆柱图腾（黄土墙盾/零度冰柱）：代理原点=地面点，柱心抬半高
			var cyl := MeshInstance3D.new()
			cyl.name = "ObstacleBody"
			var c := CylinderMesh.new()
			c.top_radius = radius
			c.bottom_radius = radius
			c.height = 50.0
			cyl.mesh = c
			cyl.position.y = 25.0
			_mat = StandardMaterial3D.new()
			_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_mat.albedo_color = _element_color
			cyl.material_override = _mat
			add_child(cyl)
		"crescent":
			# 弧形分段墙（钻石壁垒/蔷薇花园）：沿 120° 弧排布小盒
			var seg_count := 7
			var arc_len: float = radius * 2.0944  # 120° = 2.0944 rad
			var seg_len: float = arc_len / float(seg_count) * 1.05  # 微量搭接防缝隙
			for i in range(seg_count):
				var theta: float = -1.0472 + (2.0944 * float(i) / float(seg_count - 1))
				var seg := MeshInstance3D.new()
				seg.name = "ArcSeg%d" % i
				var b := BoxMesh.new()
				b.size = Vector3(seg_len, 40.0, 10.0)
				seg.mesh = b
				seg.position = Vector3(cos(theta) * radius, 20.0, sin(theta) * radius)
				seg.rotation.y = -(theta + 1.5708)  # 盒长轴贴弧切线
				if _mat == null:
					_mat = StandardMaterial3D.new()
					_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					_mat.albedo_color = _element_color
				seg.material_override = _mat
				add_child(seg)
		_:
			# rect 长墙盒（石墙/金刚壁垒/零度冰墙/荆棘网络/风墙），2D 落地尺寸 h 作墙厚
			var box := MeshInstance3D.new()
			box.name = "ObstacleBody"
			var bm := BoxMesh.new()
			bm.size = Vector3(width, 40.0, maxf(height, 8.0))
			box.mesh = bm
			box.position.y = 20.0
			_mat = StandardMaterial3D.new()
			_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_mat.albedo_color = _element_color
			box.material_override = _mat
			add_child(box)

	# 头顶 HP 数字牌：看到消耗（球磨墙数字实时下降）
	_hp_label = Label3D.new()
	_hp_label.name = "HpLabel"
	_hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_label.no_depth_test = true
	_hp_label.pixel_size = 0.35
	_hp_label.font_size = 40
	_hp_label.outline_size = 10
	_hp_label.position = Vector3(0.0, 58.0, 0.0)
	add_child(_hp_label)
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	if _mat == null or _hp_label == null:
		return
	var hp = _host.get("obstacle_hp") if _host != null and is_instance_valid(_host) else null
	var cur: float = float(hp) if hp != null else 0.0
	var ratio := clampf(cur / _max_hp, 0.0, 1.0)
	_hp_label.text = "%d/%d" % [int(round(cur)), int(round(_max_hp))]
	# 耐久梯度：元素原色→橙→红（同盾先例分档）
	if ratio > 0.6:
		_mat.albedo_color = _element_color
	elif ratio > 0.3:
		_mat.albedo_color = Color(1.0, 0.6, 0.1)
	else:
		_mat.albedo_color = Color(0.9, 0.2, 0.15)


## bridge 每帧调用：贴 2D 障碍体位姿（单位制铁律 (x, 0, y)；代理原点=地面点，网格自带高度）
## D12：rotation.y 取负（2D 角→3D 同向），否则旋转放置墙/月牙朝向镜像
func sync_from_2d(pos: Vector2, rot_y: float) -> void:
	global_position = Vector3(pos.x, 0.0, pos.y)
	rotation.y = -rot_y
