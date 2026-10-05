extends Node
## 23-F1 召唤物系统管理器（工单23，骨架=§二点五 主人钉死；挂 battle_manager 下，照 obstacle_manager 先例）
## 职责：生成/注销/查询/上限管理/自动生成计时器/融合判定；事件经 BattleEventBus（23-F2 v2 枚举）。
## 纪律：确定性（固定步长计时，无墙钟无 randf）；球权权威仍在 ball.gd（实体只走既有公开口）；
## fail-closed：类型表缺失/字段非法→拒绝生成。

const TYPES_PATH := "res://data/systems/summon/summon_types.json"

var _types: Dictionary = {}                 # type_id -> 类型定义
var _limits: Dictionary = {}                # type_id -> 上限（未设=类型表 active_limit，缺省 6）
var _live: Array = []                       # 在场实体引用
var _auto_spawners: Array = []              # [{owner_id, type_id, interval_frames, acc_frames, params}]
var _limit_restores: Array = []             # [{type_id, old_limit, frames_left}]（工单23 芬尼#1 duration 到期还原）
var _empowers: Dictionary = {}              # owner_id -> {config: Dictionary, left: int, frames_left: float}（芬尼#4 强化态）
var _frame_acc: int = 0                     # 固定步长帧计数（确定性时钟）


func _ready() -> void:
	add_to_group("summon_managers")
	_load_types()


func _load_types() -> void:
	if not FileAccess.file_exists(TYPES_PATH):
		push_warning("[Summon] 类型表缺失：" + TYPES_PATH)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(TYPES_PATH))
	if parsed is Dictionary and parsed.get("types", {}) is Dictionary:
		_types = parsed["types"]


func _bus():
	var tree := get_tree()
	return tree.get_first_node_in_group("battle_event_bus") if tree else null


## ===== 核心 API（骨架钉死签名）=====

## 生成：类型定义实例化+上限检查；超限/类型缺失 → null（fail-closed）
func spawn(type_id: String, owner_id: int, pos: Vector2, params: Dictionary = {}) -> Node:
	var tdef: Dictionary = _types.get(type_id, {})
	if tdef.is_empty():
		push_warning("[Summon] 未知类型：" + type_id)
		return null
	var limit: int = int(_limits.get(type_id, int(tdef.get("active_limit", 6))))
	if _count_live(type_id, owner_id) >= limit:
		return null
	var spawn_params: Dictionary = params.duplicate()
	if _empowers.has(owner_id):
		var e: Dictionary = _empowers[owner_id]
		spawn_params["empower"] = (e["config"] as Dictionary).duplicate()
		e["left"] = int(e["left"]) - 1
		if int(e["left"]) <= 0:
			_empowers.erase(owner_id)
	var ent_script: GDScript = load("res://scripts/systems/summon/summon_entity.gd")
	var ent = ent_script.new()
	ent.summon_type = type_id
	ent.owner_id = owner_id
	ent._mgr = self
	get_parent().add_child(ent)
	ent.global_position = pos
	ent.setup(tdef, owner_id, spawn_params)
	_live.append(ent)
	var bus = _bus()
	if bus:
		bus.emit_event(bus.GameEvent.SUMMON_SPAWNED, {"type_id": type_id, "owner_id": owner_id, "node": ent})
	return ent


## 注销（reason: lifespan/consumed/broken/manual/merged）
func despawn(node: Node, reason: String = "lifespan") -> void:
	if node == null or not is_instance_valid(node):
		return
	_live.erase(node)
	print("[SummonManager] 注销: type=%s reason=%s" % [str(node.get("summon_type")), reason])
	var bus = _bus()
	if bus:
		bus.emit_event(bus.GameEvent.SUMMON_DESPAWNED, {"type_id": str(node.get("summon_type")), "owner_id": int(node.get("owner_id")), "node": node, "reason": reason})
	node.queue_free()


func get_summons_of(owner_id: int) -> Array:
	var out: Array = []
	for e in _live:
		if is_instance_valid(e) and int(e.get("owner_id")) == owner_id:
			out.append(e)
	return out


## 上限设置（魔术无上限技 6+6→10+10 由此实现；team 空=不限队伍）
func set_active_limit(type_id: String, n: int) -> void:
	_limits[type_id] = n


## ===== 自动生成计时器（魔术无上限技"此后5秒/个自动无耗生成"；固定步长确定性）=====

func register_auto_spawner(owner_id: int, type_id: String, interval_s: float = 5.0, params: Dictionary = {}) -> void:
	_auto_spawners.append({"owner_id": owner_id, "type_id": type_id,
		"interval_frames": int(round(interval_s * 60.0)), "acc_frames": 0, "params": params})


func stop_auto_spawner(owner_id: int, type_id: String = "") -> void:
	_auto_spawners = _auto_spawners.filter(func(a): return int(a["owner_id"]) != owner_id or (type_id != "" and str(a["type_id"]) != type_id))


## 23 芬尼#1：上限提升（duration 到期自动还原旧值；固定步长帧账本）
func set_active_limit_timed(type_id: String, n: int, old_limit: int, duration_s: float) -> void:
	set_active_limit(type_id, n)
	_limit_restores.append({"type_id": type_id, "old_limit": old_limit, "frames_left": int(round(duration_s * 60.0))})


## 23 芬尼#4：强化态登记（spawn 时透传 params.empower 并递减次数）
func register_empower(owner_id: int, config: Dictionary, count: int, duration_s: float) -> void:
	_empowers[owner_id] = {"config": config, "left": count, "frames_left": duration_s * 60.0}


func _physics_process(delta: float) -> void:
	_frame_acc += 1
	# limit 到期还原
	var keep: Array = []
	for lr in _limit_restores:
		lr["frames_left"] = int(lr["frames_left"]) - 1
		if int(lr["frames_left"]) > 0:
			keep.append(lr)
		else:
			set_active_limit(str(lr["type_id"]), int(lr["old_limit"]))
	_limit_restores = keep
	# empower 到期清除
	for key in _empowers.keys():
		var e: Dictionary = _empowers[key]
		e["frames_left"] = float(e["frames_left"]) - delta
		if float(e["frames_left"]) <= 0.0:
			_empowers.erase(key)
	for a in _auto_spawners:
		a["acc_frames"] = int(a["acc_frames"]) + 1
		if int(a["acc_frames"]) >= int(a["interval_frames"]):
			a["acc_frames"] = 0
			var owner_id: int = int(a["owner_id"])
			var owner_node = _find_node_by_instance_id(owner_id)
			if owner_node == null:
				continue
			# 1001 主人令：自动生成的白球生成在敌方外场带（原作=外场上空生成；此前在施法者身边=与描述不符）
			var spawn_team := _team_of(owner_id)
			var spawn_x: float = 560.0 if spawn_team == "a" else -560.0
			var base_pos: Vector2 = Vector2(spawn_x, -120.0 + 120.0 * float(_frame_acc % 3))  # 确定性轮转散布（禁随机流）
			spawn(str(a["type_id"]), owner_id, base_pos, (a["params"] as Dictionary).duplicate())
	# 1001 主人令：主攻+防御水鲨共存即自动融合为大鲨鱼（原作组合鲨鱼炸弹体系；同队跨球员，
	# 无需快道前置——快道内融合为增强语义保留；randi 仅散布用不影响判定）
	var att_shark: Node = null
	var def_shark: Node = null
	var att_owner: int = -1
	for e in _live:
		if e == null or not is_instance_valid(e):
			continue
		var st_v = e.get("state")     # Object.get 仅 1 参（4.6 静态/运行时同规）
		var ty_v = e.get("summon_type")
		var oid_v = e.get("owner_id")
		if st_v == null or ty_v == null or oid_v == null:
			continue
		if str(st_v) != "active":
			continue
		var ty := str(ty_v)
		var oid := int(oid_v)
		if ty == "shuimu_shark_att" and att_shark == null:
			att_shark = e
			att_owner = oid
		elif ty == "shuimu_shark_def" and def_shark == null and _team_of(oid) == _team_of(att_owner if att_owner >= 0 else -99):
			def_shark = e
	# 1001 主人裁定：双鲨共存即自动融合（不要求快道；快道内融合为增强语义留 11 二期）
	# 不走 try_merge（其内含快道 is_in_energy_path 检查会拦）——直接合：双消+中点生成大鲨鱼+SUMMON_MERGED
	if att_shark != null and def_shark != null:
		var def_owner: int = int(def_shark.get("owner_id"))
		if _team_of(att_owner) == _team_of(def_owner) and att_owner != def_owner:
			var mid: Vector2 = (att_shark.global_position + def_shark.global_position) * 0.5
			var members: Array = [att_shark.get_instance_id(), def_shark.get_instance_id()]
			despawn(att_shark, "merged")
			despawn(def_shark, "merged")
			var bomb: Node = spawn("shuimu_shark_bomb", att_owner, mid, {"members": members})
			if bomb != null:
				var bus = _bus()
				if bus:
					bus.emit_event(bus.GameEvent.SUMMON_MERGED, {"result_type": "shuimu_shark_bomb", "members": members, "params": {}})
				print("[Summon] 🦈→🦈💎 双鲨自动融合: 组合鲨鱼炸弹（跨球员同队）")


## ===== 融合判定（组合鲨鱼炸弹：两条同族鲨鱼+双方处于能量路径=F4 查询口）=====
## F4 未接线时 is_in_energy_path 不存在→恒 false（fail-closed）；SUMMON_MERGED 与20号 on_formed 并行不混用
func try_merge(entity_a: Node, entity_b: Node, result_type: String) -> Node:
	if entity_a == null or entity_b == null or not is_instance_valid(entity_a) or not is_instance_valid(entity_b):
		return null
	var fz = get_tree().get_first_node_in_group("field_zone_managers") if get_tree() else null
	var in_path := false
	if fz != null and fz.has_method("is_in_energy_path"):
		in_path = bool(fz.is_in_energy_path(entity_a.global_position)) and bool(fz.is_in_energy_path(entity_b.global_position))
	if not in_path:
		return null
	var pos: Vector2 = (entity_a.global_position + entity_b.global_position) * 0.5
	var owner_id: int = int(entity_a.get("owner_id"))
	var params: Dictionary = {"members": [entity_a.get_instance_id(), entity_b.get_instance_id()]}
	despawn(entity_a, "merged")
	despawn(entity_b, "merged")
	var result: Node = spawn(result_type, owner_id, pos, params)
	if result != null:
		var bus = _bus()
		if bus:
			bus.emit_event(bus.GameEvent.SUMMON_MERGED, {"result_type": result_type, "members": params["members"], "params": params})
	return result


## ===== 内部 =====

func _count_live(type_id: String, owner_id: int) -> int:
	var owner_team := _team_of(owner_id)
	var n: int = 0
	for e in _live:
		if is_instance_valid(e) and str(e.get("summon_type")) == type_id and _team_of(int(e.get("owner_id"))) == owner_team:
			n += 1
	return n


func _team_of(owner_id: int) -> String:
	var n = _find_node_by_instance_id(owner_id)
	return str(n.get("team")) if n != null else ""


func _find_node_by_instance_id(id: int) -> Node:
	for e in _live:
		if is_instance_valid(e) and int(e.get("owner_id")) == id:
			var cand = e.get("owner_ref")
			if cand != null and is_instance_valid(cand):
				return cand
	return null
