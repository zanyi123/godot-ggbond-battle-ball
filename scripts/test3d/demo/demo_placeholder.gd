extends Node3D
## 工单37 演示占位模型（六件套）——操控标签演示平台专用
## 映射表写死（37号§一）：圆球=OP_AIM/STEER/MIDFLY/FP/SUMMON/KEY_JUMP；
##   立体方块=OP_TOGGLE/AUTO生效提示/PLACE放置后实体；五角星=OP_MARK；
##   扁平贴地色块=OP_PLACE预览/OP_POINT落点指示；连线=横切拖长击；组合体=OP_COMBO。
## 四动作接口：appear / move_to / attach_to / vanish（另含 pulse 闪烁、set_line 刷新）。
## 红线：纯演示件，零比赛机制、零逻辑判定。

enum Kind { SPHERE, CUBE, STAR, PAD, LINE, COMBO }

const DEFAULT_COLOR := Color(0.35, 0.75, 1.0)
const HIGHLIGHT_COLOR := Color(1.0, 0.85, 0.3)
const FLOAT_Y := 26.0        # 立体占位默认浮空高（≈ball 飞行高 30 口径）

var kind: int = Kind.SPHERE
var params: Dictionary = {}
var mat: StandardMaterial3D
var _mesh_node: MeshInstance3D
var _extra_meshes: Array[MeshInstance3D] = []
var _attach_target: Node3D = null
var _attach_offset := Vector3.ZERO
var _pulse_left := -1.0      # >0 = 闪烁中（剩余秒）
var _pulse_dur := 1.0
var _vanish_left := -1.0     # >0 = 缩小消失动画中
var _base_scale := Vector3.ONE
var _spin := false           # 五角星贴附后慢速自转


## 建型入口：kind + 参数（size/radius/color/shape/w/h/point）
func setup(p_kind: int, p_params: Dictionary = {}) -> void:
	kind = p_kind
	params = p_params
	var color: Color = p_params.get("color", DEFAULT_COLOR)
	mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color * 0.35
	mat.roughness = 0.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var translucent: bool = p_params.get("translucent", false)
	if translucent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.45
	match kind:
		Kind.SPHERE:
			_build_sphere()
		Kind.CUBE:
			_build_cube()
		Kind.STAR:
			_build_star()
		Kind.PAD:
			_build_pad()
		Kind.LINE:
			_build_line()
		Kind.COMBO:
			_build_combo()
	_base_scale = scale


func _build_sphere() -> void:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = params.get("radius", 14.0)
	mesh.height = mesh.radius * 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(0, FLOAT_Y, 0)
	add_child(mi)
	_mesh_node = mi


func _build_cube() -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var s: float = params.get("size", 36.0)
	mesh.size = Vector3(s, s, s)
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(0, FLOAT_Y + s * 0.5, 0)
	add_child(mi)
	_mesh_node = mi


func _build_star() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _build_star_mesh(params.get("radius", 20.0), params.get("height", 10.0))
	mi.material_override = mat
	mi.position = Vector3(0, FLOAT_Y + 20.0, 0)
	add_child(mi)
	_mesh_node = mi
	_spin = true


func _build_pad() -> void:
	# 扁平贴地色块：rect（中心锚定/anchor_edge 宽边锚定）/circle/sector 扇形/ring 环形，半透明
	# 锚点语义（37号 19 号标签主人规格）：矩形 anchor_edge=球员站宽边中点，几何向局部 -Z 延申；sector/ring=球员在圆心
	var mi := MeshInstance3D.new()
	var shape := str(params.get("shape", "rect"))
	if shape == "circle":
		var cyl := CylinderMesh.new()
		cyl.top_radius = params.get("radius", 60.0)
		cyl.bottom_radius = cyl.top_radius
		cyl.height = 1.0
		mi.mesh = cyl
	elif shape == "sector":
		mi.mesh = _build_sector_mesh(params.get("radius", 300.0), params.get("angle_deg", 90.0))
	elif shape == "ring":
		mi.mesh = _build_ring_mesh(params.get("inner_r", 80.0), params.get("outer_r", 300.0))
	elif params.get("anchor_edge", false):
		mi.mesh = _build_rect_edge_mesh(params.get("w", 600.0), params.get("h", 80.0))
	else:
		var plane := PlaneMesh.new()
		plane.size = Vector2(params.get("w", 160.0), params.get("h", 100.0))
		mi.mesh = plane
	mi.material_override = mat
	mi.position = Vector3(0, 0.8, 0)
	add_child(mi)
	_mesh_node = mi


## 贴地矩形（宽边锚定）：局部原点=宽边中点，矩形向 -Z 延申 w、横向宽 h
func _build_rect_edge_mesh(w: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3(h * 0.5, 0, 0), Vector3(-h * 0.5, 0, 0), Vector3(-h * 0.5, 0, -w), Vector3(h * 0.5, 0, -w)]
	for tri in [[0, 1, 2], [0, 2, 3]]:
		for idx in tri:
			st.set_normal(Vector3.UP)
			st.add_vertex(pts[idx])
	return st.commit()


## 贴地扇形：圆心=局部原点，朝 -Z 张开 angle_deg、半径 radius
func _build_sector_mesh(radius: float, angle_deg: float, segments: int = 24) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := deg_to_rad(angle_deg) * 0.5
	for i in range(segments):
		var a0 := -half + deg_to_rad(angle_deg) * float(i) / float(segments)
		var a1 := -half + deg_to_rad(angle_deg) * float(i + 1) / float(segments)
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(0, 0, 0))
		st.add_vertex(Vector3(sin(a0) * radius, 0, -cos(a0) * radius))
		st.add_vertex(Vector3(sin(a1) * radius, 0, -cos(a1) * radius))
	return st.commit()


## 贴地环形：圆心=局部原点，内半径 inner_r～外半径 outer_r
func _build_ring_mesh(inner_r: float, outer_r: float, segments: int = 36) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var o0 := Vector3(sin(a0) * outer_r, 0, -cos(a0) * outer_r)
		var o1 := Vector3(sin(a1) * outer_r, 0, -cos(a1) * outer_r)
		var i0 := Vector3(sin(a0) * inner_r, 0, -cos(a0) * inner_r)
		var i1 := Vector3(sin(a1) * inner_r, 0, -cos(a1) * inner_r)
		for vtx in [o0, i0, o1, i0, i1, o1]:
			st.set_normal(Vector3.UP)
			st.add_vertex(vtx)
	return st.commit()


func _build_line() -> void:
	# 连线：细长方体桥接 a-b（set_line 刷新）
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(3, 3, 10)
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	_mesh_node = mi


func _build_combo() -> void:
	# 组合体：增强占位=大号金色圆球+外环
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = params.get("radius", 22.0)
	mesh.height = mesh.radius * 2.0
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(0, FLOAT_Y, 0)
	add_child(mi)
	_mesh_node = mi
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = mesh.radius + 6.0
	ring_mesh.outer_radius = mesh.radius + 9.0
	ring.mesh = ring_mesh
	ring.material_override = mat
	ring.position = Vector3(0, FLOAT_Y, 0)
	add_child(ring)
	_extra_meshes.append(ring)


## 五角星棱柱（SurfaceTool 手工建：10 点星形挤出）
func _build_star_mesh(outer: float, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector2] = []
	for i in range(10):
		var ang := -PI / 2.0 + TAU * float(i) / 10.0
		var r := outer if i % 2 == 0 else outer * 0.45
		pts.append(Vector2(cos(ang), sin(ang)) * r)
	for i in range(10):
		var j := (i + 1) % 10
		var a := pts[i]
		var b := pts[j]
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(0, height, 0))
		st.add_vertex(Vector3(b.x, height, b.y))
		st.add_vertex(Vector3(a.x, height, a.y))
		st.set_normal(Vector3.DOWN)
		st.add_vertex(Vector3(0, 0, 0))
		st.add_vertex(Vector3(a.x, 0, a.y))
		st.add_vertex(Vector3(b.x, 0, b.y))
		var n := Vector3(a.x + b.x, 0.0, a.y + b.y).normalized()
		st.set_normal(n)
		st.add_vertex(Vector3(a.x, 0, a.y))
		st.add_vertex(Vector3(a.x, height, a.y))
		st.add_vertex(Vector3(b.x, height, b.y))
		st.add_vertex(Vector3(a.x, 0, a.y))
		st.add_vertex(Vector3(b.x, height, b.y))
		st.add_vertex(Vector3(b.x, 0, b.y))
	return st.commit()


## ===== 38号批4 消费端：真模型替换（ctl_visual_model_path/scale/rot/offset——25号闸门：模型到位自动替换） =====
func apply_model(path: String, p_scale: float, rot_deg: float, offset: Vector3) -> bool:
	var sc: PackedScene = load(path)
	if sc == null:
		return false
	var inst = sc.instantiate()
	if not (inst is Node3D):
		return false
	if _mesh_node != null:
		_mesh_node.visible = false
	for e in _extra_meshes:
		e.visible = false
	var n3d := inst as Node3D
	n3d.position = offset
	n3d.rotation_degrees = Vector3(0, rot_deg, 0)
	n3d.scale = Vector3.ONE * p_scale
	add_child(n3d)
	return true


## ===== 38号批4 消费端：出现方式（ctl_time_enter_fx：instant/fade/scale_in） =====
func set_enter_fx(mode: String) -> void:
	match mode:
		"scale_in":
			appear()
		"fade":
			if mat != null:
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				var target: float = mat.albedo_color.a
				mat.albedo_color.a = 0.0
				var tw := create_tween()
				tw.tween_property(mat, "albedo_color:a", target, 0.35)



## ===== 38号批4 消费端：出现方式（ctl_time_enter_fx：instant/fade/scale_in） =====


## 动作①：出现（从 0.3 倍弹到 1 倍）
func appear() -> void:
	scale = _base_scale * 0.3
	var tw := create_tween()
	tw.tween_property(self, "scale", _base_scale, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 动作②：移动（补间飞行）
func move_to(target: Vector3, dur: float = 0.8) -> void:
	var tw := create_tween()
	tw.tween_property(self, "position", target, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## 动作③：贴附（每帧跟随目标节点；五角星贴球员头顶用）
func attach_to(target: Node3D, offset: Vector3 = Vector3.ZERO) -> void:
	_attach_target = target
	_attach_offset = offset
	global_position = target.global_position + offset


## 动作④：消失（0.25s 缩小后释放）
func vanish(animated: bool = true) -> void:
	if _vanish_left >= 0.0:
		return
	if not animated:
		queue_free()
		return
	_vanish_left = 0.25
	_attach_target = null


## 闪烁（OP_AUTO 原地闪烁 1s / 完成高亮用）
func pulse(duration: float = 1.0) -> void:
	_pulse_left = duration
	_pulse_dur = duration


## 连线刷新（拖长击 a-b 作用线 / 拖动跟随）
func set_line(a: Vector3, b: Vector3) -> void:
	if a.distance_to(b) < 1.0:
		visible = false
		return
	visible = true
	var mi := _mesh_node
	(mi.mesh as BoxMesh).size = Vector3(3, 3, a.distance_to(b))
	global_position = (a + b) * 0.5
	if not global_position.is_equal_approx(b):
		look_at(b, Vector3.UP)


## 吸附高亮（拖长击端点吸附目标时）
func set_highlight(on: bool) -> void:
	if mat == null:
		return
	var base: Color = params.get("color", DEFAULT_COLOR)
	mat.emission = (HIGHLIGHT_COLOR if on else base) * (0.8 if on else 0.35)


func _process(delta: float) -> void:
	if _attach_target != null and is_instance_valid(_attach_target):
		global_position = _attach_target.global_position + _attach_offset
	if _pulse_left > 0.0:
		_pulse_left -= delta
		var k := 0.5 + 0.5 * absf(sin(_pulse_left * TAU * 2.0))
		if mat != null:
			mat.emission_energy_multiplier = 0.4 + 2.6 * k
		scale = _base_scale * (1.0 + 0.12 * k)
		if _pulse_left <= 0.0:
			mat.emission_energy_multiplier = 1.0
			scale = _base_scale
	if _spin and _mesh_node != null:
		_mesh_node.rotate_y(1.6 * delta)
	if _vanish_left > 0.0:
		_vanish_left -= delta
		var k2: float = maxf(_vanish_left / 0.25, 0.01)
		scale = _base_scale * k2
		if _vanish_left <= 0.0:
			queue_free()
