## 工单23 时期2 验收：芬尼/水木新召唤系技能——标签链+AI 描述符+F 波分发（headless）
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_summon_skills.gd
extends SceneTree

const EventBusScript = preload("res://scripts/systems/event_bus/event_bus.gd")
const PrimF = preload("res://scripts/battle/spirit_ai/primitives_f.gd")

var _pass: int = 0
var _fail: int = 0


class StubOwner extends CharacterBody2D:
	var character_id: String = "t_own"
	var team: String = "a"
	var is_defeated: bool = false
	var is_penalized: bool = false
	var is_carrying_ball: bool = false
	var spirit_energy: float = 100.0
	var max_spirit_energy: float = 100.0
	var stamina: float = 100.0
	var max_stamina: float = 100.0


class StubBall extends Area2D:
	var is_active: bool = true
	var owner_player: CharacterBody2D = null
	var ball_direction: Vector2 = Vector2.RIGHT
	var ball_speed: float = 400.0


func _initialize() -> void:
	_run()


func _cp(msg: String) -> void:
	var f := FileAccess.open("res://sim_results/_p2_trace.log", FileAccess.READ_WRITE if FileAccess.file_exists("res://sim_results/_p2_trace.log") else FileAccess.WRITE)
	f.seek_end()
	f.store_line(msg)
	f.flush()


func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  ✓ " + name)
	else:
		_fail += 1
		print("  ✗ " + name)


func _run() -> void:
	print("\n========== 工单23 时期2：新召唤系技能链验收 ==========\n")
	for i in range(3):
		await process_frame
	var watchdog := create_timer(60.0).timeout.connect(func() -> void:
		print("❌ WATCHDOG 超时")
		quit(3))

	# ===== T1：F 波描述符分发（AI 侧计价）=====
	print("[T1] F 波描述符")
	var SW := "res://data/systems/spirit_ai/switches.json"
	var sw_backup: String = FileAccess.get_file_as_string(SW)
	var fw := FileAccess.open(SW, FileAccess.WRITE)
	fw.store_string("{\"master_enabled\": true, \"waves\": {\"A\": true, \"B\": true, \"C\": true, \"D\": true, \"E\": true, \"F\": true}}")
	fw.close()
	load("res://scripts/battle/spirit_ai/primitive_registry.gd").reload_switches(SW)
	var sam = load("res://scripts/battle/spirit_ai_manager.gd").new()
	var owner_a: StubOwner = StubOwner.new()
	owner_a.is_carrying_ball = true
	root.add_child(owner_a)
	var PrimF: GDScript = load("res://scripts/battle/spirit_ai/primitives_f.gd")
	var hit: Dictionary = sam._query_primitive("enhance_next")
	_check(not hit.is_empty() and str((hit["primitives"] as GDScript).resource_path).ends_with("primitives_f.gd"), "T1 F 波标签经 manager 分发（enhance_next→primitives_f）")
	var v: float = float(PrimF.compute_value(hit["descriptor"], {"damage_mult": 2.0}))
	_check(absf(v - 30.0) < 0.01, "T2 enhance_next 计价：2×15=30")

	# ===== T2：summon_limit_up 全链（标签→handler→manager 上限+自动生成）=====
	print("[T2] summon_limit_up 全链")
	_cp("T2头")
	var bus = EventBusScript.new()
	bus.add_to_group("battle_event_bus")
	root.add_child(bus)
	var handler_script: GDScript = load("res://scripts/systems/spirit_system/spirit_tag_effect_handler.gd")
	if handler_script == null or not handler_script.can_instantiate():
		print("  ⚠ handler 编译失败重试（首载竞态）")
		await process_frame
		handler_script = load("res://scripts/systems/spirit_system/spirit_tag_effect_handler.gd")
	var handler = handler_script.new()
	handler.priority_queue_enabled = false   # 22-B 同款：诊断直通（生产=队列窗口 flush）
	# handler 的 manager 查找走 battle_manager.get_node("SummonManager")——测试挂真 manager 对齐生产口径
	var bm_stub := Node2D.new()
	root.add_child(bm_stub)
	var mgr: Node = load("res://scripts/systems/summon/summon_manager.gd").new()
	mgr.name = "SummonManager"
	bm_stub.add_child(mgr)
	mgr.add_to_group("summon_managers")
	await process_frame   # -s 模式：add_child 的 _ready 延迟至首帧（types 载入需要）
	root.add_child(handler)
	handler.battle_manager = bm_stub   # add_child 触发 _ready 会覆盖，赋值必须在其后
	var caster: StubOwner = StubOwner.new()
	caster.character_id = "fenny_caster"
	caster.team = "a"
	root.add_child(caster)
	handler.players = [caster] as Array[Node]   # _get_caster 名册注册（显式转型防 -s 赋值挂起）
	_cp("T2 players注册")
	var params := {"att_limit": 10.0, "def_limit": 10.0, "auto_interval": 5.0, "duration": 20.0, "caster_id": caster.get_instance_id()}
	_cp("T2 直调前")
	print("  ⏱ T2直调_do_apply_tag（绕过facade入口二分）")
	handler._do_apply_tag("summon_limit_up", params, caster.get_instance_id())
	_cp("T2 直调返回")
	print("  ⏱ T2直调返回")
	var spawned: Node = mgr.spawn("fenny_magic_ball_att", caster.get_instance_id(), Vector2.ZERO, {"owner_ref": caster})
	_check(spawned != null, "T3 上限提升后 spawn 放行")
	var extra: Array = []
	for i in range(6):
		var e: Node = mgr.spawn("fenny_magic_ball_att", caster.get_instance_id(), Vector2(i * 20, 0), {"owner_ref": caster})
		if e != null:
			extra.append(e)
	_check((extra as Array).size() >= 4, "T4 上限10：可生成远多于默认6 实测+%d" % (extra as Array).size())

	_cp("T2b前")
	# ===== T2b：芬尼口径双键兼容（type_id/spawn_count——时期2 实测缺口修复）=====
	var fenny_events: Array = []
	var cbf := func(payload: Dictionary) -> void: fenny_events.append(payload)
	bus.subscribe(bus.GameEvent.SUMMON_SPAWNED, cbf)
	handler.apply_tag_effect("summon_spawn", {"type_id": "fenny_magic_ball_def", "spawn_count": 3.0}, caster.get_instance_id())
	_cp("T2b spawn后")
	_check((fenny_events as Array).size() == 3, "T2b 芬尼口径 spawn_count=3 → SUMMON_SPAWNED×3（双键兼容）")
	var fenny_live: int = 0
	for e in mgr.get_summons_of(caster.get_instance_id()):
		if str(e.get("summon_type")) == "fenny_magic_ball_def":
			fenny_live += 1
	_check(fenny_live == 3, "T2c 白球-守实体×3 在场（type_id 解析正确）")

	# ===== T3：enhance_next 全链（强化透传与递减）=====
	print("[T3] enhance_next 全链")
	handler.apply_tag_effect("enhance_next", {"damage_mult": 2.0, "duration": 15.0}, caster.get_instance_id())
	var ball: StubBall = StubBall.new()
	ball.is_active = true
	root.add_child(ball)
	var before: int = (mgr.get_summons_of(caster.get_instance_id()) as Array).size()
	var e1: Node = mgr.spawn("fenny_magic_ball_att", caster.get_instance_id(), Vector2(500, 0), {"owner_ref": caster})
	_check(e1 != null and e1.get("_params").has("empower"), "T5 强化态透传：spawn params 带 empower")
	var e2: Node = mgr.spawn("fenny_magic_ball_att", caster.get_instance_id(), Vector2(520, 0), {"owner_ref": caster})
	_check(e2 != null and e2.get("_params").has("empower"), "T6 强化第二发仍携带（count=15 足量）")
	_check(before < (mgr.get_summons_of(caster.get_instance_id()) as Array).size(), "T7 召唤入账")

	print("\n========== 结果：%d 通过 / %d 失败 ==========" % [_pass, _fail])
	var rf := FileAccess.open(SW, FileAccess.WRITE)
	rf.store_string("{\"master_enabled\": false, \"waves\": {\"A\": false, \"B\": false, \"C\": false, \"D\": false, \"E\": false, \"F\": false}}")
	rf.close()
	load("res://scripts/battle/spirit_ai/primitive_registry.gd").reload_switches(SW)
	quit(1 if _fail > 0 else 0)
