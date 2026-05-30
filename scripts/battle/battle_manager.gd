extends Node2D
## 比赛主场景 - 管理一场比赛的完整流程
## 场景树：FieldZone + Ball + 6 Players + UI

# 场地配置
const FIELD_WIDTH: float = 1300.0
const FIELD_HEIGHT: float = 780.0

# 节点引用（动态创建）
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
var preparation_ui: Control  # 备战界面

# 比赛是否已开始
var match_started: bool = false

# 违规处理队列
var pending_transfers: Array[Dictionary] = []  # [{player, offset_index, timer}]
const TRANSFER_DELAY: float = 1.0  # 传送延迟

# 违规状态追踪（防重复触发）
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
	_setup_preparation_ui()
	
	GameManager.phase_changed.connect(_on_phase_changed)
	GameManager.match_paused.connect(_on_match_paused)
	GameManager.match_resumed.connect(_on_match_resumed)
	
	if field_zone:
		field_zone.player_transition_completed.connect(_on_player_transition_completed)
	
	# 不在这里 start_match，等备战完成后由 _on_prep_match_started 触发
	GameManager.match_phase = GameManager.MatchPhase.PREP
	
	# 启动违规处理定时器
	set_process(true)
	
	# 初始化瞄准线
	_create_aim_visuals()
	
	# 连接输入信号
	if input_mgr:
		input_mgr.aim_info_updated.connect(_on_aim_info_updated)
		input_mgr.cursor_info_updated.connect(_on_cursor_info_updated)
		input_mgr.player_facing_updated.connect(_on_player_facing_updated)


func _create_field() -> void:
	"""创建场地区域管理器（含视觉+碰撞+区域判定）"""
	var field_script := load("res://scripts/battle/field_zone.gd")
	field_zone = Node2D.new()
	field_zone.name = "FieldZone"
	field_zone.set_script(field_script)
	add_child(field_zone)
	
	# 边界碰撞墙（蓝色禁区边界）
	_create_wall(Vector2(-FIELD_WIDTH / 2.0, 0.0), Vector2(10.0, FIELD_HEIGHT))    # 左
	_create_wall(Vector2(FIELD_WIDTH / 2.0,  0.0), Vector2(10.0, FIELD_HEIGHT))    # 右
	_create_wall(Vector2(0.0, -FIELD_HEIGHT / 2.0), Vector2(FIELD_WIDTH, 10.0))   # 上
	_create_wall(Vector2(0.0, FIELD_HEIGHT / 2.0), Vector2(FIELD_WIDTH, 10.0))    # 下
	
	# 创建隔离墙
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
	# 队A初始位置：内场左半（队A半场）
	var team_a_ids := ["char_001", "char_002", "char_003"]
	var team_a_positions := [
		Vector2(-260, -130),
		Vector2(-320, 0),
		Vector2(-260, 130)
	]
	
	for i in range(3):
		var player := _create_player(team_a_ids[i], "a", i == 0, team_a_positions[i])
		team_a_players.append(player)
	
	# 队B初始位置：内场右半（队B半场）
	var team_b_ids := ["char_004", "char_005", "char_006"]
	var team_b_positions := [
		Vector2(260, -130),
		Vector2(320, 0),
		Vector2(260, 130)
	]
	
	for i in range(3):
		var player := _create_player(team_b_ids[i], "b", false, team_b_positions[i])
		team_b_players.append(player)
	
	input_mgr.all_team_players = team_a_players
	input_mgr.set_controlled_player(team_a_players[0])
	
	GameManager.team_a = team_a_players
	GameManager.team_b = team_b_players
	
	# 球权分配推迟到备战完成后（_on_prep_match_started）


func _create_player(char_id: String, team_name: String, controlled: bool, start_pos: Vector2) -> CharacterBody2D:
	var player_script := load("res://scripts/battle/player.gd")
	var player := CharacterBody2D.new()
	player.name = "Player_%s_%d" % [team_name, team_a_players.size() + team_b_players.size()]
	player.set_script(player_script)
	player.position = start_pos
	player.collision_layer = 1
	player.collision_mask = 1 | 16  # layer 1(球员互碰) + layer 5(penalty_walls)
	add_child(player)
	player.initialize(char_id, team_name, controlled)
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


func _on_catch_entered() -> void:
	pass


func _on_catch_exited() -> void:
	pass


func _on_skill_requested(slot: int) -> void:
	var player: CharacterBody2D = input_mgr.controlled_player
	if player:
		player.use_skill(slot)


func _on_quick_command(command: int) -> void:
	match command:
		0: print("[Match] 快捷指令: 把球给我!")
		1: print("[Match] 快捷指令: 准备接球!")


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
				# 新违规，触发处理
				_handle_violation(player, violation)
				violating_players[player] = violation
		else:
			# 未违规，清除记录
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
	
	# 安排传送（1秒延迟后）
	_schedule_transfer(player, violation_type)


func _schedule_transfer(player: CharacterBody2D, violation_type: int) -> void:
	"""安排传送到自己的外场（防重叠）"""
	# 计算偏移索引（同一外场已安排的传送数）
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
	"""每帧处理：违规检测 + 传送队列"""
	# 持续检测违规
	_check_violations()
	
	# 处理传送队列
	if pending_transfers.is_empty():
		return
	
	var all_done := true
	for item in pending_transfers:
		var p = item["player"]
		var offset = item["offset_index"] if item.has("offset_index") else 0
		if p and is_instance_valid(p):
			item["timer"] -= delta
			if item["timer"] <= 0:
				# 执行传送
				field_zone.start_field_transition(p, offset)
				item["player"] = null  # 标记已完成
			else:
				all_done = false
	
	# 所有传送完成后恢复比赛
	if all_done:
		pending_transfers.clear()
		GameManager.resume_match()
		print("[Match] 传送完成，比赛恢复")


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
	"""创建外场隔离墙（限制失分球员不能离开外场）"""
	penalty_walls = Node2D.new()
	penalty_walls.name = "PenaltyWalls"
	add_child(penalty_walls)
	
	# 左外场隔离墙（队B的外场白色边框，2px厚）
	_create_penalty_wall(Vector2(-511.0, 0.0), Vector2(2.0, 650.0))   # 左边 x=-510
	_create_penalty_wall(Vector2(-381.0, 0.0), Vector2(2.0, 650.0))   # 右边 x=-380
	_create_penalty_wall(Vector2(-445.0, -326.0), Vector2(130.0, 2.0))  # 上边 y=-325
	_create_penalty_wall(Vector2(-445.0, 324.0), Vector2(130.0, 2.0))   # 下边 y=325
	
	# 左外场上臂边界
	_create_penalty_wall(Vector2(-381.0, -326.0), Vector2(2.0, 65.0))   # 上臂右边界
	_create_penalty_wall(Vector2(-381.0, 260.0), Vector2(2.0, 65.0))    # 下臂右边界
	
	# 右外场隔离墙（队A的外场白色边框，2px厚）
	_create_penalty_wall(Vector2(379.0, 0.0), Vector2(2.0, 650.0))    # 左边 x=380
	_create_penalty_wall(Vector2(509.0, 0.0), Vector2(2.0, 650.0))    # 右边 x=510
	_create_penalty_wall(Vector2(445.0, -326.0), Vector2(130.0, 2.0))  # 上边 y=-325
	_create_penalty_wall(Vector2(445.0, 324.0), Vector2(130.0, 2.0))   # 下边 y=325
	
	# 右外场上臂边界
	_create_penalty_wall(Vector2(379.0, -326.0), Vector2(2.0, 65.0))   # 上臂左边界
	_create_penalty_wall(Vector2(379.0, 260.0), Vector2(2.0, 65.0))    # 下臂左边界
	
	print("[Match] 隔离墙创建完成")


func _create_penalty_wall(pos: Vector2, size: Vector2) -> void:
	"""创建单个隔离墙"""
	var wall := StaticBody2D.new()
	wall.position = pos
	wall.name = "PenaltyWall"
	
	# 设置碰撞层：layer 5 (penalty_walls)
	wall.collision_layer = 1 << 4  # bit 4 = layer 5
	wall.collision_mask = 0  # 墙不检测任何碰撞，只阻挡球员
	
	var wall_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	wall_shape.shape = rect
	wall.add_child(wall_shape)
	
	penalty_walls.add_child(wall)


func _on_player_transition_completed(player: CharacterBody2D) -> void:
	"""球员传送完成，设置惩罚状态"""
	if player and player.has_method("set_penalized"):
		player.set_penalized(true)


# ===== 瞄准可视化 =====

func _create_aim_visuals() -> void:
	"""创建瞄准线可视化"""
	# 瞄准虚线
	aim_line = Line2D.new()
	aim_line.width = 3.0
	aim_line.default_color = Color(1, 1, 0, 0.7)  # 黄色半透明
	add_child(aim_line)
	aim_line.visible = false
	
	# 鼠标光标点（十字准星）
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
	
	# 绘制新的虚线效果（通过多个短线实现）
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
	
	# 计算动态半径（呼吸效果）
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


func _on_player_facing_updated(player: CharacterBody2D, facing_direction: Vector2) -> void:
	"""球员朝向更新"""
	if not player or not is_instance_valid(player):
		return
	
	# 创建或更新朝向箭头
	if player not in player_arrows:
		player_arrows[player] = _create_player_arrow()
		add_child(player_arrows[player])
	
	_update_player_arrow(player_arrows[player], player.global_position, facing_direction)


func _create_player_arrow() -> Polygon2D:
	"""创建球员朝向箭头（仅三角形尖尖）"""
	var arrow := Polygon2D.new()
	arrow.color = Color.CYAN
	arrow.antialiased = true
	return arrow


func _update_player_arrow(arrow: Polygon2D, player_pos: Vector2, direction: Vector2) -> void:
	"""更新球员朝向箭头（仅三角形尖尖）"""
	if not arrow or not is_instance_valid(arrow):
		return
	
	var distance: float = 35.0  # 箭头距离球员的距离
	var start_pos := player_pos + direction * 10.0  # 从球员前方10px开始
	var tip_pos := start_pos + direction * distance
	
	# 三角形箭头参数
	const arrow_length: float = 15.0
	const arrow_width: float = 12.0
	
	# 计算垂直向量
	var perp := Vector2(-direction.y, direction.x)
	
	# 创建三角形箭头点
	var points: PackedVector2Array = [
		tip_pos,  # 尖端
		start_pos + perp * arrow_width * 0.5,  # 左底
		start_pos - perp * arrow_width * 0.5   # 右底
	]
	
	arrow.polygon = points
	arrow.color = Color.CYAN
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
	
	# 创建箭头形状（三角形）
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
	
	# 注册所有球员到AI管理器
	for i in range(team_a_players.size()):
		ai_mgr.register_player(team_a_players[i], "a", i)
	
	for i in range(team_b_players.size()):
		ai_mgr.register_player(team_b_players[i], "b", i)
	
	print("[Match] AI管理器初始化完成")


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
	
	# 隐藏比赛场地（只显示备战窗口）
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
	"""策略变更"""
	print("[Match] 策略变更: 个人=%d, 团队=%d" % [player_strategy, team_strategy])
	
	# 更新AI管理器
	if ai_mgr:
		ai_mgr.set_team_strategy("a", team_strategy)
		
		# 更新所有队友的个人策略
		for i in range(team_a_players.size()):
			ai_mgr.set_player_strategy(i, player_strategy)


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
	"""备战界面点击开始比赛后：恢复场地、开始比赛、发球、解锁输入"""
	print("[Match] 备战完成，开始比赛!")
	
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
	
	# 解锁
	match_started = true
	if input_mgr:
		input_mgr.match_started = true
	
	# 正式开始比赛
	GameManager.start_match()
	
	# 发球：球给随机一方
	_assign_initial_ball()
