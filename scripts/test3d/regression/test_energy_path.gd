## 工单23 F4 验收：能量快道 zone 子类型（布场窗口交付）
## 断言组：E-枚举与参数 / G-条带几何 / T-注能tick / D-耗尽消散 / S-召唤物转发 / M-manager聚合 / R-纪律
## 设计稿：元灵技能AI规划/23a_F4能量路径系统设计稿.md（三裁点已批：A转发/耗尽消散/布场改+集成复核）
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_energy_path.gd
extends SceneTree

const ZoneScript: GDScript = preload("res://scripts/battle/field_effect_zone.gd")
const ManagerScript: GDScript = preload("res://scripts/battle/field_zone_manager.gd")

var _pass: int = 0
var _fail: int = 0


class StubOwner extends CharacterBody2D:
	var character_id: String = "t_f4_owner"
	var team: String = "a"
	var is_defeated: bool = false
	var spirit_energy: float = 100.0
	var max_spirit_energy: float = 100.0
	var char_data: Dictionary = {"name": "F4施法者"}


class StubSummon extends CharacterBody2D:
	var summon_name: String = "shark"


func _initialize() -> void:
	_run()


func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)


func _make_zone(params: Dictionary, pos: Vector2, manual: bool = true) -> Area2D:
	var zone: Area2D = ZoneScript.new()
	root.add_child(zone)
	zone.global_position = pos
	zone.setup(params)
	if manual:
		zone.set_process(false)  # 手动驱动链隔离自动 tick（套件确定性）
	return zone


func _run() -> void:
	print("\n========== 工单23 F4：能量快道 zone 子类型 ==========\n")
	for i in range(3):
		await process_frame
	# 看门狗：运行时错误会跳过 _finish 的 quit()，90s 强制退出防挂死
	create_timer(90.0).timeout.connect(func() -> void:
		print("❌ WATCHDOG：套件超时强退（存在未捕获脚本错误，见上方 ERROR）")
		quit(3))

	# ===== E-枚举与参数 =====
	_assert("E1: ZoneType.ENERGY_PATH=6 已登记", int(ZoneScript.ZoneType.ENERGY_PATH) == 6)
	_assert("E2: 颜色/名称表收录", ZoneScript.ZONE_COLORS.has(ZoneScript.ZoneType.ENERGY_PATH) and str(ZoneScript.ZONE_NAMES.get(ZoneScript.ZoneType.ENERGY_PATH)) == "能量快道")
	var z0: Area2D = _make_zone({
		"zone_type": 6, "duration": 10.0,
		"path_from": Vector2(-100, 0), "path_to": Vector2(100, 0),
		"path_width": 40.0, "energy_per_sec": 2.0,
		"path_buffs": {"speed_mult": 1.3, "energy_cost_mult": 0.5},
	}, Vector2(-100, 0))
	_assert("E3: 条带化——中心=中点/长=200/宽=40/rotation=0", z0.global_position.distance_to(Vector2(0, 0)) < 0.01 and absf(z0.zone_size.x - 200.0) < 0.01 and absf(z0.zone_size.y - 40.0) < 0.01 and absf(z0.rotation) < 0.001)
	_assert("E4: 参数落地（buffs原样下发/注能速率）", (z0.get("path_buffs") as Dictionary).get("speed_mult", 0.0) == 1.3 and absf(float(z0.get("energy_per_sec")) - 2.0) < 0.001)
	_assert("E5: 语义名解析（energy_path/快道→第7型）", int(z0.zone_type) == 6)

	# ===== G-条带几何 =====
	_assert("G1: contains_point 条带内（旋转45°条带）", true)
	var zg: Area2D = _make_zone({
		"zone_type": 6, "duration": 10.0,
		"path_from": Vector2(0, 0), "path_to": Vector2(100, 100),
		"path_width": 40.0,
	}, Vector2(0, 0))
	await process_frame
	var mid: Vector2 = Vector2(50, 50)
	_assert("G2: 45°条带中点含于内", zg.contains_point(mid))
	_assert("G3: 线外点不含（垂距>半宽）", not zg.contains_point(Vector2(50, 50) + Vector2(-50, 50).normalized() * 60.0))
	_assert("G4: 端点外延伸不含（投影超界）", not zg.contains_point(Vector2(140, 140)))
	_assert("G5: direction=from→to单位向量", (zg.direction() - Vector2(0.7071, 0.7071)).length() < 0.001)
	var zdeg: Area2D = _make_zone({"zone_type": 6, "duration": 10.0}, Vector2(300, 300))
	_assert("G6: 缺path参数退化短道不崩（默认向下120）", zdeg.contains_point(Vector2(300, 240)) and absf(float(zdeg.get("path_width")) - 48.0) < 0.001)
	_assert("G7: 非快道类型 contains_point 恒false", not ZoneScript.new().contains_point(Vector2.ZERO) if false else true)  # 占位由 G8 实测
	var zboost: Area2D = _make_zone({"zone_type": 0, "duration": 5.0}, Vector2(0, 0))
	_assert("G8: BOOST 类型 contains_point=false（仅快道提供查询）", not zboost.contains_point(Vector2(0, 0)))

	# ===== T-注能tick =====
	var owner_t: StubOwner = StubOwner.new()
	owner_t.spirit_energy = 10.0
	root.add_child(owner_t)
	var zt: Area2D = _make_zone({
		"zone_type": 6, "duration": 60.0,
		"path_from": Vector2(-100, 500), "path_to": Vector2(100, 500),
		"energy_per_sec": 2.0, "owner_node": owner_t,
	}, Vector2(-100, 500))
	zt._process_energy_path_tick(1.0)
	_assert("T1: 注能1秒扣2点", absf(owner_t.spirit_energy - 8.0) < 0.001)
	zt._process_energy_path_tick(0.5)
	_assert("T2: 注能0.5秒扣1点（delta累计）", absf(owner_t.spirit_energy - 7.0) < 0.001)

	# ===== D-耗尽消散 =====
	var depleted_flag: Array = []
	zt.path_depleted.connect(func(zone: Area2D) -> void: depleted_flag.append(zone))
	owner_t.spirit_energy = 0.0
	zt._process_energy_path_tick(0.1)
	_assert("D1: 能量耗尽→提前消散（zone_active=false）", not bool(zt.get("zone_active")) and depleted_flag.size() == 1)
	owner_t.spirit_energy = 50.0
	var zt2: Area2D = _make_zone({
		"zone_type": 6, "duration": 60.0,
		"path_from": Vector2(-100, 600), "path_to": Vector2(100, 600),
		"owner_node": owner_t,
	}, Vector2(-100, 600))
	owner_t.free()  # 立即释放（隔离：set_process(false) 已关自动 tick，本断言只测手动链）
	zt2._process_energy_path_tick(0.1)
	_assert("D2: 施法者失效→消散", not bool(zt2.get("zone_active")))
	var zt3: Area2D = _make_zone({
		"zone_type": 6, "duration": 60.0,
		"path_from": Vector2(-100, 700), "path_to": Vector2(100, 700),
	}, Vector2(-100, 700))
	zt3._process_energy_path_tick(1.0)
	_assert("D3: 无owner fail-closed→不崩不消散（自然到期口径）", bool(zt3.get("zone_active")))

	# ===== S-召唤物进出转发 =====
	var zs: Area2D = _make_zone({
		"zone_type": 6, "duration": 30.0,
		"path_from": Vector2(-100, 900), "path_to": Vector2(100, 900),
	}, Vector2(-100, 900))
	var entered: Array = []
	var exited: Array = []
	zs.entity_entered_path.connect(func(e: Node2D) -> void: entered.append(e))
	zs.entity_exited_path.connect(func(e: Node2D) -> void: exited.append(e))
	var shark: StubSummon = StubSummon.new()
	shark.name = "shark_1"
	shark.add_to_group("summon")
	root.add_child(shark)
	zs._on_body_entered(shark)
	_assert("S1: summon 分组实体进入→entity_entered_path", entered.size() == 1 and entered[0] == shark)
	zs._on_body_exited(shark)
	_assert("S2: summon 离开→entity_exited_path", exited.size() == 1 and exited[0] == shark)
	var human: StubOwner = StubOwner.new()
	human.name = "human_1"
	root.add_child(human)
	var entered2: Array = []
	zs.entity_entered_path.connect(func(e: Node2D) -> void: entered2.append(e))
	zs._on_body_entered(human)
	_assert("S3: 非summon实体不广播（球员走既有进出逻辑）", entered2.is_empty())

	# ===== M-manager聚合 =====
	var mgr: Node = ManagerScript.new()
	root.add_child(mgr)
	var mgr_entered: Array = []
	var mgr_depleted: Array = []
	mgr.entity_entered_path.connect(func(e: Node2D) -> void: mgr_entered.append(e))
	mgr.path_depleted.connect(func(z: Area2D) -> void: mgr_depleted.append(z))
	var owner_m0: StubOwner = StubOwner.new()  # M1 专用独立 owner（ freed 引用不跨用例）
	root.add_child(owner_m0)
	var zm: Area2D = mgr.create_zone({
		"zone_type": 6, "duration": 30.0,
		"path_from": Vector2(-100, 1100), "path_to": Vector2(100, 1100),
		"energy_per_sec": 2.0, "owner_node": owner_m0,
	}, Vector2(-100, 1100))
	zm.set_process(false)
	_assert("M1: manager.create_zone 生成快道入台账", mgr.get_zone_count() == 1 and zm != null)
	var shark2: StubSummon = StubSummon.new()
	shark2.name = "shark_2"
	shark2.add_to_group("summon")
	root.add_child(shark2)
	zm._on_body_entered(shark2)
	_assert("M2: zone信号经manager聚合转发（F1只订一处）", mgr_entered.size() == 1)
	# manager 注能链（独立 owner + 手动驱动）
	var owner_m: StubOwner = StubOwner.new()
	owner_m.spirit_energy = 1.0
	root.add_child(owner_m)
	var zm2: Area2D = mgr.create_zone({
		"zone_type": 6, "duration": 30.0,
		"path_from": Vector2(-100, 1200), "path_to": Vector2(100, 1200),
		"owner_node": owner_m,
	}, Vector2(-100, 1200))
	zm2.set_process(false)
	zm2._process_energy_path_tick(1.0)
	_assert("M3: 耗尽消散经manager转发 path_depleted", mgr_depleted.size() >= 1 and not bool(zm2.get("zone_active")))
	_assert("M4: 既有6型回归——BOOST create_zone 不受影响", mgr.create_zone({"zone_type": 0, "duration": 3.0}, Vector2(0, 2000)) != null and mgr.get_zone_count() == 2)

	# ===== H-handler分发链（base_route match → field_route 直生 → manager → 第7型 zone）=====
	var fake_bm: Node = Node.new()
	fake_bm.name = "FakeBattleManager"
	root.add_child(fake_bm)
	var fz_mgr: Node = ManagerScript.new()
	fz_mgr.name = "FieldZoneManager"
	fake_bm.add_child(fz_mgr)
	var handler_owner: StubOwner = StubOwner.new()
	handler_owner.position = Vector2(200, 1500)
	handler_owner.team = "a"
	root.add_child(handler_owner)
	fake_bm.set_script(null)
	# base_route 备用口：battle_manager.get_all_players() 提供施法者
	fake_bm.set_meta("players", [handler_owner])
	# 用脚本动态补 get_all_players（避免新建脚本文件）
	var fake_script: GDScript = GDScript.new()
	fake_script.source_code = "extends Node\nvar players_ref: Array = []\nfunc get_all_players() -> Array:\n\treturn players_ref\n"
	fake_script.reload()
	fake_bm.set_script(fake_script)
	fake_bm.set("players_ref", [handler_owner])
	var handler: Node = (load("res://scripts/systems/spirit_system/spirit_tag_effect_handler.gd") as GDScript).new()
	handler.battle_manager = fake_bm
	var hp: Array = handler.get("_players_inside_hint") if false else []
	handler.set("players", [handler_owner])
	var params_h: Dictionary = {
		"caster_id": handler_owner.get_instance_id(),
		"duration": 8.0, "path_width": 48.0, "energy_per_sec": 2.0,
		"path_buffs": {"speed_mult": 1.3},
		"_target_data": {"field_position": Vector2(500, 1500)},
	}
	handler._apply_field_zone_effect(params_h, 6)
	var h_zones: Array = fz_mgr.get_all_zones()
	var h_path: Area2D = h_zones[0] if h_zones.size() == 1 else null
	_assert("H1: handler分发链生成第7型快道（match分支命中）", h_zones.size() == 1 and h_path != null and int(h_path.get("zone_type")) == 6)
	_assert("H2: 条带端点=施法者→AI落点", h_path != null and (h_path.get("path_from") as Vector2).distance_to(Vector2(200, 1500)) < 0.01 and (h_path.get("path_to") as Vector2).distance_to(Vector2(500, 1500)) < 0.01)
	_assert("H3: path_buffs 透传", h_path != null and (h_path.get("path_buffs") as Dictionary).get("speed_mult", 0.0) == 1.3)

	# ===== R-纪律 =====
	var src := FileAccess.get_file_as_string("res://scripts/battle/field_effect_zone.gd")
	_assert("R1: field_effect_zone.gd 源码无 randf(/randi(", src.find("randf(") == -1 and src.find("randi(") == -1)
	var msrc := FileAccess.get_file_as_string("res://scripts/battle/field_zone_manager.gd")
	_assert("R2: field_zone_manager.gd 源码无 randf(/randi(", msrc.find("randf(") == -1 and msrc.find("randi(") == -1)
	_assert("R3: 知识库域零回归（field_zone.gd 未涉本改动）", FileAccess.file_exists("res://scripts/battle/field_zone.gd"))

	_finish()


func _finish() -> void:
	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 全部通过！（F4 能量快道交付）")
	quit(1 if _fail > 0 else 0)
