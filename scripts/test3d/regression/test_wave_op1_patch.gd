## 操1 增补工单（操控规划/05）七项验收：按键迁移/再击/拖长击/右键取消/盾朝向/Tab分流/SUMMON（headless 可跑）
## 零 skills.json 触碰：临时技能走备份→写入→还原（R1 落盘清洁）
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_wave_op1_patch.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0
var _raw_backup: String = ""


class StubPlayer extends CharacterBody2D:
	var team: String = "a"
	var is_defeated: bool = false
	var is_player_controlled: bool = true
	var facing_direction: Vector2 = Vector2.RIGHT
	var ball_ref: Node = null
	var summons: Array = []
	var is_carrying_ball: bool = false
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
	var last_space_mode: String = ""
	func manual_steer(d: Vector2) -> void:
		last_dir = d
	func steer_space_action(mode: String) -> void:
		last_space_mode = mode


class StubArena extends Node:
	var battle_manager: Node = null


class StubBM extends Node:
	var team_a_players: Array = []
	var team_b_players: Array = []


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== 操1 增补工单（05）七项验收 ==========\n")
	for i in range(3):
		await process_frame

	var ssm_script: GDScript = load("res://scripts/systems/spirit_system/skill_state_manager.gd")
	var im_script: GDScript = load("res://scripts/battle/input_manager.gd")
	var shield_script: GDScript = load("res://scripts/battle/player_shield.gd")

	# ===== 临时技能数据（备份在先，R1）=====
	_raw_backup = FileAccess.get_file_as_string("res://data/spirits/skills.json")
	_assert("前置: skills.json 可读", _raw_backup.length() > 100)
	var skills: Array = DevDataSync.load_skills()
	var temp_ids: Array[String] = ["t_op1_steer", "t_op1_reclick", "t_op1_recdir", "t_op1_plain", "t_op1_drag", "t_op1_summon", "t_op1_toggle"]
	for sid in temp_ids:
		for s in skills:
			if str(s.get("id", "")) == sid:
				_fail += 1
				print("  ❌ 前置: 临时 id 撞现有技能 " + sid)
				quit(1)
				return
	skills.append({"id": "t_op1_steer", "name": "t", "type": "active", "element": "雷火", "tags": ["ball_manual_steering"], "tag_params": {"ball_manual_steering": {"energy_per_sec": 4.0, "max_duration": 6.0}}, "operator": "OP_STEER", "description": "t"})
	skills.append({"id": "t_op1_reclick", "name": "t", "type": "active", "element": "雷火", "tags": [], "tag_params": {}, "params": {"reclick": true}, "operator": "OP_POINT", "description": "t"})
	skills.append({"id": "t_op1_recdir", "name": "t", "type": "active", "element": "草木", "tags": [], "tag_params": {}, "params": {"reclick": "direction"}, "operator": "OP_POINT", "description": "t"})
	skills.append({"id": "t_op1_plain", "name": "t", "type": "active", "element": "雷火", "tags": [], "tag_params": {}, "operator": "OP_POINT", "description": "t"})
	skills.append({"id": "t_op1_drag", "name": "t", "type": "active", "element": "梦幻", "tags": [], "tag_params": {}, "params": {"drag": true, "snap_radius": 90.0}, "operator": "OP_MARK", "description": "t"})
	skills.append({"id": "t_op1_summon", "name": "t", "type": "active", "element": "冰雪", "tags": [], "tag_params": {}, "operator": "OP_SUMMON", "description": "t"})
	skills.append({"id": "t_op1_toggle", "name": "t", "type": "active", "element": "金刚", "tags": [], "tag_params": {}, "operator": "OP_TOGGLE", "mode": "toggle", "description": "t"})
	DevDataSync.save_skills(skills)
	await process_frame

	var ssm: Node = ssm_script.new()
	root.add_child(ssm)
	var pid: int = 12345

	# ===== 项1 按键迁移窗口 =====
	ssm.setup_player_skills(pid, ["t_op1_steer"] as Array[String])
	ssm._activate_skill(pid, 0)
	_assert("项1: STEER 激活（无子态，窗口按 operator 判）", str(ssm.get_operator_substate(pid)) == "" and ssm.get_active_operator(pid) == "OP_STEER")
	_assert("项1: STEER 激活期迁移窗口开启", bool(ssm.is_key_migration_active(pid)) == true)
	ssm.operator_system_enabled = false
	_assert("项1: 总开关关闭→迁移窗口关闭（全旁路）", bool(ssm.is_key_migration_active(pid)) == false)
	ssm.operator_system_enabled = true
	ssm.cancel_active_skill(pid)

	# ===== 项1 input_manager 侧：球手动态窗口 + 双源合成 =====
	var arena_stub: StubArena = StubArena.new()
	root.add_child(arena_stub)
	var bm_stub: StubBM = StubBM.new()
	var enemy: StubPlayer = StubPlayer.new()
	enemy.team = "b"
	enemy.position = Vector2(300, 0)
	arena_stub.add_child(enemy)   # 树内才有 global_position（吸附距离计算依赖）
	bm_stub.team_a_players = []
	bm_stub.team_b_players = [enemy]
	arena_stub.battle_manager = bm_stub
	arena_stub.add_child(bm_stub)
	var im: Node = im_script.new()
	arena_stub.add_child(im)
	var caster: StubPlayer = StubPlayer.new()
	caster.team = "a"
	arena_stub.add_child(caster)
	var ball: StubBall = StubBall.new()
	caster.ball_ref = ball
	im.set_controlled_player(caster)
	im.match_started = true
	ball._manual_active = true
	_assert("项1: 球手动态→input_manager 操控窗口开启", bool(im.is_skill_control_active()) == true)
	ball._manual_active = false
	_assert("项1: 球非手动态+无激活→窗口关闭", bool(im.is_skill_control_active()) == false)
	_assert("项1: 双源合成=朝向旋转增量（右×90°=下）", (im.compose_steer_direction(Vector2.RIGHT, PI / 2.0) - Vector2.DOWN).length() < 0.001)
	_assert("项1: 零增量合成=原朝向", im.compose_steer_direction(Vector2.RIGHT, 0.0) == Vector2.RIGHT)

	# ===== 项2 左键再击（两段式）=====
	ssm.setup_player_skills(pid, ["t_op1_reclick"] as Array[String])
	ssm._activate_skill(pid, 0)
	var act1: String = ssm.confirm_substate_at(pid, Vector2(100, 0))
	_assert("项2: 第一段左键=仅选中（不释放）", act1 == "selected" and not ssm.get_active_skill(pid).is_empty())
	var act2: String = ssm.confirm_substate_at(pid, Vector2(120, 0))
	_assert("项2: 第二段左键=真释放+回 IDLE", act2 == "released" and ssm.get_active_skill(pid).is_empty())
	# 三段式 direction：select→(鼠移)→confirm 定向（换 recdir 技能）
	ssm.setup_player_skills(pid, ["t_op1_recdir"] as Array[String])
	ssm._activate_skill(pid, 0)
	ssm.confirm_substate_at(pid, Vector2(100, 0))
	ssm.confirm_substate_at(pid, Vector2(200, 0))
	var dir_ok: bool = ssm.last_confirm_info.get("action", "") == "released" \
		and (ssm.last_confirm_info.get("selected", {}).get("direction", Vector2.ZERO) - Vector2.RIGHT).length() < 0.001
	_assert("项2: direction 型=选中点→末击点定向", dir_ok)

	# ===== 项2 对照：非 reclick 技能不受影响 =====
	ssm.setup_player_skills(pid, ["t_op1_plain"] as Array[String])
	ssm._activate_skill(pid, 0)
	_assert("项2: 非 reclick 单击即释放", ssm.confirm_substate_at(pid, Vector2.ZERO) == "released")

	# ===== 项4 右键取消选中（子态保留可重选）=====
	ssm.setup_player_skills(pid, ["t_op1_reclick"] as Array[String])
	ssm._activate_skill(pid, 0)
	ssm.confirm_substate_at(pid, Vector2(100, 0))   # stage→2 已选中
	_assert("项4: 有选中时右键清除=成功", bool(ssm.clear_substate_selection(pid)) == true)
	_assert("项4: 清除后子态保留且回到第一段", (not ssm.get_active_skill(pid).is_empty()) and ssm.confirm_substate_at(pid, Vector2(110, 0)) == "selected")
	_assert("项4: 无选中可清时右键=不消费", bool(ssm.clear_substate_selection(999)) == false)

	# ===== 项3 拖长击（路由在 im 自建状态机上激活）=====
	var issm: Node = im.skill_state_manager
	var cpid: int = caster.get_instance_id()
	issm.setup_player_skills(cpid, ["t_op1_drag"] as Array[String])
	issm._activate_skill(cpid, 0)
	_assert("项3: drag 技能激活期 is_drag_skill=真", bool(issm.is_drag_skill(cpid)) == true)
	# 大相机限定：FP 态左键不进入拖动
	im.fp_mode = true
	im._on_left_click_press()
	_assert("项3: FP 态左键不进入拖动（大相机限定）", bool(im._drag_state.active) == false)
	# 大相机：按下=选 a（b 由每帧吸附轮询产生，此处显式调一次检测断言）
	im.fp_mode = false
	im.mouse_world_pos = Vector2(290, 0)
	im._on_left_click_press()
	var cand = im._find_drag_candidate()
	_assert("项3: 大相机左键按下→拖动态+吸附检测到半径内敌方 b", bool(im._drag_state.active) == true and cand == enemy)
	# 松开无 b：取消选中不释放（先把鼠标拖出半径模拟脱离）
	im.mouse_world_pos = Vector2(1000, 1000)
	im._drag_state.b = im._find_drag_candidate()
	var released_flag: Array = []
	issm.skill_released.connect(func(_sid, _p): released_flag.append(1))
	if im._drag_state.b == null:
		im._on_left_click_release()
		_assert("项3: 松开无 b→取消选中且不释放", released_flag.is_empty() and not issm.get_active_skill(cpid).is_empty())
	else:
		_assert("项3: 松开无 b→取消选中且不释放（跳过：吸附半径内未能脱离）", false)
	# 重新按下拖到敌方松开：a 对 b 作用=释放
	im._on_left_click_press()
	im._drag_state.b = enemy
	im._on_left_click_release()
	_assert("项3: 松开有 b→作用结算（释放+drag 记录）", released_flag.size() == 1 and issm.last_confirm_info.get("drag", false) == true)

	# ===== 项7 SUMMON 基础版 =====
	ssm.setup_player_skills(pid, ["t_op1_summon"] as Array[String])
	ssm._activate_skill(pid, 0)
	_assert("项7: OP_SUMMON 激活进入 SUMMONING 子态", str(ssm.get_operator_substate(pid)) == "SUMMONING")
	var sum_act: String = ssm.confirm_substate_at(pid, Vector2(50, 50))
	_assert("项7: 左键地面=召唤指令（无召唤体告警不崩溃）", sum_act == "summoned" and ssm.last_confirm_info.get("action", "") == "summoned")

	# ===== 项6 Tab 分流（im 自建状态机）=====
	_assert("项6: 无激活时 Tab=切球员（不消费）", bool(im._tab_skill_state_switch()) == false)
	issm.setup_player_skills(cpid, ["t_op1_toggle"] as Array[String])
	issm._activate_skill(cpid, 0)
	_assert("项6: TOGGLE 激活进 TOGGLED 子态", str(issm.get_operator_substate(cpid)) == "TOGGLED")
	var toggle_released: Array = []
	issm.skill_released.connect(func(_sid, _p): toggle_released.append(1))
	_assert("项6: TOGGLED 期 Tab=切换/关闭（消费）", bool(im._tab_skill_state_switch()) == true)
	_assert("项6: Tab 关闭后技能释放", toggle_released.size() >= 1 and str(issm.get_operator_substate(cpid)) == "")

	# ===== 项5 盾朝向跟随 =====
	var shield: Node = shield_script.new()
	root.add_child(shield)
	var shield_caster: StubPlayer = StubPlayer.new()
	shield_caster.facing_direction = Vector2.RIGHT
	shield_caster.position = Vector2(0, 0)
	root.add_child(shield_caster)
	shield.setup_shield({"follow_mode": "follow"}, shield_caster)
	var rot_a: float = float(shield.rotation)
	shield_caster.facing_direction = Vector2.DOWN
	shield._follow_caster()
	var rot_b: float = float(shield.rotation)
	_assert("项5: 盾体朝向跟随释放者面向（右0°→下90°）", absf(angle_difference(rot_a, 0.0)) < 0.01 and absf(angle_difference(rot_b, PI / 2.0)) < 0.01)

	# ===== 项1 空格迁移双语义（主人裁决 2026-09-24：贴地=跳跃/飞行=上升增量；W/S 维持现状不加速减速）=====
	var ball_real: Node = load("res://scripts/battle/ball.gd").new()
	root.add_child(ball_real)
	ball_real._manual_active = true
	ball_real.steer_space_action("jump")
	_assert("空格迁移: 贴地跳跃=垂直冲量+滞空", absf(float(ball_real.ball_z_vel) - float(ball_real.STEER_JUMP_VEL)) < 0.01 and bool(ball_real._steer_jump_airborne) == true)
	ball_real.steer_space_action("rise")
	ball_real.steer_space_action("rise")
	_assert("空格迁移: 飞行上升增量=每击+step", absf(float(ball_real.ball_z) - 2.0 * float(ball_real.STEER_RISE_STEP)) < 0.01)
	ball_real.ball_z = float(ball_real.STEER_RISE_MAX) + 500.0
	ball_real.steer_space_action("rise")
	_assert("空格迁移: 上升有上限 clamp", absf(float(ball_real.ball_z) - float(ball_real.STEER_RISE_MAX)) < 0.01)
	# 语义解析：缺省 jump / params.space_mode="rise"
	ssm.setup_player_skills(pid, ["t_op1_steer"] as Array[String])
	ssm._activate_skill(pid, 0)
	_assert("空格迁移: 缺省语义=jump（贴地类）", str(ssm.get_space_mode(pid)) == "jump")
	var skills2: Array = DevDataSync.load_skills()
	skills2.append({"id": "t_op1_fly", "name": "t", "type": "active", "element": "雷火", "tags": ["ball_manual_steering"], "tag_params": {}, "params": {"space_mode": "rise"}, "operator": "OP_STEER", "description": "t"})
	DevDataSync.save_skills(skills2)
	await process_frame
	ssm.setup_player_skills(pid, ["t_op1_fly"] as Array[String])
	ssm._activate_skill(pid, 0)
	_assert("空格迁移: params.space_mode=rise→飞行语义", str(ssm.get_space_mode(pid)) == "rise")
	ssm.cancel_active_skill(pid)
	# 路由：im 迁移窗口+球手动态 → steer_space_action 收到语义（缺省 jump）
	ball.last_space_mode = ""
	ball._manual_active = true
	issm.setup_player_skills(cpid, ["t_op1_steer"] as Array[String])
	issm._activate_skill(cpid, 0)
	im._route_space_to_skill()
	_assert("空格迁移: im 路由→球收到动作语义", ball.last_space_mode == "jump")
	# 拦截闸门：迁移期 is_skill_control_active=true（player 侧据此抑制跳跃；物理抑制由 sim 回归覆盖）
	_assert("空格迁移: STEER 激活期迁移窗口开启（player 跳跃闸门条件）", bool(im.is_skill_control_active()) == true)
	issm.cancel_active_skill(cpid)

	# ===== 落盘清洁 =====
	var wf := FileAccess.open("res://data/spirits/skills.json", FileAccess.WRITE)
	wf.store_string(_raw_backup)
	wf.close()
	_assert("落盘清洁: skills.json 与原文一致", FileAccess.get_file_as_string("res://data/spirits/skills.json") == _raw_backup)

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 全部通过！（skills.json 已还原）")
	quit(1 if _fail > 0 else 0)


func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)


func angle_difference(a: float, b: float) -> float:
	var d := fposmod(a - b + PI, TAU) - PI
	return absf(d)
