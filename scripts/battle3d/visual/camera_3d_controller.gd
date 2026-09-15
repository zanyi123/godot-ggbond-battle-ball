## 3D 相机控制器（battle3d 模块 · Phase 1）
## 四模式：UNITY（Unity TestBattle 观感，×50 像素制）/ TOP / ANGLED / FOLLOW
## TOP/ANGLED 常量直接搬 player_3d_test 大相机（铁律定死值，零换算）
## P2 新增 FIRST_PERSON：挂操控球员球点、朝向=facing+俯仰，由 2D 层数据驱动（只读）
class_name Camera3DController
extends Camera3D

const CFG = preload("res://scripts/battle3d/battle3d_const.gd")

enum Mode { UNITY, TOP, ANGLED, FOLLOW, FIRST_PERSON }

const MODE_NAMES: Array[String] = ["UNITY", "TOP", "ANGLED", "FOLLOW", "FP"]

var mode: Mode = Mode.UNITY
var follow_target: Node3D = null
## FOLLOW 模式相机相对目标的偏移
var follow_offset := Vector3(300.0, 150.0, 200.0)
## FIRST_PERSON 模式参数（bridge 每帧喂 2D 层数据）
var fp_pos2d: Vector2 = Vector2.ZERO    # 球员水平位置
var fp_height_z: float = 60.0           # 眼高（球点）
var fp_yaw: float = 0.0                 # 水平角（弧度，2D facing 的极角）
var fp_pitch: float = 0.0               # 俯仰角（弧度，抬头为正）
var fp_forward_offset: float = 35.0     # 相机沿视线前移（移出自机模型，防嵌在头内部）

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
			fov = CFG.CAM_FOV
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
		Mode.FIRST_PERSON:
			projection = Camera3D.PROJECTION_PERSPECTIVE
			fov = 60.0
			_update_fp()

func next_mode() -> Mode:
	var next_idx: int = (int(mode) + 1) % 4  # 循环只走前四模式，FP 由专用键进出
	var next := next_idx as Mode
	set_mode(next)
	return next

func get_mode_name() -> String:
	return MODE_NAMES[mode]

func _process(_delta: float) -> void:
	if mode == Mode.FOLLOW:
		_update_follow()
	elif mode == Mode.FIRST_PERSON:
		_update_fp()

func _update_follow() -> void:
	if follow_target != null and is_instance_valid(follow_target):
		global_position = follow_target.global_position + follow_offset
		# 俯视目标，up 不能与视线平行（踩坑记录）
		look_at(follow_target.global_position, Vector3(0.0, 1.0, 0.0))

## FIRST_PERSON：位姿由 2D 层数据（fp_*）组装，零换算 1:1
## 相机沿视线水平方向前移 fp_forward_offset——不出模型会嵌在头内部没法玩
func _update_fp() -> void:
	var fwd := Vector3(cos(fp_yaw), 0.0, sin(fp_yaw))
	global_position = Vector3(fp_pos2d.x, fp_height_z, fp_pos2d.y) + fwd * fp_forward_offset
	# 2D facing 极角 → 3D 水平朝向：2D (x,y) 映射 3D (x,·,y)，
	# 相机默认朝 -Z，yaw=0 时应朝 2D +x 方向 → 基础角 = -90°
	rotation = Vector3(0.0, -fp_yaw - PI / 2.0, 0.0)
	rotate_object_local(Vector3(1.0, 0.0, 0.0), fp_pitch)
