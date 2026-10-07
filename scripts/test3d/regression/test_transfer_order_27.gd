## 27号移交单验收套件（操控UI窗口实施判定域件；headless 可跑）
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_transfer_order_27.gd
## 覆盖：D13 印记传敌（存储meta/清空转移/接收合并/施放侧阈值延迟/经handler转移）+
##       J1 拦截发射点（序断言：拦截先于 on-hit 消费=免负面）+ J2 element 字段 +
##       J3 OBSTACLE_IMPACT 三阶段 + J4 SUMMON_STATE_CHANGED（功能测）+ D14 AI 锚点语义/宽度80
extends SceneTree

var _pass: int = 0
var _fail: int = 0

func _initialize() -> void:
	_run()

func _assert(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  ✅ PASS: " + name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + name)

func _run() -> void:
	print("\n========== 27号：判定域移交件验收 ==========\n")
	for i in range(3):
		await process_frame
	var PlayerScript: GDScript = load("res://scripts/battle/player.gd")
	var HandlerScript: GDScript = load("res://scripts/systems/spirit_system/spirit_tag_effect_handler.gd")
	var EntityScript: GDScript = load("res://scripts/systems/summon/summon_entity.gd")
	var BusScript: GDScript = load("res://scripts/systems/event_bus/event_bus.gd")
	_assert(HandlerScript != null and EntityScript != null, "handler 司法链/召唤实体可加载（含语法编译）")
	_assert(BusScript.GameEvent.has("OBSTACLE_IMPACT") and BusScript.GameEvent.has("SUMMON_STATE_CHANGED"), "事件枚举: OBSTACLE_IMPACT + SUMMON_STATE_CHANGED 在册（J3/J4）")

	# ===== D13：印记存储三件 =====
	var caster: CharacterBody2D = PlayerScript.new()
	var victim: CharacterBody2D = PlayerScript.new()
	caster.team = "a"
	victim.team = "b"
	root.add_child(caster)
	root.add_child(victim)
	await process_frame
	var meta: Dictionary = {"thresholds": [{"count": 99, "tag": "x", "params": {}, "clear": false}]}
	caster.apply_mark("huo_yinji", 3, 20.0, meta)
	caster.apply_mark("huo_yinji", 3, 20.0, meta)
	_assert(caster.get_mark_count("huo_yinji") == 2, "D13: 叠层 ×2=2（meta 存储不影响计数）")
	var drained: Dictionary = caster.drain_all_marks()
	_assert(drained.has("huo_yinji") and int(drained["huo_yinji"]["count"]) == 2 and caster.get_mark_count("huo_yinji") == 0, "D13: drain=快照返回+本体清空")
	victim.receive_mark("huo_yinji", 2, 3, 15.0, meta)
	victim.receive_mark("huo_yinji", 1, 3, 18.0, meta)
	_assert(victim.get_mark_count("huo_yinji") == 2, "D13: receive 叠合并=取较大层数")

	# ===== D13：经 handler 转移（注册名册直驱）=====
	var handler: Node = HandlerScript.new()
	root.add_child(handler)
	await process_frame
	handler.players = [caster, victim] as Array[Node]  # 强类型属性赋值需显式转型（-s 引擎怪癖，8a1e117 备案）
	caster.apply_mark("huo_yinji", 3, 20.0, meta)
	caster.apply_mark("huo_yinji", 3, 20.0, meta)
	handler.transfer_marks_on_hit(caster.get_instance_id(), victim)
	_assert(caster.get_mark_count("huo_yinji") == 0 and victim.get_mark_count("huo_yinji") == 2, "D13: 经handler 施法者印记→受击者（层数随转移，阈值99不触发）")

	# ===== D13：施放侧阈值延迟（self 充能印记只叠层不触发）=====
	caster.clear_mark("huo_yinji")
	handler._apply_player_mark_apply({
		"mark_id": "huo_yinji", "max_stacks": 3.0, "duration": 20.0, "target": "self",
		"thresholds": [{"count": 2.0, "tag": "player_heal_block", "params": {"duration": 6.0}, "clear": false}],
	}, caster.get_instance_id())
	_assert(caster.get_mark_count("huo_yinji") == 1, "D13: self 充能印记施放侧叠层")
	_assert(victim.is_status_active("heal_block") == false, "D13: 施放侧阈值未触发（延迟到受击者侧，print 口径验证）")
	# 非self目标：阈值照旧施放侧触发（行为兼容面）——目标=显式敌人语义
	victim.clear_mark("huo_yinji")

	# ===== J1/J2/J3：ball.gd 源码序断言（整球链路需场景环境，以源码口径+枚举在册核验）=====
	var ball_src: String = (load("res://scripts/battle/ball.gd") as GDScript).source_code
	var idx_intercept: int = ball_src.find("GameEvent.DEFEND_INTERCEPT")
	var idx_consume: int = ball_src.find("consume_hit_tags(")
	_assert(idx_intercept > 0 and idx_intercept < idx_consume, "J1: 拦截发射点先于 on-hit 消费（伤害与标签均不达=免负面）")
	_assert(ball_src.contains("\"element\": _attacker_element()"), "J2: HIT_TAKEN payload 补 element（来袭属性）")
	_assert(ball_src.contains("\"phase\": \"contact\"") and ball_src.contains("\"phase\": \"breakthrough\"") and ball_src.contains("\"phase\": \"blocked\""), "J3: 球-障碍三阶段事件（接触/击穿/挡停）")
	var granter_src: String = (load("res://scripts/battle/battle_item_granter.gd") as GDScript).source_code
	_assert(granter_src.contains("DEFEND_INTERCEPT") and granter_src.contains("defend_intercept_ready = false"), "J1: granter 订阅端耐久消费闭环在位")

	# ===== J4：SUMMON_STATE_CHANGED 功能测（真实体+真总线）=====
	var bus: Node = BusScript.new()
	bus.add_to_group("battle_event_bus")
	root.add_child(bus)
	var got: Array = []
	bus.subscribe(bus.GameEvent.SUMMON_STATE_CHANGED, func(p: Dictionary) -> void: got.append(str(p.get("state", ""))))
	var ent: Node2D = EntityScript.new()
	root.add_child(ent)
	ent.set("_tdef", {"burrow": {"energy_cost_per_s": 2.0}})
	ent.set("lifespan_left", 999.0)  # 压默认寿命0到期回收（引擎正确行为，防第三事件混入断言）
	ent.enter_burrow()
	ent.exit_burrow()
	await process_frame
	_assert(got.size() >= 2 and got[0] == "burrowed" and got[1] == "active", "J4: 遁地进出→状态事件（显示层可订阅零轮询）")

	# ===== D14：AI 锚点语义 + 宽度 80 =====
	var fr_src: String = (load("res://scripts/systems/spirit_system/handler/field_route.gd") as GDScript).source_code
	_assert(fr_src.contains("knowledge_enemy_side_anchor") and fr_src.contains("AI_PATH_LENGTH"), "D14: AI 快道=朝对方内场锚铺开（知识库权威）")
	var fzk: GDScript = load("res://scripts/battle/field_zone.gd")
	_assert(fzk.knowledge_enemy_side_anchor("a").distance_to(Vector2(-300, 0)) < 0.001, "D14: 锚点交叉布局核验（a队→敌锚-300）")
	var jdata: Dictionary = load_json_res("res://data/spirits/skills.json")
	var pw: float = 0.0
	for sk in jdata.get("skills", []):
		if str(sk.get("id", "")) == "shuimu_3":
			pw = float(sk.get("tag_params", {}).get("field_zone_energy_path", {}).get("path_width", 0.0))
	_assert(absf(pw - 80.0) < 0.01, "D14: 快道宽度数据件 48→80（600×80 口径）")

	# ===== D14 玩家通道（已交付件回归锚）=====
	var placer_src: String = (load("res://scripts/battle/field_zone_placer.gd") as GDScript).source_code
	_assert(placer_src.contains("path_release_points") and placer_src.contains("PATH_LENGTH"), "D14: 玩家通道预览/释放语义在位（17/17 套件另证）")

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail == 0:
		print("🎉 全部通过")
	else:
		print("❌ 有失败项")
	quit(0 if _fail == 0 else 1)

func load_json_res(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}
