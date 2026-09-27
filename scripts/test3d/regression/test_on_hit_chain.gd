## 命中传递管线端到端验收（2026-09-27 修复"印记挂自己"）：释放印记球技→随球暂存→球命中敌人→敌人身上印记
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_on_hit_chain.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0

func _initialize() -> void:
	_run()

func _run() -> void:
	print("\n========== 命中传递管线端到端（on-hit 随球标签）==========\n")
	for i in range(3):
		await process_frame
	var handler: Node = load("res://scripts/systems/spirit_system/spirit_tag_effect_handler.gd").new()
	root.add_child(handler)
	handler.priority_queue_enabled = false
	await process_frame
	var caster: CharacterBody2D = load("res://scripts/battle/player.gd").new()
	caster.team = "a"
	caster.spirit_energy = 100.0
	root.add_child(caster)
	var victim: CharacterBody2D = load("res://scripts/battle/player.gd").new()
	victim.team = "b"
	root.add_child(victim)
	await process_frame
	var roster: Array[Node] = [caster, victim]
	handler.players = roster
	var cid: int = caster.get_instance_id()

	# ===== ① 释放印记球技：随球暂存（施法者自己 NOT 挂印记）=====
	var r1: Dictionary = handler._do_apply_tag("player_mark_apply",
		{"mark_id": "frost", "max_stacks": 5, "duration": 6.0}, cid)
	await process_frame
	_assert("①: 释放→随球暂存(success+pending)", bool(r1.get("success", false)) and bool(r1.get("on_hit_pending", false)))
	_assert("①: 施法者自己 NOT 被挂印记（缺陷修复核心）", caster.get_mark_count("frost") == 0)

	# ===== ② 球命中敌人：以被命中者消费 → 敌人身上印记 +1 =====
	var consumed: int = handler.consume_hit_tags(cid, victim)
	await process_frame
	_assert("②: 命中消费=1 个标签", consumed == 1)
	_assert("②: 敌人身上印记 +1（get_mark_count=1）", victim.get_mark_count("frost") == 1)
	_assert("②: 施法者依旧无印记", caster.get_mark_count("frost") == 0)

	# ===== ③ 一球一清：二次消费=0（防重复）=====
	var consumed2: int = handler.consume_hit_tags(cid, victim)
	_assert("③: 消费后暂存清空（二次消费=0）", consumed2 == 0)

	# ===== ④ 多标签同球：印记+减速+眩晕 一次命中全部落到敌人 =====
	handler._do_apply_tag("player_mark_apply", {"mark_id": "fire", "max_stacks": 3, "duration": 8.0}, cid)
	handler._do_apply_tag("player_move_slow", {"multiplier": 1.3, "duration": 2.0}, cid)
	handler._do_apply_tag("player_stun", {"duration": 1.0}, cid)
	await process_frame
	var c3: int = handler.consume_hit_tags(cid, victim)
	await process_frame
	_assert("④: 多标签一次命中全消费(3)", c3 == 3)
	var speed_now: float = victim._get_effective_value("speed", victim.speed)
	var base_speed: float = victim.speed
	_assert("④: 敌人 印记+减速(speed %.0f→%.0f)+眩晕灯 全部生效" % [base_speed, speed_now],
		victim.get_mark_count("fire") == 1 and speed_now < base_speed and victim.is_status_active("stunned"))

	# ===== ⑤ 未命中清空：耗尽/回收路径不留残留 =====
	handler._do_apply_tag("player_mark_apply", {"mark_id": "frost", "max_stacks": 5, "duration": 6.0}, cid)
	handler.clear_hit_tags(cid)
	var c4: int = handler.consume_hit_tags(cid, victim)
	_assert("⑤: 清空后消费=0", c4 == 0)

	# ===== ⑥ 过期不传递（TTL 防陈旧）=====
	handler._do_apply_tag("player_mark_apply", {"mark_id": "frost", "max_stacks": 5, "duration": 6.0}, cid)
	handler._match_clock += 9.0   # 推过 8s TTL
	handler._do_apply_tag("player_root", {"duration": 2.0, "target": "enemies"}, cid)   # 新球技正常暂存
	var c5: int = handler.consume_hit_tags(cid, victim)
	await process_frame
	_assert("⑥: 过期标签不消费/新标签正常（TTL 生效）", c5 == 1 and victim.is_status_active("rooted") and victim.get_mark_count("frost") == 1)

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 命中传递链路打通！（印记技能：球命中敌人 → 敌人身上叠加印记）")
	quit(1 if _fail > 0 else 0)

func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)
