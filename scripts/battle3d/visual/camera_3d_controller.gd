## 3D 相机控制器（battle3d 模块 · Phase 1）
## 四模式：UNITY（Unity TestBattle 观感，×50 像素制）/ TOP / ANGLED / FOLLOW
## TOP/ANGLED 常量直接搬 player_3d_test 大相机（铁律定死值，零换算）
class_name Camera3DController
extends Camera3D

const CFG = preload("res://scripts/battle3d/battle3d_const.gd")

enum Mode { UNITY, TOP, ANGLED, FOLLOW }

const MODE_NAMES: Array[String] = ["UNITY", "TOP", "ANGLED", "FOLLOW"]

var mode: Mode = Mode.UNITY
var follow_target: Node3D = null
## FOLLOW 模式相机相对目标的偏移
var follow_offset := Vector3(300.0, 150.0, 200.0)

func setup(initial_mode: Mode = Mode.UNITY) -> void:
	fov = CFG.CAM_FOV
	near = 1.0
	far = 20000.0
	current = true
	set_mode(initial_mode)

func set_mode(m: Mode) -> void:
	mode = m
	match m:
		Mode.UNITY:
			projection = Camera3D.PROJECTION_PERSPECTIVE
			global_position = CFG.CAM_UNITY_POS
			# Unity 相机在 -Z 侧朝 +Z 俯视场心；Godot 相机默认朝 -Z，
			# 直接套 (-58,0,0) 会背对球场，用 look_at 场心（俯角=atan(800/500)≈58°）
			look_at(Vector3.ZERO, Vector3(0.0, 1.0, 0.0))
		Mode.TOP:
			projection = Camera3D.PROJECTION_ORTHOGONAL
			size = CFG.CAM_TOP_ORTHO_SIZE
			global_position = Vector3(0.0, CFG.CAM_TOP_Y, 0.0)
			rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		Mode.ANGLED:
			projection = Camera3D.PROJECTION_PERSPECTIVE
			fov = CFG.CAM_FOV
			var d := CFG.CAM_ANGLED_DIST
			var v := sqrt(0.5) * d
			global_position = Vector3(0.0, v, v)
			rotation_degrees = Vector3(-45.0, 0.0, 0.0)
		Mode.FOLLOW:
			projection = Camera3D.PROJECTION_PERSPECTIVE
			fov = CFG.CAM_FOV
			_update_follow()

func next_mode() -> Mode:
	var next_idx: int = (int(mode) + 1) % 4
	var next := next_idx as Mode
	set_mode(next)
	return next

func get_mode_name() -> String:
	return MODE_NAMES[mode]

func _process(_delta: float) -> void:
	if mode == Mode.FOLLOW:
		_update_follow()

func _update_follow() -> void:
	if follow_target != null and is_instance_valid(follow_target):
		global_position = follow_target.global_position + follow_offset
		# 俯视目标，up 不能与视线平行（踩坑记录）
		look_at(follow_target.global_position, Vector3(0.0, 1.0, 0.0))
