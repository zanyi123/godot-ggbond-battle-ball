extends Node
## 比赛奖励系统
## 管理奖励开关、连胜、可调数值、货币发放

# ===== 奖励配置 =====
# 可通过开发者面板调整并保存到存档
var reward_config: Dictionary = {
	"reward_enabled": false,       # 奖励开关（开发测试默认关闭）
	"win_fairy_coin": 300,
	"win_spirit_ore": 10,
	"win_crystal": 3,
	"lose_fairy_coin": 150,
	"lose_spirit_ore": 5,
	"lose_crystal": 1,
	"draw_fairy_coin": 200,
	"draw_spirit_ore": 7,
	"draw_crystal": 2,
	"streak_fairy_coin_bonus": 10,  # 连胜每场额外童话币
	"streak_spirit_ore_bonus": 2,   # 连胜每场额外元灵矿石
	"streak_crystal_bonus": 1,      # 连胜每场额外水晶
}

# 连胜计数
var _win_streak: int = 0

# 配置文件路径
const REWARD_CONFIG_PATH: String = "user://reward_config.json"
# 比赛历史记录路径
const MATCH_HISTORY_PATH: String = "user://match_history.json"
# 最多保留多少条历史记录
const MAX_HISTORY: int = 50

signal rewards_granted(rewards: Dictionary)


func _ready() -> void:
	_load_config()


## 计算并发放奖励（比赛结束时调用）
## result: "win" / "lose" / "draw"
## is_forfeit: 是否中途退出（不发奖励、不更新连胜、不记录历史）
func grant_rewards(result: String, is_forfeit: bool = false) -> Dictionary:
	var empty_rewards: Dictionary = {"fairy_coin": 0, "spirit_ore": 0, "crystal": 0}
	
	if is_forfeit:
		print("[RewardSystem] 中途退出，不发放奖励，不更新连胜")
		return empty_rewards
	
	if not reward_config.get("reward_enabled", false):
		print("[RewardSystem] 奖励已关闭，不发放")
		return empty_rewards
	
	# 基础奖励
	var rewards: Dictionary = {"fairy_coin": 0, "spirit_ore": 0, "crystal": 0}
	
	match result:
		"win":
			rewards.fairy_coin = int(reward_config.win_fairy_coin)
			rewards.spirit_ore = int(reward_config.win_spirit_ore)
			rewards.crystal = int(reward_config.win_crystal)
			_win_streak += 1
			# 连胜加成
			if _win_streak > 1:
				rewards.fairy_coin += int(reward_config.streak_fairy_coin_bonus) * (_win_streak - 1)
				rewards.spirit_ore += int(reward_config.streak_spirit_ore_bonus) * (_win_streak - 1)
				rewards.crystal += int(reward_config.streak_crystal_bonus) * (_win_streak - 1)
		"lose":
			rewards.fairy_coin = int(reward_config.lose_fairy_coin)
			rewards.spirit_ore = int(reward_config.lose_spirit_ore)
			rewards.crystal = int(reward_config.lose_crystal)
			_win_streak = 0  # 失败重置连胜
		"draw":
			rewards.fairy_coin = int(reward_config.draw_fairy_coin)
			rewards.spirit_ore = int(reward_config.draw_spirit_ore)
			rewards.crystal = int(reward_config.draw_crystal)
			# 平局不重置连胜也不增加
		_:
			push_error("[RewardSystem] 未知比赛结果: %s" % result)
			return rewards
	
	# 发放货币
	PlayerSaveManager.add_currency("fairy_coin", rewards.fairy_coin)
	PlayerSaveManager.add_currency("spirit_ore", rewards.spirit_ore)
	PlayerSaveManager.add_currency("crystal", rewards.crystal)
	PlayerSaveManager.save_slot()
	
	print("[RewardSystem] 奖励发放: %s → 童话币+%d 元灵矿石+%d 水晶+%d (连胜%d)" % [
		result, rewards.fairy_coin, rewards.spirit_ore, rewards.crystal, _win_streak
	])
	
	rewards_granted.emit(rewards)
	return rewards


## 获取当前连胜数
func get_win_streak() -> int:
	return _win_streak


## 重置连胜（新存档时调用）
func reset_win_streak() -> void:
	_win_streak = 0


## 设置奖励开关
func set_reward_enabled(enabled: bool) -> void:
	reward_config.reward_enabled = enabled
	_save_config()
	print("[RewardSystem] 奖励开关: %s" % ("开启" if enabled else "关闭"))


## 更新奖励配置（开发者面板调用）
func update_config(new_config: Dictionary) -> void:
	for key in new_config:
		if reward_config.has(key):
			reward_config[key] = new_config[key]
	_save_config()
	print("[RewardSystem] 配置已更新")


## 保存配置到文件
func _save_config() -> void:
	var file := FileAccess.open(REWARD_CONFIG_PATH, FileAccess.WRITE)
	if file:
		var data: Dictionary = reward_config.duplicate()
		data["win_streak"] = _win_streak
		file.store_string(JSON.stringify(data, "\t"))
		file.close()


## 加载配置
func _load_config() -> void:
	if not FileAccess.file_exists(REWARD_CONFIG_PATH):
		return
	var file := FileAccess.open(REWARD_CONFIG_PATH, FileAccess.READ)
	if file:
		var json := JSON.new()
		var err := json.parse(file.get_as_text())
		file.close()
		if err == OK:
			var data: Dictionary = json.data
			for key in data:
				if reward_config.has(key):
					reward_config[key] = data[key]
			# 连胜从配置恢复
			if data.has("win_streak"):
				_win_streak = int(data.win_streak)
			print("[RewardSystem] 配置已加载, 奖励开关: %s" % ("开启" if reward_config.reward_enabled else "关闭"))


# ===== 比赛历史记录 =====

## 记录比赛历史（比赛正常结束时调用，中途退出不调用）
## result: "win"/"lose"/"draw"
## score_a, score_b: 比分
## duration: 比赛时长（秒）
## stats_data: player_stats.get_report() 返回的数据
## rewards: 发放的奖励字典
func record_match_history(result: String, score_a: int, score_b: int, duration: float, stats_data: Dictionary, rewards: Dictionary) -> void:
	var history: Array = _load_history()

	# 提取我方（team a）击杀/死亡总数
	var total_kills: int = 0
	var total_deaths: int = 0
	var players: Array = stats_data.get("players", [])
	for pstats: Dictionary in players:
		if pstats.get("team", "") == "a":
			total_kills += int(pstats.get("kills", 0))
			total_deaths += int(pstats.get("deaths", 0))

	var record: Dictionary = {
		"date": Time.get_datetime_string_from_system(false, true),
		"result": result,
		"score": "%d:%d" % [score_a, score_b],
		"duration": round(duration * 10.0) / 10.0,
		"kills": total_kills,
		"deaths": total_deaths,
		"rewards": {
			"fairy_coin": int(rewards.get("fairy_coin", 0)),
			"spirit_ore": int(rewards.get("spirit_ore", 0)),
			"crystal": int(rewards.get("crystal", 0)),
		},
	}

	history.push_front(record)  # 最新的放最前

	# 超过上限截断
	if history.size() > MAX_HISTORY:
		history = history.slice(0, MAX_HISTORY)

	_save_history(history)
	print("[RewardSystem] 比赛历史已记录: %s %s 击杀%d/死亡%d (共%d条)" % [result, record.score, total_kills, total_deaths, history.size()])


## 获取比赛历史记录（最新在前）
func get_match_history() -> Array:
	return _load_history()


## 清空所有比赛历史（开发者工具可调用）
func clear_match_history() -> void:
	_save_history([])
	print("[RewardSystem] 比赛历史已清空")


## 保存历史到文件
func _save_history(history: Array) -> void:
	var file := FileAccess.open(MATCH_HISTORY_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(history, "\t"))
		file.close()


## 加载历史记录
func _load_history() -> Array:
	if not FileAccess.file_exists(MATCH_HISTORY_PATH):
		return []
	var file := FileAccess.open(MATCH_HISTORY_PATH, FileAccess.READ)
	if file:
		var json := JSON.new()
		var err := json.parse(file.get_as_text())
		file.close()
		if err == OK and json.data is Array:
			return json.data
	return []
