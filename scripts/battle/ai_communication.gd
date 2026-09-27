extends Node
## 球员通信系统 - 同队球员间的信息传递
## 弥补视野盲区，增强团队协作真实感
## 
## 消息类型：
##   DEFEND_ALERT  = 注意防守（发现视野外敌人靠近队友）
##   PASS_TO_ME    = 传球给我（我在好位置）
##   DONT_PASS     = 别传球（我看到你附近有敌人）

const AIProfile = preload("res://scripts/battle/ai_profile.gd")

enum MsgType {
	DEFEND_ALERT,   # 注意防守
	PASS_TO_ME,     # 传球给我
	DONT_PASS,      # 别传球
	SKILL_READY,    # 技能就绪（我大招好了）
	BUFF_ON_YOU,    # 我给你加buff了
	NEED_BUFF,      # 我需要buff支援
	COMBO_SETUP,    # 连招邀约（我起了手，接我）——17号v2
	ENEMY_ULT_WARNING,  # 敌方大招预警——17号v2
}

# 消息文本（队友可见）
const MSG_TEXT = {
	MsgType.DEFEND_ALERT: "防守!",
	MsgType.PASS_TO_ME: "传我!",
	MsgType.DONT_PASS: "别传!",
	MsgType.SKILL_READY: "技能就绪!",
	MsgType.BUFF_ON_YOU: "加油!",
	MsgType.NEED_BUFF: "需要支援!",
	MsgType.COMBO_SETUP: "连招邀约!",
	MsgType.ENEMY_ULT_WARNING: "敌方大招!",
}

# v2 消息默认 TTL（秒，elapsed sim time 计——fixed-fps 下确定性）
const MSG_TTL_V2 = {
	MsgType.COMBO_SETUP: 6.0,
	MsgType.ENEMY_ULT_WARNING: 4.0,
	MsgType.SKILL_READY: 5.0,
	MsgType.BUFF_ON_YOU: 2.0,
	MsgType.NEED_BUFF: 3.0,
	MsgType.DEFEND_ALERT: 1.5,
	MsgType.PASS_TO_ME: 3.0,
	MsgType.DONT_PASS: 1.5,
}

# ===== 17号通讯协议v2：开关（单口拦截，默认关=全旁路，行为与旧版逐位一致）=====
# switches.json 加法键 "protocol_v2"：true 时新消息收发/消费生效；缺失/损坏一律视同关（fail-closed）
var protocol_v2_enabled: bool = false
var _protocol_switch_loaded: bool = false

# v2 负载化消息存储（确定性时钟=elapsed_time 累加 delta；fixed-fps sim 下逐位可复现）
# 每条：{type, sender_id, sender_name, team, urgency, expire_at, position: Vector2, related_skill_id}
var v2_messages: Array[Dictionary] = []

# 信号：某球员发送了消息（由 battle_manager 连接处理显示）
signal message_sent(sender: CharacterBody2D, msg_type: int, team: String)

# 冷却与频率限制
const PLAYER_COOLDOWN: float = 0.5        # 单个球员发送冷却（秒）
const TEAM_FREQ_INTERVAL: float = 2.0     # 团队消息最小间隔（秒，保证不超过0.5条/秒）
const MESSAGE_DISPLAY_TIME: float = 0.5   # 消息显示时间（秒）

# 每个球员的冷却计时
var player_cooldowns: Dictionary = {}  # {player_instance_id: remaining_time}

# 团队频率控制
var team_last_msg_time: Dictionary = {}  # {team: last_send_time}
var elapsed_time: float = 0.0

# AI管理器引用
var ai_manager: Node = null
var ball_node: Area2D = null


func _process(delta: float) -> void:
	elapsed_time += delta
	# 衰减球员冷却
	var to_remove: Array = []
	for id in player_cooldowns:
		player_cooldowns[id] -= delta
		if player_cooldowns[id] <= 0.0:
			to_remove.append(id)
	for id in to_remove:
		player_cooldowns.erase(id)


func set_ai_manager(mgr: Node) -> void:
	ai_manager = mgr


func set_ball(ball: Area2D) -> void:
	ball_node = ball


# ==============================
# ===== 发送消息 ================
# ==============================

func try_send_message(sender: CharacterBody2D, msg_type: int) -> bool:
	"""尝试发送消息，返回是否成功（受冷却和频率限制）"""
	if not sender or not is_instance_valid(sender):
		return false

	var id: int = sender.get_instance_id()
	var team: String = sender.team

	# 单个球员冷却检查
	if id in player_cooldowns:
		return false

	# 团队频率检查
	if team in team_last_msg_time:
		if elapsed_time - team_last_msg_time[team] < TEAM_FREQ_INTERVAL:
			return false

	# 通过检查，发送
	player_cooldowns[id] = PLAYER_COOLDOWN
	team_last_msg_time[team] = elapsed_time
	message_sent.emit(sender, msg_type, team)
	print("[Comm] %s: %s" % [_pname(sender), MSG_TEXT.get(msg_type, "?")])
	return true


func can_send(sender: CharacterBody2D) -> bool:
	"""检查该球员是否可以发消息（不实际发送）"""
	if not sender or not is_instance_valid(sender):
		return false
	var id: int = sender.get_instance_id()
	if id in player_cooldowns:
		return false
	var team: String = sender.team
	if team in team_last_msg_time:
		if elapsed_time - team_last_msg_time[team] < TEAM_FREQ_INTERVAL:
			return false
	return true


# ==============================
# ===== 17号 协议v2：负载化 =====
# ==============================

## 读协议开关（switches.json 加法键 protocol_v2；缺失/损坏=关，fail-closed）
func reload_protocol_switch(path: String = "res://data/systems/spirit_ai/switches.json") -> void:
	protocol_v2_enabled = false
	_protocol_switch_loaded = true
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return
	var v = parsed.get("protocol_v2", false)
	protocol_v2_enabled = v is bool and bool(v)


func _ensure_protocol_switch() -> void:
	if not _protocol_switch_loaded:
		reload_protocol_switch()


## v2 发送：同 legacy 冷却/频率闸，成功后写负载化存储并走同一信号（气泡/record 自动复用）
## payload 可覆盖：{urgency: float, ttl: float, position: Vector2, related_skill_id: String}
func post_message(sender: CharacterBody2D, msg_type: int, payload: Dictionary = {}) -> bool:
	_ensure_protocol_switch()
	if not protocol_v2_enabled:
		return try_send_message(sender, msg_type)
	if not try_send_message(sender, msg_type):
		return false
	var ttl: float = float(payload.get("ttl", MSG_TTL_V2.get(msg_type, 3.0)))
	v2_messages.append({
		"type": msg_type,
		"sender_id": sender.get_instance_id(),
		"sender_name": _pname(sender),
		"team": str(sender.team),
		"urgency": float(payload.get("urgency", 0.5)),
		"expire_at": elapsed_time + ttl,
		"position": payload.get("position", sender.global_position),
		"related_skill_id": str(payload.get("related_skill_id", "")),
	})
	return true


## v2 存储登记（不经冷却闸——供已通过 try_send_message 的调用方登记负载；受开关约束）
func record_v2_message(sender: CharacterBody2D, msg_type: int, payload: Dictionary = {}) -> void:
	_ensure_protocol_switch()
	if not protocol_v2_enabled or not sender or not is_instance_valid(sender):
		return
	var ttl: float = float(payload.get("ttl", MSG_TTL_V2.get(msg_type, 3.0)))
	v2_messages.append({
		"type": msg_type,
		"sender_id": sender.get_instance_id(),
		"sender_name": _pname(sender),
		"team": str(sender.team),
		"urgency": float(payload.get("urgency", 0.5)),
		"expire_at": elapsed_time + ttl,
		"position": payload.get("position", sender.global_position),
		"related_skill_id": str(payload.get("related_skill_id", "")),
	})


## 过期清理（惰性：查询时顺带清理，零额外时钟）
func _v2_purge_expired() -> void:
	v2_messages = v2_messages.filter(func(m): return elapsed_time < float(m["expire_at"]))


## 查活跃消息（team 必填；type=-1 = 全类型）
func get_active_messages(team: String, type: int = -1) -> Array[Dictionary]:
	_ensure_protocol_switch()
	var out: Array[Dictionary] = []
	if not protocol_v2_enabled:
		return out
	_v2_purge_expired()
	for m in v2_messages:
		if str(m["team"]) == team and (type < 0 or int(m["type"]) == type):
			out.append(m)
	return out


func is_type_active(team: String, msg_type: int) -> bool:
	return not get_active_messages(team, msg_type).is_empty()


func get_latest_message(team: String, msg_type: int) -> Dictionary:
	var active := get_active_messages(team, msg_type)
	if active.is_empty():
		return {}
	var best: Dictionary = active[0]
	for m in active:
		if float(m["expire_at"]) > float(best["expire_at"]):
			best = m
	return best


## 敌方大招预警查询：任一**敌队**发出且仍活跃的 ENEMY_ULT_WARNING
func is_enemy_ult_warning_hot(team: String) -> bool:
	_ensure_protocol_switch()
	if not protocol_v2_enabled:
		return false
	_v2_purge_expired()
	for m in v2_messages:
		if int(m["type"]) == MsgType.ENEMY_ULT_WARNING and str(m["team"]) != team:
			return true
	return false


## 测试/平台注入口：直接写一条活跃 v2 消息（绕过冷却；仍受开关约束）
func inject_message(team: String, msg_type: int, payload: Dictionary = {}) -> void:
	_ensure_protocol_switch()
	if not protocol_v2_enabled:
		return
	var ttl: float = float(payload.get("ttl", MSG_TTL_V2.get(msg_type, 3.0)))
	v2_messages.append({
		"type": msg_type,
		"sender_id": int(payload.get("sender_id", 0)),
		"sender_name": str(payload.get("sender_name", "test")),
		"team": team,
		"urgency": float(payload.get("urgency", 0.5)),
		"expire_at": elapsed_time + ttl,
		"position": payload.get("position", Vector2.ZERO),
		"related_skill_id": str(payload.get("related_skill_id", "")),
	})


# ==============================
# ===== AI 自动发送逻辑 ========
# ==============================

func evaluate_ai_messages(delta: float) -> void:
	"""每帧调用，评估所有AI球员是否需要发送消息"""
	if not ai_manager or not ball_node:
		return

	for ap in ai_manager.ai_players:
		if not ai_manager._is_valid(ap):
			continue
		if not can_send(ap.player):
			continue

		var profile: AIProfile = ap.profile
		_evaluate_single_ai(ap, profile)


func _evaluate_single_ai(ap: Dictionary, profile: AIProfile) -> void:
	"""评估单个AI球员是否应该发消息"""
	var p: CharacterBody2D = ap.player
	var team: String = ap.team
	var my_pos: Vector2 = p.global_position

	# === 情况1：我看到了持球者没看到的敌人 → 注意防守 ===
	if ball_node.owner_player and ball_node.owner_player.team == team:
		var carrier: CharacterBody2D = ball_node.owner_player
		# 我是AI，持球者可能是玩家或AI队友
		# 检查：我看到有敌人靠近持球者，但持球者可能看不到（不在其视野内）
		var known_enemies: Array[Dictionary] = ai_manager._get_known_enemies(ap)
		for e_info in known_enemies:
			var enemy: CharacterBody2D = e_info["ref"]
			var enemy_pos: Vector2 = e_info["pos"]
			var dist_to_carrier: float = enemy_pos.distance_to(carrier.global_position)

			if dist_to_carrier < 150.0:
				# 检查持球者是否看得到这个敌人
				if not ai_manager._is_in_field_of_view({"player": carrier, "profile": _get_carrier_profile(carrier)}, enemy_pos):
					# 持球者看不到，我发防守警报
					if randf() < 0.3:  # 30%概率触发，避免频繁
						try_send_message(p, MsgType.DEFEND_ALERT)
					return

	# === 情况2：我在好位置且持球者没看到我 → 传球给我 ===
	if ball_node.owner_player and ball_node.owner_player.team == team:
		var carrier: CharacterBody2D = ball_node.owner_player
		if carrier != p:  # 不是自己持球
			# 我在视野外（持球者看不到我）且在好位置
			var goal: Vector2 = ai_manager.SIDE_ANCHOR_A if team == "a" else ai_manager.SIDE_ANCHOR_B
			var my_goal_dist: float = my_pos.distance_to(goal)
			var carrier_goal_dist: float = carrier.global_position.distance_to(goal)

			# 我比持球者更靠近球门
			if my_goal_dist < carrier_goal_dist - 50.0:
				# 检查持球者是否看得到我
				if not ai_manager._is_in_field_of_view({"player": carrier, "profile": _get_carrier_profile(carrier)}, my_pos):
					# 我附近没有敌人
					if not ai_manager._has_visible_enemy_nearby(ap, 80.0):
						if randf() < 0.2:  # 20%概率触发
							try_send_message(p, MsgType.PASS_TO_ME)
						return

	# === 情况3：我看到持球者要传球的目标附近有敌人 → 别传球 ===
	if ball_node.owner_player and ball_node.owner_player.team == team:
		var carrier: CharacterBody2D = ball_node.owner_player
		# 检查每个队友是否被我看到的敌人包围
		var known_enemies: Array[Dictionary] = ai_manager._get_known_enemies(ap)
		var known_teammates: Array[Dictionary] = ai_manager._get_known_teammates(ap)

		for tm_info in known_teammates:
			var tm_pos: Vector2 = tm_info["pos"]
			var enemies_near_tm: int = 0
			for e_info in known_enemies:
				if tm_pos.distance_to(e_info["pos"]) < 60.0:
					enemies_near_tm += 1

			# 该队友附近有2+个敌人（被围），且持球者可能看不全
			if enemies_near_tm >= 2:
				# 检查持球者是否能完全看到这个区域
				if not ai_manager._is_in_field_of_view({"player": carrier, "profile": _get_carrier_profile(carrier)}, tm_pos):
					if randf() < 0.15:  # 15%概率触发
						try_send_message(p, MsgType.DONT_PASS)
					return


func _get_carrier_profile(carrier: CharacterBody2D) -> AIProfile:
	"""获取持球者的profile（如果有的话）"""
	if ai_manager:
		for ap in ai_manager.ai_players:
			if ap.player == carrier:
				return ap.profile
	# 如果持球者是玩家控制的，返回一个默认profile用于视野判断
	var default_profile := AIProfile.new()
	default_profile.field_of_view = 180.0
	default_profile.vision_range = 350.0
	return default_profile


# ==============================
# ===== 消息对AI决策的影响 ======
# ==============================

func get_team_messages(team: String, max_age: float = 2.0) -> Array[Dictionary]:
	"""获取指定队伍最近的消息列表（已发送的，用于影响AI决策）"""
	var result: Array[Dictionary] = []
	# 从 ai_manager 的 ai_players 中收集最近的通信记录
	# 这里用简单的内存记录
	return result


func get_pass_to_me_bonus(target: CharacterBody2D) -> float:
	"""如果最近有人喊'传球给我'且目标是该球员，返回额外传球加分"""
	if not ai_manager:
		return 0.0
	# 检查该球员的队伍中是否有 PASS_TO_ME 的活跃消息
	for ap in ai_manager.ai_players:
		if ap.player == target:
			continue
		if ap.team != target.team:
			continue
		if ap.has("last_msg_type") and ap.has("last_msg_time"):
			if ap.last_msg_type == MsgType.PASS_TO_ME:
				if elapsed_time - ap.last_msg_time < 2.0:  # 2秒内有效
					return 25.0  # 传球加分
	return 0.0


func is_dont_pass_active(target: CharacterBody2D) -> bool:
	"""检查是否有'别传球'消息针对该球员附近"""
	if not ai_manager:
		return false
	for ap in ai_manager.ai_players:
		if ap.team != target.team:
			continue
		if ap.has("last_msg_type") and ap.has("last_msg_time"):
			if ap.last_msg_type == MsgType.DONT_PASS:
				if elapsed_time - ap.last_msg_time < 1.5:  # 1.5秒内有效
					# 检查目标是否在消息发送者附近
					if ap.player.global_position.distance_to(target.global_position) < 150.0:
						return true
	return false


func has_pass_to_me(team: String) -> bool:
	"""检查队伍中是否有活跃的'传球给我'消息"""
	if not ai_manager:
		return false
	for ap in ai_manager.ai_players:
		if ap.team != team:
			continue
		if ap.has("last_msg_type") and ap.has("last_msg_time"):
			if ap.last_msg_type == MsgType.PASS_TO_ME:
				if elapsed_time - ap.last_msg_time < 3.0:  # 3秒内有效
					return true
	return false


func get_pass_to_me_sender(team: String) -> CharacterBody2D:
	"""获取最近发'传球给我'的球员"""
	if not ai_manager:
		return null
	var best_sender: CharacterBody2D = null
	var best_time: float = -1.0
	for ap in ai_manager.ai_players:
		if ap.team != team:
			continue
		if ap.has("last_msg_type") and ap.has("last_msg_time"):
			if ap.last_msg_type == MsgType.PASS_TO_ME:
				if elapsed_time - ap.last_msg_time < 3.0:
					if ap.last_msg_time > best_time:
						best_time = ap.last_msg_time
						best_sender = ap.player
	return best_sender


func has_defend_alert(team: String) -> bool:
	"""检查队伍中是否有活跃的防守警报"""
	if not ai_manager:
		return false
	for ap in ai_manager.ai_players:
		if ap.team != team:
			continue
		if ap.has("last_msg_type") and ap.has("last_msg_time"):
			if ap.last_msg_type == MsgType.DEFEND_ALERT:
				if elapsed_time - ap.last_msg_time < 1.5:
					return true
	return false

func has_skill_ready(team: String) -> bool:
	"""检查队伍中是否有活跃的技能就绪消息"""
	if not ai_manager:
		return false
	for ap in ai_manager.ai_players:
		if ap.team != team:
			continue
		if ap.has("last_msg_type") and ap.has("last_msg_time"):
			if ap.last_msg_type == MsgType.SKILL_READY:
				if elapsed_time - ap.last_msg_time < 5.0:
					return true
	return false

func get_skill_ready_sender(team: String) -> CharacterBody2D:
	"""获取最近发'技能就绪'的球员"""
	if not ai_manager:
		return null
	var best_sender: CharacterBody2D = null
	var best_time: float = -1.0
	for ap in ai_manager.ai_players:
		if ap.team != team:
			continue
		if ap.has("last_msg_type") and ap.has("last_msg_time"):
			if ap.last_msg_type == MsgType.SKILL_READY:
				if elapsed_time - ap.last_msg_time < 5.0:
					if ap.last_msg_time > best_time:
						best_time = ap.last_msg_time
						best_sender = ap.player
	return best_sender

func has_need_buff(team: String) -> bool:
	"""检查队伍中是否有活跃的需要buff消息"""
	if not ai_manager:
		return false
	for ap in ai_manager.ai_players:
		if ap.team != team:
			continue
		if ap.has("last_msg_type") and ap.has("last_msg_time"):
			if ap.last_msg_type == MsgType.NEED_BUFF:
				if elapsed_time - ap.last_msg_time < 3.0:
					return true
	return false

func get_need_buff_sender(team: String) -> CharacterBody2D:
	"""获取最近发'需要buff'的球员"""
	if not ai_manager:
		return null
	var best_sender: CharacterBody2D = null
	var best_time: float = -1.0
	for ap in ai_manager.ai_players:
		if ap.team != team:
			continue
		if ap.has("last_msg_type") and ap.has("last_msg_time"):
			if ap.last_msg_type == MsgType.NEED_BUFF:
				if elapsed_time - ap.last_msg_time < 3.0:
					if ap.last_msg_time > best_time:
						best_time = ap.last_msg_time
						best_sender = ap.player
	return best_sender

func has_buff_on_you(player: CharacterBody2D) -> bool:
	"""检查是否有'我给你加buff了'消息针对该球员"""
	if not ai_manager:
		return false
	for ap in ai_manager.ai_players:
		if ap.team != player.team:
			continue
		if ap.has("last_msg_type") and ap.has("last_msg_time"):
			if ap.last_msg_type == MsgType.BUFF_ON_YOU:
				if elapsed_time - ap.last_msg_time < 2.0:
					if ap.player.global_position.distance_to(player.global_position) < 100.0:
						return true
	return false


# ==============================
# ===== 记录消息（内部使用）=====
# ==============================

func record_message(player: CharacterBody2D, msg_type: int) -> void:
	"""在 ai_players 中记录消息（供后续查询）"""
	if not ai_manager:
		return
	for ap in ai_manager.ai_players:
		if ap.player == player:
			ap["last_msg_type"] = msg_type
			ap["last_msg_time"] = elapsed_time
			return


func _pname(p: CharacterBody2D) -> String:
	if p and p.char_data and p.char_data.has("name"):
		return str(p.char_data.name)
	return "Player"
