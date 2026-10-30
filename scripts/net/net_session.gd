## 工单01 S1 会话层 · 房间状态机/槽位/队长/就绪/匹配门/心跳/聊天（host 权威）
## 裁定对齐：D1~D3（就绪/确认/匹配门）、D9（掉线）、D10（队长）、D15（等待阶段取消制）、
##           D18（聊天频道矩阵）、D22（host 星型转发）、S13.2 限流。
## host=唯一权威（room 状态/开赛/取消/聊天分发）；guest 上报+渲染。
## 时间源可注入（time_fn）——测试虚拟时钟快进，真机默认 ticks 秒。
class_name NetSession
extends RefCounted

signal state_changed(phase: String)
signal room_updated(room: Dictionary)          # 本端可见房间状态（含自己 slot）
signal peer_joined(peer_id: int, name: String)
signal peer_left(peer_id: int)
signal chat_display(chat: Dictionary, mine: bool)
signal chat_blocked(reason: String)
signal notice(notice: Dictionary)
signal match_started(config: Dictionary)       # 开赛配置（模式/阵容/槽位→peer）
signal match_result(result: Dictionary)
signal cancelled(reason: String)               # D15 等待阶段取消
signal host_lost()                             # guest 视角 host 失联（等待阶段=回大厅）
signal input_command_received(cmd: Dictionary) # host：收到 guest 指令
signal snapshot_received(snap: Dictionary)     # guest：收到快照
signal gate_state_changed(gate: Dictionary)    # S7 面板门状态（prep/half；全员准备+队长确认/宽限/判负）

const TEAM_A := "A"
const TEAM_B := "B"

var is_host: bool = false
var local_name: String = "玩家"
var mode: String = NetSchema.MP_1V1
var phase: String = NetSchema.PHASE_IDLE

var transport: NetTransport = null

# 时间常量（测试可注入覆盖）
var t_match_wait: float = NetSchema.MATCH_WAIT_S
var t_pick: float = NetSchema.PICK_TIME_S
var t_load: float = 2.0
var t_heartbeat: float = NetSchema.HEARTBEAT_S
var t_peer_timeout: float = NetSchema.PEER_TIMEOUT_S
var t_result_wait: float = 30.0
var t_panel: float = NetSchema.PANEL_TIME_S      # D5 面板倒计时 60s
var t_grace: float = NetSchema.GRACE_S           # D6 宽限 15s

var time_fn: Callable = func() -> float: return Time.get_ticks_msec() / 1000.0

var _slots: Array = []            # [{peer_id,name,team,slot,ready,captain}]
var _now: float = 0.0
var _gate_at: float = -1.0        # 匹配门启动时刻（满员时）
var _phase_at: float = 0.0
var _last_beat: float = 0.0
var _last_seen: Dictionary = {}   # peer_id -> last ts
var _host_seen: float = -999.0    # guest 视角：最近收到 host 任何包的时刻
var cmd_queue: Array = []   # host 侧指令队列（bridge 轮询消费；信号连接在 arena 内静默失效已实证，改队列直读）
var _chat_log: Dictionary = {}    # peer_id -> Array[ts]（限流窗口）
var _match_config: Dictionary = {}
var _gate: Dictionary = {}        # S7 面板门 {panel, ready:{peer_id:bool}, confirm:bool, deadline, grace_at}
var _picks: Dictionary = {}       # S3 选角：peer_id -> {char_id, spirit_id}（host 权威）
var char_pool: Array = []         # 球员池（默认 7；由大厅从 DataManager 组装传入）
var spirit_pool: Array = []       # 元灵池（默认 6 正式元灵，验收条目不进池）

# ══════════════ 生命周期 ══════════════

func _init(host: bool, player_name: String = "玩家") -> void:
	is_host = host
	local_name = player_name

func create_room(room_mode: String, port: int = NetSchema.PORT_GAME, player_name: String = "") -> bool:
	if player_name != "":
		local_name = player_name
	mode = room_mode
	transport = NetTransport.new()
	if not transport.start_server(port):
		return false
	_bind_transport()
	_slots = [_make_slot(1, local_name, TEAM_A, 0, true)]
	_set_phase(NetSchema.PHASE_LOBBY)
	_refresh_room()
	# S1：host 建房即广播房间信标（局域网发现）；_refresh_room 持续刷新人数
	transport.start_beacon(NetSchema.make_beacon_json(local_name, mode, _slots.size(), NetSchema.MODE_CAP.get(mode, 2)), NetSchema.PORT_DISCOVERY)
	return true

func join_room(host_ip: String, port: int = NetSchema.PORT_GAME, player_name: String = "") -> bool:
	if player_name != "":
		local_name = player_name
	transport = NetTransport.new()
	if not transport.start_client(host_ip, port):
		return false
	_bind_transport()
	_now = _time()
	_host_seen = _now
	# HELLO 延迟到 peer_connected 回调再发（ENet 握手中的 peer 发包会被丢弃）
	return true

func leave() -> void:
	if transport != null:
		transport.close()
		transport = null
	_slots = []
	_set_phase(NetSchema.PHASE_IDLE)

func _bind_transport() -> void:
	transport.peer_connected.connect(_on_peer_connected)
	transport.peer_disconnected.connect(_on_peer_disconnected)
	transport.packet_received.connect(_on_packet)

# ══════════════ 帧驱动（UI 每帧 / 测试小步） ══════════════

func update(delta: float = 0.0) -> void:
	if transport == null:
		return
	_now = _time()
	transport.poll(delta)
	if is_host:
		_host_tick()
	else:
		_guest_tick()

func _time() -> float:
	if time_fn.is_valid():
		return float(time_fn.call())
	return 0.0

# ── host 节拍：心跳、匹配门、PICKING/LOADING 直通、结算回收 ──
func _host_tick() -> void:
	_beat()
	match phase:
		NetSchema.PHASE_LOBBY:
			if _is_full() and _gate_at < 0.0:
				_gate_at = _now
				_refresh_room()
			if _gate_at >= 0.0:
				if _all_ready():
					_enter_picking()
				elif _now - _gate_at >= t_match_wait:
					# D15：到点有人未就绪 → 全场取消回大厅重新匹配
					_do_cancel("有人未准备")
		NetSchema.PHASE_PICKING:
			if _now - _phase_at >= t_pick:
				_enter_loading()
		NetSchema.PHASE_LOADING:
			if _now - _phase_at >= t_load:
				_start_match()
		NetSchema.PHASE_IN_MATCH:
			_gate_tick()
		NetSchema.PHASE_RESULTS:
			if _now - _phase_at >= t_result_wait:
				_back_to_lobby()

# ── guest 节拍：心跳 + host 失联判定（client 只有 host 一个 peer，断=host 失联）──
func _guest_tick() -> void:
	_beat()
	if _now - _host_seen > t_peer_timeout * 2.0:
		host_lost.emit()
		_host_seen = _now + 999999.0  # 只报一次，等 ENet 断开事件收尾

func _beat() -> void:
	if _now - _last_beat < t_heartbeat:
		return
	_last_beat = _now
	if is_host:
		transport.broadcast(NetSchema.MSG_PING, {"ts": _now})
	else:
		transport.send_to_host(NetSchema.MSG_PING, {"ts": _now})

# ══════════════ 网络事件 ══════════════

func _on_peer_connected(peer_id: int) -> void:
	# guest 侧：与 host 的 ENet 连接建立（此刻才可发首包）
	if not is_host:
		_last_seen[peer_id] = _now
		_host_seen = _now
		transport.send_to_host(NetSchema.MSG_HELLO, {"ver": NetSchema.PROTO_VERSION, "name": local_name})

func _on_peer_disconnected(peer_id: int) -> void:
	_last_seen.erase(peer_id)
	if is_host:
		var name := _slot_name(peer_id)
		_remove_slot(peer_id)
		if phase == NetSchema.PHASE_LOBBY or phase == NetSchema.PHASE_PICKING or phase == NetSchema.PHASE_LOADING:
			peer_left.emit(peer_id)
			# D15：等待阶段任一人掉线 → 全场取消回大厅
			_do_cancel("有玩家掉线（%s）" % name)
		else:
			peer_left.emit(peer_id)
			_broadcast_notice("leave", name, "%s 离开了比赛" % name)
			_transfer_captains()
			_refresh_room()
	else:
		host_lost.emit()
		peer_left.emit(peer_id)

func _on_packet(peer_id: int, msg_type: int, d: Dictionary, _channel: int) -> void:
	_last_seen[peer_id] = _now
	if not is_host:
		_host_seen = _now
		_guest_handle(msg_type, d)
	else:
		_host_handle(peer_id, msg_type, d)

# ── host 消息处理（权威）────────────────────────
func _host_handle(peer_id: int, msg_type: int, d: Dictionary) -> void:
	match msg_type:
		NetSchema.MSG_HELLO:
			var ver := str(d.get("ver", ""))
			if ver != NetSchema.PROTO_VERSION:
				transport.send_to(peer_id, NetSchema.MSG_REJECT, {"reason": "版本不一致（房主 %s / 你 %s）" % [NetSchema.PROTO_VERSION, ver]})
				return
			if _is_full():
				transport.send_to(peer_id, NetSchema.MSG_REJECT, {"reason": "房间已满"})
				return
			var pname := str(d.get("name", "玩家"))
			var slot := _assign_slot(peer_id, pname)
			transport.send_to(peer_id, NetSchema.MSG_WELCOME, {"your_peer_id": peer_id, "room": _room_dict()})
			peer_joined.emit(peer_id, pname)
			_broadcast_notice("join", pname, "%s 加入了房间" % pname)
			_refresh_room()
		NetSchema.MSG_READY:
			var want: bool = bool(d.get("ready", false))
			_set_ready(peer_id, want)
			# S7 面板门期间：就绪同时计入门（D1 逐面板逐人；1v1 ready 即确认 D4）
			if not _gate.is_empty() and not _slot_forfeited(peer_id):
				_gate["ready"][peer_id] = want
				if mode == NetSchema.MP_1V1 and want:
					_gate["confirm"] = true
				_broadcast_gate()
			_refresh_room()
		NetSchema.MSG_CONFIRM:
			# D2 队长确认（非队长无效；1v1 由 ready 兼任不处理）
			if not _gate.is_empty() and mode != NetSchema.MP_1V1 and _is_captain(peer_id):
				_gate["confirm"] = true
				_broadcast_gate()
		NetSchema.MSG_PICK:
			_host_handle_pick(peer_id, d)
		NetSchema.MSG_CHAT:
			_host_dispatch_chat(peer_id, d)
		NetSchema.MSG_INPUT_CMD:
			cmd_queue.append(d)   # 队列直读（bridge 轮询消费）；信号 emit 保留给外部监听者
			input_command_received.emit(d)

# ── guest 消息处理 ──────────────────────────────
func _guest_handle(msg_type: int, d: Dictionary) -> void:
	match msg_type:
		NetSchema.MSG_WELCOME:
			transport.set_local_id(int(d.get("your_peer_id", transport.local_id())))
			mode = str(d.get("room", {}).get("mode", mode))
			_set_phase(NetSchema.PHASE_LOBBY)
			_apply_room(d.get("room", {}))
			room_updated.emit(_room_dict())
		NetSchema.MSG_REJECT:
			chat_blocked.emit("入房被拒：" + str(d.get("reason", "")))
			leave()
		NetSchema.MSG_ROOM_STATE:
			_apply_room(d.get("room", {}))
			room_updated.emit(_room_dict())
		NetSchema.MSG_CHAT:
			chat_display.emit(d, false)
		NetSchema.MSG_START_MATCH:
			_match_config = d.get("config", {})
			_set_phase(NetSchema.PHASE_IN_MATCH)
			match_started.emit(_match_config)
		NetSchema.MSG_MATCH_CONFIG:
			_match_config = d
		NetSchema.MSG_PICK_REJECT:
			chat_blocked.emit("选角被拒：" + str(d.get("reason", "")))
		NetSchema.MSG_CANCEL:
			var reason := str(d.get("reason", ""))
			_set_phase(NetSchema.PHASE_LOBBY)
			cancelled.emit(reason)
		NetSchema.MSG_NOTICE:
			notice.emit(d)
		NetSchema.MSG_GATE:
			_gate = d
			gate_state_changed.emit(d)
		NetSchema.MSG_SNAPSHOT:
			snapshot_received.emit(d)
		NetSchema.MSG_RESULT:
			_set_phase(NetSchema.PHASE_RESULTS)
			match_result.emit(d)

# ══════════════ 对外动作（两端通用） ══════════════

## 就绪切换（D1；1v1 即确认 D4）
func set_local_ready(ready: bool) -> void:
	if is_host:
		_set_ready(local_peer_id(), ready)
		if not _gate.is_empty() and not _slot_forfeited(local_peer_id()):
			_gate["ready"][local_peer_id()] = ready
			if mode == NetSchema.MP_1V1 and ready:
				_gate["confirm"] = true
			_broadcast_gate()
		_refresh_room()
	else:
		transport.send_to_host(NetSchema.MSG_READY, {"ready": ready})

## 队长确认面板（D2；UI 的「开始比赛/继续比赛」按钮）
func confirm_panel() -> void:
	if is_host:
		if not _gate.is_empty() and mode != NetSchema.MP_1V1 and _is_captain(local_peer_id()):
			_gate["confirm"] = true
			_broadcast_gate()
	else:
		transport.send_to_host(NetSchema.MSG_CONFIRM, {})

## 发聊天（S13.2）：按 D18 矩阵本地判频道；1v1 对局禁用
func send_chat(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return
	trimmed = trimmed.substr(0, NetSchema.CHAT_TEXT_MAX)
	var channel := NetSchema.chat_channel_for_phase(phase)
	if channel == "none":
		chat_blocked.emit("当前阶段禁用聊天")
		return
	if mode == NetSchema.MP_1V1 and phase == NetSchema.PHASE_IN_MATCH:
		chat_blocked.emit("1v1 对局中无队友频道，仅快捷消息")
		return
	var chat := NetSchema.make_chat(channel, local_peer_id(), local_name, trimmed, _now)
	if is_host:
		_host_dispatch_chat(local_peer_id(), chat)
	else:
		transport.send_to_host(NetSchema.MSG_CHAT, chat)

## S5-2 指令上行：guest 本地输入 → host（move=世界系方向；skill_slot=-1=无）
func send_input_command(move: Vector2, skill_slot: int = -1) -> void:
	if is_host or transport == null:
		return
	# 指令走可靠通道：本构建 client→server 的不可靠上行实测全丢（快照下行不可靠却通——已探针实证）；
	# 带宽账：InputCommand ~200B×20Hz×6 人 ≈24KB/s，LAN/家用上行无压力（高频 aim 优化后置）
	transport.send_to_host(NetSchema.MSG_INPUT_CMD, NetSchema.make_input_command(local_peer_id(), 0, move, skill_slot, 0))

## host：对局内推快照（S5 驱动；M1 测试用）
func push_snapshot(snap: Dictionary) -> void:
	if is_host:
		transport.broadcast(NetSchema.MSG_SNAPSHOT, snap, NetSchema.CH_STATE, false)

## host：结束比赛进结算
func end_match(result: Dictionary) -> void:
	if not is_host:
		return
	transport.broadcast(NetSchema.MSG_RESULT, result)
	transport.flush()   # host 进程可能随即退出（sim 终局 quit）：不 flush 则 RESULT 死在 ENet 发送队列
	_set_phase(NetSchema.PHASE_RESULTS)
	match_result.emit(result)

## host：取消回大厅（D15 全场取消）
func _do_cancel(reason: String) -> void:
	_gate_at = -1.0
	for s in _slots:
		s["ready"] = false
	transport.broadcast(NetSchema.MSG_CANCEL, {"reason": reason})
	cancelled.emit(reason)
	notice.emit(NetSchema.make_notice("cancel", "", "匹配取消：%s，已回大厅" % reason))
	_set_phase(NetSchema.PHASE_LOBBY)
	_refresh_room()

# ══════════════ 聊天分发（D18 矩阵 + D22 星型转发 + 限流） ══════════════

func _host_dispatch_chat(from_peer: int, chat: Dictionary) -> void:
	var text := str(chat.get("text", ""))
	var channel := str(chat.get("channel", NetSchema.CHAT_CHANNEL_ROOM))
	# 限流：窗口内超限 → 静默丢弃 + 回发件人提示
	if not _chat_rate_ok(from_peer):
		if from_peer == local_peer_id():
			chat_blocked.emit("发送太频繁，稍后再试")
		else:
			transport.send_to(from_peer, NetSchema.MSG_NOTICE, NetSchema.make_notice("chat_rate", _slot_name(from_peer), "发送太频繁，稍后再试"))
		return
	# 频道矩阵（host 权威复查）
	var allowed := NetSchema.chat_channel_for_phase(phase)
	if allowed == "none" or (mode == NetSchema.MP_1V1 and phase == NetSchema.PHASE_IN_MATCH):
		return
	if channel != allowed:
		channel = allowed
		chat["channel"] = channel
	# 收件人（D22：host 星型转发；team=同队成员，room=全员）
	var from_team := _slot_team(from_peer)
	var targets: Array = []
	var local_in_targets := false
	for s in _slots:
		var pid := int(s["peer_id"])
		if channel == NetSchema.CHAT_CHANNEL_TEAM and str(s["team"]) != from_team:
			continue
		if pid == local_peer_id():
			local_in_targets = true
		else:
			targets.append(pid)
	for pid in targets:
		transport.send_to(pid, NetSchema.MSG_CHAT, chat)
	if local_in_targets:
		chat_display.emit(chat, from_peer == local_peer_id())

# ── 限流窗（10s 内最多 5 条，S13.2）──────────────
func _chat_rate_ok(peer_id: int) -> bool:
	var log: Array = _chat_log.get(peer_id, [])
	var keep: Array = []
	for ts in log:
		if _now - float(ts) <= NetSchema.CHAT_RATE_WINDOW_S:
			keep.append(float(ts))
	if keep.size() >= NetSchema.CHAT_RATE_MAX:
		_chat_log[peer_id] = keep
		return false
	keep.append(_now)
	_chat_log[peer_id] = keep
	return true

# ══════════════ 槽位 / 队长 / 房间状态 ══════════════

func _make_slot(peer_id: int, pname: String, team: String, slot: int, captain: bool) -> Dictionary:
	return {"peer_id": peer_id, "name": pname, "team": team, "slot": slot, "ready": false, "captain": captain}

## 分配规则（§二）：房主=A/0；1v1 第二人=B/0；COOP 全进 A；6P A 满 3 再进 B
func _assign_slot(peer_id: int, pname: String) -> Dictionary:
	var cap: int = NetSchema.MODE_CAP.get(mode, 2)
	var a_count := _team_count(TEAM_A)
	var b_count := _team_count(TEAM_B)
	var team := TEAM_A
	var slot := a_count
	if mode == NetSchema.MP_1V1:
		team = TEAM_B
		slot = 0
	elif mode == NetSchema.MP_3V3_6P and a_count >= 3:
		team = TEAM_B
		slot = b_count
	var s := _make_slot(peer_id, pname, team, slot, slot == 0)
	_slots.append(s)
	return s

func _remove_slot(peer_id: int) -> void:
	_slots = _slots.filter(func(s): return int(s["peer_id"]) != peer_id)

func _team_count(team: String) -> int:
	var n := 0
	for s in _slots:
		if str(s["team"]) == team:
			n += 1
	return n

func _slot_team(peer_id: int) -> String:
	for s in _slots:
		if int(s["peer_id"]) == peer_id:
			return str(s["team"])
	return ""

func _slot_name(peer_id: int) -> String:
	for s in _slots:
		if int(s["peer_id"]) == peer_id:
			return str(s["name"])
	return "玩家%d" % peer_id

func _set_ready(peer_id: int, ready: bool) -> void:
	for s in _slots:
		if int(s["peer_id"]) == peer_id:
			s["ready"] = ready

func _all_ready() -> bool:
	for s in _slots:
		if not bool(s["ready"]):
			return false
	return true

func _is_full() -> bool:
	return _slots.size() >= NetSchema.MODE_CAP.get(mode, 2)

## D10：队长=该队 slot 最小者（掉线/判负出局后顺延；出局者不得回任）
func _transfer_captains() -> void:
	for team in [TEAM_A, TEAM_B]:
		var members: Array = _slots.filter(func(s): return str(s["team"]) == team and not bool(s.get("forfeited", false)))
		members.sort_custom(func(a, b): return int(a["slot"]) < int(b["slot"]))
		var first: bool = true
		for m in members:
			m["captain"] = first
			first = false
		# 出局成员强制摘队长标（防 sort 抢回）
		for s in _slots:
			if bool(s.get("forfeited", false)):
				s["captain"] = false

func _refresh_room() -> void:
	_transfer_captains()
	var room := _room_dict()
	if is_host:
		transport.broadcast(NetSchema.MSG_ROOM_STATE, {"room": room})
		transport.update_beacon_text(NetSchema.make_beacon_json(local_name, mode, _slots.size(), NetSchema.MODE_CAP.get(mode, 2)))
	room_updated.emit(room)

func _apply_room(room: Dictionary) -> void:
	mode = str(room.get("mode", mode))
	phase = str(room.get("phase", phase))
	_slots = room.get("slots", [])

func local_peer_id() -> int:
	return transport.local_id() if transport != null else 1

func local_slot() -> Dictionary:
	var pid := local_peer_id()
	for s in _slots:
		if int(s["peer_id"]) == pid:
			return s
	return {}

func _room_dict() -> Dictionary:
	return {
		"phase": phase,
		"mode": mode,
		"host": 1,
		"cur": _slots.size(),
		"cap": NetSchema.MODE_CAP.get(mode, 2),
		"slots": _slots.duplicate(true),
	}

# ══════════════ 阶段流转（M1：PICKING/LOADING 直通默认阵容） ══════════════

func _set_phase(p: String) -> void:
	if phase == p:
		return
	phase = p
	_phase_at = _now
	state_changed.emit(p)

func _enter_picking() -> void:
	_gate_at = -1.0
	_picks.clear()
	if char_pool.is_empty():
		char_pool = ["char_001", "char_002", "char_003", "char_004", "char_005", "char_006", "char_007"]
	if spirit_pool.is_empty():
		spirit_pool = ["spirit_1", "spirit_2", "spirit_3", "spirit_4", "spirit_5", "spirit_6"]
	_set_phase(NetSchema.PHASE_PICKING)
	_refresh_room()

func _enter_loading() -> void:
	# S3 选角收口：未锁定者由 AI 选角策略补选（元灵AI域移交已交付 SpiritAIPickStrategy），
	# 策略缺失/异常回落随机（队内剩余池），随后组配置进 LOADING
	for s in _slots:
		var pid := int(s["peer_id"])
		if not _picks.has(pid):
			var team := str(s["team"])
			_picks[pid] = {
				"char_id": _strategy_pick("char", team, _team_free_chars(team)),
				"spirit_id": _strategy_pick("spirit", team, _team_free_spirits(team)),
			}
	_match_config = _build_default_config()
	transport.broadcast(NetSchema.MSG_MATCH_CONFIG, _match_config)
	_set_phase(NetSchema.PHASE_LOADING)
	_refresh_room()

## S3 选角：host 按 D16 队内唯一仲裁（敌我可重复）
func _host_handle_pick(peer_id: int, d: Dictionary) -> void:
	if phase != NetSchema.PHASE_PICKING or _slot_forfeited(peer_id):
		return
	var char_id := str(d.get("char_id", ""))
	var spirit_id := str(d.get("spirit_id", ""))
	var team := _slot_team(peer_id)
	for pid in _picks.keys():
		if int(pid) == peer_id:
			continue
		if _slot_team(int(pid)) != team:
			continue  # 敌队同款合法（D16）
		var pk: Dictionary = _picks[pid]
		if str(pk.get("char_id")) == char_id and char_id != "":
			transport.send_to(peer_id, NetSchema.MSG_PICK_REJECT, {"reason": "队友已选该球员"})
			return
		if str(pk.get("spirit_id")) == spirit_id and spirit_id != "":
			transport.send_to(peer_id, NetSchema.MSG_PICK_REJECT, {"reason": "队友已选该元灵"})
			return
	_picks[peer_id] = {"char_id": char_id, "spirit_id": spirit_id}
	# 全员锁定 → 提前进加载
	var all_locked := true
	for s in _slots:
		if not _picks.has(int(s["peer_id"])):
			all_locked = false
	if all_locked:
		_enter_loading()

func _team_free_chars(team: String) -> Array:
	var used: Array = []
	for pid in _picks.keys():
		if _slot_team(int(pid)) == team:
			used.append(str(( _picks[pid] as Dictionary).get("char_id", "")))
	var free := char_pool.duplicate()
	for u in used:
		free.erase(u)
	return free if not free.is_empty() else char_pool.duplicate()

func _team_free_spirits(team: String) -> Array:
	var used: Array = []
	for pid in _picks.keys():
		if _slot_team(int(pid)) == team:
			used.append(str((_picks[pid] as Dictionary).get("spirit_id", "")))
	var free := spirit_pool.duplicate()
	for u in used:
		free.erase(u)
	return free if not free.is_empty() else spirit_pool.duplicate()

func _random_from(pool: Array) -> String:
	if pool.is_empty():
		return ""
	return str(pool[randi() % pool.size()])

## AI 选角策略补选（S3-4：元灵AI域 SpiritAIPickStrategy；静态接口 pick_character/pick_spirit）；
## 脚本缺失/异常回落随机（移交单保底路径约定）
func _strategy_pick(kind: String, team: String, free: Array) -> String:
	if free.is_empty():
		return ""
	var picks: Array = []
	for pid in _picks.keys():
		if _slot_team(int(pid)) == team:
			picks.append(_picks[pid])
	var script = load("res://scripts/battle/spirit_ai/pick_strategy.gd")
	if script != null and script.can_instantiate() == false and script.has_method("pick_character"):
		var id := ""
		if kind == "char":
			id = str(script.pick_character(free, picks))
		else:
			id = str(script.pick_spirit(free, picks))
		if id != "" and free.has(id):
			return id
	return _random_from(free)

## guest：选角锁定上报（S3；被拒走 chat_blocked 信号提示重选）
func pick_and_lock(char_id: String, spirit_id: String) -> void:
	if is_host:
		_host_handle_pick(local_peer_id(), {"char_id": char_id, "spirit_id": spirit_id})
	else:
		transport.send_to_host(NetSchema.MSG_PICK, {"char_id": char_id, "spirit_id": spirit_id})

func _start_match() -> void:
	transport.broadcast(NetSchema.MSG_START_MATCH, {"config": _match_config})
	_set_phase(NetSchema.PHASE_IN_MATCH)
	match_started.emit(_match_config)
	_open_gate(NetSchema.PANEL_PREP)   # S7：开赛即开备战门（全员准备+队长确认）
	_refresh_room()

func _back_to_lobby() -> void:
	for s in _slots:
		s["ready"] = false
	_set_phase(NetSchema.PHASE_LOBBY)
	_refresh_room()

## 选角结果（含 M1 默认阵容直通时的随机兜底）；roster 条目带 picks（S3）
func _build_default_config() -> Dictionary:
	var roster_a: Array = []
	var roster_b: Array = []
	for s in _slots:
		var entry := {"peer_id": int(s["peer_id"]), "name": str(s["name"]), "team": str(s["team"]), "slot": int(s["slot"])}
		if _picks.has(int(s["peer_id"])):
			entry["char_id"] = str((_picks[int(s["peer_id"])] as Dictionary).get("char_id", ""))
			entry["spirit_id"] = str((_picks[int(s["peer_id"])] as Dictionary).get("spirit_id", ""))
		if str(s["team"]) == TEAM_A:
			roster_a.append(entry)
		else:
			roster_b.append(entry)
	return {"mode": mode, "roster_a": roster_a, "roster_b": roster_b, "field": "full_1300x780"}

func _broadcast_notice(type: String, who: String, text: String) -> void:
	var n := NetSchema.make_notice(type, who, text)
	transport.broadcast(NetSchema.MSG_NOTICE, n)
	notice.emit(n)

# ══════════════ S7 面板门（D1/D2/D4/D5/D6/D7/D10） ══════════════

## host 开面板门（prep=开赛自动；half 由中场事件接线；result 走 30s 自动无门）
func _open_gate(panel: String) -> void:
	var ready_map := {}
	for s in _slots:
		if not bool(s.get("forfeited", false)):
			ready_map[int(s["peer_id"])] = false
	_gate = {"panel": panel, "ready": ready_map, "confirm": mode == NetSchema.MP_1V1, "deadline": _now + t_panel, "grace_at": -1.0}
	_broadcast_gate()

func _broadcast_gate() -> void:
	var g := _gate.duplicate(true)
	gate_state_changed.emit(g)
	transport.broadcast(NetSchema.MSG_GATE, g)

func _gate_missing() -> Array:
	var missing: Array = []
	for pid in _gate["ready"].keys():
		if not bool(_gate["ready"][pid]):
			missing.append(int(pid))
	return missing

func _gate_tick() -> void:
	if _gate.is_empty():
		return
	var missing := _gate_missing()
	# 门通过：全员就绪 + 队长确认（1v1 confirm 随 ready 自动置位 D4）
	if missing.is_empty() and bool(_gate["confirm"]):
		_gate = {}
		_broadcast_gate()   # 广播空门=通过
		return
	if float(_gate["grace_at"]) < 0.0 and _now >= float(_gate["deadline"]):
		# D6 宽限启动：再等 15s
		_gate["grace_at"] = _now + t_grace
		_broadcast_notice("grace", "", "面板超时，宽限 %d 秒：仍未准备者将判负" % int(t_grace))
		_broadcast_gate()
		return
	if float(_gate["grace_at"]) >= 0.0 and _now >= float(_gate["grace_at"]):
		_judge_forfeit(missing)

## D7 判负：1v1=整场结算对方胜；3v3=个人出局转托管、比赛继续；判负后门重算自动继续
func _judge_forfeit(missing: Array) -> void:
	if mode == NetSchema.MP_1V1:
		var loser := int(missing[0]) if missing.size() > 0 else 0
		var winner_name := _slot_name(local_peer_id() if loser != local_peer_id() else _other_peer_1v1())
		_broadcast_notice("forfeit", _slot_name(loser), "%s 判负，比赛结束" % _slot_name(loser))
		end_match({"score": {"winner": winner_name}, "reason": "forfeit"})
		_gate = {}
		return
	# 3v3：个人出局
	for pid in missing:
		for s in _slots:
			if int(s["peer_id"]) == int(pid):
				s["forfeited"] = true
		_broadcast_notice("forfeit", _slot_name(int(pid)), "%s 判负出局，转为 AI 托管" % _slot_name(int(pid)))
	_transfer_captains()   # D10 队长判负自动顺延
	# 门重算：剩余未出局者全员就绪视为确认通过，自动继续（D7 尾款）——广播给全体 guest
	var ready_map := {}
	for s in _slots:
		if not bool(s.get("forfeited", false)):
			ready_map[int(s["peer_id"])] = true
	_gate = {}
	_refresh_room()
	var auto_pass := {"panel": "auto_pass", "ready": ready_map, "confirm": true, "deadline": 0, "grace_at": 0}
	gate_state_changed.emit(auto_pass)
	transport.broadcast(NetSchema.MSG_GATE, auto_pass)

func _other_peer_1v1() -> int:
	for s in _slots:
		if int(s["peer_id"]) != local_peer_id():
			return int(s["peer_id"])
	return 0

func _is_captain(peer_id: int) -> bool:
	for s in _slots:
		if int(s["peer_id"]) == peer_id:
			return bool(s.get("captain", false))
	return false

func _slot_forfeited(peer_id: int) -> bool:
	for s in _slots:
		if int(s["peer_id"]) == peer_id:
			return bool(s.get("forfeited", false))
	return false

## 战斗内接线用：中场门（game_manager HALF_TIME 事件→host 调）
func host_open_half_gate() -> void:
	if is_host:
		_open_gate(NetSchema.PANEL_HALF)

## 当前门状态（UI 查询）
func get_gate() -> Dictionary:
	return _gate.duplicate(true)
