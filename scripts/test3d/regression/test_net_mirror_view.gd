## 工单01 S11 · 网络套件 E：S8 视图镜像数学（guest 己方永远在左）
## 运行：bash ./run_suite_guarded.sh res://scripts/test3d/regression/test_net_mirror_view.gd
## 覆盖：镜像判定（B 队）、move/aim 互逆换算、世界↔屏幕往返、相机 yaw 常量、HUD 侧序。
extends SceneTree

var _pass: int = 0
var _fail: int = 0

func _initialize() -> void:
	_run()
	print("\n========== 结果：%d/%d PASS ==========" % [_pass, _pass + _fail])
	quit(0 if _fail == 0 else 1)

func _assert(cond: bool, n: String) -> void:
	if cond:
		_pass += 1
		print("  ✅ PASS: " + n)
	else:
		_fail += 1
		print("  ❌ FAIL: " + n)

func _run() -> void:
	print("\n========== 工单01 · 网络套件 E（S8 镜像数学） ==========\n")

	var slot_a := {"team": "A", "slot": 0}
	var slot_b := {"team": "B", "slot": 0}
	var field_center := Vector2(650, 390)   # 全场 1300×780 场心

	# M1 镜像判定：B 队才镜像
	_assert(not NetView.needs_mirror(slot_a), "M1a: A 队（host 侧）不镜像=现单机视角")
	_assert(NetView.needs_mirror(slot_b), "M1b: B 队（guest 侧）镜像=己方渲染到屏幕左")
	_assert(not NetView.needs_mirror({}), "M1c: 无槽位（单机/未入房）不镜像")

	# M2 移动/瞄准互逆（按左=往屏幕左走）
	_assert(NetView.mirror_move(Vector2(1, 0), true) == Vector2(-1, 0), "M2a: guest 屏幕右→世界左")
	_assert(NetView.mirror_move(Vector2(0, 1), true) == Vector2(0, -1), "M2b: guest 屏幕下→世界上")
	_assert(NetView.mirror_move(Vector2(1, 0), false) == Vector2(1, 0), "M2c: host 恒等")
	_assert(NetView.mirror_aim(Vector2(0.7, -0.7), true) == Vector2(-0.7, 0.7), "M2d: 瞄准向量同律换算（D17 aim 上行）")

	# M3 世界↔屏幕往返（绕场心 180°）
	var world_pos := Vector2(100, 200)          # A 队半场（世界左）
	var on_guest_screen: Vector2 = NetView.world_to_screen(world_pos, field_center, true)
	_assert(on_guest_screen.x > field_center.x, "M3a: 世界左半场 → guest 屏幕右半（敌我互换位）")
	var round_trip: Vector2 = NetView.screen_to_world(on_guest_screen, field_center, true)
	_assert(absf(round_trip.x - world_pos.x) < 0.001 and absf(round_trip.y - world_pos.y) < 0.001, "M3b: 屏幕→世界往返无损（放置点上行换算）")
	_assert(NetView.world_to_screen(world_pos, field_center, false) == world_pos, "M3c: host 世界=屏幕恒等")

	# M4 相机与 HUD
	_assert(absf(NetView.CAMERA_YAW_OFFSET - PI) < 0.001, "M4a: 镜像机位=绕场心 yaw 180°")
	_assert(NetView.hud_flip(true) and not NetView.hud_flip(false), "M4b: guest HUD 侧序镜像（计分板己方在左）")
