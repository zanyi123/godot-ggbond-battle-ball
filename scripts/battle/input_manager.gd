extends Node
## 输入管理器 - 处理玩家操作
## 管理：球员切换、发球预瞄、待接球、技能快捷键、快捷指令
## 控制方式：鼠标朝向、W朝前移动、左键发球瞄准

var controlled_player: CharacterBody2D = null
var all_team_players: Array[CharacterBody2D] = []

# 比赛是否已开始（备战期间为false，锁定所有输入）
var match_started: bool = false

# 发球预瞄
var is_aiming: bool = false

# 技能状态管理器
var skill_state_manager: SkillStateManager = null

# 鼠标位置（世界坐标）
var mouse_world_pos: Vector2 = Vector2.ZERO

# 鼠标光标圆环动画
var cursor_ring_timer: float = 0.0
const CURSOR_RING_MAX_RADIUS: float = 25.0  # 直径50像素 = 半径25像素
const CURSOR_RING_ANIMATION_SPEED: float = 3.0  # 闪烁速度

signal player_switch_requested(player_index: int)
signal throw_requested(direction: Vector2, power: float)
signal throw_cancelled()
signal catch_state_entered()
signal catch_state_exited()
signal skill_requested(slot: int)
signal quick_command_requested(command: int)
signal aim_info_updated(aim_info: Dictionary)
signal cursor_info_updated(cursor_info: Dictionary)
signal player_facing_updated(player: CharacterBody2D, facing_direction: Vector2)
signal skill_cancel_requested(player_id: int)


func _input(event: InputEvent) -> void:
	if not match_started:
		return
	if controlled_player == null:
		return

	# === 球员切换（点击头像/Tab） ===
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_1:
			player_switch_requested.emit(0)
		elif event.keycode == KEY_2:
			player_switch_requested.emit(1)
		elif event.keycode == KEY_3:
			player_switch_requested.emit(2)
		# 技能快捷键
		elif event.keycode == KEY_4:
			_handle_skill_key_press(0)
		elif event.keycode == KEY_5:
			_handle_skill_key_press(1)
		elif event.keycode == KEY_6:
			_handle_skill_key_press(2)
		# C键取消技能
		elif event.keycode == KEY_C:
			_handle_skill_cancel()
		# 快捷指令
		elif event.keycode == KEY_7:
			quick_command_requested.emit(0)  # 注意防守
		elif event.keycode == KEY_8:
			quick_command_requested.emit(1)  # 传球给我
		elif event.keycode == KEY_9:
			quick_command_requested.emit(2)  # 别传球
		# Tab切换球员
		elif event.keycode == KEY_TAB:
			_cycle_player()
	
	# === 鼠标操作 ===
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_on_left_click_press()
			else:
				_on_left_click_release()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_on_right_click_press()
			else:
				_on_right_click_release()


func _on_left_click_press() -> void:
	if controlled_player == null:
		return

	if controlled_player.is_carrying_ball:
		# 持球：进入瞄准状态
		is_aiming = true
	else:
		# 无球：冲刺加速
		controlled_player.start_sprint()


func _on_left_click_release() -> void:
	if controlled_player == null:
		return

	# 缴械检查：灯亮则不能投球
	if controlled_player.is_status_active("disarmed"):
		is_aiming = false
		throw_cancelled.emit()
		aim_info_updated.emit({"aiming": false})
		return

	if controlled_player.is_carrying_ball and is_aiming:
		# 释放：计算力度和方向（鼠标到球员方向），发球
		var direction := (mouse_world_pos - controlled_player.global_position).normalized()
		var distance: float = (mouse_world_pos - controlled_player.global_position).length()
		var power := clampf(distance / 500.0, 0.1, 1.0)  # 最大力度对应500像素距离
		
		if distance > 20.0:  # 最小距离阈值
			throw_requested.emit(direction, power)
		else:
			throw_cancelled.emit()
			# 发送空的瞄准信息（确保UI清除瞄准线）
			aim_info_updated.emit({"aiming": false})
		
		is_aiming = false
	
	elif not controlled_player.is_carrying_ball:
		# 无球松开：冲刺不受松开影响（持续到时间结束）
		pass


func _on_right_click_press() -> void:
	if controlled_player == null:
		return
	
	if is_aiming:
		# 预发球中右键取消
		is_aiming = false
		# 发送取消信号（清除瞄准线）
		throw_cancelled.emit()
		# 发送空的瞄准信息（确保UI清除瞄准线）
		aim_info_updated.emit({"aiming": false})
	elif not controlled_player.is_carrying_ball:
		# 无球：进入待接球状态
		controlled_player.enter_catch_state()
		catch_state_entered.emit()


func _on_right_click_release() -> void:
	if controlled_player == null:
		return
	
	if controlled_player.is_ready_to_catch:
		controlled_player.exit_catch_state()
		catch_state_exited.emit()


func _cycle_player() -> void:
	"""Tab键循环切换球员"""
	if all_team_players.is_empty():
		return
	var current_idx := all_team_players.find(controlled_player)
	var next_idx := (current_idx + 1) % all_team_players.size()
	player_switch_requested.emit(next_idx)


func set_controlled_player(player: CharacterBody2D) -> void:
	if controlled_player:
		controlled_player.is_player_controlled = false
	controlled_player = player
	if controlled_player:
		controlled_player.is_player_controlled = true
		# 初始化技能状态管理器
		_init_skill_state_manager()


func get_aim_info() -> Dictionary:
	"""获取当前瞄准信息（用于UI绘制辅助线）"""
	if not is_aiming or controlled_player == null:
		return {"aiming": false}
	
	var player_pos := controlled_player.global_position
	var direction := (mouse_world_pos - player_pos).normalized()
	var distance: float = (mouse_world_pos - player_pos).length()
	var power := clampf(distance / 500.0, 0.1, 1.0)
	
	return {
		"aiming": true,
		"start": player_pos,
		"end": mouse_world_pos,
		"direction": direction,
		"power": power,
		"distance": distance
	}


func _process(delta: float) -> void:
	"""每帧更新鼠标世界坐标和朝向"""
	if not match_started:
		return
	if controlled_player == null:
		return
	
	# 获取鼠标世界坐标
	var viewport := get_viewport()
	if viewport:
		var camera := viewport.get_camera_2d()
		if camera:
			mouse_world_pos = camera.get_global_mouse_position()
		else:
			mouse_world_pos = viewport.get_mouse_position()
	
	# 更新球员朝向
	controlled_player.facing_direction = (mouse_world_pos - controlled_player.global_position).normalized()
	player_facing_updated.emit(controlled_player, controlled_player.facing_direction)
	
	# 更新瞄准信息（始终发送，确保取消时能清除）
	aim_info_updated.emit(get_aim_info())
	
	# 更新鼠标圆环动画
	cursor_ring_timer += delta * CURSOR_RING_ANIMATION_SPEED
	if cursor_ring_timer >= PI * 2:
		cursor_ring_timer = 0.0
	
	# 发送鼠标圆环信息
	cursor_info_updated.emit({
		"pos": mouse_world_pos,
		"timer": cursor_ring_timer,
		"max_radius": CURSOR_RING_MAX_RADIUS
	})


func get_movement_direction(input_dir: Vector2) -> Vector2:
	"""根据输入方向和鼠标朝向计算实际移动方向"""
	if controlled_player == null:
		return input_dir

	# W键：朝向鼠标方向移动
	if input_dir.length() > 0 and Input.is_key_pressed(KEY_W):
		return controlled_player.facing_direction

	return input_dir


## ==================== 技能系统处理 ====================

func _init_skill_state_manager() -> void:
	"""初始化技能状态管理器"""
	if skill_state_manager == null:
		skill_state_manager = SkillStateManager.new()
		add_child(skill_state_manager)

		# 连接信号
		skill_state_manager.skill_activated.connect(_on_skill_activated)
		skill_state_manager.skill_cancelled.connect(_on_skill_cancelled)
		skill_state_manager.skill_released.connect(_on_skill_released)

		# 设置玩家技能
		if controlled_player and controlled_player.has_method("get_equipped_skills"):
			var skill_ids = controlled_player.get_equipped_skills()
			var player_id = controlled_player.get_instance_id()
			skill_state_manager.setup_player_skills(player_id, skill_ids)
			print("[InputManager] 已设置玩家技能: %d个" % skill_ids.size())


func _handle_skill_key_press(slot: int) -> void:
	"""处理技能键按下（检测双击）"""
	if not controlled_player:
		return

	if skill_state_manager == null:
		# 降级：直接发送技能请求
		skill_requested.emit(slot)
		return

	var player_id = controlled_player.get_instance_id()
	var auto_release = skill_state_manager.on_skill_key_pressed(player_id, slot)

	if auto_release:
		# 双击：自动释放
		_release_active_skill(player_id)
	else:
		# 单击：激活或取消
		pass


func _handle_skill_cancel() -> void:
	"""处理C键取消技能"""
	if not controlled_player:
		return

	if skill_state_manager:
		var player_id = controlled_player.get_instance_id()
		var cancelled = skill_state_manager.cancel_active_skill(player_id)
		if cancelled:
			print("[InputManager] C键取消技能")
		skill_cancel_requested.emit(player_id)


func _on_skill_activated(skill_id: String, player_id: int) -> void:
	"""技能已激活回调"""
	print("[InputManager] 技能已激活: %s (玩家:%d)" % [skill_id, player_id])
	# TODO: 通知UI显示激活状态


func _on_skill_cancelled(skill_id: String, player_id: int) -> void:
	"""技能已取消回调"""
	print("[InputManager] 技能已取消: %s (玩家:%d)" % [skill_id, player_id])
	# TODO: 通知UI清除激活状态


func _on_skill_released(skill_id: String, player_id: int) -> void:
	"""技能已释放回调"""
	print("[InputManager] 技能已释放: %s (玩家:%d)" % [skill_id, player_id])
	# 通知玩家执行技能
	if controlled_player and controlled_player.get_instance_id() == player_id:
		if controlled_player.has_method("use_skill_by_id"):
			controlled_player.use_skill_by_id(skill_id)


func _release_active_skill(player_id: int) -> void:
	"""释放当前激活的技能"""
	var active_skill = skill_state_manager.get_active_skill(player_id)
	if not active_skill.is_empty():
		var slot = active_skill.slot
		skill_state_manager._release_skill(player_id, slot)


## 清理
func cleanup() -> void:
	if skill_state_manager and controlled_player:
		var player_id = controlled_player.get_instance_id()
		skill_state_manager.cleanup_player(player_id)
