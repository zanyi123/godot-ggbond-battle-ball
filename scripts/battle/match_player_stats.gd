extends Node
## 比赛个人数据采集器
## 采集每位球员的击杀/死亡/伤害/接球/截球/技能释放等统计数据

## 单个球员的统计数据结构
class PlayerStats:
	var player_id: String = ""
	var player_name: String = ""
	var team: String = ""
	
	# 进攻数据
	var kills: int = 0
	var damage_dealt: float = 0.0
	var skill_hits: int = 0
	
	# 防守数据
	var deaths: int = 0
	var damage_taken: float = 0.0
	var balls_caught: int = 0
	var balls_intercepted: int = 0
	
	# 技能数据
	var skills_used: int = 0
	
	# 生存数据
	var survived: bool = true
	var stamina_remaining: float = 0.0
	
	func to_dict() -> Dictionary:
		return {
			"player_id": player_id,
			"player_name": player_name,
			"team": team,
			"kills": kills,
			"damage_dealt": damage_dealt,
			"skill_hits": skill_hits,
			"deaths": deaths,
			"damage_taken": damage_taken,
			"balls_caught": balls_caught,
			"balls_intercepted": balls_intercepted,
			"skills_used": skills_used,
			"survived": survived,
			"stamina_remaining": stamina_remaining,
		}


# 所有球员的统计数据 { player_instance_id: PlayerStats }
var _stats: Dictionary = {}
# 是否正在记录
var _recording: bool = false


func start_recording() -> void:
	_stats.clear()
	_recording = true
	print("[MatchPlayerStats] 开始记录")


func stop_recording() -> void:
	_recording = false
	print("[MatchPlayerStats] 停止记录, 共%d名球员" % _stats.size())


func is_recording() -> bool:
	return _recording


## 注册球员（比赛开始时调用）
func register_player(player: CharacterBody2D) -> void:
	if not _recording:
		return
	var stats := PlayerStats.new()
	stats.player_id = player.character_id
	stats.player_name = player.char_data.get("name", "?")
	stats.team = player.team
	_stats[player.get_instance_id()] = stats


## 获取球员统计
func get_stats(player: CharacterBody2D) -> PlayerStats:
	return _stats.get(player.get_instance_id(), null)


## 获取所有统计
func get_all_stats() -> Dictionary:
	return _stats


## 获取某队所有统计
func get_team_stats(team: String) -> Array:
	var result: Array = []
	for id in _stats:
		var stats: PlayerStats = _stats[id]
		if stats.team == team:
			result.append(stats)
	return result


## 获取比赛报告字典
func get_report() -> Dictionary:
	var players: Array = []
	for id in _stats:
		var stats: PlayerStats = _stats[id]
		players.append(stats.to_dict())
	return {"players": players}


## 打印报告
func print_report() -> void:
	print("\n========== 比赛个人数据 ==========")
	for id in _stats:
		var s: PlayerStats = _stats[id]
		var status: String = "存活" if s.survived else "被罚下"
		print("  %s(%s) 击杀:%d 死亡:%d 伤害:%.0f 接球:%d 截球:%d 技能:%d [%s]" % [
			s.player_name, s.team, s.kills, s.deaths, s.damage_dealt,
			s.balls_caught, s.balls_intercepted, s.skills_used, status
		])
	print("===================================\n")


# ===== 事件上报接口（由 player.gd / ball.gd 调用）=====

## 球员被击败（击杀者+被击败者）
func report_defeat(killer: CharacterBody2D, victim: CharacterBody2D) -> void:
	if not _recording:
		return
	var killer_stats: PlayerStats = get_stats(killer)
	var victim_stats: PlayerStats = get_stats(victim)
	if killer_stats:
		killer_stats.kills += 1
	if victim_stats:
		victim_stats.deaths += 1
		victim_stats.survived = false


## 球员造成伤害
func report_damage_dealt(attacker: CharacterBody2D, amount: float) -> void:
	if not _recording:
		return
	var stats: PlayerStats = get_stats(attacker)
	if stats:
		stats.damage_dealt += amount


## 球员承受伤害
func report_damage_taken(victim: CharacterBody2D, amount: float) -> void:
	if not _recording:
		return
	var stats: PlayerStats = get_stats(victim)
	if stats:
		stats.damage_taken += amount


## 球员接球（同队传球）
func report_ball_caught(player: CharacterBody2D) -> void:
	if not _recording:
		return
	var stats: PlayerStats = get_stats(player)
	if stats:
		stats.balls_caught += 1


## 球员截球（敌方球）
func report_ball_intercepted(player: CharacterBody2D) -> void:
	if not _recording:
		return
	var stats: PlayerStats = get_stats(player)
	if stats:
		stats.balls_intercepted += 1


## 球员释放技能
func report_skill_used(player: CharacterBody2D) -> void:
	if not _recording:
		return
	var stats: PlayerStats = get_stats(player)
	if stats:
		stats.skills_used += 1


## 技能命中
func report_skill_hit(player: CharacterBody2D) -> void:
	if not _recording:
		return
	var stats: PlayerStats = get_stats(player)
	if stats:
		stats.skill_hits += 1


## 记录最终体力（比赛结束时调用）
func record_final_stamina(player: CharacterBody2D) -> void:
	var stats: PlayerStats = get_stats(player)
	if stats:
		stats.stamina_remaining = player.stamina
