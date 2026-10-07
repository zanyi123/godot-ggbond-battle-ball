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

## ===== 玩家操控链（1001 主人实测补全：选中→索敌→飞行→结算→消失）=====
## 攻球：选中→左键点目标→锁定最近敌人飞行→爆炸（范围伤害）→消失；
## 守球：选中→左键点目标→飞向最近队友→道具交付→消失。右键=取消选中。
var _order: Dictionary = {}
var _steer_dir: Vector2 = Vector2.ZERO      # 27-R4 STEER 引导（帧新鲜度守卫）
var _steer_until_tick: int = 0
var _face_pos: Vector2 = Vector2.INF        # 29-S10 鼠标悬停朝向
var _face_fresh: bool = false
var _flying: bool = false
var _ticks: int = 0
const FLY_SPEED := 420.0


func setup(type_def: Dictionary, owner: int, params: Dictionary) -> void:
	_tdef = type_def
	_params = params
	owner_id = owner
	owner_ref = params.get("owner_ref", null)   # 施法者注入（耗能 tick/自动生成落点依赖）
	skill_id = str(params.get("skill_id", ""))
	lifespan_left = float(type_def.get("lifespan", 20.0))
	_build_hitbox(str(type_def.get("hitbox", "circle:18")))
	_build_touch_area(str(type_def.get("hitbox", "circle:18")))
	if is_inside_tree():
		_build_2d_visual()
	_on_spawned()


func _build_hitbox(spec: String) -> void:
	# 33号b（主人报"完全限制外场队员的行动"）：召唤体=空中/逻辑单位——碰撞归零
	# （不与球员/球互撞=不挡路；触碰检测走 Area2D 层位，见 _build_touch_area）
	collision_layer = 4
	collision_mask = 0
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


func issue_order_at(click_world: Vector2) -> void:
	var mode := str(_tdef.get("on_ball", {}).get("mode", ""))
	if mode == "carry_with_ball":
		var enemy := _nearest_char_near(click_world, 150.0, true)
		_order = {"mode": "explode", "target": enemy.global_position if enemy != null else click_world}
	else:
		var ally := _nearest_char_near(click_world, 240.0, false)
		if ally == null and owner_ref != null and is_instance_valid(owner_ref):
			ally = owner_ref  # 33号b 交付兜底=球主人（原作"操控球飞向自己获得道具"）——指挥必有可见结果
		_order = {"mode": "grant", "target": ally.global_position if ally != null else click_world, "ally": ally}
	_flying = true
	print("[Summon] 🎯 出击: %s → %s" % [str(_tdef.get("on_ball", {}).get("mode", "")), str(_order.get("target", ""))])


## 27-R2（19A S5 拼图）：召唤体移动指令——操1 项7 SUMMONING/子态确认桥统一入口
## 白球=出击/交付语义（复用 issue_order_at 点击结算）；鲨鱼=移动指令（自主游动让位，到达恢复）
func order_move_to(pos: Vector2) -> void:
	if state != "active" and state != "controlled":
		return
	if str(_tdef.get("kind", "")) == "magic_ball":
		issue_order_at(pos)
		return
	_order = {"mode": "move", "target": pos}


## 29-S10（2026-10-06 主人裁定模型）：召唤体=**临时可操控球员**——WASD 轴向直开（同球员移动），
## 鼠标悬停只定朝向；操控窗内每帧刷新，停发 3 帧回自主游动档
## 通道过滤=单一事实源：仅 controllable="steer"（白球-攻/快牙猎杀系）；mark/auto 拒绝
func control_move(axis: Vector2, face_pos: Vector2) -> void:
	if str(_tdef.get("controllable", "")) != "steer":
		return
	_steer_dir = axis.limit_length(1.0)
	_face_pos = face_pos
	_steer_until_tick = _ticks + 3
	_face_fresh = true

## 兼容旧调用（既有套件）：方向向量口径转发
func apply_steer_direction(dir: Vector2) -> void:
	control_move(dir, Vector2.INF)


func _nearest_char_near(pos: Vector2, radius: float, want_enemy: bool) -> Node:
	var bm: Node = _mgr.get_parent() if _mgr != null and _mgr.get_parent() != null else null
	if bm == null or bm.get("team_a_players") == null:
		return null
	var my_team := str(owner_ref.team) if owner_ref != null and is_instance_valid(owner_ref) else "a"
	var best: Node = null
	var best_d: float = radius
	for p in (bm.team_a_players + bm.team_b_players):
		if p == null or not is_instance_valid(p) or p.is_defeated:
			continue
		if (str(p.team) != my_team) != want_enemy:
			continue
		var d: float = float(p.global_position.distance_to(pos))
		if d <= best_d:
			best_d = d
			best = p
	return best


func _arrive() -> void:
	match str(_order.get("mode", "")):
		"explode":
			_explode_now()
		"grant":
			_grant_now()
		_:
			_consume("used")


## 33号c：施法者是否人类操控（分流：人类球=储备听指挥 / AI 球=自动行为平替）
func _caster_is_human() -> bool:
	return owner_ref != null and is_instance_valid(owner_ref) and bool(owner_ref.get("is_player_controlled"))


## 31号：己方队伍解析链（owner_ref→manager 名册兜底→空串=fail-closed 不猜队）
## 根因修复：此前 my_team 兜底 "a"——B 队召唤体身份为空时追杀自己队友（主人报"分不清敌我"）
func _resolve_my_team() -> String:
	if owner_ref != null and is_instance_valid(owner_ref):
		return str(owner_ref.team)
	if _mgr != null and is_instance_valid(_mgr) and _mgr.has_method("_team_of"):
		return str(_mgr._team_of(owner_id))
	return ""


## 30号：攻鲨接触命中——触碰范围内敌方→伤害+消失（类型表 contact_damage；fail-closed 无字段不命中）
func _try_contact_hit() -> void:
	var dmg: float = float(_tdef.get("contact_damage", 0.0))
	if dmg <= 0.0:
		return
	var bm: Node = _mgr.get_parent() if _mgr != null and _mgr.get_parent() != null else null
	if bm == null or bm.get("team_a_players") == null:
		return
	var my_team := _resolve_my_team()
	if my_team.is_empty():
		return  # 身份不齐不猜队（fail-closed）
	var attacker: Node = owner_ref if owner_ref != null and is_instance_valid(owner_ref) else null
	for p in (bm.team_a_players + bm.team_b_players):
		if p == null or not is_instance_valid(p) or p.is_defeated:
			continue
		if str(p.team) == my_team:
			continue
		if float(p.global_position.distance_to(global_position)) <= 40.0:
			p.take_damage(dmg, attacker, str(_params.get("element", "")))
			print("[Summon] 🦈 攻鲨命中: %s 受 %.0f 伤害，鲨鱼消失" % [str(p.char_data.get("name", "?")), dmg])
			_consume("hit")
			return


func _explode_now() -> void:
	var dmg: float = float(_tdef.get("on_ball", {}).get("damage", 30.0))
	var emp = _params.get("empower", {})
	if emp is Dictionary:
		dmg *= float(emp.get("damage_mult", 1.0))
	var bm: Node = _mgr.get_parent() if _mgr != null and _mgr.get_parent() != null else null
	var my_team := _resolve_my_team()
	if my_team.is_empty():
		_consume("exploded")
		return  # 身份不齐不猜队（fail-closed）
	var attacker: Node = owner_ref if owner_ref != null and is_instance_valid(owner_ref) else null
	var hits := 0
	# 33号（原作逐字）：能量强化态爆炸→敌方障碍立刻消失
	var emp2: Dictionary = _params.get("empower", {}) if _params.get("empower", {}) is Dictionary else {}
	if bm != null and not emp2.is_empty():
		var om: Node = bm.get_node_or_null("ObstacleManager") if bm.has_node("ObstacleManager") else null
		if om != null:
			for obs in (om.obstacles as Array).duplicate():
				if is_instance_valid(obs) and float(obs.global_position.distance_to(global_position)) <= 90.0:
					obs._destroy()
					print("[Summon] 💥 强化爆炸摧毁障碍（90 范围内；敌我 M1 简约不区分）")
	# 差距3（同原作）：非强化爆炸对障碍也可破（伤害消耗）——保持既有不扩
	if bm != null and bm.get("team_a_players") != null:
		for p in (bm.team_a_players + bm.team_b_players):
			if p == null or not is_instance_valid(p) or p.is_defeated:
				continue
			if str(p.team) == my_team:
				continue
			if float(p.global_position.distance_to(global_position)) <= 90.0:
				p.take_damage(dmg, attacker, str(_params.get("element", "")))
				hits += 1
	print("[Summon] 💥 白球爆炸: 伤害%0.f 命中%d" % [dmg, hits])
	_consume("exploded")


func _grant_now() -> void:
	var ally = _order.get("ally", null)
	var pool = _tdef.get("on_ball", {}).get("item_pool", [])
	if ally != null and is_instance_valid(ally) and pool is Array and not (pool as Array).is_empty():
		var granter: Node = get_tree().get_first_node_in_group("battle_item_granters")
		var item_id: String = str((pool as Array)[_ticks % (pool as Array).size()])
		if granter != null and granter.has_method("grant_battle_item"):
			granter.grant_battle_item(ally, item_id)
			print("[Summon] 🎁 道具交付: %s ← %s" % [str(ally.char_data.get("name", "?")), item_id])
	_consume("delivered")


func _physics_process(delta: float) -> void:
	if state == "consumed":
		return
	_ticks += 1
	# 玩家操控飞行（1001 主人令"球的飞行过程要出来"）：直奔指令点，到达即结算并消失
	if _flying:
		var to: Vector2 = (_order.get("target", global_position) as Vector2) - global_position
		if to.length() <= 36.0:
			_arrive()
			return
		velocity = to.normalized() * FLY_SPEED
		move_and_slide()
		return
	# 33号：快道增益（原作"水鲨鱼在路径上耗能减少、速度加快"）——速度乘区随所在快道
	var spd: float = float(_tdef.get("move_speed", 120.0))
	var pb: Dictionary = _path_buffs_at(global_position)
	if not pb.is_empty():
		spd *= float(pb.get("speed_mult", 1.0))
	var spd_mult: float = pb.get("speed_mult", 1.0) if pb.is_empty() == false else 1.0
	# 29-S10：受控=临时可操控球员（鼠标定向自游；松开轴=原地停等下一段指令；朝向随鼠标）
	if _ticks <= _steer_until_tick:
		velocity = _steer_dir * spd
		if velocity != Vector2.ZERO:
			move_and_slide()
		if _face_fresh and _face_pos != Vector2.INF:
			var face_v: Vector2 = _face_pos - global_position
			if face_v.length_squared() > 1.0:
				rotation = face_v.angle()
		return
	elif str(_order.get("mode", "")) == "move":
		# 27-R2：移动指令（操1 项7 SUMMONING 点击/桥接下发）
		var to_m: Vector2 = (_order.get("target", global_position) as Vector2) - global_position
		if to_m.length() <= 24.0:
			_order = {}
		else:
			velocity = to_m.normalized() * float(_tdef.get("move_speed", 120.0))
			move_and_slide()
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
		# 33号c：白球行为分流——AI 施法者=自动行为平替（自游攻敌/飞向主人交付）；
		# 人类施法者=储备悬停只听指挥（两段点击）。鲨鱼不受此分流（auto 守鲨待机语义保留）
		if kind == "magic_ball" and not _caster_is_human():
			var ball_mode := str(_tdef.get("on_ball", {}).get("mode", ""))
			var mb_spd: float = float(_tdef.get("move_speed", 140.0)) * spd_mult
			if ball_mode == "carry_with_ball":
				velocity = Vector2(atk_x * mb_spd, 0.0)
				move_and_slide()
			elif ball_mode == "grant_item" and owner_ref != null and is_instance_valid(owner_ref):
				var to_owner: Vector2 = owner_ref.global_position - global_position
				if to_owner.length() > 30.0:
					velocity = to_owner.normalized() * mb_spd
					move_and_slide()
		elif kind == "shark" and ctrl != "auto":
			velocity = Vector2(atk_x * spd, 0.0)
			move_and_slide()
	# 30号（2026-10-06 主人报"水鲨鱼触碰敌人没造成伤害消失"）：攻鲨接触命中——
	# steer 通道鲨鱼在场态触碰敌方→伤害+自毁消失（原作=单独操控进攻造成伤害；
	# 守鲨 auto/融合判定不适用；burrowed 潜地态不命中）
	if state == "active" and str(_tdef.get("kind", "")) == "shark" and str(_tdef.get("controllable", "")) == "steer":
		_try_contact_hit()

	# 寿命递减（固定步长确定性；耗尽→注销）
	lifespan_left -= delta
	if lifespan_left <= 0.0:
		_consume("lifespan")
		return
	# 潜地耗能 tick（快牙系：额外耗能维持；能量尽→自动浮出）
	if state == "burrowed":
		var cost: float = float(_tdef.get("burrow", {}).get("burrow_energy_cost_per_s", 0.0)) if _tdef.get("burrow", {}) is Dictionary else 0.0
		var pb2: Dictionary = _path_buffs_at(global_position)
		if not pb2.is_empty():
			cost *= float(pb2.get("energy_cost_mult", 1.0))  # 33号：快道上潜地耗能减少（原作）
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


## ===== 32号：触碰检测体（此前 F1 检测体未接线=球/人碰到召唤体零反应——主人实测"触碰不爆炸/拾取无效果"）=====
## Area2D 覆盖球(物理层2)+球员(物理层1)，进入即分发 _on_touch_body；burrowed 潜地态不响应
func _build_touch_area(hit_spec: String) -> void:
	var parts := hit_spec.split(":")
	var radius: float = float(parts[1]) if parts[0] == "circle" and parts.size() > 1 else 22.0
	var area := Area2D.new()
	area.name = "TouchArea"
	area.collision_layer = 0
	area.collision_mask = 1 | 2 | 4  # 球员(1)+球(2)+召唤体(4)
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius + 12.0
	cs.shape = shape
	area.add_child(cs)
	area.body_entered.connect(_on_touch_body)
	add_child(area)


func _on_touch_body(body: Node) -> void:
	if state != "active" and state != "controlled":
		return  # 潜地/已消耗不响应
	if body == null or not is_instance_valid(body):
		return
	var is_player: bool = body.get("team") != null and str(body.get("team")) in ["a", "b"]
	var kind := str(_tdef.get("kind", ""))
	if kind == "shark":
		if is_player:
			var my_team := _resolve_my_team()
			if not my_team.is_empty() and str(body.get("team")) != my_team and float(_tdef.get("contact_damage", 0.0)) > 0.0:
				body.take_damage(float(_tdef.get("contact_damage")), owner_ref if owner_ref != null and is_instance_valid(owner_ref) else null, str(_params.get("element", "")))
				print("[Summon] 🦈 攻鲨命中: %s 受 %.0f 伤害，鲨鱼消失" % [str(body.char_data.get("name", "?")) if body.get("char_data") != null else "?", float(_tdef.get("contact_damage"))])
				_consume("hit")
			return
		# 球触碰（融球/停球按类型表分发）；障碍等非球体守卫（ball 特征=is_active 成员）
		if body.get("is_active") != null:
			on_ball_proximity(body)
		return
	if kind == "magic_ball":
		var mode := str(_tdef.get("on_ball", {}).get("mode", ""))
		var caster_is_human: bool = owner_ref != null and is_instance_valid(owner_ref) and bool(owner_ref.get("is_player_controlled"))
		# 33号c 分流（主人裁定模型）：人类施法者的球=储备待命只听指挥（两段点击）；
		# AI 施法者的球=自动行为平替（19A 尾款落地前的 AI 操控代偿）
		if not caster_is_human:
			if mode == "carry_with_ball" and is_player and str(body.get("team")) != str(owner_ref.team if owner_ref != null and is_instance_valid(owner_ref) else ""):
				_explode_now()
				return
			if body.get("is_active") != null:
				on_ball_proximity(body)
			return
		# 人类球：攻球碰敌必爆（本性，待命/飞行均爆）
		if mode == "carry_with_ball" and is_player:
			if owner_ref != null and is_instance_valid(owner_ref) and str(body.get("team")) != str(owner_ref.team):
				_explode_now()
			return
		# 人类守球：仅指挥飞抵结算（触碰不结算=储备语义）；飞行中触碰→交付给触碰者
		if _flying and mode == "grant_item":
			var granter: Node = get_tree().get_first_node_in_group("battle_item_granters") if get_tree() else null
			var pool = _tdef.get("on_ball", {}).get("item_pool", [])
			if granter != null and granter.has_method("grant_battle_item") and pool is Array and not (pool as Array).is_empty():
				granter.grant_battle_item(body, str((pool as Array)[0]))
				print("[Summon] 🎁 道具交付(触碰): %s ← %s" % [str(body.char_data.get("name", "?")) if body.get("char_data") != null else "?", str((pool as Array)[0])])
			_consume("delivered")
		return


## 33号：来球元素推导（attacker spirit → 数据表；查不到=空=fail-closed 不误瓦解）
func _incoming_ball_element(ball: Node) -> String:
	var att = ball.get("attacker_player") if ball.get("attacker_player") != null else null
	if att == null or not is_instance_valid(att):
		return ""
	var sid: String = str(att.get("spirit_id") if att.get("spirit_id") != null else "")
	if sid.is_empty():
		return ""
	var dm: Node = Engine.get_main_loop().root.get_node_or_null("DataManager") if Engine.get_main_loop() != null else null
	if dm != null:
		var sd: Dictionary = dm.get_spirit_by_id(sid)
		return str(sd.get("element", ""))
	return ""


## 33号：快道增益读取（所在能量快道的 path_buffs；不在道上=空）
func _path_buffs_at(pos: Vector2) -> Dictionary:
	if _mgr == null or not is_instance_valid(_mgr):
		return {}
	var bm: Node = _mgr.get_parent() if _mgr.get_parent() != null else null
	var zm: Node = bm.get("field_zone_manager") if bm != null and bm.get("field_zone_manager") != null else null
	if zm == null:
		return {}
	for zone in zm.zones:
		if is_instance_valid(zone) and int(zone.get("zone_type")) == 6 and zone.contains_point(pos):
			return zone.get("path_buffs", {}) if zone.get("path_buffs", {}) is Dictionary else {}
	return {}


## 球接近分发（实体→球交互入口；ball 走既有公开口，模式按类型表 on_ball.mode）
## 由 F1 球检测体（Area2D 子节点）调用于球进入时；骨架阶段先支持 intercept/grant 两模式
func on_ball_proximity(ball: Node) -> void:
	if state != "active" and state != "controlled":
		return
	var on_ball: Dictionary = _tdef.get("on_ball", {}) if _tdef.get("on_ball", {}) is Dictionary else {}
	var mode := str(on_ball.get("mode", ""))
	match mode:
		"intercept":
			# 33号（原作逐字）：带雷火系技能的决竞球进攻→防御鲨瞬间瓦解（球不受阻）；
			# 限度内让球停下；超限改敌方球进攻路线（鲨存续至寿命）
			var weak: String = str(on_ball.get("weak_to_element", ""))
			var bel: String = _incoming_ball_element(ball)
			if weak != "" and bel == weak:
				print("[Summon] ⚡ 撕咬被雷火系瞬间瓦解")
				_consume("broken")
				return
			var stops: int = int(_params.get("stop_count", 0)) + 1
			_params["stop_count"] = stops
			var limit: int = int(on_ball.get("stop_limit", 2))
			var bus = _bus()
			if stops <= limit:
				if ball.has_method("get") and ball.get("is_active") != null:
					ball.set("is_active", false)
				if bus:
					bus.emit_event(bus.GameEvent.BALL_FORCED_CONTROL, {"ball": ball, "by_player": owner_ref, "mode": "stop"})
			else:
				# 超限改线：球沿远离鲨鱼方向继续飞
				var away: Vector2 = (ball.global_position - global_position).normalized()
				if ball.has_method("get"):
					ball.set("ball_direction", away)
					ball.set("is_active", true)
				if bus:
					bus.emit_event(bus.GameEvent.BALL_FORCED_CONTROL, {"ball": ball, "by_player": owner_ref, "mode": "deflect"})
				print("[Summon] 撕咬超限: 改球路线")
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
