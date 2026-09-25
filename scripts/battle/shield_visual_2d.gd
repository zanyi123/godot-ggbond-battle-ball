extends Node2D
class_name ShieldVisual2D
## 13-C 基础 UI：盾本体 2D 兜底可视（贴身弧面+耐久可辨；作为盾障碍的子节点，跟随/落点天然同步）
## 铁律：只读消费宿主盾的公开数据（obstacle_hp/uses_left/shield_state_changed），零判定逻辑

var _host: Node = null            # 宿主盾（player_shield.gd 实例）
var _hp_ratio: float = 1.0        # hp 模式耐久比（绿→黄→红梯度）
var _uses_left: int = -1          # uses 模式剩余次数
var _durability_mode: String = "hp"
var _arc_radius: float = 34.0
var _max_hp: float = 1.0


func setup(host: Node) -> void:
	_host = host
	_durability_mode = str(host.get("durability_mode") if host.get("durability_mode") != null else "hp")
	_max_hp = maxf(float(host.get("obstacle_hp") if host.get("obstacle_hp") != null else 1.0), 1.0)
	if host.has_signal("shield_state_changed"):
		host.shield_state_changed.connect(_on_shield_state_changed)
	_refresh_from_host()
	queue_redraw()


func _refresh_from_host() -> void:
	if _host == null or not is_instance_valid(_host):
		return
	var hp = _host.get("obstacle_hp")
	if hp != null:
		_hp_ratio = clampf(float(hp) / _max_hp, 0.0, 1.0)
	var uses = _host.get("uses_left")
	if uses != null:
		_uses_left = int(uses)
	queue_redraw()


func _on_shield_state_changed(_hp: float, _reason: String) -> void:
	_refresh_from_host()


func _process(_delta: float) -> void:
	# hp 模式无信号逐帧变化（击穿消耗走 consume_frame），低频刷新保证可辨
	_refresh_from_host()


func _draw() -> void:
	# 弧面：金/盾色，耐久梯度（hp 模式=颜色 绿→黄→红；uses 模式=剩余次数点）
	var arc_color: Color
	if _durability_mode == "uses":
		arc_color = Color(1.0, 0.84, 0.0)
	else:
		if _hp_ratio > 0.6:
			arc_color = Color(1.0, 0.84, 0.0).lerp(Color(1.0, 0.7, 0.1), 0.0)
		elif _hp_ratio > 0.3:
			arc_color = Color(1.0, 0.7, 0.1)
		else:
			arc_color = Color(0.9, 0.25, 0.15)
	var sweep: float = PI * 1.2
	var start: float = -PI / 2.0 - sweep / 2.0
	# hp 模式弧长也随耐久收缩（递减可辨）
	if _durability_mode == "hp":
		sweep *= clampf(_hp_ratio, 0.15, 1.0)
	draw_arc(Vector2.ZERO, _arc_radius, start, start + sweep, 24, arc_color, 5.0)
	# uses 模式：剩余次数点
	if _durability_mode == "uses" and _uses_left >= 0:
		for i in range(_uses_left):
			draw_circle(Vector2(-12.0 + i * 10.0, 0.0), 3.0, Color.WHITE)
	# 内描边（轮廓可辨）
	draw_arc(Vector2.ZERO, _arc_radius - 5.0, start, start + sweep, 24, Color(0.1, 0.1, 0.1, 0.5), 1.5)
