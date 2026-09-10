## Phase 4 类一验证：2.5D 特效贴合 3D —— 18 项矩阵（3 target_type × 6 元素）
## 每项：构建对应 3D 轮廓（球膜环/脚下环/朝向条带）→ 材质色断言（元素色+α0.55）→ 截图存档
## 运行：带窗口加载本场景自动跑完退出（PASS=exit 0）；截图在 docs/img/3d_p4/
extends Node3D

const CFG = preload("res://scripts/battle3d/battle3d_const.gd")

const ELEMENTS: Array[String] = ["金刚", "大地", "雷火", "冰雪", "草木", "梦幻"]
const ELEMENT_COLORS: Dictionary = {
	"金刚": Color("#FFD700"), "大地": Color("#8B4513"), "雷火": Color("#FF4500"),
	"冰雪": Color("#87CEEB"), "草木": Color("#32CD32"), "梦幻": Color("#DA70D6"),
}
const TARGET_TYPES: Array[String] = ["ball", "player", "field"]
const SHOT_DIR := "res://docs/img/3d_p4"

var _proxy: PlayerProxy3D = null
var _ball: BallProxy3DV2 = null
var _cam: Camera3DController = null
var _current: SkillOutline3D = null
var _pass := 0
var _fail := 0

func _ready() -> void:
	print("[P4] === 18 项特效矩阵验证开始 ===")
	_build_scene()
	_run_matrix()

func _build_scene() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 90.0, 0.0)
	add_child(sun)
	# 地面参照（一块草地色平面）
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1300.0, 780.0)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.12, 0.38, 0.12)
	ground.material_override = gmat
	add_child(ground)
	# 球员代理 + 球代理
	_proxy = PlayerProxy3D.new()
	add_child(_proxy)
	_proxy.setup("char_001", Color(0.2, 0.45, 0.95, 0.8))
	_proxy.sync_from_2d(Vector2(0, 0), Vector2.ZERO, Vector2(1, 0))
	_ball = BallProxy3DV2.new()
	add_child(_ball)
	_ball.setup()
	_ball.set_flight(Vector2(160.0, 0.0))
	# 相机（UNITY 观感位看向场心附近）
	_cam = Camera3DController.new()
	add_child(_cam)
	_cam.setup(Camera3DController.Mode.UNITY)
	_cam.global_position = Vector3(-350.0, 320.0, 420.0)
	_cam.look_at(Vector3(0.0, 30.0, 0.0), Vector3.UP)

func _run_matrix() -> void:
	DirAccess.open("res://docs").make_dir_recursive("img/3d_p4")
	var idx := 0
	for tt in TARGET_TYPES:
		for elem in ELEMENTS:
			idx += 1
			await _check_one(idx, tt, elem)
	print("[P4] === 结果: %d/18 通过 ===" % _pass)
	print("[P4] RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	get_tree().quit(0 if _fail == 0 else 1)

func _check_one(idx: int, tt: String, elem: String) -> void:
	if _current != null and is_instance_valid(_current):
		_current.queue_free()
	var expect: Color = ELEMENT_COLORS[elem]
	match tt:
		"ball":
			_current = SkillOutline3D.make_ring(20.0 + 6.0, expect, 0.0)
			_ball.add_child(_current)
		"player":
			_current = SkillOutline3D.make_ring(28.0 + 5.0, expect, 3.0)
			_proxy.add_child(_current)
		"field":
			_current = SkillOutline3D.make_strip(40.0, expect)
			_proxy.add_child(_current)
	await get_tree().process_frame
	await get_tree().process_frame
	# 断言材质色
	var mesh_node := _current.get_child(0) as MeshInstance3D
	var mat := mesh_node.material_override as StandardMaterial3D
	var ok_color := mat != null \
		and absf(mat.albedo_color.r - expect.r) < 0.01 \
		and absf(mat.albedo_color.g - expect.g) < 0.01 \
		and absf(mat.albedo_color.b - expect.b) < 0.01 \
		and absf(mat.albedo_color.a - 0.55) < 0.01
	# 断言挂载位置正确
	var ok_parent := (tt == "ball" and _current.get_parent() == _ball) \
		or (tt != "ball" and _current.get_parent() == _proxy)
	var ok := ok_color and ok_parent
	if ok:
		_pass += 1
	else:
		_fail += 1
	# 截图存档
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/p4_%02d_%s_%s.png" % [SHOT_DIR, idx, tt, elem])
	print("[P4][%s] #%02d %s/%s color=%s parent=%s" % [
		"PASS" if ok else "FAIL", idx, tt, elem,
		str(mat.albedo_color) if mat != null else "null", "OK" if ok_parent else "WRONG"])
