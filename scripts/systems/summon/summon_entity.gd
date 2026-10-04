extends CharacterBody2D
## 23-F1 召唤物实体基类（工单23）：魔术球/水鲨鱼共用。
## 状态机：active(在场) / burrowed(潜地) / controlled(被操控) / consumed(已消耗)。
## 纪律：寿命/潜地耗能=固定步长递减（确定性）；球交互走 ball 既有公开口，不新开球权通道；
## 类型表驱动（data/systems/summon/summon_types.json），未知字段 fail-closed。

var summon_type: String = ""
var owner_id: int = 0
var owner_ref: Node = null          # 施法者引用（manager.spawn 注入）
var skill_id: String = ""
var state: String = "active"
var lifespan_left: float = 0.0
var _mgr: Node = null               # summon_manager 反向引用（despawn/融合）
var _tdef: Dictionary = {}          # 类型定义
var _params: Dictionary = {}

const BURROW_TICK_INTERVAL := 60    # 潜地耗能结算间隔（帧；1s@60fps，固定步长确定性）


func setup(type_def: Dictionary, owner: int, params: Dictionary) -> void:
	_tdef = type_def
	_params = params
	owner_id = owner
	owner_ref = params.get("owner_ref", null)   # 施法者注入（耗能 tick/自动生成落点依赖）
	skill_id = str(params.get("skill_id", ""))
	lifespan_left = float(type_def.get("lifespan", 20.0))
	_build_hitbox(str(type_def.get("hitbox", "circle:18")))
	if is_inside_tree():
		_build_2d_visual()
	_on_spawned()


func _build_hitbox(spec: String) -> void:
	var parts := spec.split(":")
	var cs := CollisionShape2D.new()
	if parts[0] == "circle":
		var shape := CircleShape2D.new()
		shape.radius = float(parts[1]) if parts.size() > 1 else 18.0
		cs.shape = shape
	else:
		var shape2 := RectangleShape2D.new()
		shape2.size = Vector2(40, 40)
		cs.shape = shape2
	add_child(cs)


func _physics_process(delta: float) -> void:
	if state == "consumed":
		return
	# 1001 自主行为（主人实测"鲨鱼一直不动"）：攻击型召唤物无操控输入时向敌半场游动
	# （原作=可融球进攻或单独操控进攻；AI 无 STEER 输入的默认档=自主进攻游动）。
	# 方向=16号铁事实（a 内场在左→a 攻 +x）；守型/未操控外型不游（拦截待机）。叠加操控UI窗口视觉 WIP 之上。
	if state == "active" and not is_on_wall():
		var kind := str(_tdef.get("kind", ""))
		var ctrl := str(_tdef.get("controllable", ""))
		var team := str(owner_ref.team) if owner_ref != null and is_instance_valid(owner_ref) else "a"
		var atk_x: float = 1.0 if team == "a" else -1.0
		# 1001 AI 平替（主人问"AI不会操控白球"）：19A 操控体系建成前的最小可行平替——
		# 攻球=自主游向敌半场（撞敌/障碍爆炸由 on_ball 既有链结算）；守球=游向己方球员（触达给道具）。
		# 鲨鱼攻击型同款自主游动（守鲨 auto 待机）。
		if kind == "magic_ball":
			var ball_mode := str(_tdef.get("on_ball", {}).get("mode", ""))
			var mb_spd: float = float(_tdef.get("move_speed", 140.0))
			if ball_mode == "carry_with_ball":
				velocity = Vector2(atk_x * mb_spd, 0.0)
				move_and_slide()
			elif ball_mode == "grant_item" and owner_ref != null and is_instance_valid(owner_ref):
				var to_owner: Vector2 = owner_ref.global_position - global_position
				if to_owner.length() > 30.0:
					velocity = to_owner.normalized() * mb_spd
					move_and_slide()
		elif kind == "shark" and ctrl != "auto":
			var spd: float = float(_tdef.get("move_speed", 120.0))
			velocity = Vector2(atk_x * spd, 0.0)
			move_and_slide()
	# 寿命递减（固定步长确定性；耗尽→注销）
	lifespan_left -= delta
	if lifespan_left <= 0.0:
		_consume("lifespan")
		return
	# 潜地耗能 tick（快牙系：额外耗能维持；能量尽→自动浮出）
	if state == "burrowed":
		var cost: float = float(_tdef.get("burrow", {}).get("burrow_energy_cost_per_s", 0.0)) if _tdef.get("burrow", {}) is Dictionary else 0.0
		if cost > 0.0 and _frame_count() % BURROW_TICK_INTERVAL == 0:
			var owner_node = owner_ref
			if owner_node != null and is_instance_valid(owner_node) and owner_node.get("spirit_energy") != null:
				owner_node.spirit_energy = maxf(0.0, float(owner_node.spirit_energy) - cost)
				if float(owner_node.spirit_energy) <= 0.0:
					exit_burrow()


var _frames: int = 0
func _frame_count() -> int:
	_frames += 1
	return _frames


## ===== 状态机（骨架钉死四态）=====

func enter_burrow() -> void:
	if _tdef.get("burrow", null) == null:
		return   # 类型不支持潜地（fail-closed：防御鲨）
	state = "burrowed"
	if _visual != null:
		_visual.modulate.a = 0.5
	_emit_state_changed("burrowed")


func exit_burrow() -> void:
	if state == "burrowed":
		state = "active"
	if _visual != null:
		_visual.modulate.a = 1.0
	_emit_state_changed("active")


func consume() -> void:
	_consume("consumed")


func _consume(reason: String) -> void:
	if state == "consumed":
		return
	state = "consumed"
	_emit_state_changed("consumed", reason)
	if _mgr != null and is_instance_valid(_mgr):
		_mgr.despawn(self, reason)
	else:
		queue_free()


## ===== 2D 兜底视觉（27排查 2026-10-04：实体原为纯逻辑 Node2D，2D 视图轨下完全隐形；
## 双轨裁定=3D主/2D兜底——简约圆形/胶囊+类型色环，零判定）=====
func _ready() -> void:
	_build_2d_visual()
	# 已在树内时补一次（setup 晚于 _ready 的装配序）
	if _tdef.size() > 0 and _visual == null:
		_build_2d_visual()

func _build_2d_visual() -> void:
	if _visual != null:
		return
	_visual = Node2D.new()
	_visual.name = "Visual2D"
	_visual.z_index = 50
	add_child(_visual)
	_visual.draw.connect(_draw_visual)
	_visual.queue_redraw()

func _draw_visual() -> void:
	var kind := str(_tdef.get("kind", ""))
	var stype := str(_tdef.get("id", summon_type))
	if kind == "magic_ball":
		var ring := Color(0.9, 0.2, 0.15, 0.95) if stype.contains("_att") else Color(0.2, 0.45, 0.95, 0.95)
		_visual.draw_circle(Vector2.ZERO, 14.0, Color(0.96, 0.96, 0.98, 0.95))
		_visual.draw_arc(Vector2.ZERO, 17.0, 0.0, TAU, 24, ring, 3.0)
	else:
		var body := Color(1.0, 0.55, 0.1, 0.95) if stype.contains("bomb") else Color(0.55, 0.3, 0.9, 0.92)
		# 鲨鱼=胶囊俯视（长椭圆）
		_visual.draw_circle(Vector2.ZERO, 15.0, body)
		_visual.draw_rect(Rect2(-30, -8, 60, 16), body)
		_visual.draw_circle(Vector2(24, 0), 8.0, body)

var _visual: Node2D = null

## 27-J4：状态流转事件（遁地进出/消耗；订阅端=显示层/战术层，零轮询）
func _emit_state_changed(new_state: String, reason: String = "state") -> void:
	var bus: Node = _bus()
	if bus:
		bus.emit_event(bus.GameEvent.SUMMON_STATE_CHANGED, {"node": self, "state": new_state, "reason": reason})


## ===== 生成/消亡钩子（子类覆写点；骨架阶段=类型表事件广播）=====

func _on_spawned() -> void:
	pass


## 球接近分发（实体→球交互入口；ball 走既有公开口，模式按类型表 on_ball.mode）
## 由 F1 球检测体（Area2D 子节点）调用于球进入时；骨架阶段先支持 intercept/grant 两模式
func on_ball_proximity(ball: Node) -> void:
	if state != "active" and state != "controlled":
		return
	var on_ball: Dictionary = _tdef.get("on_ball", {}) if _tdef.get("on_ball", {}) is Dictionary else {}
	var mode := str(on_ball.get("mode", ""))
	match mode:
		"intercept":
			# 快牙撕咬（防御）：限度内让球停下（超限改线归撕咬实体扩展，骨架=停球计数）
			var stops: int = int(_params.get("stop_count", 0)) + 1
			_params["stop_count"] = stops
			var limit: int = int(on_ball.get("stop_limit", 2))
			if ball.has_method("get") and ball.get("is_active") != null:
				ball.set("is_active", false)
			var bus = _bus()
			if bus:
				bus.emit_event(bus.GameEvent.BALL_FORCED_CONTROL, {"ball": ball, "by_player": owner_ref, "mode": "stop"})
			if stops >= limit:
				_consume("consumed")
		"grant_item":
			# 魔术白球-守：触者获道具（F3 granter 组查找，未接线静默）
			var granter = get_tree().get_first_node_in_group("battle_item_granters") if get_tree() else null
			var taker = ball.get("owner_player") if ball.get("owner_player") != null else _find_owner_node()
			if granter != null and granter.has_method("grant_battle_item") and taker != null:
				granter.grant_battle_item(taker, str(on_ball.get("item_pool", ["potion"])[0]), "magic_ball")
			_consume("consumed")
		_:
			pass   # carry_with_ball/merge_with_ball：随操控族（19号链）与融合工单接续


func _find_owner_node() -> Node:
	return owner_ref


func _bus():
	var tree := get_tree()
	return tree.get_first_node_in_group("battle_event_bus") if tree else null
