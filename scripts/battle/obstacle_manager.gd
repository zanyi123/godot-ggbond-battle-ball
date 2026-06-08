## 障碍物管理器
## 管理场上所有障碍物的创建、清除、查询
## 挂载在 BattleManager 下

extends Node
class_name ObstacleManager

## ==================== 数据 ====================

## 场上所有障碍物
var obstacles: Array[StaticBody2D] = []

## 鼠标放置/清除系统
var placer: Node = null


## ==================== 初始化 ====================

func _ready() -> void:
	# 创建放置系统
	placer = Node.new()
	placer.set_script(load("res://scripts/battle/obstacle_placer.gd"))
	placer.name = "ObstaclePlacer"
	add_child(placer)
	# 注册到 obstacle_managers 组（供球查找）
	add_to_group("obstacle_managers")
	print("[ObstacleManager] 已初始化")


## ==================== 创建障碍物 ====================

func create_obstacle(params: Dictionary, position: Vector2, rotation: float = 0.0) -> StaticBody2D:
	"""创建并放置障碍物

	参数：
	- params: 障碍物参数（shape, hp, attack_consume_rate, speed_consume_rate等）
	- position: 放置位置（全局坐标）
	- rotation: 旋转角度

	返回：创建的障碍物节点
	"""
	# 检查最大数量
	var max_count: int = int(params.get("max_count", 1))
	var source_skill: String = params.get("source_skill", "")
	if max_count > 0 and source_skill != "":
		var count: int = 0
		for obs in obstacles:
			if is_instance_valid(obs) and obs.source_skill == source_skill:
				count += 1
		# 超出数量限制，移除最早的
		while count >= max_count:
			for obs in obstacles:
				if is_instance_valid(obs) and obs.source_skill == source_skill:
					_remove_obstacle(obs)
					count -= 1
					break

	# 创建障碍物节点
	var obstacle := StaticBody2D.new()
	obstacle.set_script(load("res://scripts/battle/obstacle.gd"))
	obstacle.name = "Obstacle_" + str(obstacles.size())
	obstacle.global_position = position
	obstacle.rotation = rotation

	# 添加到场景（必须在 setup 之前，否则 CollisionShape2D 无法正确注册）
	add_child(obstacle)

	# 初始化参数（创建碰撞形状、视觉等）
	obstacle.setup(params)

	# 连接信号
	obstacle.obstacle_destroyed.connect(_on_obstacle_destroyed)
	obstacle.obstacle_expired.connect(_on_obstacle_expired)
	obstacles.append(obstacle)

	print("[ObstacleManager] 创建障碍物: shape=" + str(params.get("shape", "rect")) + " hp=" + str(snapped(params.get("hp", 50.0), 1.0)) + " pos=(" + str(snapped(position.x, 1.0)) + "," + str(snapped(position.y, 1.0)) + ")")

	return obstacle


## ==================== 清除障碍物 ====================

func remove_obstacle(obstacle: StaticBody2D) -> void:
	"""清除指定障碍物"""
	_remove_obstacle(obstacle)


func remove_obstacles(obstacle_list: Array) -> void:
	"""清除多个障碍物"""
	for obs in obstacle_list:
		if is_instance_valid(obs):
			_remove_obstacle(obs)


func clear_all_obstacles() -> void:
	"""清除所有障碍物"""
	for obs in obstacles.duplicate():
		if is_instance_valid(obs):
			obs.remove()
	obstacles.clear()
	print("[ObstacleManager] 已清除所有障碍物")


func clear_obstacles_by_skill(skill_id: String) -> void:
	"""清除指定技能创建的障碍物"""
	for obs in obstacles.duplicate():
		if is_instance_valid(obs) and obs.source_skill == skill_id:
			obs.remove()
	_obstacles_cleanup()


## ==================== 查询 ====================

func get_obstacle_at_position(pos: Vector2, radius: float = 30.0) -> StaticBody2D:
	"""获取指定位置附近的障碍物（用于鼠标点击选中）

	参数：
	- pos: 点击位置
	- radius: 搜索半径

	返回：最近的障碍物，没有则返回null
	"""
	var closest: StaticBody2D = null
	var closest_dist: float = radius

	for obs in obstacles:
		if not is_instance_valid(obs):
			continue
		var dist: float = obs.global_position.distance_to(pos)
		if dist < closest_dist:
			closest_dist = dist
			closest = obs

	return closest


func get_all_obstacles() -> Array:
	"""获取所有存活障碍物"""
	_obstacles_cleanup()
	var result: Array = []
	for obs in obstacles:
		if is_instance_valid(obs):
			result.append(obs)
	return result


func get_obstacle_count() -> int:
	"""获取障碍物数量"""
	_obstacles_cleanup()
	return obstacles.size()


## ==================== 鼠标放置/清除 ====================

func start_placing(params: Dictionary, mouse_ops: int = 1) -> void:
	"""进入放置模式（创造障碍标签调用）"""
	if placer:
		placer.start_placing(params, mouse_ops)


func start_clearing(clear_count: int, mouse_ops: int = 1) -> void:
	"""进入清除模式（清除障碍标签调用）"""
	if placer:
		placer.start_clearing(clear_count, mouse_ops)


func cancel_operation() -> void:
	"""取消当前鼠标操作"""
	if placer:
		placer.cancel_operation()


func is_operating() -> bool:
	"""是否在鼠标操作模式中"""
	if placer:
		return placer.is_operating()
	return false


## ==================== 内部方法 ====================

func _remove_obstacle(obstacle: StaticBody2D) -> void:
	"""移除单个障碍物"""
	if obstacles.has(obstacle):
		obstacles.erase(obstacle)
	if is_instance_valid(obstacle):
		obstacle.remove()


func _obstacles_cleanup() -> void:
	"""清理无效障碍物引用"""
	var valid: Array[StaticBody2D] = []
	for obs in obstacles:
		if is_instance_valid(obs):
			valid.append(obs)
	obstacles = valid


func _on_obstacle_destroyed(obstacle: StaticBody2D) -> void:
	"""障碍物被摧毁回调"""
	if obstacles.has(obstacle):
		obstacles.erase(obstacle)
	print("[ObstacleManager] 障碍物被摧毁 pos=(" + str(snapped(obstacle.global_position.x, 1.0)) + "," + str(snapped(obstacle.global_position.y, 1.0)) + ")")


func _on_obstacle_expired(obstacle: StaticBody2D) -> void:
	"""障碍物过期回调"""
	if obstacles.has(obstacle):
		obstacles.erase(obstacle)
	print("[ObstacleManager] 障碍物持续时间结束 pos=(" + str(snapped(obstacle.global_position.x, 1.0)) + "," + str(snapped(obstacle.global_position.y, 1.0)) + ")")
