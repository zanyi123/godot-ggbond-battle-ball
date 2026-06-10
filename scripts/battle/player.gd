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
var _knockback_timer: float = 0.0  # 击退剩余时间
var _knockback_duration: float = 0.0  # 击退总持续时间
var _knockback_start_velocity: float = 0.0  # 击退初始速度
var knockback_dir: Vector2 = Vector2.ZERO  # 击退方向
var _stagger_timer: float = 0.0  # 僵直持续时间（被击中后无法移动）

# 状态灯（第2步：控制状态系统）
var _status_lights: Dictionary = {}  # { "stunned": { "remaining": 2.0, ... }, ... }

# 闹钟纸条（第3步：持续效果系统）
var _tick_effects: Dictionary = {}  # { "hp_regen": { "type": "regen", "rate": 5.0, "remaining": 5.0 }, ... }

# 折扣卡（第4步：技能倍率系统）
var _skill_cost_mults: Dictionary = {}   # { "cost_1": { "mult": 0.5, "remaining": 5.0 } }
var _skill_cd_mults: Dictionary = {}     # { "cd_1": { "mult": 0.5, "remaining": 5.0 } }
var _next_skill_mults: Array = []        # [2.0, 1.5] 效果倍率卡列表，第一个全效，后续1/10
var _skill_bonus_uses: Dictionary = {}   # { skill_id: bonus_count }

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

	# 加载元灵偏好 → 获取元灵技能
	var spirit_pref: String = str(char_data.get("spirit_preference", ""))
	if spirit_pref != "":
		load_spirit_by_element(spirit_pref)

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

	# 击退中：匀减速到0（不处理输入）
	if _knockback_timer > 0.0:
		_knockback_timer -= delta
		_tick_status_lights(delta)
		_process_tick_effects(delta)
		_process_discount_cards(delta)

		# 匀减速：速度线性衰减到0
		if _knockback_duration > 0.0:
			var progress: float = 1.0 - (_knockback_timer / _knockback_duration)
			var current_speed: float = _knockback_start_velocity * (1.0 - progress)
			velocity = knockback_dir * current_speed
		else:
			velocity = Vector2.ZERO
		
		move_and_slide()
		
		# 击退结束
		if _knockback_timer <= 0.0:
			_knockback_timer = 0.0
			velocity = Vector2.ZERO
			knockback_dir = Vector2.ZERO
		return

	# 僵直/眩晕/定身：无法移动（站着不动）
	if _stagger_timer > 0.0 or is_status_active("stunned") or is_status_active("rooted"):
		if _stagger_timer > 0.0:
			_stagger_timer -= delta
			if _stagger_timer <= 0.0:
				_stagger_timer = 0.0
		_tick_status_lights(delta)
		_process_tick_effects(delta)
		_process_discount_cards(delta)
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
	_tick_status_lights(delta)
	_process_tick_effects(delta)
	_process_discount_cards(delta)


func take_damage(amount: float, attacker: CharacterBody2D = null) -> Dictionary:
	"""受到伤害,返回 {damage: int, effect: String}
	effect: "none" / "knockback1" / "knockback2" / "ball_fly" / "knockback_and_fly"

	非待接球: 新体力 = 当前体力 + 防御抗力 - 攻击（无韧性）
	待接球:   新体力 = 当前体力 + 防御抗力 - 攻击×(1-衰减率)（韧性生效+效果判定）
	"""
	if is_defeated:
		return {"damage": 0, "effect": "none"}

	# 无敌检查：灯亮则不受伤
	if is_status_active("invincible"):
		return {"damage": 0, "effect": "none"}

	# 易伤倍率
	var dmg_mult: float = 1.0
	if is_status_active("vulnerable"):
		dmg_mult = _status_lights["vulnerable"].get("multiplier", 1.5)
	var effective_amount: float = amount * dmg_mult

	var defense_resist: float = defense * defense_factor
	var actual_damage: int = 0
	var decay_rate: float = 0.0
	var effect: String = "none"

	if is_ready_to_catch:
		# === 待接球: 韧性系统生效 ===
		# 1. 韧性伤害衰减百分比
		decay_rate = _get_resilience_decay_rate(resilience)
		var reduced_attack: float = effective_amount * (1.0 - decay_rate)
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


## 获取场地摩擦系数
func _get_field_friction() -> float:
	"""获取当前场地摩擦系数 μ
	
	从场地物理管理器读取摩擦系数，用于击退距离计算
	
	查找顺序：
	1. 尝试绝对路径 /root/BattleManager
	2. 尝试绝对路径 /root/BattleArena
	3. 尝试场景树查找
	"""
	# 方法1：尝试绝对路径 /root/BattleManager
	var battle_manager = get_node_or_null("/root/BattleManager")
	if not battle_manager:
		# 方法2：尝试绝对路径 /root/BattleArena
		battle_manager = get_node_or_null("/root/BattleArena")
	
	if not battle_manager:
		# 方法3：场景树查找（向上遍历）
		var parent = get_parent()
		while parent:
			if parent.has_method("has_method") and parent.has_method("get_node"):
				if parent.get_node_or_null("FieldPhysicsManager"):
					battle_manager = parent
					break
			parent = parent.get_parent()
	
	if battle_manager:
		var field_physics = battle_manager.get_node_or_null("FieldPhysicsManager")
		if field_physics and field_physics.has_method("get_friction"):
			return field_physics.get_friction()
		else:
			print("[Player] 警告：找到 BattleManager 但找不到 FieldPhysicsManager")
	else:
		print("[Player] 警告：找不到 BattleManager/BattleArena")
	
	return 1.0  # 默认标准地面


## 击退系统（物理化）
func _apply_knockback(attacker: CharacterBody2D, distance: float = 100.0) -> void:
	"""被击退（物理化版本）
	
	参数：
	- attacker: 攻击者
	- distance: 基准距离（100=一段, 200=二段）
	
	物理逻辑：
	1. 读取场地摩擦系数 μ
	2. 根据 μ 和基准距离计算实际击退距离：d = distance / μ
	3. 根据距离和僵直时间计算初始速度：v = 2 × d / t
	4. 匀减速动画：速度线性衰减到0
	"""
	if attacker == null:
		return
	
	# 1. 确定击退类型
	var knockback_type: String = "knockback1" if distance <= 150.0 else "knockback2"
	
	# 2. 获取僵直时间（已由韧性系统计算，从 _stagger_timer 获取）
	var stagger_duration: float = _get_stagger_by_resilience(resilience)
	
	# 3. 读取场地摩擦系数
	var mu: float = _get_field_friction()
	
	# 4. 物理计算（使用 KnockbackPhysics 模块）
	var result: Dictionary = KnockbackPhysics.calculate_knockback(
		knockback_type,   # 击退类型
		mu,              # 摩擦系数
		stagger_duration, # 僵直时间
		1.0,             # 技能倍率（默认1.0）
		0.0,             # 技能固定加成
		400.0,           # 球速
		false            # 不启用球速加成
	)
	
	# 5. 应用击退
	knockback_dir = (global_position - attacker.global_position).normalized()
	velocity = knockback_dir * result.initial_velocity
	
	# 6. 设置击退计时器（用于匀减速动画）
	_knockback_timer = result.duration
	_knockback_duration = result.duration
	_knockback_start_velocity = result.initial_velocity
	
	var pname: String = char_data.get("name", "?")
	print("[Player] %s 击退! μ=%.2f 僵直%.2fs 距离%.0fpx 初速%.0f" % [
		pname, mu, result.duration, result.distance, result.initial_velocity
	])


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
		# 持球时显示已激活技能的光环
		_update_ball_skill_aura()
	elif not is_ready_to_catch:
		state_indicator.color = Color.TRANSPARENT
		# 不持球时清除光环
		_clear_ball_skill_aura()


func can_be_scored_against() -> bool:
	"""是否还能被得分(被击败后不能)"""
	return not is_defeated


func use_skill(slot_index: int) -> void:
	"""使用技能"""
	if slot_index >= equipped_skills.size():
		return

	# 沉默检查：灯亮则不能技能
	if is_status_active("silenced"):
		return

	var skill_id: String = str(equipped_skills[slot_index])
	var skill_data: Dictionary = DataManager.get_skill_by_id(skill_id)
	if skill_data.is_empty():
		return

	# 检查解锁（没有 unlocked 字段默认为已解锁）
	if skill_data.has("unlocked") and not skill_data["unlocked"]:
		print("[Player] 技能未解锁: %s" % (skill_data.get("name", "")))
		return

	# 检查CD
	var current_cd: float = skill_cooldowns[skill_id] if skill_cooldowns.has(skill_id) else 0.0
	if current_cd > 0:
		print("[Player] 技能冷却中: %s" % (skill_data.get("name") if skill_data.has("name") else ""))
		return

	# 检查能量（应用消耗折扣卡）
	var cost: float = float(skill_data["energy_cost"] if skill_data.has("energy_cost") else 0) * get_skill_cost_mult()
	if spirit_energy < cost:
		print("[Player] 能量不足: %s (需要%.1f, 当前%.1f)" % [(skill_data.get("name") if skill_data.has("name") else ""), cost, spirit_energy])
		return

	# 消耗能量
	spirit_energy -= cost
	# 能量条由下方球员栏更新，此处不处理

	# 设置CD（应用CD折扣卡）
	skill_cooldowns[skill_id] = float(skill_data["cooldown"] if skill_data.has("cooldown") else 5.0) * get_skill_cd_mult()

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


## ==================== 技能光环系统（球）====================

var _active_skill_id: String = ""


func set_active_skill(skill_id: String) -> void:
	"""设置当前激活的技能（外部调用）"""
	_active_skill_id = skill_id
	if is_carrying_ball:
		_update_ball_skill_aura()


func clear_active_skill() -> void:
	"""清除当前激活的技能（外部调用）"""
	_active_skill_id = ""
	_clear_ball_skill_aura()


func get_active_skill_id() -> String:
	"""获取当前激活的技能ID"""
	return _active_skill_id


func _update_ball_skill_aura() -> void:
	"""更新球的技能光环显示"""
	if _active_skill_id.is_empty() or not is_carrying_ball:
		return

	var ball_node = _get_ball_node()
	if ball_node and ball_node.has_method("set_active_skill"):
		var skill_data = DataManager.get_skill_by_id(_active_skill_id)
		if not skill_data.is_empty():
			ball_node.set_active_skill(skill_data)
			print("[Player] 显示球技能光环: %s" % _active_skill_id)


func _clear_ball_skill_aura() -> void:
	"""清除球的技能光环"""
	var ball_node = _get_ball_node()
	if ball_node and ball_node.has_method("cancel_active_skill"):
		ball_node.cancel_active_skill()


func _get_ball_node() -> Node:
	"""获取球节点"""
	var tree = get_tree()
	if tree:
		var ball_nodes = tree.get_nodes_in_group("ball")
		if not ball_nodes.is_empty():
			return ball_nodes[0]
	return null


## 通过技能ID使用技能（供外部调用）
func use_skill_by_id(skill_id: String) -> void:
	"""通过技能ID使用技能"""
	for i in range(equipped_skills.size()):
		if str(equipped_skills[i]) == skill_id:
			use_skill(i)
			return
	print("[Player] 未找到技能ID: %s" % skill_id)


## 获取装备的技能ID列表
func get_equipped_skills() -> Array[String]:
	"""返回装备的技能ID列表"""
	var result: Array[String] = []
	for skill_id in equipped_skills:
		result.append(str(skill_id))
	return result


func load_spirit_by_element(element: String) -> void:
	"""根据元素类型加载元灵及其技能"""
	if not DataManager:
		return
	var spirit_data: Dictionary = {}
	if DataManager.has_method("get_spirit_by_element"):
		spirit_data = DataManager.get_spirit_by_element(element)
	if spirit_data.is_empty():
		# 备用：遍历所有元灵
		for s in DataManager.spirits:
			if str(s.get("element", "")) == element:
				spirit_data = s
				break
	if not spirit_data.is_empty():
		equip_spirit(spirit_data)


func equip_spirit(spirit_data: Dictionary) -> void:
	"""装备元灵，加载其技能到 equipped_skills"""
	spirit_id = str(spirit_data.get("id", ""))
	equipped_skills.clear()
	var skill_ids = spirit_data.get("skills", [])
	for sid in skill_ids:
		equipped_skills.append(sid)
	# 初始化技能冷却
	skill_cooldowns.clear()
	for sid in equipped_skills:
		skill_cooldowns[str(sid)] = 0.0
	print("[Player] %s 装备元灵: %s 技能=%s" % [char_data.get("name", "?"), spirit_data.get("name", "?"), str(skill_ids)])


## ==================== 状态灯系统（第2步：控制状态）====================

# 控制类状态名列表（受免控灯保护）
const _CC_STATUSES: PackedStringArray = ["stunned", "silenced", "disarmed", "rooted"]


func is_status_active(status_name: String) -> bool:
	"""灯亮没亮？"""
	return _status_lights.has(status_name) and _status_lights[status_name].get("on", false)


func turn_on_light(status_name: String, duration: float, extra: Dictionary = {}) -> bool:
	"""点灯（返回true=成功，false=被免控拦截）
	控制类状态（眩晕/沉默/缴械/定身）会被免控灯拦截
	同一盏灯重复点会刷新时间"""
	# 控制类状态，先检查免控灯
	if status_name in _CC_STATUSES:
		if is_status_active("cc_immune"):
			return false
	_status_lights[status_name] = {
		"on": true,
		"remaining": duration,
	}
	# 附加额外数据（如易伤倍率）
	for key in extra:
		_status_lights[status_name][key] = extra[key]
	return true


func turn_off_light(status_name: String) -> void:
	"""关灯（手动，如解控）"""
	_status_lights.erase(status_name)


func turn_off_lights_by_type(light_names: PackedStringArray) -> void:
	"""关掉指定类型的所有灯"""
	for name in light_names:
		_status_lights.erase(name)


func _tick_status_lights(delta: float) -> void:
	"""每帧倒计时，到期自动关灯"""
	var to_remove: PackedStringArray = []
	for status in _status_lights:
		var remaining: float = _status_lights[status].get("remaining", 0.0) - delta
		if remaining <= 0.0:
			to_remove.append(status)
		else:
			_status_lights[status]["remaining"] = remaining
	for status in to_remove:
		_status_lights.erase(status)


## ==================== 闹钟纸条系统（第3步：持续效果）====================


func add_tick_effect(id: String, type: String, rate: float, duration: float) -> void:
	"""添加一个持续效果（闹钟纸条）
	type: "regen"（持续恢复）或 "dot"（持续掉血）
	rate: 每秒的量
	duration: 持续时间（秒）
	同id重复添加会覆盖"""
	_tick_effects[id] = {
		"type": type,
		"rate": rate,
		"remaining": duration,
	}


func remove_tick_effect(id: String) -> bool:
	"""手动撕掉一张纸条"""
	return _tick_effects.erase(id)


func has_tick_effect(id: String) -> bool:
	"""纸条还在不在？"""
	return _tick_effects.has(id)


func get_total_tick_rate(type: String) -> float:
	"""某个类型的总速率（如所有regen加起来每秒回多少）"""
	var total: float = 0.0
	for id in _tick_effects:
		if _tick_effects[id].get("type", "") == type:
			total += _tick_effects[id].get("rate", 0.0)
	return total


func _process_tick_effects(delta: float) -> void:
	"""每帧执行：运行闹钟纸条 + 倒计时 + 撕掉到期的"""
	var to_remove: PackedStringArray = []
	for id in _tick_effects:
		var effect: Dictionary = _tick_effects[id]
		var etype: String = effect.get("type", "")
		var rate: float = effect.get("rate", 0.0)

		# 每帧执行
		if etype == "regen":
			stamina = minf(max_stamina, stamina + rate * delta)
		elif etype == "dot":
			# 无敌灯亮时，不掉血（但倒计时照跑）
			if not is_status_active("invincible"):
				stamina = maxf(0.0, stamina - rate * delta)
				if stamina <= 0.0 and not is_defeated:
					_on_defeated()

		# 倒计时
		effect["remaining"] = effect.get("remaining", 0.0) - delta
		if effect.get("remaining", 0.0) <= 0.0:
			to_remove.append(id)

	for id in to_remove:
		_tick_effects.erase(id)


## ==================== 折扣卡系统（第4步：技能倍率）====================


func add_skill_cost_mult(id: String, mult: float, duration: float) -> void:
	"""添加消耗折扣卡，同id覆盖"""
	_skill_cost_mults[id] = { "mult": mult, "remaining": duration }


func get_skill_cost_mult() -> float:
	"""消耗倍率 = 所有卡连乘"""
	var m: float = 1.0
	for id in _skill_cost_mults:
		m *= _skill_cost_mults[id].get("mult", 1.0)
	return m


func add_skill_cd_mult(id: String, mult: float, duration: float) -> void:
	"""添加CD折扣卡，同id覆盖"""
	_skill_cd_mults[id] = { "mult": mult, "remaining": duration }


func get_skill_cd_mult() -> float:
	"""CD倍率 = 所有卡连乘"""
	var m: float = 1.0
	for id in _skill_cd_mults:
		m *= _skill_cd_mults[id].get("mult", 1.0)
	return m


func add_next_skill_mult(mult: float) -> void:
	"""添加效果倍率卡（一次性，技能使用时消费）"""
	_next_skill_mults.append(mult)


func get_and_consume_next_skill_mult() -> float:
	"""读取并消费效果倍率
	第1张卡全效，后续每张只取1/10
	无卡返回1.0"""
	if _next_skill_mults.is_empty():
		return 1.0
	var total: float = 0.0
	for i in range(_next_skill_mults.size()):
		var m: float = _next_skill_mults[i]
		if i == 0:
			total = m
		else:
			total += m * 0.1
	_next_skill_mults.clear()
	return total


func remove_skill_cost_mult(id: String) -> bool:
	return _skill_cost_mults.erase(id)


func remove_skill_cd_mult(id: String) -> bool:
	return _skill_cd_mults.erase(id)


func add_skill_bonus_uses(skill_id: String, bonus: int) -> void:
	"""增加技能使用次数"""
	if not _skill_bonus_uses.has(skill_id):
		_skill_bonus_uses[skill_id] = 0
	_skill_bonus_uses[skill_id] += bonus


func get_skill_bonus_uses(skill_id: String) -> int:
	return _skill_bonus_uses.get(skill_id, 0)


func _process_discount_cards(delta: float) -> void:
	"""每帧倒计时折扣卡，到期收回"""
	_tick_mult_dict(_skill_cost_mults, delta)
	_tick_mult_dict(_skill_cd_mults, delta)


func _tick_mult_dict(d: Dictionary, delta: float) -> void:
	var to_remove: PackedStringArray = []
	for id in d:
		d[id]["remaining"] = d[id].get("remaining", 0.0) - delta
		if d[id].get("remaining", 0.0) <= 0.0:
			to_remove.append(id)
	for id in to_remove:
		d.erase(id)
