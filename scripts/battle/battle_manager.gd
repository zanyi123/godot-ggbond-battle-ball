extends Node2D
## 比赛主场景 - 管理一场比赛的完整流程
## 场景树:FieldZone + Ball + 6 Players + UI

const AIProfile = preload("res://scripts/battle/ai_profile.gd")

# 场地配置
const FIELD_WIDTH: float = 1300.0
const FIELD_HEIGHT: float = 780.0

# 节点引用(动态创建)
var field_zone: Node2D  # FieldZone
var ball_node: Area2D
var ui_layer: CanvasLayer

# 隔离墙节点
var penalty_walls: Node2D  # 保存所有隔离墙

# 球员列表
var team_a_players: Array[CharacterBody2D] = []
var team_b_players: Array[CharacterBody2D] = []

# 子系统
var input_mgr: Node  # InputManager
var ai_mgr: Node     # AIManager
var comm_system: Node  # AICommunication
var preparation_ui: Control  # 备战界面

# 消息气泡显示
var message_bubbles: Array[Dictionary] = []  # [{label, timer, player}]

# 比赛是否已开始
var match_started: bool = false

# 违规处理队列
var pending_transfers: Array[Dictionary] = []  # [{player, offset_index, timer}]
const TRANSFER_DELAY: float = 1.0  # 传送延迟

# 违规状态追踪(防重复触发)
var violating_players: Dictionary = {}  # {player: violation_type}

# 瞄准绘制
var aim_line: Line2D
var aim_dots: Array[Node2D] = []  # 瞄准虚线的点
var mouse_cursor: ColorRect  # 鼠标光标点
var aim_arrow: Polygon2D  # 瞄准线末端箭头

# 鼠标圆环动画
var cursor_ring: Polygon2D

# 球员朝向箭头
var player_arrows: Dictionary = {}  # {player: arrow_node}


func _ready() -> void:
	_create_field()
	_create_ball()
	_setup_input_manager()
	_setup_teams()
	_setup_ui()
	_setup_ai_manager()
	_setup_comm_system()
	_setup_preparation_ui()

	GameManager.phase_changed.connect(_on_phase_changed)
	GameManager.match_paused.connect(_on_match_paused)
	GameManager.match_resumed.connect(_on_match_resumed)

	if field_zone:
		field_zone.player_transition_completed.connect(_on_player_transition_completed)

	# 不在这里 start_match,等备战完成后由 _on_prep_match_started 触发
	GameManager.match_phase = GameManager.MatchPhase.PREP

	# 启动违规处理定时器
	set_process(true)

	# 初始化瞄准线
	_create_aim_visuals()

	# 连接输入信号
	if input_mgr:
		input_mgr.aim_info_updated.connect(_on_aim_info_updated)
		input_mgr.cursor_info_updated.connect(_on_cursor_info_updated)
	# 箭头更新改为 _process 中统一处理,不再依赖信号


func _create_field() -> void:
	"""创建场地区域管理器(含视觉+碰撞+区域判定)"""
	var field_script := load("res://scripts/battle/field_zone.gd")
	field_zone = Node2D.new()
	field_zone.name = "FieldZone"
	field_zone.set_script(field_script)
	add_child(field_zone)

	# 边界碰撞墙(仅场地最外围,防止球员/球飞出场地)
	_create_wall(Vector2(-FIELD_WIDTH / 2.0, 0.0), Vector2(10.0, FIELD_HEIGHT))    # 左
	_create_wall(Vector2(FIELD_WIDTH / 2.0,  0.0), Vector2(10.0, FIELD_HEIGHT))    # 右
	_create_wall(Vector2(0.0, -FIELD_HEIGHT / 2.0), Vector2(FIELD_WIDTH, 10.0))   # 上
	_create_wall(Vector2(0.0, FIELD_HEIGHT / 2.0), Vector2(FIELD_WIDTH, 10.0))    # 下

	# 不在内/外场边界创建空气墙--AI靠逻辑不越线,球/球员可物理跨越
	# 隔离墙仅为被惩罚球员动态创建
	_create_penalty_walls()
	
	print("[Match] 场地创建完成")


func _create_wall(pos: Vector2, size: Vector2) -> void:
	"""创建边界碰撞墙"""
	var wall := StaticBody2D.new()
	wall.position = pos
	var wall_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	wall_shape.shape = rect
	wall.add_child(wall_shape)
	add_child(wall)


func _create_ball() -> void:
	"""创建全局唯一实球"""
	var ball_script := load("res://scripts/battle/ball.gd")
	var ball := Area2D.new()
	ball.name = "Ball"
	ball.set_script(ball_script)
	ball_node = ball
	add_child(ball_node)


func _setup_input_manager() -> void:
	"""创建输入管理器"""
	var input_script := load("res://scripts/battle/input_manager.gd")
	input_mgr = Node.new()
	input_mgr.name = "InputManager"
	input_mgr.set_script(input_script)
	add_child(input_mgr)

	input_mgr.player_switch_requested.connect(_on_player_switch)
	input_mgr.throw_requested.connect(_on_throw_requested)
	input_mgr.throw_cancelled.connect(_on_throw_cancelled)
	input_mgr.catch_state_entered.connect(_on_catch_entered)
	input_mgr.catch_state_exited.connect(_on_catch_exited)
	input_mgr.skill_requested.connect(_on_skill_requested)
	input_mgr.quick_command_requested.connect(_on_quick_command)


func _setup_teams() -> void:
	"""创建双方球队"""
	# 队A初始位置:内场左半(队A半场)
	var team_a_ids := ["char_001", "char_002", "char_003"]
	var team_a_positions := [
		Vector2(-260, -130),
		Vector2(-320, 0),
		Vector2(-260, 130)
	]

	for i in range(3):
		var player := _create_player(team_a_ids[i], "a", i == 0, team_a_positions[i])
		team_a_players.append(player)

	# 队B初始位置:内场右半(队B半场)
	var team_b_ids := ["char_004", "char_005", "char_006"]
	var team_b_positions := [
		Vector2(260, -130),
		Vector2(320, 0),
		Vector2(260, 130)
	]

	for i in range(3):
		var player := _create_player(team_b_ids[i], "b", false, team_b_positions[i])
		team_b_players.append(player)

	# 队B策略在 _setup_ai_manager 中随 profile 生成

	input_mgr.all_team_players = team_a_players
	input_mgr.set_controlled_player(team_a_players[0])

	GameManager.team_a = team_a_players
	GameManager.team_b = team_b_players

	# 球权分配推迟到备战完成后(_on_prep_match_started)


func _create_player(char_id: String, team_name: String, controlled: bool, start_pos: Vector2) -> CharacterBody2D:
	var player_script := load("res://scripts/battle/player.gd")
	var player := CharacterBody2D.new()
	player.name = "Player_%s_%d" % [team_name, team_a_players.size() + team_b_players.size()]
	player.set_script(player_script)
	player.position = start_pos
	player.collision_layer = 1
	player.collision_mask = 1  # layer 1 only(球员互碰),layer 5隔离墙由set_penalized动态控制
	add_child(player)
	player.initialize(char_id, team_name, controlled)
	# 连接被击败信号
	player.defeated.connect(_on_player_defeated)
	return player


func _assign_initial_ball() -> void:
	var coin := randi() % 2
	if coin == 0:
		ball_node.return_to_player(team_a_players[0])
	else:
		ball_node.return_to_player(team_b_players[0])
	print("[Match] 初始球权分配给队%s" % ("A" if coin == 0 else "B"))


func _setup_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UILayer"
	ui_layer.layer = 10
	add_child(ui_layer)

	var hud_script := load("res://scripts/battle/battle_hud.gd")
	var hud := Control.new()
	hud.name = "HUD"
	hud.set_script(hud_script)
	ui_layer.add_child(hud)

	# 绑定球员引用到HUD
	var team_a_arr: Array[CharacterBody2D] = []
	team_a_arr.assign(team_a_players)
	var team_b_arr: Array[CharacterBody2D] = []
	team_b_arr.assign(team_b_players)
	hud.setup_players(team_a_arr, team_b_arr)

	# 通信系统在 _setup_ai_manager 之后创建,这里先保存HUD引用
	# HUD的comm_system连接在 _setup_comm_system 中完成


# ===== 信号处理 =====

func _on_player_switch(index: int) -> void:
	var players: Array[CharacterBody2D] = input_mgr.all_team_players
	if index < players.size():
		var target: CharacterBody2D = players[index]
		input_mgr.set_controlled_player(target)
		print("[Match] 切换控制球员 -> %s" % (target.char_data.get("name") if target.char_data.has("name") else ""))


func _on_throw_requested(direction: Vector2, power: float) -> void:
	var player: CharacterBody2D = input_mgr.controlled_player
	if player == null or not player.is_carrying_ball:
		return

	var damage: float = player.attack_power
	var max_dist: float = 300.0 + power * 500.0

	var skills: Array[Dictionary] = []
	for skill_id in player.equipped_skills:
		var skill_data: Dictionary = DataManager.get_skill_by_id(str(skill_id))
		if not skill_data.is_empty():
			skills.append(skill_data)

	player.set_carrying_ball(false)
	ball_node.launch(player.global_position, direction, damage, max_dist, player, skills)


func _on_throw_cancelled() -> void:
	print("[Match] 发球取消")
	# 清除瞄准线
	if aim_line:
		aim_line.visible = false
	_cleanup_old_aim_lines()


func _on_catch_entered() -> void:
	pass


func _on_catch_exited() -> void:
	pass


func _on_skill_requested(slot: int) -> void:
	var player: CharacterBody2D = input_mgr.controlled_player
	if player:
		player.use_skill(slot)


func _on_quick_command(command: int) -> void:
	"""玩家快捷指令 → 通过通信系统发送"""
	if comm_system and input_mgr and input_mgr.controlled_player:
		comm_system.try_send_message(input_mgr.controlled_player, command)


func _on_comm_message_sent(sender: CharacterBody2D, msg_type: int, team: String) -> void:
	"""通信消息发送后:显示气泡 + 记录消息"""
	comm_system.record_message(sender, msg_type)

	var player_team: String = "a"
	if input_mgr and input_mgr.controlled_player:
		player_team = input_mgr.controlled_player.team

	if team == player_team:
		var text: String = ""
		match msg_type:
			0: text = "防守!"
			1: text = "传我!"
			2: text = "别传!"
			_: text = "..."
		_show_message_bubble(sender, text, 0.5)
	else:
		_show_opponent_dots(sender, 0.5)


func _show_message_bubble(player: CharacterBody2D, text: String, duration: float) -> void:
	"""在球员头顶显示消息气泡"""
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.8))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.z_index = 100
	add_child(label)
	message_bubbles.append({"label": label, "timer": duration, "player": player})


func _show_opponent_dots(player: CharacterBody2D, duration: float) -> void:
	"""在对手球员右下角显示省略号"""
	var label := Label.new()
	label.text = "。。。"
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.6))
	label.z_index = 100
	add_child(label)
	message_bubbles.append({"label": label, "timer": duration, "player": player, "is_opponent": true})


func _update_message_bubbles(delta: float) -> void:
	"""每帧更新消息气泡位置和计时"""
	var expired: Array[Dictionary] = []

	for bubble in message_bubbles:
		bubble["timer"] -= delta
		if bubble["timer"] <= 0.0:
			expired.append(bubble)
			continue

		var player: CharacterBody2D = bubble["player"]
		var label: Label = bubble["label"]
		if not is_instance_valid(player) or not is_instance_valid(label):
			expired.append(bubble)
			continue

		var pos: Vector2 = player.global_position
		# 区分对手省略号(右下角)和队友消息(头顶)
		if bubble.get("is_opponent", false):
			label.global_position = Vector2(pos.x + 20.0, pos.y + 20.0)
		else:
			label.global_position = Vector2(pos.x - label.size.x / 2.0, pos.y - 65.0)

	for bubble in expired:
		if is_instance_valid(bubble["label"]):
			bubble["label"].queue_free()
		message_bubbles.erase(bubble)


func _on_player_defeated(player: CharacterBody2D) -> void:
	"""处理球员被击败事件:移动到外场并设置惩罚状态"""
	var pname: String = player.char_data.get("name", "?") if player.char_data else "?"
	print("[Match] %s (队%s) 被击败,移动到外场" % [pname, player.team])

	# 暂停比赛
	GameManager.pause_match()

	# 计算偏移量(避免多个球员同时被击败时重叠)
	var defeated_count: int = 0
	for p in team_a_players + team_b_players:
		if p.is_defeated and p != player:
			defeated_count += 1

	# 移动到外场
	field_zone.start_field_transition(player, defeated_count)

	# 等待【自己的】传送完成（忽略其他球员的传送信号）
	var completed_player: CharacterBody2D = await field_zone.player_transition_completed
	while completed_player != player:
		completed_player = await field_zone.player_transition_completed

	# 设置惩罚状态(限制在外场内) + 碰撞层
	# 注：_on_player_transition_completed 也会设置惩罚和建墙
	# 这里双重保障，确保不遗漏
	if not player.is_penalized:
		player.set_penalized(true)
		_build_penalty_enclosure(player.team)
		_ensure_all_penalty_enclosures()

	# 恢复比赛
	GameManager.resume_match()

	print("[Match] %s (队%s) 已移动到外场并设置惩罚状态" % [pname, player.team])


# ===== 违规检测与处理 =====

func _check_violations() -> void:
	"""每帧检查所有球员是否违规"""
	var players_to_clear: Array[CharacterBody2D] = []

	for player: CharacterBody2D in team_a_players + team_b_players:
		# 跳过无效/已击败/传送中/被惩罚球员
		if not player or not is_instance_valid(player):
			players_to_clear.append(player)
			continue
		if player.is_defeated or field_zone.is_player_transitioning(player):
			players_to_clear.append(player)
			continue
		var penalized_val = player.get("is_penalized")
		if penalized_val != null and penalized_val:
			players_to_clear.append(player)
			continue

		var violation: int = field_zone.check_zone_violation(player)

		# 检查是否新违规
		if violation != field_zone.ViolationType.NONE:
			if player not in violating_players:
				# 新违规,触发处理
				_handle_violation(player, violation)
				violating_players[player] = violation
		else:
			# 未违规,清除记录
			if player in violating_players:
				violating_players.erase(player)

	# 清理无效记录
	for player in players_to_clear:
		violating_players.erase(player)


func _handle_violation(player: CharacterBody2D, violation_type: int) -> void:
	"""处理违规事件"""
	# 暂停比赛
	GameManager.pause_match()

	# 计算对手得分
	var scoring_team := "b" if player.team == "a" else "a"
	GameManager.add_score(scoring_team)

	# 播报违规
	var violation_text: String
	match violation_type:
		field_zone.ViolationType.BLUE_BOUNDARY:
			violation_text = "越出禁区"
		field_zone.ViolationType.CROSS_MIDLINE:
			violation_text = "越中线"
		field_zone.ViolationType.CROSS_FIELD_BOUNDARY:
			violation_text = "越内外场边界"
		_:
			violation_text = "未知违规"
	print("[Match] 违规: %s %s! 队%s 得分" % [(player.char_data.get("name") if player.char_data.has("name") else ""), violation_text, scoring_team.to_upper()])

	# 安排传送(1秒延迟后)
	_schedule_transfer(player, violation_type)


func _schedule_transfer(player: CharacterBody2D, violation_type: int) -> void:
	"""安排传送到自己的外场(防重叠)"""
	# 计算偏移索引(同一外场已安排的传送数)
	var offset_index := 0
	for item in pending_transfers:
		var p = item["player"]
		if p and p.team == player.team:
			offset_index += 1

	pending_transfers.append({
		"player": player,
		"offset_index": offset_index,
		"timer": TRANSFER_DELAY
	})
	print("[Match] 安排传送: %s -> 偏移%d, %s后执行" % [(player.char_data.get("name") if player.char_data.has("name") else ""), offset_index, TRANSFER_DELAY])


func _process(delta: float) -> void:
	"""每帧处理:违规检测 + 传送队列 + 朝向箭头 + 通信 + 气泡"""
	_check_violations()
	_update_all_player_arrows()
	_update_message_bubbles(delta)

	# AI通信评估(仅比赛中)
	if match_started and comm_system:
		comm_system.evaluate_ai_messages(delta)

	# 处理传送队列（违规传送）
	if pending_transfers.is_empty():
		return

	var all_done := true
	for item in pending_transfers:
		var p = item["player"]
		var offset = item["offset_index"] if item.has("offset_index") else 0
		if p and is_instance_valid(p):
			item["timer"] -= delta
			if item["timer"] <= 0:
				# 执行传送（传送完成后 _on_player_transition_completed 会设置惩罚+建墙）
				field_zone.start_field_transition(p, offset)
				item["player"] = null  # 标记已完成
			else:
				all_done = false

	# 所有传送完成后恢复比赛
	if all_done:
		pending_transfers.clear()
		GameManager.resume_match()
		GameManager.resume_match()
		print("[Match] 传送完成,比赛恢复")


func _on_match_paused() -> void:
	"""比赛暂停时停止输入"""
	if input_mgr:
		input_mgr.set_physics_process(false)


func _on_match_resumed() -> void:
	"""比赛恢复时恢复输入"""
	if input_mgr:
		input_mgr.set_physics_process(true)
	# 重新启用所有玩家物理处理
	for player: CharacterBody2D in team_a_players + team_b_players:
		if player and is_instance_valid(player):
			player.set_physics_process(true)


func _on_phase_changed(new_phase: int) -> void:
	match new_phase:
		GameManager.MatchPhase.FIRST_HALF:
			print("[Match] 上半场开始!")
		GameManager.MatchPhase.HALF_TIME:
			print("[Match] 中场休息")
		GameManager.MatchPhase.SECOND_HALF:
			print("[Match] 下半场开始!")
		GameManager.MatchPhase.RESULTS:
			print("[Match] 比赛结束! 最终比分: %d - %d" % [GameManager.score_team_a, GameManager.score_team_b])


# ===== 隔离墙管理 =====

func _create_penalty_walls() -> void:
	"""创建外场隔离墙容器(初始为空,按需为被惩罚球员动态添加)"""
	penalty_walls = Node2D.new()
	penalty_walls.name = "PenaltyWalls"
	add_child(penalty_walls)
	print("[Match] 隔离墙容器创建完成(按需动态添加)")


func _create_penalty_wall(pos: Vector2, size: Vector2, wall_name: String = "PenaltyWall") -> void:
	"""创建单个隔离墙"""
	var wall := StaticBody2D.new()
	wall.position = pos
	wall.name = wall_name

	# 设置碰撞层:layer 5 (penalty_walls)
	wall.collision_layer = 1 << 4  # bit 4 = layer 5
	wall.collision_mask = 0  # 墙不检测任何碰撞,只阻挡球员

	var wall_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	wall_shape.shape = rect
	wall.add_child(wall_shape)

	penalty_walls.add_child(wall)


func _build_penalty_enclosure(team: String) -> void:
	"""为指定队伍的外场动态创建完整隔离墙(匹配凹字形)"""
	var wall_prefix: String = "enclosure_%s_" % team
	#  先清理该队伍旧的隔离 墙
	_remove_penalty_enclosure(team)

	var wall_count: int = 0
	if team == "a":
		# 右外场 凹字形隔离
		# 外围4面(矩形外框)
		_create_penalty_wall(Vector2(249.0, 0.0), Vector2(2.0, 650.0), wall_prefix + "left")    # 左边 x=249
		_create_penalty_wall(Vector2(511.0, 0.0), Vector2(2.0, 650.0), wall_prefix + "right")   # 右边 x=511
		_create_penalty_wall(Vector2(380.0, -326.0), Vector2(260.0, 2.0), wall_prefix + "top")    # 上边
		_create_penalty_wall(Vector2(380.0, 325.0), Vector2(260.0, 2.0), wall_prefix + "bot")     # 下边
		# 缺口密封墙(封堵上下臂之间的内场缺口 x=[250,380] y=[-260,260])
		_create_penalty_wall(Vector2(381.0, 0.0), Vector2(2.0, 520.0), wall_prefix + "gap_inner")  # 主体内侧 x=381, y=[-260,260]
		_create_penalty_wall(Vector2(315.0, -261.0), Vector2(130.0, 2.0), wall_prefix + "gap_top")  # 缺口上边 y=-261, x=[250,380]
		_create_penalty_wall(Vector2(315.0, 261.0), Vector2(130.0, 2.0), wall_prefix + "gap_bot")   # 缺口下边 y=261, x=[250,380]
		wall_count = 7
	else:
		# 左外场 凹字形隔离
		# 外围4面(矩形外框)
		_create_penalty_wall(Vector2(-511.0, 0.0), Vector2(2.0, 650.0), wall_prefix + "left")   # 左边 x=-511
		_create_penalty_wall(Vector2(-249.0, 0.0), Vector2(2.0, 650.0), wall_prefix + "right")  # 右边 x=-249
		_create_penalty_wall(Vector2(-380.0, -326.0), Vector2(260.0, 2.0), wall_prefix + "top")   # 上边
		_create_penalty_wall(Vector2(-380.0, 325.0), Vector2(260.0, 2.0), wall_prefix + "bot")    # 下边
		# 缺口密封墙(封堵上下臂之间的内场缺口 x=[-380,-250] y=[-260,260])
		_create_penalty_wall(Vector2(-381.0, 0.0), Vector2(2.0, 520.0), wall_prefix + "gap_inner")  # 主体内侧 x=-381, y=[-260,260]
		_create_penalty_wall(Vector2(-315.0, -261.0), Vector2(130.0, 2.0), wall_prefix + "gap_top")  # 缺口上边 y=-261, x=[-380,-250]
		_create_penalty_wall(Vector2(-315.0, 261.0), Vector2(130.0, 2.0), wall_prefix + "gap_bot")   # 缺口下边 y=261, x=[-380,-250]
		wall_count = 7

	print("[Match] 队%s 外场隔离墙已建(%d面)" % [team, wall_count])


func _remove_penalty_enclosure(team: String) -> void:
	"""移除指定队伍的隔离墙"""
	if not penalty_walls or not is_instance_valid(penalty_walls):
		return
	var wall_prefix: String = "enclosure_%s_" % team
	var to_remove: Array[Node] = []
	for child in penalty_walls.get_children():
		if child.name.begins_with(wall_prefix):
			to_remove.append(child)
	for child in to_remove:
		child.queue_free()
	if to_remove.size() > 0:
		print("[Match] 队%s 旧隔离墙已清除(%d面)" % [team, to_remove.size()])


func _ensure_all_penalty_enclosures() -> void:
	"""确保所有有被淘汰球员的队伍都有隔离墙（兜底，防止遗漏）"""
	for team_name: String in ["a", "b"]:
		var has_defeated: bool = false
		var players: Array = team_a_players if team_name == "a" else team_b_players
		for p: CharacterBody2D in players:
			if p and is_instance_valid(p) and p.is_defeated:
				has_defeated = true
				break
		if has_defeated:
			# 检查是否已有隔离墙
			var wall_prefix: String = "enclosure_%s_" % team_name
			var has_walls: bool = false
			if penalty_walls and is_instance_valid(penalty_walls):
				for child in penalty_walls.get_children():
					if child.name.begins_with(wall_prefix):
						has_walls = true
						break
			if not has_walls:
				print("[Match] ⚠️ 队%s 有被淘汰球员但缺少隔离墙，补建!" % team_name)
				_build_penalty_enclosure(team_name)
				# 补设置惩罚状态
				for p: CharacterBody2D in players:
					if p and is_instance_valid(p) and p.is_defeated:
						if not p.is_penalized:
							p.set_penalized(true)
							print("[Match] ⚠️ 补设置 %s 惩罚状态" % (p.char_data.get("name", "?") if p.char_data else "?"))


func _on_player_transition_completed(player: CharacterBody2D) -> void:
	"""球员传送完成：设置惩罚状态+建墙（违规传送和击败传送都走这里）"""
	if player and player.has_method("set_penalized"):
		if not player.is_penalized:
			player.set_penalized(true)
			_build_penalty_enclosure(player.team)
			_ensure_all_penalty_enclosures()
	var pname: String = player.char_data.get("name", "?") if player and player.char_data else "?"
	print("[Match] %s 传送完成" % pname)


# ===== 瞄准可视化 =====

func _create_aim_visuals() -> void:
	"""创建瞄准线可视化"""
	# 瞄准虚线
	aim_line = Line2D.new()
	aim_line.width = 3.0
	aim_line.default_color = Color(1, 1, 0, 0.7)  # 黄色半透明
	add_child(aim_line)
	aim_line.visible = false

	# 鼠标光标点(十字准星)
	mouse_cursor = ColorRect.new()
	mouse_cursor.size = Vector2(10, 10)
	mouse_cursor.position = Vector2(-5, -5)
	mouse_cursor.color = Color(1, 1, 0, 0.9)
	add_child(mouse_cursor)
	mouse_cursor.visible = false


func _on_aim_info_updated(aim_info: Dictionary) -> void:
	"""瞄准信息更新"""
	if not aim_info["aiming"]:
		aim_line.visible = false
		mouse_cursor.visible = false
		_cleanup_old_aim_lines()
		return

	var start: Vector2 = aim_info["start"]
	var end: Vector2 = aim_info["end"]
	var power: float = aim_info["power"]
	var direction: Vector2 = aim_info["direction"]
	var distance: float = aim_info["distance"]

	# 清理旧的虚线段
	_cleanup_old_aim_lines()

	# 绘制新的虚线效果(通过多个短线实现)
	_draw_dashed_line(start, end, direction, distance)

	# 更新瞄准线
	aim_line.clear_points()
	aim_line.add_point(start)
	aim_line.add_point(end)
	aim_line.width = 2.0 + power * 2.0  # 力度越大线越粗
	aim_line.default_color = Color(1, 1, 0, 0.5 + power * 0.5)  # 力度越大线越明显
	aim_line.visible = true

	# 更新鼠标光标点
	mouse_cursor.global_position = end
	mouse_cursor.visible = true

	# 更新瞄准线末端箭头
	_update_aim_arrow(end, direction)


func _draw_dashed_line(start: Vector2, end: Vector2, direction: Vector2, total_distance: float) -> void:
	"""绘制虚线效果"""
	const dash_length: float = 15.0  # 虚线段长
	const gap_length: float = 10.0   # 虚线间隙

	var current_dist: float = 0.0
	var dash_on := true

	while current_dist < total_distance:
		var segment_length: float
		if dash_on:
			segment_length = min(dash_length, total_distance - current_dist)
		else:
			segment_length = min(gap_length, total_distance - current_dist)

		if dash_on:
			# 添加虚线段
			var line_start := start + direction * current_dist
			var line_end := start + direction * (current_dist + segment_length)

			var line := Line2D.new()
			line.width = 2.0
			line.default_color = Color(1, 1, 0, 0.6)
			line.add_point(line_start)
			line.add_point(line_end)
			add_child(line)
			aim_dots.append(line)

		current_dist += segment_length
		dash_on = not dash_on


func _cleanup_old_aim_lines() -> void:
	"""清理旧的虚线段"""
	for line in aim_dots:
		if is_instance_valid(line):
			line.queue_free()
	aim_dots.clear()


func _on_cursor_info_updated(cursor_info: Dictionary) -> void:
	"""鼠标光标圆环更新"""
	var pos: Vector2 = cursor_info["pos"]
	var timer: float = cursor_info["timer"]
	var max_radius: float = cursor_info["max_radius"]

	# 计算动态半径(呼吸效果)
	var radius: float = max_radius * (0.7 + 0.3 * sin(timer))

	# 创建或更新圆环
	if not cursor_ring or not is_instance_valid(cursor_ring):
		cursor_ring = Polygon2D.new()
		add_child(cursor_ring)
		cursor_ring.z_index = 100  # 在最上层

	var circle_points: PackedVector2Array = _create_circle_points(pos, radius, 32)
	cursor_ring.polygon = circle_points
	cursor_ring.color = Color(1, 1, 0, 0.6)  # 黄色半透明
	cursor_ring.antialiased = true
	cursor_ring.visible = true


func _update_all_player_arrows() -> void:
	"""统一更新所有球员的朝向箭头(每帧调用)"""
	var all_players: Array = []
	for p in team_a_players:
		if p and is_instance_valid(p):
			all_players.append(p)
	for p in team_b_players:
		if p and is_instance_valid(p):
			all_players.append(p)

	for player: CharacterBody2D in all_players:
		if player not in player_arrows:
			player_arrows[player] = _create_player_arrow()
			add_child(player_arrows[player])

		var arrow: Polygon2D = player_arrows[player]
		if not arrow or not is_instance_valid(arrow):
			player_arrows.erase(player)
			continue

		var direction: Vector2 = player.facing_direction
		_update_player_arrow(arrow, player.global_position, direction, player)


func _create_player_arrow() -> Polygon2D:
	"""创建球员朝向箭头(仅三角形尖尖)"""
	var arrow := Polygon2D.new()
	arrow.color = Color.CYAN
	arrow.antialiased = true
	return arrow


func _update_player_arrow(arrow: Polygon2D, player_pos: Vector2, direction: Vector2, player: CharacterBody2D = null) -> void:
	"""更新球员朝向箭头(仅三角形尖尖)+ 按队伍/控制状态区分颜色"""
	if not arrow or not is_instance_valid(arrow):
		return

	var distance: float = 35.0
	var start_pos := player_pos + direction * 10.0
	var tip_pos := start_pos + direction * distance

	const arrow_width: float = 12.0
	var perp := Vector2(-direction.y, direction.x)

	var points: PackedVector2Array = [
		tip_pos,
		start_pos + perp * arrow_width * 0.5,
		start_pos - perp * arrow_width * 0.5
	]

	arrow.polygon = points

	# 颜色区分:玩家青色 / 队友浅蓝半透明 / 对手浅红半透明
	if player and player.is_player_controlled:
		arrow.color = Color.CYAN
	elif player and player.team == "a":
		arrow.color = Color(0.5, 0.8, 1.0, 0.7)  # 浅蓝半透明
	else:
		arrow.color = Color(1.0, 0.5, 0.5, 0.5)  # 浅红半透明

	arrow.antialiased = true
	arrow.z_index = 50
	arrow.global_position = Vector2.ZERO


func _update_aim_arrow(end_pos: Vector2, direction: Vector2) -> void:
	"""更新瞄准线末端箭头"""
	if not aim_arrow or not is_instance_valid(aim_arrow):
		aim_arrow = Polygon2D.new()
		add_child(aim_arrow)
		aim_arrow.z_index = 99
		aim_arrow.visible = false

	aim_arrow.visible = true

	# 创建箭头形状(三角形)
	var arrow_length: float = 20.0
	var arrow_width: float = 15.0

	var perp := Vector2(-direction.y, direction.x)  # 垂直向量

	var tip := end_pos + direction * arrow_length
	var left := end_pos + perp * arrow_width * 0.5
	var right := end_pos - perp * arrow_width * 0.5

	var points: PackedVector2Array = [left, tip, right]
	aim_arrow.polygon = points
	aim_arrow.color = Color(1, 1, 0, 0.8)  # 黄色
	aim_arrow.antialiased = true


func _create_circle_points(center: Vector2, radius: float, segments: int) -> PackedVector2Array:
	"""创建圆的点集"""
	var points: PackedVector2Array = []
	for i in range(segments + 1):
		var angle: float = float(i) * PI * 2.0 / float(segments)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


# ===== AI和备战界面 =====

func _setup_ai_manager() -> void:
	"""设置AI管理器"""
	var ai_script := load("res://scripts/battle/ai_manager.gd")
	ai_mgr = Node.new()
	ai_mgr.name = "AIManager"
	ai_mgr.set_script(ai_script)
	add_child(ai_mgr)
	ai_mgr.initialize(self, input_mgr)

	# 队A:3个角色分工(前锋/后卫/支援)+ balanced
	var team_a_roles := ["attacker", "defender", "supporter"]
	for i in range(team_a_players.size()):
		var profile: AIProfile = AIProfile.get_role_preset(team_a_roles[i])
		AIProfile.apply_team_strategy(profile, "balanced")
		AIProfile.apply_difficulty(profile, "normal")
		ai_mgr.register_player(team_a_players[i], "a", i, profile)

	# 队B:随机角色(保证不重复)+ 随机策略 + 随机弱点
	var roles := ["attacker", "defender", "supporter"]
	roles.shuffle()
	var strategies := ["offensive", "defensive", "balanced"]
	var team_b_strategy: String = strategies[randi() % strategies.size()]

	for i in range(team_b_players.size()):
		var profile: AIProfile = AIProfile.get_role_preset(roles[i])
		AIProfile.apply_team_strategy(profile, team_b_strategy)
		# 随机弱点(30%无弱点)
		if randf() < 0.7:
			var weaknesses := ["slow_reaction", "ball_focused", "over_chase", "predictable_target"]
			var w: String = weaknesses[randi() % weaknesses.size()]
			AIProfile.apply_weakness(profile, w)
		AIProfile.apply_difficulty(profile, "normal")
		ai_mgr.register_player(team_b_players[i], "b", i, profile)

	print("[Match] AI管理器初始化完成 队B策略=%s" % team_b_strategy)


func _setup_comm_system() -> void:
	"""创建通信系统并连接信号"""
	var comm_script := load("res://scripts/battle/ai_communication.gd")
	comm_system = Node.new()
	comm_system.name = "AICommunication"
	comm_system.set_script(comm_script)
	add_child(comm_system)

	comm_system.set_ai_manager(ai_mgr)
	comm_system.set_ball(ball_node)

	# 连接消息信号
	comm_system.message_sent.connect(_on_comm_message_sent)

	# 连接玩家快捷指令(已在 _setup_input_manager 中连接,无需重复)

	# 连接HUD的通信系统
	if ui_layer:
		var hud = ui_layer.get_node_or_null("HUD")
		if hud and hud.has_method("set_comm_system"):
			hud.set_comm_system(comm_system)

	print("[Match] 通信系统初始化完成")


func _setup_preparation_ui() -> void:
	"""设置备战界面"""
	var prep_script := load("res://scripts/ui/preparation_ui.gd")
	preparation_ui = Control.new()
	preparation_ui.name = "PreparationUI"
	preparation_ui.set_script(prep_script)

	if ui_layer:
		ui_layer.add_child(preparation_ui)
	else:
		add_child(preparation_ui)

	# 加载数据
	preparation_ui.load_battle_data(team_a_players)

	# 连接AI管理器
	if ai_mgr:
		preparation_ui.set_ai_manager(ai_mgr)

	# 连接信号
	preparation_ui.strategy_changed.connect(_on_strategy_changed)
	preparation_ui.player_substituted.connect(_on_player_substituted)
	preparation_ui.spirit_changed.connect(_on_spirit_changed)
	preparation_ui.match_started_from_prep.connect(_on_prep_match_started)

	# 隐藏比赛场地(只显示备战窗口)
	if field_zone:
		field_zone.visible = false
	if ball_node:
		ball_node.visible = false
	for player: CharacterBody2D in team_a_players + team_b_players:
		if player and is_instance_valid(player):
			player.visible = false
	if penalty_walls:
		penalty_walls.visible = false
	# 隐藏瞄准线等视觉元素
	if aim_line:
		aim_line.visible = false
	if mouse_cursor:
		mouse_cursor.visible = false
	if aim_arrow and is_instance_valid(aim_arrow):
		aim_arrow.visible = false
	if cursor_ring and is_instance_valid(cursor_ring):
		cursor_ring.visible = false

	# 隐藏比赛HUD（备战期间不显示）
	var hud_node = ui_layer.get_node_or_null("HUD") if ui_layer else null
	if hud_node:
		hud_node.visible = false

	# 显示备战界面
	preparation_ui.visible = true

	# 暂停比赛
	GameManager.pause_match()

	# 锁定输入
	match_started = false
	if input_mgr:
		input_mgr.match_started = false

	print("[Match] 备战界面初始化完成")


func _on_strategy_changed(player_strategy: int, team_strategy: int) -> void:
	"""策略变更 - profile更新已由 preparation_ui._rebuild_team_a_profiles 处理"""
	print("[Match] 策略变更信号接收: 个人=%d, 团队=%d (profile已由备战面板更新)" % [player_strategy, team_strategy])


func _on_player_substituted(index: int, new_char_id: String) -> void:
	"""球员替补"""
	print("[Match] 球员%d替补为 %s" % [index, new_char_id])

	# TODO: 实现替补逻辑
	# 1. 创建新球员
	# 2. 替换旧球员
	# 3. 更新AI管理器
	# 4. 更新备战界面


func _on_spirit_changed(index: int, spirit_id: String) -> void:
	"""元灵切换"""
	print("[Match] 位置%d切换元灵为 %s" % [index, spirit_id])

	# TODO: 实现元灵切换逻辑
	# 1. 应用元灵属性到球员
	# 2. 更新备战界面


func _on_prep_match_started() -> void:
	"""备战界面点击开始比赛后:恢复场地、开始比赛、发球、解锁输入"""
	print("[Match] 备战完成,开始比赛!")

	# 显示比赛场地
	if field_zone:
		field_zone.visible = true
	if ball_node:
		ball_node.visible = true
	for player: CharacterBody2D in team_a_players + team_b_players:
		if player and is_instance_valid(player):
			player.visible = true
	if penalty_walls:
		penalty_walls.visible = true

	# 隐藏备战界面
	preparation_ui.visible = false

	# 显示比赛HUD
	var hud_node = ui_layer.get_node_or_null("HUD") if ui_layer else null
	if hud_node:
		hud_node.visible = true

	# 解锁
	match_started = true
	if input_mgr:
		input_mgr.match_started = true

	# 正式开始比赛
	GameManager.start_match()

	# 发球:球给随机一方
	_assign_initial_ball()
