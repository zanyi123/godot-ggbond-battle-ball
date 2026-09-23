## 17 复核表第一批代码级验证（20 可产/简化技逐技执行；headless 可跑）
## 零 skills.json 触碰：组合在内存经 handler._do_apply_tag 真实执行，验证每标签 success
## 运行：Godot_console.exe --headless --script res://scripts/test3d/regression/test_review_batch1.gd
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
	print("\n========== 17 复核表第一批 代码级验证 ==========\n")
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

	# ===== 逐技组合执行（17 表"建议标签组合"列；参数按工单/registry 合法键）=====
	var recipes: Array = [
		["猛虎金刚闪", {"ball_dmg_up_pct": {"value": 35.0}, "ball_speed_up_pct": {"multiplier": 1.35}, "ball_range_up": {"radius": 80.0, "damage_pct": 0.5}}],
		["超时空猛虎金刚闪(⚠高阶档)", {"ball_dmg_up_pct": {"value": 52.0}, "ball_speed_up_pct": {"multiplier": 2.0}}],
		["超时空光明之刃(⚠彩蛋)", {"ball_dmg_up_pct": {"value": 80.0}}],
		["飞火流星", {"ball_dmg_up_pct": {"value": 30.0}, "ball_speed_up_pct": {"multiplier": 1.4}}],
		["回旋火星", {"ball_boomerang": {"return_distance": 0.6}}],
		["凤凰飞袭", {"ball_dmg_up_pct": {"value": 40.0}, "ball_speed_up_pct": {"multiplier": 1.3}, "ball_penetrate": {}}],
		["火凤燎原", {"field_zone_danger": {"radius": 90.0, "damage_value": 8.0, "duration": 4.0, "spawn_at": "ball_land"}}],
		["凤凰俯冲(⚠lob 待标签化)", {"ball_dmg_up_pct": {"value": 45.0}}],
		["零度冰墙", {"field_obs_add": {"shape": "rect", "width": 130.0, "height": 26.0, "hp": 280.0, "duration": 10.0}}],
		["零度冰柱(⚠pillar→rect 简化)", {"field_obs_add": {"shape": "rect", "width": 40.0, "height": 70.0, "hp": 200.0, "duration": 8.0}}],
		["冰球弹", {"ball_dmg_up_pct": {"value": 20.0}, "player_move_slow": {"multiplier": 1.3, "duration": 2.5}}],
		["减速水球袋(⚠手持一次性盾)", {"player_shield_obstacle": {"uses": 1, "duration": 30.0, "shape": "circle", "radius": 30.0, "durability_mode": "uses", "follow_mode": "follow"}}],
		["冰天雪地(⚠简化减速区)", {"field_zone_slow": {"radius": 160.0, "slow_multiplier": 1.4, "duration": 6.0, "spawn_at": "ball_stop"}}],
		["钻石壁垒", {"player_shield_obstacle": {"shape": "crescent", "radius": 70.0, "hp": 3.0, "uses": 3, "durability_mode": "uses", "follow_mode": "follow", "duration": 8.0}}],
		["钻石之舞(⚠群体自强化简化)", {"player_def_up_pct": {"value": 30.0, "duration": 5.0}, "player_res_up_pct": {"value": 30.0, "duration": 5.0}, "player_spd_up_pct": {"value": 30.0, "duration": 5.0}}],
		["狂风扫落叶(⚠def_down 直接削弱简化)", {"ball_speed_up_pct": {"multiplier": 1.35}, "player_spirit_cost_down": {"multiplier": 1.5, "duration": 4.0}, "player_def_down_pct": {"value": 25.0, "duration": 4.0, "target": "enemies"}}],
		["蔓藤缠绕", {"player_root": {"duration": 2.0, "break_on_hit": true}}],
		["飞叶幻影", {"player_spd_up_pct": {"value": 30.0, "duration": 3.0}, "player_stealth": {"duration": 3.0}}],
		["弹性触手", {"ball_recall": {"max_times": 2}}],
		["光明之刃", {"ball_dmg_up_pct": {"value": 30.0}, "ball_speed_up_pct": {"multiplier": 1.3}}],
		["聚力回旋", {"ball_boomerang": {"return_distance": 0.5}, "ball_lockon": {}, "player_stun": {"duration": 1.0}}],
	]

	for recipe in recipes:
		var skill_name: String = recipe[0]
		var tag_params: Dictionary = recipe[1]
		var all_ok := true
		for tag_id in tag_params:
			var result: Dictionary = handler._do_apply_tag(str(tag_id), tag_params[tag_id], p1.get_instance_id())
			if not bool(result.get("success", false)):
				all_ok = false
				_issues.append("%s: 标签 %s 执行失败" % [skill_name, str(tag_id)])
		_assert("组合可执行: " + skill_name, all_ok)

	# ===== 特殊点核验 =====
	# ① SKILL_COPIED 被动订阅解析（梦幻束缚）
	var ev: int = trigger._event_name_to_enum("Skill.COPIED")
	_assert("梦幻束缚: Skill.COPIED 可解析到事件枚举", ev >= 0)

	# ② pillar shape 边界（零度冰柱）：obstacle 无 pillar 类型，确认 fallback rect 可用（表内已标简化）
	_issues.append("复核确认: 零度冰柱 pillar shape 不存在，已按 rect(40×70) 简化（17 表 ⚠ 已标注）")
	_issues.append("复核确认: 凤凰俯冲 lob 轨迹无标签化字段，组合只含 dmg_up 大数值（17 表 ⚠ 已标注'组合待配'）")
	_issues.append("复核确认: 狂风扫落叶第三标签 registry 实名=player_def_down_pct（17 表泛称 player_def_down）")

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
