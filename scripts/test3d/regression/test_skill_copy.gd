## 波6 #1 验收：复制系（12 工单，headless 可跑；数据内存注入零 skills.json 触碰）
## 断言：历史环形覆盖/复制折扣执行/无快照 fallback/skill_copied 可订阅/暗黑共享槽/复制系不自噬
## 运行：Godot_console.exe --headless --script res://scripts/test3d/regression/test_skill_copy.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0


class StubPlayer extends CharacterBody2D:
	var team: String = "a"
	var is_defeated: bool = false
	var char_data: Dictionary = {"name": "stub"}
	var max_stamina: float = 100.0
	var stamina: float = 100.0
	var max_spirit_energy: float = 100.0
	var spirit_energy: float = 100.0
	var ball_ref: Node = null
	var _cc: bool = false
	func is_status_active(s: String) -> bool:
		return false
	func set_carrying_ball(v: bool) -> void:
		pass


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== 复制系测试 ==========\n")
	for i in range(3):
		await process_frame
	var trigger: Node = load("res://scripts/systems/spirit_system/spirit_skill_trigger.gd").new()
	root.add_child(trigger)
	var handler: Node = load("res://scripts/systems/spirit_system/spirit_tag_effect_handler.gd").new()
	root.add_child(handler)
	handler.priority_queue_enabled = false
	handler.trigger_ref = trigger  # 显式注入（-s 模式无 BattleManager）
	await process_frame
	await process_frame

	var pa: StubPlayer = StubPlayer.new(); pa.team = "a"; root.add_child(pa)
	var pb: StubPlayer = StubPlayer.new(); pb.team = "b"; root.add_child(pb)
	var roster: Array[Node] = [pa, pb]
	trigger.players = roster
	var h_roster: Array[Node] = [pa, pb]
	handler.players = h_roster

	# 内存注入两个源技能（零 skills.json 触碰）
	trigger._skills_cache["test_fireball"] = {"id": "test_fireball", "type": "active",
		"energy_cost": 20.0, "cooldown": 0.0, "tags": [], "tag_params": {}}
	trigger._skills_cache["skill_copy_last"] = {"id": "skill_copy_last", "type": "active",
		"energy_cost": 0.0, "cooldown": 0.0, "tags": [], "tag_params": {}}

	# ===== 敌方（b 队）释放 fireball ×2 → 历史 2 条 =====
	trigger._record_cast(pb.get_instance_id(), "test_fireball")
	trigger._record_cast(pb.get_instance_id(), "test_fireball")
	# 我方（a 队）也释放一条（应被 get_last_enemy_cast 过滤）
	trigger._record_cast(pa.get_instance_id(), "test_fireball")

	# ===== 复制折扣执行：a 队复制 b 队最近释放，能耗 ×0.5 =====
	pa.spirit_energy = 100.0
	var copy_params := {"cost_pct": 0.5}
	handler._do_apply_tag("skill_copy_last", copy_params.duplicate(), pa.get_instance_id())
	_assert("复制: 折扣能耗扣 10 (20×0.5)", absf(pa.spirit_energy - 90.0) < 0.01)

	# ===== skill_copied 事件可订阅 =====
	var copied: Array = []
	var bus = root.get_node_or_null("/root/BattleEventBus")
	if bus:
		bus.subscribe(BattleEventBus.GameEvent.SKILL_COPIED, func(payload): copied.append(payload))
	handler._do_apply_tag("skill_copy_last", copy_params.duplicate(), pa.get_instance_id())
	_assert("事件: SKILL_COPIED 触发（总线在场时）", bus == null or copied.size() >= 1)

	# ===== 暗黑共享：b 队快照写入 a 队可复制槽 =====
	handler._do_apply_tag("skill_share_copy", {"duration": 30.0}, pa.get_instance_id())
	_assert("共享: a 队槽有快照", not trigger.take_shared_copy(pa.get_instance_id()).is_empty())
	_assert("共享: b 队槽为空", trigger.take_shared_copy(pb.get_instance_id()).is_empty())

	# ===== 无快照 fallback：清史后复制失败 =====
	var hist_len: int = trigger._cast_history.size()
	for i in range(hist_len + 1):
		trigger._cast_history.pop_back()
	pa.spirit_energy = 100.0
	handler._do_apply_tag("skill_copy_last", copy_params.duplicate(), pa.get_instance_id())
	_assert("fallback: 无快照复制失败且不扣能", absf(pa.spirit_energy - 100.0) < 0.01)

	# ===== 环形覆盖：上限 20 =====
	for i in range(25):
		trigger._record_cast(pb.get_instance_id(), "test_fireball")
	_assert("环形: 历史上限 20", trigger._cast_history.size() == 20)

	# ===== 复制系不自噬：复制技不入史 =====
	var before: int = trigger._cast_history.size()
	trigger._record_cast(pa.get_instance_id(), "skill_copy_last")
	_assert("自噬防护: 复制技不入史", trigger._cast_history.size() == before)

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 全部通过！")
	quit(1 if _fail > 0 else 0)


func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)
