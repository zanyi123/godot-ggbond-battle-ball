extends Node
## 22-C S1 轨迹采集器（模仿学习·学主人打法）—— 平台窗口
## 采样（0.1s）：受控球员位置/朝向/速度/持球/体力 + 球位置；
## 事件：投球(throw_requested)/技能(skill_requested→施放成功由 skill_used 关联)/接球(ball_caught)/比分变化；
## 产物：user://play_traces/trace_<时间戳>.json（零仓库污染，trace_analyzer.py 消费）。
## 只读采集零行为影响；主人操控模式（--platform-human=N）下由平台自动挂载。

const SAMPLE_INTERVAL: float = 0.1
const TRACE_DIR := "user://play_traces"

var bm: Node2D = null
var recording: bool = false
var _samples: Array = []        # 0.1s 采样行
var _events: Array = []         # 事件行
var _elapsed: float = 0.0
var _accum: float = 0.0
var _last_scores: Vector2i = Vector2i.ZERO


func setup(battle_manager: Node2D) -> void:
	bm = battle_manager
	name = "PlayTraceRecorder"
	var input_mgr: Node = bm.input_mgr
	if input_mgr == null:
		print("[Trace] ⚠ input_mgr 不可用，采集停用")
		return
	if input_mgr.has_signal("throw_requested"):
		input_mgr.throw_requested.connect(_on_throw)
	if input_mgr.has_signal("skill_requested"):
		input_mgr.skill_requested.connect(_on_skill_key)
	if bm.ball_node != null and bm.ball_node.has_signal("ball_caught"):
		bm.ball_node.ball_caught.connect(_on_caught)
	recording = true
	DirAccess.make_dir_recursive_absolute(TRACE_DIR)
	print("[Trace] ✅ 轨迹采集开始（受控=%s 采样%.1fs）" % [
		str(input_mgr.controlled_player.char_data.get("name", "?")) if input_mgr.controlled_player != null else "无", SAMPLE_INTERVAL])


func _process(delta: float) -> void:
	if not recording or bm == null:
		return
	_elapsed += delta
	_accum += delta
	if _accum < SAMPLE_INTERVAL:
		return
	_accum = 0.0
	var input_mgr: Node = bm.input_mgr
	var cp = input_mgr.controlled_player if input_mgr else null
	var row := {"t": snappedf(_elapsed, 0.1)}
	if cp != null and is_instance_valid(cp):
		row["pos"] = [snappedf(cp.global_position.x, 0.1), snappedf(cp.global_position.y, 0.1)]
		row["facing"] = snappedf(cp.facing_direction.angle(), 0.01)
		row["speed"] = snappedf(cp.velocity.length(), 0.1)
		row["carry"] = bool(cp.is_carrying_ball)
		row["stamina"] = snappedf(float(cp.stamina), 0.1)
		row["energy"] = snappedf(float(cp.spirit_energy), 0.1)
	if bm.ball_node != null and is_instance_valid(bm.ball_node):
		row["ball"] = [snappedf(bm.ball_node.global_position.x, 0.1), snappedf(bm.ball_node.global_position.y, 0.1)]
	_samples.append(row)
	# 比分事件
	var sc := Vector2i(GameManager.score_team_a, GameManager.score_team_b)
	if sc != _last_scores:
		_events.append({"t": snappedf(_elapsed, 0.1), "ev": "goal", "score": [sc.x, sc.y]})
		_last_scores = sc


func _on_throw(direction: Vector2, power: float) -> void:
	_events.append({"t": snappedf(_elapsed, 0.1), "ev": "throw", "dir": snappedf(direction.angle(), 0.01), "power": snappedf(power, 0.01)})


func _on_skill_key(slot: int) -> void:
	_events.append({"t": snappedf(_elapsed, 0.1), "ev": "skill_key", "slot": slot})


func _on_caught(player: Node) -> void:
	var who := "?"
	if player != null and is_instance_valid(player):
		who = str(player.char_data.get("name", player.name))
	_events.append({"t": snappedf(_elapsed, 0.1), "ev": "catch", "who": who})


func finalize_and_save() -> String:
	if not recording:
		return ""
	recording = false
	var controlled := "?"
	var input_mgr: Node = bm.input_mgr if bm else null
	if input_mgr != null and input_mgr.controlled_player != null and is_instance_valid(input_mgr.controlled_player):
		controlled = str(input_mgr.controlled_player.char_data.get("name", "?"))
	var out := {
		"schema_version": 1,
		"controlled": controlled,
		"duration": snappedf(_elapsed, 0.1),
		"sample_interval": SAMPLE_INTERVAL,
		"score": [_last_scores.x, _last_scores.y],
		"samples": _samples,
		"events": _events,
	}
	var path := "%s/trace_%s.json" % [TRACE_DIR, Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "\t"))
		f.close()
	print("[Trace] 💾 轨迹已保存: %s（采样%d 行 / 事件%d 条）" % [path, _samples.size(), _events.size()])
	return path
