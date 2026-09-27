## 22-1 金路径场景测试（技能规划/22）：真实 battle_arena 一条龙——
## 装备→开赛→释放印记球技→必中锁定命中敌人→被打者印记落地+HUD反射→反例清空
## 设计：不挪任何球员（越界传送系统会对抗），球用 lockon+sure_hit 追踪 victim（既有球特性）
## 数据：临时测试技测试内构造（备份→写→还原，R1）；有窗口屏显
extends Node

var bm: Node = null
var results: Array = []
var _raw_backup: String = ""
var _spirits_backup: String = ""

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	bm = get_tree().root.get_node_or_null("GoldenPath/Arena")
	if bm == null:
		for c in get_tree().root.get_children():
			if c.get_script() and str(c.get_script().resource_path).contains("battle_manager"):
				bm = c
				break
	if bm == null:
		_finish("FAIL: 未找到 battle_manager")
		return
	_run()

func _run() -> void:
	var DataManager = get_tree().root.get_node_or_null("DataManager")

	# ===== 数据准备（R1：备份在先；临时印记球技挂玲珑）=====
	_raw_backup = FileAccess.get_file_as_string("res://data/spirits/skills.json")
	_spirits_backup = FileAccess.get_file_as_string("res://data/spirits/spirits.json")
	var skills: Array = DevDataSync.load_skills()
	# 幂等数据准备：先清历史泄漏的测试技（上一轮崩溃可能跳过还原），再新建（R6：只动本批登记 id）
	var GP_IDS := ["gp_frost", "gp_stealth"]
	var cleaned: Array = []
	for s in skills:
		if not (s is Dictionary) or not (str(s.get("id", "")) in GP_IDS):
			cleaned.append(s)
	skills = cleaned
	skills.append({"id": "gp_frost", "name": "冰霜粉末(测)", "type": "active", "element": "冰雪",
		"tags": ["player_mark_apply"], "tag_params": {"player_mark_apply": {"mark_id": "frost", "max_stacks": 5, "duration": 8.0}},
		"operator": "OP_AUTO", "energy_cost": 5.0, "cooldown": 0.0, "description": "t"})
	skills.append({"id": "gp_stealth", "name": "隐身术(测)", "type": "active", "element": "冰雪",
		"tags": ["player_stealth"], "tag_params": {"player_stealth": {"duration": 4.0}},
		"operator": "OP_AUTO", "energy_cost": 5.0, "cooldown": 0.0, "description": "t"})
	DevDataSync.save_skills(skills)
	var spirits: Array = DevDataSync.load_spirits()
	for sp in spirits:
		if str(sp.get("id")) == "spirit_leihuo":
			var sk: Array = sp.get("skills", [])
			if "gp_frost" not in sk:
				sk.append("gp_frost")
			if "gp_stealth" not in sk:
				sk.append("gp_stealth")
			sp["skills"] = sk
	DevDataSync.save_spirits(spirits)
	DataManager.load_all_data()
	# 失效 trigger 的 skills 缓存（_skills_cache/_skills_loaded），确保新测试技可读
	var _spirit_sys = get_tree().root.get_node_or_null("GoldenPath/Arena").get("spirit_system")
	if _spirit_sys != null and _spirit_sys.get("skill_trigger") != null:
		_spirit_sys.skill_trigger._skills_loaded = false
		_spirit_sys.skill_trigger._skills_cache.clear()
	await get_tree().process_frame

	# ===== 装备玲珑（正式链路）+ 关标签队列（确定性：生产队列 flush 会被进球暂停冻结）=====
	var pa: CharacterBody2D = bm.team_a_players[0]
	pa.equip_spirit({"id": "spirit_leihuo", "name": "玲珑", "skills": ["gp_frost", "gp_stealth"]})
	var ss = bm.spirit_system
	if ss and ss.skill_trigger:
		ss.skill_trigger.set_player_skills(pa.get_instance_id(), pa.get_equipped_skills())
	if ss and ss.get("tag_effect_handler") != null:
		ss.tag_effect_handler.priority_queue_enabled = false
	bm._on_prep_match_started()
	await _wait(2.0)
	var ss2 = bm.spirit_system
	_check(ss2 != null and ss2.skill_trigger != null, "开赛: spirit_system 注入（正式链路）")
	# 受控环境：停双 AI（普通跑位+技能AI 指挥，含待接球姿态切换）——
	# 否则 B 队开待接球会把锁定球接走（接球判定优先于命中，正确防守语义）
	if bm.get("spirit_ai_manager") != null:
		bm.spirit_ai_manager.set_physics_process(false)
		bm.spirit_ai_manager.set_process(false)
	if bm.get("ai_manager") != null:
		bm.ai_manager.set_physics_process(false)
		bm.ai_manager.set_process(false)
	_check("gp_frost" in pa.get_equipped_skills(), "装备: 印记球技在球员名册")

	# ===== ① 整机命中链（顺势：球必中锁定 victim，不挪任何人）=====
	var victim: CharacterBody2D = _find_player("超人强")
	var victim_bar: Control = load("res://scripts/battle/status_icon_bar.gd").new()
	get_tree().root.add_child(victim_bar)
	victim_bar.bind_player(victim)
	var ok_cast: bool = ss2.use_skill(pa.get_instance_id(), "gp_frost")
	await _wait(0.2)
	_check(ok_cast, "释放: 印记球技 use_skill 成功（随球暂存，不挂施法者）")
	_assert_self_clean(pa, "①: 施法者无印记（暂存不挂己）")
	var ball = bm.ball_node
	# 清残留接球姿态（停 AI 前置位的 is_ready_to_catch 会把球接走——接球判定优先于命中）
	victim.is_ready_to_catch = false
	if victim.has_method("exit_catch_state"):
		victim.exit_catch_state()
	if ball and ball.has_method("launch"):
		ball.launch(pa.global_position, Vector2(0.0, 1.0).normalized(), 30.0, 400.0, pa)
		ball.ball_mods["lockon_target"] = victim
		ball.ball_mods["sure_hit"] = true
	# 轮询等待命中落地（球追踪飞行时长不定；最多 3s）
	for poll in range(15):
		await _wait(0.2)
		if victim.get_mark_count("frost") >= 1:
			break
	_assert_hit(victim, "①: 球命中→被打者印记落地")

	# ===== ①+ HUD 反射（判定→可视）=====
	await get_tree().process_frame
	var icon_on: bool = "mark_frost" in victim_bar.get_entry_keys()
	_check(icon_on, "①: HUD 图标条出现\"印\"图标（判定→可视同步）")

	# ===== ② 可视反射②：自身 buff→释放者 HUD 图标条（隐身）=====
	var ok3: bool = ss2.use_skill(pa.get_instance_id(), "gp_stealth")
	await _wait(0.3)
	var hud2: Control = bm.get_node_or_null("UILayer/HUD")
	var self_bar: Control = null
	if hud2 and hud2._status_icon_bars.size() > 0:
		self_bar = hud2._status_icon_bars[0]
	var stealth_icon := false
	if self_bar != null and bm.team_a_players[0] == pa:
		stealth_icon = "stealthed" in self_bar.get_entry_keys()
	var pa_stealth: bool = pa.is_status_active("stealthed")
	var dbg_keys: Array = self_bar.get_entry_keys() if self_bar != null else []
	_check(ok3 and pa_stealth and stealth_icon, "②: 隐身判定+HUD\"隐\"图标 (ok3=%s pa灯=%s keys=%s)" % [str(ok3), str(pa_stealth), str(dbg_keys)])

	# ===== ③ 反例：未命中（球耗尽清空）→ 无人被挂印 =====
	var marks_before: int = _find_player("超人强").get_mark_count("frost")
	var ok2: bool = ss2.use_skill(pa.get_instance_id(), "gp_frost")
	if bm.ball_node and bm.ball_node.has_method("launch"):
		# 未命中方向：朝无人区（B 队全部在下方场内，向上投）——球耗尽即清空
		bm.ball_node.launch(pa.global_position, Vector2(0.0, -1.0).normalized(), 30.0, 130.0, pa)
	await _wait(1.0)
	var marks_after: int = _find_player("超人强").get_mark_count("frost")
	_check(ok2 and marks_after == marks_before, "③: 未命中→暂存清空无人挂印 (before=%d after=%d ok2=%s)" % [marks_before, marks_after, str(ok2)])

	await _shot("golden_path")

	# ===== 数据还原（R1）=====
	var wf := FileAccess.open("res://data/spirits/skills.json", FileAccess.WRITE)
	wf.store_string(_raw_backup)
	wf.close()
	var wf2 := FileAccess.open("res://data/spirits/spirits.json", FileAccess.WRITE)
	wf2.store_string(_spirits_backup)
	wf2.close()
	_check(FileAccess.get_file_as_string("res://data/spirits/skills.json") == _raw_backup 		and FileAccess.get_file_as_string("res://data/spirits/spirits.json") == _spirits_backup,
		"落盘清洁: skills.json + spirits.json 双还原一致")
	_finish("DONE")

func _assert_self_clean(pa: CharacterBody2D, what: String) -> void:
	_check(pa.get_mark_count("frost") == 0, what)

func _assert_hit(victim: CharacterBody2D, what: String) -> void:
	_check(victim.get_mark_count("frost") >= 1, what)


func _find_player(pname: String) -> CharacterBody2D:
	for team in [bm.team_a_players, bm.team_b_players]:
		for p in team:
			if p and is_instance_valid(p) and str(p.char_data.get("name", "")) == pname:
				return p
	return null

func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img and not img.is_empty() and img.get_width() > 4:
		img.save_png("res://docs/img/golden_path_%s.png" % name)
		print("[GoldenPath] 截图: docs/img/golden_path_%s.png" % name)

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _check(ok: bool, what: String) -> void:
	results.append({"ok": ok, "what": what})
	print(("[GoldenPath] ✅ PASS: " if ok else "[GoldenPath] ❌ FAIL: ") + what)

func _pass_n() -> int:
	var n := 0
	for r in results:
		if r.ok:
			n += 1
	return n

func _finish(msg: String) -> void:
	print("[GoldenPath] ====== %s | %d/%d PASS ======" % [msg, _pass_n(), results.size()])
	get_tree().quit(0 if _pass_n() == results.size() else 1)
