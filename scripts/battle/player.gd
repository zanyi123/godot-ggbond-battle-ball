extends CharacterBody2D
## 球员节点 - 2D表示(带背景色的数字头像)
## 处理移动、接球、发球、状态管理

@export var character_id: String = ""
@export var team: String = "a"  # "a" 或 "b"
@export var is_player_controlled: bool = false

# 球员数据(从DataManager加载)
var char_data: Dictionary = {}

# 运行时属性
var stamina: float = 100.0
var max_stamina: float = 100.0
var defense: float = 0.0
var speed: float = 200.0

# 全局速度缩放:角色数据中speed范围50~85
# 缩放后范围150~255,场地760px宽,最快约1.5秒穿半场
const SPEED_SCALE: float = 3.25
var attack_power: float = 0.0
var resilience: float = 50.0
var defense_factor: float = 0.15  # 防御因子(0.1~0.2)
var spirit_energy: float = 0.0
var max_spirit_energy: float = 100.0

# 状态
var is_defeated: bool = false
signal defeated(player: CharacterBody2D)  # 被击败信号
var is_carrying_ball: bool = false
var is_ready_to_catch: bool = false  # 待接球状态
var is_charging_throw: bool = false   # 预发球状态
var charge_start_pos: Vector2 = Vector2.ZERO
var assigned_role: int = 0  # GameManager.PlayerRole
var is_penalized: bool = false  # 是否被惩罚(在外场隔离中)

# 击退状态
var _knockback_timer: float = 0.0  # 击退持续时间
var _stagger_timer: float = 0.0  # 僵直持续时间（被击中后无法移动）

# 冲刺状态
var is_sprinting: bool = false
var sprint_timer: float = 0.0      # 冲刺剩余时间
var sprint_cooldown: float = 0.0   # 冷却剩余时间
const SPRINT_SPEED_BONUS: float = 50.0  # 冲刺加速量
const SPRINT_DURATION: float = 3.0      # 冲刺持续3秒
const SPRINT_COOLDOWN: float = 2.0      # 冷却2秒

# 角色(主攻/防御/辅助)
var role: String = "attacker"

# 天赋
var talent_name: String = ""
var talent_desc: String = ""

# 元灵
var spirit_id: String = ""
var equipped_skills: Array[int] = []  # 最多4个技能ID

# 技能CD追踪
var skill_cooldowns: Dictionary = {}

# 视觉节点
var avatar_label: Label
var avatar_bg: ColorRect
var stamina_bar: ProgressBar
var energy_bar: ProgressBar
var state_indicator: ColorRect  # 状态指示(待接球/预发球等)
var facing_direction: Vector2 = Vector2.ZERO  # 由 register_player 或输入设置


func _ready() -> void:
	_setup_visuals()


func initialize(data_id: String, team_name: String, controlled: bool) -> void:
	character_id = data_id
	team = team_name
	is_player_controlled = controlled

	# 从DataManager加载数据
	char_data = DataManager.get_character_by_id(character_id)
	if char_data.is_empty():
		push_error("[Player] 找不到角色数据: %s" % character_id)
		return

	# 设置属性
	max_stamina = char_data["stamina"] if char_data.has("stamina") else 100.0
	stamina = max_stamina
	defense = char_data["defense"] if char_data.has("defense") else 50.0
	# speed 统一从角色数据出发,全局缩放
	# 原始范围50~85,缩放后150~255,让场地移动节奏合理
	var raw_speed: float = char_data["speed"] if char_data.has("speed") else 50.0
	speed = raw_speed * SPEED_SCALE
	attack_power = char_data["attack"] if char_data.has("attack") else 50.0
	resilience = char_data["resilience"] if char_data.has("resilience") else 50.0
	defense_factor = char_data["defense_factor"] if char_data.has("defense_factor") else 0.15
	talent_name = char_data["talent_name"] if char_data.has("talent_name") else ""
	talent_desc = char_data["talent_desc"] if char_data.has("talent_desc") else ""

	_setup_visuals()


func _setup_visuals() -> void:
	# 创建角色头像:带背景色的数字圆形
	# 碰撞区域
	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 28.0
	collision.shape = circle
	add_child(collision)

	# 背景色圆
	avatar_bg = ColorRect.new()
	avatar_bg.size = Vector2(56, 56)
	avatar_bg.position = Vector2(-28, -28)
	avatar_bg.color = Color.BLUE if team == "a" else Color.RED
	# 圆角模拟
	avatar_bg.add_theme_stylebox_override("normal", _make_circle_style(20))
	add_child(avatar_bg)

	# 数字标签(球员编号)
	avatar_label = Label.new()
	avatar_label.text = _get_display_number()
	avatar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	avatar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	avatar_label.position = Vector2(-28, -28)
	avatar_label.size = Vector2(56, 56)
	add_child(avatar_label)

	# 体力条和能量条不再显示在球员头上，只在下方球员栏显示

	# 状态指示器
	state_indicator = ColorRect.new()
	state_indicator.size = Vector2(12, 12)
	state_indicator.position = Vector2(16, -48)
	state_indicator.color = Color.TRANSPARENT
	add_child(state_indicator)


func _make_circle_style(radius: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.BLUE
	style.set_corner_radius_all(int(radius))
	return style


func _get_display_number() -> String:
	if char_data.is_empty():
		return "#"
	return str(char_data["name"] if char_data.has("name") else "#").substr(0, 1)


func _physics_process(delta: float) -> void:
	# 冲刺计时器更新（无论谁控制都要跑）
	if is_sprinting:
		sprint_timer -= delta
		if sprint_timer <= 0.0:
			is_sprinting = false
			sprint_timer = 0.0
			sprint_cooldown = SPRINT_COOLDOWN
	elif sprint_cooldown > 0.0:
		sprint_cooldown -= delta
		if sprint_cooldown < 0.0:
			sprint_cooldown = 0.0

	# 击退中：只执行移动，不处理输入
	if _knockback_timer > 0.0:
		_knockback_timer -= delta
		if _knockback_timer <= 0.0:
			_knockback_timer = 0.0
			velocity = Vector2.ZERO
		move_and_slide()
		return

	# 僵直中：无法移动（站着不动）
	if _stagger_timer > 0.0:
		_stagger_timer -= delta
		if _stagger_timer <= 0.0:
			_stagger_timer = 0.0
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if not is_player_controlled:
		return  # AI控制由AI管理器处理

	# 计算实际移动速度（含冲刺加成）
	var move_speed: float = speed
	if is_sprinting:
		move_speed += SPRINT_SPEED_BONUS

	# 移动（包括外场球员，由隔离墙限制范围即可）
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.y = Input.get_axis("move_up", "move_down")

	if input_dir != Vector2.ZERO:
		# W键（上）：朝鼠标方向移动
		if input_dir.y < 0:
			velocity = facing_direction * move_speed
		else:
			velocity = input_dir.normalized() * move_speed
		# 玩家控制时根据移动方向更新朝向
		if velocity.length() > 1.0:
			facing_direction = velocity.normalized()
	else:
		velocity = Vector2.ZERO

	move_and_slide()


func take_damage(amount: float, attacker: CharacterBody2D = null) -> Dictionary:
	"""受到伤害,返回 {damage: int, effect: String}
	effect: "none" / "knockback1" / "knockback2" / "ball_fly" / "knockback_and_fly"

	非待接球: 新体力 = 当前体力 + 防御抗力 - 攻击（无韧性）
	待接球:   新体力 = 当前体力 + 防御抗力 - 攻击×(1-衰减率)（韧性生效+效果判定）
	"""
	if is_defeated:
		return {"damage": 0, "effect": "none"}

	var defense_resist: float = defense * defense_factor
	var actual_damage: int = 0
	var decay_rate: float = 0.0
	var effect: String = "none"

	if is_ready_to_catch:
		# === 待接球: 韧性系统生效 ===
		# 1. 韧性伤害衰减百分比
		decay_rate = _get_resilience_decay_rate(resilience)
		var reduced_attack: float = amount * (1.0 - decay_rate)
		actual_damage = int(max(0, reduced_attack - defense_resist))

		# 2. 扣血（取整）
		stamina = int(max(0, stamina + defense_resist - reduced_attack))

		# 3. 僵直时间（与韧性反比，四段）
		var base_stagger: float = _get_stagger_by_resilience(resilience)

		# 4. 韧性效果判定（与衰减同时发生，三选一）
		effect = _roll_resilience_effect(resilience)
		if effect == "knockback1":
			_apply_knockback(attacker, 100.0)
			_stagger_timer = max(base_stagger, _knockback_timer)
		elif effect == "knockback2":
			_apply_knockback(attacker, 200.0)
			_stagger_timer = max(base_stagger, _knockback_timer)
		elif effect == "ball_fly" or effect == "knockback_and_fly":
			if effect == "knockback_and_fly":
				_apply_knockback(attacker, 100.0)
				_stagger_timer = max(base_stagger, _knockback_timer)
			else:
				_stagger_timer = max(base_stagger, 0.5)  # 弹飞球飞行约0.5s
		else:
			_stagger_timer = base_stagger
	else:
		# === 非待接球: 新体力 = 当前体力 + 防御抗力 - 攻击 ===
		actual_damage = int(max(0, amount - defense_resist))
		stamina = int(max(0, stamina + defense_resist - amount))
		# 非待接球无韧性保护，但僵直仍按韧性查表
		_stagger_timer = _get_stagger_by_resilience(resilience)

	# 体力条由下方球员栏更新，此处不处理

	# 检查是否被击败
	if stamina <= 0 and not is_defeated:
		_on_defeated()

	var pname: String = char_data["name"] if char_data.has("name") else "?"
	if decay_rate > 0.0:
		print("[Player] %s 待接球受伤 %d(衰减%.0f%% 防御抗力%.1f) 效果=%s 剩余体力%d" % [pname, actual_damage, decay_rate * 100.0, defense_resist, effect, stamina])
	else:
		print("[Player] %s 非接球受伤 %d(防御抗力%.1f) 剩余体力%d" % [pname, actual_damage, defense_resist, stamina])

	return {"damage": actual_damage, "effect": effect}


func _get_resilience_decay_rate(rd: float) -> float:
	"""韧性伤害衰减百分比（查表）"""
	if rd >= 90.0:
		return 0.5 * rd / 100.0
	elif rd >= 80.0:
		return 0.4 * rd / 100.0
	elif rd >= 60.0:
		return 0.3 * rd / 100.0
	elif rd >= 40.0:
		return 0.2 * rd / 100.0
	elif rd >= 30.0:
		return 0.1 * rd / 100.0
	else:
		return 0.0


func _get_stagger_by_resilience(rd: float) -> float:
	"""僵直时间与韧性反比（四段，最小0.3s）
	韧性 0-25 → 0.7s
	韧性 26-50 → 0.5s
	韧性 51-75 → 0.4s
	韧性 76-100 → 0.3s
	"""
	if rd >= 76.0:
		return 0.3
	elif rd >= 51.0:
		return 0.4
	elif rd >= 26.0:
		return 0.5
	else:
		return 0.7


func _roll_resilience_effect(rd: float) -> String:
	"""韧性效果判定（三选一 + 击退分段）"""
	# 查效果概率表
	var p_knockback_and_fly: float
	var p_ball_fly: float
	var p_knockback: float

	if rd < 30.0:
		p_knockback_and_fly = 0.3
		p_ball_fly = 0.45
		p_knockback = 0.25
	elif rd < 70.0:
		p_knockback_and_fly = 0.2
		p_ball_fly = 0.4
		p_knockback = 0.4
	else:
		p_knockback_and_fly = 0.1
		p_ball_fly = 0.4
		p_knockback = 0.5

	var roll: float = randf()

	if roll < p_knockback_and_fly:
		return "knockback_and_fly"
	elif roll < p_knockback_and_fly + p_ball_fly:
		return "ball_fly"
	else:
		# 击退：再分一段/二段
		var p_phase2: float = _get_phase2_knockback_chance()
		if randf() < p_phase2:
			return "knockback2"
		else:
			return "knockback1"


func _get_phase2_knockback_chance() -> float:
	"""二段击退概率 = 体力因子 × 剩余元灵能量因子"""
	# 体力因子
	var stamina_ratio: float = (stamina / max_stamina) * 100.0
	var stamina_factor: float
	if stamina_ratio < 30.0:
		stamina_factor = 0.6
	elif stamina_ratio < 60.0:
		stamina_factor = 0.3
	else:
		stamina_factor = 0.1

	# 元灵能量因子
	var energy_ratio: float = (spirit_energy / max_spirit_energy) * 100.0 if max_spirit_energy > 0.0 else 0.0
	var energy_factor: float
	if energy_ratio < 30.0:
		energy_factor = 0.5
	elif energy_ratio < 60.0:
		energy_factor = 0.3
	else:
		energy_factor = 0.2

	return stamina_factor * energy_factor


func _apply_knockback(attacker: CharacterBody2D, distance: float = 100.0) -> void:
	"""被击退"""
	if attacker == null:
		return
	var knockback_dir := (global_position - attacker.global_position).normalized()
	var knockback_speed: float = distance * 3.0  # 一段=300,二段=600
	velocity = knockback_dir * knockback_speed
	_knockback_timer = 0.25  # 击退持续0.25秒
	print("[Player] %s 被击退%.0fpx 速度=%.0f" % [char_data.get("name", "?"), distance, knockback_speed])


func _on_defeated() -> void:
	"""被击败:全属性减半,对手得分,发出信号"""
	is_defeated = true

	# 移除与球的碰撞(layer 1)，球不再击中被击败球员
	collision_layer = 0
	collision_mask = 0

	# 属性减半
	attack_power *= 0.5
	defense *= 0.5
	speed *= 0.5
	max_spirit_energy *= 0.5
	spirit_energy = min(spirit_energy, max_spirit_energy)

	# 视觉变化
	if avatar_bg:
		avatar_bg.color = avatar_bg.color.darkened(0.5)
	if avatar_label:
		avatar_label.add_theme_color_override("font_color", Color.GRAY)

	# 发出被击败信号(通知 battle_manager 移动到外场)
	defeated.emit(self)

	# 对手得分
	var scoring_team := "b" if team == "a" else "a"
	GameManager.add_score(scoring_team)

	print("[Player] %s 被击败! 属性减半" % (char_data["name"] if char_data.has("name") else ""))


func set_penalized(penalized: bool) -> void:
	"""设置惩罚状态(更新碰撞层)"""
	is_penalized = penalized
	var pname: String = char_data["name"] if char_data and char_data.has("name") else "?"
	if penalized:
		# 恢复球员间碰撞 + 与隔离墙碰撞
		collision_layer = 1  # layer 1 (球员)
		collision_mask = 1 | (1 << 4)  # layer 1(球员互碰) + layer 5(隔离墙)
		print("[Player] %s (队%s) 被隔离 pos=%.0f,%.0f layer=%d mask=%d" % [pname, team, global_position.x, global_position.y, collision_layer, collision_mask])
	else:
		# 正常时,恢复标准碰撞
		collision_layer = 1
		collision_mask = 1  # layer 1 only
		print("[Player] %s (队%s) 解除隔离" % [pname, team])


func enter_catch_state() -> void:
	"""进入待接球状态"""
	is_ready_to_catch = true
	state_indicator.color = Color.YELLOW


func exit_catch_state() -> void:
	"""退出待接球状态"""
	is_ready_to_catch = false
	state_indicator.color = Color.TRANSPARENT


func set_carrying_ball(carrying: bool) -> void:
	is_carrying_ball = carrying
	if carrying:
		state_indicator.color = Color.GREEN
	elif not is_ready_to_catch:
		state_indicator.color = Color.TRANSPARENT


func can_be_scored_against() -> bool:
	"""是否还能被得分(被击败后不能)"""
	return not is_defeated


func use_skill(slot_index: int) -> void:
	"""使用技能"""
	if slot_index >= equipped_skills.size():
		return
	var skill_id: String = str(equipped_skills[slot_index])
	var skill_data: Dictionary = DataManager.get_skill_by_id(skill_id)
	if skill_data.is_empty():
		return

	# 检查解锁
	if not (skill_data.get("unlocked") if skill_data.has("unlocked") else false):
		print("[Player] 技能未解锁: %s" % (skill_data.get("name") if skill_data.has("name") else ""))
		return

	# 检查CD
	var current_cd: float = skill_cooldowns[skill_id] if skill_cooldowns.has(skill_id) else 0.0
	if current_cd > 0:
		print("[Player] 技能冷却中: %s" % (skill_data.get("name") if skill_data.has("name") else ""))
		return

	# 检查能量
	var cost: float = float(skill_data["energy_cost"] if skill_data.has("energy_cost") else 0)
	if spirit_energy < cost:
		print("[Player] 能量不足: %s (需要%.1f, 当前%.1f)" % [(skill_data.get("name") if skill_data.has("name") else ""), cost, spirit_energy])
		return

	# 消耗能量
	spirit_energy -= cost
	# 能量条由下方球员栏更新，此处不处理

	# 设置CD
	skill_cooldowns[skill_id] = float(skill_data["cooldown"] if skill_data.has("cooldown") else 5.0)

	print("[Player] %s 使用技能: %s" % [char_data["name"] if char_data.has("name") else "", skill_data.get("name") if skill_data.has("name") else ""])

	# 技能效果由SkillSystem处理
	skill_used.emit(skill_id, skill_data)


signal skill_used(skill_id: String, skill_data: Dictionary)
signal facing_direction_changed()
signal message_bubble_requested(text: String, duration: float)


func start_sprint() -> bool:
	"""尝试开始冲刺，返回是否成功"""
	if is_sprinting or sprint_cooldown > 0.0 or is_carrying_ball:
		return false
	is_sprinting = true
	sprint_timer = SPRINT_DURATION
	return true


func show_message_bubble(text: String, duration: float = 0.5) -> void:
	"""在球员头顶显示消息气泡"""
	message_bubble_requested.emit(text, duration)
