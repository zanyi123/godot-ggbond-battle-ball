class_name MatchStats
extends Node
## 比赛指标采集器（方案A 步骤1，2026-06-17）
## 目的：让 AI 改动可量化验证，摆脱"手动跑游戏肉眼观察"
##
## 数据来源：
##   1. 球的信号（ball_caught / ball_hit_player / ball_out_of_bounds）
##   2. ai_manager 上报（卡死 record_stuck / 状态切换 record_state_change）
##   3. GameManager.match_ended（比分）
##
## 关键指标对应已知痛点：
##   - same_team_catch_rate：传球到位率（接球 bug 回归）
##   - outer_catches：外场接球次数（外场接不到队友传球）
##   - stuck_count：卡死次数（P0 卡线）
##   - state_changes：状态切换次数（抖动）
##   - score_a/b + duration：整体平衡

# === 球权流转 ===
var catches_same_team: int = 0       # 同队接球（传球到位 / 安全接球）
var catches_enemy_team: int = 0      # 敌队接球（截断 / 夺球）
var outer_catches: int = 0           # 外场球员（被罚下）接球次数

# === 命中/伤害 ===
var balls_hit_player: int = 0        # 球击中球员次数
var total_damage_dealt: float = 0.0  # 总伤害量

# === 失误 ===
var balls_out_of_bounds: int = 0     # 出界次数

# === ai_manager 上报 ===
var stuck_count: int = 0             # 卡死触发总次数
var stuck_by_team: Dictionary = {"a": 0, "b": 0}
var state_changes: int = 0           # 状态切换总次数（决策抖动指标）
var state_changes_by_team: Dictionary = {"a": 0, "b": 0}

# === 比赛结果 ===
var match_start_msec: float = 0.0
var match_end_msec: float = 0.0
var score_a: int = 0
var score_b: int = 0

var is_recording: bool = false
var ball_node: Area2D


## 开始采集（连接球信号）
func start_recording(ball: Area2D) -> void:
	ball_node = ball
	if ball_node:
		if not ball_node.ball_caught.is_connected(_on_ball_caught):
			ball_node.ball_caught.connect(_on_ball_caught)
		if not ball_node.ball_hit_player.is_connected(_on_ball_hit):
			ball_node.ball_hit_player.connect(_on_ball_hit)
		if not ball_node.ball_out_of_bounds.is_connected(_on_ball_out):
			ball_node.ball_out_of_bounds.connect(_on_ball_out)
	_reset_counters()
	is_recording = true
	match_start_msec = float(Time.get_ticks_msec())
	print("[Stats] 开始采集比赛指标")


## 停止采集
func stop_recording() -> void:
	is_recording = false
	match_end_msec = float(Time.get_ticks_msec())


func _reset_counters() -> void:
	catches_same_team = 0
	catches_enemy_team = 0
	outer_catches = 0
	balls_hit_player = 0
	total_damage_dealt = 0.0
	balls_out_of_bounds = 0
	stuck_count = 0
	stuck_by_team = {"a": 0, "b": 0}
	state_changes = 0
	state_changes_by_team = {"a": 0, "b": 0}


# ==============================
# ===== 球信号回调 =============
# ==============================

func _on_ball_caught(player: CharacterBody2D) -> void:
	if not is_recording or not ball_node or not player:
		return
	# 用 attacker_player 判断球来自哪队（接球时 attacker_player 仍有效）
	if ball_node.attacker_player:
		if ball_node.attacker_player.team == player.team:
			catches_same_team += 1   # 同队接球 = 传球到位
		else:
			catches_enemy_team += 1 # 敌队接球 = 被截断
	# 外场球员接球（is_penalized = 在外场隔离中）
	if player.get("is_penalized"):
		outer_catches += 1


func _on_ball_hit(player: CharacterBody2D, damage: float) -> void:
	if not is_recording:
		return
	balls_hit_player += 1
	total_damage_dealt += damage


func _on_ball_out() -> void:
	if not is_recording:
		return
	balls_out_of_bounds += 1


# ==============================
# ===== ai_manager 上报接口 ====
# ==============================

## 卡死触发（ai_manager 在 stuck_timer > 1.0 时调用）
func record_stuck(team: String) -> void:
	if not is_recording:
		return
	stuck_count += 1
	stuck_by_team[team] = stuck_by_team.get(team, 0) + 1


## 状态切换（ai_manager 在 _decide 后状态变化时调用）
func record_state_change(team: String) -> void:
	if not is_recording:
		return
	state_changes += 1
	state_changes_by_team[team] = state_changes_by_team.get(team, 0) + 1


## 记录最终比分（match_ended 时调用）
func set_final_score(a: int, b: int) -> void:
	score_a = a
	score_b = b


# ==============================
# ===== 报告输出 ===============
# ==============================

## 返回完整指标字典
func get_report() -> Dictionary:
	var duration_s: float = (match_end_msec - match_start_msec) / 1000.0
	var total_catches: int = catches_same_team + catches_enemy_team
	var same_team_rate: float = 0.0
	if total_catches > 0:
		same_team_rate = float(catches_same_team) / float(total_catches)
	return {
		"duration_s": duration_s,
		"score_a": score_a,
		"score_b": score_b,
		"catches_same_team": catches_same_team,
		"catches_enemy_team": catches_enemy_team,
		"same_team_catch_rate": same_team_rate,
		"outer_catches": outer_catches,
		"balls_hit_player": balls_hit_player,
		"total_damage": total_damage_dealt,
		"balls_out_of_bounds": balls_out_of_bounds,
		"stuck_count": stuck_count,
		"stuck_a": stuck_by_team.get("a", 0),
		"stuck_b": stuck_by_team.get("b", 0),
		"state_changes": state_changes,
		"state_changes_a": state_changes_by_team.get("a", 0),
		"state_changes_b": state_changes_by_team.get("b", 0),
	}


## 打印人类可读报告
func print_report() -> void:
	var r: Dictionary = get_report()
	print("================================================")
	print("【比赛指标报告】MatchStats Report")
	print("================================================")
	print("时长: %.1f秒 | 比分: 队A %d - %d 队B" % [r.duration_s, r.score_a, r.score_b])
	print("--- 球权流转 ---")
	print("  同队接球(传球到位): %d" % r.catches_same_team)
	print("  敌队接球(被截断):   %d" % r.catches_enemy_team)
	print("  同队接球率:         %.1f%%" % (r.same_team_catch_rate * 100.0))
	print("  外场接球次数:       %d" % r.outer_catches)
	print("--- 命中/伤害 ---")
	print("  球击中球员: %d 次, 总伤害 %.0f" % [r.balls_hit_player, r.total_damage])
	print("  出界次数:   %d" % r.balls_out_of_bounds)
	print("--- AI 健康（越低越好）---")
	print("  卡死触发: %d 次 (队A %d / 队B %d)" % [r.stuck_count, r.stuck_a, r.stuck_b])
	print("  状态切换: %d 次 (队A %d / 队B %d)" % [r.state_changes, r.state_changes_a, r.state_changes_b])
	print("================================================")
