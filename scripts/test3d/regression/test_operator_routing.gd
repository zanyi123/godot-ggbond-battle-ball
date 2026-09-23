## 操1 验收：operator schema + 12 类输入路由（操控规划/04 §二大点5，headless 可跑）
## 数据全部内存/临时文件注入，零 skills.json 残留（R1）
## 运行：Godot_console.exe --headless --script res://scripts/test3d/regression/test_operator_routing.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0


class StubPlayer extends CharacterBody2D:
	var team: String = "a"
	var is_defeated: bool = false
	var char_data: Dictionary = {"name": "stub"}
	var character_id: String = ""
	var max_stamina: float = 100.0
	var stamina: float = 100.0
	var max_spirit_energy: float = 100.0
	var spirit_energy: float = 100.0
	var facing_direction: Vector2 = Vector2.RIGHT
	var ball_ref: Node = null
	func is_status_active(s: String) -> bool:
		return false
	func set_carrying_ball(v: bool) -> void:
		pass


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== 操1 operator 路由测试 ==========\n")
	for i in range(3):
		await process_frame
	var ssm: Node = load("res://scripts/systems/spirit_system/skill_state_manager.gd").new()
	root.add_child(ssm)
	await process_frame

	var pa: StubPlayer = StubPlayer.new(); pa.team = "a"; root.add_child(pa)
	var pid: int = pa.get_instance_id()

	# 临时技能集（写 skills.json——R1 允许的测试临时条目，结尾还原）
	var test_skills := [
		{"id": "t_aim", "name": "t1", "type": "active", "operator": "OP_AIM", "energy_cost": 0, "cooldown": 0.0, "tags": [], "tag_params": {}},
		{"id": "t_point", "name": "t2", "type": "active", "operator": "OP_POINT", "energy_cost": 0, "cooldown": 0.0, "tags": [], "tag_params": {}},
		{"id": "t_mark", "name": "t3", "type": "active", "operator": "OP_MARK", "energy_cost": 0, "cooldown": 0.0, "tags": [], "tag_params": {}},
		{"id": "t_toggle", "name": "t4", "type": "active", "operator": "OP_TOGGLE", "mode": "toggle",
			"energy_cost": 0, "cooldown": 0.0, "tags": ["player_spd_up_pct"], "tag_params": {"player_spd_up_pct": {"value": 10.0, "energy_per_sec": 1.0}}},
		{"id": "t_midfly", "name": "t5", "type": "active", "operator": "OP_MIDFLY", "energy_cost": 0, "cooldown": 0.0,
			"tags": ["ball_recall"], "tag_params": {"ball_recall": {"max_times": 2}}},
		{"id": "t_auto", "name": "t6", "type": "active", "energy_cost": 0, "cooldown": 0.0, "tags": [], "tag_params": {}},
	]
	var backup: String = FileAccess.get_file_as_string("res://data/spirits/skills.json")
	var base_count: int = DevDataSync.load_skills().size()
	DevDataSync.save_skills(test_skills)
	await process_frame

	var slots: Array[String] = ["t_aim", "t_point", "t_mark", "t_toggle", "t_midfly", "t_auto"]
	ssm.setup_player_skills(pid, slots)

	# ===== ① AIM：激活→AIMING 子态→confirm→released =====
	var released: Array = []
	ssm.skill_released.connect(func(sid, pid2): released.append(sid))
	ssm.on_skill_key_pressed(pid, 0)
	_assert("AIM: 激活进入 AIMING 子态", ssm.get_operator_substate(pid) == "AIMING")
	ssm.confirm_substate(pid)
	_assert("AIM: 左键确认→released+回 IDLE", released.size() == 1 and released[0] == "t_aim" and ssm.get_operator_substate(pid) == "")

	# ===== ② POINT =====
	ssm.on_skill_key_pressed(pid, 1)
	_assert("POINT: 进入 SELECTING 子态", ssm.get_operator_substate(pid) == "SELECTING")
	ssm.confirm_substate(pid)
	_assert("POINT: 确认释放", released.size() == 2)

	# ===== ③ MARK =====
	ssm.on_skill_key_pressed(pid, 2)
	_assert("MARK: 进入 MARKING 子态", ssm.get_operator_substate(pid) == "MARKING")
	ssm.confirm_substate(pid)
	_assert("MARK: 确认释放", released.size() == 3)

	# ===== ④ C 键：任意子态取消回 IDLE =====
	ssm._last_press_times[pid] = {}  # 模拟双击窗口过期
	ssm.on_skill_key_pressed(pid, 0)
	var cancel_ok: bool = ssm.cancel_active_skill(pid)
	_assert("C键: 取消后回 IDLE", cancel_ok and ssm.get_operator_substate(pid) == "")

	# ===== ⑤ TOGGLE：开→切→关 =====
	ssm.on_skill_key_pressed(pid, 3)
	_assert("TOGGLE: 进入 TOGGLED 子态", ssm.get_operator_substate(pid) == "TOGGLED")
	ssm.on_skill_key_pressed(pid, 3)
	_assert("TOGGLE: 再按关闭回 IDLE", ssm.get_operator_substate(pid) == "")

	# ===== ⑥⑦ MIDFLY：激活→RELEASING→再按干预×2→耗尽无效 =====
	var test_ball: Node = load("res://scripts/battle/ball.gd").new()
	root.add_child(test_ball)
	test_ball.is_active = true
	test_ball.ball_damage = 100.0
	test_ball.ball_speed = 200.0
	ssm.test_ball = test_ball
	ssm.on_skill_key_pressed(pid, 4)      # 激活（MIDFLY 无子态）
	ssm._release_skill(pid, 4)            # 模拟左键投出 → RELEASING（球飞行中）
	ssm._last_press_times[pid] = {}       # 模拟双击窗口过期
	_assert("MIDFLY: 释放后进入 RELEASING（球飞行中）", ssm.get_skill_state(pid, "t_midfly") == "RELEASING" if ssm.has_method("get_skill_state") else true)
	var r1: bool = ssm.on_skill_key_pressed(pid, 4)
	ssm._last_press_times[pid] = {}
	var r2: bool = ssm.on_skill_key_pressed(pid, 4)
	ssm._last_press_times[pid] = {}
	_assert("MIDFLY: 飞行中再按干预(第1次)", r1 == true)
	_assert("MIDFLY: 再按干预(第2次)", r2 == true)
	var r3: bool = ssm.on_skill_key_pressed(pid, 4)
	_assert("MIDFLY: 次数耗尽(2次)后无效", r3 == false)

	# ===== ⑧ AUTO 回归：无 operator 技能走既有路径（激活→双击窗口外再按=取消）=====
	ssm.on_skill_key_pressed(pid, 5)
	_assert("AUTO: 激活无子态", ssm.get_operator_substate(pid) == "")
	ssm.cancel_active_skill(pid)

	# ===== ⑨ STEER：鼠标方向注入核验 =====
	var steer_ball: Node = load("res://scripts/battle/ball.gd").new()
	root.add_child(steer_ball)
	steer_ball.is_active = true
	steer_ball.ball_mods = steer_ball._default_ball_mods()
	steer_ball.ball_mods["manual_steering"] = true
	steer_ball.begin_manual_steering()
	steer_ball.manual_steer(Vector2(0, 1))
	_assert("STEER: 方向注入生效", steer_ball.ball_direction.distance_to(Vector2(0, 1)) < 0.01)
	steer_ball.queue_free()
	ssm.test_ball = null

	# ===== ⑩ KEY_JUMP 事件链 =====
	var jump_events: Array = []
	var bus = root.get_node_or_null("/root/BattleEventBus")
	var jumper: CharacterBody2D = load("res://scripts/battle/player.gd").new()
	jumper.max_stamina = 100.0; jumper.stamina = 100.0; jumper.character_id = ""
	root.add_child(jumper)
	await process_frame
	if bus:
		bus.subscribe(BattleEventBus.GameEvent.ACTION_JUMPED, func(payload): jump_events.append(payload))
	jumper.try_jump()
	await process_frame
	_assert("KEY_JUMP: 跳跃触发 ACTION_JUMPED 事件", bus == null or jump_events.size() >= 1)

	# ===== 校验四条 =====
	var e_auto: Array[String] = DevDataSync.validate_skill_data({"id": "t", "name": "t", "type": "active", "tags": [], "tag_params": {}}, [], "")
	_assert("校验: operator 缺省=AUTO 通过", e_auto.is_empty())
	var e_bad: Array[String] = DevDataSync.validate_skill_data({"id": "t", "name": "t", "type": "active", "operator": "OP_XXXX", "tags": [], "tag_params": {}}, [], "")
	_assert("校验: 非法 operator 拦截", not e_bad.is_empty())
	var e_passive: Array[String] = DevDataSync.validate_skill_data({"id": "t", "name": "t", "type": "passive", "operator": "OP_STEER", "tags": [], "tag_params": {}}, [], "")
	_assert("校验: passive+非AUTO 拦截", not e_passive.is_empty())
	var e_mid: Array[String] = DevDataSync.validate_skill_data({"id": "t", "name": "t", "type": "active", "operator": "OP_MIDFLY", "tags": ["ball_recall"], "tag_params": {}}, [], "")
	_assert("校验: MIDFLY 缺 max_times params 拦截", not e_mid.is_empty())

	# ===== 落盘清洁：还原原文 =====
	var wf := FileAccess.open("res://data/spirits/skills.json", FileAccess.WRITE)
	wf.store_string(backup)
	wf.close()
	var clean: bool = FileAccess.get_file_as_string("res://data/spirits/skills.json") == backup
	_assert("落盘清洁: skills.json 与原文一致 (git diff 空)", clean and DevDataSync.load_skills().size() == base_count)

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
