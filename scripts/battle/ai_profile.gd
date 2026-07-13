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

# ──── 站位约束参数（2026-07-12 新增，解决乱走位/卡中线问题）────
var hold_range: float = 120.0              # 无球静止时最大活动半径（以阵型位为中心）
var hold_range_teammate_ball: float = 100.0  # 队友持球时最大活动半径
var hold_range_enemy_ball: float = 80.0    # 对手持球时最大活动半径（防守不乱跑）
var stationary_when_ball_idle: bool = true  # 球落地静止时保持站位（不乱追）
var formation_priority: float = 0.7        # 阵型优先级 0~1，越高越守阵型

# ──── 微动待机参数（2026-07-12 新增，解决无球时抽搐/往复运动）────
# 球不在飞行时，无球球员在阵型基准位附近做小幅偏移，到达后静止
var idle_drift_radius: float = 25.0        # 微动偏移半径（px），0=完全静止
var idle_drift_interval: float = 2.0       # 微动换位间隔（秒），到达后等这么久再换微动点
var idle_arrive_snap: float = 8.0          # 到达此距离内直接停下（防止微观抖动）

# ──── Steering 避障参数（P0，借鉴 GDQuest GSAI，结合决竞球内外场规则）────
# 内场分离力强度：决竞球内场有阵型约束（spread_force 已存在），分离力只做微调防撞
var separation_inner: float = 600.0
# 外场分离力强度：外场狭小（被罚下球员的隔离区），需强力排斥防卡死（>内场）
var separation_outer: float = 1400.0
# 队友感知半径（像素）：超出此距离的队友不施加分离力
var separation_radius: float = 80.0
# 带球碰撞预测时长（秒）：DRIBBLE 时预测前方此秒数内会撞到的敌人，提前绕行
var avoid_lookahead: float = 0.4

# ──── Hysteresis 防抖参数（P0，借鉴 InfluenceWalker 思路）────
# 决竞球角色容差不同：attacker 容忍小（果断切换）、defender 容忍大（稳定）
# 用法：新状态分数必须 >= 当前状态分数 + margin 才切换，消除 pass/shoot 抖动
var decision_hysteresis: float = 8.0
# 卡死换向的滞回：当前位置到新目标距离必须 > 此值，否则不切（避免 y 镜像抽搐）
var stuck_redecide_margin: float = 30.0

# ──── 效用权重（P1，situation 因子→行为分数，数值外置便于平衡调优）────
# 原 _utility_carrying / _utility_catch 里的魔法数字（50/60/30/40/20）提到这里
# 持球效用：pass/shoot 的 situation 因子权重
var util_pass_team_w: float = 50.0      # 队友状态→传球加分
var util_pass_enemy_w: float = -30.0    # 对手状态→传球减分（对手弱少传直接打）
var util_pass_skill_w: float = 40.0     # 技能就绪→传球配合
var util_shoot_enemy_w: float = 60.0    # 对手状态→投球加分（对手弱猛打）
var util_shoot_team_w: float = -20.0    # 队友状态→投球减分（队友强传给他们）
# 接球效用：_utility_catch 的 situation 因子权重
var util_catch_possession_w: float = 60.0  # 球权价值→接球加分（急需夺回→积极接）
var util_catch_stamina_w: float = 40.0     # 体力健康→接球加分
var util_catch_threat_w: float = -50.0     # 球威胁→接球减分（负值，危险球拒接）

# ──── Response Curve 曲线类型（P1，让因子过曲线更拟人，借鉴 Dave Mark Utility AI）────
# linear=线性 / logistic=S形（达阈值才急升）/ exp=凸（越高越极端，无饱和）/ inv_log=反S（高忽略低急升）
var curve_enemy_state: String = "logistic"  # 对手残血度：达阈值才猛攻（不匀速激进）
var curve_stamina: String = "exp"            # 体力健康：越好越想接（无饱和，体力满时极积极）
var curve_threat: String = "logistic"        # 球威胁：达阈值才躲（低威胁忽略）
var curve_k: float = 1.0                     # 曲线斜率（越大越陡，默认1.0）

# ──── 感知常识参数（2026-07-12 新增，解决感知不到队友/敌人导致不会传球的问题）────
var teammate_awareness_always: bool = true   # 始终知道队友存在（常识，不依赖视野）
var teammate_pos_accuracy: float = 0.6       # 队友位置感知精度（0~1，比视野低）
var enemy_awareness_close: float = 150.0     # 此距离内敌人必知（近距离感知）
var enemy_awareness_fallback: bool = true    # 感知不到时用全局最近敌人兜底（不瞎打）
var pass_min_teammate_score: float = 0.0     # 传球目标最低评分（低于则不传）

# ──── 个人策略名称（外场效用计算用，2026-06-15 新增）────
# "breakthrough"(突破进攻) / "defense"(防守反击) / "passing"(传球配合)
# 备战面板选择后存入，外场持球决策读此字段决定 PASS 还是 ATTACK
var player_strategy_name: String = "passing"

# 外场增益系数：外场球员个人策略权重放大倍数（外场独立性强）
var outer_personal_boost: float = 1.5

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

# ──── 元灵技能AI参数（2026-07-13 新增）────
var skill_use_threshold: float = 15.0
var skill_energy_min: float = 10.0
var skill_reserve_weight: float = 0.9
var skill_attack_intent_weight: float = 1.0
var skill_defense_intent_weight: float = 1.0
var skill_support_intent_weight: float = 1.0
var skill_think_interval: float = 0.5
var skill_late_game_bonus: float = 1.5
var skill_losing_bonus: float = 1.3
var skill_leading_penalty: float = 0.7
var skill_uncertainty_discount: float = 0.6
var skill_expected_future_score: float = 50.0
var skill_element_counter_bonus: float = 1.3
var skill_element_counter_penalty: float = 0.7
var skill_combo_bonus: float = 0.5
var skill_threat_assessment_weight: float = 0.3
var skill_distance_factor_weight: float = 0.1
var skill_situation_reading_depth: int = 3
var skill_accuracy: float = 0.7
var skill_mistake_chance: float = 0.15
var skill_synergy_bonus_critical: float = 1.5
var skill_synergy_bonus_high: float = 1.3
var skill_outnumbered_bonus: float = 1.15
var skill_selection_temperature: float = 2.0


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
			p.decision_hysteresis = 5.0   # 主攻手：小容差，果断切换（P0）
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
			p.hold_range = 150.0
			p.hold_range_teammate_ball = 120.0
			p.hold_range_enemy_ball = 100.0
			p.formation_priority = 0.5
			p.idle_drift_radius = 35.0
			p.idle_drift_interval = 1.5
			p.prefer_forward_pass = true
			p.prefer_distance_min = 100.0
			p.prefer_distance_max = 250.0
			p.random_factor = 12.0
			p.pass_angle_error = 5.0
			p.shoot_angle_error = 2.0
			p.field_of_view = 180.0
			p.vision_range = 400.0
			p.awareness_accuracy = 0.85
			p.memory_duration = 1.5
			p.awareness_update_interval = 0.3
			p.facing_mode_chase = "ball"
			p.facing_mode_dribble = "goal"
			p.facing_mode_support = "move"
			p.facing_mode_defend = "enemy"
			p.skill_reserve_weight = 0.7
			p.skill_attack_intent_weight = 1.4
			p.skill_defense_intent_weight = 0.9
			p.skill_support_intent_weight = 1.0
			p.skill_think_interval = 0.3

		"defender":
			p.weight_pass = 30.0
			p.weight_shoot = -10.0
			p.weight_dribble = -25.0
			p.decision_hysteresis = 12.0
			p.hold_duration_min = 0.5
			p.hold_duration_max = 1.2
			p.think_interval = 0.3
			p.reaction_delay = 0.08
			p.speed_chase_mult = 0.9
			p.speed_dribble_mult = 0.7
			p.speed_move_mult = 0.8
			p.aggro_range = 300.0
			p.pass_range = 360.0
			p.ball_attract_weight = 0.1
			p.spread_force = 0.7
			p.hold_range = 80.0
			p.hold_range_teammate_ball = 70.0
			p.hold_range_enemy_ball = 90.0
			p.formation_priority = 0.9
			p.idle_drift_radius = 10.0
			p.idle_drift_interval = 3.0
			p.prefer_forward_pass = false
			p.prefer_distance_min = 80.0
			p.prefer_distance_max = 300.0
			p.random_factor = 4.0
			p.pass_angle_error = 2.0
			p.shoot_angle_error = 6.0
			p.field_of_view = 200.0
			p.vision_range = 400.0
			p.awareness_accuracy = 0.92
			p.memory_duration = 2.5
			p.awareness_update_interval = 0.2
			p.facing_mode_chase = "ball"
			p.facing_mode_dribble = "move"
			p.facing_mode_support = "ball"
			p.facing_mode_defend = "enemy"
			p.skill_reserve_weight = 1.1
			p.skill_attack_intent_weight = 0.9
			p.skill_defense_intent_weight = 1.4
			p.skill_support_intent_weight = 1.0
			p.skill_think_interval = 0.4

		"supporter":
			p.weight_pass = 40.0
			p.weight_shoot = 0.0
			p.weight_dribble = 5.0
			p.decision_hysteresis = 8.0
			p.hold_duration_min = 0.25
			p.hold_duration_max = 0.6
			p.think_interval = 0.18
			p.reaction_delay = 0.0
			p.speed_chase_mult = 1.0
			p.speed_dribble_mult = 0.78
			p.speed_move_mult = 0.95
			p.aggro_range = 420.0
			p.pass_range = 380.0
			p.ball_attract_weight = 0.3
			p.spread_force = 0.5
			p.hold_range = 120.0
			p.hold_range_teammate_ball = 100.0
			p.hold_range_enemy_ball = 85.0
			p.formation_priority = 0.7
			p.idle_drift_radius = 20.0
			p.idle_drift_interval = 2.0
			p.prefer_forward_pass = true
			p.prefer_distance_min = 120.0
			p.prefer_distance_max = 300.0
			p.random_factor = 8.0
			p.pass_angle_error = 3.0
			p.shoot_angle_error = 5.0
			p.field_of_view = 180.0
			p.vision_range = 380.0
			p.awareness_accuracy = 0.88
			p.memory_duration = 2.0
			p.awareness_update_interval = 0.22
			p.facing_mode_chase = "ball"
			p.facing_mode_dribble = "ball"
			p.facing_mode_support = "ball"
			p.facing_mode_defend = "enemy"
			p.skill_reserve_weight = 0.9
			p.skill_attack_intent_weight = 1.0
			p.skill_defense_intent_weight = 1.0
			p.skill_support_intent_weight = 1.4
			p.skill_think_interval = 0.35

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
			profile.skill_use_threshold = 60.0
			profile.skill_energy_min = 40.0
			profile.skill_accuracy = 0.5
			profile.skill_mistake_chance = 0.3
			profile.skill_late_game_bonus = 1.1
			profile.skill_losing_bonus = 1.1
			profile.skill_leading_penalty = 0.5
			profile.skill_expected_future_score = 70.0
			profile.skill_uncertainty_discount = 0.8
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
			profile.skill_use_threshold = 25.0
			profile.skill_energy_min = 10.0
			profile.skill_accuracy = 0.95
			profile.skill_mistake_chance = 0.03
			profile.skill_late_game_bonus = 1.8
			profile.skill_losing_bonus = 1.5
			profile.skill_leading_penalty = 0.85
			profile.skill_expected_future_score = 30.0
			profile.skill_uncertainty_discount = 0.4


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
