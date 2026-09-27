## 工单12 原作技能三连·完全体深度测试验收：合体/增益/印记全链
## 断言组：J-技能配置 / M-印记多阈值 / C-OP_COMBO合体 / L-平台装载 / R-纪律
## 依据：元灵技能AI规划/12_原作技能三连深度测试工单.md（主人四项裁决§三）
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_original_trio.gd
extends SceneTree

const SKILLS_PATH := "res://data/spirits/skills.json"
const REGISTRY_PATH := "res://data/spirits/tags_registry.json"
const LOADOUTS_PATH := "res://data/systems/spirit_ai/test_loadouts.json"
const HANDLER_PATH := "res://scripts/systems/spirit_system/spirit_tag_effect_handler.gd"
const STATE_MANAGER_PATH := "res://scripts/systems/spirit_system/skill_state_manager.gd"

const TRIO_IDS: Array[String] = [
	"skill_雷火_5", "skill_雷火_6", "skill_大地_3", "skill_金刚_2", "skill_金刚_3",
]
const LEGAL_OPS: Array[String] = [
	"OP_AUTO", "OP_AIM", "OP_POINT", "OP_MARK", "OP_STEER", "OP_MIDFLY",
	"OP_TOGGLE", "OP_KEY_JUMP", "OP_PLACE", "OP_SUMMON", "OP_FP", "OP_COMBO",
]

var _pass: int = 0
var _fail: int = 0


## 套件用球员桩：印记计数（镜像 player.gd 语义）+ 状态灯/增益记录
class StubTrioPlayer extends CharacterBody2D:
	var character_id: String = ""
	var team: String = "a"
	var is_defeated: bool = false
	var is_carrying_ball: bool = false
	var char_data: Dictionary = {"name": "stub"}
	var _marks: Dictionary = {}
	var lights_on: Array[String] = []
	var buffs: Array[Dictionary] = []

	func apply_mark(mark_id: String, max_stacks: int, duration: float) -> int:
		var cur: Dictionary = _marks.get(mark_id, {"count": 0})
		var count: int = int(cur.get("count", 0)) + 1
		_marks[mark_id] = {"count": count, "max_stacks": maxi(1, max_stacks), "remaining": duration}
		return count

	func get_mark_count(mark_id: String) -> int:
		return int(_marks.get(mark_id, {}).get("count", 0))

	func clear_mark(mark_id: String) -> void:
		_marks.erase(mark_id)

	func turn_on_light(status: String, duration: float, extra: Dictionary = {}) -> bool:
		lights_on.append(status)
		return true

	func is_status_active(status: String) -> bool:
		return status in lights_on

	func add_buff(buff_id: String, stat: String, mult: float, flat: float, duration: float, tag: String) -> void:
		buffs.append({"stat": stat, "mult": mult, "duration": duration})

	func get_and_consume_next_skill_mult() -> float:
		return 1.0


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== 工单12：原作技能三连（合体/增益/印记）全链验收 ==========\n")
	for i in range(3):
		await process_frame

	# ===== J-技能配置 =====
	var skills_text := FileAccess.get_file_as_string(SKILLS_PATH)
	var skills_data: Variant = JSON.parse_string(skills_text)
	_assert("J1: skills.json 可解析", typeof(skills_data) == TYPE_DICTIONARY)
	if typeof(skills_data) != TYPE_DICTIONARY:
		_finish()
		return
	var skills: Array = skills_data.get("skills", [])
	_assert("J2: 技能总数 24（工单12五技+波E实证四技+工单19操控两技等演进）", skills.size() == 24)
	var by_id: Dictionary = {}
	for s in skills:
		if typeof(s) == TYPE_DICTIONARY:
			by_id[str(s.get("id", ""))] = s
	var ids_ok := true
	for tid in TRIO_IDS:
		if not by_id.has(tid):
			ids_ok = false
			print("    [缺技能] " + tid)
	_assert("J3: 五新技能齐备", ids_ok)

	var reg_text := FileAccess.get_file_as_string(REGISTRY_PATH)
	var reg: Variant = JSON.parse_string(reg_text)
	var reg_by_id: Dictionary = {}
	if typeof(reg) == TYPE_DICTIONARY:
		for t in reg.get("tags", []):
			if typeof(t) == TYPE_DICTIONARY:
				reg_by_id[str(t.get("id", ""))] = t
	_assert("J4: tags_registry 104 条（103+combo_ready）", reg_by_id.size() == 104)
	_assert("J5: 新标签 player_combo_ready 已注册（19b10）", reg_by_id.has("player_combo_ready") and str(reg_by_id.get("player_combo_ready", {}).get("code", "")) == "19b10")

	var tags_ok := true
	var params_ok := true
	var ops_ok := true
	for tid in TRIO_IDS:
		var s: Dictionary = by_id.get(tid, {})
		for t in s.get("tags", []):
			if not reg_by_id.has(str(t)):
				tags_ok = false
				print("    [标签未注册] %s.%s" % [tid, str(t)])
			var tp: Dictionary = s.get("tag_params", {}).get(str(t), {})
			var reg_params: Array = reg_by_id.get(str(t), {}).get("params", [])
			for k in tp.keys():
				if not (reg_params as Array).has(str(k)):
					params_ok = false
					print("    [params越界] %s.%s.%s" % [tid, str(t), str(k)])
		if str(s.get("operator", "")) not in LEGAL_OPS:
			ops_ok = false
	_assert("J6: 五技能标签全部已注册", tags_ok)
	_assert("J7: tag_params 键逐一在 registry params", params_ok)
	_assert("J8: operator 全部合法（半技能=OP_COMBO）", ops_ok and str(by_id.get("skill_金刚_2", {}).get("operator", "")) == "OP_COMBO")

	var mk_qilin: Dictionary = by_id.get("skill_雷火_5", {}).get("tag_params", {}).get("player_mark_apply", {})
	var mk_sanwei: Dictionary = by_id.get("skill_雷火_6", {}).get("tag_params", {}).get("player_mark_apply", {})
	_assert("J9: 印记链同 mark_id=huo_yinji 跨技叠加 + max_stacks=3", str(mk_qilin.get("mark_id", "")) == "huo_yinji" and str(mk_sanwei.get("mark_id", "")) == "huo_yinji" and int(mk_qilin.get("max_stacks", 0)) == 3)
	var ths: Array = mk_qilin.get("thresholds", [])
	var th_ok: bool = ths.size() == 2
	var th_tags: Array[String] = []
	if th_ok:
		for th in ths:
			if typeof(th) != TYPE_DICTIONARY:
				th_ok = false
				break
			var thd: Dictionary = th
			if int(thd.get("count", 0)) <= 0 or str(thd.get("tag", "")) == "" or typeof(thd.get("params", {})) != TYPE_DICTIONARY:
				th_ok = false
				break
			th_tags.append(str(thd.get("tag", "")))
			if not reg_by_id.has(str(thd.get("tag", ""))):
				th_ok = false
				break
	_assert("J10: 印记 thresholds 两层合法（2→heal_block / 3→field_zone_danger）", th_ok and th_tags.has("player_heal_block") and th_tags.has("field_zone_danger"))
	var secret: Dictionary = by_id.get("skill_大地_3", {}).get("tag_params", {})
	_assert("J11: 祖传秘法攻防双buff 40%/10s", int(secret.get("player_atk_up_pct", {}).get("value", 0)) == 40 and int(secret.get("player_def_up_pct", {}).get("value", 0)) == 40 and float(secret.get("player_atk_up_pct", {}).get("duration", 0)) == 10.0)
	var armor_p: Dictionary = by_id.get("skill_金刚_2", {}).get("tag_params", {}).get("player_combo_ready", {})
	var cannon_p: Dictionary = by_id.get("skill_金刚_3", {}).get("tag_params", {}).get("player_combo_ready", {})
	_assert("J12: 坦克两半同 combo_id + role 互补 + 距离/时长合法", str(armor_p.get("combo_id", "")) == "combo_heavy_tank" and str(cannon_p.get("combo_id", "")) == "combo_heavy_tank" and str(armor_p.get("role", "")) != str(cannon_p.get("role", "")) and float(armor_p.get("combo_range", 0)) > 0.0 and float(armor_p.get("duration", 0)) > 0.0)

	# ===== M-印记多阈值（handler 全链） =====
	var handler: Node = load(HANDLER_PATH).new()
	root.add_child(handler)
	handler.priority_queue_enabled = false  # 套件即时断言：关闭优先级队列窗口（平台同款开关），标签效果直执行
	var caster: StubTrioPlayer = StubTrioPlayer.new()
	caster.character_id = "t_mark_caster"
	caster.team = "a"
	caster.position = Vector2(0, 0)
	root.add_child(caster)
	var near_foe: StubTrioPlayer = StubTrioPlayer.new()
	near_foe.character_id = "t_mark_foe_near"
	near_foe.team = "b"
	near_foe.position = Vector2(120, 0)
	root.add_child(near_foe)
	var far_foe: StubTrioPlayer = StubTrioPlayer.new()
	far_foe.character_id = "t_mark_foe_far"
	far_foe.team = "b"
	far_foe.position = Vector2(900, 0)
	root.add_child(far_foe)
	handler.players = _node_array([caster, near_foe, far_foe])
	var caster_id: int = caster.get_instance_id()

	_assert("M1: registry mark_apply params 含 thresholds", (reg_by_id.get("player_mark_apply", {}).get("params", []) as Array).has("thresholds"))

	var mk_params: Dictionary = mk_qilin.duplicate(true)
	var mk_apply: Dictionary = {"target": "self"}
	mk_apply.merge(mk_params, true)
	handler._apply_player_mark_apply(mk_apply, caster_id)
	_assert("M2: 首次施法→1层无层触发（近敌无禁疗灯）", caster.get_mark_count("huo_yinji") == 1 and near_foe.lights_on.is_empty())
	handler._apply_player_mark_apply(mk_apply, caster_id)
	_assert("M3: 二次施法→2层→heal_block 层触发（近敌禁疗灯）", caster.get_mark_count("huo_yinji") == 2 and near_foe.lights_on.has("heal_block"))
	_assert("M4: heal_block 目标=nearest_enemy（远敌无灯）", not far_foe.lights_on.has("heal_block"))
	var near_lights_before: int = near_foe.lights_on.size()
	handler._apply_player_mark_apply(mk_apply, caster_id)
	_assert("M5: 三次施法→3层（heal 累计语义再触发；zone 生成依赖 FieldZoneManager，headless fail-closed 不崩溃）", caster.get_mark_count("huo_yinji") == 3 and near_foe.lights_on.size() == near_lights_before + 1)

	var mk_single: Dictionary = {
		"target": "self", "mark_id": "mark_old", "max_stacks": 2, "duration": 5.0,
		"threshold_count": 1, "threshold_tag": "player_heal_block",
		"threshold_params": {"duration": 4.0, "target": "self"},
	}
	handler._apply_player_mark_apply(mk_single, caster_id)
	_assert("M6: 旧单阈值兼容路径仍生效", caster.get_mark_count("mark_old") == 1 and caster.lights_on.has("heal_block"))
	var mk_both: Dictionary = {
		"target": "self", "mark_id": "mark_both", "max_stacks": 2, "duration": 5.0,
		"threshold_count": 1, "threshold_tag": "player_heal_block", "threshold_params": {"duration": 4.0, "target": "self"},
		"thresholds": [{"count": 1, "tag": "player_heal_block", "params": {"duration": 4.0, "target": "self"}, "clear": false}],
	}
	var foe_lights_before: int = far_foe.lights_on.size()
	handler._apply_player_mark_apply(mk_both, caster_id)
	_assert("M7: thresholds 优先不重复触发（单阈值路径被屏蔽）", far_foe.lights_on.size() == foe_lights_before)

	# ===== C-OP_COMBO 合体协调器 =====
	var sm: Node = load(STATE_MANAGER_PATH).new()
	root.add_child(sm)
	_assert("C1: 协调器入组 skill_state_managers", sm.is_in_group("skill_state_managers"))

	var a1: StubTrioPlayer = StubTrioPlayer.new()
	a1.character_id = "t_armor"
	a1.team = "a"
	a1.position = Vector2(0, 0)
	root.add_child(a1)
	var a2: StubTrioPlayer = StubTrioPlayer.new()
	a2.character_id = "t_cannon"
	a2.team = "a"
	a2.position = Vector2(100, 0)
	root.add_child(a2)
	var far_ally: StubTrioPlayer = StubTrioPlayer.new()
	far_ally.character_id = "t_far_ally"
	far_ally.team = "a"
	far_ally.position = Vector2(1000, 0)
	root.add_child(far_ally)
	var foe: StubTrioPlayer = StubTrioPlayer.new()
	foe.character_id = "t_foe"
	foe.team = "b"
	foe.position = Vector2(50, 0)
	root.add_child(foe)

	var p_armor: Dictionary = {"combo_id": "combo_t", "role": "armor", "duration": 1.0, "combo_range": 150.0, "def_up_pct": 40.0, "spd_up_pct": 25.0, "ball_dmg_up_pct": 35.0}
	var p_cannon: Dictionary = {"combo_id": "combo_t", "role": "cannon", "duration": 1.0, "combo_range": 150.0}
	var p_other: Dictionary = {"combo_id": "combo_other", "role": "cannon", "duration": 1.0, "combo_range": 150.0}
	var p_same_role: Dictionary = {"combo_id": "combo_t", "role": "armor", "duration": 1.0, "combo_range": 150.0}

	sm.register_combo_ready(a1.get_instance_id(), a1, p_armor)
	sm.register_combo_ready(far_ally.get_instance_id(), far_ally, p_same_role)
	_assert("C2: 同 role 不合体", sm.try_form_combos() == 0)
	sm.unregister_combo_ready(far_ally.get_instance_id())
	sm.register_combo_ready(far_ally.get_instance_id(), far_ally, p_other)
	_assert("C3: 不同 combo_id 不合体", sm.try_form_combos() == 0)
	sm.unregister_combo_ready(far_ally.get_instance_id())
	far_ally.position = Vector2(30, 0)
	sm.register_combo_ready(far_ally.get_instance_id(), far_ally, {"combo_id": "combo_t", "role": "cannon", "duration": 1.0, "combo_range": 150.0})
	far_ally.team = "b"
	_assert("C4: 异队不合体", sm.try_form_combos() == 0)
	far_ally.team = "a"
	far_ally.position = Vector2(1000, 0)
	_assert("C5: 距离>combo_range 不合体", sm.try_form_combos() == 0)
	sm.unregister_combo_ready(far_ally.get_instance_id())

	var formed_sig: Array = []
	sm.combo_formed.connect(func(cid: String, members: Array, params: Dictionary) -> void: formed_sig.append(cid))
	sm.register_combo_ready(a1.get_instance_id(), a1, p_armor)
	sm.register_combo_ready(a2.get_instance_id(), a2, p_cannon)
	_assert("C6: 互补+同队+近距→自动合体×1", sm.try_form_combos() == 1 and formed_sig.size() == 1)
	_assert("C7: 合体态登记（remaining>0）+ 双方就绪清空", (sm.get_combo_states().get("combo_t", {}).get("remaining", 0.0) as float) > 0.0 and sm.get_combo_readies().is_empty())
	var broken_log: Array = []
	sm.combo_broken.connect(func(cid: String, members: Array) -> void: broken_log.append(members))
	sm._process(2.0)
	_assert("C8: 合体到期拆分（信号+态清空）", broken_log.size() == 1 and (broken_log[0] as Array).size() == 2 and sm.get_combo_states().is_empty())
	a1.is_defeated = true
	sm.register_combo_ready(a1.get_instance_id(), a1, p_armor)
	sm._process(0.01)
	_assert("C9: 死亡者就绪被清扫", not sm.get_combo_readies().has(a1.get_instance_id()))
	sm.unregister_combo_ready(a1.get_instance_id())

	# C10：handler→协调器→信号→增益 全链（参数镜像 skills.json 重型坦克配置）
	var full_armor: Dictionary = by_id.get("skill_金刚_2", {}).get("tag_params", {}).get("player_combo_ready", {})
	var full_cannon: Dictionary = by_id.get("skill_金刚_3", {}).get("tag_params", {}).get("player_combo_ready", {})
	var h_armor: StubTrioPlayer = StubTrioPlayer.new()
	h_armor.character_id = "t_full_armor"
	h_armor.team = "a"
	h_armor.position = Vector2(0, 0)
	root.add_child(h_armor)
	var h_cannon: StubTrioPlayer = StubTrioPlayer.new()
	h_cannon.character_id = "t_full_cannon"
	h_cannon.team = "a"
	h_cannon.position = Vector2(80, 0)
	root.add_child(h_cannon)
	handler.players = _node_array([h_armor, h_cannon])
	handler._apply_player_combo_ready(full_armor, h_armor.get_instance_id())
	handler._apply_player_combo_ready(full_cannon, h_cannon.get_instance_id())
	_assert("C10a: 半装经标签流登记到协调器", sm.get_combo_readies().size() == 2)
	var n_formed: int = sm.try_form_combos()
	_assert("C10b: 全链自动合体成立", n_formed == 1 and sm.get_combo_states().has("combo_heavy_tank"))
	_assert("C10c: 合体增益=双方 def/spd buff（标签流施加）", h_armor.buffs.size() >= 2 and h_cannon.buffs.size() >= 2)
	var mods_armor: Dictionary = handler._ball_mods_by_caster.get(h_armor.get_instance_id(), {})
	_assert("C10d: 炮弹增伤入准备区（dmg_mult≈1.35）", absf(float(mods_armor.get("dmg_mult", 0.0)) - 1.35) < 0.001)
	sm._process(10.0)
	_assert("C10e: 合体期到→拆分（增益随 buff 时长自然到期）", sm.get_combo_states().is_empty())
	sm.cleanup_player(h_armor.get_instance_id())
	_assert("C11: cleanup_player 清半装", not sm.get_combo_readies().has(h_armor.get_instance_id()))

	# ===== L-平台装载 =====
	var lo_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOADOUTS_PATH))
	_assert("L1: test_loadouts.json 可解析", typeof(lo_data) == TYPE_DICTIONARY)
	var test_spirits: Array = lo_data.get("test_spirits", []) if typeof(lo_data) == TYPE_DICTIONARY else []
	var spirit_names: Dictionary = {}
	var spirit_skills_ok := true
	for sp in test_spirits:
		if typeof(sp) != TYPE_DICTIONARY:
			continue
		spirit_names[str(sp.get("name", ""))] = sp
		for sid in sp.get("skills", []):
			if not by_id.has(str(sid)):
				spirit_skills_ok = false
				print("    [装载引用悬空] %s → %s" % [str(sp.get("name", "")), str(sid)])
	_assert("L2: 四原作元灵齐备（墨麟/狐赖/狐宇/泰格）", spirit_names.has("墨麟的元灵") and spirit_names.has("狐赖的元灵") and spirit_names.has("狐宇的元灵") and spirit_names.has("泰格的元灵"))
	_assert("L3: test_spirits 技能引用零悬空", spirit_skills_ok)
	var loadouts: Array = lo_data.get("loadouts", [])
	var lo_ok: bool = loadouts.size() == 6
	var a1_name := ""
	var a2_name := ""
	for lo in loadouts:
		if typeof(lo) != TYPE_DICTIONARY:
			lo_ok = false
			continue
		if not spirit_names.has(str(lo.get("spirit_id", ""))):
			lo_ok = false
			print("    [loadouts 引用未知名] " + str(lo.get("spirit_id", "")))
		if str(lo.get("slot", "")) == "A1":
			a1_name = str(lo.get("spirit_id", ""))
		if str(lo.get("slot", "")) == "A2":
			a2_name = str(lo.get("spirit_id", ""))
	_assert("L4: loadouts 6 槽引用全部合法", lo_ok)
	_assert("L5: 合体对同队同槽组（A1=狐赖/A2=狐宇）", a1_name == "狐赖的元灵" and a2_name == "狐宇的元灵")

	# ===== R-纪律 =====
	var src_base := FileAccess.get_file_as_string("res://scripts/systems/spirit_system/handler/base_route.gd")
	_assert("R1: base_route 含 player_combo_ready 分发臂", src_base.find("player_combo_ready") != -1)
	var src_pr := FileAccess.get_file_as_string("res://scripts/systems/spirit_system/handler/player_route.gd")
	_assert("R2: player_route 含 thresholds 多层实现", src_pr.find("thresholds") != -1)
	var src_sm := FileAccess.get_file_as_string(STATE_MANAGER_PATH)
	_assert("R3: skill_state_manager 无 randf(/randi(（确定性铁律不回退）", src_sm.find("randf(") == -1 and src_sm.find("randi(") == -1)
	_assert("R4: registry player_mark_apply description 载明 thresholds 语义", str(reg_by_id.get("player_mark_apply", {}).get("description", "")).find("thresholds") != -1)

	_finish()


func _finish() -> void:
	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 全部通过！（工单12交付门槛达成）")
	quit(1 if _fail > 0 else 0)


func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)


## base_route.players 为 Array[Node] 类型化数组——无类型字面量直接赋值会运行时报错
func _node_array(nodes: Array) -> Array[Node]:
	var out: Array[Node] = []
	for n in nodes:
		out.append(n)
	return out
