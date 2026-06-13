## 幻象节点
## 复制自真身球员(player.gd)的虚假实体
## - 视觉：克隆真身节点，颜色黯淡（异色/降透明度）
## - 行为：默认镜像模仿真身移动动作；开启AI智能→被AI接管保护真身
## - 挡伤：实体，球击中走防御减伤扣体力，无韧性系统（不弹飞/不僵直），球会被挡住
## - 消失：duration 与 stamina<=0 取先到
## - AI对接预留：加组 illusions + is_illusion 标记 + source_player 引用

extends CharacterBody2D
class_name Illusion

## ==================== 配置 ====================

# 颜色：比真身黯淡（真身蓝/红 → 幻象降饱和+降透明）
const PHANTOM_ALPHA: float = 0.55
const PHANTOM_TINT: Dictionary = {
	"a": Color(0.35, 0.4, 0.9, PHANTOM_ALPHA),   # 我方蓝→黯淡蓝
	"b": Color(0.9, 0.35, 0.4, PHANTOM_ALPHA),   # 敌方红→黯淡红
}

## ==================== 核心引用 ====================

var source_player: CharacterBody2D = null  # 真身
var illusion_id: String = ""
var illusion_team: String = ""

## ==================== 运行时状态 ====================

var stamina: float = 100.0
var max_stamina: float = 100.0
var defense: float = 0.0
var defense_factor: float = 0.15
var speed: float = 200.0
var attack_power: float = 0.0

var is_illusion: bool = true
var is_defeated: bool = false
var facing_direction: Vector2 = Vector2.RIGHT
var duration: float = 10.0
var remaining: float = 10.0

# 球员标识字段（与 player.gd 对齐，供 ball.gd / 碰撞查询）
var team: String = "a"
var is_player_controlled: bool = false
var char_data: Dictionary = {}

# 行为模式
var ai_mode: bool = false  # true=AI接管；false=镜像真身

# Buff堆栈（区域效果会挂 buff，幻象需要自己的栈）
var _buffs: Dictionary = {}

# 视觉节点引用（克隆后改色用）
var avatar_bg: ColorRect = null
var avatar_label: Label = null


## ==================== 信号 ====================

signal illusion_expired(illusion: Illusion)


## ==================== 初始化 ====================

func setup(source: CharacterBody2D, params: Dictionary) -> void:
	"""初始化幻象：克隆真身数据
	params: stamina, duration, ai_mode, illusion_id"""
	if not source or not is_instance_valid(source):
		push_error("[Illusion] 真身无效")
		return
	source_player = source
	illusion_team = source.team
	illusion_id = str(params.get("illusion_id", ""))
	team = source.team

	# 复制数值
	max_stamina = float(params.get("stamina", source.max_stamina))
	stamina = max_stamina
	defense = float(source.defense)
	defense_factor = float(source.defense_factor)
	speed = float(source.speed)
	attack_power = float(source.attack_power)
	is_player_controlled = false

	duration = float(params.get("duration", 10.0))
	remaining = duration
	ai_mode = bool(params.get("ai_mode", false))

	# 碰撞：与真身同层，可被球检测
	collision_layer = 1
	collision_mask = 0

	# 分组：球员组(供球碰撞查询) + 幻象组(供AI/清除)
	add_to_group("players")
	add_to_group("illusions")

	# 视觉
	_build_visual(source)


func _build_visual(source: CharacterBody2D) -> void:
	"""克隆真身视觉，改色为黯淡"""
	# 碰撞圆（半径同真身 28）
	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 28.0
	collision.shape = circle
	add_child(collision)

	# 背景色圆（黯淡色）
	avatar_bg = ColorRect.new()
	avatar_bg.size = Vector2(56, 56)
	avatar_bg.position = Vector2(-28, -28)
	avatar_bg.color = PHANTOM_TINT.get(illusion_team, PHANTOM_TINT["a"])
	var style := StyleBoxFlat.new()
	style.bg_color = avatar_bg.color
	style.set_corner_radius_all(20)
	avatar_bg.add_theme_stylebox_override("normal", style)
	add_child(avatar_bg)

	# 数字标签（与真身相同）
	avatar_label = Label.new()
	var display: String = "#"
	if source.char_data.has("name"):
		display = str(source.char_data["name"]).substr(0, 1)
	avatar_label.text = display
	avatar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	avatar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	avatar_label.position = Vector2(-28, -28)
	avatar_label.size = Vector2(56, 56)
	avatar_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.8))
	add_child(avatar_label)


## ==================== 帧处理 ====================

func _physics_process(delta: float) -> void:
	if is_defeated:
		return

	# 倒计时
	remaining -= delta
	if remaining <= 0.0:
		_expire("duration")
		return

	# 体力归零
	if stamina <= 0.0:
		_expire("stamina")
		return

	# 移动行为
	if ai_mode:
		_ai_move(delta)  # 占位：AI接管（未来对接 ai_manager）
	else:
		_mirror_source(delta)

	# 真正位移（CharacterBody2D 必须调用 move_and_slide 才会动）
	move_and_slide()

	# buff 倒计时（区域效果挂的 buff）
	_tick_buffs(delta)

	# 朝向更新
	if velocity.length() > 1.0:
		facing_direction = velocity.normalized()


func _mirror_source(delta: float) -> void:
	"""默认行为：镜像模仿真身的移动动作（速度方向+大小）"""
	if not source_player or not is_instance_valid(source_player):
		velocity = Vector2.ZERO
		return
	# 直接复用真身当前速度（模仿动作）
	velocity = source_player.velocity


func _ai_move(_delta: float) -> void:
	"""AI接管模式：保护真身（占位，未来由 ai_manager 驱动）
	当前简单实现：贴在真身前方阻挡"""
	if not source_player or not is_instance_valid(source_player):
		velocity = Vector2.ZERO
		return
	var target: Vector2 = source_player.global_position + source_player.facing_direction * 35.0
	var to_target: Vector2 = target - global_position
	if to_target.length() > 4.0:
		velocity = to_target.normalized() * speed
	else:
		velocity = Vector2.ZERO


## ==================== 挡伤（与真身流程相同，无韧性系统）====================

func take_damage(amount: float, _attacker: CharacterBody2D = null) -> Dictionary:
	"""球击中幻象：走防御减伤，无韧性系统（不弹飞/不僵直）
	球会被挡住（实体），所以不改变球权——由 ball.gd 处理球停"""
	if is_defeated:
		return {"damage": 0, "effect": "none"}

	var dmg: float = amount
	# 防御减伤（与真身流程一致）
	var def_resist: float = defense * defense_factor
	var reduction_rate: float = minf(def_resist / 100.0, 0.8)
	dmg *= (1.0 - reduction_rate)
	dmg = maxf(0.0, dmg)

	stamina = maxf(0.0, stamina - dmg)

	var effect: String = "blocked"  # 被挡住，无韧性弹飞

	if stamina <= 0.0:
		is_defeated = true

	print("[Illusion] %s 挡伤 %.1f(减伤后) 剩余体力%.0f" % [illusion_id, dmg, stamina])
	return {"damage": dmg, "effect": effect}


func is_status_active(_status_name: String) -> bool:
	"""幻象不复制真身技能状态，恒返回 false"""
	return false


## ==================== 消失 ====================

func _expire(reason: String) -> void:
	if is_defeated:
		return
	is_defeated = true
	print("[Illusion] %s 消失(原因:%s)" % [illusion_id, reason])
	illusion_expired.emit(self)
	queue_free()


func force_remove() -> void:
	"""外部强制清除"""
	_expire("cleared")


func get_illusion_info() -> String:
	return "%s | 队%s | 体力%.0f/%.0f | 剩余%.1fs | AI%s" % [
		illusion_id, illusion_team, stamina, max_stamina, remaining,
		"开" if ai_mode else "关"
	]


## ==================== Buff系统（区域效果用）====================

func add_buff(id: String, stat: String, mult: float, flat: float, duration: float, source: String = "") -> void:
	"""添加/覆盖属性buff（与 player.add_buff 接口一致，供 field_effect_zone 调用）"""
	_buffs[id] = {
		"id": id,
		"stat": stat,
		"mult": mult,
		"flat": flat,
		"source": source,
		"duration": duration,
		"remaining": duration,
	}


func remove_buff(id: String) -> bool:
	return _buffs.erase(id)


func _get_effective_value(stat: String, base_value: float) -> float:
	"""计算属性最终值 = 基础×连乘 + 加法（与 player._get_effective_value 一致）"""
	var m: float = 1.0
	var f: float = 0.0
	for id in _buffs:
		var b: Dictionary = _buffs[id]
		if b.get("stat", "") == stat:
			m *= b.get("mult", 1.0)
			f += b.get("flat", 0.0)
	m = maxf(m, 0.01)
	return base_value * m + f


func _tick_buffs(delta: float) -> void:
	"""每帧倒计时，到期移除"""
	var expired_ids: Array = []
	for id in _buffs:
		_buffs[id]["remaining"] = float(_buffs[id].get("remaining", 0.0)) - delta
		if float(_buffs[id]["remaining"]) <= 0.0:
			expired_ids.append(id)
	for id in expired_ids:
		_buffs.erase(id)
