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
# P0 空中斜线发球参数（release 时写入，battle_manager 读取；信号签名不动）
var last_throw_start_z: float = -1.0
var last_throw_pitch_deg: float = 0.0
# P2 第一人称模式（E 键切换；独立按键，不改既有鼠标语义）
var fp_mode: bool = false
var fp_yaw: float = 0.0              # 水平角（弧度；朝 2D +x 为 0）
var fp_pitch: float = 0.0            # 俯仰角（弧度，抬头为正）
const FP_PITCH_MIN: float = deg_to_rad(-60.0)
const FP_PITCH_MAX: float = deg_to_rad(30.0)
const FP_MOUSE_SENS: float = 0.003   # 鼠标灵敏度（弧度/像素）

# 操1 增补（操控规划/05）：项1 按键迁移偏航增量 + 项3 拖长击状态
const STEER_KEY_TURN_SPEED: float = 2.6   # A/D 朝向偏转速率（弧度/秒，≈150°/s）
var _skill_control_yaw: float = 0.0       # 本帧按键偏转增量（注入方向=facing 旋转此值）
var _drag_state: Dictionary = {"active": false, "a_pos": Vector2.ZERO, "b": null}
var _drag_ring_on: bool = false           # 拖动吸附高亮圈开关（功能性显示）

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
		# 快捷指令（整数键值：Godot 4.x 中 KEY_* 常量兼容性不稳）
		elif event.keycode == 55:   # KEY_7
			quick_command_requested.emit(0)  # 注意防守
		elif event.keycode == 56:   # KEY_8
			quick_command_requested.emit(1)  # 传球给我
		elif event.keycode == 57:   # KEY_9
			quick_command_requested.emit(2)  # 别传球
		# Tab（项6 操控规划/05 §4）：激活/子态期=技能状态切换；无激活=既有切换球员（上下文分流）
		elif event.keycode == KEY_TAB:
			if not _tab_skill_state_switch():
				_cycle_player()
		# 项1 空格迁移（05 §1 主人裁决 2026-09-24）：迁移期空格归技能体——贴地=跳跃/飞行=上升增量；
		# 球员侧跳跃由 player.gd 闸门同步抑制（迁移期不跳）
		elif event.keycode == KEY_SPACE:
			if is_skill_control_active():
				_route_space_to_skill()
		# P2 E键：第一人称进出（独立按键，不涉既有鼠标操作）
		elif event.keycode == KEY_E:
			toggle_fp_mode()
	
	# === 鼠标操作 ===
	if event is InputEventMouseButton:
		# 鼠标放置守卫：技能激活了障碍/区域/幻象放置模式时，鼠标交给 placer，不触发瞄准/发球/接球
		if _any_placer_operating():
			return
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

	# P2 第一人称：鼠标移动=转视角（相对模式，不依赖屏幕光标位置）
	# 水平：鼠标右移 rel.x>0 → 视线右转（yaw 增，朝向 (cosθ,·,sinθ) 的 θ 增方向）
	if fp_mode and event is InputEventMouseMotion:
		fp_yaw = fposmod(fp_yaw + event.relative.x * FP_MOUSE_SENS, TAU)
		fp_pitch = clampf(fp_pitch - event.relative.y * FP_MOUSE_SENS, FP_PITCH_MIN, FP_PITCH_MAX)


## P2 FP 移动向量（视角相对）：W前S后A左D右，随视线旋转（ax=A/D=-1/+1, ay=W/S=-1/+1）
## 返回世界系单位向量；输入全零返回 ZERO
func compute_fp_move(ax: float, ay: float) -> Vector2:
	if ax == 0.0 and ay == 0.0:
		return Vector2.ZERO
	var fwd := Vector2(cos(fp_yaw), sin(fp_yaw))
	var right := Vector2(-sin(fp_yaw), cos(fp_yaw))
	return (fwd * -ay + right * ax).normalized()


## P2 第一人称进出（E 键）。进入时以当前朝向初始化 yaw，pitch 清平视
## 进入=捕获鼠标（OS 光标隐藏，只出相对位移）；退出=恢复可见
func toggle_fp_mode() -> void:
	fp_mode = not fp_mode
	if fp_mode:
		if controlled_player and controlled_player.facing_direction.length_squared() > 0.001:
			fp_yaw = controlled_player.facing_direction.angle()
		fp_pitch = 0.0
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("[Input] 第一人称 %s" % ("进入" if fp_mode else "退出"))


func _on_left_click_press() -> void:
	if controlled_player == null:
		return

	# 项3（操控规划/05 §3.3）拖长击：drag 技能激活期左键按下=选 a（拖动吸附检测，松开作用；大相机限定）
	if not _drag_state.active and not fp_mode and skill_state_manager != null:
		var player_id = controlled_player.get_instance_id()
		var sub: String = skill_state_manager.get_operator_substate(player_id)
		if sub != "" and skill_state_manager.is_drag_skill(player_id):
			_drag_state = {"active": true, "a_pos": controlled_player.global_position, "b": null}
			return

	# 操1 大点3 输入路由器（增补：带坐标推进=再击两段/三段、召唤指定点；不走发球）
	# drag 技能排除：其确认由"按下-拖动-松开"手势完成，press 不做普通确认（FP 下拖动不可用=该技无操作）
	if skill_state_manager != null:
		var sub: String = skill_state_manager.get_operator_substate(controlled_player.get_instance_id())
		if sub != "" and not skill_state_manager.is_drag_skill(controlled_player.get_instance_id()) \
				and sub in ["AIMING", "SELECTING", "MARKING", "SUMMONING"]:
			skill_state_manager.confirm_substate_at(controlled_player.get_instance_id(), mouse_world_pos)
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

	# 项3 拖长击：松开=a 对 b 作用（有吸附对象）或取消选中（无 b，子态保留可重选）
	if _drag_state.active:
		var b = _drag_state.b
		var a_pos: Vector2 = _drag_state.a_pos
		_drag_state = {"active": false, "a_pos": Vector2.ZERO, "b": null}
		_set_drag_ring(null)
		if b != null and skill_state_manager != null:
			skill_state_manager.confirm_drag(controlled_player.get_instance_id(), a_pos, b, b.global_position)
		elif skill_state_manager != null:
			skill_state_manager.clear_substate_selection(controlled_player.get_instance_id())
		return

	# 缴械检查：灯亮则不能投球
	if controlled_player.is_status_active("disarmed"):
		is_aiming = false
		throw_cancelled.emit()
		aim_info_updated.emit({"aiming": false})
		return

	if controlled_player.is_carrying_ball and is_aiming:
		# 释放：计算力度和方向，发球
		var direction: Vector2
		var distance: float
		var power: float

		# P2 第一人称：方向=视线水平投影，力度=满蓄视觉距离（FP 无落点概念，按固定距离比例）
		if fp_mode:
			direction = Vector2(cos(fp_yaw), sin(fp_yaw))
			distance = 300.0 + 0.0
			power = 0.6
			# 出手参数：球点高度 + 视线俯仰（可打任意高度，含空中平射）
			last_throw_start_z = controlled_player.get_ball_origin_z()
			last_throw_pitch_deg = rad_to_deg(fp_pitch)
		else:
			# 第三人称：鼠标地面投影瞄准（既有逻辑）
			direction = (mouse_world_pos - controlled_player.global_position).normalized()
			distance = (mouse_world_pos - controlled_player.global_position).length()
			power = clampf(distance / 500.0, 0.1, 1.0)  # 最大力度对应500像素距离
			# P0 空中斜线发球：仅在跳跃空中出手时启用（地面发球恒高不变，sim 基线零影响）
			# 俯角对准鼠标地面投影点：tanφ = 出手高 / 水平距离
			last_throw_start_z = -1.0
			last_throw_pitch_deg = 0.0
			if controlled_player.z_height > 0.0 and distance > 20.0:
				last_throw_start_z = controlled_player.get_ball_origin_z()
				last_throw_pitch_deg = -rad_to_deg(atan2(last_throw_start_z, distance))

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

	# 项4（操控规划/05 §3.4）右键=取消选中：SELECTING/MARKING 子态清选中（子态保留可重选），不整段取消激活
	if skill_state_manager != null:
		var sub: String = skill_state_manager.get_operator_substate(controlled_player.get_instance_id())
		if sub in ["SELECTING", "MARKING"]:
			skill_state_manager.clear_substate_selection(controlled_player.get_instance_id())
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


## 项6（操控规划/05 §4）Tab 多重技能状态切换：激活/子态期消费 Tab，返回是否消费
## TOGGLED=再按同键语义（切换/关闭，复用既有按键路径）；其它子态=保留（v1 无多状态档）；无激活=false→切球员
func _tab_skill_state_switch() -> bool:
	if skill_state_manager == null or controlled_player == null:
		return false
	var player_id = controlled_player.get_instance_id()
	var sub: String = skill_state_manager.get_operator_substate(player_id)
	if sub == "":
		return false
	if sub == "TOGGLED":
		var active = skill_state_manager.get_active_skill(player_id)
		if not active.is_empty():
			skill_state_manager.on_skill_key_pressed(player_id, active.slot)
		return true
	print("[InputManager] Tab: 子态 %s 期保留（无多状态档切换，v1）" % sub)
	return true


## 项1（操控规划/05 §1）技能操控窗口：STEER 类激活期 或 球飞行手动态（波6 #17）——WASD/SPC 控制权在技能
func is_skill_control_active() -> bool:
	if skill_state_manager != null and controlled_player != null:
		if skill_state_manager.is_key_migration_active(controlled_player.get_instance_id()):
			return true
		var b = controlled_player.get("ball_ref")
		if b != null and is_instance_valid(b) and b.get("_manual_active") == true:
			return true
	return false


## 项3 拖长击吸附检测：鼠标附近 snap 半径内最近敌方=可作用对象 b（名册优先，组兜底）
func _find_drag_candidate() -> Node2D:
	if controlled_player == null:
		return null
	var snap_radius: float = 80.0
	if skill_state_manager != null:
		snap_radius = skill_state_manager.get_drag_snap_radius(controlled_player.get_instance_id())
	var my_team: String = str(controlled_player.get("team"))
	var candidates: Array = []
	var bm = get_parent().get("battle_manager") if get_parent() else null
	if bm != null:
		var enemy_team: Array = bm.get("team_b_players") if my_team == "a" else bm.get("team_a_players")
		if enemy_team is Array:
			candidates = enemy_team
	if candidates.is_empty() and is_inside_tree():
		for n in get_tree().get_nodes_in_group("players"):
			if n != controlled_player and str(n.get("team")) != my_team:
				candidates.append(n)
	var best: Node2D = null
	var best_d := snap_radius
	for c in candidates:
		if c == null or not is_instance_valid(c) or c.get("is_defeated") == true:
			continue
		var d: float = (c as Node2D).global_position.distance_to(mouse_world_pos)
		if d <= best_d:
			best_d = d
			best = c
	return best


## 项3 拖动吸附高亮（功能性显示：3D 目标圈；无 3D 载体时静默）
func _set_drag_ring(candidate: Node2D) -> void:
	var _ofb = get_tree().get_first_node_in_group("operator_feedback_3d") if is_inside_tree() else null
	if _ofb == null:
		return
	if candidate != null:
		_ofb.show_target_ring((candidate as Node2D).global_position)
		_drag_ring_on = true
	elif _drag_ring_on:
		_ofb.clear_target_ring()
		_drag_ring_on = false


## 项1 双源合成（纯函数可测）：基础朝向（鼠标/FP 折算）+ 按键偏转增量
func compose_steer_direction(base_dir: Vector2, key_yaw: float) -> Vector2:
	if absf(key_yaw) < 0.0001:
		return base_dir
	return base_dir.rotated(key_yaw)


## 项1 空格迁移路由：语义由技能 params.space_mode 定（rise=飞行上升增量/缺省 jump=贴地跳跃），作用于手动态球
func _route_space_to_skill() -> void:
	if skill_state_manager == null or controlled_player == null:
		return
	var mode: String = skill_state_manager.get_space_mode(controlled_player.get_instance_id())
	var b = controlled_player.get("ball_ref")
	if b != null and is_instance_valid(b) and b.get("_manual_active") == true and b.has_method("steer_space_action"):
		b.steer_space_action(mode)


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
	
	# 更新球员朝向（FP 下=视线方向；鼠标捕获后 mouse_world_pos 冻结不可用）
	if fp_mode:
		controlled_player.facing_direction = Vector2(cos(fp_yaw), sin(fp_yaw))
	else:
		controlled_player.facing_direction = (mouse_world_pos - controlled_player.global_position).normalized()
	player_facing_updated.emit(controlled_player, controlled_player.facing_direction)

	# 操1 大点5：AIMING 子态 → 3D 世界空间 AIM 预览跟随（2D 模式/无载体时静默=2D 兜底）
	var _ofb = get_tree().get_first_node_in_group("operator_feedback_3d") if is_inside_tree() else null
	if _ofb != null and skill_state_manager != null and controlled_player != null:
		var sub: String = skill_state_manager.get_operator_substate(controlled_player.get_instance_id())
		var op: String = skill_state_manager.get_active_operator(controlled_player.get_instance_id())
		if sub == "AIMING" and op == "OP_AIM":
			if not _ofb.has_meta("aim_shown"):
				_ofb.set_meta("aim_shown", true)
				_ofb.show_aim_preview(controlled_player.global_position, controlled_player.facing_direction)
			else:
				_ofb.update_aim_preview_dir(controlled_player.facing_direction)
		elif _ofb.has_meta("aim_shown"):
			_ofb.remove_meta("aim_shown")
			_ofb.hide_aim_preview()
	
	# 更新瞄准信息（始终发送，确保取消时能清除）
	aim_info_updated.emit(get_aim_info())

	# 项1（操控规划/05 §1）按键迁移：技能操控窗口内 A/D=朝向偏转增量（FP 下=视角偏转），注入方向双源叠加
	_skill_control_yaw = 0.0
	var migration := is_skill_control_active()
	if migration:
		var key_yaw := 0.0
		if Input.is_key_pressed(KEY_A):
			key_yaw += 1.0
		if Input.is_key_pressed(KEY_D):
			key_yaw -= 1.0
		_skill_control_yaw = key_yaw * STEER_KEY_TURN_SPEED * delta
		if fp_mode and key_yaw != 0.0:
			fp_yaw = fposmod(fp_yaw + key_yaw * STEER_KEY_TURN_SPEED * delta, TAU)

	# 波6 #17 手动制导（项1 双源）：方向=球员朝向（鼠标/FP 折算）+ A/D 偏转增量叠加
	if controlled_player.has_method("get") and controlled_player.get("ball_ref") != null:
		var steer_ball = controlled_player.get("ball_ref")
		if is_instance_valid(steer_ball) and steer_ball.is_active \
				and steer_ball.get("_manual_active") == true and steer_ball.has_method("manual_steer"):
			var steer_dir: Vector2 = compose_steer_direction(controlled_player.facing_direction, _skill_control_yaw)
			steer_ball.manual_steer(steer_dir)

	# 项3 拖长击：拖动中吸附检测（附近敌方=可作用对象 b；大相机限定），目标圈高亮为功能性显示
	if _drag_state.active and not fp_mode:
		_drag_state.b = _find_drag_candidate()
		_set_drag_ring(_drag_state.b)

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
	"""初始化技能状态管理器，并为当前球员设置技能"""
	if skill_state_manager == null:
		skill_state_manager = SkillStateManager.new()
		add_child(skill_state_manager)

		# 连接信号
		skill_state_manager.skill_activated.connect(_on_skill_activated)
		skill_state_manager.skill_cancelled.connect(_on_skill_cancelled)
		skill_state_manager.skill_released.connect(_on_skill_released)

	# 每次切换主控球员都重新设置该球员的技能（按 player_id 索引，安全可重复调用）
	if controlled_player and controlled_player.has_method("get_equipped_skills"):
		var skill_ids = controlled_player.get_equipped_skills()
		var player_id = controlled_player.get_instance_id()
		skill_state_manager.setup_player_skills(player_id, skill_ids)
		print("[InputManager] 已设置玩家技能: player=%d %d个" % [player_id, skill_ids.size()])


## 公开方法：重新读取当前主控球员的最新装备技能并刷新技能状态机
## 用于备战面板选/卸元灵后、比赛开始时同步（避免setup时机过早读到空数据）
func refresh_controlled_skills() -> void:
	_init_skill_state_manager()


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
	_show_skill_toast(skill_id, "激活")
	if controlled_player and controlled_player.get_instance_id() == player_id:
		if controlled_player.has_method("set_active_skill"):
			controlled_player.set_active_skill(skill_id)
		
		var skill_data = _get_skill_data(skill_id)
		var tags: Array = skill_data.get("tags", [])
		var has_ball_tag: bool = false
		var has_field_tag: bool = false
		var has_player_tag: bool = false
		
		for tag in tags:
			var category: String = _get_tag_category(tag)
			if category == "BALL":
				has_ball_tag = true
			elif category == "FIELD":
				has_field_tag = true
			elif category == "PLAYER":
				has_player_tag = true
		
		if has_field_tag or has_player_tag:
			print("[InputManager] 场地/球员类型技能，立即生效: %s" % skill_id)
			if controlled_player.has_method("use_skill_by_id"):
				controlled_player.use_skill_by_id(skill_id)
			if skill_state_manager:
				skill_state_manager.cancel_active_skill(player_id)


func _on_skill_cancelled(skill_id: String, player_id: int) -> void:
	"""技能已取消回调"""
	print("[InputManager] 技能已取消: %s (玩家:%d)" % [skill_id, player_id])
	_show_skill_toast(skill_id, "取消")
	if controlled_player and controlled_player.get_instance_id() == player_id:
		if controlled_player.has_method("clear_active_skill"):
			controlled_player.clear_active_skill()


func _on_skill_released(skill_id: String, player_id: int) -> void:
	"""技能已释放回调"""
	print("[InputManager] 技能已释放: %s (玩家:%d)" % [skill_id, player_id])
	_show_skill_toast(skill_id, "释放")
	if controlled_player and controlled_player.get_instance_id() == player_id:
		if controlled_player.has_method("clear_active_skill"):
			controlled_player.clear_active_skill()
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


## 检查是否有任意鼠标放置管理器正在操作（障碍/区域/幻象）
## 用于在技能激活鼠标放置时，屏藏球员的鼠标输入（瞄准/发球/接球）
func _any_placer_operating() -> bool:
	var parent_node = get_parent()
	if parent_node == null:
		return false
	for mgr_name in ["ObstacleManager", "FieldZoneManager", "IllusionManager"]:
		if parent_node.has_node(mgr_name):
			var mgr = parent_node.get_node(mgr_name)
			if mgr.has_method("is_operating") and mgr.is_operating():
				return true
	return false


## 显示技能提示弹窗（通过 battle_manager 找到 HUD）
func _show_skill_toast(skill_id: String, state: String) -> void:
	var parent_node = get_parent()
	if parent_node == null:
		return
	# battle_manager → UILayer → HUD
	var ui_layer = parent_node.get_node_or_null("UILayer")
	if ui_layer == null:
		return
	var hud = ui_layer.get_node_or_null("HUD")
	if hud and hud.has_method("show_skill_toast"):
		hud.show_skill_toast(skill_id, state)


## ==================== 技能辅助方法 ====================

var _skills_cache: Dictionary = {}
var _tags_registry_cache: Dictionary = {}
var _tags_loaded: bool = false


func _get_skill_data(skill_id: String) -> Dictionary:
	"""获取技能数据（带缓存）"""
	if _skills_cache.has(skill_id):
		return _skills_cache[skill_id]
	
	var skill_data: Dictionary = {}
	if DataManager and DataManager.has_method("get_skill_by_id"):
		skill_data = DataManager.get_skill_by_id(skill_id)
	
	_skills_cache[skill_id] = skill_data
	return skill_data


func _get_tag_category(tag_id: String) -> String:
	"""获取标签分类（BALL/FIELD/PLAYER）"""
	if not _tags_loaded:
		_load_tags_registry()
	
	if _tags_registry_cache.has(tag_id):
		return _tags_registry_cache[tag_id].get("category", "")
	return ""


func _load_tags_registry() -> void:
	"""加载标签注册表"""
	_tags_loaded = true
	if not FileAccess.file_exists("res://data/spirits/tags_registry.json"):
		return
	
	var file = FileAccess.open("res://data/spirits/tags_registry.json", FileAccess.READ)
	if not file:
		return
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_text) != OK:
		return
	
	var tags_array = json.data.get("tags", [])
	for tag in tags_array:
		_tags_registry_cache[tag.id] = tag
