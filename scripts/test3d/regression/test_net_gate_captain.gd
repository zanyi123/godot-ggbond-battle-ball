## 工单01 S11 · 网络套件 D：S7 面板门禁全分支（队长确认/超时判负/判负自动继续/D10 转让/1v1 判负）
## 运行：bash ./run_suite_guarded.sh res://scripts/test3d/regression/test_net_gate_captain.gd
## 覆盖：D1 就绪逐人、D2 队长确认（非队长无效）、D4 1v1 合一、D5+D6 面板 60s+15s、
##       D7 判负（3v3 个人出局自动继续 / 1v1 整场结算）、D10 队长判负顺延转让。
extends SceneTree

const P1 := 19011   # COOP 3 人房
const P2 := 19012   # 1v1 房

var _pass: int = 0
var _fail: int = 0

var _g1_gates: Array = []      # guest1 收到的门状态序列
var _g1_notices: Array = []    # guest1 收到的播报
var _g3_result: Dictionary = {}

func _initialize() -> void:
	await _run()
	print("\n========== 结果：%d/%d PASS ==========" % [_pass, _pass + _fail])
	quit(0 if _fail == 0 else 1)

func _assert(cond: bool, n: String) -> void:
	if cond:
		_pass += 1
		print("  ✅ PASS: " + n)
	else:
		_fail += 1
		print("  ❌ FAIL: " + n)

## 条件泵：双/三端步进直到 cond 为真或超帧（防固定帧数吞掉时序窗口）
func _pump(sessions: Array, cond: Callable, max_frames: int = 200) -> bool:
	for i in max_frames:
		for s in sessions:
			(s as NetSession).update(0.016)
		await process_frame
		if cond.call():
			return true
	return cond.call()

func _short(s: NetSession) -> void:
	s.t_match_wait = 0.6; s.t_pick = 0.1; s.t_load = 0.05
	s.t_heartbeat = 0.1; s.t_peer_timeout = 2.0; s.t_result_wait = 30.0
	s.t_panel = 1.2; s.t_grace = 0.4

func _run() -> void:
	print("\n========== 工单01 · 网络套件 D（S7 面板门禁） ==========\n")

	# ════ 第一幕：COOP 3 人房——门通过分支 + 超时判负自动继续 + D10 转让 ════
	var host := NetSession.new(true, "队长甲")
	_short(host)
	_assert(host.create_room(NetSchema.MP_3V3_COOP, P1), "G0a: COOP 建房")
	var g1 := NetSession.new(false, "乙")
	_short(g1)
	g1.gate_state_changed.connect(func(g: Dictionary): _g1_gates.append(g))
	g1.notice.connect(func(n: Dictionary): _g1_notices.append(n))
	g1.join_room("127.0.0.1", P1)
	var g2 := NetSession.new(false, "丙")
	_short(g2)
	g2.join_room("127.0.0.1", P1)
	await _pump([host, g1, g2], func(): return host._slots.size() == 3)
	_assert(host._slots.size() == 3, "G0b: 三人满员（A 队 0/1/2）")

	# 三人就绪 → 匹配门提前过 → IN_MATCH → prep 门自动开（到即停，不吃面板计时窗）
	host.set_local_ready(true); g1.set_local_ready(true); g2.set_local_ready(true)
	await _pump([host, g1, g2], func(): return host.phase == NetSchema.PHASE_IN_MATCH and not g1.get_gate().is_empty())
	_assert(host.phase == NetSchema.PHASE_IN_MATCH and str(g1.get_gate().get("panel")) == NetSchema.PANEL_PREP, "G1: 全就绪过匹配门进对局，prep 门自动开（D5 计时起点）")

	# ── 分支一：全员准备+队长确认 → 门通过（D1+D2）──
	g1.set_local_ready(true)
	g2.set_local_ready(true)
	await _pump([host, g1, g2], func(): return (host.get_gate().get("ready") as Dictionary).get(g1.local_peer_id(), false) == true, 30)
	# 非队长确认无效（D2）
	g2.confirm_panel()
	for i in 10:
		for s in [host, g1, g2]:
			(s as NetSession).update(0.016)
		await process_frame
	_assert(not host.get_gate().is_empty(), "G2a: 非队长确认无效（门仍关）")
	host.set_local_ready(true)
	host.confirm_panel()
	await _pump([host, g1, g2], func(): return host.get_gate().is_empty(), 30)
	_assert(host.get_gate().is_empty(), "G2b: 全员就绪+队长确认 → 门通过")
	await _pump([host, g1, g2], func(): return g1.get_gate().is_empty(), 30)
	_assert(g1.get_gate().is_empty(), "G2c: guest 同步收到通过（gate 清空广播）")

	# ── 分支二：中场门超时 60s+宽限 15s → 未就绪者个人判负出局（D6+D7）→ 门重算自动继续 ──
	host.host_open_half_gate()
	await _pump([host, g1, g2], func(): return str(host.get_gate().get("panel")) == NetSchema.PANEL_HALF, 30)
	_assert(str(host.get_gate().get("panel")) == NetSchema.PANEL_HALF, "G3a: 中场门开启（half）")
	g1.set_local_ready(true)
	host.set_local_ready(true)
	# g2 不准备 → 面板 1.2s + 宽限 0.4s → 判负（实测链路含发送往返，上限放宽）
	await _pump([host, g1, g2], func():
		var g := g1.get_gate()
		return str(g.get("panel")) == "auto_pass", 500)
	var g2_forfeited := false
	for s in host._slots:
		if str(s["name"]) == "丙":
			g2_forfeited = bool(s.get("forfeited", false))
	_assert(g2_forfeited, "G3b: 超时未准备者判负出局（forfeited 标记，D7 个人出局不散场）")
	_assert(str(g1.get_gate().get("panel")) == "auto_pass", "G3c: 判负后门重算自动继续（剩余全员就绪=通过，广播 guest）")
	var forfeit_notice_g1 := false
	var grace_notice := false
	for n in _g1_notices:
		if str((n as Dictionary).get("type")) == "forfeit":
			forfeit_notice_g1 = true
		if str((n as Dictionary).get("type")) == "grace":
			grace_notice = true
	_assert(forfeit_notice_g1, "G3d: 判负小字播报到达 guest（D11 通道）")
	_assert(grace_notice, "G3e: 面板超时进入宽限的播报（D6）")

	# ── 分支三：D10 队长判负 → 顺延转让 ──
	host.host_open_half_gate()
	await _pump([host, g1, g2], func(): return str(host.get_gate().get("panel")) == NetSchema.PANEL_HALF, 30)
	g1.set_local_ready(true)
	await _pump([host, g1, g2], func():
		var g := g1.get_gate()
		return str(g.get("panel")) == "auto_pass", 500)
	var host_forfeited := false
	var g1_captain := false
	for s in host._slots:
		if str(s["name"]) == "队长甲":
			host_forfeited = bool(s.get("forfeited", false))
		if str(s["name"]) == "乙":
			g1_captain = bool(s.get("captain", false))
	_assert(host_forfeited and g1_captain, "G4: 队长判负出局 → 队长顺延转让（D10，不等人点）")
	host.leave(); g1.leave(); g2.leave()

	# ════ 第二幕：1v1——整场判负（D7 前款）+ D4 按钮合一 ════
	_g3_result = {}
	var h2 := NetSession.new(true, "独狼")
	_short(h2)
	h2.create_room(NetSchema.MP_1V1, P2)
	var g3 := NetSession.new(false, "对手")
	_short(g3)
	g3.match_result.connect(func(r: Dictionary): _g3_result = r)
	g3.join_room("127.0.0.1", P2)
	await _pump([h2, g3], func(): return h2._slots.size() == 2)
	h2.set_local_ready(true); g3.set_local_ready(true)
	await _pump([h2, g3], func(): return h2.phase == NetSchema.PHASE_IN_MATCH, 150)
	_assert(h2.phase == NetSchema.PHASE_IN_MATCH, "G5a: 1v1 开赛进对局")
	# D4：1v1 就绪即确认——host ready 后 confirm 自动置位，只等 guest
	h2.set_local_ready(true)
	await _pump([h2, g3], func(): return bool(h2.get_gate().get("confirm", false)), 20)
	_assert(bool(h2.get_gate().get("confirm", false)), "G5b: 1v1 confirm 随就绪自动置位（D4 按钮合一）")
	# guest 不准备 → 面板+宽限 → 整场判负 → RESULTS（判负链含往返延迟，上限放宽）
	await _pump([h2, g3], func(): return h2.phase == NetSchema.PHASE_RESULTS, 500)
	_assert(h2.phase == NetSchema.PHASE_RESULTS, "G5c: 1v1 超时判负=整场结算（RESULTS，比赛不再继续）")
	await _pump([h2, g3], func(): return not _g3_result.is_empty(), 50)
	_assert(not _g3_result.is_empty() and str(_g3_result.get("reason")) == "forfeit", "G5d: 对方收到判负结算包（reason=forfeit）")
	h2.leave(); g3.leave()
