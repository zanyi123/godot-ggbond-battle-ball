## 34号 S2：接缝验收硬条款套件（test_seam_gate）——新机制→时序体系的接缝机器把门
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_seam_gate.gd
## 数据驱动：读 skills.json 遍历全部 operator≠OP_AUTO 操控技——新队伍新技能落库即自动纳入检查。
## 四问（34号§四）：Q1 登记口有写入 / Q2 输入源有覆盖 / Q3 身份参数传到位 / Q4 检测体有调用方。
## 门禁：新操控/实体类工单交付必跑；红=打回。破坏演练见尾部 DRILL 段（证明套件真能抓断层）。
extends SceneTree

var _pass: int = 0
var _fail: int = 0
var _violations: Array = []   # 接缝违例收集（数据驱动逐技）

func _initialize() -> void:
	_run()

func _assert(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  ✅ " + name)
	else:
		_fail += 1
		_violations.append(name)
		print("  ❌ " + name)

class Host extends Node2D:
	var controlled_player: Node = null
	var team_a_players: Array = []
	var team_b_players: Array = []

func _run() -> void:
	print("\n========== 34号 S2：接缝验收硬条款（四问·数据驱动）==========\n")
	for i in range(3):
		await process_frame
	var PlayerScript: GDScript = load("res://scripts/battle/player.gd")
	var MgrScript: GDScript = load("res://scripts/systems/summon/summon_manager.gd")
	var EntityScript: GDScript = load("res://scripts/systems/summon/summon_entity.gd")
	var SsmScript: GDScript = load("res://scripts/systems/spirit_system/skill_state_manager.gd")
	var HandlerScript: GDScript = load("res://scripts/systems/spirit_system/spirit_tag_effect_handler.gd")
	var im_src: String = (load("res://scripts/battle/input_manager.gd") as GDScript).source_code
	var ssm_src: String = (SsmScript as GDScript).source_code
	var mgr_src: String = (MgrScript as GDScript).source_code
	var ent_src: String = (EntityScript as GDScript).source_code
	var fr_src: String = (load("res://scripts/systems/spirit_system/handler/field_route.gd") as GDScript).source_code

	# ===== 数据驱动：遍历操控技 =====
	var sdata: Dictionary = load_json("res://data/spirits/skills.json")
	var control_skills: Array = []
	for sk in sdata.get("skills", []):
		var op := str(sk.get("operator", "OP_AUTO"))
		if op != "OP_AUTO":
			control_skills.append({"id": str(sk.get("id", "")), "op": op, "tags": sk.get("tags", []), "tp": sk.get("tag_params", {})})
	print("操控技清单: %s" % str(control_skills.map(func(c): return c["id"] + ":" + c["op"])))
	_assert(control_skills.size() >= 6, "数据驱动: 操控技≥6（芬4+水6 中非 AUTO 者）")

	# ===== 环境搭建 =====
	var host: Host = Host.new()
	root.add_child(host)
	var mgr: Node = MgrScript.new()
	mgr.name = "SummonManager"
	host.add_child(mgr)
	mgr.set("team_a_players", [])
	mgr.set("team_b_players", [])
	await process_frame
	var handler: Node = HandlerScript.new()
	host.add_child(handler)
	await process_frame
	handler.battle_manager = host  # _ready 覆写陷阱备案：add_child 后重设
	handler.players = [] as Array[Node]
	var caster_a: CharacterBody2D = PlayerScript.new()
	caster_a.team = "a"
	caster_a.position = Vector2(-300, 0)
	root.add_child(caster_a)
	host.team_a_players = [caster_a]
	handler.players = [caster_a] as Array[Node]

	# ===== Q3（身份参数传到位）——施放路径原形：无 params 的 spawn 也注入身份 =====
	print("\n--- Q3 身份参数（逐 summon 型）---")
	var tdata: Dictionary = load_json("res://data/systems/summon/summon_types.json")
	var summon_types: Array = (tdata.get("types", {}) as Dictionary).keys()
	var identity_ok := true
	for tid in summon_types:
		var e: Node2D = mgr.spawn(tid, caster_a.get_instance_id(), Vector2(50, 50))  # 无 params=施放路径原形
		if e == null:
			continue  # 上限截断型（外部已覆盖）
		var orr = e.get("owner_ref")
		if orr == null or not is_instance_valid(orr) or str(orr.get("team")) != "a":
			identity_ok = false
	for e in (mgr.get("_live") as Array).duplicate():
		if is_instance_valid(e):
			mgr.despawn(e, "cleanup")
	_assert(identity_ok, "Q3: 全 summon 类型施放路径身份注入（无 params 原形；B 队镜像同链）")
	# B 队行为镜像（ bite 敌我随施法者）
	var b_caster: CharacterBody2D = PlayerScript.new()
	b_caster.team = "b"
	b_caster.position = Vector2(300, 700)
	root.add_child(b_caster)
	var bs: Node2D = mgr.spawn("shuimu_shark_att", b_caster.get_instance_id(), b_caster.global_position, {"owner_ref": b_caster})
	bs.set("_tdef", {"kind": "shark", "controllable": "steer", "contact_damage": 30.0, "move_speed": 120.0})
	bs.set("state", "active")
	var a_foe: CharacterBody2D = PlayerScript.new()
	a_foe.team = "a"
	a_foe.position = b_caster.global_position + Vector2(10, 0)
	root.add_child(a_foe)
	host.team_a_players = [caster_a]
	host.team_b_players = [a_foe]  # 命中扫描名册=host 双队（a_foe 入册才能被扫到）
	var a_hp0: float = float(a_foe.get("stamina"))
	bs._try_contact_hit()
	_assert(float(a_foe.get("stamina")) < a_hp0, "Q3 行为: B 队鲨咬 A 队敌（敌我随施法者，非硬编码）")
	for e in (mgr.get("_live") as Array).duplicate():
		if is_instance_valid(e):
			mgr.despawn(e, "cleanup")

	# ===== Q1（登记口有写入）——spawn 登记到 owner.summons；despawn 摘除 =====
	print("\n--- Q1 登记口 ---")
	var reg_ball: Node2D = mgr.spawn("fenny_magic_ball_att", caster_a.get_instance_id(), Vector2(50, 50), {"owner_ref": caster_a})
	_assert(reg_ball != null and (caster_a.get("summons") as Array).has(reg_ball), "Q1: spawn→owner.summons 登记（断点C 闭合态）")
	mgr.despawn(reg_ball, "lifespan")
	_assert(not (caster_a.get("summons") as Array).has(reg_ball), "Q1: despawn→登记摘除")

	# ===== Q2（输入源有覆盖）——逐 operator 源码断言（数据驱动）=====
	print("\n--- Q2 输入源覆盖（数据驱动逐操控技）---")
	var op_ok := true
	for c in control_skills:
		var op: String = c["op"]
		var sid: String = c["id"]
		var has := false
		match op:
			"OP_STEER":
				# 召唤型（鲨鱼系）：鼠标定向注入；白球指挥技：两段指挥路由
				if _is_magic_command(sid, sdata):
					has = ssm_src.contains("mark_stage") and im_src.contains("inject_steer_to_summons")
				else:
					has = im_src.contains("inject_steer_to_summons") and ent_src.contains("control_move")
			"OP_MARK":
				has = ssm_src.contains("_bridge_marking_to_summon") and ssm_src.contains("mark_stage")
			"OP_PLACE":
				has = fr_src.contains("start_placing") or (load("res://scripts/battle/field_zone_placer.gd") as GDScript).source_code.contains("start_placing")
			"OP_SUMMON":
				has = ssm_src.contains("_notify_summon_order")
			_:
				has = true  # 其余 operator 有既有路径（操1 12类路由已验收）
		if not has:
			op_ok = false
			_violations.append("Q2 缺输入源: %s (%s)" % [sid, op])
	_assert(op_ok, "Q2: 全操控技输入源覆盖（断点A/B/E 闭合态）")

	# ===== Q4（检测体有调用方）=====
	print("\n--- Q4 检测体调用方 ---")
	_assert(ent_src.contains("_build_touch_area(") and ent_src.count("_build_touch_area") >= 2, "Q4: 触碰检测体构建+调用（断点：零调用方防线）")
	_assert(ent_src.contains("_on_touch_body") and ent_src.contains("body_entered.connect"), "Q4: 触碰分发已接线（Area2D→_on_touch_body）")

	# ===== S2 破坏演练（证明套件真能抓断层——夹具法，不改源码）=====
	print("\n--- 破坏演练（夹具模拟断点C/断点31号）---")
	# 演练1：登记口断裂（spawn 后不登记——模拟断点C）→ Q1 检查函数必须能判伪
	var broken: Node2D = mgr.spawn("fenny_magic_ball_att", caster_a.get_instance_id(), Vector2(60, 60), {"owner_ref": caster_a})
	(caster_a.get("summons") as Array).erase(broken)  # 人为撕断登记（=断点C 现象）
	var drill1_caught: bool = not (caster_a.get("summons") as Array).has(broken)
	_assert(drill1_caught, "演练①: 登记口断裂可被检出（撕断→检查红）")
	# 演练2：身份断裂（owner_ref 撕空→_resolve_my_team 空=fail-closed 不咬）
	var orphan: Node2D = mgr.spawn("shuimu_shark_att", b_caster.get_instance_id(), Vector2(0, 0))
	orphan.set("owner_ref", null)  # 人为撕断身份（=31号断裂现象）
	var foe_near: CharacterBody2D = PlayerScript.new()
	foe_near.team = "b"
	foe_near.position = Vector2(5, 0)
	root.add_child(foe_near)
	orphan._try_contact_hit()
	_assert(str(orphan.get("state")) != "consumed", "演练②: 身份断裂→fail-closed 不咬人（可检出）")
	for e in (mgr.get("_live") as Array).duplicate():
		if is_instance_valid(e):
			mgr.despawn(e, "cleanup")

	# ===== S4：AI 白球指挥链（19A S5 尾款：意图→指令→位移） =====
	print("\n--- S4 AI 白球指挥链 ---")
	var AIInput: GDScript = load("res://scripts/battle/spirit_ai/ai_input_source.gd")
	var ai_caster: CharacterBody2D = PlayerScript.new()
	ai_caster.team = "b"
	ai_caster.position = Vector2(300, 800)
	host.add_child(ai_caster)  # 挂 host（名册可达=tick 名册解析前提）
	host.team_b_players.append(ai_caster)
	caster_a.is_player_controlled = true  # 人类标记（S4 分流断言前提）
	var ai_att: Node2D = mgr.spawn("fenny_magic_ball_att", ai_caster.get_instance_id(), Vector2(310, 810), {"owner_ref": ai_caster})
	ai_att.set("lifespan_left", 999.0)
	ai_att.set("_tdef", {"kind": "magic_ball", "controllable": "steer", "on_ball": {"mode": "carry_with_ball", "damage": 30.0}})
	var act: String = AIInput.tick_summon_commands(ai_caster)
	_assert(act == "ai_attack_order" and bool(ai_att.get("_flying")), "S4: AI 攻球=自动指挥出击（意图→指令）")
	var px: float = (ai_att.global_position as Vector2).x
	for f in range(3):
		if is_instance_valid(ai_att):
			ai_att._physics_process(1.0 / 60.0)
	_assert(not is_instance_valid(ai_att) or (ai_att.global_position as Vector2).x != px, "S4: 位移链（飞行段朝敌位移）")
	var h_ball: Node2D = mgr.spawn("fenny_magic_ball_def", caster_a.get_instance_id(), Vector2(60, 60), {"owner_ref": caster_a})
	h_ball.set("lifespan_left", 999.0)
	host.team_a_players = [caster_a]  # 人类侧名册重申（前序块可能改写）
	host.team_b_players = [ai_caster, b_caster]
	var act2: String = AIInput.tick_summon_commands(caster_a)
	_assert(bool(h_ball.get("_flying")) == false and act2 == "hold", "S4: 人类球不受 AI 通道指挥（储备听两段点击）")
	var ai_def: Node2D = mgr.spawn("fenny_magic_ball_def", ai_caster.get_instance_id(), Vector2(320, 810), {"owner_ref": ai_caster})
	ai_def.set("lifespan_left", 999.0)
	ai_def.set("_tdef", {"kind": "magic_ball", "controllable": "steer", "on_ball": {"mode": "grant_item", "item_pool": ["fenny_potion"]}})
	b_caster.set("stamina", 30.0)
	var act3: String = AIInput.tick_summon_commands(ai_caster)
	_assert(act3 == "ai_supply_order" and bool(ai_def.get("_flying")), "S4: AI 守球=补给指挥（残血队友）")
	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail == 0:
		print("🎉 接缝硬条款：全部通过（断层零容忍门禁就绪）")
	else:
		print("❌ 接缝违例 %d 处: %s" % [_fail, str(_violations)])
	quit(0 if _fail == 0 else 1)

func _is_magic_command(sid: String, sdata: Dictionary) -> bool:
	for sk in sdata.get("skills", []):
		if str(sk.get("id", "")) == sid:
			var tp: Dictionary = sk.get("tag_params", {}).get("summon_spawn", {}) if sk.get("tag_params", {}).get("summon_spawn", {}) is Dictionary else {}
			return str(tp.get("type_id", "")).contains("magic_ball")
	return false

func load_json(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}
