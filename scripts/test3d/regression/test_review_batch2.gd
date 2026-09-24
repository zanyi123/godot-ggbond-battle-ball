## 18 复核表第二批代码级验证（对手队可产/简化技逐技执行；headless 可跑）
## 零 skills.json 触碰：组合在内存经 handler._do_apply_tag 真实执行，验证每标签 success
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_review_batch2.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0
var _issues: Array[String] = []   # 复核发现的表/实现缺口


class StubPlayer extends CharacterBody2D:
	var team: String = "a"
	var is_defeated: bool = false
	var char_data: Dictionary = {"name": "stub"}
	var max_stamina: float = 100.0
	var stamina: float = 100.0
	var max_spirit_energy: float = 100.0
	var spirit_energy: float = 100.0
	var facing_direction: Vector2 = Vector2.RIGHT
	func is_status_active(s: String) -> bool:
		return false
	func set_carrying_ball(v: bool) -> void:
		pass


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== 18 复核表第二批 代码级验证 ==========\n")
	for i in range(3):
		await process_frame
	var handler: Node = load("res://scripts/systems/spirit_system/spirit_tag_effect_handler.gd").new()
	root.add_child(handler)
	handler.priority_queue_enabled = false
	var trigger: Node = load("res://scripts/systems/spirit_system/spirit_skill_trigger.gd").new()
	root.add_child(trigger)
	await process_frame
	await process_frame

	var p1: CharacterBody2D = load("res://scripts/battle/player.gd").new()
	p1.max_stamina = 100.0; p1.stamina = 100.0; p1.max_spirit_energy = 100.0; p1.spirit_energy = 100.0
	p1.character_id = ""; p1.team = "a"
	root.add_child(p1)
	var roster: Array[Node] = [p1]
	handler.players = roster
	trigger.players = roster
	await process_frame

	# ===== 逐技组合执行（18 表"建议组合"列；参数按 registry 合法键；🔒S1/S3/S4/S5/S7/S8/S10 与无描述技不入执行）=====
	var recipes: Array = [
		["蝰蛇毒咬", {"ball_speed_up_pct": {"multiplier": 1.3}, "player_heal_block": {"duration": 4.0, "block": true}, "player_energy_block": {"duration": 4.0}}],
		["毒蛇强袭(STEER)", {"ball_manual_steering": {"energy_per_sec": 5.0, "max_duration": 6.0}, "ball_dmg_up_pct": {"value": 80.0}}],
		["羊羊碰碰球", {"ball_dmg_up_pct": {"value": 25.0}}],
		["小鹿乱撞", {"ball_speed_up_pct": {"multiplier": 1.3}, "ball_dmg_up_pct": {"value": 20.0}, "ball_bounce_enhance": {"max_bounces": 6, "speed_keep_pct": 0.9}}],
		["小鹿魅惑(POINT)", {"player_stun": {"duration": 2.0}, "player_silence": {"duration": 2.0}}],
		["移形换影", {"player_spd_up_pct": {"value": 40.0, "duration": 5.0}, "player_def_up_pct": {"value": 30.0, "duration": 5.0}}],
		["蔷薇花园(PLACE)", {"field_obs_add": {"shape": "crescent", "radius": 70.0, "arc_angle": 200.0, "hp": 250.0, "duration": 10.0}}],
		["水瓶封印(⚠简化circle)", {"field_obs_add": {"shape": "circle", "radius": 60.0, "hp": 300.0, "duration": 8.0}}],
		["爱心守护", {"player_shield_obstacle": {"shape": "circle", "radius": 30.0, "uses": 1, "durability_mode": "uses", "follow_mode": "follow", "duration": 20.0}}],
		["坚果盾(TOGGLE)", {"player_shield_obstacle": {"shape": "circle", "radius": 35.0, "hp": 2.0, "uses": 2, "durability_mode": "uses", "follow_mode": "follow", "duration": 10.0}}],
		["加厚坚果盾(TOGGLE)", {"player_shield_obstacle": {"shape": "circle", "radius": 35.0, "hp": 4.0, "uses": 4, "durability_mode": "uses", "follow_mode": "follow", "duration": 10.0}}],
		["荆棘炮(⚠反伤备案)", {"ball_penetrate": {}, "ball_dmg_up_pct": {"value": 30.0}}],
		["防守版荆棘网络", {"field_obs_add": {"shape": "rect", "width": 120.0, "height": 24.0, "hp": 260.0, "duration": 10.0}}],
		["分身球(⚠假球备案)", {"ball_dmg_up_pct": {"value": 30.0}, "ball_speed_up_pct": {"multiplier": 1.2}}],
		["斗牛冲撞(⚠STEER阈值备案)", {"ball_manual_steering": {"energy_per_sec": 5.0, "max_duration": 5.0}, "player_stun": {"duration": 1.0}}],
		["催眠术(⚠POINT简化单人)", {"player_stun": {"duration": 2.0}, "player_silence": {"duration": 2.0}}],
		["巨石攻击(AIM)", {"ball_dmg_up_pct": {"value": 80.0}}],
		["黄土墙盾(⚠pillar→rect)", {"field_obs_add": {"shape": "rect", "width": 40.0, "height": 70.0, "hp": 300.0, "duration": 12.0}}],
		["能量补充(⚠POINT选队友)", {"player_spirit_cost_down": {"multiplier": 1.5, "duration": 6.0}}],
		["雷鸟", {"ball_stealth": {}, "player_stun": {"duration": 1.0}, "player_silence": {"duration": 1.0}}],
		["冰雪列车", {"ball_dmg_up_pct": {"value": 25.0}, "ball_speed_up_pct": {"multiplier": 1.25}, "field_zone_boost": {"position": "0,0", "size": "200,200", "boost_multiplier": 1.5, "duration": 8.0, "affect_ball": true}}],
		["冷冻空间-进攻(PLACE)", {"field_zone_slow": {"position": "0,0", "size": "220,220", "slow_multiplier": 1.4, "duration": 8.0, "affect_ball": true}}],
		["冷冻空间-防御(⚠人数倍增备案)", {"player_shield_obstacle": {"shape": "circle", "radius": 40.0, "hp": 3.0, "uses": 3, "durability_mode": "uses", "follow_mode": "follow", "duration": 10.0}}],
		["电兽速度强化(TOGGLE)", {"player_spd_up_pct": {"value": 35.0, "duration": 5.0}}],
		["电兽攻击强化", {"ball_dmg_up_pct": {"value": 25.0}, "ball_speed_up_pct": {"multiplier": 1.25}}],
		["野牛冲撞", {"ball_dmg_up_pct": {"value": 20.0}, "ball_speed_up_pct": {"multiplier": 1.2}}],
		["防御盾(⚠充能备案)", {"player_shield_obstacle": {"shape": "rect", "width": 120.0, "height": 24.0, "hp": 300.0, "duration": 10.0}}],
		["蛮牛凝视(AIM前摇备案)", {"ball_dmg_up_pct": {"value": 90.0}}],
		["冰霜粉末", {"player_mark_apply": {"mark_id": "frost", "max_stacks": 5, "duration": 6.0}}],
		["冰封粒子(POINT)", {"player_mark_apply": {"mark_id": "frost", "max_stacks": 5, "duration": 6.0, "threshold_count": 3}}],
		["冰雪风暴", {"ball_speed_up_pct": {"multiplier": 1.2}, "player_mark_apply": {"mark_id": "frost", "max_stacks": 5, "duration": 6.0}}],
		["寒冰呼啸", {"ball_dmg_up_pct": {"value": 30.0}, "player_spd_down_pct": {"value": 30.0, "duration": 3.0}, "player_element_immune": {"duration": 5.0, "elements": ["雷火"], "multiplier": 0.0}}],
		["巨型雪球", {"ball_transform": {"size_scale": 2.0}, "ball_dmg_up_pct": {"value": 30.0}}],
		["绝对控制(STEER)", {"ball_manual_steering": {"energy_per_sec": 4.0, "max_duration": 8.0}, "ball_dmg_up_pct": {"value": 25.0}}],
		["魔术白球-攻(STEER)", {"ball_manual_steering": {"energy_per_sec": 4.0, "max_duration": 6.0}, "ball_dmg_up_pct": {"value": 40.0}}],
		["魔术白球-守(⚠道具简化)", {"ball_manual_steering": {"energy_per_sec": 4.0, "max_duration": 6.0}, "player_spd_up_pct": {"value": 30.0, "duration": 3.0}}],
		["滑溜溜护甲", {"player_damage_reflect": {"duration": 6.0, "value": 15.0, "pct": 0.3}, "player_element_weak": {"duration": 6.0, "elements": ["雷火"], "multiplier": 2.0}}],
		["麒麟火", {"ball_dmg_up_pct": {"value": 20.0}, "player_mark_apply": {"mark_id": "fire", "max_stacks": 3, "duration": 8.0}}],
		["三味真火", {"player_mark_apply": {"mark_id": "fire", "max_stacks": 3, "duration": 8.0}}],
		["火印记体系(层2禁疗)", {"player_mark_apply": {"mark_id": "fire", "max_stacks": 3, "duration": 8.0, "threshold_count": 2}, "player_heal_block": {"duration": 3.0, "block": true}}],
		["黑洞吸收(巨变射线系)", {"skill_copy_last": {"cost_pct": 1.0}}],
		["暗黑复制", {"skill_copy_last": {"cost_pct": 1.0}}],
		["暗黑共享", {"skill_share_copy": {"duration": 10.0}}],
		["黑白旋涡(POINT)", {"field_zone_boost": {"position": "0,0", "size": "180,180", "boost_multiplier": 1.4, "duration": 10.0, "affect_ball": false}}],
		["暴烈回旋", {"ball_bounce_enhance": {"max_bounces": 2, "speed_keep_pct": 0.85}, "ball_boomerang": {"return_distance": 0.5}}],
		["巨石手套", {"player_def_up_pct": {"value": 60.0, "duration": 6.0}}],
		["火焰爆射", {"ball_dmg_up_pct": {"value": 25.0}, "ball_speed_up_pct": {"multiplier": 1.3}}],
		["风暴弹珠", {"ball_dmg_up_pct": {"value": 20.0}, "ball_speed_up_pct": {"multiplier": 1.3}}],
		["风暴音盾(⚠反弹加速备案)", {"player_shield_obstacle": {"shape": "rect", "width": 110.0, "height": 22.0, "hp": 260.0, "duration": 10.0}}],
		["音速弹珠", {"ball_speed_up_pct": {"multiplier": 2.2}}],
		["红甲虫结壳", {"player_shield_obstacle": {"shape": "circle", "radius": 32.0, "hp": 3.0, "uses": 3, "durability_mode": "uses", "follow_mode": "follow", "duration": 12.0}}],
		["甲虫夹击(⚠逐个操控S3)", {"ball_spread": {"split_count": 3, "split_damage_ratio": 0.5}}],
		["追踪导弹(FP)", {"ball_tracking": {"turn_speed": 6.0}, "ball_lockon": {}}],
		["二段推进(MIDFLY)", {"ball_in_flight_boost": {"dmg_pct": 0.3, "speed_pct": 1.3}}],
		["爆裂散弹(⚠AIM扇形备案)", {"ball_spread": {"split_count": 4, "split_damage_ratio": 0.6}}],
		["陨石撞击(⚠lob区域近似)", {"field_zone_danger": {"position": "0,0", "size": "160,160", "damage_value": 30.0, "duration": 4.0}}],
		["超新星(一级)", {"ball_dmg_up_pct": {"value": 25.0}, "ball_speed_up_pct": {"multiplier": 1.25}}],
		["(多重)超新星(⚠距离分裂)", {"ball_spread": {"split_count": 3, "split_damage_ratio": 0.6, "trigger_dist_pct": 0.5}}],
		["失重领域(⚠易伤备案)", {"field_zone_slow": {"position": "0,0", "size": "200,200", "slow_multiplier": 1.3, "duration": 6.0}}],
		["超重领域(⚠root备案)", {"field_zone_slow": {"position": "0,0", "size": "240,240", "slow_multiplier": 1.5, "duration": 6.0}}],
		["战车冲锋", {"ball_dmg_up_pct": {"value": 30.0}, "ball_speed_up_pct": {"multiplier": 1.3}}],
		["光明护盾", {"player_shield_obstacle": {"shape": "rect", "width": 120.0, "height": 24.0, "hp": 280.0, "duration": 10.0}}],
		["光明飞弹", {"ball_dmg_up_pct": {"value": 25.0}, "ball_speed_up_pct": {"multiplier": 1.25}}],
		["必中机制(队伍特性)", {"ball_sure_hit": {}}],
		["风之屏障(接线补遗后)", {"field_drain_wall": {"duration": 8.0, "width": 140.0, "height": 26.0, "capture_radius": 60.0, "absorb_pull": 300.0, "drain_hold": 2.0}}],
		["爆裂轰击", {"ball_speed_up_pct": {"multiplier": 2.0}}],
		["慢悠悠光线(⚠分效备案)", {"player_charge_stock": {"duration": 20.0, "charges": 6}}],
		["钢铁皮肤(⚠击退免疫备案)", {"player_def_up_pct": {"value": 50.0, "duration": 8.0}}],
		["元灵结界", {"player_shield_obstacle": {"shape": "rect", "width": 130.0, "height": 26.0, "hp": 500.0, "duration": 12.0}}],
		["万伏雷霆", {"ball_dmg_up_pct": {"value": 25.0}, "player_hp_dot": {"value": 5.0, "duration": 3.0, "target": "enemies"}}],
		["大惊雷(AIM)", {"ball_carry_push": {"pull_speed": 200.0, "max_duration": 3.0}, "player_stun": {"duration": 1.0}, "player_silence": {"duration": 1.0}}],
		["自由之火(⚠清空球权备案)", {"player_element_immune": {"duration": 4.0, "elements": ["冰雪"], "multiplier": 0.0}}],
		["惊雷响应", {"player_energy_share": {"duration": 8.0, "share_pct": 0.5}}],
		["万伏汹涌", {"player_energy_gain_pct": {"value": 30.0, "target": "self"}, "player_spirit_cost_down": {"multiplier": 1.3, "duration": 8.0}}],
		["轰天炮", {"ball_dmg_up_pct": {"value": 25.0}, "ball_speed_up_pct": {"multiplier": 1.3}}],
		["电闪火石(⚠触爆备案)", {"ball_dmg_up_pct": {"value": 25.0}, "ball_speed_up_pct": {"multiplier": 1.2}}],
	]

	for recipe in recipes:
		var skill_name: String = recipe[0]
		var tag_params: Dictionary = recipe[1]
		var all_ok := true
		for tag_id in tag_params:
			var result: Dictionary = handler._do_apply_tag(str(tag_id), tag_params[tag_id], p1.get_instance_id())
			if not bool(result.get("success", false)):
				all_ok = false
				_issues.append("%s: 标签 %s 执行失败 (result=%s)" % [skill_name, str(tag_id), str(result)])
		_assert("组合可执行: " + skill_name, all_ok)

	# ===== 特殊点核验 =====
	# ⓪ 削能墙标签接线核验（风之屏障；2026-09-24 小工单主人批准后接线）：
	#    分发 _apply_field_drain_wall 已实现（field_route，放置流同 obs_add）；
	#    create_obstacle 统一注入 drain 参数（setup_drain 钩子，无需手动二次调用）
	var drain_result: Dictionary = handler._do_apply_tag("field_drain_wall", {"duration": 8.0}, p1.get_instance_id())
	_assert("削能墙接线: 标签分发返回 success", bool(drain_result.get("success", false)))
	var drain_mgr = load("res://scripts/battle/obstacle_manager.gd").new()
	root.add_child(drain_mgr)
	drain_mgr.ball_ref = null
	await process_frame
	var p_wall := {"shape": "rect", "width": 140.0, "height": 26.0, "hp": 9999.0, "duration": 8.0,
		"capture_radius": 60.0, "absorb_pull": 300.0, "drain_hold": 2.0}
	var wall = drain_mgr.create_obstacle(p_wall.duplicate(), Vector2(120, 0), 0.0, "res://scripts/battle/drain_wall.gd")
	await process_frame
	_assert("削能墙接线: create_obstacle 钩子注入 drain 参数", is_instance_valid(wall) \
		and absf(float(wall.capture_radius) - 60.0) < 0.01 \
		and absf(float(wall.absorb_pull) - 300.0) < 0.01 \
		and absf(float(wall.drain_hold) - 2.0) < 0.01)

	# ① 能量强化（芬尼队）：18 表标 ✅（next_skill_mult 管道已有）——管道在 player.gd，registry 无标签条目
	var has_tag := false
	for t in DevDataSync.load_tags():
		if str(t.get("id", "")).begins_with("next_skill"):
			has_tag = true
	if not has_tag:
		_issues.append("复核确认: 能量强化 next_skill_mult=player.gd 管道已有(add_next_skill_mult)、registry 无标签条目——18 表该技 ✅ 应修正为 ⚠(待标签化)")

	# ② 击退/击飞类无独立标签（羊羊碰碰球/电兽攻击强化/音速弹珠/爆裂轰击/分身球以数值档覆盖）
	_issues.append("复核确认: 击退/击飞无独立标签，v1 以数值档覆盖（18 表'概率/击飞'参数表述→备案）")
	# ③ 形状类：pillar/笼形不存在（黄土墙盾 rect、水瓶封印 circle 简化，17 已有先例）
	_issues.append("复核确认: pillar/笼形 shape 不存在——黄土墙盾 rect、水瓶封印 circle 简化（17 表同款先例）")
	# ④ lob 轨迹无标签化（陨石撞击→区域坠落近似，同 17 凤凰俯冲先例）
	_issues.append("复核确认: lob 轨迹无标签化——陨石撞击以 field_zone_danger 区域近似（17 凤凰俯冲同款先例）")
	# ⑤ 召唤系无标签（快牙猎杀×2/猎杀快道/快牙撕咬/塔台基座→S5；暗影分身/分身-顿挫/藤蔓树妖/不死鸟→S5）
	_issues.append("复核确认: 召唤系无标签可验（快牙猎杀系/塔台基座/暗影分身/藤蔓树妖/不死鸟）——随 S5 立项")
	# ⑥ 信息/规则/道具系备案（心眼S7/棋盘领域S8/镇灵鼓S4/全家同心力球权转移）
	_issues.append("复核确认: 信息/规则/道具/球权转移系（心眼S7、棋盘领域S8、镇灵鼓S4、全家同心力）无标签，随对应系统")
	# ⑦ 参数备案小项汇总（表内 ⚠ 已标注的改写点，代码侧复核成立）
	_issues.append("复核确认: 参数备案项成立——荆棘炮穿透时长+owner反伤/冷冻防御人数倍增/防御盾充能/慢悠悠敌我分效/风暴音盾反弹加速/钢铁皮肤击退免疫/自由之火清空球权/电闪火石触爆禁反弹/失重易伤/超重root/意识共享视野")

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if not _issues.is_empty():
		print("\n---- 复核发现项 ----")
		for x in _issues:
			print("  · " + x)
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 全部通过！")
	quit(1 if _fail > 0 else 0)


func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)
