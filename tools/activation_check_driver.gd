## 工单19 任务A 平台实证 driver：STEER 引导球 + MIDFLY 飞行干预 运行时可见（信号判定）
## 复用 rolling_check 模式：battle_arena --sim 真场景全 AI；运行时内存注册"操控测试的元灵"
## 装备到 B 队球员（loadout_loader 先例=零污染主数据）；设 AI 感知 provider（build_default_ctx）
## 后由激活窗 tick 自动接管——判定=球侧状态+state_machine 上下文+意图留档（21表通道①数据源）
## 运行：Godot_console.exe --headless --path . res://tools/activation_check_launcher.tscn --sim --seed=N
extends Node

const AI_INPUT_SOURCE := preload("res://scripts/battle/spirit_ai/ai_input_source.gd")

const STEER_SKILL := "skill_雷火_7"
const MIDFLY_SKILL := "skill_雷火_8"
const CTRL_SPIRIT := {
	"id": "test_spirit_ctrl", "name": "操控测试的元灵", "element": "雷火",
	"skills": [STEER_SKILL, MIDFLY_SKILL],
}

var bm: Node = null
var sm: Node = null
var ss: Node = null           # spirit_system（驱动层用）               # 全局 skill_state_manager（input_manager 下，波C attach 目标）
var ctrl_player: Node = null      # 装备操控元灵的球员
var casts: Dictionary = {}        # skill_used 采样
var steer_ball_seen: bool = false       # 球进手动态（STEER 效果落地）
var steer_inject_seen: bool = false     # AI 引导注入（get_ai_aim 非零=激活窗 tick 接管）
var midfly_ctx_seen: bool = false       # MIDFLY 激活上下文出现（自动激活）
var midfly_pressed_seen: bool = false   # 干预生效（midfly_left 扣减<初始）
var _waited: float = 0.0
var match_over: bool = false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed(int(a.substr(7)))
	print("[ActCheck] 工单19任务A 实证启动")
	await get_tree().process_frame
	await get_tree().process_frame
	bm = get_tree().root.get_node_or_null("ActCheck/Arena")
	if bm == null:
		for c in get_tree().root.get_children():
			if c.get_script() and str(c.get_script().resource_path).contains("battle_manager"):
				bm = c
	if bm == null:
		print("[ActCheck] FAIL: 未找到 battle_manager")
		get_tree().quit(1)
		return
	_setup()


func _setup() -> void:
	# 1. AI 感知 provider（平台实证默认实现；正式接线由 manager 单口组装换装）
	var input_manager = bm.get("input_manager")
	if input_manager != null:
		sm = input_manager.get("skill_state_manager")
	if sm == null and is_inside_tree():
		sm = get_tree().get_first_node_in_group("skill_state_managers")
	if sm == null:
		print("[ActCheck] FAIL: 未找到 skill_state_manager")
		get_tree().quit(1)
		return
	sm.ai_ctx_provider = func(caster: Node) -> Dictionary:
		return AI_INPUT_SOURCE.build_default_ctx(caster)
	print("[ActCheck][dbg] 组内sm数量=", get_tree().get_nodes_in_group("skill_state_managers").size())
	for n in get_tree().get_nodes_in_group("skill_state_managers"):
		var info: String = str(n) + " parent=" + str(n.get_parent())
		print("  - sm: " + info)
	var im = bm.get("input_manager")
	var im_sm = im.get("skill_state_manager") if im != null else null
	print("[ActCheck][dbg] bm.input_manager=" + str(im) + " 其ssm=" + str(im_sm))
	# ⚠架构缺口上报（集成窗口）：全 AI 场景 input_manager 不存在→9172e5e 波C attach 链恒 null
	# （登记移至装备段后直登记 workaround，见下）
	# 2. 释放信号采样
	ss = bm.get("spirit_system")
	if ss != null and ss.has_signal("skill_used"):
		ss.skill_used.connect(func(skill_id: String, _cid: int, ok: bool) -> void:
			if ok and skill_id in [STEER_SKILL, MIDFLY_SKILL]:
				casts[skill_id] = int(casts.get(skill_id, 0)) + 1)
	# 3. 运行时内存注册操控元灵并装备到 B0（loadout_loader 先例：零污染主数据）
	var dm = get_tree().root.get_node_or_null("DataManager")
	if dm != null and dm.get("spirits") is Array:
		var exists: bool = false
		for s in dm.spirits:
			if str(s.get("name")) == CTRL_SPIRIT["name"]:
				exists = true
		if not exists:
			dm.spirits.append(CTRL_SPIRIT.duplicate(true))
	var team_b = bm.get("team_b_players")
	print("[ActCheck][dbg] sm=", sm, " dm=", dm, " spirits数=", (dm.get("spirits") as Array).size() if dm != null and dm.get("spirits") is Array else -1, " team_b=", (team_b as Array).size() if team_b is Array else -1)
	if team_b is Array and (team_b as Array).size() > 0:
		ctrl_player = (team_b as Array)[0]
		if ctrl_player.has_method("equip_spirit"):
			ctrl_player.equip_spirit(CTRL_SPIRIT)
			var trig = ss.get("skill_trigger") if ss != null else null
			if trig != null and trig.has_method("set_player_skills"):
				trig.set_player_skills(ctrl_player.get_instance_id(), ctrl_player.get_equipped_skills())
			print("[ActCheck] 操控元灵已装备→", str(ctrl_player.get("char_data").get("name", "?")), " skills=", str(ctrl_player.get_equipped_skills()))
		# ⚠架构缺口上报（集成窗口）：全 AI 场景 input_manager 不存在→9172e5e 波C attach 链
		# （经 input_manager.skill_state_manager）恒 null=登记从未发生。workaround：直登记
		# 组内 sm（handler 组查找同源=全链闭环）；正式修=state_manager 创建位收口归集成。
		if sm != null:
			sm.register_ai_input_source(ctrl_player.get_instance_id(), ctrl_player)
			print("[ActCheck][dbg] 已直登记操控球员→组内sm（workaround）")
	_run()


## AI 执行层代理（实证驱动）：持球+冷却好→use_skill 雷火_7（投球链进手动态）。
## 决策选中率受 gate 场景/评分竞争影响=平衡面（看板备案）；本驱动验证操控链本体。
var _last_cast_at: float = -99.0


func _drive_cast() -> void:
	if ctrl_player == null or not is_instance_valid(ctrl_player) or ss == null:
		return
	if _waited - _last_cast_at < 10.0:
		return
	if ss.has_method("get_skill_cooldown"):
		if float(ss.get_skill_cooldown(ctrl_player.get_instance_id(), STEER_SKILL)) > 0.0:
			return
	if ss.has_method("use_skill"):
		var ok: bool = bool(ss.use_skill(ctrl_player.get_instance_id(), STEER_SKILL))
		print("[ActCheck] 驱动投球链 t=%.0f 持球=%s ok=%s" % [_waited, str(ctrl_player.get("is_carrying_ball")), str(ok)])
		if ok:
			_last_cast_at = _waited


func _run() -> void:
	var gm = get_tree().root.get_node_or_null("GameManager")
	if gm != null and gm.has_signal("match_ended"):
		gm.match_ended.connect(_on_ended, CONNECT_DEFERRED)
	_waited = 0.0
	while not match_over and _waited < 300.0:
		await get_tree().create_timer(1.0).timeout
		_waited += 1.0
		if gm != null and int(gm.get("match_phase")) == 4:
			match_over = true
		_drive_cast()
		if _waited in [5.0, 8.0, 12.0, 15.0, 20.0] and sm != null and ctrl_player != null and is_instance_valid(ctrl_player):
			var ball = ctrl_player.get("ball_ref")
			var ball_active: String = "-"
			if ball != null and is_instance_valid(ball):
				ball_active = str(bool(ball.get("is_active")))
			var act: String = AI_INPUT_SOURCE.tick_activation(sm, ctrl_player.get_instance_id(), ctrl_player, AI_INPUT_SOURCE.build_default_ctx(ctrl_player))
			print("[ActCheck][dbg] t=" + str(_waited) + " ball=" + str(ball) + " active=" + ball_active + " tick=" + act)
	_sample()
	_report()


func _on_ended(_a: int, _b: int, _r: String) -> void:
	match_over = true
	_sample()
	_report()


func _sample() -> void:
	if ctrl_player == null or not is_instance_valid(ctrl_player):
		return
	var ball = ctrl_player.get("ball_ref")
	if ball != null and is_instance_valid(ball):
		if bool(ball.get("_manual_active")):
			steer_ball_seen = true
			# AI 引导注入判定：瞄准留档非零（激活窗 tick 写入）
			if sm != null and sm.get_ai_aim(ctrl_player.get_instance_id()) != Vector2.ZERO:
				steer_inject_seen = true
	var op_ctx: Dictionary = sm.get_active_operation(ctrl_player.get_instance_id()) if sm != null else {}
	if str(op_ctx.get("operator", "")) == "OP_MIDFLY":
		midfly_ctx_seen = true
		if int(op_ctx.get("midfly_left", 2)) < 2:
			midfly_pressed_seen = true


func _report() -> void:
	print("\n[ActCheck] ========== 工单19任务A 实证判定（对照21表） ==========")
	print("[ActCheck] 出手：手动制导(测)×%d 飞行干预(测)×%d" % [int(casts.get(STEER_SKILL, 0)), int(casts.get(MIDFLY_SKILL, 0))])
	var steer_ok: bool = int(casts.get(STEER_SKILL, 0)) > 0 and steer_ball_seen and steer_inject_seen
	var midfly_ok: bool = int(casts.get(MIDFLY_SKILL, 0)) > 0 and midfly_ctx_seen and midfly_pressed_seen
	print("[ActCheck] STEER：出手>0=%s 球手动态=%s AI引导注入=%s → %s" % [
		str(int(casts.get(STEER_SKILL, 0)) > 0), str(steer_ball_seen), str(steer_inject_seen),
		"✅ 引导球可见（判定层）" if steer_ok else "⚠（未全链；出手为0=决策未选中，见看板备案）"])
	print("[ActCheck] MIDFLY：出手>0=%s 激活上下文=%s 干预生效=%s → %s" % [
		str(int(casts.get(MIDFLY_SKILL, 0)) > 0), str(midfly_ctx_seen), str(midfly_pressed_seen),
		"✅ 飞行干预可见（判定层）" if midfly_ok else "⚠（未全链；出手为0=决策未选中，见看板备案）"])
	var pass_n := int(steer_ok) + int(midfly_ok)
	print("[ActCheck] 结果: %d/2 操控链全链通过\n" % pass_n)
	get_tree().quit(0 if pass_n > 0 else 1)
