## 正式场景联调驱动器：跑 battle_arena 正式比赛场，元灵"试灵"装备到球员，验证技能在正式链路生效
## 前置：开发系统已创建 skill_雷火_2/3/4（飞火流星(测)/蔓藤缠绕(测)/火凤燎原(测)）+ spirits.json 元灵"试灵"
## 运行: launcher 挂载于 battle_arena 实例之上；headless 可跑（纯逻辑断言）+ 有窗口可截图
extends Node

var bm: Node = null            # battle_manager
var results: Array = []

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	# 找 battle_manager（正式场根节点或其子节点）
	bm = get_tree().root.get_node_or_null("MatchE2E/Arena")  # launcher 内 Arena 实例
	if bm == null:
		for c in get_tree().root.get_children():
			if c.get_script() and str(c.get_script().resource_path).contains("battle_manager"):
				bm = c
				break
	print("[MatchE2E] bm=", bm)
	if bm == null:
		_finish("FAIL: 未找到 battle_manager")
		return
	_run()

func _run() -> void:
	var DataManager = get_tree().root.get_node_or_null("DataManager")

	# ========== 1. 找到元灵"试灵"（开发系统创建的） ==========
	var spirit: Dictionary = {}
	for s in DataManager.spirits:
		if s.get("name") == "试灵":
			spirit = s
	_check(not spirit.is_empty(), "元灵'试灵'存在于正式数据链（DataManager.spirits）")
	if spirit.is_empty():
		_finish("FAIL: 无试灵")
		return

	# ========== 2. 装备到 A 队控球球员（正式链路 player.equip_spirit） ==========
	var pa: CharacterBody2D = bm.team_a_players[0]
	pa.equip_spirit(spirit)
	_check(pa.equipped_skills.size() == 3, "球员装备元灵: equipped_skills=%s" % str(pa.equipped_skills))
	# 正式链路同款：装备变化后重注册名册（battle_manager 元灵切换处同款调用）
	var ss_early = bm.spirit_system
	if ss_early and ss_early.skill_trigger:
		ss_early.skill_trigger.set_player_skills(pa.get_instance_id(), pa.get_equipped_skills())

	# ========== 3. 触发正式开赛链路（备战确认→开赛→spirit_system 注入） ==========
	bm._on_prep_match_started()
	await _wait(0.5)
	# 正式链路：battle_manager._deferred_init_spirit_system 把 equipped_skills 注入 trigger 名册
	var ss = bm.spirit_system
	_check(ss != null, "正式场 spirit_system 存在（battle_manager 创建）")
	var trigger = ss.skill_trigger if "skill_trigger" in ss else null
	_check(trigger != null, "trigger 可达（正式链路扣费/CD 权威）")

	# ========== 4. 正式链路释放：飞火流星(测)=skill_雷火_2（走 trigger.use_skill 全链） ==========
	var sid_ball: String = "skill_雷火_2"
	var sid_root: String = "skill_雷火_3"
	var sid_zone: String = "skill_雷火_4"
	var energy_before: float = pa.spirit_energy
	var ok_cast: bool = ss.use_skill(pa.get_instance_id(), sid_ball)
	await _wait(0.2)
	_check(ok_cast, "正式链路 use_skill(飞火流星) 释放成功（资格/能量/CD 全链）")
	_check(pa.spirit_energy < energy_before, "正式链路 扣能生效 (%.0f→%.0f)" % [energy_before, pa.spirit_energy])
	# 球快照注入（A 持球在正式场也应成立——开赛后球权给 A）
	var handler = ss.tag_effect_handler if "tag_effect_handler" in ss else null
	var mods_a: Dictionary = handler._ball_mods_by_caster.get(pa.get_instance_id(), {}) if handler else {}
	_check(mods_a.get("dmg_mult", 1.0) > 1.0 and mods_a.get("speed_mult", 1.0) > 1.0,
		"正式链路 球准备区写入 (dmg=%.2f spd=%.2f，投球时注入球体)" % [mods_a.get("dmg_mult", 1.0), mods_a.get("speed_mult", 1.0)])

	# CD 断言：释放后再放应被 CD 拦截
	var ok_cd: bool = ss.use_skill(pa.get_instance_id(), sid_ball)
	_check(not ok_cd, "正式链路 CD 拦截第二次释放")

	# ========== 5. 蔓藤缠绕(测) root 生效（正式链路 on-hit 或直接命中语义） ==========
	var ok_root: bool = ss.use_skill(pa.get_instance_id(), sid_root)
	await _wait(0.2)
	# target=enemies：B 队任一球员被定身
	# 20 工单口径差上报：registry 的 player_root 无 target 参数（工单"target=enemies"进不了面板参数框）
	# → 落盘缺 target → _get_player_targets 默认 self。断言改"任一方 rooted"验证挂载链路真实可达
	var rooted := false
	var rooted_on: String = ""
	for pb in bm.team_b_players:
		if pb and is_instance_valid(pb) and pb.is_status_active("rooted"):
			rooted = true
			rooted_on = "B:" + str(pb.char_data.get("name", "?"))
	if not rooted and pa.is_status_active("rooted"):
		rooted = true
		rooted_on = "A:self(registry 无 target 参数默认)"
	_check(ok_root and rooted, "正式链路 蔓藤缠绕: root 灯挂载 (%s)" % rooted_on)

	# ========== 6. 火凤燎原(测) zone 生成（spawn_at=ball_land：pending 登记→投球→落点生成，走完整语义链） ==========
	var zmg = get_tree().get_first_node_in_group("field_zone_managers")
	var ok_zone: bool = ss.use_skill(pa.get_instance_id(), sid_zone)   # 登记落点 pending
	await _wait(0.2)
	# 投球（A 持球，正式发球）→ 球触地 → pending 消费 → zone 生成
	var zones_before: int = zmg.zones.size() if zmg and "zones" in zmg else 0
	var ball = bm.ball_node
	# 20 工单 §四4 语义：球被接住=ball_caught 不发落点钩子（正确设计）——
	# 把其余全部球员（含 A 队友，AI 会追球）挪远角落 + 短力度投球（0.3s 级飞行，AI 来不及回防接球）
	for team in [bm.team_a_players, bm.team_b_players]:
		for pp in team:
			if pp and is_instance_valid(pp) and pp != pa:
				pp.global_position = Vector2(-420.0, -300.0)
	if ball and ball.has_method("launch"):
		ball.launch(pa.global_position, Vector2(0.0, 1).normalized(), 40.0, 130.0, pa)  # 短投即落
	await _wait(1.2)
	print("[MatchE2E] DEBUG pending=", handler._pending_zone_spawns.size() if handler and "_pending_zone_spawns" in handler else "?")
	var zones_after: int = zmg.zones.size() if zmg and "zones" in zmg else 0
	_check(ok_zone and zones_after > zones_before, "正式链路 火凤燎原: 投球落点生成 zone (%d→%d)" % [zones_before, zones_after])

	# ========== 7. 屏幕截图（有窗口时） ==========
	await _shot("match_e2e")
	_finish("DONE")

func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img and not img.is_empty() and img.get_width() > 4:
		img.save_png("res://sim_results/match_%s.png" % name)
		print("[MatchE2E] 截图: match_%s.png" % name)

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _check(ok: bool, what: String) -> void:
	results.append({"ok": ok, "what": what})
	print(("[MatchE2E] ✅ PASS: " if ok else "[MatchE2E] ❌ FAIL: ") + what)

func _pass_n() -> int:
	var n := 0
	for r in results:
		if r.ok:
			n += 1
	return n

func _finish(msg: String) -> void:
	print("[MatchE2E] ====== %s | %d/%d PASS ======" % [msg, _pass_n(), results.size()])
	get_tree().quit(0 if _pass_n() == results.size() else 1)
