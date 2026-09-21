extends Obstacle
class_name PlayerShield

## V1-2 体外实体盾（技能规划/05）：岩石墙的随身变体，只做判定层（表现=美术线消费接口）
## D1/D2 follow_mode: "follow"=跟随释放者位置+朝向 / "static"=落地固定（行为等同岩石墙）
## D3 挡所有球：无队伍过滤（与岩石墙一致，含释放者自己的球——已知限制见 05 §五）
## D4 durability_mode: "hp"=数值制（沿用岩石墙逐帧消耗口径）/ "uses"=次数制（每次撞击扣1）

signal shield_state_changed(hp: float, reason: String)  # reason: hit/broken/expired

var follow_mode: String = "follow"
var durability_mode: String = "hp"
var caster_id: int = -1
var caster_node: Node2D = null
var follow_offset: float = 52.0
var uses_left: int = 1
var _broken_signaled: bool = false


func setup_shield(params: Dictionary, caster: Node2D) -> void:
	"""Obstacle.setup 之后调用：绑定释放者与盾特有参数"""
	follow_mode = str(params.get("follow_mode", "follow"))
	durability_mode = str(params.get("durability_mode", "hp"))
	uses_left = maxi(1, int(params.get("uses", 1)))
	caster_id = int(params.get("caster_id", -1))
	caster_node = caster
	follow_offset = float(params.get("follow_offset", 52.0))
	if follow_mode == "follow":
		_follow_caster()


func _process(_delta: float) -> void:
	# 跟随 + 生命周期联动（副系统规范：释放者淘汰 → 盾随之清理）
	if follow_mode == "follow":
		_follow_caster()
	if (caster_node == null or not is_instance_valid(caster_node) or caster_node.get("is_defeated") == true) and not _broken_signaled:
		shield_state_changed.emit(0.0, "expired")
		_destroy()


func _follow_caster() -> void:
	if caster_node == null or not is_instance_valid(caster_node):
		return
	var facing = caster_node.get("facing_direction")
	var dir: Vector2 = facing if facing is Vector2 and facing.length() > 0.1 else Vector2.RIGHT
	global_position = caster_node.global_position + dir.normalized() * follow_offset


## 对外只读接口（05 §二）
func get_shield_hp() -> float:
	return obstacle_hp


## 球开始撞盾（ball 进入 stuck 时调用一次）：uses 次数制在此扣次
func on_ball_hit() -> void:
	if durability_mode != "uses":
		return
	uses_left -= 1
	shield_state_changed.emit(float(maxi(uses_left, 0)), "hit")
	if uses_left <= 0:
		_signal_broken()
		_destroy()


func consume_frame(delta: float) -> void:
	"""hp 数值制沿用岩石墙逐帧消耗；uses 次数制不逐帧扣耐久（球攻/速照常被球侧消耗）"""
	if durability_mode == "uses":
		return
	var before: float = obstacle_hp
	super.consume_frame(delta)
	if obstacle_hp != before:
		shield_state_changed.emit(maxf(obstacle_hp, 0.0), "hit")
	if obstacle_hp <= 0.0:
		_signal_broken()


func _signal_broken() -> void:
	if not _broken_signaled:
		_broken_signaled = true
		shield_state_changed.emit(0.0, "broken")


func _destroy() -> void:
	_signal_broken()
	super._destroy()


func _on_duration_expired() -> void:
	shield_state_changed.emit(0.0, "expired")
	super._on_duration_expired()
