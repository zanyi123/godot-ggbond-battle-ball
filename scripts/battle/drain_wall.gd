extends Obstacle
class_name DrainWall

## 波7 #6b 削能墙（16 工单）：吸力墙障碍——捕获半径内球被吸向墙心并逐帧削攻击/球速
## 与岩石墙差异 = 吸力（未接触即吸入）+ 不做击穿（consume_frame 不扣墙 hp，削完即止）
## 消耗规则复用既有 attack_consume_rate/speed_consume_rate 口径（ball._process_obstacle_stuck）
## 球速/攻击耗尽 → 既有 _stop_and_return 球权规则；吸住时长上限到 → 释放继续飞

var capture_radius: float = 90.0
var absorb_pull: float = 240.0     # 吸入速度（px/s，向墙心）
var drain_hold: float = 2.0        # 单次吸住时长上限（秒），到时释放继续飞
var ball_ref: Node2D = null
var _hold_left: float = 0.0


func setup_drain(params: Dictionary) -> void:
	"""Obstacle.setup 之后调用：削能墙特有参数"""
	capture_radius = float(params.get("capture_radius", 90.0))
	absorb_pull = float(params.get("absorb_pull", 240.0))
	drain_hold = float(params.get("drain_hold", 2.0))


func _physics_process(delta: float) -> void:
	if ball_ref == null or not is_instance_valid(ball_ref) or not ball_ref.is_active:
		_hold_left = 0.0
		return
	if ball_ref.is_clone:
		return  # 子球不与削能墙交互（防递归/简化生命周期）
	var dist: float = global_position.distance_to(ball_ref.global_position)
	if dist <= capture_radius:
		# 吸力：球位置向墙心靠拢
		ball_ref.global_position = ball_ref.global_position.move_toward(global_position, absorb_pull * delta)
		if ball_ref.stuck_on_obstacle != self:
			# 进入逐帧消耗（复用岩石墙口径：削攻击/球速）
			ball_ref.stuck_on_obstacle = self
			_hold_left = drain_hold
			print("[DrainWall] 球被吸入削能墙! 开始削能")
		# 吸住时长上限：到时释放继续飞
		_hold_left -= delta
		if _hold_left <= 0.0 and ball_ref.stuck_on_obstacle == self:
			ball_ref.stuck_on_obstacle = null
			print("[DrainWall] 吸住超时释放, 球继续飞")
	elif ball_ref.stuck_on_obstacle == self:
		# 球被吸出捕获半径（理论少见）：释放
		ball_ref.stuck_on_obstacle = null


func consume_frame(_delta: float) -> void:
	"""削能墙不做击穿（墙 hp 不被消耗）；球的攻击/球速仍由 ball 侧逐帧削减"""
	pass
