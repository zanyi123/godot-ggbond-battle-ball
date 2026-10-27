## 工单01 S11 · 网络套件 C：NetSession 双端全流程（同进程 1v1 + 队伍频道白盒）
## 运行：bash ./run_suite_guarded.sh res://scripts/test3d/regression/test_net_session_flow.gd
## 覆盖：S1 入房握手/槽位分配、D3+D15 匹配门（满员+双就绪→提前开赛）、M1 默认阵容开赛、
##       D18 1v1 对局聊天禁用、结算回大厅、room 频道聊天互通、S13.2 限流、D15 掉线全场取消、
##       D18 team 频道敌方不达（白盒注入 6P 阵营，省两进程）。
extends SceneTree

const T_PORT := 18901
const T_PORT2 := 18902

var _pass: int = 0
var _fail: int = 0

# 信号收集（成员变量，具名回调写入）
var _host_chats: Array = []
var _guest_chats: Array = []
var _g1_chats: Array = []
var _g2_chats: Array = []
var _host_blocked: Array = []
var _g1_blocked_cnt: int = 0
var _host_cancel: String = ""
var _guest_result: Dictionary = {}
var _guest_started: Dictionary = {}
var _host_notices: Array = []

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

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _pump(a: NetSession, b: NetSession, frames: int) -> void:
	for i in frames:
		a.update(0.016)
		b.update(0.016)
		await process_frame

func _run() -> void:
	print("\n========== 工单01 · 网络套件 C（会话全流程 1v1） ==========\n")

	# ── 建房 + 入房握手
	var host := NetSession.new(true, "房主")
	host.t_match_wait = 8.0; host.t_pick = 0.2; host.t_load = 0.1; host.t_heartbeat = 0.1; host.t_peer_timeout = 2.0; host.t_result_wait = 0.4
	host.chat_display.connect(func(c: Dictionary, mine: bool): _host_chats.append(c))
	host.chat_blocked.connect(func(r: String): _host_blocked.append(r))
	host.cancelled.connect(func(r: String): _host_cancel = r)
	host.notice.connect(func(n: Dictionary): _host_notices.append(n))
	_assert(host.create_room(NetSchema.MP_1V1, T_PORT), "S1a: host 建房（MP_1V1, port %d）" % T_PORT)

	var guest := NetSession.new(false, "客人")
	guest.t_heartbeat = 0.1
	guest.chat_display.connect(func(c: Dictionary, mine: bool): _guest_chats.append(c))
	guest.match_started.connect(func(cfg: Dictionary): _guest_started = cfg)
	guest.match_result.connect(func(r: Dictionary): _guest_result = r)
	_assert(guest.join_room("127.0.0.1", T_PORT), "S1b: guest 发起入房连接")

	await _pump(host, guest, 60)
	_assert(guest.phase == NetSchema.PHASE_LOBBY, "S1c: 握手完成 guest 入房（WELCOME→LOBBY）")
	_assert(guest._slots.size() == 2 and host._slots.size() == 2, "S1d: 槽位=2 满员（房主 A/0 队长 + 客人 B/0 队长）")
	var g_slot: Dictionary = guest.local_slot()
	_assert(str(g_slot.get("team")) == "B" and bool(g_slot.get("captain")), "S1e: 1v1 第二人=B 队队长（D4 二人各为队长）")

	# ── D3 匹配门：满员 → 未就绪保持等待；双就绪 → 提前过门开赛
	await _pump(host, guest, 20)
	_assert(host.phase == NetSchema.PHASE_LOBBY and host._gate_at >= 0.0, "D3a: 满员后匹配门启动（未就绪不进）")
	host.set_local_ready(true)
	guest.set_local_ready(true)
	await _pump(host, guest, 120)
	_assert(host.phase == NetSchema.PHASE_IN_MATCH and guest.phase == NetSchema.PHASE_IN_MATCH, "D3b: 双就绪 → 提前过门 → PICKING→LOADING→IN_MATCH 直通（M1 默认阵容）")
	var cfg: Dictionary = _guest_started
	_assert(str(cfg.get("mode")) == NetSchema.MP_1V1 and (cfg.get("roster_a") as Array).size() == 1 and (cfg.get("roster_b") as Array).size() == 1, "S5a: 开赛配置下发（模式/双方阵容各 1 人，M1 默认）")
	_assert(str(cfg.get("field")) == "full_1300x780", "S6a: 1v1 用正常全场（主人裁定 1026-5）")
	var ra0: Dictionary = (cfg.get("roster_a") as Array)[0] if (cfg.get("roster_a") as Array).size() > 0 else {}
	_assert(str(ra0.get("char_id", "")) != "" and str(ra0.get("spirit_id", "")) != "", "S3a: 无人选角→超时随机兜底进配置（S3 尾款）")

	# ── D18：1v1 对局中聊天禁用（无队友对象）
	var blocked_before := _host_blocked.size()
	host.send_chat("对局聊天应被禁用")
	guest.send_chat("对局聊天应被禁用")
	await _pump(host, guest, 10)
	_assert(_host_blocked.size() == blocked_before + 1, "D18a: 1v1 对局打字聊天被禁用（本地拦截）")
	_assert(_host_chats.is_empty() and _guest_chats.is_empty(), "D18b: 禁用期间零聊天到达双方")

	# ── 结算 → 自动回大厅（S7：30s 常量，注入 0.4s）
	host.end_match({"score": {"A": 2, "B": 1}, "winner": "A"})
	await _pump(host, guest, 20)
	_assert(guest.phase == NetSchema.PHASE_RESULTS and not _guest_result.is_empty(), "S7a: host 结算广播 → guest 收 RESULT 进结算")
	await _pump(host, guest, 40)
	_assert(host.phase == NetSchema.PHASE_LOBBY and guest.phase == NetSchema.PHASE_LOBBY, "S7b: 结算窗口到点 → 双方自动回大厅（就绪重置）")

	# ── room 频道聊天互通（D18：大厅=全员；D22：host 星型转发）
	host.send_chat("回大厅了，再来一把")
	await _pump(host, guest, 20)
	_assert(_guest_chats.size() == 1 and str((_guest_chats[0] as Dictionary).get("text")) == "回大厅了，再来一把", "S13a: 大厅 room 频道 → 全员互通（host 发 guest 收）")
	_assert(str((_guest_chats[0] as Dictionary).get("channel")) == NetSchema.CHAT_CHANNEL_ROOM, "S13b: 频道标记=room（D18 矩阵）")
	guest.send_chat("好")
	await _pump(host, guest, 20)
	_assert(_host_chats.size() == 2 and str((_host_chats[1] as Dictionary).get("from_name")) == "客人", "S13c: guest 发 → host 星型转发回显（D22）")

	# ── S13.2 限流：10s 窗口 5 条，第 6 条丢弃+本地提示
	host._chat_log.clear()   # 白盒：清窗（前面已发 2 条）
	for i in 6:
		host.send_chat("刷屏%d" % i)
		await _frames(1)
	var shown := 0
	for c in _host_chats:
		if str((c as Dictionary).get("text")).begins_with("刷屏"):
			shown += 1
	_assert(shown == 5, "S13d: 限流生效——窗口内第 6 条被丢（显示 %d/6）" % shown)
	var rate_blocked := false
	for r in _host_blocked:
		if str(r).contains("频繁"):
			rate_blocked = true
	_assert(rate_blocked, "S13e: 超限本地提示「发送太频繁」")

	# ── D15：等待阶段掉线 → 全场取消回大厅
	var host_peer_key: int = int(guest.transport.host_peer_id())
	guest.transport.drop_peer(host_peer_key)
	await _pump(host, guest, 60)
	_assert(not _host_cancel.is_empty() and _host_cancel.contains("掉线"), "D15a: 等待阶段 guest 掉线 → host 全场取消（原因含「掉线」）")
	_assert(host.phase == NetSchema.PHASE_LOBBY and host._slots.size() == 1, "D15b: 取消后回大厅、槽位回收（余 1 人）")
	var cancel_notice_cnt := 0
	for n in _host_notices:
		if str((n as Dictionary).get("type")) == "cancel":
			cancel_notice_cnt += 1
	_assert(cancel_notice_cnt >= 1, "D15c: 取消播报已发（D11 通道）")
	host.leave()

	# ══════════ 第二幕：S3 真选角（队内仲裁 D16）+ team 频道敌方不达（白盒注入阵营） ══════════
	print("\n---------- 第二幕：S3 选角 + D18 team 频道隔离（6P 白盒） ----------")
	var h2 := NetSession.new(true, "甲")
	h2.t_match_wait = 0.8; h2.t_heartbeat = 0.1; h2.t_pick = 30.0; h2.t_load = 0.1
	h2.char_pool = ["c1", "c2", "c3", "c4"]
	h2.spirit_pool = ["s1", "s2", "s3"]
	h2.create_room(NetSchema.MP_3V3_COOP, T_PORT2)
	var g1 := NetSession.new(false, "乙")
	g1.t_heartbeat = 0.1
	g1.join_room("127.0.0.1", T_PORT2)
	var g2 := NetSession.new(false, "丙")
	g2.t_heartbeat = 0.1
	g2.join_room("127.0.0.1", T_PORT2)
	g1.chat_display.connect(func(c: Dictionary, mine: bool): _g1_chats.append(c))
	g1.chat_blocked.connect(func(r: String): _g1_blocked_cnt += 1)
	g2.chat_display.connect(func(c: Dictionary, mine: bool): _g2_chats.append(c))
	for i in 80:
		h2.update(0.016); g1.update(0.016); g2.update(0.016)
		await process_frame
	_assert(h2._slots.size() == 3, "W1: 6P 房三人入（A/0 A/1 A/2）")
	# 三人 ready → 匹配门 → PICKING
	h2.set_local_ready(true); g1.set_local_ready(true); g2.set_local_ready(true)
	for i in 120:
		h2.update(0.016); g1.update(0.016); g2.update(0.016)
		await process_frame
		if h2.phase == NetSchema.PHASE_PICKING:
			break
	_assert(h2.phase == NetSchema.PHASE_PICKING, "P1: 全就绪过门进选角（PICKING）")
	# 队内撞车：g2 先锁 c1，g1 再锁 c1 → 被拒重选
	g2.pick_and_lock("c1", "s1")
	for i in 30:
		h2.update(0.016); g1.update(0.016); g2.update(0.016)
		await process_frame
	var g1_blocked_before := _g1_blocked_cnt
	g1.pick_and_lock("c1", "s2")
	for i in 30:
		h2.update(0.016); g1.update(0.016); g2.update(0.016)
		await process_frame
	_assert(_g1_blocked_cnt > g1_blocked_before, "P2: 队内撞车被拒（D16 队内唯一，提示重选）")
	g1.pick_and_lock("c2", "s2")
	h2.pick_and_lock("c3", "s3")
	for i in 120:
		h2.update(0.016); g1.update(0.016); g2.update(0.016)
		await process_frame
		if h2.phase == NetSchema.PHASE_IN_MATCH:
			break
	_assert(h2.phase == NetSchema.PHASE_IN_MATCH, "P3: 全员锁定 → 提前进加载开赛（不必等满 60s）")
	var picks: Array = []
	for e in h2._match_config.get("roster_a", []):
		picks.append(str((e as Dictionary).get("char_id", "")))
	_assert(picks.has("c1") and picks.has("c2") and picks.has("c3") and picks.size() == 3, "P4: 配置携带队内唯一 picks（D16）")
	# 白盒注入：把丙调到 B 队（6P 需 4 人才自然分 B；此处省两进程直测矩阵），对局阶段测频道
	h2._slots[2]["team"] = "B"
	h2._slots[2]["captain"] = true
	h2._set_phase(NetSchema.PHASE_IN_MATCH)
	h2.send_chat("A 队战术：先集火")
	await h2_pump(h2, g1, g2, 30)
	_assert(_g1_chats.size() == 1, "D18c: 对局 team 频道 → 同队（乙·A 队）收到")
	_assert(_g2_chats.is_empty(), "D18d: 对局 team 频道 → 敌方（丙·B 队）不达（防偷听战术）")
	h2.leave(); g1.leave(); g2.leave()

	# ══════════ 第三幕：D16 敌我可重复（1v1 双方同款） ══════════
	print("\n---------- 第三幕：D16 敌我同款（1v1） ----------")
	var h3 := NetSession.new(true, "东")
	h3.t_match_wait = 0.6; h3.t_heartbeat = 0.1; h3.t_pick = 30.0; h3.t_load = 0.1
	h3.char_pool = ["c1", "c2"]
	h3.spirit_pool = ["s1", "s2"]
	h3.create_room(NetSchema.MP_1V1, T_PORT2 + 1)
	var g3b := NetSession.new(false, "西")
	g3b.t_heartbeat = 0.1
	g3b.join_room("127.0.0.1", T_PORT2 + 1)
	for i in 80:
		h3.update(0.016); g3b.update(0.016)
		await process_frame
	h3.set_local_ready(true); g3b.set_local_ready(true)
	for i in 150:
		h3.update(0.016); g3b.update(0.016)
		await process_frame
		if h3.phase == NetSchema.PHASE_PICKING:
			break
	_assert(h3.phase == NetSchema.PHASE_PICKING, "E1: 1v1 进选角")
	# 双方选同款球员+元灵（敌队同款合法，D16 主人裁定）
	h3.pick_and_lock("c1", "s1")
	g3b.pick_and_lock("c1", "s1")
	for i in 120:
		h3.update(0.016); g3b.update(0.016)
		await process_frame
		if h3.phase == NetSchema.PHASE_IN_MATCH:
			break
	_assert(h3.phase == NetSchema.PHASE_IN_MATCH, "E2: 敌我同款双双锁定不被拒（D16 敌方可重复）")
	var ra3 := str(((h3._match_config.get("roster_a") as Array)[0] as Dictionary).get("char_id", ""))
	var rb3 := str(((h3._match_config.get("roster_b") as Array)[0] as Dictionary).get("char_id", ""))
	_assert(ra3 == "c1" and rb3 == "c1", "E3: 配置双方同款球员（镜像对决成立）")
	h3.leave(); g3b.leave()

func h2_pump(h: NetSession, a: NetSession, b: NetSession, frames: int) -> void:
	for i in frames:
		h.update(0.016); a.update(0.016); b.update(0.016)
		await process_frame
