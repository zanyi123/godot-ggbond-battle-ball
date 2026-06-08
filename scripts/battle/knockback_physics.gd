## 击退物理计算模块
## 职责：计算击退距离、速度、时间等物理量
## 设计原则：
##   - 击退时间 = 僵直时间（由韧性系统决定）
##   - 击退距离响应摩擦系数（摩擦越小，距离越远）
##   - 支持技能标签的额外加成

class_name KnockbackPhysics
extends Node

## ==================== 基准参数 ====================

## 击退距离基准
const BASE_DISTANCE_K1: float = 100.0  # 一段击退基准距离（标准摩擦μ=1.0）
const BASE_DISTANCE_K2: float = 200.0  # 二段击退基准距离（标准摩擦μ=1.0）

## 球速基准
const BALL_SPEED_NORMAL: float = 400.0 # 标准球速（用于球速加成）

## 常用摩擦系数
const FRICTION_NORMAL: float = 1.0     # 标准地面
const FRICTION_ICE: float = 0.5        # 冰面
const FRICTION_MUD: float = 1.5        # 泥潭


## ==================== 核心计算函数 ====================

## 计算击退距离
## 公式：d_final = (d_baseline / μ) × M_skill + offset
## 参数：
##   - knockback_type: 击退类型（"knockback1" 或 "knockback2"）
##   - friction_coefficient: 场地摩擦系数 μ
##   - skill_distance_multiplier: 技能距离加成倍率（默认1.0）
##   - skill_distance_offset: 技能距离固定加成（像素，默认0.0）
##   - ball_speed: 球速度（可选，启用球速加成时使用）
##   - enable_ball_speed_bonus: 是否启用球速加成（默认false）
## 返回：击退距离（像素）
static func calculate_distance(
	knockback_type: String = "knockback1",
	friction_coefficient: float = 1.0,
	skill_distance_multiplier: float = 1.0,
	skill_distance_offset: float = 0.0,
	ball_speed: float = 400.0,
	enable_ball_speed_bonus: bool = false
) -> float:
	"""计算击退距离
	
	公式：d = (d_baseline / μ) × M_skill + offset
	
	参数说明：
	- knockback_type: 击退类型，影响基准距离
	- friction_coefficient: 摩擦系数，值越小击退越远
	- skill_distance_multiplier: 技能倍率加成（如标签"增伤"或"强力击退"）
	- skill_distance_offset: 技能固定距离加成（如标签"距离+50"）
	- ball_speed: 球速度，用于球速加成
	- enable_ball_speed_bonus: 是否启用球速加成
	
	返回：击退距离（像素）
	
	示例：
	- 标准击退：knockback1, μ=1.0, skill_mult=1.0 → 100px
	- 冰面击退：knockback1, μ=0.5, skill_mult=1.0 → 200px
	- 强力击退：knockback1, μ=1.0, skill_mult=1.5 → 150px
	- 组合效果：knockback1, μ=0.5, skill_mult=1.5 → 300px
	"""
	# 1. 获取基准距离
	var base_dist: float = BASE_DISTANCE_K1 if knockback_type == "knockback1" else BASE_DISTANCE_K2
	
	# 2. 摩擦系数影响（核心公式：摩擦越小，距离越远）
	if friction_coefficient <= 0.0:
		friction_coefficient = 0.01  # 防止除零
	var distance: float = base_dist / friction_coefficient
	
	# 3. 技能倍率加成
	distance *= skill_distance_multiplier
	
	# 4. 技能固定加成
	distance += skill_distance_offset
	
	# 5. 可选：球速加成
	if enable_ball_speed_bonus:
		var speed_bonus: float = ball_speed / BALL_SPEED_NORMAL
		distance *= speed_bonus
	
	return distance


## 计算初始速度（用于动画）
## 公式：v_initial = 2 × d / t（匀减速到0）
## 参数：
##   - distance: 击退距离
##   - duration: 击退持续时间（=僵直时间）
## 返回：初始速度（像素/秒）
static func calculate_initial_velocity(
	distance: float,
	duration: float
) -> float:
	"""计算匀减速到0所需的初始速度
	
	公式：v = 2 × d / t
	
	参数：
	- distance: 击退距离
	- duration: 击退持续时间（必须>0）
	
	返回：初始速度（px/s），如果duration<=0则返回0
	
	示例：
	- 距离100px，时间0.4s → 初始速度500px/s
	- 距离200px，时间0.4s → 初始速度1000px/s
	- 距离100px，时间0.7s → 初始速度286px/s
	"""
	if duration <= 0.0:
		push_error("[KnockbackPhysics] 持续时间必须大于0，当前值: %f" % duration)
		return 0.0
	
	return 2.0 * distance / duration


## 计算当前速度（匀减速过程中的瞬时速度）
## 公式：v_current = v_initial × (1 - t_elapsed / t_total)
## 参数：
##   - initial_velocity: 初始速度
##   - elapsed_time: 已经过的时间
##   - total_duration: 总持续时间
## 返回：当前速度
static func calculate_current_velocity(
	initial_velocity: float,
	elapsed_time: float,
	total_duration: float
) -> float:
	"""计算匀减速过程中的当前速度
	
	公式：v(t) = v₀ × (1 - t/T)
	
	参数：
	- initial_velocity: 初始速度
	- elapsed_time: 已经过的时间
	- total_duration: 总持续时间
	
	返回：当前速度（px/s），如果elapsed_time>=total_duration则返回0
	"""
	if total_duration <= 0.0:
		return 0.0
	
	var progress: float = min(elapsed_time / total_duration, 1.0)
	return initial_velocity * (1.0 - progress)


## 完整计算（一步到位）
## 返回包含所有物理量的字典
static func calculate_knockback(
	knockback_type: String = "knockback1",
	friction_coefficient: float = 1.0,
	stagger_duration: float = 0.4,
	skill_distance_multiplier: float = 1.0,
	skill_distance_offset: float = 0.0,
	ball_speed: float = 400.0,
	enable_ball_speed_bonus: bool = false
) -> Dictionary:
	"""完整计算击退物理量
	
	返回字典：
	{
		"distance": float,          # 击退距离（像素）
		"duration": float,          # 击退持续时间（秒，=僵直时间）
		"initial_velocity": float,  # 初始速度（px/s）
		"friction_coefficient": float # 摩擦系数（用于日志）
	}
	
	示例：
	var result = KnockbackPhysics.calculate_knockback("knockback1", 0.5, 0.4)
	# result.distance = 200.0
	# result.duration = 0.4
	# result.initial_velocity = 1000.0
	"""
	var dist: float = calculate_distance(
		knockback_type,
		friction_coefficient,
		skill_distance_multiplier,
		skill_distance_offset,
		ball_speed,
		enable_ball_speed_bonus
	)
	
	var v0: float = calculate_initial_velocity(dist, stagger_duration)
	
	return {
		"distance": dist,
		"duration": stagger_duration,
		"initial_velocity": v0,
		"friction_coefficient": friction_coefficient
	}


## ==================== 辅助函数 ====================

## 反向计算：给定目标距离，求需要的摩擦系数
## 公式：μ = d_baseline / (d_target / M_skill - offset)
## 参数：
##   - knockback_type: 击退类型
##   - target_distance: 目标击退距离
##   - skill_distance_multiplier: 技能倍率（默认1.0）
##   - skill_distance_offset: 技能固定加成（默认0.0）
## 返回：需要的摩擦系数（如果无法实现则返回-1.0）
static func calculate_required_friction(
	knockback_type: String = "knockback1",
	target_distance: float = 100.0,
	skill_distance_multiplier: float = 1.0,
	skill_distance_offset: float = 0.0
) -> float:
	"""反向计算：要达到目标击退距离需要的摩擦系数
	
	公式推导：
	d = (d_baseline / μ) × M_skill + offset
	d - offset = (d_baseline / μ) × M_skill
	μ = (d_baseline × M_skill) / (d - offset)
	
	参数：
	- knockback_type: 击退类型
	- target_distance: 目标击退距离
	- skill_distance_multiplier: 技能倍率
	- skill_distance_offset: 技能固定加成
	
	返回：需要的摩擦系数，如果无法实现则返回-1.0
	"""
	var base_dist: float = BASE_DISTANCE_K1 if knockback_type == "knockback1" else BASE_DISTANCE_K2
	var effective_distance: float = target_distance - skill_distance_offset
	
	if effective_distance <= 0.0:
		push_warning("[KnockbackPhysics] 目标距离(" + str(target_distance) + ")小于固定加成(" + str(skill_distance_offset) + ")")
		return -1.0
	
	var required_mu: float = (base_dist * skill_distance_multiplier) / effective_distance
	
	return required_mu


## 反向计算：给定目标距离，求需要的技能倍率
## 公式：M_skill = (d - offset) × μ / d_baseline
## 参数：
##   - knockback_type: 击退类型
##   - target_distance: 目标击退距离
##   - friction_coefficient: 当前摩擦系数
##   - skill_distance_offset: 技能固定加成（默认0.0）
## 返回：需要的技能倍率
static func calculate_required_skill_multiplier(
	knockback_type: String = "knockback1",
	target_distance: float = 100.0,
	friction_coefficient: float = 1.0,
	skill_distance_offset: float = 0.0
) -> float:
	"""反向计算：要达到目标击退距离需要的技能倍率
	
	公式推导：
	d = (d_baseline / μ) × M_skill + offset
	d - offset = (d_baseline / μ) × M_skill
	M_skill = (d - offset) × μ / d_baseline
	
	参数：
	- knockback_type: 击退类型
	- target_distance: 目标击退距离
	- friction_coefficient: 当前摩擦系数
	- skill_distance_offset: 技能固定加成
	
	返回：需要的技能倍率
	"""
	var base_dist: float = BASE_DISTANCE_K1 if knockback_type == "knockback1" else BASE_DISTANCE_K2
	var effective_distance: float = target_distance - skill_distance_offset
	
	return (effective_distance * friction_coefficient) / base_dist


## 格式化击退信息（用于日志）
static func format_knockback_info(result: Dictionary, skill_name: String = "") -> String:
	"""格式化击退信息字符串
	
	参数：
	- result: calculate_knockback() 返回的字典
	- skill_name: 技能名称（可选）
	
	返回：格式化的字符串
	"""
	var parts: Array = []
	
	if not skill_name.is_empty():
		parts.append("[%s]" % skill_name)
	
	parts.append("距离%.0fpx" % result.distance)
	parts.append("时长%.2fs" % result.duration)
	parts.append("初速%.0f" % result.initial_velocity)
	
	if result.has("friction_coefficient"):
		parts.append("μ=%.2f" % result.friction_coefficient)
	
	return " ".join(parts)


## ==================== 样本数据生成 ====================

## 生成击退距离样本数据表（单摩擦系数）
static func generate_distance_samples(
	knockback_type: String = "knockback1",
	friction_coefficient: float = 1.0,
	stagger_durations: Array = [0.3, 0.4, 0.5, 0.7],
	skill_multipliers: Array = [1.0, 1.5, 2.0],
	ball_speed: float = 400.0
) -> String:
	"""生成击退距离样本数据表
	
	返回：格式化的表格字符串
	"""
	var lines: Array = []
	var type_name: String = "一段击退(基准100px)" if knockback_type == "knockback1" else "二段击退(基准200px)"
	
	lines.append("=== 击退距离样本表 ===")
	lines.append("类型: " + type_name)
	lines.append("摩擦系数: μ=" + str(snapped(friction_coefficient, 0.01)))
	lines.append("球速: " + str(int(ball_speed)))
	lines.append("")
	
	# 表头
	var header = "僵直时间   技能倍率   击退距离   初始速度   说明"
	lines.append(header)
	var separator = ""
	for i in range(55):
		separator += "-"
	lines.append(separator)
	
	for t_stagger in stagger_durations:
		for skill_mult in skill_multipliers:
			var result: Dictionary = calculate_knockback(
				knockback_type,
				friction_coefficient,
				t_stagger,
				skill_mult,
				0.0,
				ball_speed,
				false
			)
			
			var note: String = ""
			if skill_mult == 1.0:
				note = "标准"
			elif skill_mult == 1.5:
				note = "强力"
			elif skill_mult == 2.0:
				note = "爆发"
			
			var line = str(snapped(t_stagger, 0.1)).lpad(10) + "   "
			line += str(snapped(skill_mult, 0.1)).lpad(10) + "   "
			line += str(int(result.distance)).lpad(10) + "   "
			line += str(int(result.initial_velocity)).lpad(10) + "   "
			line += note
			lines.append(line)
	
	return "\n".join(lines)


## 生成摩擦系数影响样本表
static func generate_friction_samples(
	knockback_type: String = "knockback1",
	stagger_duration: float = 0.4,
	friction_values: Array = [0.3, 0.5, 0.7, 1.0, 1.3, 1.5, 2.0],
	skill_multiplier: float = 1.0
) -> String:
	"""生成摩擦系数影响样本表
	
	返回：格式化的表格字符串
	"""
	var lines: Array = []
	var type_name: String = "一段击退" if knockback_type == "knockback1" else "二段击退"
	var base_dist: float = BASE_DISTANCE_K1 if knockback_type == "knockback1" else BASE_DISTANCE_K2
	
	lines.append("=== 摩擦系数影响样本表 ===")
	lines.append("类型: " + type_name + " (基准" + str(int(base_dist)) + "px)")
	lines.append("僵直时间: " + str(snapped(stagger_duration, 0.1)) + "s")
	lines.append("技能倍率: " + str(snapped(skill_multiplier, 0.1)))
	lines.append("")
	
	# 表头
	var header = "摩擦系数   击退距离   距离变化   初始速度   场地描述"
	lines.append(header)
	var separator = ""
	for i in range(55):
		separator += "-"
	lines.append(separator)
	
	for mu in friction_values:
		var result: Dictionary = calculate_knockback(
			knockback_type,
			mu,
			stagger_duration,
			skill_multiplier
		)
		
		var dist_change: String = ""
		var base_result: Dictionary = calculate_knockback(knockback_type, 1.0, stagger_duration, skill_multiplier)
		var ratio: float = result.distance / base_result.distance
		
		if ratio >= 2.0:
			dist_change = "↑" + str(int((ratio - 1.0) * 100)) + "%"
		elif ratio <= 0.5:
			dist_change = "↓" + str(int((1.0 - ratio) * 100)) + "%"
		elif ratio >= 1.2:
			dist_change = "↑" + str(int((ratio - 1.0) * 100)) + "%"
		elif ratio <= 0.8:
			dist_change = "↓" + str(int((1.0 - ratio) * 100)) + "%"
		else:
			dist_change = "≈"
		
		var surface_desc: String = ""
		if mu <= 0.4:
			surface_desc = "超滑"
		elif mu <= 0.6:
			surface_desc = "冰面"
		elif mu <= 0.8:
			surface_desc = "湿滑"
		elif mu <= 1.1:
			surface_desc = "标准"
		elif mu <= 1.4:
			surface_desc = "粗糙"
		elif mu <= 1.7:
			surface_desc = "泥潭"
		else:
			surface_desc = "粘胶"
		
		var line = str(snapped(mu, 0.1)).lpad(10) + "   "
		line += str(int(result.distance)).lpad(10) + "   "
		line += dist_change.lpad(10) + "   "
		line += str(int(result.initial_velocity)).lpad(10) + "   "
		line += surface_desc
		lines.append(line)
	
	return "\n".join(lines)


## 生成完整样本表（所有因素）
static func generate_full_samples(
	stagger_duration: float = 0.4,
	ball_speed: float = 400.0
) -> String:
	"""生成完整样本表（包含所有因素组合）
	
	返回：格式化的完整表格字符串
	"""
	var lines: Array = []
	
	var separator1 = ""
	for i in range(70):
		separator1 += "="
	lines.append(separator1)
	lines.append("=== 击退物理完整样本表 ===")
	lines.append(separator1)
	lines.append("")
	
	# 韧性段说明
	lines.append("【僵直时间与韧性关系】")
	lines.append("韧性 0-25  → 僵直 0.7s（最久）")
	lines.append("韧性 26-50 → 僵直 0.5s")
	lines.append("韧性 51-75 → 僵直 0.4s")
	lines.append("韧性 76-100→ 僵直 0.3s（最短）")
	lines.append("")
	
	# 一段击退样本
	lines.append(generate_distance_samples("knockback1", 1.0, [0.4], [1.0, 1.5, 2.0], ball_speed))
	lines.append("")
	
	# 二段击退样本
	lines.append(generate_distance_samples("knockback2", 1.0, [0.4], [1.0, 1.5, 2.0], ball_speed))
	lines.append("")
	
	# 摩擦系数影响
	lines.append(generate_friction_samples("knockback1", 0.4, [0.5, 1.0, 1.5], 1.0))
	lines.append("")
	
	var separator2 = ""
	for i in range(70):
		separator2 += "="
	lines.append(separator2)
	
	return "\n".join(lines)
