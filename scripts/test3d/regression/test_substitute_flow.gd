## 换人链路集成测试（2026-09-10 球员自选功能 · headless 可跑）
## 流程：加载真实 battle_arena → 驱动备战面板 _apply_substitute → 断言
##   ① A队球员 character_id 切换 ② B队自动补全无重复 ③ 3D代理自动重建（bridge 在场）
extends Node3D

func _ready() -> void:
	print("[SubTest] === 换人链路集成测试 ===")
	# 加载真实战斗场景（USE_3D_SCENE=true 非 sim → bridge 存在；备战面板显示但 headless 无人点）
	var arena_scene: PackedScene = load("res://scenes/battle/battle_arena.tscn")
	var arena = arena_scene.instantiate()
	add_child(arena)
	await get_tree().create_timer(1.5).timeout  # 等 _ready 全链路 + bridge 构建

	var mgr = arena
	var prep = mgr.get_node_or_null("UILayer/PreparationUI")
	var bridge = mgr.get_node_or_null("BattleArena3DBridge")
	_report("备战面板存在", prep != null, str(prep != null))
	_report("bridge 存在(3D默认开)", bridge != null, str(bridge != null))
	if prep == null or mgr.team_a_players.size() < 3:
		print("[SubTest] RESULT: FAIL (前置缺失)")
		get_tree().quit(1)
		return

	var before_a0 := str(mgr.team_a_players[0].character_id)
	var before_b := []
	for p in mgr.team_b_players:
		before_b.append(str(p.character_id))
	print("[SubTest] 换人前 A0=%s B=%s" % [before_a0, str(before_b)])
	# 备战面板视觉截图（验证 HUD 隐藏 + 背景不透明）
	if not DisplayServer.is_dark_mode_supported() or true:
		var shot := get_viewport().get_texture().get_image()
		if shot != null:
			DirAccess.open("res://docs").make_dir_recursive("img/3d_p2")
			shot.save_png("res://docs/img/3d_p2/prep_panel.png")
			print("[SubTest] 📷 备战面板截图已存")

	# 驱动换人：位置1 → char_005（初始 B 队含 char_005，应触发 B 队补全）
	prep._apply_substitute(0, "char_005")
	await get_tree().create_timer(0.5).timeout

	var after_a0 := str(mgr.team_a_players[0].character_id)
	var after_b := []
	for p in mgr.team_b_players:
		after_b.append(str(p.character_id))
	_report("A0 已切换", after_a0 == "char_005", "%s → %s" % [before_a0, after_a0])
	var no_dup := not after_b.has("char_005")
	_report("B队无重复(char_005被补全走)", no_dup, str(after_b))
	var b_valid := true
	for cid in after_b:
		if cid == "":
			b_valid = false
	_report("B队全部有效角色", b_valid, str(after_b))

	# 3D 代理重建断言（bridge._player_proxies 以 player 对象为 key）
	if bridge != null:
		await get_tree().create_timer(0.5).timeout  # 等下一帧 _sync_players 重建
		var proxies: Dictionary = bridge._player_proxies
		var p0 = mgr.team_a_players[0]
		var ok_proxy: bool = proxies.has(p0) and is_instance_valid(proxies[p0]) \
			and proxies[p0].char_id == "char_005"
		_report("3D代理已重建", ok_proxy, "proxy.char_id=%s" % (proxies[p0].char_id if proxies.has(p0) else "无"))

	var all_ok := after_a0 == "char_005" and no_dup and b_valid

	# ===== 迟到球员补建（dev 模式场景：球员晚于 bridge 创建）=====
	if bridge != null and mgr.team_a_players.size() >= 3:
		var late_player = mgr._create_player("char_007", "a", false, Vector2(-100, 0))
		mgr.team_a_players.append(late_player)
		await get_tree().create_timer(0.5).timeout  # 等 _check_roster_rebuild 补建
		var proxies: Dictionary = bridge._player_proxies
		var ok_late: bool = proxies.has(late_player) and is_instance_valid(proxies[late_player]) 			and proxies[late_player].char_id == "char_007"
		_report("迟到球员3D代理补建(dev场景)", ok_late, str(ok_late))
		all_ok = all_ok and ok_late

	# ===== 韧性弹飞球权归属（弹飞球停止→回攻击者，不按半场白送）=====
	if mgr.ball_node != null:
		var ball = mgr.ball_node
		var atk = mgr.team_a_players[0]
		var def = mgr.team_b_players[0]
		var empty_skills: Array[Dictionary] = []
		ball.launch(atk.global_position, Vector2.RIGHT, 30.0, 500.0, atk, empty_skills)
		ball.bounced_by_resilience = true  # 模拟已被韧性弹飞
		ball.global_position = Vector2(200, 100)  # 落在B半场（旧逻辑会白送B队）
		ball._hit_player_ids.clear()
		ball._on_ball_stopped()
		await get_tree().create_timer(0.1).timeout
		var owner_after = ball.owner_player
		var ok_owner: bool = owner_after == atk
		_report("弹飞球停止球权回攻击者", ok_owner, "owner=%s" % ("A0" if owner_after == atk else str(owner_after)))
		all_ok = all_ok and ok_owner
		# 出界路径：弹飞球出界同样回攻击者
		ball.launch(def.global_position, Vector2.RIGHT, 30.0, 500.0, def, empty_skills)
		ball.bounced_by_resilience = true
		ball.global_position = Vector2(560, 0)  # 出界点（x>510）
		ball._hit_player_ids.clear()
		ball._on_ball_out_of_field()
		await get_tree().create_timer(0.1).timeout
		var owner_ob = ball.owner_player
		var ok_ob: bool = owner_ob == def
		_report("弹飞球出界球权回攻击者", ok_ob, "owner=%s" % ("B0" if ok_ob else str(owner_ob)))
		all_ok = all_ok and ok_ob
		# 待接球接球机制：命中后韧性 roll——knockback1=接住拿球权 / knockback2=脱手 / 弹飞=球飞走
		# 统计只认"真实命中后"的球权（排除半场分配假阳性）
		var caught := 0
		var returned := 0
		var trials := 25
		for t in range(trials):
			var defender = mgr.team_b_players[0]
			defender.is_ready_to_catch = true
			defender.stamina = 200  # 防止连打致死干扰统计
			defender.global_position = Vector2(260, -130)  # 复位（击退会推走）
			var empty_skills2: Array[Dictionary] = []
			ball.launch(atk.global_position, (defender.global_position - atk.global_position).normalized(), 30.0, 500.0, atk, empty_skills2)
			# 等球命中/停止（球速460px/s，520px 距离约1.2s，上限3s）
			var waited := 0.0
			while waited < 3.0 and ball.is_active and ball.owner_player == null:
				await get_tree().physics_frame
				waited += get_process_delta_time()
			await get_tree().create_timer(0.1).timeout
			# 只有命中过 defender 后拿球才算真接住（否则可能是半场分配）
			var hit_defender: bool = ball._hit_player_ids.has(defender.get_instance_id())
			if hit_defender and ball.owner_player == defender:
				caught += 1
			elif hit_defender and ball.owner_player == atk:
				returned += 1
			defender.is_ready_to_catch = false
			ball.reset()
		_report("接球机制-命中后接住拿球权", caught > 0, "%d/%d 次接住" % [caught, trials])
		# 未接住（弹飞/击退回手）在韧性 roll 下概率出现；0 次也可能是全接住（合法）
		all_ok = all_ok and caught > 0

	# 弹窗构建验证（问题2自查：点"替补"按钮必须真的弹出选人列表）
	if prep != null:
		prep._on_substitute_player(1)
		await get_tree().process_frame
		var popup = prep.get_node_or_null("PlayerSelectPopup")
		_report("换人弹窗打开", popup != null, str(popup != null))
		var btn_count := 0
		if popup != null:
			for child in popup.get_children():
				if child is Button and (child as Button).text != "取消":
					btn_count += 1
		_report("角色列表完整(≥7)", btn_count >= 7, "按钮数=%d" % btn_count)
		prep._close_player_popup()
		all_ok = all_ok and popup != null and btn_count >= 7
	print("[SubTest] RESULT: %s" % ("PASS" if all_ok else "FAIL"))
	get_tree().quit(0 if all_ok else 1)

func _report(item: String, ok: bool, detail: String) -> void:
	print("[SubTest][%s] %s (%s)" % ["PASS" if ok else "FAIL", item, detail])
