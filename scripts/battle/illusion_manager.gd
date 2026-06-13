## 幻象管理器
## 管理场上所有幻象的创建、清除、查询
## 挂载在 BattleManager 下（或测试场景下，加组 illusion_managers）

extends Node
class_name IllusionManager

## ==================== 数据 ====================

var illusions: Array[Illusion] = []
var illusion_counter: int = 0
var placer: Node = null

## ==================== 初始化 ====================

func _ready() -> void:
	placer = Node.new()
	placer.set_script(load("res://scripts/battle/illusion_placer.gd"))
	placer.name = "IllusionPlacer"
	add_child(placer)
	add_to_group("illusion_managers")
	print("[IllusionManager] 已初始化")


## ==================== 创建幻象 ====================

func create_illusion(source: CharacterBody2D, params: Dictionary, position: Vector2) -> Illusion:
	"""创建并放置幻象"""
	if not source or not is_instance_valid(source):
		push_error("[IllusionManager] 真身无效")
		return null

	illusion_counter += 1
	if not params.has("illusion_id"):
		params["illusion_id"] = "illusion_%d" % illusion_counter

	var illusion_script := load("res://scripts/battle/illusion.gd")
	var illusion := CharacterBody2D.new()
	illusion.set_script(illusion_script)
	illusion.name = "Illusion_%d" % illusion_counter
	illusion.global_position = position
	add_child(illusion)
	illusion.setup(source, params)

	illusion.illusion_expired.connect(_on_illusion_expired)
	illusions.append(illusion)

	print("[IllusionManager] 创建幻象: id=%s pos=(%.0f,%.0f) stamina=%.0f dur=%.1fs" % [
		params["illusion_id"], position.x, position.y,
		float(params.get("stamina", source.max_stamina)),
		float(params.get("duration", 10.0))
	])
	return illusion


## ==================== 清除幻象 ====================

func remove_illusion(illusion: Illusion) -> void:
	if illusions.has(illusion) and is_instance_valid(illusion):
		illusions.erase(illusion)
		illusion.force_remove()


func remove_illusion_by_id(illusion_id: String) -> int:
	"""按ID移除，返回移除数"""
	var count: int = 0
	for ill in illusions.duplicate():
		if is_instance_valid(ill) and ill.illusion_id == illusion_id:
			illusions.erase(ill)
			ill.force_remove()
			count += 1
	return count


func clear_all_illusions() -> void:
	"""清除所有幻象"""
	var count: int = illusions.size()
	for ill in illusions.duplicate():
		if is_instance_valid(ill):
			ill.force_remove()
	illusions.clear()
	print("[IllusionManager] 清除所有幻象(%d个)" % count)


## ==================== 查询 ====================

func get_illusion_count() -> int:
	_cleanup()
	return illusions.size()


func get_all_illusions() -> Array:
	_cleanup()
	var result: Array = []
	for ill in illusions:
		if is_instance_valid(ill):
			result.append(ill)
	return result


func get_illusion_at_position(pos: Vector2, radius: float = 50.0) -> Illusion:
	"""获取指定位置附近的幻象"""
	var closest: Illusion = null
	var closest_dist: float = radius
	for ill in illusions:
		if not is_instance_valid(ill):
			continue
		var dist: float = ill.global_position.distance_to(pos)
		if dist < closest_dist:
			closest_dist = dist
			closest = ill
	return closest


## ==================== 鼠标放置 ====================

func start_placing(params: Dictionary, mouse_ops: int = 1) -> void:
	"""进入放置模式
	params: source_player, place_mode(any/near), stamina, duration, ai_mode"""
	if placer:
		placer.start_placing(params, mouse_ops)


func start_clearing(mouse_ops: int = 1) -> void:
	if placer:
		placer.start_clearing(mouse_ops)


func cancel_operation() -> void:
	if placer:
		placer.cancel_operation()


func is_operating() -> bool:
	if placer:
		return placer.is_operating()
	return false


## ==================== 内部方法 ====================

func _cleanup() -> void:
	var valid: Array[Illusion] = []
	for ill in illusions:
		if is_instance_valid(ill):
			valid.append(ill)
	illusions = valid


func _on_illusion_expired(illusion: Illusion) -> void:
	if illusions.has(illusion):
		illusions.erase(illusion)
	print("[IllusionManager] 幻象 %s 已消失" % (illusion.illusion_id if illusion else "?"))
