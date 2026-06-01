extends Node
## 游戏全局状态管理器
## 管理比赛状态、得分、时间等全局信息
## 挂载为Autoload单例

enum MatchPhase {
	PREP,           # 备战状态
	FIRST_HALF,     # 上半场 5min
	HALF_TIME,      # 中场休息 1min (备战)
	SECOND_HALF,    # 下半场 5min
	RESULTS         # 结算
}

enum PlayerRole {
	ATTACKER,    # 主攻手
	DEFENDER,    # 防御手
	SUPPORT      # 辅助手
}

# 比赛配置
const FIRST_HALF_DURATION: float = 300.0  # 5分钟
const HALF_TIME_DURATION: float = 60.0    # 1分钟
const SECOND_HALF_DURATION: float = 300.0 # 5分钟

# 当前比赛状态
var match_phase: MatchPhase = MatchPhase.PREP
var match_time: float = 0.0
var score_team_a: int = 0
var score_team_b: int = 0

# 暂停控制
var is_paused: bool = false

# 队伍数据
var team_a: Array[CharacterBody2D] = []
var team_b: Array[CharacterBody2D] = []

signal phase_changed(new_phase: MatchPhase)
signal match_time_updated(time: float)
signal score_updated(team: String, new_score: int)
signal match_ended(score_a: int, score_b: int)
signal match_paused()
signal match_resumed()


func _process(delta: float) -> void:
	if is_paused:
		return
	
	if match_phase in [MatchPhase.FIRST_HALF, MatchPhase.SECOND_HALF, MatchPhase.HALF_TIME]:
		match_time -= delta
		match_time_updated.emit(match_time)
		
		if match_time <= 0.0:
			_advance_phase()


func start_match() -> void:
	score_team_a = 0
	score_team_b = 0
	_set_phase(MatchPhase.FIRST_HALF)
	match_time = FIRST_HALF_DURATION


func _advance_phase() -> void:
	match match_phase:
		MatchPhase.FIRST_HALF:
			_set_phase(MatchPhase.HALF_TIME)
			match_time = HALF_TIME_DURATION
			print("[GameManager] 上半场结束，中场休息")
		MatchPhase.HALF_TIME:
			_set_phase(MatchPhase.SECOND_HALF)
			match_time = SECOND_HALF_DURATION
			print("[GameManager] 下半场开始")
		MatchPhase.SECOND_HALF:
			_set_phase(MatchPhase.RESULTS)
			print("[GameManager] 下半场结束，比赛结果: 队A %d - 队B %d" % [score_team_a, score_team_b])
			match_ended.emit(score_team_a, score_team_b)
			
			# 宣布胜者
			if score_team_a > score_team_b:
				print("[GameManager] 胜者：队A！")
			elif score_team_b > score_team_a:
				print("[GameManager] 胜者：队B！")
			else:
				print("[GameManager] 平局！")


func _set_phase(phase: MatchPhase) -> void:
	match_phase = phase
	phase_changed.emit(phase)
	print("[GameManager] 阶段切换: %s" % MatchPhase.keys()[phase])


func add_score(team: String, amount: int = 1) -> void:
	if team == "a":
		score_team_a += amount
		score_updated.emit("a", score_team_a)
	else:
		score_team_b += amount
		score_updated.emit("b", score_team_b)
	print("[GameManager] 得分: 队A %d - 队B %d" % [score_team_a, score_team_b])
	
	# 检查是否有一队全部被击败
	_check_defeat_condition()


func check_all_defeated(team: String) -> bool:
	var team_players: Array[CharacterBody2D] = (team_a if team == "b" else team_b)
	var all_defeated := true
	for player: CharacterBody2D in team_players:
		if player and is_instance_valid(player) and not player.is_defeated:
			all_defeated = false
			break
	return all_defeated


func _check_defeat_condition() -> void:
	"""检查是否有一队全部被击败，如果是则结束比赛"""
	var all_a_defeated: bool = check_all_defeated("a")
	var all_b_defeated: bool = check_all_defeated("b")
	
	if all_a_defeated or all_b_defeated:
		print("[GameManager] 队%s全部被击败，比赛结束！" % ("A" if all_a_defeated else "B"))
		# 提前结束比赛
		_set_phase(MatchPhase.RESULTS)
		match_ended.emit(score_team_a, score_team_b)


func pause_match() -> void:
	"""暂停比赛（时间停止）"""
	if not is_paused:
		is_paused = true
		match_paused.emit()
		print("[GameManager] 比赛暂停")


func resume_match() -> void:
	"""恢复比赛"""
	if is_paused:
		is_paused = false
		match_resumed.emit()
		print("[GameManager] 比赛恢复")
