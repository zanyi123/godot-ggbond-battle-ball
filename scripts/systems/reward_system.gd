extends Node
## 比赛奖励系统
## 管理奖励开关、连胜、可调数值、货币发放

# ===== 奖励配置 =====
# 可通过开发者面板调整并保存到存档
var reward_config: Dictionary = {
	"reward_enabled": false,       # 奖励开关（开发测试默认关闭）
	"win_fairy_coin": 300,
	"win_spirit_ore": 10,
	"win_crystal": 2,
	"lose_fairy_coin": 150,
	"lose_spirit_ore": 5,
	"lose_crystal": 1,
	"draw_fairy_coin": 200,
	"draw_spirit_ore": 7,
	"draw_crystal": 1,
	"streak_fairy_coin_bonus": 10,  # 连胜每场额外童话币
	"streak_spirit_ore_bonus": 2,   # 连胜每场额外元灵矿石
	"streak_crystal_bonus": 1,      # 连胜每场额外水晶
}

# 连胜计数
var _win_streak: int = 0

# 配置文件路径
const REWARD_CONFIG_PATH: String = "user://reward_config.json"

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
	PlayerSaveManager.save_game()
	
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
