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
			skill_requested.emit(0)
		elif event.keycode == KEY_5:
			skill_requested.emit(1)
		elif event.keycode == KEY_6:
			skill_requested.emit(2)
		# 快捷指令
		elif event.keycode == KEY_7:
			quick_command_requested.emit(0)  # 把球给我
		elif event.keycode == KEY_8:
			quick_command_requested.emit(1)  # 准备接球
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
		# 无球：加速奔跑
		controlled_player.speed *= 1.5


func _on_left_click_release() -> void:
	if controlled_player == null:
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
		
		is_aiming = false
	
	elif not controlled_player.is_carrying_ball:
		# 无球加速结束
		controlled_player.speed /= 1.5


func _on_right_click_press() -> void:
	if controlled_player == null:
		return
	
	if is_aiming:
		# 预发球中右键取消
		is_aiming = false
		throw_cancelled.emit()
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


func _process(_delta: float) -> void:
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
		
	# 更新球员朝向
	controlled_player.facing_direction = (mouse_world_pos - controlled_player.global_position).normalized()
	player_facing_updated.emit(controlled_player, controlled_player.facing_direction)
	
	# 更新瞄准信息
	if is_aiming:
		aim_info_updated.emit(get_aim_info())
	
	# 更新鼠标圆环动画
	cursor_ring_timer += _delta * CURSOR_RING_ANIMATION_SPEED
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
