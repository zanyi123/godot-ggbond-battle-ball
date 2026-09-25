## 基础 UI 批次验收（技能规划/19，13-A~D）：节点/状态断言 ≥10（headless 可跑）
## 红线核验含"UI 零判定"（grep 图标条源码无写操作）；截图项 headless 无法产出如实标注
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_basic_ui.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== 基础 UI 批次验收（19 工单 13-A~D）==========\n")
	for i in range(3):
		await process_frame

	var player: CharacterBody2D = load("res://scripts/battle/player.gd").new()
	player.team = "a"
	root.add_child(player)
	await process_frame

	# ===== 13-A 图标条组件：挂/摘/配色 =====
	var bar: Control = load("res://scripts/battle/status_icon_bar.gd").new()
	root.add_child(bar)
	bar.bind_player(player)
	player.turn_on_light("heal_block", 3.0)
	await process_frame
	var keys: Array = bar.get_entry_keys()
	var heal_ok: bool = "heal_block" in keys
	var icon_cfg: Dictionary = bar.STATUS_ICONS.get("heal_block", {})
	var entry_color: Color = bar._entries.get("heal_block", {}).get("color", Color.BLACK) if heal_ok else Color.BLACK
	_assert("13-A: 状态灯亮→图标出现(键在册)", heal_ok)
	_assert("13-A: 图标配色=映射表(禁疗紫)", entry_color == Color(0.65, 0.3, 0.85) and str(icon_cfg.get("char", "")) == "疗")
	player.turn_off_light("heal_block")
	await process_frame
	_assert("13-A: 灯灭→图标消失", not ("heal_block" in bar.get_entry_keys()))

	# ===== 13-A 秒数角标递减（整秒节流广播）=====
	player.turn_on_light("energy_block", 5.0)
	await process_frame
	var r0: int = int(bar._entries.get("energy_block", {}).get("remaining", -1))
	player._tick_status_lights(1.2)   # headless 物理帧不跑：手动驱动 tick（验证整秒节流广播→条目更新链路）
	await process_frame
	var r1: int = int(bar._entries.get("energy_block", {}).get("remaining", -1))
	_assert("13-A: 秒数角标随时间递减(%d->%d)" % [r0, r1], r0 > r1 and r1 >= 3)
	player.turn_off_light("energy_block")

	# ===== 13-A 8 个折叠 =====
	var names := ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"]
	for n in names:
		bar.set_entry(n, "?", Color.GRAY, 9, 0)
	_assert("13-A: 注入10条→折叠条件成立", bar.get_entry_keys().size() == 10 and bar.get_visible_count() <= 8)
	for n in names:
		bar.remove_entry(n)

	# ===== 13-B 波3 六原语接入（灯键→图标）=====
	var wave3 := {"heal_block": "疗", "energy_block": "能", "reflect": "反", "element_immune": "免", "energy_share": "摊"}
	var w3_ok := true
	for light_name in wave3:
		player.turn_on_light(light_name, 4.0)
	await process_frame
	for light_name in wave3:
		if not (light_name in bar.get_entry_keys()):
			w3_ok = false
		player.turn_off_light(light_name)
	_assert("13-B: 波3 原语灯亮→图标挂/灭→摘(禁疗/禁能/反伤/免疫/分摊)", w3_ok)
	# toggle 激活态图标（经 toggle_changed 信号）
	player.open_toggle("t_ui_test", [], 1.0)
	await process_frame
	var t_on: bool = "toggle_t_ui_test" in bar.get_entry_keys()
	player.close_toggle("t_ui_test")
	await process_frame
	_assert("13-B: toggle 开→T图标挂 / 关→摘", t_on and not ("toggle_t_ui_test" in bar.get_entry_keys()))

	# ===== 13-D1 印记层数（mark_changed 消费）=====
	player.apply_mark("frost", 5, 8.0)
	player.apply_mark("frost", 5, 8.0)
	await process_frame
	var frost: Dictionary = bar._entries.get("mark_frost", {})
	_assert("13-D: 印记层数角标随 mark_changed 更新(2层)", int(frost.get("stacks", 0)) == 2)
	player.clear_mark("frost")
	await process_frame
	_assert("13-D: 印记清→图标摘", not ("mark_frost" in bar.get_entry_keys()))

	# ===== 13-D2 充能点 N/M =====
	player.turn_on_light("charge_stock", 10.0, {"charges": 3, "charges_max": 6})
	await process_frame
	var cs: Dictionary = bar._entries.get("charge_stock", {})
	_assert("13-D: 充能点 N/M 随 charges 更新(3/6)", int(cs.get("charges", 0)) == 3 and int(cs.get("charges_max", 0)) == 6)
	player.turn_off_light("charge_stock")

	# ===== 13-C 盾本体可视（2D 弧子节点 + 3D 代理）=====
	var om: Node = load("res://scripts/battle/obstacle_manager.gd").new()
	root.add_child(om)
	await process_frame
	var svm: Node = load("res://scripts/systems/spirit_system/skill_visual_manager.gd").new()
	root.add_child(svm)
	svm.setup(om, null, [])
	if not om.player_shield_spawned.is_connected(svm._on_player_shield_spawned):
		om.player_shield_spawned.connect(svm._on_player_shield_spawned)
	var caster: CharacterBody2D = load("res://scripts/battle/player.gd").new()
	caster.team = "b"
	caster.spirit_energy = 100.0
	root.add_child(caster)
	var shield_params := {"shape": "circle", "radius": 30.0, "hp": 3.0, "uses": 3, "durability_mode": "uses", "follow_mode": "follow", "duration": 10.0}
	var shield: StaticBody2D = om.create_player_shield(shield_params.duplicate(), caster)
	await process_frame
	var vis: Node2D = null
	for c in shield.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("shield_visual_2d.gd"):
			vis = c
	_assert("13-C: 盾生成→2D 弧面可视子节点挂载(follow 定位=施法者前方)", vis != null \
		and shield.global_position.distance_to(caster.global_position) > 1.0)
	shield.on_ball_hit()
	await process_frame
	_assert("13-C: uses 扣次→耐久可辨(3->2)", int(vis._uses_left) == 2)
	om.remove_obstacle(shield)
	await process_frame
	_assert("13-C: 盾移除→可视随宿主消失", not is_instance_valid(shield))
	var sv3_script: GDScript = load("res://scripts/battle3d/visual/shield_visual_3d.gd")
	var sv3: Node3D = Node3D.new()
	sv3.set_script(sv3_script)
	root.add_child(sv3)
	var host2: CharacterBody2D = load("res://scripts/battle/player.gd").new()
	host2.team = "b"
	root.add_child(host2)
	var shield2: StaticBody2D = om.create_player_shield(shield_params.duplicate(), host2)
	sv3.setup(shield2)
	sv3.sync_from_2d(Vector2(120.0, 80.0), 1.0)
	var mesh_found: bool = false
	for c in sv3.get_children():
		if c.name == "ShieldBody":
			mesh_found = true
	_assert("13-C: 3D 盾体简约件(mesh+跟随同步)", mesh_found and (sv3.global_position - Vector3(120.0, 30.0, 80.0)).length() < 0.5)
	om.remove_obstacle(shield2)

	# ===== 13-D3 必中锁定线 / 13-D4 球隐身半透明 =====
	var ball: Area2D = load("res://scripts/battle/ball.gd").new()
	root.add_child(ball)
	await process_frame
	var target: CharacterBody2D = load("res://scripts/battle/player.gd").new()
	target.team = "b"
	target.position = Vector2(200, 0)
	root.add_child(target)
	ball.ball_mods["sure_hit"] = true
	ball.ball_mods["lockon_target"] = target
	ball._sync_basic_ui_visuals()
	var line: Line2D = ball.get_node_or_null("SureHitLine")
	_assert("13-D: 必中激活→锁定线生成且两点连线", line != null and line.visible and line.points.size() == 2)
	ball.ball_mods["hidden_from_enemies"] = true
	ball._sync_basic_ui_visuals()
	_assert("13-D: 球隐身→2D 半透明(alpha=0.35)", absf(ball.ball_visual.modulate.a - 0.35) < 0.01)
	ball.ball_mods["hidden_from_enemies"] = false
	ball.ball_mods["sure_hit"] = false
	ball._sync_basic_ui_visuals()
	_assert("13-D: 恢复→不透明+必中线隐藏", ball.ball_visual.modulate.a == 1.0 and not line.visible)

	# ===== HUD 挂载 =====
	var hud: Control = load("res://scripts/battle/battle_hud.gd").new()
	root.add_child(hud)
	await process_frame
	var team: Array[CharacterBody2D] = [player, caster, target]
	var enemies: Array[CharacterBody2D] = []
	hud.setup_players(team, enemies)
	await process_frame
	var bars: Array = hud._status_icon_bars
	var bound_ok: bool = bars.size() == 3
	if bound_ok:
		for i in range(3):
			if bars[i]._bound_player != team[i]:
				bound_ok = false
	_assert("HUD: 三球员面板各挂图标条且绑定正确", bound_ok)

	# ===== UI 零判定断言（grep 架构核验）=====
	var src: String = FileAccess.get_file_as_string("res://scripts/battle/status_icon_bar.gd")
	var clean: bool = not ("turn_on_light" in src) and not ("turn_off_light" in src) \
		and not ("player._status_lights" in src) \
		and not (".spirit_energy" in src) and not ("apply_mark" in src) \
		and not ("close_toggle" in src) and not ("open_toggle" in src)
	_assert("架构: 图标条源码零判定写操作(grep 核验)", clean)

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 全部通过！（截图观感项 headless 无法产出，已如实标注待窗口环境补）")
	quit(1 if _fail > 0 else 0)


func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)
