class_name AIProfile
## AI球员参数模板 - 数据驱动的行为配置
## 每个AI球员持有此配置，引擎根据参数产生不同行为
## 不内置任何行为偏好，所有"个性"来自外部填入的参数

var profile_name: String = ""

# ──── 角色定位 ────
var role: String = "attacker"
# "attacker"（主攻手）/ "defender"（防御者）/ "supporter"（支援者）

# ──── 决策因子：持球时各选项的评分加权（分数）────
var weight_pass: float = 0.0
var weight_shoot: float = 0.0
var weight_dribble: float = 0.0

# ──── 持球节奏 ────
var hold_duration_min: float = 0.3
var hold_duration_max: float = 0.8
var max_carry_time: float = 4.0

# ──── 反应速度 ────
var think_interval: float = 0.2
var reaction_delay: float = 0.0

# ──── 移动参数（乘数，register时根据角色speed计算实际值）────
var speed_chase_mult: float = 1.0    # 追球速度乘数
var speed_dribble_mult: float = 0.75 # 带球速度乘数
var speed_move_mult: float = 0.85   # 跑位速度乘数

# 实际速度（由 ai_manager.register_player 根据 player.speed * 乘数 填入）
var speed_chase: float = 200.0
var speed_dribble: float = 150.0
var speed_move: float = 170.0

# ──── 范围 ────
var aggro_range: float = 400.0
var pass_range: float = 320.0
var shoot_dist: float = 100.0
var arrive_threshold: float = 15.0

# ──── 视野感知参数 ────
var field_of_view: float = 180.0       # 视野角度（度）
var vision_range: float = 350.0        # 视野最大距离
var awareness_accuracy: float = 0.85   # 感知精度 0~1
var memory_duration: float = 1.5       # 记忆保持时间（秒）
var awareness_update_interval: float = 0.3  # 感知刷新间隔（秒）

# ──── 战术/阵型参数 ────
var formation_offset: Vector2 = Vector2.ZERO
var ball_attract_weight: float = 0.25
var spread_force: float = 0.5
var team_strategy_name: String = "balanced"  # 团队策略名称（阵型选择用）

# ──── 传球偏好 ────
var prefer_forward_pass: bool = true
var prefer_distance_min: float = 100.0
var prefer_distance_max: float = 250.0

# ──── 失误/随机 ────
var random_factor: float = 8.0
var pass_angle_error: float = 0.0
var shoot_angle_error: float = 0.0

# ──── 弱点（仅对手使用）────
var weakness: String = ""
var weakness_scale: float = 0.0
# 弱点行为标记（引擎读取，控制特殊行为）
var weakness_ignore_flank: bool = false     # ball_focused: 忽略侧面敌人
var weakness_overextend: bool = false       # over_chase: 追球过度前压
var weakness_stuck_on_target: bool = false  # predictable_target: 死盯一个目标

# ──── 朝向更新策略 ────
var facing_mode_chase: String = "ball"
var facing_mode_dribble: String = "goal"
var facing_mode_support: String = "ball"
var facing_mode_defend: String = "enemy"


## 返回角色预设配置
static func get_role_preset(role_name: String) -> AIProfile:
	var p := AIProfile.new()
	p.role = role_name
	p.profile_name = "preset_%s" % role_name

	match role_name:
		"attacker":
			p.weight_pass = -20.0       # 不爱传球
			p.weight_shoot = 35.0       # 强烈倾向投球
			p.weight_dribble = 20.0     # 带球意愿高
			p.hold_duration_min = 0.15  # 果断出手
			p.hold_duration_max = 0.35
			p.think_interval = 0.15     # 决策快
			p.reaction_delay = 0.0
			p.speed_chase_mult = 1.1    # 追球全力
			p.speed_dribble_mult = 0.85  # 带球较快
			p.speed_move_mult = 0.95   # 跑位快
			p.aggro_range = 500.0       # 攻击范围大
			p.pass_range = 280.0        # 传球范围短（不爱传）
			p.ball_attract_weight = 0.45 # 强烈被球吸引
			p.spread_force = 0.2        # 不太散开（向前冲）
			p.prefer_forward_pass = true
			p.prefer_distance_min = 100.0
			p.prefer_distance_max = 250.0
			p.random_factor = 12.0      # 较冲动
			p.pass_angle_error = 8.0    # 传球不太准
			p.shoot_angle_error = 3.0   # 投球较准
			p.field_of_view = 160.0     # 窄视野（专注前方）
			p.vision_range = 300.0      # 看不远
			p.awareness_accuracy = 0.75 # 感知粗糙
			p.memory_duration = 1.0     # 记忆短
			p.awareness_update_interval = 0.35
			p.facing_mode_chase = "ball"
			p.facing_mode_dribble = "goal"
			p.facing_mode_support = "move"  # 跑位时看移动方向
			p.facing_mode_defend = "enemy"

		"defender":
			p.weight_pass = 30.0        # 爱传球（安全）
			p.weight_shoot = -15.0      # 不爱投球
			p.weight_dribble = -25.0    # 不爱带球
			p.hold_duration_min = 0.5   # 犹豫久
			p.hold_duration_max = 1.2
			p.think_interval = 0.3      # 决策慢
			p.reaction_delay = 0.08
			p.speed_chase_mult = 0.9    # 追球不急
			p.speed_dribble_mult = 0.7   # 带球慢
			p.speed_move_mult = 0.8    # 跑位稳
			p.aggro_range = 300.0       # 攻击范围小
			p.pass_range = 360.0        # 传球范围大（爱传远）
			p.ball_attract_weight = 0.1  # 不被球吸引（守位）
			p.spread_force = 0.7        # 强散开（保持阵型）
			p.prefer_forward_pass = false
			p.prefer_distance_min = 80.0
			p.prefer_distance_max = 300.0
			p.random_factor = 4.0       # 稳定少失误
			p.pass_angle_error = 2.0    # 传球准
			p.shoot_angle_error = 10.0  # 投球差
			p.field_of_view = 200.0     # 宽视野（警惕四周）
			p.vision_range = 400.0      # 看得远
			p.awareness_accuracy = 0.92 # 感知精准
			p.memory_duration = 2.5     # 记忆长
			p.awareness_update_interval = 0.2
			p.facing_mode_chase = "ball"
			p.facing_mode_dribble = "move"   # 带球看移动方向
			p.facing_mode_support = "ball"    # 跑位时盯球
			p.facing_mode_defend = "enemy"

		"supporter":
			p.weight_pass = 40.0        # 最爱传球
			p.weight_shoot = -5.0       # 不太投球
			p.weight_dribble = 5.0      # 略微带球
			p.hold_duration_min = 0.25  # 中等节奏
			p.hold_duration_max = 0.6
			p.think_interval = 0.18     # 决策较快
			p.reaction_delay = 0.0
			p.speed_chase_mult = 1.0    # 追球中等
			p.speed_dribble_mult = 0.78  # 带球中等
			p.speed_move_mult = 0.95   # 跑位最快（满场飞）
			p.aggro_range = 420.0       # 中等范围
			p.pass_range = 380.0        # 传球范围最大
			p.ball_attract_weight = 0.3  # 中等吸引
			p.spread_force = 0.5        # 中等散开
			p.prefer_forward_pass = true
			p.prefer_distance_min = 120.0
			p.prefer_distance_max = 300.0
			p.random_factor = 8.0       # 中等随机
			p.pass_angle_error = 3.0    # 传球还行
			p.shoot_angle_error = 7.0   # 投球一般
			p.field_of_view = 180.0     # 标准视野
			p.vision_range = 360.0      # 看得较远
			p.awareness_accuracy = 0.88
			p.memory_duration = 2.0
			p.awareness_update_interval = 0.22
			p.facing_mode_chase = "ball"
			p.facing_mode_dribble = "ball"    # 带球盯球（随时准备传）
			p.facing_mode_support = "ball"    # 跑位盯球
			p.facing_mode_defend = "enemy"

		_:
			# 默认值（balanced）
			p.weight_pass = 0.0
			p.weight_shoot = 0.0
			p.weight_dribble = 0.0

	return p


## 叠加难度修正
static func apply_difficulty(profile: AIProfile, difficulty: String) -> void:
	match difficulty:
		"easy":
			profile.vision_range *= 0.7
			profile.awareness_accuracy = 0.6
			profile.memory_duration = 0.8
			profile.awareness_update_interval = 0.4
			profile.think_interval = 0.35
			profile.random_factor = 16.0
			profile.pass_angle_error += 10.0
			profile.shoot_angle_error += 8.0
			profile.speed_chase_mult *= 0.85
			profile.speed_dribble_mult *= 0.85
			profile.reaction_delay += 0.15
		"normal":
			pass  # 不修改
		"hard":
			profile.vision_range *= 1.15
			profile.awareness_accuracy = 0.95
			profile.memory_duration = 2.5
			profile.awareness_update_interval = 0.2
			profile.think_interval = 0.12
			profile.random_factor = 4.0
			profile.pass_angle_error *= 0.5
			profile.shoot_angle_error *= 0.5
			profile.speed_chase_mult *= 1.1
			profile.speed_dribble_mult *= 1.1
			profile.reaction_delay = 0.0


## 叠加弱点
static func apply_weakness(profile: AIProfile, weakness_type: String) -> void:
	profile.weakness = weakness_type
	profile.weakness_scale = randf_range(0.3, 1.0)
	match weakness_type:
		"slow_reaction":
			profile.think_interval *= 2.0     # 反应更慢
			profile.reaction_delay += 0.3
			profile.hold_duration_min *= 2.0
			profile.hold_duration_max *= 2.0
			profile.speed_chase_mult *= 0.8
			profile.speed_dribble_mult *= 0.8
		"ball_focused":
			profile.vision_range *= 0.5        # 视野极窄
			profile.awareness_accuracy *= 0.6
			profile.aggro_range *= 1.4         # 追球范围大
			profile.weakness_ignore_flank = true  # 引擎: 不躲避侧面
		"over_chase":
			profile.aggro_range *= 1.5         # 追球范围极大
			profile.spread_force *= 0.2        # 几乎不散开
			profile.ball_attract_weight = 0.7   # 疯狂追球
			profile.vision_range *= 0.8
			profile.weakness_overextend = true    # 引擎: 允许过半追球
		"predictable_target":
			profile.weakness_stuck_on_target = true  # 引擎: 70%概率打上次目标


## 叠加团队策略
static func apply_team_strategy(profile: AIProfile, strategy: String) -> void:
	profile.team_strategy_name = strategy
	match strategy:
		"offensive":
			profile.weight_shoot += 10.0
			profile.weight_dribble += 10.0
			profile.ball_attract_weight = minf(profile.ball_attract_weight + 0.1, 0.6)
			profile.hold_duration_min *= 0.8
			profile.hold_duration_max *= 0.8
		"defensive":
			profile.weight_pass += 10.0
			profile.weight_dribble -= 10.0
			profile.ball_attract_weight = maxf(profile.ball_attract_weight - 0.1, 0.05)
			profile.hold_duration_min *= 1.2
			profile.hold_duration_max *= 1.2
		"balanced":
			pass  # 不修改


## 获取阵型模板位置（相对于己方半场中心的偏移）
## 半场中心：队A≈(-190,0)，合法范围 x∈[-380,-10]
## 偏移应为小值，让阵型均匀分布在半场内
static func get_formation_positions(strategy: String) -> Dictionary:
	match strategy:
		"offensive":
			return {
				"attacker": Vector2(60, 0),       # 前锋靠中线
				"defender": Vector2(-60, -110),   # 后卫偏后偏上
				"supporter": Vector2(20, 100),    # 支援在中偏下
			}
		"defensive":
			return {
				"attacker": Vector2(20, 60),      # 前锋不冒进
				"defender": Vector2(-80, -80),    # 后卫缩后
				"supporter": Vector2(-60, 80),    # 支援缩后
			}
		"balanced", _:
			return {
				"attacker": Vector2(40, 0),       # 前锋稍前
				"defender": Vector2(-70, -100),   # 后卫偏后上
				"supporter": Vector2(-10, 90),    # 支援居中偏下
			}
