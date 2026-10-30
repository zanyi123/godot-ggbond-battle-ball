## 工单01 S5-1 · 战斗↔会话桥（host 权威出向 / guest 侧应用）
## host：20Hz 采集比分/阶段/时间/球员与球位置 → session.push_snapshot（ch1 unreliable）；
##        比赛结束由 battle_manager._on_sim_match_ended 调 session.end_match（桥只管快照）。
## guest：本类提供 apply_guest(gm, snap) 把快照写进 game_manager（阶段/计时/比分）；
##        guest 的 game_manager._process 已被 S5-3 门禁禁本地推进。
## 单机零影响：attach 仅在 NetManager.active 且 host 侧被 battle_manager 调用。
class_name NetBattleBridge
extends RefCounted

const SNAP_INTERVAL_S := 0.05   # 20Hz（S0.1 快照下行 ≥20Hz）

var session: NetSession = null
var bm: Node = null             # battle_manager（鸭子类型，避免循环引用）
var _acc: float = 0.0
var _frame: int = 0

func attach(battle_manager: Node, net_session: NetSession) -> void:
	bm = battle_manager
	session = net_session
	_acc = 0.0

## host 每帧驱动（battle_manager._process 调用）
func tick(delta: float) -> void:
	if session == null or bm == null:
		return
	_acc += delta
	if _acc < SNAP_INTERVAL_S:
		return
	_acc = 0.0
	session.push_snapshot(gather())

## 采集权威快照（最小集：比分/阶段/时间/球员位/球位；控制状态与事件=下一批）
func gather() -> Dictionary:
	var gm := GameManager
	var players: Array = []
	for p in (bm.team_a_players + bm.team_b_players):
		if p != null and is_instance_valid(p):
			players.append({"id": p.get_instance_id(), "pos": [p.global_position.x, p.global_position.y]})
	var ball: Dictionary = {}
	var b: Node2D = bm.ball_node
	if b != null and is_instance_valid(b):
		ball = {"pos": [b.global_position.x, b.global_position.y]}
	_frame += 1
	var phase_names: Array = gm.MatchPhase.keys()
	return NetSchema.make_snapshot(_frame, str(phase_names[int(gm.match_phase)]), gm.match_time, {"A": gm.score_team_a, "B": gm.score_team_b}, players, ball, [])

## guest 侧：把快照写进本端 game_manager（阶段/计时/比分跟随 host；本地推进已被门禁禁用）
static func apply_guest(gm: Node, snap: Dictionary) -> void:
	var names: Array = gm.MatchPhase.keys()
	var idx: int = names.find(str(snap.get("phase", "")))
	if idx >= 0:
		gm.match_phase = idx
	gm.match_time = float(snap.get("match_time", 0.0))
	var score: Dictionary = snap.get("score", {})
	gm.score_team_a = int(score.get("A", 0))
	gm.score_team_b = int(score.get("B", 0))

## ── S5-2 host 远端指令驱动 ──
var _latest_cmd: Dictionary = {}   # peer_id -> {move, skill_slot}

func bind_commands() -> void:
	if session != null:
		session.input_command_received.connect(_on_cmd)

var cmd_rx_count: int = 0
var last_cmd_peer: int = 0
var last_cmd_move: String = ""
var last_cmd_raw: String = ""
var last_lookup_peer: int = 0

func _on_cmd(cmd: Dictionary) -> void:
	cmd_rx_count += 1
	last_cmd_peer = int(cmd.get("peer_id", 0))
	last_cmd_move = str(cmd.get("move", "MISSING"))
	last_cmd_raw = str(cmd)
	_latest_cmd[int(cmd.get("peer_id", 0))] = {"move": cmd.get("move", Vector2.ZERO), "skill_slot": int(cmd.get("skill_slot", -1)), "ts": Time.get_ticks_msec()}

## host 每帧：按 config roster 的 peer→球员映射应用远端移动指令（AI 接口同构=直接设 velocity）
var apply_writes: int = 0
var guest_player_x0: float = -1.0
var guest_player_dx: float = 0.0

func apply_remote(delta: float) -> void:
	if bm == null or session == null:
		return
	# 队列轮询消费（信号连接在 arena 树内静默失效已实证——快照同款，直读直喂）
	while not session.cmd_queue.is_empty():
		_on_cmd(session.cmd_queue.pop_front())
	var cfg: Dictionary = bm._match_config
	for roster_key in ["roster_a", "roster_b"]:
		var team_players: Array = bm.team_a_players if roster_key == "roster_a" else bm.team_b_players
		var roster: Array = cfg.get(roster_key, [])
		for i in team_players.size():
			if i >= roster.size():
				break
			var pid := int((roster[i] as Dictionary).get("peer_id", 0))
			last_lookup_peer = pid
			if pid == 1:
				continue   # host 本机球员走本地输入，不抢占
			var pl: Node2D = team_players[i]
			if pl == null or not is_instance_valid(pl):
				continue
			var cmd: Dictionary = _latest_cmd.get(pid, {})
			var mv: Vector2 = cmd.get("move", Vector2.ZERO)
			# 指令保活超时 0.5s=松键（guest 侧变化触发式不发包，靠超时归零停走）
			if cmd.has("ts") and Time.get_ticks_msec() - int(cmd.get("ts", 0)) > 500:
				mv = Vector2.ZERO
			pl.velocity = mv * float(pl.get("speed") if pl.get("speed") != null else 300.0)
			if mv != Vector2.ZERO:
				apply_writes += 1
				if guest_player_x0 < 0.0:
					guest_player_x0 = pl.global_position.x
				guest_player_dx = pl.global_position.x - guest_player_x0

## ── S5-2 guest 快照驱动渲染（副本模式：本地节点被快照按序钉位）──
var latest_snap: Dictionary = {}
var _snap_dirty := false

## 直接喂入（worker/宿主收到快照即转发，绕开跨对象信号连接玄学）
func on_snap(snap: Dictionary) -> void:
	latest_snap = snap
	last_snap_frame = int(snap.get("frame", -1))
	_snap_dirty = true
	_bind_rx += 1

func bind_snapshots() -> void:
	if session != null:
		session.snapshot_received.connect(func(snap: Dictionary):
			latest_snap = snap
			last_snap_frame = int(snap.get("frame", -1))
			_snap_dirty = true
			_bind_rx += 1)

## guest 每帧：把最新快照按序写进本端场景节点（位置+球），并喂 game_manager（阶段/比分）
var apply_calls: int = 0
var _bind_rx: int = 0
var last_snap_frame: int = -1
var last_b0_pos: String = ""

func apply_snapshot_to_scene(delta: float) -> void:
	apply_calls += 1
	# 惰性绑定：arena 就绪时 NetManager.session 可能瞬时不可见（双实例/时序疑点），每帧查到即绑
	if session == null and NetManager.session != null:
		session = NetManager.session
		bind_snapshots()
	if bm == null or latest_snap.is_empty():
		return
	last_snap_frame = int(latest_snap.get("frame", -1))
	var players: Array = latest_snap.get("players", [])
	var all: Array = bm.team_a_players + bm.team_b_players
	for i in mini(players.size(), all.size()):
		var rec: Dictionary = players[i]
		var pos: Array = rec.get("pos", [0, 0])
		var pl: Node2D = all[i]
		if pl != null and is_instance_valid(pl):
			pl.global_position = Vector2(float(pos[0]), float(pos[1]))
			pl.velocity = Vector2.ZERO
	var all2: Array = bm.team_a_players + bm.team_b_players
	if all2.size() > 1 and players.size() > 1:
		var b0: Node2D = all2[players.size() - 1]
		if b0 != null and is_instance_valid(b0):
			last_b0_pos = "%.1f,%.1f" % [b0.global_position.x, b0.global_position.y]
	var b: Dictionary = latest_snap.get("ball", {})
	var bpos: Array = b.get("pos", [])
	var ball: Node2D = bm.ball_node
	if bpos.size() == 2 and ball != null and is_instance_valid(ball):
		ball.global_position = Vector2(float(bpos[0]), float(bpos[1]))
		if ball.get("is_active") != null:
			ball.set("is_active", false)   # guest 端球不被本地物理带走（纯渲染）
	_snap_dirty = false
