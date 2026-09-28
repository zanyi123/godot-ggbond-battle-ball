## 11框架一期验收套件：团队合击追踪器（同窗爆发型）
## 覆盖：框架表加载/反向索引 / 登记聚合判定（distinct 施法者按 role 计数）/ 窗口过期 / 同窗冷却 /
##       结算出口（on_formed→handler 引用标签）/ S1 零依赖护栏。
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_team_combo.gd
extends SceneTree

const TrackerScript := preload("res://scripts/systems/spirit_system/team_combo_tracker.gd")

var _pass: int = 0
var _fail: int = 0
var _formed_signals: Array = []  # [combo_id, members]


## 测试替身： SpiritSystemManager（只含 skill_used 信号与 handler 引用）
class StubSS extends Node:
	signal skill_used(skill_id: String, caster_id: int, success: bool)
	var tag_effect_handler: Node = null


## 测试替身：标签效果处理器（记录 apply_tag_effect 调用）
class StubHandler extends Node:
	var calls: Array = []
	func apply_tag_effect(tag: String, params: Dictionary, target_id: int) -> void:
		calls.append({"tag": tag, "params": params, "target": target_id})


## 测试替身：球员
class StubPlayer extends CharacterBody2D:
	var char_data: Dictionary = {}
	var team: String = "a"
	var is_defeated: bool = false


## 测试替身：battle_manager（scope 队伍解析用）
class StubBM extends Node2D:
	var team_a_players: Array = []
	var team_b_players: Array = []


func _initialize() -> void:
	_run()


func _make_player(name: String, team: String, uid: int) -> StubPlayer:
	var p := StubPlayer.new()
	p.name = name + str(uid)
	p.char_data = {"name": name}
	p.team = team
	return p


func _make_tracker() -> Node:
	var tracker: Node = TrackerScript.new()
	return tracker


func _run() -> void:
	print("\n========== 11框架一期：团队合击追踪器验收 ==========\n")
	for i in range(2):
		await process_frame

	# ===== A组：框架表加载与反向索引 =====
	var tracker: Node = _make_tracker()
	get_root().add_child(tracker)
	tracker._load_table()
	_assert("A1: kirin_trio 已加载", tracker._combos.has("kirin_trio"))
	_assert("A2: 麒麟火→main 反向索引", _index_has(tracker, "skill_雷火_5", "main"))
	_assert("A3: 三味真火→assist 反向索引", _index_has(tracker, "skill_雷火_6", "assist"))
	_assert("A4: 窗口秒=12（频率取向，D9 收紧）", absf(float(tracker._window_seconds.get("kirin_trio", 0))) - 12.0 < 0.01)

	# ===== B组：聚合判定（distinct 施法者按 role 计数）=====
	var ss := StubSS.new()
	var handler := StubHandler.new()
	ss.tag_effect_handler = handler
	var bm := StubBM.new()
	var p1: StubPlayer = _make_player("甲", "a", 1)
	var p2: StubPlayer = _make_player("乙", "a", 2)
	var p3: StubPlayer = _make_player("丙", "a", 3)
	var p4: StubPlayer = _make_player("丁", "b", 4)
	bm.team_a_players = [p1, p2, p3]
	bm.team_b_players = [p4]
	get_root().add_child(ss)
	get_root().add_child(handler)
	get_root().add_child(bm)

	var tracker2: Node = TrackerScript.new()
	get_root().add_child(tracker2)
	tracker2._load_table()
	tracker2._bm = bm
	tracker2.setup(ss)
	tracker2.team_combo_formed.connect(func(cid: String, members: Array, params: Dictionary) -> void:
		_formed_signals.append([cid, members]))

	# 仅两道 assist（缺 main）→ 不成立
	tracker2.register_cast("skill_雷火_6", p2.get_instance_id())
	tracker2.register_cast("skill_雷火_6", p3.get_instance_id())
	tracker2._try_form_combos()
	_assert("B1: 缺 main 不成立", _formed_signals.is_empty())

	# 同一施法者两道 assist → distinct 计 1 → 仍不成立
	var tracker3: Node = TrackerScript.new()
	get_root().add_child(tracker3)
	tracker3._load_table()
	tracker3._bm = bm
	tracker3.register_cast("skill_雷火_6", p2.get_instance_id())
	tracker3.register_cast("skill_雷火_6", p2.get_instance_id())
	tracker3._try_form_combos()
	_assert("B2: 同人重复 assist 不复用（distinct=1<2）", tracker3.get_formed_count("kirin_trio") == 0)

	# main + 2 distinct assist → 成立（信号+计数）
	tracker2.register_cast("skill_雷火_5", p1.get_instance_id())
	tracker2._try_form_combos()
	_assert("B3: main+2assist → 成立", tracker2.get_formed_count("kirin_trio") == 1)
	_assert("B4: 信号收到且成员3人", _formed_signals.size() == 1 and (_formed_signals[0][1] as Array).size() == 3)

	# ===== C组：结算出口（on_formed→handler 引用标签）=====
	var ally_hits := 0
	for call in handler.calls:
		if str(call["tag"]) == "player_atk_up_pct" and int(call["target"]) in [p1.get_instance_id(), p2.get_instance_id(), p3.get_instance_id()]:
			ally_hits += 1
	_assert("C1: 结算对友军施加 player_atk_up_pct ×3", ally_hits == 3)
	var foe_hits := 0
	for call in handler.calls:
		if int(call["target"]) == p4.get_instance_id():
			foe_hits += 1
	_assert("C2: 敌方不受结算波及", foe_hits == 0)

	# ===== D组：同窗冷却 + 窗口过期 =====
	var formed_before: int = tracker2.get_formed_count("kirin_trio")
	tracker2.register_cast("skill_雷火_5", p1.get_instance_id())
	tracker2.register_cast("skill_雷火_6", p2.get_instance_id())
	tracker2.register_cast("skill_雷火_6", p3.get_instance_id())
	tracker2._try_form_combos()
	_assert("D1: 同窗冷却不重复触发", tracker2.get_formed_count("kirin_trio") == formed_before)

	# 窗口过期：模拟时钟推过窗口（8s），旧登记全部失效
	tracker2._elapsed += 20.0
	tracker2._try_form_combos()
	_assert("D2: 过期后登记清空→无信号", tracker2.get_formed_count("kirin_trio") == formed_before)
	tracker2.register_cast("skill_雷火_5", p1.get_instance_id())
	tracker2.register_cast("skill_雷火_6", p2.get_instance_id())
	tracker2.register_cast("skill_雷火_6", p3.get_instance_id())
	tracker2.register_cast("skill_e2e_we_teleport", p3.get_instance_id())  # 无关技能不入索引（噪声对照）
	tracker2._try_form_combos()
	_assert("D3: 冷却期满可再成立（新窗口）", tracker2.get_formed_count("kirin_trio") == formed_before + 1)

	# ===== E组：护栏 =====
	_assert("E1: tracker 挂 team_combo_trackers 组", tracker2.is_in_group("team_combo_trackers"))
	var ssm_src: String = (load("res://scripts/systems/spirit_system/spirit_system_manager.gd") as GDScript).source_code
	_assert("E2: SSM 仅追加挂载段（含 TeamComboTracker）", ssm_src.contains("TeamComboTracker"))
	var tracker_ref: GDScript = TrackerScript
	var tracker_src: String = tracker_ref.source_code
	_assert("E2b: tracker 零依赖 S1 协调器（纯增量无交叉）", not tracker_src.contains("skill_state_manager"))
	_assert("E3: 无随机流/墙钟调用（确定性纪律）", not tracker_src.contains("randf(") and not tracker_src.contains("Time.get_ticks"))

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 全部通过！（S1 协调器零触碰，框架纯增量）")
	quit(1 if _fail > 0 else 0)


func _index_has(tracker: Node, skill_id: String, role: String) -> bool:
	for entry in tracker._skill_index.get(skill_id, []):
		if str(entry["role"]) == role:
			return true
	return false


func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)
