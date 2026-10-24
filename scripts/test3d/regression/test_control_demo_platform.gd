## 工单37 S4 自测套件：操控标签演示平台
## 覆盖：A 基础件（四件脚本+场景+注册表16条8组）/ B 占位模型映射表逐条对账（37号§一映射表写死）/
##       C 剧本推演（16条操作序列 headless 走通+完成标志）/ D 横切（右键取消+切换清场）/
##       E 提示一致性（steps/model/system_entry 非空+02表标注）/ F F9 入口与 full_ai 防劫持。
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_control_demo_platform.gd
extends SceneTree

const PLATFORM_SCENE := "res://scenes/test3d/skill_control_demo_platform.tscn"
const HOTKEYS_PATH := "res://scripts/core/global_hotkeys.gd"

var _pass: int = 0
var _fail: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== 工单37：操控标签演示平台自测 ==========\n")
	for i in range(3):
		await process_frame  # 等 autoload 就位

	var DemoScripts: GDScript = load("res://scripts/test3d/demo/demo_scripts.gd")
	var DemoPlaceholder: GDScript = load("res://scripts/test3d/demo/demo_placeholder.gd")
	var DemoActor: GDScript = load("res://scripts/test3d/demo/demo_actor.gd")
	var DemoBall: GDScript = load("res://scripts/test3d/demo/demo_ball.gd")
	var MainScript: GDScript = load("res://scripts/test3d/skill_control_demo_platform.gd")

	# ===== A 基础件 =====
	_assert("A1: demo 四件+主控脚本可加载", DemoScripts != null and DemoPlaceholder != null and DemoActor != null and DemoBall != null and MainScript != null)
	var packed: PackedScene = load(PLATFORM_SCENE)
	_assert("A2: 平台场景 tscn 可加载", packed != null)
	var platform: Node3D = packed.instantiate()
	root.add_child(platform)
	_assert("A3: 场景实例化+headless 冒烟 ready（runner 已建）", platform.runner != null)
	_assert("A4: 场景基础元素齐（相机/测试者/陪衬/球地面）", platform.camera != null and platform.tester != null and platform.buddy != null)

	var scripts: Array = DemoScripts.SCRIPTS
	_assert("A5: 注册表 23 条（+23 OP_HOLD 首例）", scripts.size() == 23)
	var groups := {}
	var ids := {}
	var fields_ok := true
	for s in scripts:
		groups[str(s.get("group"))] = true
		ids[str(s.get("id"))] = true
		for k in ["id", "group", "title", "model", "steps", "done_text", "system_entry"]:
			if str(s.get(k, "")).is_empty():
				fields_ok = false
	_assert("A6: 分组 9 组（…时序横切/抽象参考标签）", groups.size() == 9)
	_assert("A7: 每条 id/group/title/model/steps/done_text/system_entry 全非空", fields_ok)

	# ===== B 占位模型映射表（37号§一映射表写死，改动=改工单表） =====
	var expect := {
		"auto": "圆球", "aim": "圆球", "point": "贴地色块", "mark": "五角星",
		"steer": "圆球", "midfly": "圆球", "toggle": "方块", "key_jump": "圆球",
		"place": "贴地色块+方块", "summon": "圆球", "fp": "圆球", "combo": "组合体",
		"multi_hit": "圆球→方块→五角星", "drag": "连线+五角星",
		"cancel_demo": "圆球", "migrate": "圆球",
		"whiteball_select": "可选对象+投影环", "shark_swim": "定向占位(圆球)",
		"fastlane_d14": "贴地区域(四形)+占位", "guide_ball": "圆球(手动态)",
		"firework_use": "形态占位(A/B)", "fp_whiteball": "FP准星+可选对象",
		"hold_aura": "维持占位(光环)",
	}
	var map_ok := true
	var map_bad := ""
	for s in scripts:
		var id := str(s.get("id"))
		if str(expect.get(id, "?")) != str(s.get("model")):
			map_ok = false
			map_bad += id + " "
	_assert("B1: 23 条占位映射逐条对上工单映射表" + ("" if map_ok else "（不符=" + map_bad + "）"), map_ok)

	# ===== C 剧本推演（操作序列 headless 走通+完成标志触发） =====
	var runner = platform.runner
	_drive_auto(runner);        _assert("C1 auto: 闪烁1s→消失→完成", runner.done)
	_drive_aim(runner);         _assert("C2 aim: 瞄准→左键定方向→飞出→完成", runner.done)
	_drive_point(runner);       _assert("C3 point: SELECTING→选点→落点→完成", runner.done)
	_drive_mark(runner);        _assert("C4 mark: MARKING→选陪衬→贴附→完成+命中扣血(100→90)", runner.done and platform.buddy.hp == 90)
	_drive_steer(runner);       _assert("C5 steer: 飞出→引导→结束→完成", runner.done)
	_drive_midfly(runner);      _assert("C6 midfly: 飞出→3次干预→飞完→完成", runner.done)
	_drive_toggle(runner);      _assert("C7 toggle: 开→关→完成", runner.done)
	_drive_key_jump(runner);    _assert("C8 key_jump: 激活→空格→跳→落地→完成", runner.done)
	_drive_place(runner);       _assert("C9 place: 预览(Q切形状)→放置→转实体→完成（方块持续在场）", runner.done and runner.keep.size() > 0)
	_drive_summon(runner);      _assert("C10 summon: 召唤→点地移动→寿命尽→完成", runner.done)
	_drive_fp(runner);          _assert("C11 fp: 进FP→准星释放→飞出→完成", runner.done)
	_drive_combo(runner);       _assert("C12 combo: T合体→T拆分→完成", runner.done)
	_drive_multi_hit(runner);   _assert("C13 multi_hit: 三段形态→完成", runner.done)
	_drive_drag(runner);        _assert("C14 drag: 按住拖动→吸附→作用→完成+命中扣血(90→80)", runner.done and platform.buddy.hp == 80)
	_drive_cancel_demo(runner); _assert("C15 cancel_demo: 右键取消→子态保留→重选确认→走完", runner.done and runner.phase == "idle")
	_drive_migrate(runner);     _assert("C16 migrate: 操控窗→空格跳+方向键移动→收窗→完成", runner.done)
	_drive_whiteball_select(runner)
	_assert("C17 OP_SELECT: 进选择→单选→锁定敌→命中（扣血）", runner.done and platform.buddy.hp < 100)
	_drive_whiteball_deliver(runner); _assert("C17b OP_SELECT 交付链: 单选→锁定队友→贴附消散→完成", runner.done)
	_drive_whiteball_green(runner); _assert("C17c OP_SELECT 绿环占位: 单选→锁定敌→命中（两种占位均可操作）", runner.done and platform.buddy.hp < 100)
	_drive_shark_swim(runner);       _assert("C18 OP_ORIENT: 定向自游→潜/浮翻转→触碰敌→完成", runner.done)
	_drive_fastlane_d14(runner);     _assert("C19 OP_TRAIL: 球员锚预览+Tab四形轮转→铺开→入区域增速→走完", runner.done)
	_drive_guide_ball(runner);       _assert("C20 OP_GUIDE: 发球→W 朝鼠标+A/D→收回→完成", runner.done)
	_drive_hold_aura(runner);  _assert("C23 OP_HOLD: 生成→按住刷新→松开衰减→归零消散", runner.done)
	_drive_firework_use(runner, platform); _assert("C21 OP_TRANSFORM: 形态A→Q变身B→触碰敌(扣血)→恢复A", runner.done and platform.buddy.hp < 100)
	await _drive_fp_whiteball(runner, platform)
	_assert("C22 FP_SELECT: 进FP→准星单选→锁定敌→命中", runner.done and platform.buddy.hp < 100)

	# ===== D 时序横切 =====
	runner.switch_to("aim")
	runner.advance("activate")
	_assert("D1: aim 激活后有占位产物", runner.keep.size() > 0)
	runner.advance("cancel")
	_assert("D2: 右键横切→清场回空闲（keep 空+phase=idle）", runner.keep.is_empty() and runner.phase == "idle")
	runner.switch_to("point")
	runner.advance("activate")
	var pre_keep: int = runner.keep.size()
	runner.switch_to("place")
	_assert("D3: 切换演示清场不残留（旧占位即清）", pre_keep > 0 and runner.keep.is_empty())
	# 15号横切对其它剧本生效已在 D2 验证；cancel_demo 自身吃右键在 C15

	# ===== G 修复节四修（主人 10-17 验收反馈） =====
	runner.clear_script()
	runner.script_id = ""
	runner.phase = "idle"
	runner.done = false
	platform.buddy.hp = 100
	var loadout: Array = platform.loadout
	_assert("G1: 技能栏 3 格初始全空", loadout.size() == 3 and loadout.count("") == 3)
	platform._on_script_btn("aim")
	_assert("G2: 面板点选=装载不触发（格1=aim 且零占位零剧本）", loadout[0] == "aim" and runner.script_id == "" and runner.keep.is_empty())
	var trig_bad := ""
	for s in scripts:
		var tg := str(runner.trigger_of(str(s.get("id"))))
		if tg != "activate" and tg != "t_key" and tg != "e_key" and tg != "enter_only":
			trig_bad += str(s.get("id")) + ":" + tg + " "
	_assert("G3: 16 条 trigger 全合法（activate/t_key/e_key/enter_only）", trig_bad == "")
	platform._trigger_slot(1)
	_assert("G4: 空格触发=无操作（不误触）", runner.script_id == "" and runner.keep.is_empty())
	platform._trigger_slot(0)
	_assert("G5: 装载后按技能键→占位出现（修1 两层结构通）", runner.script_id == "aim" and runner.keep.size() > 0)
	platform._on_script_btn("mark")
	platform._on_script_btn("aim")
	platform._on_script_btn("point")
	platform._on_script_btn("steer")
	platform._on_script_btn("toggle")
	_assert("G6: 重复装载无操作+全满替换最早格（[toggle,mark,point]）", loadout[0] == "toggle" and loadout[1] == "mark" and loadout[2] == "point")
	_assert("G7: 球=原决竞球模型加载成功（修2）", platform.ball.is_model_ok())
	platform.ball.hold_at(platform.tester)   # 发球时手持：先 hold 再 throw
	await process_frame
	var hold_off: Vector3 = platform.ball.position - platform.tester.global_position
	_assert("G8a: 持球=贴身右手位（手持正确：高度38+水平贴身）", platform.ball.state == 1 and hold_off.y > 30.0 and Vector2(hold_off.x, hold_off.z).length() < 25.0)
	platform.ball.throw_toward(Vector3(1, 0, 0), 500.0)
	var bx: float = platform.ball.position.x
	for i in range(14):
		await process_frame
	_assert("G8: 手持发球后位移>30px", platform.ball.position.x > bx + 30.0)
	platform.ball.reset_ball()
	_assert("G9: 命中扣血归零自动回满（演示循环）", (platform.buddy.call("take_hit", 95) == false) and platform.buddy.hp == 5 and (platform.buddy.call("take_hit", 10) == true) and platform.buddy.hp == 100)
	# G10 飞行占位触碰命中（朝陪衬方向飞→命中扣血+完成）
	_trigger(runner, "aim")
	_step(runner, "confirm", Vector3(160, 0, 0))
	_spin(runner, 3.0)
	_assert("G10: aim 朝敌飞→触碰命中（100→90+done）", runner.done and platform.buddy.hp == 90)
	platform.enter_fp(true)
	var eye_offset: Vector3 = platform.camera.global_position - platform.tester.global_position
	platform.enter_fp(false)
	_assert("G11: FP 相机=模型外侧（前偏40+头顶62，不封闭）", eye_offset.length() > 40.0 and eye_offset.y > 55.0)
	_assert("G12: 左键分流（空载=投球/激活=剧本/完成=投球）", platform._left_to_script() == false)
	runner.switch_to("migrate")
	runner.advance("activate")
	_assert("G12b: 激活中左键归剧本", platform._left_to_script() == true)
	runner.cancel()
	_assert("G12c: 取消后左键还投球", platform._left_to_script() == false)
	# R1 复验：同格激活中再按=推进不重置（键位表 4/5/6 再按语义）
	platform.loadout[0] = "toggle"
	platform.loadout[1] = ""
	platform.loadout[2] = ""
	platform._trigger_slot(0)
	_assert("G13a: toggle 技能键触发=开（占位持续）", runner.phase == "on")
	platform._trigger_slot(0)
	_assert("G13b: 同格再按=关闭完成（不再重开）", runner.done and runner.phase == "idle")
	# R2 复验：迁移移动（02表§1 移动方向键迁移）
	_trigger(runner, "migrate")
	var mpx: float = runner.ph.position.x
	for i in range(10):
		runner.advance("move", Vector3.ZERO, Vector3(1, 0, 0))
	_assert("G14: 迁移方向键=占位移动（10次步进+50px）", runner.ph.position.x > mpx + 40.0)
	runner.advance("activate")
	# R4 复验：mark 点谁贴谁
	platform.tester.hp = 100
	_trigger(runner, "mark")
	runner.advance("confirm", Vector3(-160, 0, 0))
	_assert("G15: mark 点测试者→星贴测试者+测试者扣血（目标不再写死陪衬）", platform.tester.hp == 90)
	runner.cancel()

	# ===== E 提示一致性 =====
	var entry_ok := true
	for s in scripts:
		var se := str(s.get("system_entry", ""))
		if str(s.get("group")) == "抽象参考标签":
			if not (se.begins_with("配方登记") or se.begins_with("38号§")):
				entry_ok = false
		elif not se.begins_with("02表"):
			entry_ok = false
	_assert("E1: 体系入口标注分口径（16 operator=02表 / 抽象参考=配方登记或扩展口登记，防两套漂移）", entry_ok)
	var no_skill_words := true
	for s in scripts:
		for w in ["芬尼", "鲨鱼", "快道", "烟花", "白球"]:
			if w in str(s.get("title", "")) or w in str(s.get("steps", "")):
				no_skill_words = false
	_assert("E2: 抽象层零具体技能词（主人 10-20 裁：平台演示=抽象动作无具体内容）", no_skill_words)

	# ===== F 入口与防劫持 =====
	var hk := _read_file(HOTKEYS_PATH)
	_assert("F1: F9 全局入口已挂 GlobalHotkeys", hk.contains("KEY_F9") and hk.contains("skill_control_demo_platform.tscn"))
	_assert("F2: F9 在 full_ai_platform 内不劫持（观测面板防冲突）", hk.contains("FullAIPlatform") and hk.contains("SkillControlDemoPlatform"))
	_assert("F3: 场景根节点名=SkillControlDemoPlatform（防重复切依赖）", hk.contains("SkillControlDemoPlatform") and platform.name == "SkillControlDemoPlatform")

	platform.queue_free()
	print("\n---------- 结果：%d 过 / %d 败 ----------" % [_pass, _fail])
	print("========== 工单37 自测结束 ==========\n")
	quit(1 if _fail > 0 else 0)


## ===== 推演助手：事件 + 时间推进循环 =====
func _step(runner, kind: String, pos := Vector3.ZERO, dir := Vector3.ZERO) -> void:
	runner.advance(kind, pos, dir)


## 修1 触发口径起手：switch_to + 按 trigger 表发触发键（enter_only=仅进入就绪态）
func _trigger(runner, id: String, pos := Vector3.ZERO) -> void:
	runner.switch_to(id)
	var trig: String = runner.trigger_of(id)
	if trig != "enter_only":
		runner.advance(trig, pos)


func _spin(runner, seconds: float, max_loops: int = 40) -> void:
	var left := seconds
	var loops := 0
	while left > 0.0 and loops < max_loops:
		var dt := minf(0.25, left)
		runner.tick(dt)
		left -= dt
		loops += 1
		if runner.done:
			return


func _drive_auto(runner) -> void:
	_trigger(runner, "auto")
	_spin(runner, 1.4)


func _drive_aim(runner) -> void:
	_trigger(runner, "aim")
	_step(runner, "confirm", Vector3(400, 0, -200))
	_spin(runner, 3.0)


func _drive_point(runner) -> void:
	_trigger(runner, "point")
	_step(runner, "confirm", Vector3(-200, 0, 120))
	_spin(runner, 2.0)


func _drive_mark(runner) -> void:
	_trigger(runner, "mark")
	_step(runner, "confirm", Vector3(160, 0, 0))
	_spin(runner, 2.5)


func _drive_steer(runner) -> void:
	_trigger(runner, "steer", Vector3(0, 0, -300))
	_step(runner, "ad", Vector3.ZERO, Vector3(1, 0, 0))
	_spin(runner, 9.0)


func _drive_midfly(runner) -> void:
	_trigger(runner, "midfly", Vector3(0, 0, -300))
	_step(runner, "activate")
	_step(runner, "activate")
	_step(runner, "activate")
	_spin(runner, 9.0)


func _drive_toggle(runner) -> void:
	_trigger(runner, "toggle")
	_step(runner, "activate")


func _drive_key_jump(runner) -> void:
	_trigger(runner, "key_jump")
	_step(runner, "space")
	_spin(runner, 1.0)


func _drive_place(runner) -> void:
	_trigger(runner, "place")
	_step(runner, "shape")
	_step(runner, "confirm", Vector3(120, 0, 80))
	_spin(runner, 1.6)


func _drive_summon(runner) -> void:
	_trigger(runner, "summon")
	_step(runner, "confirm", Vector3(220, 0, 100))
	_spin(runner, 8.0)


func _drive_fp(runner) -> void:
	_trigger(runner, "fp")
	_step(runner, "confirm", Vector3.ZERO, Vector3(0, 0, -1))
	_spin(runner, 3.0)


func _drive_combo(runner) -> void:
	_trigger(runner, "combo")
	_spin(runner, 1.0)
	_step(runner, "t_key")
	_spin(runner, 1.4)


func _drive_multi_hit(runner) -> void:
	_trigger(runner, "multi_hit")
	_step(runner, "activate")
	_step(runner, "activate")
	_spin(runner, 1.2)


func _drive_drag(runner) -> void:
	_trigger(runner, "drag")	# enter_only：进入就绪态
	_step(runner, "press", Vector3(160, 0, 0))
	_step(runner, "confirm", Vector3(160, 0, 0))
	_spin(runner, 1.6)


func _drive_cancel_demo(runner) -> void:
	_trigger(runner, "cancel_demo")	# enter_only：进入瞄准前半
	_step(runner, "cancel")   # 右键=取消选中（回退消散→rewind 空档 0.6s）
	_spin(runner, 0.7)        # 等回退动画+空档走完→重选占位出现
	_step(runner, "confirm", Vector3(400, 0, -200))   # 重选确认→飞出
	_spin(runner, 3.0)


func _drive_migrate(runner) -> void:
	_trigger(runner, "migrate")
	_step(runner, "space")
	_step(runner, "move", Vector3.ZERO, Vector3(1, 0, 0))
	_step(runner, "activate")


func _drive_whiteball_green(runner) -> void:
	_trigger(runner, "whiteball_select")
	runner.mouse = Vector3(60, 0, -120)    # 悬停绿环对象
	runner.tick(0.05)
	_step(runner, "confirm")
	runner.mouse = Vector3(160, 0, 0)
	runner.tick(0.05)
	_step(runner, "confirm")
	_spin(runner, 3.0)


func _drive_whiteball_deliver(runner) -> void:
	_trigger(runner, "whiteball_select")
	runner.mouse = Vector3(-100, 0, -120)
	runner.tick(0.05)
	_step(runner, "confirm")            # 单选
	runner.mouse = Vector3(-160, 0, 0)  # 悬停队友（测试者）
	runner.tick(0.05)
	_step(runner, "confirm")            # 锁定队友
	_spin(runner, 3.0)                  # 飞→贴附 0.8s→消散


func _drive_whiteball_select(runner) -> void:
	_trigger(runner, "whiteball_select")
	runner.mouse = Vector3(-100, 0, -120)
	runner.tick(0.05)
	_step(runner, "confirm")            # 单选（悬停蓝环对象）
	runner.mouse = Vector3(160, 0, 0)
	runner.tick(0.05)
	_step(runner, "confirm")            # 锁定敌（红框悬停）
	_spin(runner, 2.0)                  # 占位飞向目标→命中


func _drive_shark_swim(runner) -> void:
	_trigger(runner, "shark_swim")
	runner.mouse = Vector3(160, 0, 0)
	_step(runner, "space")              # 下沉
	_step(runner, "space")              # 浮起翻转
	_spin(runner, 3.5)                  # 定向自游→触碰敌


func _drive_fastlane_d14(runner) -> void:
	_trigger(runner, "fastlane_d14")
	runner.mouse = Vector3(0, 0, 150)
	runner.tick(0.05)
	_step(runner, "tab")                # Tab 切形状（矩形→扇形）
	_step(runner, "tab")
	_step(runner, "tab")
	_step(runner, "tab")                # 切满一轮回矩形（环绕断言）
	_assert("C19a: Tab 四形轮转回矩形", int(runner.flags.get("shape_idx", 0)) == 0)
	_step(runner, "confirm", Vector3(0, 0, 150))   # 铺开（球员为锚）
	_spin(runner, 8.0)                  # 入区域增速→出区域→走完


func _drive_hold_aura(runner) -> void:
	_trigger(runner, "hold_aura")
	runner.advance("hold")
	runner.advance("hold")
	runner.advance("hold")
	_spin(runner, 7.0)


func _drive_firework_use(runner, platform) -> void:
	_trigger(runner, "firework_use")
	_step(runner, "shape")              # Q 变身形态B
	platform.buddy.hp = 100
	runner.mouse = Vector3(160, 0, 0)   # 形态B 朝敌推进
	_spin(runner, 6.0)


func _drive_fp_whiteball(runner, platform) -> void:
	_trigger(runner, "fp_whiteball")
	await process_frame                 # 等 FP 相机同步
	var ball0: Node3D = runner.flags.get("balls", [{}])[0].get("node")
	var aim0: Vector3 = ball0.position + Vector3(0, 26, 0)   # 实际判定点（root y=hover_y 悬浮口径）
	var eye: Vector3 = platform.camera.global_position
	var dir: Vector3 = (aim0 - eye).normalized()
	platform._fp_yaw = atan2(-dir.x, -dir.z)
	platform._fp_pitch = asin(clampf(dir.y, -1.0, 1.0))
	await process_frame
	runner.tick(0.05)
	_step(runner, "confirm")            # 准星单选蓝环对象
	var tgt_pos: Vector3 = platform.buddy.global_position + Vector3(0, 30, 0)
	var d2: Vector3 = (tgt_pos - platform.camera.global_position).normalized()
	platform._fp_yaw = atan2(-d2.x, -d2.z)
	platform._fp_pitch = asin(clampf(d2.y, -1.0, 1.0))
	await process_frame
	runner.tick(0.05)
	_step(runner, "confirm")            # 准星锁定敌
	_spin(runner, 2.5)


func _drive_guide_ball(runner) -> void:
	_trigger(runner, "guide_ball")
	runner.mouse = Vector3(0, 0, -200)
	for i in range(10):
		runner.advance("move", Vector3(0, 0, -200))   # W 朝鼠标
	runner.advance("ad", Vector3.ZERO, Vector3(1, 0, 0))   # A/D 偏转
	runner.advance("activate")          # 再按4=收回
	_spin(runner, 0.8)


func _assert(name: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("  ✅ " + name)
	else:
		_fail += 1
		print("  ❌ " + name)


func _read_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()
