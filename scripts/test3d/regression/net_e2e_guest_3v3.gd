## 工单01 S11 e2e · guest worker 场景（godot --headless 直接跑本场景）
## 流程：入房→就绪→开赛→收集快照（阶段/比分序列）→收结算→写 json→退出。
extends Node

const PORT := 19501
const OUT := "res://sim_results/net_e2e_3v3_guest2.json"

var _snap_phases: Array = []
var _last_score: Dictionary = {}
var _started := false
var _got := false
var _result := {}
var _cfg := {}
var _arena: Node = null

func _ready() -> void:
	_run()

func _run() -> void:
	# join 带确认重试（双进程冷启竞争：ENet 一次性 connect 不自动重试，打空则重 join）
	var s: NetSession = null
	var joined := false
	for attempt in 5:
		if NetManager.session != null:
			NetManager.leave()
		if not NetManager.join_room("127.0.0.1", "guest2AI", PORT):
			await get_tree().create_timer(0.5).timeout
			continue
		s = NetManager.session
		var t := 0.0
		while t < 3.0:
			await get_tree().create_timer(0.2).timeout
			t += 0.2
			if s != null and s._slots.size() > 0:
				joined = true
				break
		if joined:
			break
	if not joined:
		_finish({"ok": false, "err": "join_room failed (retry exhausted)"})
		return
	s.t_match_wait = 1.0
	s.t_result_wait = 30.0
	s.snapshot_received.connect(func(snap: Dictionary):
		_snap_phases.append(str(snap.get("phase", "")))
		_last_score = snap.get("score", {})
		# 快照自判终局（RESULTS 帧=host 权威终态；绕开 RESULT 包对 flush 时序的依赖）
		if str(snap.get("phase", "")) == NetSchema.PHASE_RESULTS and not _got:
			_got = true
			_result = {"score": snap.get("score", {}), "winner": str(snap.get("winner", ""))}
		if _arena != null and _arena._net_bridge != null:
			_arena._net_bridge.on_snap(snap))
	s.match_started.connect(func(cfg): _cfg = cfg; _started = true)
	s.set_local_ready(true)
	var waited := 0.0
	while not _started and waited < 35.0:
		await get_tree().create_timer(1.0).timeout
		waited += 1.0
		var st := -1
		if s.transport != null and s.transport.peer_ids().size() > 0:
			var pk = s.transport._peers[s.transport.peer_ids()[0]]
			st = pk.get_state()
	if not _started:
		_finish({"ok": false, "err": "match_started timeout", "phase": s.phase})
		return
	# 结算回调前置（host 战斗可能先于 guest 慢启动结束；信号不补发，晚连必丢）
	s.match_result.connect(func(r: Dictionary): _result = r; _got = true)
	# 场景资源等待期预热（battle_arena 依赖链大，load 花秒级——拖后则指令窗全落 host 赛后）
	var packed: PackedScene = load("res://scenes/battle/battle_arena.tscn")
	# S5-2：guest 副本战场（快照渲染+指令上行回环验证）
	await get_tree().create_timer(0.3).timeout
	var arena: Node = packed.instantiate()
	arena.configure_match(_cfg if not _cfg.is_empty() else s._match_config)
	_arena = arena
	add_child(arena)
	await get_tree().create_timer(0.8).timeout   # 等首批评快照钉位
	var all: Array = arena.team_a_players + arena.team_b_players
	var guest_pl: Node2D = null
	for e in (arena._match_config.get("roster_b", []) as Array):
		if int((e as Dictionary).get("peer_id", 0)) == NetManager.local_peer_id() and arena.team_b_players.size() > 0:
			guest_pl = arena.team_b_players[0]
	var x0: float = guest_pl.global_position.x if guest_pl != null else 0.0
	for i in 30:
		s.send_input_command(Vector2(1, 0), -1)   # 持续右移（host 远端驱动→快照回显）
		await get_tree().create_timer(0.05).timeout
	var moved_dx: float = (guest_pl.global_position.x - x0) if guest_pl != null else 0.0
	var diag := {
		"pl_found": guest_pl != null,
		"local_peer": NetManager.local_peer_id(),
		"roster_b": str((arena._match_config.get("roster_b", []) as Array)),
		"x0": x0,
	}
	waited = 0.0
	while not _got and waited < 40.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	_finish({
		"ok": _got,
		"err": "" if _got else "match_result timeout",
		"score": _result.get("score", {}),
		"snap_count": _snap_phases.size(),
		"had_in_match_snap": _snap_phases.has("FIRST_HALF") or _snap_phases.has("SECOND_HALF"),
		"last_snap_score": _last_score,
		"final_phase": s.phase,
		"replica_players": all.size(),
		"moved_dx": moved_dx,
		"apply_calls": arena._net_bridge.apply_calls if arena._net_bridge != null else -1,
		"snap_frame": arena._net_bridge.last_snap_frame if arena._net_bridge != null else -1,
		"b0_pos": arena._net_bridge.last_b0_pos,
		"diag": diag,
	})

func _finish(d: Dictionary) -> void:
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	get_tree().quit(0 if bool(d.get("ok", false)) else 1)
