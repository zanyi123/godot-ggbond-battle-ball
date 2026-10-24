extends Node3D
## 工单37 操控标签演示平台（主控）——纯演示场：无 GameManager/比分/计时/AI 评分
## 平台职责=展示操控标签抽象方式（16 条剧本，两层结构：面板=装载器，技能栏+快捷键=触发器）。
## 修复节落实（主人 10-17 验收反馈）：
##   修1 面板点选=装载到技能栏 3 格（不渲染）；按 4/5/6=触发对应格剧本（占位才出现）；未装载=无操作
##   修2 球=原决竞球模型（demo_ball 同源 BallProxy3DV2 口径）+左键按住瞄准→松开发球（复用操1 左键段口径）
##   修3 HUD 状态栏：测试者+陪衬体力条；作用类剧本命中扣血可见，归零自动回满
##   修4 FP 相机=球员模型外侧（头顶前外方锚点，模型不包围相机）
## 输入：复用真实键位习惯（4/5/6=技能格触发/左键=确认·瞄准发球/右键=取消/空格=迁移/A-D=偏转/Q=形状/T=合体/E=FP）
##   不接 input_manager/ssm（方案 B 自实现；剧本旁标注真体系入口，漂移由 r14 套件管）。
## 入口：F9（GlobalHotkeys，full_ai_platform 内不劫持给观测面板）。

const DemoActor := preload("res://scripts/test3d/demo/demo_actor.gd")
const DemoBall := preload("res://scripts/test3d/demo/demo_ball.gd")
const DemoPlaceholder := preload("res://scripts/test3d/demo/demo_placeholder.gd")
const DemoScripts := preload("res://scripts/test3d/demo/demo_scripts.gd")
const SchemaValidator := preload("res://scripts/systems/control_templates/schema_validator.gd")

const HALF_X := 500.0
const HALF_Z := 300.0
const BALL_HELD := 1            # DemoBall.BState.HELD
const BALL_POWER_PER_PX := 1.8  # 投球力度=鼠标距离映射（操1：距离力度）

var camera: Camera3D
var tester = null
var buddy = null
var ball = null
var runner  # DemoScripts.Runner
var loadout: Array[String] = ["", "", ""]   # 修1：技能栏 3 格（script id，空=未装载）
var fp_active := false
var _fp_yaw := 0.0
var _fp_pitch := -0.12
var _cam_home: Transform3D
var mouse_override := false          # true=外部驱动 mouse（自动演示/录屏用），_process 不覆盖
var fp_cross: Control                # FP 准星（剧本11：进FP显示，退出隐藏）
var _ball_aiming := false            # 修2：左键按住瞄准中
var _aim_line = null                 # 投球瞄准线（主控自有，不入 runner.keep）

# 面板
var hint_label: Label
var title_label: Label
var btn_map: Dictionary = {}     # id -> Button
var slot_labels: Array[Label] = []      # 修1：技能栏三格文本
var hp_fg: Dictionary = {}       # 修3：体力前景条 disp -> ColorRect
var _done_marked := false
var _last_hint := ""

# 38号 出口工作台（S3：37号演示场演化，同场景加参数栏——不建第二个场景）
var workbench_template: Dictionary = {}   # 当前编辑模板副本（resolved 全键；改值即时生效于演示场）
var wb_controls: Dictionary = {}          # key -> 控件引用（加载/恢复默认后回填）
var wb_status_label: Label
var wb_publish_edit: LineEdit

func _ready() -> void:
	_build_world()
	# 38号出口：装载 OP_SELECT 黄金模板（三级回落：gold→内置默认）
	var gold: Dictionary = SchemaValidator.read_template_file("res://data/control_templates/gold_op_select.json")
	workbench_template = SchemaValidator.resolve_params(gold.get("params", {}), "OP_SELECT")
	runner = DemoScripts.Runner.new()
	runner.setup({"tester": tester, "buddy": buddy, "parent": self, "half_x": HALF_X, "half_z": HALF_Z, "platform": self, "template": workbench_template})
	if DisplayServer.get_name() == "headless":
		print("[DemoPlatform] headless 冒烟就绪（16 剧本注册=%d）" % DemoScripts.SCRIPTS.size())
		return
	_build_panel()
	print("[DemoPlatform] ✅ 操控标签演示平台就绪（F9 入口；面板点选装载→4/5/6 触发）")


## ===== 场景搭建（地面+边界墙+测试者+陪衬+原模型球+灯光相机） =====
func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.14, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -32, 0)
	sun.light_energy = 1.1
	add_child(sun)

	camera = Camera3D.new()
	camera.position = Vector3(0, 620, 560)
	camera.fov = 52
	add_child(camera)
	camera.look_at(Vector3(0, 0, 0), Vector3.UP)
	_cam_home = camera.global_transform

	# 地面（1000x600 像素口径演示场）
	var ground_body := StaticBody3D.new()
	ground_body.name = "Ground"
	var ground_mesh := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(HALF_X * 2.0, 10, HALF_Z * 2.0)
	ground_mesh.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.22, 0.34, 0.24)
	ground_mesh.material_override = gmat
	ground_mesh.position = Vector3(0, -5, 0)
	ground_body.add_child(ground_mesh)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = gm.size
	col.shape = box
	col.position = Vector3(0, -5, 0)
	ground_body.add_child(col)
	add_child(ground_body)

	# 边界墙（视觉半透明，演示"碰墙"语义）
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.4, 0.6, 1.0, 0.16)
	wall_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for w in [
		[Vector3(0, 25, -HALF_Z), Vector3(HALF_X * 2.0 + 20, 50, 6)],
		[Vector3(0, 25, HALF_Z), Vector3(HALF_X * 2.0 + 20, 50, 6)],
		[Vector3(-HALF_X, 25, 0), Vector3(6, 50, HALF_Z * 2.0 + 20)],
		[Vector3(HALF_X, 25, 0), Vector3(6, 50, HALF_Z * 2.0 + 20)],
	]:
		var wm := MeshInstance3D.new()
		var wmesh := BoxMesh.new()
		wmesh.size = w[1]
		wm.mesh = wmesh
		wm.material_override = wall_mat
		wm.position = w[0]
		add_child(wm)

	# 演员与球（球=原决竞球模型，demo_ball 内同源 BallProxy3DV2 口径加载）
	tester = DemoActor.new()
	tester.position = Vector3(-160, 0, 0)
	add_child(tester)
	tester.setup(true, "测试者")
	buddy = DemoActor.new()
	buddy.position = Vector3(160, 0, 0)
	add_child(buddy)
	buddy.setup(false, "陪衬")
	ball = DemoBall.new()
	ball.position = Vector3(60, 0, -180)   # 场边（避中点：不与合体/出生路径重叠，R6）
	add_child(ball)


## ===== 面板（左侧 16 条分组列表 + 顶部演示名 + 底部技能栏三格 + 状态栏 + 步骤条） =====
func _build_panel() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DemoPanel"
	layer.layer = 60
	add_child(layer)

	var left := PanelContainer.new()
	left.position = Vector2(10, 10)
	left.custom_minimum_size = Vector2(250, 0)
	layer.add_child(left)
	var vb := VBoxContainer.new()
	left.add_child(vb)

	var head := Label.new()
	head.text = "操控标签演示平台（37号）"
	head.add_theme_font_size_override("font_size", 16)
	vb.add_child(head)
	var sub := Label.new()
	sub.text = "点选=装载技能栏 → 4/5/6 触发\n纯演示场·不接真体系（方案B）"
	sub.add_theme_font_size_override("font_size", 11)
	sub.modulate = Color(1, 1, 1, 0.6)
	vb.add_child(sub)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(230, 470)
	vb.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var last_group := ""
	for s in DemoScripts.SCRIPTS:
		var group := str(s.get("group"))
		if group != last_group:
			last_group = group
			var gl := Label.new()
			gl.text = "— " + group
			gl.modulate = Color(0.6, 0.85, 1.0)
			gl.add_theme_font_size_override("font_size", 12)
			list.add_child(gl)
		var id := str(s.get("id"))
		var btn := Button.new()
		btn.text = str(s.get("title"))
		btn.focus_mode = Control.FOCUS_NONE
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_script_btn.bind(id))
		list.add_child(btn)
		btn_map[id] = btn

	# 顶部当前演示名
	title_label = Label.new()
	title_label.position = Vector2(290, 10)
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.text = "面板点选标签装载 → 按技能键 4/5/6 触发演示"
	layer.add_child(title_label)

	# 底部步骤条 + 键位提示
	hint_label = Label.new()
	hint_label.position = Vector2(290, 40)
	hint_label.add_theme_font_size_override("font_size", 15)
	hint_label.modulate = Color(1.0, 0.95, 0.6)
	layer.add_child(hint_label)
	var keys := Label.new()
	keys.position = Vector2(290, 66)
	keys.add_theme_font_size_override("font_size", 12)
	keys.modulate = Color(1, 1, 1, 0.65)
	keys.text = "4/5/6=触发技能格 左键=确认·按住瞄准松开发球 右键=取消 空格=迁移 A/D=偏转 Q=形状 Tab=区域形状 T=合体 E=FP C/ESC=清场"
	layer.add_child(keys)

	# 修1：技能栏（屏幕底部中央三格，格名=已装载标签短名）
	var bar := PanelContainer.new()
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -185
	bar.offset_right = 185
	bar.offset_top = -62
	bar.offset_bottom = -10
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	bar.add_child(hb)
	for i in range(3):
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(112, 42)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cl := Label.new()
		cl.text = "格%d（空）" % (i + 1)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cl.add_theme_font_size_override("font_size", 12)
		cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(cl)
		hb.add_child(cell)
		slot_labels.append(cl)

	# 修3：状态栏（右上角两条：测试者/陪衬——避开顶部标题/步骤条区）
	_build_hp_bar(layer, "测试者", Color(0.3, 0.75, 1.0), 1110)
	_build_hp_bar(layer, "陪衬（敌）", Color(1.0, 0.45, 0.4), 1280)

	# FP 准星（剧本11：屏幕中心十字）
	fp_cross = Control.new()
	fp_cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	fp_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fp_cross.visible = false
	layer.add_child(fp_cross)
	_cross_bar(fp_cross, true)
	_cross_bar(fp_cross, false)

	# 38号：右栏=工作台参数表单（S3 三栏布局之右栏；按 schema 动态生成，改值即时生效）
	_build_workbench(layer)


func _build_hp_bar(layer: CanvasLayer, disp: String, color: Color, x_left: float) -> void:
	var name_l := Label.new()
	name_l.text = disp
	name_l.position = Vector2(x_left, 8)
	name_l.add_theme_font_size_override("font_size", 13)
	layer.add_child(name_l)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.12, 0.12, 0.85)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.position = Vector2(x_left, 30)
	bg.size = Vector2(150, 12)
	layer.add_child(bg)
	var fg := ColorRect.new()
	fg.color = color
	fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fg.position = Vector2(x_left, 30)
	fg.size = Vector2(150, 12)
	layer.add_child(fg)
	hp_fg[disp] = fg


## 准星横/竖条（以屏幕中心为锚）
func _cross_bar(parent: Control, horizontal: bool) -> void:
	var bar := ColorRect.new()
	bar.color = Color(1, 1, 1, 0.85)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.anchor_left = 0.5
	bar.anchor_top = 0.5
	bar.anchor_right = 0.5
	bar.anchor_bottom = 0.5
	if horizontal:
		bar.offset_left = -16
		bar.offset_right = 16
		bar.offset_top = -1
		bar.offset_bottom = 1
	else:
		bar.offset_left = -1
		bar.offset_right = 1
		bar.offset_top = -16
		bar.offset_bottom = 16
	parent.add_child(bar)


func _short_title(id: String) -> String:
	for s in DemoScripts.SCRIPTS:
		if str(s.get("id")) == id:
			var parts := str(s.get("title", id)).split(" ", false, 1)
			return parts[1] if parts.size() > 1 else str(s.get("title", id))
	return id


## ===== 修1：面板=装载器（点选只写装载表，不渲染） =====
func _on_script_btn(id: String) -> void:
	var slot := loadout.find(id)
	if slot >= 0:
		_set_hint("「%s」已在技能格 %d" % [_short_title(id), slot + 1])
		return
	var empty := loadout.find("")
	if empty >= 0:
		loadout[empty] = id
	else:
		loadout[0] = id   # 全满：替换最早装载格
	empty = loadout.find(id)
	_refresh_slots()
	_set_hint("已装载「%s」→按技能键 %d 触发" % [_short_title(id), empty + 1])


func _refresh_slots() -> void:
	for i in range(3):
		if slot_labels.size() > i and slot_labels[i] != null:
			var id: String = loadout[i]
			slot_labels[i].text = ("格%d %s" % [i + 1, _short_title(id)]) if id != "" else ("格%d（空）" % (i + 1))


func _set_hint(msg: String) -> void:
	_last_hint = msg
	if hint_label != null:
		hint_label.text = msg


## 修1：技能键触发对应格（未装载=无操作不误触；占位才出现）
func _trigger_slot(i: int) -> void:
	var id: String = loadout[i]
	if id == "":
		_set_hint("技能格 %d 未装载——先在左侧面板点选操控标签" % (i + 1))
		return
	# 键位表「4/5/6 再按=再击/两段推进/MIDFLY 干预/TOGGLED 再按同键」：
	# 同格剧本激活中再按=推进（K_ACTIVATE 直推），不重置剧本
	if runner.script_id == id and runner.is_busy():
		runner.advance(DemoScripts.K_ACTIVATE, runner.mouse)
		_set_hint(str(runner.result().get("hint", "")))
		return
	runner.switch_to(id)
	_done_marked = false
	var trig: String = runner.trigger_of(id)
	if trig != "enter_only":
		runner.advance(trig, runner.mouse)
	var def := _def_of(id)
	if title_label != null:
		title_label.text = "%s ｜ 占位模型：%s" % [str(def.get("title", id)), str(def.get("model", ""))]
	print("[DemoPlatform] 技能格 %d 触发 → %s（trigger=%s）" % [i + 1, id, trig])


func _def_of(id: String) -> Dictionary:
	for s in DemoScripts.SCRIPTS:
		if str(s.get("id")) == id:
			return s
	return {}


## ===== 输入翻译（演示控制器自实现，不接 input_manager/ssm） =====
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and fp_active:
		_fp_yaw -= event.relative.x * 0.003
		_fp_pitch = clampf(_fp_pitch - event.relative.y * 0.003, -1.2, 0.6)
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if fp_active:
					runner.advance(DemoScripts.K_CONFIRM, runner.mouse, -camera.global_transform.basis.z)
				elif _left_to_script():
					if runner.script_id == "drag":
						runner.advance(DemoScripts.K_PRESS, runner.mouse)   # 3.3 拖长击：按下=开始拖
					else:
						runner.advance(DemoScripts.K_CONFIRM, runner.mouse)
				elif ball != null and ball.state != BALL_HELD:
					_ball_aim_begin()   # 修2：空闲左键按住=瞄准（操1 口径）
			MOUSE_BUTTON_RIGHT:
				if _ball_aiming:
					_ball_aim_cancel()   # 键位表：瞄准中右键=取消投球
				else:
					runner.advance(DemoScripts.K_CANCEL, runner.mouse)
					if fp_active:
						enter_fp(false)   # 剧本开的 FP 随横切取消一并退出
		return
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _ball_aiming:
				_ball_throw_release()   # 修2：松开=发球
			elif runner.script_id == "drag" and _left_to_script():
				runner.advance(DemoScripts.K_CONFIRM, runner.mouse)   # 3.3 松开=作用/取消选中
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_4:
				_trigger_slot(0)
			KEY_5:
				_trigger_slot(1)
			KEY_6:
				_trigger_slot(2)
			KEY_SPACE:
				runner.advance(DemoScripts.K_SPACE, runner.mouse)
			KEY_Q:
				runner.advance(DemoScripts.K_SHAPE, runner.mouse)
			KEY_TAB:
				runner.advance(DemoScripts.K_TAB, runner.mouse)   # 19：区域形状切换（02表§4 Tab 分流语义）
			KEY_T:
				runner.advance(DemoScripts.K_T, runner.mouse)
			KEY_E:
				runner.advance(DemoScripts.K_E, runner.mouse)
			KEY_C, KEY_ESCAPE:
				runner.cancel()
			KEY_A:
				_feed_ad(-1.0)
			KEY_D:
				_feed_ad(1.0)


## 左键归属分流：激活剧本持有左键（drag 全程；其余激活中）；空闲=投球交互
func _left_to_script() -> bool:
	if runner.script_id == "" or runner.done:
		return false
	if runner.script_id == "drag":
		return true
	return runner.is_busy()


## ===== 修2 投球交互（复用操1 左键段口径：按住瞄准→松开发球） =====
func _ball_aim_begin() -> void:
	_ball_aiming = true
	ball.hold_at(tester)
	_aim_line = DemoPlaceholder.new()
	add_child(_aim_line)
	_aim_line.setup(DemoPlaceholder.Kind.LINE, {"color": Color(0.95, 0.9, 0.5)})
	_set_hint("瞄准中：移动鼠标选方向（力度随距离），松开左键发球；右键取消")


func _ball_throw_release() -> void:
	_ball_aiming = false
	if _aim_line != null:
		_aim_line.call("vanish")
		_aim_line = null
	var d: Vector3 = runner.mouse - tester.global_position
	d.y = 0.0
	var power: float = clampf(d.length() * BALL_POWER_PER_PX, 300.0, 700.0)
	ball.throw_toward(d, power)
	_set_hint("球已发出（力度 %d）" % int(power))


func _ball_aim_cancel() -> void:
	_ball_aiming = false
	if _aim_line != null:
		_aim_line.call("vanish")
		_aim_line = null
	ball.cancel_hold()
	_set_hint("已取消投球瞄准")


## A/D 分流：migrate 操控窗=A/D 迁移为占位左右移动（02表§1）；guide 制导期=A/D 偏转；steer 引导期=偏转增量
func _feed_ad(sign_val: float) -> void:
	if runner.script_id == "migrate" and runner.phase == "active":
		runner.advance("move", Vector3.ZERO, Vector3(sign_val, 0, 0))
		return
	if runner.script_id == "guide_ball" and runner.phase == "guiding":
		runner.advance(DemoScripts.K_AD, runner.mouse, Vector3(sign_val, 0, 0))
		return
	var migrating: bool = runner.script_id == "steer" and runner.phase == "flying"
	if migrating:
		runner.advance(DemoScripts.K_AD, runner.mouse, Vector3(sign_val, 0, 0))


## ===== 每帧 =====
func _process(delta: float) -> void:
	if runner == null:
		return
	_update_mouse_ground()
	# 修4：FP 相机=球员模型外侧（头顶前外方锚点）
	if fp_active and tester != null:
		camera.global_position = tester.fp_eye_global()
		camera.rotation = Vector3(_fp_pitch, _fp_yaw, 0)
	# 投球瞄准线跟随
	if _ball_aiming and _aim_line != null:
		_aim_line.call("set_line", tester.global_position + Vector3(0, 42, 0), runner.mouse + Vector3(0, 2, 0))
	# 测试者 WASD（02表§1 迁移：migrate 操控窗激活期方向键全迁移给占位，球员不动；guide 制导期 W 让给球；steer 引导期 A/D 让给占位偏转）
	if not fp_active and tester != null:
		var mv := Vector2.ZERO
		var migrate_on: bool = runner.script_id == "migrate" and runner.phase == "active"
		var guide_on: bool = runner.script_id == "guide_ball" and runner.phase == "guiding"
		if migrate_on:
			# 迁移语义：移动方向键控占位（移动可见），球员不动
			var mdir := Vector3.ZERO
			if Input.is_key_pressed(KEY_W):
				mdir.z -= 1.0
			if Input.is_key_pressed(KEY_S):
				mdir.z += 1.0
			if Input.is_key_pressed(KEY_A):
				mdir.x -= 1.0
			if Input.is_key_pressed(KEY_D):
				mdir.x += 1.0
			if mdir.length_squared() > 0.01:
				runner.advance("move", Vector3.ZERO, mdir.normalized())
		elif guide_on:
			# OP_GUIDE 双源之一：W=球朝鼠标移动（A/D 走 _feed_ad 偏转），球员不动
			if Input.is_key_pressed(KEY_W):
				runner.advance("move", runner.mouse, Vector3.ZERO)
		else:
			if Input.is_key_pressed(KEY_W):
				mv.y -= 1.0
			if Input.is_key_pressed(KEY_S):
				mv.y += 1.0
			var ad_busy: bool = runner.script_id == "steer" and runner.phase == "flying"
			if not ad_busy:
				if Input.is_key_pressed(KEY_A):
					mv.x -= 1.0
				if Input.is_key_pressed(KEY_D):
					mv.x += 1.0
		tester.move_step(mv, delta, HALF_X, HALF_Z)
		if runner.mouse.length_squared() > 1.0:
			tester.face_ground(runner.mouse)
	runner.tick(delta)
	# 修3：状态栏体力刷新（UI 只读消费，零判定）
	if hp_fg.has("测试者") and tester != null:
		(hp_fg["测试者"] as ColorRect).size.x = 150.0 * float(tester.hp) / float(tester.max_hp)
	if hp_fg.has("陪衬（敌）") and buddy != null:
		(hp_fg["陪衬（敌）"] as ColorRect).size.x = 150.0 * float(buddy.hp) / float(buddy.max_hp)
	# 步骤条：runner.hint 变化即刷（含待点亮登记提示等非激活态）；主控即时提示靠 _set_hint 同步防覆盖
	if hint_label != null and str(runner.hint) != _last_hint:
		hint_label.text = str(runner.hint)
		_last_hint = str(runner.hint)
	if runner.done and not _done_marked and runner.script_id != "":
		_done_marked = true
	# 23 OP_HOLD：维持键按住轮询（键位从模板 ctl_input_hold_key 读——扩展口①）
	if runner.script_id == "hold_aura" and runner.phase == "holding":
		var hc := OS.find_keycode_from_string("KEY_" + str(runner.tpl("ctl_input_hold_key", "H")).trim_prefix("KEY_"))
		if hc != 0 and Input.is_key_pressed(hc):
			runner.advance(DemoScripts.K_HOLD, Vector3.ZERO)
	# OP_SELECT：选择中隐藏系统光标（34号口径：投影环替身），退出恢复
	var select_on: bool = runner.script_id == "whiteball_select" and (runner.phase == "selecting" or runner.phase == "choosing_target")
	if select_on and Input.mouse_mode != Input.MOUSE_MODE_HIDDEN:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	elif not select_on and Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _update_mouse_ground() -> void:
	if fp_active or camera == null or mouse_override:
		return
	var mpos := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mpos)
	var normal := camera.project_ray_normal(mpos)
	if absf(normal.y) < 0.0001:
		return
	var t := -origin.y / normal.y
	if t < 0.0:
		return
	runner.mouse = origin + normal * t


## 22 FP_SELECT 准星判定用：当前 FP 前向/眼位（非 FP 返回零向量）
func get_fp_forward() -> Vector3:
	return -camera.global_transform.basis.z if fp_active and camera != null else Vector3.ZERO


func get_fp_eye() -> Vector3:
	return tester.fp_eye_global() if fp_active and tester != null else Vector3.ZERO


## ===== 修4：FP 进出（相机=球员模型外侧锚点） =====
func enter_fp(on: bool) -> void:
	if on == fp_active:
		return
	fp_active = on
	if fp_cross != null:
		fp_cross.visible = on
	if on:
		_fp_yaw = tester.rotation.y if tester != null else 0.0
		_fp_pitch = -0.12
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		camera.global_transform = _cam_home
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## ===== 38号 出口工作台（S3 右栏：按 schema 动态生成参数表单，改值即时生效；C2/C3/C4/C5） =====
func _build_workbench(layer: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(1176, 10)
	panel.custom_minimum_size = Vector2(256, 0)
	layer.add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)

	var head := Label.new()
	head.text = "操控出口工作台（38号）"
	head.add_theme_font_size_override("font_size", 15)
	vb.add_child(head)
	wb_status_label = Label.new()
	wb_status_label.text = "模板：gold_op_select（合法）"
	wb_status_label.add_theme_font_size_override("font_size", 11)
	wb_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(wb_status_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(240, 430)
	vb.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var group_names := {"ctl_input": "— 交互（input）", "ctl_visual": "— 显示（visual）", "ctl_time": "— 时序（time）"}
	var done_groups := {}
	for key in SchemaValidator.SCHEMAS:
		for g in group_names:
			if str(key).begins_with(g) and not done_groups.has(g):
				done_groups[g] = true
				var gl := Label.new()
				gl.text = str(group_names[g])
				gl.modulate = Color(0.6, 0.85, 1.0)
				gl.add_theme_font_size_override("font_size", 12)
				list.add_child(gl)
		var row := HBoxContainer.new()
		var kl := Label.new()
		kl.text = _wb_short_key(key)
		kl.tooltip_text = key
		kl.custom_minimum_size = Vector2(96, 0)
		kl.add_theme_font_size_override("font_size", 11)
		row.add_child(kl)
		row.add_child(_wb_make_control(key))
		list.add_child(row)

	# 模板管理按钮（C5：草稿/发布分开）
	var row1 := HBoxContainer.new()
	vb.add_child(row1)
	var b_save := Button.new()
	b_save.text = "保存草稿"
	b_save.focus_mode = Control.FOCUS_NONE
	b_save.pressed.connect(_wb_save_draft)
	row1.add_child(b_save)
	var b_load := Button.new()
	b_load.text = "加载草稿"
	b_load.focus_mode = Control.FOCUS_NONE
	b_load.pressed.connect(_wb_load_draft)
	row1.add_child(b_load)
	var b_reset := Button.new()
	b_reset.text = "恢复默认"
	b_reset.focus_mode = Control.FOCUS_NONE
	b_reset.pressed.connect(_wb_reset_default)
	row1.add_child(b_reset)
	var row2 := HBoxContainer.new()
	vb.add_child(row2)
	wb_publish_edit = LineEdit.new()
	wb_publish_edit.text = "ctl_select_01"
	wb_publish_edit.custom_minimum_size = Vector2(120, 0)
	row2.add_child(wb_publish_edit)
	var b_pub := Button.new()
	b_pub.text = "发布实战"
	b_pub.focus_mode = Control.FOCUS_NONE
	b_pub.pressed.connect(_wb_publish)
	row2.add_child(b_pub)
	_wb_refresh_controls()
	_wb_status_refresh()


func _wb_short_key(key: String) -> String:
	return key.trim_prefix("ctl_input_").trim_prefix("ctl_visual_").trim_prefix("ctl_time_")


## C3 动态控件映射：float→SpinBox / bool→CheckBox / enum→OptionButton / res_path·key→LineEdit / color→ColorPickerButton / vec2→双SpinBox
func _wb_make_control(key: String) -> Control:
	var schema: Dictionary = SchemaValidator.SCHEMAS.get(key, {})
	var cur: Variant = workbench_template.get(key, schema.get("default"))
	match str(schema.get("type", "")):
		"float":
			var sp := SpinBox.new()
			sp.min_value = 0.0
			sp.max_value = 2000.0
			sp.step = 0.1
			sp.value = float(cur)
			sp.custom_minimum_size = Vector2(96, 0)
			# 38号工作台：SpinBox.value_changed 首参=新值，必须用 lambda 把 (key, value) 按 _on_param 签名传；
			# 原 _on_param.bind(key) 会把 float 当第一个 String 形参→运行时报错、参数改不动（2026-10-24 验收抓出）
			sp.value_changed.connect(func(v: float): _on_param(key, v))
			wb_controls[key] = sp
			return sp
		"bool":
			var cb := CheckBox.new()
			cb.button_pressed = bool(cur)
			# 同上：CheckBox.toggled 首参=bool，用 lambda 按 (key, value) 传
			cb.toggled.connect(func(on: bool): _on_param(key, on))
			wb_controls[key] = cb
			return cb
		"enum":
			var ob := OptionButton.new()
			for v in schema.get("values", []):
				ob.add_item(str(v))
			ob.selected = schema.get("values", []).find(str(cur))
			ob.item_selected.connect(func(idx: int): _on_param(key, schema.get("values", [])[idx]))
			wb_controls[key] = ob
			return ob
		"color":
			var cp := ColorPickerButton.new()
			cp.color = Color.html(str(cur))
			cp.custom_minimum_size = Vector2(60, 22)
			cp.color_changed.connect(func(c: Color): _on_param(key, "#" + c.to_html(true)))
			wb_controls[key] = cp
			return cp
		"vec2":
			var hb := HBoxContainer.new()
			var sx := SpinBox.new()
			sx.min_value = -2000.0
			sx.max_value = 2000.0
			sx.value = float(cur.get("x", 0.0))
			sx.custom_minimum_size = Vector2(64, 0)
			sx.value_changed.connect(func(v: float): _on_param(key, v, "x"))
			var sy := SpinBox.new()
			sy.min_value = -2000.0
			sy.max_value = 2000.0
			sy.value = float(cur.get("y", 0.0))
			sy.custom_minimum_size = Vector2(64, 0)
			sy.value_changed.connect(func(v: float): _on_param(key, v, "y"))
			hb.add_child(sx)
			hb.add_child(sy)
			wb_controls[key] = {"x": sx, "y": sy}
			return hb
		_:
			var le := LineEdit.new()
			le.text = str(cur)
			le.custom_minimum_size = Vector2(120, 0)
			le.text_changed.connect(_on_param_text.bind(key))
			wb_controls[key] = le
			return le


func _on_param_text(text: String, key: String) -> void:
	_on_param(key, text)


func _on_param(key: String, value: Variant, sub: String = "") -> void:
	if key == "ctl_visual_offset":
		var off: Dictionary = (workbench_template.get(key, {"x": 0.0, "y": 0.0}) as Dictionary).duplicate()
		off[sub] = value
		workbench_template[key] = off
	else:
		workbench_template[key] = value
	_wb_status_refresh()


## C2/C4：即时校验状态行（非法值红字提示；演示场由消费端默认兜底不崩）
func _wb_status_refresh() -> void:
	if wb_status_label == null:
		return
	var params := workbench_template.duplicate(true)
	params.erase("_model_ok")
	var r: Dictionary = SchemaValidator.validate(params)
	if r.ok:
		var m1 := "（M1 兜底占位）" if not bool(r.get("model_ok", false)) else ""
		wb_status_label.text = "模板合法 ✓%s\n生效键 %d 个" % [m1, workbench_template.size() - 1]
		wb_status_label.modulate = Color(0.6, 1.0, 0.6)
	else:
		wb_status_label.text = "✗ " + str((r.errors as Array).front())
		wb_status_label.modulate = Color(1.0, 0.5, 0.4)


func _wb_refresh_controls() -> void:
	for key in wb_controls:
		var schema: Dictionary = SchemaValidator.SCHEMAS.get(key, {})
		var cur: Variant = workbench_template.get(key, schema.get("default"))
		var ctl: Variant = wb_controls[key]
		match str(schema.get("type", "")):
			"float":
				(ctl as SpinBox).set_value_no_signal(float(cur))
			"bool":
				(ctl as CheckBox).set_pressed_no_signal(bool(cur))
			"enum":
				(ctl as OptionButton).select(schema.get("values", []).find(str(cur)))
			"color":
				(ctl as ColorPickerButton).color = Color.html(str(cur))
			"vec2":
				(ctl as Dictionary)["x"].set_value_no_signal(float(cur.get("x", 0.0)))
				(ctl as Dictionary)["y"].set_value_no_signal(float(cur.get("y", 0.0)))
			_:
				(ctl as LineEdit).text = str(cur)


func _wb_clean_params() -> Dictionary:
	var out := workbench_template.duplicate(true)
	out.erase("_model_ok")
	return out


func _wb_save_draft() -> void:
	var ok: bool = SchemaValidator.save_draft("op_select_draft", {"version": 1, "source": "workbench", "operator": str(workbench_template.get("ctl_input_operator", "OP_SELECT")), "params": _wb_clean_params()})
	_set_hint("工作台：" + ("草稿已存 user://control_drafts/" if ok else "草稿保存失败"))


func _wb_load_draft() -> void:
	var tpl: Dictionary = SchemaValidator.read_template_file(SchemaValidator.DRAFT_DIR + "op_select_draft.json")
	if tpl.is_empty():
		_set_hint("工作台：无草稿可加载")
		return
	workbench_template = SchemaValidator.resolve_params(tpl.get("params", {}), str(tpl.get("operator", "OP_SELECT")))
	runner.env["template"] = workbench_template
	_wb_refresh_controls()
	_wb_status_refresh()
	_set_hint("工作台：草稿已加载（调参即时生效）")


func _wb_reset_default() -> void:
	var gold: Dictionary = SchemaValidator.read_template_file("res://data/control_templates/gold_op_select.json")
	workbench_template = SchemaValidator.resolve_params(gold.get("params", {}), "OP_SELECT")
	runner.env["template"] = workbench_template
	_wb_refresh_controls()
	_wb_status_refresh()
	_set_hint("工作台：已恢复 gold_op_select 默认")


func _wb_publish() -> void:
	var pname := wb_publish_edit.text.strip_edges()
	if pname.is_empty():
		_set_hint("工作台：发布 id 不可为空")
		return
	var ok: bool = SchemaValidator.save_published(pname, {"version": 1, "source": "workbench", "operator": str(workbench_template.get("ctl_input_operator", "OP_SELECT")), "params": _wb_clean_params()})
	_set_hint("工作台：" + ("已发布实战库 data/control_templates/%s.json" % pname if ok else "发布失败（校验未过，看状态行）"))
