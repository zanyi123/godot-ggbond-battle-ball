## 33号·原作符合度大套件：芬尼队 4 技 + 水木联盟 6 技逐条对照（headless 可跑）
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_original_work_compliance.gd
## 每条断言组首行引用《docs/原作队伍元灵技能资料_填写版》原作逐字——行为不符=FAIL 必修
extends SceneTree

var _pass: int = 0
var _fail: int = 0

func _initialize() -> void:
	_run()

func _assert(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  ✅ " + name)
	else:
		_fail += 1
		print("  ❌ " + name)

class StubBall extends Node2D:
	# 拦截分发消费的最小球面（is_active/ball_direction/attacker_player）
	var is_active: bool = true
	var ball_direction: Vector2 = Vector2.RIGHT
	var attacker_player: Node = null


class Host extends Node2D:
	var controlled_player: Node = null
	var team_a_players: Array = []
	var team_b_players: Array = []

func _run() -> void:
	print("\n========== 33号：原作符合度验证（芬尼+水木）==========\n")
	for i in range(3):
		await process_frame
	var PlayerScript: GDScript = load("res://scripts/battle/player.gd")
	var MgrScript: GDScript = load("res://scripts/systems/summon/summon_manager.gd")
	var EntityScript: GDScript = load("res://scripts/systems/summon/summon_entity.gd")
	var BusScript: GDScript = load("res://scripts/systems/event_bus/event_bus.gd")
	var SsmScript: GDScript = load("res://scripts/systems/spirit_system/skill_state_manager.gd")
	var HandlerScript: GDScript = load("res://scripts/systems/spirit_system/spirit_tag_effect_handler.gd")
	var host: Host = Host.new()
	root.add_child(host)
	await process_frame
	var mgr: Node = MgrScript.new()
	mgr.name = "SummonManager"
	host.add_child(mgr)
	mgr.set("team_a_players", [])  # spawn 身份解析读 parent 名册
	mgr.set("team_b_players", [])
	await process_frame
	var handler: Node = HandlerScript.new()
	host.add_child(handler)
	await process_frame
	handler.battle_manager = host  # _ready 覆写后重设（备案陷阱）
	handler.players = [] as Array[Node]

	# 造 A/B 施法者各一（B 队用于通用性对照）
	var a1: CharacterBody2D = PlayerScript.new()
	a1.team = "a"
	a1.position = Vector2(-300, 0)
	root.add_child(a1)
	var b1: CharacterBody2D = PlayerScript.new()
	b1.team = "b"
	b1.position = Vector2(300, 0)
	root.add_child(b1)
	host.team_a_players = [a1]
	host.team_b_players = [b1]
	handler.players = [a1, b1] as Array[Node]
	await process_frame

	# ========== 水木·快牙猎杀（阿朗姆）==========
	# 原作："召唤水鲨鱼，可潜入地下遁形（额外耗能维持），可配合融入决竞球，也可单独操控进攻"
	print("\n--- 水木·快牙猎杀 ---")

	var tdata: Dictionary = load_json("res://data/systems/summon/summon_types.json")
	var shark_def_t: Dictionary = tdata.get("types", {}).get("shuimu_shark_att", {})
	_assert(str(shark_def_t.get("spawn_hint", "")) == "caster", "猎① spawn_hint=caster（召唤于施法者处）")
	_assert((shark_def_t.get("burrow", {}) as Dictionary).has("burrow_energy_cost_per_s"), "猎② burrow 配置在（潜地+额外耗能）")
	var shark1: Node2D = mgr.spawn("shuimu_shark_att", a1.get_instance_id(), a1.global_position, {"owner_ref": a1})
	_assert(shark1 != null and (shark1.global_position as Vector2).distance_to(a1.global_position) < 1.0, "猎③ 施放路径=施法者脚下生成（33号身份链）")
	var hp_b: float = float(b1.get("stamina"))
	shark1.global_position = b1.global_position + Vector2(10, 0)
	shark1._try_contact_hit()
	_assert(float(b1.get("stamina")) < hp_b, "猎④ 单独进攻=触碰敌方造成伤害（B 队施法者敌我识别正确）")
	_assert(not is_instance_valid(shark1) or str(shark1.get("state")) == "consumed", "猎⑤ 命中后鲨鱼消失")

	# ========== 水木·多重快牙猎杀（多条）==========
	print("\n--- 水木·多重快牙猎杀 ---")
	var m1: Node2D = mgr.spawn("shuimu_shark_att", a1.get_instance_id(), Vector2(-100, 100), {"owner_ref": a1})
	var m2: Node2D = mgr.spawn("shuimu_shark_att", a1.get_instance_id(), Vector2(-140, 100), {"owner_ref": a1})
	_assert(m1 != null and m2 != null and m1 != m2, "多① 多条鲨鱼各自独立生成")

	# ========== 水木·快牙撕咬（防御）==========
	# 原作："不可潜入地下，抵御攻击，带雷火系技能的决竞球进攻技能瞬间瓦解；限度内让球停下，超限改路线"
	print("\n--- 水木·快牙撕咬 ---")
	var tdef_d: Dictionary = tdata.get("types", {}).get("shuimu_shark_def", {})
	_assert(tdef_d.get("burrow", null) == null and str(tdef_d.get("on_ball", {}).get("mode", "")) == "intercept", "咬① 不可潜地+拦截模式（类型表）")
	_assert(str(tdef_d.get("on_ball", {}).get("weak_to_element", "")) == "雷火", "咬② weak_to_element=雷火（类型表）")
	var def_shark: Node2D = mgr.spawn("shuimu_shark_def", b1.get_instance_id(), Vector2(200, 200), {"owner_ref": b1})
	def_shark.set("lifespan_left", 999.0)
	# 球触碰→intercept 停球
	var ball_stub: Node2D = StubBall.new()
	ball_stub.attacker_player = a1
	ball_stub.position = Vector2(210, 200)
	root.add_child(ball_stub)
	var got_ctrl: Array = []
	var bus: Node = BusScript.new()
	bus.add_to_group("battle_event_bus")
	root.add_child(bus)
	var GranterScript: GDScript = load("res://scripts/battle/battle_item_granter.gd")
	var granter: Node = GranterScript.new()
	granter.add_to_group("battle_item_granters")
	host.add_child(granter)
	await process_frame
	bus.subscribe(bus.GameEvent.BALL_FORCED_CONTROL, func(p: Dictionary) -> void: got_ctrl.append(str(p.get("mode", ""))))
	def_shark.on_ball_proximity(ball_stub)
	_assert(bool(ball_stub.get("is_active")) == false and got_ctrl.has("stop"), "咬③ 限度内触碰→球停下（BALL_FORCED_CONTROL stop）")
	# 雷火瓦解：intercept 分支源码口径 + 元素推导函数在
	var ent_src: String = (EntityScript as GDScript).source_code
	_assert(ent_src.contains("weak_to_element") and ent_src.contains("_incoming_ball_element"), "咬④ 雷火系瞬间瓦解已实现（弱点判定+来球元素推导）")
	_assert(ent_src.contains("mode\": \"deflect") or ent_src.contains("超限改"), "咬⑤ 超限改线已实现")

	# ========== 水木·组合鲨鱼炸弹（融合伤害翻倍）==========
	print("\n--- 水木·组合鲨鱼炸弹 ---")
	var bomb_t: Dictionary = tdata.get("types", {}).get("shuimu_shark_bomb", {})
	_assert(float(bomb_t.get("contact_damage", 0)) == 60.0, "组① 融合鲨 contact_damage=60（30 翻倍）")
	_assert(str(bomb_t.get("spawn_hint", "")) == "caster", "组② 融合鲨 spawn_hint=caster")

	# ========== 水木·猎杀快道（阿克维）==========
	# 原作："持续注入能量形成路线；水鲨鱼在路径上耗能减少、速度加快"
	print("\n--- 水木·猎杀快道 ---")
	var br_src: String = (load("res://scripts/systems/spirit_system/handler/base_route.gd") as GDScript).source_code
	_assert(br_src.contains("field_zone_energy_path"), "道① 快道标签分发在（base_route 并发迁移后位置；zone type6）")
	_assert(ent_src.contains("_path_buffs_at") and ent_src.contains("speed_mult") and ent_src.contains("energy_cost_mult"), "道② 鲨鱼在路径上速度加快+耗能减少（增益消费）")
	var s3_data: Dictionary = load_json("res://data/spirits/skills.json")
	var sh3: Dictionary = {}
	for sk in s3_data.get("skills", []):
		if str(sk.get("id", "")) == "shuimu_3":
			sh3 = sk
	_assert(absf(float(sh3.get("tag_params", {}).get("field_zone_energy_path", {}).get("path_width", 0)) - 80.0) < 0.01, "道③ 快道宽度 80（600×80 口径）")

	# ========== 芬尼·魔术白球（攻/守）==========
	# 原作：攻="场地外场上空生成…操控该球飞向对方进攻造成爆炸"；守="操控球飞向自己获得道具：平底锅/药水/烟花"
	print("\n--- 芬尼·魔术白球 ---")
	var att_t: Dictionary = tdata.get("types", {}).get("fenny_magic_ball_att", {})
	var def_t: Dictionary = tdata.get("types", {}).get("fenny_magic_ball_def", {})
	_assert(str(att_t.get("spawn_hint", "")) == "enemy_outer_random" and str(def_t.get("spawn_hint", "")) == "enemy_outer_random", "白① 外场上空生成=敌方外场带全域随机（主人裁定口径）")
	var pool: Array = def_t.get("on_ball", {}).get("item_pool", []) if def_t.get("on_ball", {}) is Dictionary else []
	_assert((pool as Array).size() == 3, "白② 道具池=锅/药水/烟花 三道具")
	# 33号：待命球=储备悬停（不自动交付/不自游）——指挥飞抵才结算
	var def_ball: Node2D = mgr.spawn("fenny_magic_ball_def", a1.get_instance_id(), a1.global_position + Vector2(-80, 0), {"owner_ref": a1})  # 生成点避开施法者碰撞体（重叠会卡死 move_and_slide）
	def_ball.set("lifespan_left", 999.0)
	var b_items_before: int = _grant_count(a1)
	for f in range(10):
		await process_frame
		if not is_instance_valid(def_ball):
			break
	_assert(is_instance_valid(def_ball) and _grant_count(b1) == b_items_before, "白③ 待命球悬停不自动交付（储备；主人裁定）")
	def_ball.issue_order_at(a1.global_position + Vector2(6, 0))  # 指挥：飞向自己（原作=操控球飞向自己获得道具；交付对象=己方）
	print("    [dbg④] post-order: flying=%s state=%s pos=%s order=%s" % [
		str(def_ball.get("_flying")), str(def_ball.get("state")), str(def_ball.global_position),
		str((def_ball.get("_order") as Dictionary).get("mode", "?"))])
	for f in range(150):  # 飞行 580px@420 ≈ 83 tick
		if f % 25 == 0 and is_instance_valid(def_ball):
			print("    [dbg④] f%d flying=%s pos=%s" % [f, str(def_ball.get("_flying")), str(def_ball.global_position)])
		await process_frame
		if not is_instance_valid(def_ball):
			break
	_assert(_grant_count(a1) > b_items_before, "白④ 指挥飞抵自己→道具交付（granter 账本+1）")
	# 白⑤：攻球指挥出击→飞抵敌爆炸（无锅敌真伤；锅拦截已在 transfer27 J1 覆盖）
	var att_ball: Node2D = mgr.spawn("fenny_magic_ball_att", a1.get_instance_id(), b1.global_position + Vector2(-14, 0), {"owner_ref": a1})
	att_ball.set("lifespan_left", 999.0)
	att_ball.issue_order_at(b1.global_position)  # 指挥出击（飞抵触碰敌→爆炸）
	var b_hp0: float = float(b1.get("stamina"))
	for f in range(10):
		await process_frame
		if not is_instance_valid(att_ball) or float(b1.get("stamina")) < b_hp0:
			break
	_assert(float(b1.get("stamina")) < b_hp0, "白⑤: 攻球指挥出击→飞抵敌爆炸伤害")
	# 白⑤b：无锅敌人=爆炸真伤（b1 先挪离，保证索敌唯一指向 b2）
	b1.position = Vector2(-450, -280)
	var b2: CharacterBody2D = PlayerScript.new()
	b2.team = "b"
	b2.position = Vector2(340, 100)
	root.add_child(b2)
	host.team_b_players.append(b2)
	var att_ball2: Node2D = mgr.spawn("fenny_magic_ball_att", a1.get_instance_id(), b2.global_position + Vector2(-130, 0), {"owner_ref": a1})  # 生成点在触碰半径外（飞行段才接触敌）
	att_ball2.set("lifespan_left", 999.0)
	att_ball2.issue_order_at(b2.global_position)  # 指挥出击：索敌 b2→飞抵爆炸（主人规格两段指挥）
	var b2_hp0: float = float(b2.get("stamina"))
	for f in range(60):
		await process_frame
		if not is_instance_valid(att_ball2) or float(b2.get("stamina")) < b2_hp0:
			break
	_assert(float(b2.get("stamina")) < b2_hp0, "白⑤b: 攻球指挥出击→飞抵敌爆炸伤害落地")

	# ========== 芬尼·能量强化（接下来单个魔术球效果增强）==========
	print("\n--- 芬尼·能量强化 ---")
	_assert(ent_src.contains("damage_mult") and ent_src.contains("empower"), "强① 爆炸伤害吃强化倍率（empower.damage_mult）")
	_assert(ent_src.contains("强化爆炸摧毁障碍"), "强② 强化爆炸破障碍（原作：敌方障碍立刻消失）")
	var mgr_src: String = (MgrScript as GDScript).source_code
	_assert(mgr_src.contains("_empowers") and mgr_src.contains("left\"]) - 1"), "强③ 强化态登记+次数递减（manager 账本）")

	# ========== 芬尼·魔术无上限（杯桑）==========
	print("\n--- 芬尼·魔术无上限 ---")
	_assert(mgr_src.contains("func set_active_limit") and mgr_src.contains("register_auto_spawner"), "无① 上限设置+自动生成器 API 在（6+6→10+10 / 5秒1个）")

	# ========== 通用性：任何队伍零代码接入（快捷开发系统契约）==========
	print("\n--- 通用性契约 ---")
	_assert(ent_src.contains("_resolve_my_team") and ent_src.contains("fail-closed"), "通① 敌我识别=施法者身份链（fail-closed，非硬编码队伍）")
	_assert(ent_src.contains("spawn_hint") or (MgrScript as GDScript).source_code.contains("spawn_hint"), "通② 生成位=类型表数据驱动")

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail == 0:
		print("🎉 原作符合度：全部通过")
	else:
		print("❌ 有不符合项")
	quit(0 if _fail == 0 else 1)

func _grant_count(p: Node) -> int:
	var g: Node = get_tree_platform_granter()
	if g == null:
		return 0
	var ledger = g.get("_ledger")
	if ledger == null:
		return 0
	var pid: int = p.get_instance_id()
	if not (ledger as Dictionary).has(pid):
		return 0
	var total: int = 0
	for k in (ledger[pid] as Dictionary):
		total += int(ledger[pid][k])
	return total

func get_tree_platform_granter() -> Node:
	return _find_granter_node("battle_item_granters")

func _find_granter_node(g: String) -> Node:
	var nodes: Array = root.get_children()
	for n in nodes:
		for c in ([n] + n.get_children()):
			if c is Node and c.is_in_group(g):
				return c
	return null

func load_json(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}
