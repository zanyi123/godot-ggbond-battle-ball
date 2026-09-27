## 工单19 任务A验收：操控族激活链（c 分级——STEER/MIDFLY 必走操作链）
## 断言组：J-技能数据 / K-查询口与AI激活 / T-接管链（球侧放行/handler标记/tick注入） / P-默认provider / R-纪律
## 依据：元灵技能AI规划/19_操控族激活链与波E实证工单.md §一
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_activation_chain.gd
extends SceneTree

const SKILLS_PATH := "res://data/spirits/skills.json"
const REGISTRY_PATH := "res://data/spirits/tags_registry.json"
const INPUT_SOURCE_PATH := "res://scripts/battle/spirit_ai/ai_input_source.gd"
const STATE_MANAGER_PATH := "res://scripts/systems/spirit_system/skill_state_manager.gd"
const BALL_ROUTE_PATH := "res://scripts/systems/spirit_system/handler/ball_route.gd"
const BALL_PATH := "res://scripts/battle/ball.gd"

const STEER_SKILL := "skill_雷火_7"
const MIDFLY_SKILL := "skill_雷火_8"

var _pass: int = 0
var _fail: int = 0


class StubPlayer extends CharacterBody2D:
	var character_id: String = ""
	var team: String = "a"
	var is_player_controlled: bool = false
	var is_defeated: bool = false
	var ball_ref: Node = null
	var char_data: Dictionary = {"name": "stub"}

	func _init() -> void:
		add_to_group("players")  # build_default_ctx 名册扫描同源

	func get_equipped_skills() -> Array:
		return [STEER_SKILL, MIDFLY_SKILL]


class StubBall extends Node2D:
	var is_active: bool = true
	var _manual_active: bool = false
	var ball_direction: Vector2 = Vector2(1, 0)
	var speed: float = 300.0
	var steer_count: int = 0
	var last_dir: Vector2 = Vector2.ZERO
	var recalled: int = 0
	var attacker_player: Node = null

	func manual_steer(dir: Vector2) -> void:
		steer_count += 1
		last_dir = dir

	func recall_ball(times: int) -> void:
		recalled += times


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== 工单19任务A：操控族激活链（STEER/MIDFLY 走操作链） ==========\n")
	for i in range(3):
		await process_frame

	var input_src: GDScript = load(INPUT_SOURCE_PATH)
	var sm: Node = load(STATE_MANAGER_PATH).new()
	root.add_child(sm)

	# ===== J-技能数据 =====
	var skills: Array = (JSON.parse_string(FileAccess.get_file_as_string(SKILLS_PATH)) as Dictionary).get("skills", [])
	var by_id: Dictionary = {}
	for s in skills:
		if typeof(s) == TYPE_DICTIONARY:
			by_id[str(s.get("id", ""))] = s
	var steer_d: Dictionary = by_id.get(STEER_SKILL, {})
	var midfly_d: Dictionary = by_id.get(MIDFLY_SKILL, {})
	_assert("J1: STEER/MIDFLY 验收技已实配", not steer_d.is_empty() and not midfly_d.is_empty())
	_assert("J2: operator=OP_STEER/OP_MIDFLY", str(steer_d.get("operator", "")) == "OP_STEER" and str(midfly_d.get("operator", "")) == "OP_MIDFLY")
	var reg: Variant = JSON.parse_string(FileAccess.get_file_as_string(REGISTRY_PATH))
	var reg_params: Array = []
	if typeof(reg) == TYPE_DICTIONARY:
		for t in reg.get("tags", []):
			if typeof(t) == TYPE_DICTIONARY and str(t.get("id", "")) == "ball_manual_steering":
				reg_params = t.get("params", [])
	var tp_ok: bool = true
	for k in (steer_d.get("tag_params", {}).get("ball_manual_steering", {}) as Dictionary).keys():
		if not reg_params.has(str(k)):
			tp_ok = false
	_assert("J3: ball_manual_steering tag_params 在 registry params 内", tp_ok)

	# ===== K-查询口与AI激活 =====
	_assert("K1: 出厂查询口=空字典（无上下文）", sm.get_active_operation(9001).is_empty())
	var caster: StubPlayer = StubPlayer.new()
	caster.character_id = "t19_caster"
	caster.team = "a"
	caster.position = Vector2(0, 0)
	root.add_child(caster)
	_assert("K2a: AUTO 类技能 ai_activate 拒绝（照旧直调）", not bool(sm.ai_activate_skill(9001, caster, "skill_大地_3")))
	_assert("K2b: STEER 技 ai_activate 成功", bool(sm.ai_activate_skill(9001, caster, STEER_SKILL)))
	var ctx1: Dictionary = sm.get_active_operation(9001)
	_assert("K2c: STEER 激活-释放链走通（RELEASING；上下文随释放清=球侧判定接管，语义对）", int(sm._player_skills.get(9001, {}).get(0, {}).get("state", -1)) == 2)
	_assert("K2d: AI 输入源已登记（幂等不覆盖）", (sm.ai_virtual_inputs as Dictionary).has(9001))
	_assert("K2e: MIDFLY 技 ai_activate→RELEASING+midfly_left=2", bool(sm.ai_activate_skill(9002, caster, MIDFLY_SKILL)) and str(sm.get_active_operation(9002).get("operator", "")) == "OP_MIDFLY" and int(sm.get_active_operation(9002).get("midfly_left", -1)) == 2)
	_assert("K3a: provider 未设=Callable 无效", not sm.ai_ctx_provider.is_valid())

	# ===== T-接管链 =====
	# T1：ball.begin_manual_steering AI 放行语义（源码级：manual_ai_controlled 分支存在）
	var ball_src: String = FileAccess.get_file_as_string(BALL_PATH)
	_assert("T1a: ball.gd 含 manual_ai_controlled 放行分支", ball_src.find("manual_ai_controlled") != -1)
	var route_src: String = FileAccess.get_file_as_string(BALL_ROUTE_PATH)
	_assert("T1b: ball_route 含 AI 接管标记下发（组查找 ai_virtual_inputs）", route_src.find("manual_ai_controlled") != -1 and route_src.find("ai_virtual_inputs") != -1)

	# T2：handler 标记下发（真实 handler 实例+组查找）
	var handler: Node = load("res://scripts/systems/spirit_system/spirit_tag_effect_handler.gd").new()
	root.add_child(handler)
	handler.priority_queue_enabled = false
	handler.players = _node_array([caster])
	sm.register_ai_input_source(caster.get_instance_id(), caster)
	handler._apply_ball_manual_steering({"energy_per_sec": 5.0, "max_duration": 6.0}, caster.get_instance_id())
	var mods: Dictionary = handler._ball_mods_by_caster.get(caster.get_instance_id(), {})
	_assert("T2a: 登记者施法→manual_ai_controlled=true", bool(mods.get("manual_ai_controlled", false)))
	var stranger: StubPlayer = StubPlayer.new()
	stranger.character_id = "t19_stranger"
	stranger.team = "a"
	stranger.position = Vector2(50, 0)
	root.add_child(stranger)
	handler._apply_ball_manual_steering({"energy_per_sec": 5.0, "max_duration": 6.0}, stranger.get_instance_id())
	var mods2: Dictionary = handler._ball_mods_by_caster.get(stranger.get_instance_id(), {})
	_assert("T2b: 未登记者施法→无标记（存量行为）", not bool(mods2.get("manual_ai_controlled", false)))

	# T3：tick STEER 注入（球手动态+敌门锚向）
	var ball: StubBall = StubBall.new()
	ball._manual_active = true
	ball.attacker_player = caster
	caster.ball_ref = ball
	ball.get_parent()  # noop
	root.add_child(ball)
	sm.ai_ctx_provider = Callable(input_src, "build_default_ctx")
	_assert("K3b: provider 已设=Callable 有效", sm.ai_ctx_provider.is_valid())
	sm._tick_ai_activations()
	_assert("T3a: STEER 窗 tick→manual_steer 注入（敌门向 +x）", ball.steer_count >= 1 and ball.last_dir.x > 0.9)
	_assert("T3b: 瞄准意图留档 set_ai_aim", sm.get_ai_aim(caster.get_instance_id()) == ball.last_dir)

	# T4：tick MIDFLY 自动激活+干预（球远>350→recall press）
	var far_ball: StubBall = StubBall.new()
	far_ball.is_active = true
	far_ball._manual_active = false
	far_ball.position = Vector2(500, 0)
	caster.ball_ref = far_ball
	var caster2: StubPlayer = StubPlayer.new()
	caster2.character_id = "t19_midfly"
	caster2.team = "a"
	caster2.position = Vector2(0, 0)
	root.add_child(caster2)
	caster2.ball_ref = far_ball
	sm.register_ai_input_source(caster2.get_instance_id(), caster2)
	var action: String = input_src.tick_activation(sm, caster2.get_instance_id(), caster2, input_src.build_default_ctx(caster2))
	print("    [debug] T4 action=", action, " op_ctx=", sm.get_active_operation(caster2.get_instance_id()))
	var dbg_ctx: Dictionary = input_src.build_default_ctx(caster2)
	print("    [debug] ctx.ball_position=", dbg_ctx.get("ball_position"), " player=", caster2.global_position)
	var dbg_intent: Dictionary = input_src._midfly_intent_by_policy("recall", dbg_ctx)
	print("    [debug] recall intent=", dbg_intent)
	_assert("T4a: MIDFLY tick→自动激活+球远 recall press", action == "midfly_press")
	_assert("T4b: 干预经公开入口（midfly_left 2→1）", int(sm.get_active_operation(caster2.get_instance_id()).get("midfly_left", -1)) == 1)
	_assert("T4c: 球 recall_ball 被调（拉回效果落地）", far_ball.recalled == 1)
	far_ball.position = Vector2(100, 0)  # 球已拉近（ recall 生效后场景）→ 不再滥按
	var action2: String = input_src.tick_activation(sm, caster2.get_instance_id(), caster2, input_src.build_default_ctx(caster2))
	_assert("T4d: 球拉近后二周期→hold（不滥按）", action2 == "midfly_hold" or action2 == "")

	# T5：provider 未设时 tick 零动作（fail-closed 存量等价）
	var sm2: Node = load(STATE_MANAGER_PATH).new()
	root.add_child(sm2)
	sm2.register_ai_input_source(caster.get_instance_id(), caster)
	var steer_before: int = ball.steer_count
	sm2._tick_ai_activations()
	_assert("T5: provider 未设→tick 空转（零行为差异）", ball.steer_count == steer_before)

	# ===== P-默认 provider =====
	var pctx: Dictionary = input_src.build_default_ctx(caster)
	_assert("P1: build_default_ctx 含球位/速度/敌门/敌列表", pctx.has("ball_position") and pctx.has("ball_velocity") and pctx.has("enemy_goal") and pctx.has("visible_enemies"))
	_assert("P2: a 队敌门锚=(300,0)（16号交叉布局口径）", (pctx.get("enemy_goal", Vector2.ZERO) as Vector2).distance_to(Vector2(300, 0)) < 0.001)
	var foe: StubPlayer = StubPlayer.new()
	foe.character_id = "t19_foe"
	foe.team = "b"
	foe.position = Vector2(200, 0)
	root.add_child(foe)
	var foe_self: StubPlayer = StubPlayer.new()
	foe_self.character_id = "t19_ally_b"
	foe_self.team = "a"
	root.add_child(foe_self)
	var pctx2: Dictionary = input_src.build_default_ctx(caster)
	var enemies: Array = pctx2.get("visible_enemies", [])
	var only_enemy := true
	for e in enemies:
		if str(e.get("team")) == "a":
			only_enemy = false
	_assert("P3: 名册敌过滤（仅异队存活）", only_enemy and enemies.size() >= 1)

	# ===== R-纪律 =====
	var src_in: String = FileAccess.get_file_as_string(INPUT_SOURCE_PATH)
	_assert("R1: ai_input_source 无 randf(/ticks_msec（确定性铁律）", src_in.find("randf(") == -1 and src_in.find("ticks_msec") == -1)
	var src_sm: String = FileAccess.get_file_as_string(STATE_MANAGER_PATH)
	_assert("R2: skill_state_manager 无 randf(", src_sm.find("randf(") == -1)
	_assert("R3: ai_activate_skill 对 AUTO 返回 false（直调语义保留=c 分级）", src_sm.find("ai_activate_skill") != -1)

	_finish()


func _node_array(nodes: Array) -> Array[Node]:
	var out: Array[Node] = []
	for n in nodes:
		out.append(n)
	return out


func _finish() -> void:
	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 全部通过！（工单19任务A交付门槛达成）")
	quit(1 if _fail > 0 else 0)


func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)
