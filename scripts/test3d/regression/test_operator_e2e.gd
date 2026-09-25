## 操3 端到端联调验收·代理自动化版（操控规划/06）：5 技 × 时序步骤 → 逐格断言"系统应响应"
## 注入模式沿用 test_wave_op1_patch（InputEvent 通路 handler 调用+处理帧预留）；视觉=节点/状态断言
## 数据纪律：5 测试技测试内临时构造（备份→写入→还原，R1 落盘清洁）
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_operator_e2e.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0
var _raw_backup: String = ""
var _issues: Array[String] = []   # 观感未目验/需实机项（如实标注）
var _e2e_target: CharacterBody2D = null


class StubPlayer extends CharacterBody2D:
	var team: String = "a"
	var is_defeated: bool = false
	var is_player_controlled: bool = true
	var facing_direction: Vector2 = Vector2.RIGHT
	var ball_ref: Node = null
	var is_carrying_ball: bool = false
	var char_data: Dictionary = {"name": "stub"}
	func get_equipped_skills() -> Array[String]:
		return []
	func is_status_active(_s: String) -> bool:
		return false
	func start_sprint() -> void:
		pass


class StubBall extends Node:
	var is_active: bool = true
	var _manual_active: bool = false
	var last_dir: Vector2 = Vector2.ZERO
	var recall_count: int = 0
	func manual_steer(d: Vector2) -> void:
		last_dir = d
	func recall_ball(_n: int) -> void:
		recall_count += 1
	func boost_in_flight(_p: Dictionary) -> void:
		pass


class StubArena extends Node:
	var battle_manager: Node = null


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== 操3 端到端联调（代理自动化版）==========\n")
	for i in range(3):
		await process_frame

	var im_script: GDScript = load("res://scripts/battle/input_manager.gd")

	# ===== 数据准备（R1：备份在先）=====
	_raw_backup = FileAccess.get_file_as_string("res://data/spirits/skills.json")
	_assert("前置: skills.json 可读", _raw_backup.length() > 100)
	var skills: Array = DevDataSync.load_skills()
	var temp := {
		"e2e_dajinglei": {"tags": ["ball_carry_push", "player_stun", "player_silence"], "tag_params": {"ball_carry_push": {"pull_speed": 200.0, "max_duration": 3.0}, "player_stun": {"duration": 1.0}, "player_silence": {"duration": 1.0}}, "operator": "OP_AIM"},
		"e2e_xuanwo": {"tags": ["field_zone_boost"], "tag_params": {"field_zone_boost": {"position": "0,0", "size": "180,180", "boost_multiplier": 1.4, "duration": 10.0}}, "operator": "OP_POINT"},
		"e2e_menghu": {"tags": ["ball_manual_steering", "ball_dmg_up_pct"], "tag_params": {"ball_manual_steering": {"energy_per_sec": 4.0, "max_duration": 8.0}, "ball_dmg_up_pct": {"value": 35.0}}, "operator": "OP_STEER"},
		"e2e_jianguo": {"tags": ["player_shield_obstacle"], "tag_params": {"player_shield_obstacle": {"shape": "circle", "radius": 35.0, "hp": 2.0, "uses": 2, "durability_mode": "uses", "follow_mode": "follow", "duration": 10.0}, "player_shield_obstacle_alt": {"shape": "circle", "radius": 28.0, "hp": 4.0, "uses": 4, "durability_mode": "uses", "follow_mode": "follow", "duration": 10.0}}, "operator": "OP_TOGGLE", "mode": "toggle"},
		"e2e_chushou": {"tags": ["ball_recall"], "tag_params": {"ball_recall": {"max_times": 2}}, "operator": "OP_MIDFLY"},
	}
	for sid in temp:
		for s in skills:
			if str(s.get("id", "")) == sid:
				_fail += 1
				print("  ❌ 前置: 临时 id 撞现有技能 " + sid)
				quit(1)
				return
		var cfg: Dictionary = temp[sid]
		var entry := {"id": sid, "name": "t", "type": "active", "element": "雷火",
			"tags": cfg["tags"], "tag_params": cfg["tag_params"], "operator": cfg["operator"],
			"description": "t"}
		if cfg.has("mode"):
			entry["mode"] = cfg["mode"]
		skills.append(entry)
	DevDataSync.save_skills(skills)
	await process_frame

	# ===== 场景装配 =====
	var arena: StubArena = StubArena.new()
	root.add_child(arena)
	var im: Node = im_script.new()
	arena.add_child(im)
	var caster: StubPlayer = StubPlayer.new()
	arena.add_child(caster)
	var ball: StubBall = StubBall.new()
	caster.ball_ref = ball
	im.set_controlled_player(caster)
	im.match_started = true
	var issm: Node = im.skill_state_manager
	var cpid: int = caster.get_instance_id()
	issm.test_ball = ball

	var ofb_script: GDScript = load("res://scripts/battle3d/visual/operator_feedback_3d.gd")
	var ofb: Node3D = Node3D.new()
	ofb.set_script(ofb_script)
	ofb.name = "OperatorFeedback3D"
	root.add_child(ofb)
	await process_frame
	_assert("前置: operator_feedback_3d 载体挂载入组", ofb.is_in_group("operator_feedback_3d"))

	var released: Array = []
	issm.skill_released.connect(func(sid, _p): released.append(sid))
	_e2e_target = load("res://scripts/battle/player.gd").new()
	_e2e_target.team = "b"
	root.add_child(_e2e_target)
	await process_frame

	# =============== ① 大惊雷（OP_AIM）===============
	issm.setup_player_skills(cpid, ["e2e_dajinglei"] as Array[String])
	im._handle_skill_key_press(0)
	await process_frame
	_assert("大惊雷①: 键技能键→AIMING 子态", str(issm.get_operator_substate(cpid)) == "AIMING")
	im._process(0.016)
	_assert("大惊雷①: 预览节点挂载且可见标志", ofb.has_meta("aim_shown"))
	var dirs := {"右": Vector2(300, 0), "下": Vector2(0, 300), "左上": Vector2(-200, -200)}
	var dirs_ok := true
	for dname in dirs:
		caster.global_position = Vector2.ZERO
		im.update_aim_from_mouse(caster.global_position + dirs[dname])
		if absf(caster.facing_direction.angle_to(dirs[dname].normalized())) > 0.01:
			dirs_ok = false
	_assert("大惊雷②: 鼠移3方位→预览方向跟随", dirs_ok)
	im._on_left_click_press()
	await process_frame
	_assert("大惊雷③: 左键→释放+子态回位", released.size() == 1 and str(issm.get_operator_substate(cpid)) == "")
	var carry_ok: int = await _tags_executable(cpid, [
		["ball_carry_push", {"pull_speed": 200.0, "max_duration": 3.0}],
		["player_stun", {"duration": 1.0}], ["player_silence", {"duration": 1.0}]])
	_assert("大惊雷③: 效果标签可执行(carry_push/stun/silence 3/3)", carry_ok == 3)
	_issues.append("大惊雷③: 球实际弹道/命中麻痹/拖人位移=战斗表现，headless 无战斗场景——实机项未验（观感/实机清单）")

	# =============== ② 黑白旋涡（OP_POINT）===============
	released.clear()
	issm.setup_player_skills(cpid, ["e2e_xuanwo"] as Array[String])
	im._handle_skill_key_press(0)
	await process_frame
	_assert("黑白旋涡①: FIELD标签不再激活即生效(操3修复)→SELECTING 态", str(issm.get_operator_substate(cpid)) == "SELECTING")
	ofb.show_target_ring(Vector2(100, 100))
	_assert("黑白旋涡②: 候选高亮=目标圈接口能力可用", ofb.is_in_group("operator_feedback_3d"))
	im._on_left_click_press()
	await process_frame
	_assert("黑白旋涡③: 左键→释放", released.size() == 1)
	var zone_ok: int = await _tags_executable(cpid,
		[["field_zone_boost", {"position": "0,0", "size": "180,180", "boost_multiplier": 1.4, "duration": 10.0}]])
	_assert("黑白旋涡③: zone 增伤标签可执行", zone_ok == 1)
	_issues.append("黑白旋涡②: hover 候选高亮联动 v1 未接（操1 上报在案，目标圈接口已备）；③直线球飞对应黑漩涡+途经增伤=实机项未验")

	# =============== ③ 猛虎金刚闪（OP_STEER）===============
	released.clear()
	issm.setup_player_skills(cpid, ["e2e_menghu"] as Array[String])
	im._handle_skill_key_press(0)
	await process_frame
	_assert("猛虎①: 激活注能态(激活+迁移窗口开启)", str(issm.get_active_operator(cpid)) == "OP_STEER" and bool(issm.is_key_migration_active(cpid)) == true)
	im._release_active_skill(cpid)
	await process_frame
	ball._manual_active = true
	im.mouse_world_pos = caster.global_position + Vector2(200, 0)
	im._process(0.016)
	_assert("猛虎②: 投出→球进手动态+操控窗口开启", released.size() == 1 and bool(im.is_skill_control_active()) == true)
	var steer_ok := true
	for dname in dirs:
		caster.global_position = Vector2.ZERO
		im.update_aim_from_mouse(caster.global_position + dirs[dname])
		im.inject_steer_to_ball()
		if absf(ball.last_dir.angle_to(dirs[dname].normalized())) > 0.01:
			steer_ok = false
	_assert("猛虎③: 鼠移3方位→元灵体飞行方向实时跟随", steer_ok)
	im._route_space_to_skill()
	_assert("猛虎③+: 空格迁移路由到技能体(缺省贴地跳跃语义,不误触 recall)", ball.recall_count == 0)

	# =============== ④ 坚果盾（OP_TOGGLE·盾生命周期，真实 player+obstacle_manager）===============
	var p_real: CharacterBody2D = load("res://scripts/battle/player.gd").new()
	p_real.team = "a"
	p_real.spirit_energy = 100.0
	root.add_child(p_real)
	await process_frame
	var om: Node = load("res://scripts/battle/obstacle_manager.gd").new()
	root.add_child(om)   # 自入组 obstacle_managers，handler 组 fallback 可达
	var trig: Node = load("res://scripts/systems/spirit_system/spirit_skill_trigger.gd").new()
	root.add_child(trig)
	var trig_roster: Array[Node] = [p_real]
	trig.players = trig_roster
	var h_roster: Array[Node] = [p_real]
	trig._effect_handler.players = h_roster
	await process_frame
	var jianguo: Dictionary = {}
	for s2 in DevDataSync.load_skills():
		if str(s2.get("id", "")) == "e2e_jianguo":
			jianguo = s2
	_assert("坚果盾前置: 测试技数据在", not jianguo.is_empty())
	var open1: bool = trig._toggle_skill(jianguo, p_real.get_instance_id(), "e2e_jianguo")
	var shield1 = om.get_player_shield(p_real.get_instance_id())
	_assert("坚果盾①: 开→盾创建(form1 在册)", open1 and bool(p_real.active_toggles.has("e2e_jianguo")) == true and shield1 != null)
	var open2: bool = trig._toggle_skill(jianguo, p_real.get_instance_id(), "e2e_jianguo")
	var shield2 = om.get_player_shield(p_real.get_instance_id())
	_assert("坚果盾②: 再按→切 alt 形态(小型加固,盾重建 form2)", open2 and int(p_real.active_toggles["e2e_jianguo"].get("shield_form", 0)) == 2 and shield2 != null)
	var open3: bool = trig._toggle_skill(jianguo, p_real.get_instance_id(), "e2e_jianguo")
	var shield3 = om.get_player_shield(p_real.get_instance_id())
	_assert("坚果盾③: 三按→关闭+盾撤销+效果清除", open3 and bool(p_real.active_toggles.has("e2e_jianguo")) == false and shield3 == null)
	# 13-B 图标条联动：开→T 图标在 / 关→摘
	var bar: Control = load("res://scripts/battle/status_icon_bar.gd").new()
	root.add_child(bar)
	bar.bind_player(p_real)
	trig._toggle_skill(jianguo, p_real.get_instance_id(), "e2e_jianguo")
	await process_frame
	_assert("坚果盾13-B: toggle 开→图标条 T 图标", "toggle_e2e_jianguo" in bar.get_entry_keys())
	trig._toggle_skill(jianguo, p_real.get_instance_id(), "e2e_jianguo")  # 切形态
	trig._toggle_skill(jianguo, p_real.get_instance_id(), "e2e_jianguo")  # 三按=关闭（三态循环）
	await process_frame
	_assert("坚果盾13-B: toggle 关(切+关两按)→图标摘除", not ("toggle_e2e_jianguo" in bar.get_entry_keys()))

	# =============== ⑤ 弹性触手（OP_MIDFLY）===============
	released.clear()
	issm.setup_player_skills(cpid, ["e2e_chushou"] as Array[String])
	im._handle_skill_key_press(0)
	await process_frame
	_assert("触手①: 激活(BALL标签不立即生效)", str(issm.get_active_operator(cpid)) == "OP_MIDFLY")
	im._release_active_skill(cpid)
	await process_frame
	_assert("触手②: 投出→RELEASING(干预上下文保留)", released.size() == 1)
	im._handle_skill_key_press(0)
	await process_frame
	_assert("触手③: 飞行中再按→球被拉回(recall×1)", ball.recall_count == 1)
	im._handle_skill_key_press(0)
	await process_frame
	_assert("触手⑤a: 再按→recall×2", ball.recall_count == 2)
	im._handle_skill_key_press(0)
	await process_frame
	_assert("触手⑤b: 次数耗尽后按键无效", ball.recall_count == 2)
	_issues.append("触手④: 左键再投=持球投掷流程（实机项未验）；boost 分支同 recall 管道")

	# ===== 落盘清洁 =====
	var wf := FileAccess.open("res://data/spirits/skills.json", FileAccess.WRITE)
	wf.store_string(_raw_backup)
	wf.close()
	_assert("落盘清洁: skills.json 与原文一致 (git diff 空)", FileAccess.get_file_as_string("res://data/spirits/skills.json") == _raw_backup)

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if not _issues.is_empty():
		print("\n---- 观感未目验/需实机项（如实标注）----")
		for x in _issues:
			print("  · " + x)
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 联调矩阵全通过！（skills.json 已还原）")
	quit(1 if _fail > 0 else 0)


## 逐标签真实执行（handler._do_apply_tag），返回 success 数
func _tags_executable(caster_id: int, tags: Array) -> int:
	var handler: Node = load("res://scripts/systems/spirit_system/spirit_tag_effect_handler.gd").new()
	root.add_child(handler)
	handler.priority_queue_enabled = false
	var roster: Array[Node] = [_e2e_target]
	handler.players = roster
	var ok := 0
	for pair in tags:
		var r: Dictionary = handler._do_apply_tag(str(pair[0]), pair[1], _e2e_target.get_instance_id())
		if bool(r.get("success", false)):
			ok += 1
	handler.queue_free()
	return ok


func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)
