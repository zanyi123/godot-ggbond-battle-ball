## 工单01 S11 e2e · host worker 场景（godot --headless 直接跑本场景；autoload 全真）
## 流程：建房→就绪→开赛→预设 auto_simulate 实例化真 battle_arena（全 AI=托管语义）→
##       战斗桥 20Hz 出向+结算转发→写 json→退出（exit code=ok）。
extends Node

const PORT := 19501
const OUT := "res://sim_results/net_e2e_3v3_host.json"

var _started := false
var _got := false
var _result := {}
var _cfg := {}
var _arena: Node = null

func _ready() -> void:
	_run()

func _run() -> void:
	if not NetManager.create_room(NetSchema.MP_3V3_COOP, "host3AI", PORT):
		_finish({"ok": false, "err": "create_room failed"})
		return
	var s: NetSession = NetManager.session
	s.t_match_wait = 1.0
	s.t_pick = 0.3
	s.t_load = 0.1
	s.t_result_wait = 30.0
	s.set_local_ready(true)
	s.match_started.connect(func(cfg): _cfg = cfg; _started = true)
	var waited := 0.0
	while not _started and waited < 35.0:
		await get_tree().create_timer(1.0).timeout
		waited += 1.0
	if not _started:
		_finish({"ok": false, "err": "match_started timeout", "phase": s.phase})
		return
	# 真 battle 场景（预设 auto_simulate=全 AI 自动开赛；半场压缩 1s，中场自动 ×0.2）
	GameManager.sim_half_duration_override = 15.0   # e2e 时序：给 guest 副本启动+指令回环留真时窗（≈4.4s）
	var scene: Node = (load("res://scenes/battle/battle_arena.tscn") as PackedScene).instantiate()
	scene.set("auto_simulate", true)
	scene.set("sim_time_scale", 6.0)
	scene.configure_match(_cfg)   # S5-2：阵容配置须在 add_child（_ready/_setup_teams）前就位
	_arena = scene
	add_child(scene)
	# battle 的 sim 结束流程会 quit 进程：落盘必须内联在 result 回调（emit 同步执行，先于 quit）
	s.match_result.connect(func(r: Dictionary):
		_result = r
		var rx: int = _arena._net_bridge.cmd_rx_count if _arena != null and _arena._net_bridge != null else -1
		var aw: int = _arena._net_bridge.apply_writes if _arena != null and _arena._net_bridge != null else -1
		var gdx: float = _arena._net_bridge.guest_player_dx if _arena != null and _arena._net_bridge != null else -1.0
		_finish({
			"ok": true,
			"err": "",
			"cmd_rx": rx,
			"apply_writes": aw,
			"last_cmd_peer": _arena._net_bridge.last_cmd_peer,
			"last_cmd_move": _arena._net_bridge.last_cmd_move,
			"last_cmd_raw": _arena._net_bridge.last_cmd_raw,
			"latest_size": _arena._net_bridge._latest_cmd.size(),
			"last_lookup_peer": _arena._net_bridge.last_lookup_peer,
			"host_guest_dx": gdx,
			"score": r.get("score", {}),
			"winner": str(r.get("winner", "")),
			"reached_results": s.phase == NetSchema.PHASE_RESULTS,
			"final_phase": s.phase,
		}))

func _finish(d: Dictionary) -> void:
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	# 延迟退出：flush 只把包塞进 OS 发送缓冲，quit 竞速会吞掉尚未冲刷的包（多 peer 必丢）
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0 if bool(d.get("ok", false)) else 1)
