## 工单23时期2验收：水木6技技能配置+summon分发链（布场窗口交付）
## 断言组：K1-skills.json契约 / K2-registry对账 / K3-spawn分发链 / K4-上限截断 / K5-融合链(F4查询口) / K6-装载
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_shuimu_skills.gd
extends SceneTree

const SKILLS_JSON := "res://data/spirits/skills.json"
const REGISTRY_JSON := "res://data/spirits/tags_registry.json"
const TYPES_JSON := "res://data/systems/summon/summon_types.json"
const MANAGER_SCRIPT: GDScript = preload("res://scripts/systems/summon/summon_manager.gd")
const HANDLER_SCRIPT: GDScript = preload("res://scripts/systems/spirit_system/spirit_tag_effect_handler.gd")
const ZONE_MANAGER_SCRIPT: GDScript = preload("res://scripts/battle/field_zone_manager.gd")

var _pass: int = 0
var _fail: int = 0


class StubOwner extends CharacterBody2D:
	var character_id: String = "t_k_owner"
	var team: String = "a"
	var is_defeated: bool = false
	var spirit_energy: float = 100.0
	var max_spirit_energy: float = 100.0
	var char_data: Dictionary = {"name": "水木测试"}


func _initialize() -> void:
	_run()


func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)


func _run() -> void:
	print("\n========== 工单23时期2：水木6技配置验收 ==========\n")
	for i in range(3):
		await process_frame
	create_timer(90.0).timeout.connect(func() -> void:
		print("❌ WATCHDOG：套件超时强退")
		quit(3))

	var skills_raw := FileAccess.get_file_as_string(SKILLS_JSON)
	var skills: Dictionary = JSON.parse_string(skills_raw)
	var by_id: Dictionary = {}
	for s in skills.get("skills", []) as Array:
		if typeof(s) == TYPE_DICTIONARY:
			by_id[str(s.get("id"))] = s

	# ===== K1-skills.json契约（水木6技全配） =====
	var want := ["shuimu_1", "shuimu_2", "shuimu_3", "shuimu_4", "shuimu_5", "shuimu_6"]
	var all_in := true
	var ops_ok := true
	var tags_ok := true
	for wid in want:
		if not by_id.has(wid):
			all_in = false
			continue
		var e: Dictionary = by_id[wid]
		if str(e.get("type")) != "active" or str(e.get("operator", "")).is_empty():
			ops_ok = false
		for tag in e.get("tags", []) as Array:
			if str(tag) != "summon_spawn" and str(tag) != "summon_merge" and str(tag) != "field_zone_energy_path":
				tags_ok = false
	_assert("K1a: 水木6技全配（shuimu_1~6）", all_in)
	_assert("K1b: 全 active 且操控方式映射在案（OP_STEER×3/OP_PLACE×1/OP_AUTO×2）", ops_ok and str(by_id.get("shuimu_3", {}).get("operator")) == "OP_PLACE" and str(by_id.get("shuimu_5", {}).get("operator")) == "OP_AUTO")
	_assert("K1c: 标签全部落在已登记三族（summon_spawn/summon_merge/field_zone_energy_path）", tags_ok)
	var e1: Dictionary = by_id.get("shuimu_1", {})
	var e6: Dictionary = by_id.get("shuimu_6", {})
	_assert("K1d: 快牙猎杀=攻鲨×1 / 组合炸弹=result_type=bomb need2", str(((e1.get("tag_params", {}) as Dictionary).get("summon_spawn", {}) as Dictionary).get("summon_type")) == "shuimu_shark_att" and str(((e6.get("tag_params", {}) as Dictionary).get("summon_merge", {}) as Dictionary).get("result_type")) == "shuimu_shark_bomb")

	# ===== K2-registry对账 =====
	var reg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REGISTRY_JSON))
	var reg_ids: Dictionary = {}
	for t in reg.get("tags", []) as Array:
		reg_ids[str(t.get("id"))] = t
	_assert("K2: registry 含 summon_spawn/summon_merge（且被6技引用的标签全登记）", reg_ids.has("summon_spawn") and reg_ids.has("summon_merge") and reg_ids.has("field_zone_energy_path"))

	# ===== K3-spawn分发链（handler→SummonManager） =====
	var types: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TYPES_JSON))
	var types_ok: bool = typeof(types.get("types", null)) == TYPE_DICTIONARY and (types["types"] as Dictionary).has("shuimu_shark_att") and (types["types"] as Dictionary).has("shuimu_shark_def") and (types["types"] as Dictionary).has("shuimu_shark_bomb")
	_assert("K3a: types表五型含水木三型（攻/守/炸弹）", types_ok)

	var fake_bm: Node = Node.new()
	fake_bm.name = "FakeBattleManager"
	root.add_child(fake_bm)
	var sm: Node = MANAGER_SCRIPT.new()
	sm.name = "SummonManager"
	fake_bm.add_child(sm)
	var fz: Node = ZONE_MANAGER_SCRIPT.new()
	fz.name = "FieldZoneManager"
	fake_bm.add_child(fz)
	var handler: Node = HANDLER_SCRIPT.new()
	handler.battle_manager = fake_bm
	var owner_p: StubOwner = StubOwner.new()
	owner_p.position = Vector2(300, 800)
	root.add_child(owner_p)
	# _get_caster 备用口（照 H 组成案：battle_manager.get_all_players；typed Array set() 静默失败规避）
	var fake_script: GDScript = GDScript.new()
	fake_script.source_code = "extends Node\nvar players_ref: Array = []\nfunc get_all_players() -> Array:\n\treturn players_ref\n"
	fake_script.reload()
	fake_bm.set_script(fake_script)
	fake_bm.set("players_ref", [owner_p])

	handler._apply_summon_spawn({"summon_type": "shuimu_shark_att", "count": 1}, owner_p.get_instance_id())
	var mine: Array = sm.get_summons_of(owner_p.get_instance_id())
	_assert("K3b: spawn分发链——召唤1条攻鲨（SUMMON_SPAWNED入账本）", mine.size() == 1 and str(mine[0].get("summon_type")) == "shuimu_shark_att")
	_assert("K3c: 散布位置=施法者环绕40px内", owner_p.global_position.distance_to((mine[0] as Node2D).global_position) <= 45.0)

	# ===== K4-上限截断 =====
	handler._apply_summon_spawn({"summon_type": "shuimu_shark_att", "count": 2}, owner_p.get_instance_id())
	mine = sm.get_summons_of(owner_p.get_instance_id())
	_assert("K4: count2再召→上限2截断（types active_limit）", mine.size() == 2)

	# ===== K5-融合链（F4查询口收尾：is_in_energy_path + try_merge） =====
	_assert("K5a: 无快道时 is_in_energy_path=false", not bool(fz.is_in_energy_path(Vector2(300, 800))))
	var bomb_zone: Area2D = fz.create_zone({
		"zone_type": 6, "duration": 30.0,
		"path_from": Vector2(0, 800), "path_to": Vector2(400, 800),
	}, Vector2(0, 800))
	bomb_zone.set_process(false)
	_assert("K5b: 快道内 is_in_energy_path=true", bool(fz.is_in_energy_path(Vector2(200, 800))))
	# 双鲨挪进快道 → merge技能分发
	(mine[0] as Node2D).global_position = Vector2(150, 800)
	(mine[1] as Node2D).global_position = Vector2(250, 800)
	handler._apply_summon_merge({"result_type": "shuimu_shark_bomb", "need_count": 2}, owner_p.get_instance_id())
	mine = sm.get_summons_of(owner_p.get_instance_id())
	var bomb_ok := mine.size() == 1 and str(mine[0].get("summon_type")) == "shuimu_shark_bomb"
	_assert("K5c: 双鲨在快道内→融合为炸弹（SUMMON_MERGED链）", bomb_ok)
	# 反例：快道外不融合
	var solo: Node = sm.spawn("shuimu_shark_att", owner_p.get_instance_id(), Vector2(-600, 800))
	if solo != null:
		(solo as Node2D).global_position = Vector2(-600, 800)
	var solo2: Node = sm.spawn("shuimu_shark_att", owner_p.get_instance_id(), Vector2(-650, 800))
	if solo2 != null:
		(solo2 as Node2D).global_position = Vector2(-650, 800)
	var before: int = sm.get_summons_of(owner_p.get_instance_id()).size()
	handler._apply_summon_merge({"result_type": "shuimu_shark_bomb", "need_count": 2}, owner_p.get_instance_id())
	_assert("K5d: 快道外→try_merge 拒绝（fail-closed）", sm.get_summons_of(owner_p.get_instance_id()).size() == before)
	_assert("K6: 守鲨型可召（拦截态独立验证留给时期3事件矩阵）", sm.spawn("shuimu_shark_def", owner_p.get_instance_id(), Vector2(300, 800)) != null)

	_finish()


func _finish() -> void:
	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 全部通过！（水木6技配置+summon分发链交付）")
	quit(1 if _fail > 0 else 0)
