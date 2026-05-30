extends CharacterBody2D
## 球员节点 - 2D表示（带背景色的数字头像）
## 处理移动、接球、发球、状态管理

@export var character_id: String = ""
@export var team: String = "a"  # "a" 或 "b"
@export var is_player_controlled: bool = false

# 球员数据（从DataManager加载）
var char_data: Dictionary = {}

# 运行时属性
var stamina: float = 100.0
var max_stamina: float = 100.0
var defense: float = 0.0
var speed: float = 200.0
var attack_power: float = 0.0
var resilience: float = 50.0
var spirit_energy: float = 0.0
var max_spirit_energy: float = 100.0

# 状态
var is_defeated: bool = false
var is_carrying_ball: bool = false
var is_ready_to_catch: bool = false  # 待接球状态
var is_charging_throw: bool = false   # 预发球状态
var charge_start_pos: Vector2 = Vector2.ZERO
var assigned_role: int = 0  # GameManager.PlayerRole
var is_penalized: bool = false  # 是否被惩罚（在外场隔离中）

# 角色（主攻/防御/辅助）
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
var state_indicator: ColorRect  # 状态指示（待接球/预发球等）
var facing_direction: Vector2 = Vector2.RIGHT


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
	speed = char_data["speed"] if char_data.has("speed") else 200.0
	attack_power = char_data["attack"] if char_data.has("attack") else 50.0
	resilience = char_data["resilience"] if char_data.has("resilience") else 50.0
	talent_name = char_data["talent_name"] if char_data.has("talent_name") else ""
	talent_desc = char_data["talent_desc"] if char_data.has("talent_desc") else ""
	
	_setup_visuals()


func _setup_visuals() -> void:
	# 创建角色头像：带背景色的数字圆形
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
	
	# 数字标签（球员编号）
	avatar_label = Label.new()
	avatar_label.text = _get_display_number()
	avatar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	avatar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	avatar_label.position = Vector2(-28, -28)
	avatar_label.size = Vector2(56, 56)
	add_child(avatar_label)
	
	# 体力条
	stamina_bar = ProgressBar.new()
	stamina_bar.position = Vector2(-28, -44)
	stamina_bar.size = Vector2(56, 8)
	stamina_bar.max_value = max_stamina
	stamina_bar.value = stamina
	stamina_bar.show_percentage = false
	var style_green := StyleBoxFlat.new()
	style_green.bg_color = Color.GREEN
	stamina_bar.add_theme_stylebox_override("fill", style_green)
	add_child(stamina_bar)
	
	# 元灵能量条
	energy_bar = ProgressBar.new()
	energy_bar.position = Vector2(-28, -36)
	energy_bar.size = Vector2(56, 5)
	energy_bar.max_value = max_spirit_energy
	energy_bar.value = spirit_energy
	energy_bar.show_percentage = false
	var style_blue := StyleBoxFlat.new()
	style_blue.bg_color = Color.CYAN
	energy_bar.add_theme_stylebox_override("fill", style_blue)
	add_child(energy_bar)
	
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
	if not is_player_controlled:
		return  # AI控制由AI管理器处理
	
	# 移动
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.y = Input.get_axis("move_up", "move_down")
	
	if input_dir != Vector2.ZERO:
		# W键（上）：朝鼠标方向移动
		if input_dir.y < 0:
			velocity = facing_direction * speed
		else:
			velocity = input_dir.normalized() * speed
	else:
		velocity = Vector2.ZERO
	
	move_and_slide()


func take_damage(amount: float, attacker: CharacterBody2D = null) -> float:
	"""受到伤害，返回实际扣除的体力值"""
	if is_defeated:
		return 0.0
	
	var actual_damage := amount
	
	# 韧性判定（待接球状态）
	if is_ready_to_catch:
		var roll := randf() * 100.0
		var reduction_chance := resilience  # 韧性越高减伤概率越高
		if roll < reduction_chance:
			actual_damage *= (1.0 - resilience / 200.0)  # 减伤比例
			print("[Player] %s 韧性减伤! %.1f -> %.1f" % [char_data["name"] if char_data.has("name") else "", amount, actual_damage])
		else:
			# 低韧性效果：被击退
			_apply_knockback(attacker)
	else:
		# 非待接球状态：球反弹回攻击者
		pass
	
	stamina = max(0.0, stamina - actual_damage)
	stamina_bar.value = stamina
	
	# 检查是否被击败
	if stamina <= 0.0 and not is_defeated:
		_on_defeated()
	
	return actual_damage


func _apply_knockback(attacker: CharacterBody2D) -> void:
	"""被击退"""
	if attacker == null:
		return
	var knockback_dir := (global_position - attacker.global_position).normalized()
	var knockback_force := 300.0 * (1.0 - resilience / 100.0)
	velocity = knockback_dir * knockback_force


func _on_defeated() -> void:
	"""被击败：全属性减半，对手得分"""
	is_defeated = true
	
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
	
	# 对手得分
	var scoring_team := "b" if team == "a" else "a"
	GameManager.add_score(scoring_team)
	
	print("[Player] %s 被击败! 属性减半" % (char_data["name"] if char_data.has("name") else ""))


func set_penalized(penalized: bool) -> void:
	"""设置惩罚状态（更新碰撞层）"""
	is_penalized = penalized
	if penalized:
		# 被惩罚时，与隔离墙层碰撞
		collision_mask |= 1 << 4  # layer 5 = penalty_walls (1 << 4 = 16)
		print("[Player] %s 被隔离，无法离开外场" % (char_data["name"] if char_data.has("name") else ""))
	else:
		# 正常时，不与隔离墙层碰撞
		collision_mask &= ~(1 << 4)  # 清除 bit 4
		print("[Player] %s 解除隔离" % (char_data["name"] if char_data.has("name") else ""))


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
	"""是否还能被得分（被击败后不能）"""
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
	energy_bar.value = spirit_energy
	
	# 设置CD
	skill_cooldowns[skill_id] = float(skill_data["cooldown"] if skill_data.has("cooldown") else 5.0)
	
	print("[Player] %s 使用技能: %s" % [char_data["name"] if char_data.has("name") else "", skill_data.get("name") if skill_data.has("name") else ""])
	
	# 技能效果由SkillSystem处理
	skill_used.emit(skill_id, skill_data)


signal skill_used(skill_id: String, skill_data: Dictionary)
