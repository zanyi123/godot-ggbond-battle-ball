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


func exit_burrow() -> void:
	if state == "burrowed":
		state = "active"


func consume() -> void:
	_consume("consumed")


func _consume(reason: String) -> void:
	if state == "consumed":
		return
	state = "consumed"
	if _mgr != null and is_instance_valid(_mgr):
		_mgr.despawn(self, reason)
	else:
		queue_free()


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
