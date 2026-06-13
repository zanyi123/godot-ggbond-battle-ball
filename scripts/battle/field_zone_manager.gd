## 场地效果区域管理器
## 管理场上所有区域效果的创建、清除、查询
## 挂载在 BattleManager 下（或测试场景下）

extends Node
class_name FieldZoneManager

## ==================== 数据 ====================

var zones: Array[Area2D] = []
var zone_counter: int = 0
var placer: Node = null

## ==================== 初始化 ====================

func _ready() -> void:
	placer = Node.new()
	placer.set_script(load("res://scripts/battle/field_zone_placer.gd"))
	placer.name = "FieldZonePlacer"
	add_child(placer)
	add_to_group("field_zone_managers")
	print("[FieldZoneManager] 已初始化")


## ==================== 创建区域 ====================

func create_zone(params: Dictionary, position: Vector2) -> Area2D:
	"""创建并放置效果区域"""
	zone_counter += 1
	if not params.has("zone_id"):
		params["zone_id"] = "zone_%d" % zone_counter

	# 统一 effect_value：从各种 key 映射过来
	if not params.has("effect_value"):
		var zone_type: int = int(params.get("zone_type", 0))
		match zone_type:
			0:
				params["effect_value"] = float(params.get("boost_multiplier", 1.5))
			1:
				params["effect_value"] = float(params.get("slow_multiplier", 1.5))
			2:
				params["effect_value"] = float(params.get("damage_value", 10.0))
			3:
				params["effect_value"] = 1.0  # 安全区无数值

	var zone_script := load("res://scripts/battle/field_effect_zone.gd")
	var zone := Area2D.new()
	zone.set_script(zone_script)
	zone.name = "FieldZone_%d" % zone_counter
	zone.global_position = position
	zone.collision_mask = 1  # layer 1 = 球员层

	add_child(zone)
	zone.setup(params)

	zone.zone_expired.connect(_on_zone_expired)
	zones.append(zone)

	print("[FieldZoneManager] 创建区域: type=%s size=%.0f×%.0f dur=%.1fs pos=(%.0f,%.0f)" % [
		str(params.get("zone_type", "?")),
		float(params.get("width", 120.0)),
		float(params.get("height", 120.0)),
		float(params.get("duration", 10.0)),
		position.x, position.y
	])

	return zone


## ==================== 清除区域 ====================

func remove_zone(zone: Area2D) -> void:
	"""移除指定区域"""
	if zones.has(zone) and is_instance_valid(zone):
		zones.erase(zone)
		zone.force_remove()


func remove_zone_by_id(zone_id: String) -> void:
	"""按ID移除区域"""
	for zone in zones.duplicate():
		if is_instance_valid(zone) and zone.zone_id == zone_id:
			zones.erase(zone)
			zone.force_remove()
			return


func clear_all_zones() -> void:
	"""清除所有区域"""
	for zone in zones.duplicate():
		if is_instance_valid(zone):
			zone.force_remove()
	zones.clear()
	print("[FieldZoneManager] 已清除所有区域")


## ==================== 查询 ====================

func get_zone_count() -> int:
	_cleanup()
	return zones.size()


func get_all_zones() -> Array:
	_cleanup()
	var result: Array = []
	for zone in zones:
		if is_instance_valid(zone):
			result.append(zone)
	return result


func get_zone_at_position(pos: Vector2, radius: float = 50.0) -> Area2D:
	"""获取指定位置附近的区域"""
	var closest: Area2D = null
	var closest_dist: float = radius
	for zone in zones:
		if not is_instance_valid(zone):
			continue
		var dist: float = zone.global_position.distance_to(pos)
		if dist < closest_dist:
			closest_dist = dist
			closest = zone
	return closest


## ==================== 鼠标放置 ====================

func start_placing(params: Dictionary, mouse_ops: int = 1) -> void:
	"""进入放置模式"""
	if placer:
		placer.start_placing(params, mouse_ops)


func start_zone_clearing(mouse_ops: int = 1) -> void:
	"""进入区域清除模式"""
	if placer:
		placer.start_clearing(mouse_ops)


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

func _cleanup() -> void:
	var valid: Array[Area2D] = []
	for zone in zones:
		if is_instance_valid(zone):
			valid.append(zone)
	zones = valid


func _on_zone_expired(zone: Area2D) -> void:
	"""区域倒计时结束回调"""
	if zones.has(zone):
		zones.erase(zone)
	print("[FieldZoneManager] 区域过期移除")
