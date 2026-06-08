## 场地物理管理器
## 管理场地的全局物理属性：摩擦系数、弹性系数
## 用于技能标签修改场地物理状态

class_name FieldPhysicsManager
extends Node

## ==================== 常量定义 ====================

## 默认物理属性
const DEFAULT_FRICTION: float = 1.0      # 默认摩擦系数 μ
const DEFAULT_BOUNCINESS: float = 0.0    # 默认弹性系数 e

## 摩擦系数建议范围
const MIN_FRICTION: float = 0.3          # 最小摩擦（超滑冰面）
const MAX_FRICTION: float = 2.0          # 最大摩擦（粘胶）

## 弹性系数建议范围
const MIN_BOUNCINESS: float = 0.0        # 无反弹
const MAX_BOUNCINESS: float = 1.0        # 完全反弹


## ==================== 当前物理属性 ====================

## 摩擦系数 μ
var current_friction: float = DEFAULT_FRICTION

## 弹性系数 e
var current_bounciness: float = DEFAULT_BOUNCINESS


## ==================== 修改来源记录 ====================

## 摩擦系数修改来源（用于调试）
var friction_source: String = "default"

## 摩擦修改结束时间（Unix时间戳，0表示永久）
var friction_end_time: float = 0.0

## 弹性系数修改来源
var bounciness_source: String = "default"


## ==================== 信号 ====================

## 摩擦系数改变信号
signal friction_changed(new_friction: float, source: String)

## 弹性系数改变信号
signal bounciness_changed(new_bounciness: float, source: String)

## 恢复默认信号
signal restored_to_defaults()


## ==================== 生命周期 ====================

func _ready() -> void:
	"""初始化时启动定时检查"""
	# 每0.5秒检查一次是否需要恢复默认摩擦
	var timer = Timer.new()
	timer.wait_time = 0.5
	timer.timeout.connect(_check_friction_restore)
	add_child(timer)
	timer.start()


## ==================== 摩擦系数管理 ====================

## 设置摩擦系数
func set_friction(mu: float, source: String = "unknown", duration: float = 0.0) -> void:
	"""设置场地摩擦系数
	
	参数：
	- mu: 摩擦系数（建议范围 0.3~2.0）
	  - 0.3~0.6: 超滑/冰面（击退距离翻倍以上）
	  - 0.7~0.9: 湿滑路面
	  - 1.0: 标准地面（基准）
	  - 1.1~1.4: 粗糙地面
	  - 1.5~1.7: 泥潭（击退距离减半）
	  - 1.8~2.0: 粘胶（击退距离很短）
	- source: 修改来源（用于调试，如技能名或"terrain_change"）
	- duration: 持续时间（秒）
	  - 0: 永久（直到被其他修改覆盖）
	  - >0: 持续指定时间后自动恢复默认
	
	示例：
	set_friction(0.5, "ice_skill", 10.0)  # 冰面持续10秒
	set_friction(2.0, "mud_trap")          # 泥潭永久（直到恢复）
	"""
	# 范围限制
	if mu < MIN_FRICTION:
		push_warning("[FieldPhysicsManager] 摩擦系数过小: " + str(snapped(mu, 0.01)) + "，限制为 " + str(snapped(MIN_FRICTION, 0.01)))
		mu = MIN_FRICTION
	elif mu > MAX_FRICTION:
		push_warning("[FieldPhysicsManager] 摩擦系数过大: " + str(snapped(mu, 0.01)) + "，限制为 " + str(snapped(MAX_FRICTION, 0.01)))
		mu = MAX_FRICTION
	
	var old_friction: float = current_friction
	current_friction = mu
	friction_source = source
	
	# 设置恢复时间
	if duration > 0.0:
		friction_end_time = Time.get_unix_time_from_system() + duration
		print("[FieldPhysicsManager] 摩擦系数 " + str(snapped(old_friction, 0.01)) + " → " + str(snapped(current_friction, 0.01)) + " (来源: " + source + ", 持续: " + str(snapped(duration, 0.1)) + "s)")
	else:
		friction_end_time = 0.0
		print("[FieldPhysicsManager] 摩擦系数 " + str(snapped(old_friction, 0.01)) + " → " + str(snapped(current_friction, 0.01)) + " (来源: " + source + ", 永久)")
	
	friction_changed.emit(current_friction, source)


## 获取当前摩擦系数
func get_friction() -> float:
	"""获取当前场地摩擦系数 μ
	
	返回值：
	- 当前摩擦系数（默认 1.0）
	
	使用场景：
	- 球员击退时读取摩擦系数计算距离
	- 球员移动时读取摩擦系数影响速度（未来扩展）
	"""
	return current_friction


## 恢复默认摩擦系数
func restore_friction() -> void:
	"""恢复默认摩擦系数
	
	取消所有临时修改，恢复为标准地面
	"""
	if current_friction == DEFAULT_FRICTION:
		return  # 已经是默认值
	
	var old_friction: float = current_friction
	current_friction = DEFAULT_FRICTION
	friction_source = "default"
	friction_end_time = 0.0
	
	print("[FieldPhysicsManager] 恢复默认摩擦系数: " + str(snapped(old_friction, 0.01)) + " → " + str(snapped(current_friction, 0.01)))
	
	friction_changed.emit(current_friction, "default")


## ==================== 弹性系数管理 ====================

## 设置弹性系数
func set_bounciness(e: float, source: String = "unknown", duration: float = 0.0) -> void:
	"""设置场地弹性系数 e
	
	参数：
	- e: 弹性系数（0~1）
	  - 0.0: 无反弹（球撞墙停止或出界）
	  - 0.3: 弱反弹（仅30%速度反弹）
	  - 0.5: 中等反弹（一半速度反弹）
	  - 0.8: 强反弹（80%速度反弹）
	  - 1.0: 完全反弹（100%速度反弹）
	- source: 修改来源
	- duration: 持续时间（秒，目前弹性系数不支持自动恢复，参数保留）
	
	示例：
	set_bounciness(0.8, "bounce_skill")  # 强反弹技能
	"""
	var old_bounciness: float = current_bounciness
	current_bounciness = clamp(e, MIN_BOUNCINESS, MAX_BOUNCINESS)
	bounciness_source = source
	
	print("[FieldPhysicsManager] 弹性系数 " + str(snapped(old_bounciness, 0.01)) + " → " + str(snapped(current_bounciness, 0.01)) + " (来源: " + source + ")")
	
	bounciness_changed.emit(current_bounciness, source)


## 获取当前弹性系数
func get_bounciness() -> float:
	"""获取当前场地弹性系数 e
	
	返回值：
	- 当前弹性系数（默认 0.0）
	
	使用场景：
	- 球碰撞边界时读取弹性系数计算反弹
	"""
	return current_bounciness


## 恢复默认弹性系数
func restore_bounciness() -> void:
	"""恢复默认弹性系数
	
	取消所有修改，恢复为无反弹
	"""
	if current_bounciness == DEFAULT_BOUNCINESS:
		return  # 已经是默认值
	
	var old_bounciness: float = current_bounciness
	current_bounciness = DEFAULT_BOUNCINESS
	bounciness_source = "default"
	
	print("[FieldPhysicsManager] 恢复默认弹性系数: " + str(snapped(old_bounciness, 0.01)) + " → " + str(snapped(current_bounciness, 0.01)))
	
	bounciness_changed.emit(current_bounciness, "default")


## ==================== 批量操作 ====================

## 恢复所有默认值
func restore_all_defaults() -> void:
	"""恢复所有物理属性为默认值"""
	var changed: bool = false
	
	if current_friction != DEFAULT_FRICTION:
		restore_friction()
		changed = true
	
	if current_bounciness != DEFAULT_BOUNCINESS:
		restore_bounciness()
		changed = true
	
	if changed:
		restored_to_defaults.emit()


## ==================== 内部方法 ====================

## 定时检查是否需要恢复默认摩擦
func _check_friction_restore() -> void:
	"""每0.5秒检查一次是否到了恢复时间"""
	if friction_end_time > 0.0:
		var current_time: float = Time.get_unix_time_from_system()
		if current_time >= friction_end_time:
			print("[FieldPhysicsManager] 定时器触发：恢复默认摩擦系数")
			restore_friction()


## ==================== 调试方法 ====================

## 获取当前状态信息
func get_status_info() -> String:
	"""获取当前物理状态信息（用于调试）
	
	返回格式：
	"摩擦: 1.0(来源: default), 弹性: 0.0(来源: default)"
	"""
	var friction_part: String = "摩擦: " + str(snapped(current_friction, 0.01)) + "(来源: " + friction_source + ")"
	var bounciness_part: String = "弹性: " + str(snapped(current_bounciness, 0.01)) + "(来源: " + bounciness_source + ")"
	return friction_part + ", " + bounciness_part


## 打印当前状态
func print_status() -> void:
	"""打印当前物理状态"""
	print("[FieldPhysicsManager] " + get_status_info())


## 获取剩余恢复时间
func get_remaining_restore_time() -> float:
	"""获取摩擦系数剩余恢复时间（秒）
	
	返回值：
	- >0: 剩余秒数
	- 0: 已到时间或无定时恢复
	"""
	if friction_end_time > 0.0:
		var current_time: float = Time.get_unix_time_from_system()
		var remaining: float = friction_end_time - current_time
		return max(0.0, remaining)
	return 0.0