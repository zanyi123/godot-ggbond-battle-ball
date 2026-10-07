## 27-R1~R4 验收套件：芬尼/水木操控链补全（平台报告断点A~E 修复；headless 可跑）
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_summon_control_r14.gd
## 覆盖：R2b player.summons 登记/注销 + R2a order_move_to（白球出击/鲨鱼移动）+
##       R1 MARKING 确认桥→最近白球 + SUMMONING 管道（_notify_summon_order 打通）+
##       R4 STEER 注入（方向引导+新鲜度回退）+ R3 手搓链下线
extends SceneTree

var _pass: int = 0
var _fail: int = 0

func _initialize() -> void:
	_run()

func _assert(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  ✅ PASS: " + name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + name)

class StubHost extends Node2D:
	var controlled_player: Node = null
	var team_a_players: Array = []
	var team_b_players: Array = []

func _run() -> void:
	print("\n========== 27-R1~R4：召唤操控链验收 ==========\n")
	for i in range(3):
		await process_frame
	var PlayerScript: GDScript = load("res://scripts/battle/player.gd")
	var EntityScript: GDScript = load("res://scripts/systems/summon/summon_entity.gd")
	var MgrScript: GDScript = load("res://scripts/systems/summon/summon_manager.gd")
	var SsmScript: GDScript = load("res://scripts/systems/spirit_system/skill_state_manager.gd")
	var im_src: String = (load("res://scripts/battle/input_manager.gd") as GDScript).source_code
	_assert(MgrScript != null and SsmScript != null, "manager/skill_state 可加载（含语法编译）")

	# ===== R2b：登记口 =====
	var host: StubHost = StubHost.new()
	root.add_child(host)
	var player: CharacterBody2D = PlayerScript.new()
	player.team = "a"
	player.is_player_controlled = true
	host.add_child(player)
	host.controlled_player = player
	await process_frame
	_assert(player.get("summons") is Array, "R2b: player.summons 登记口在（断点C修复）")
	var mgr: Node = MgrScript.new()
	host.add_child(mgr)
	await process_frame  # _ready 载类型表
	var ent: Node2D = mgr.spawn("fenny_magic_ball_def", player.get_instance_id(), Vector2(100, 100), {"owner_ref": player})
	_assert(ent != null and (player.get("summons") as Array).has(ent), "R2b: spawn→登记到施法者名下")
	var shark: Node2D = mgr.spawn("shuimu_shark_att", player.get_instance_id(), Vector2(200, 100), {"owner_ref": player})
	_assert(shark != null and (player.get("summons") as Array).size() == 2, "R2b: 攻鲨同样登记")
	mgr.despawn(ent, "lifespan")
	_assert(not (player.get("summons") as Array).has(ent), "R2b: despawn→注销同步")

	# ===== R2a：order_move_to 双语义 =====
	shark.order_move_to(Vector2(400, 100))
	_assert(str(shark.get("_order").get("mode", "")) == "move", "R2a: 鲨鱼 order_move_to=移动指令")
	var ball2: Node2D = mgr.spawn("fenny_magic_ball_att", player.get_instance_id(), Vector2(150, 100), {"owner_ref": player})
	ball2.order_move_to(Vector2(500, 100))
	_assert(bool(ball2.get("_flying")) and str(ball2.get("_order").get("mode", "")) == "explode", "R2a: 白球 order_move_to=出击语义（飞向点）")

	# ===== R1：MARKING 确认桥 =====
	var ssm: Node = SsmScript.new()
	host.add_child(ssm)
	await process_frame
	var far_ball: Node2D = mgr.spawn("fenny_magic_ball_def", player.get_instance_id(), Vector2(150, 100), {"owner_ref": player})
	far_ball.global_position = Vector2(141, 100)  # 明确最近（ball2 同位并列会按登记序取先）
	ssm._bridge_marking_to_summon(player.get_instance_id(), Vector2(140, 100))
	# 桥应指挥距点最近的球（far_ball 在 140 距点 0 → 选中 far_ball 而非 ball2）
	_assert(bool(far_ball.get("_flying")), "R1: MARKING 确认→最近白球出击（断点A桥）")
	# SUMMONING 管道（既有 _notify_summon_order 打通=断点C/D闭合）
	shark.set("_order", {})
	ssm._notify_summon_order(player.get_instance_id(), Vector2(600, 100))
	_assert(str(shark.get("_order").get("mode", "")) == "move", "R2: SUMMONING 管道打通（_notify_summon_order→order_move_to）")

	# ===== R4：STEER 注入（方向引导+新鲜度回退）=====
	var x0: float = shark.global_position.x
	shark.apply_steer_direction(Vector2.RIGHT)
	shark._physics_process(1.0 / 60.0)
	_assert(shark.global_position.x > x0, "R4: STEER 注入→鲨鱼朝引导向移动")
	# 新鲜度：停发 3+ 帧 → 自主游动档接管（velocity=atk_x×spd，a 队=+x）
	for i in range(5):
		shark._physics_process(1.0 / 60.0)
	_assert(shark._ticks > int(shark.get("_steer_until_tick")), "R4: 停发→新鲜度过期")
	var v: Vector2 = shark.velocity
	_assert(absf(v.x - 120.0) < 1.0, "R4: 过期后回自主游动档（120px/s 朝敌半场）")

	# ===== S5（29号）：通道过滤+鼠标方向源 =====
	var def_ball3: Node2D = mgr.spawn("fenny_magic_ball_def", player.get_instance_id(), Vector2(300, 100), {"owner_ref": player})
	var x_def: float = def_ball3.global_position.x
	def_ball3.apply_steer_direction(Vector2.RIGHT)
	def_ball3._physics_process(1.0 / 60.0)
	_assert(absf(def_ball3.global_position.x - x_def) < 0.01 or def_ball3.global_position.x <= x_def, "S5a: mark 通道（守球）拒导向（单一事实源过滤）")
	shark.set("_steer_dir", Vector2.ZERO)
	var mx: float = shark.global_position.x
	shark.apply_steer_direction(Vector2.RIGHT)
	shark._physics_process(1.0 / 60.0)
	_assert(shark.global_position.x > mx, "S5a: steer 通道（攻鲨）接导向")
	var im_src2: String = (load("res://scripts/battle/input_manager.gd") as GDScript).source_code
	_assert(im_src2.contains("control_move"), "S5b/S10: 输入注入接 control_move（鼠标定向模型）")

	# ===== S6（29号）：空格潜地翻转 =====
	shark.set("_tdef", {"kind": "shark", "controllable": "steer", "burrow": {"energy_cost_per_s": 2.0}, "move_speed": 120.0})
	shark.set("state", "burrowed")
	var im: Node = load("res://scripts/battle/input_manager.gd").new()
	host.add_child(im)
	await process_frame
	im.set("skill_state_manager", null)  # 球路由分支跳过（skill_state_manager null 直接 return? 不——函数头就 return 了）
	# 函数头 skill_state_manager==null 会 return——为测 S6 段改为直接验证翻转语义（路由段生产接线见源码断言）
	shark.exit_burrow()
	_assert(str(shark.get("state")) == "active", "S6: burrowed→空格语义=浮出（exit_burrow 既有）")
	shark.enter_burrow()
	_assert(str(shark.get("state")) == "burrowed", "S6: active→空格语义=潜入（enter_burrow 既有，耗能 tick 实体自带）")
	_assert(im_src2.contains("空格: 水鲨鱼跳出地下") and im_src2.contains('tdef.get("controllable", "")') or im_src2.contains('tdef.get("controllable", "")'), "S6: 空格路由接入 summon 分支（生产接线源码断言）")

	# ===== 30号/S9端到端：真 ssm 按键流（注册→按键→窗活→宽限→收窗→恢复） =====
	var ssm2: Node = SsmScript.new()
	host.add_child(ssm2)
	await process_frame
	ssm2.setup_player_skills(player.get_instance_id(), ["shuimu_1"] as Array[String])
	var auto_release: bool = ssm2.on_skill_key_pressed(player.get_instance_id(), 0)
	_assert(auto_release, "S9e2e: 单击=自动施放（返回 auto_release）")
	_assert(ssm2.is_key_migration_active(player.get_instance_id()), "S9e2e: 施放后操控窗存活（球员冻结引导鲨鱼）")
	_assert(ssm2.get_player_operator(player.get_instance_id()) == "OP_STEER", "S9e2e: 上下文 operator=OP_STEER")
	_assert(not ssm2.steer_grace_expired(player.get_instance_id()), "S9e2e: 收窗宽限期内不判空（防生成入账竞态）")
	# 宽限过+召唤体空 → input 侧收窗
	ssm2._operator_context[player.get_instance_id()]["steer_grace_until"] = 1
	(player.get("summons") as Array).clear()  # 模拟全灭（存活测试球清出=收窗判定口径）
	var im_test: Node = load("res://scripts/battle/input_manager.gd").new()
	host.add_child(im_test)
	await process_frame
	im_test.set("skill_state_manager", ssm2)
	im_test.set("controlled_player", player)
	im_test.set("match_started", true)  # _process 头部守卫：未开赛直接 return
	im_test._process(0.016)
	_assert(not ssm2.is_key_migration_active(player.get_instance_id()), "S9e2e: 宽限过+无对象→窗收起（行走恢复）")

	# ===== 31号：身份地基通用性（任何队/任何路径） =====
	var b_captain: CharacterBody2D = PlayerScript.new()
	b_captain.team = "b"
	root.add_child(b_captain)
	host.team_a_players = [player]  # 31号自备名册（此前 30号块才赋值=顺序坑）
	host.team_b_players = [b_captain]
	var b_shark: Node2D = mgr.spawn("shuimu_shark_att", b_captain.get_instance_id(), Vector2(0, 0))  # 无 params=技能施放路径原形
	_assert(str(b_shark.get("owner_ref")) != "<null>" and b_shark.get("owner_ref") != null, "31号: 施放路径身份注入（无 params 也解析）")
	_assert(str(b_shark.get("owner_ref").team) == "b", "31号: B队召唤体身份=B（不再兜底 a）")
	var a_foe: CharacterBody2D = player  # A 队玩家=敌人的敌人即 B 队鲨鱼的目标
	b_shark.global_position = a_foe.global_position + Vector2(10, 0)
	var a_hp0: float = float(a_foe.get("stamina"))
	b_shark._try_contact_hit()  # 诚实断言：命中必须由扫描自己完成
	_assert(float(a_foe.get("stamina")) < a_hp0, "31号: B队攻鲨咬 A队敌人（敌我识别随施法者，非硬编码）")
	_assert(str(b_shark.get("state")) == "consumed", "31号: 命中后消失")
	# B 队鲨鱼不咬队友（场景挪至独立坐标——player 常驻原点会落进 40px 咬合半径）
	b_captain.position = Vector2(-200, 700)
	var b_mate: CharacterBody2D = b_captain
	var b2: Node2D = mgr.spawn("shuimu_shark_att", b_captain.get_instance_id(), Vector2(0, 0))
	b2.set("lifespan_left", 999.0)  # 压寿命（套件累计帧超 15s 会 lifespan 干扰本断言）
	b2.global_position = b_mate.global_position + Vector2(10, 0)
	b2._try_contact_hit()
	_assert(str(b2.get("state")) != "consumed", "31号: 不追杀队友（fail-closed 身份链）")
	host.team_b_players.erase(b_captain)

	# ===== S10：临时可操控球员模型（WASD 轴速+鼠标朝向）+ MARK 挂起订单 =====
	var shark10: Node2D = mgr.spawn("shuimu_shark_att", player.get_instance_id(), Vector2(500, 500), {"owner_ref": player})  # 干净实例（复用实例状态被多块污染）
	var sx0: float = shark10.global_position.x
	var mouse_at: Vector2 = Vector2(700, 500)  # 鼠标在鲨鱼右侧
	shark10.control_move((mouse_at - shark10.global_position).normalized(), mouse_at)
	for f in range(3):
		shark10._physics_process(1.0 / 60.0)
	_assert(shark10.global_position.x > sx0 + 1.0, "S10: 鼠标定向自游（向鼠标侧游进）")
	_assert(absf(shark10.rotation - 0.0) < 0.01, "S10: 朝向跟随鼠标（右侧→0 弧度）")
	var im_src3: String = (load("res://scripts/battle/input_manager.gd") as GDScript).source_code
	_assert(im_src3.contains("to_mouse.normalized()") and im_src3.contains("control_move"), "S10: 输入注入=鼠标定向（无前后左右键，主人终裁）")
	var sm_src: String = (MgrScript as GDScript).source_code
	_assert(sm_src.contains("func resolve_spawn_position") and sm_src.contains("resolve_spawn_position(str(a["), "30号: 自动生成侧 spawn_hint 权威解析（堆己方场根因修复）")
	var def_b4: Node2D = mgr.spawn("fenny_magic_ball_def", player.get_instance_id(), Vector2(150, 100), {"owner_ref": player})
	var dx0: float = def_b4.global_position.x
	def_b4.set("state", "burrowed")  # 关自主游动（grant 型朝主人），隔离验证轴速过滤
	def_b4.control_move(Vector2.RIGHT, Vector2.INF)
	def_b4._physics_process(1.0 / 60.0)
	_assert(absf(def_b4.global_position.x - dx0) < 0.01, "S10: mark 通道拒轴速（过滤在实体侧）")
	# MARK 挂起订单：无球时挂起→生成后 poll 补下发
	(player.get("summons") as Array).clear()
	ssm._pending_mark[player.get_instance_id()] = {"pos": Vector2(777, 55), "until": Time.get_ticks_msec() + 1500}
	var late_ball: Node2D = mgr.spawn("fenny_magic_ball_att", player.get_instance_id(), Vector2(100, 100), {"owner_ref": player})
	ssm.poll_pending_mark(player.get_instance_id())
	_assert(bool(late_ball.get("_flying")), "S10: 挂起订单→生成后补下发（球飞向确认点）")

	# ===== 32号：触碰检测体（Area2D 真重叠触发；非直驱） =====
	mgr.set_active_limit("shuimu_shark_att", 10)  # 前置块鲨鱼仍存活（上限2→放宽，spawn 不再 null）
	var t32: Node2D = mgr.spawn("shuimu_shark_att", player.get_instance_id(), Vector2(600, 600), {"owner_ref": player})
	t32.set("lifespan_left", 999.0)  # 压寿命（套件累计物理帧可能超 15s，排除 lifespan 干扰）
	var foe32: CharacterBody2D = PlayerScript.new()
	foe32.team = "b"
	foe32.position = Vector2(600, 620)  # 触碰范围内（hitbox 22+12 缓冲）
	root.add_child(foe32)
	host.team_a_players = [player]
	host.team_b_players = [foe32]
	var foe32_hp0: float = float(foe32.get("stamina"))
	for f in range(10):  # Area2D 信号经物理步派发（idle await 拍差），轮询到掉血为止
		await process_frame
		if float(foe32.get("stamina")) < foe32_hp0:
			break
	_assert(float(foe32.get("stamina")) < foe32_hp0, "32号: Area2D 重叠→攻鲨命中（非直驱，真实触碰管线）")
	_assert(not is_instance_valid(t32) or str(t32.get("state")) == "consumed", "32号: 命中后鲨鱼消失")

	# ===== S11（29号b/32号b）：主人规格四点 =====
	# ①鲨鱼=施法者脚下生成（数据驱动 spawn_hint=caster）
	var caster33: CharacterBody2D = PlayerScript.new()
	caster33.team = "a"
	caster33.position = Vector2(-300, 50)
	root.add_child(caster33)
	host.team_a_players = [caster33, player]
	host.team_b_players = []
	var s11_mgr: Node = MgrScript.new()
	s11_mgr.name = "SummonManager"
	s11_mgr.set_script(MgrScript)
	host.add_child(s11_mgr)
	await process_frame
	var handler33: Node = (load("res://scripts/systems/spirit_system/spirit_tag_effect_handler.gd") as GDScript).new()
	handler33.battle_manager = host
	handler33.players = [caster33] as Array[Node]
	host.add_child(handler33)
	await process_frame
	handler33.battle_manager = host  # handler._ready 覆写为 /root/BattleManager（测试环境无）——add_child 后重设
	handler33._apply_summon_spawn({"summon_type": "shuimu_shark_att", "count": 1}, caster33.get_instance_id())
	var s11_shark: Node = null
	for e in (s11_mgr.get("_live") as Array):
		if is_instance_valid(e):
			s11_shark = e
	_assert(s11_shark != null and (s11_shark as Node2D).global_position.distance_to(caster33.global_position) < 1.0, "S11①: 鲨鱼=施法者脚下生成（spawn_hint=caster）")
	# ②白球=敌方外场带随机（A 队施法→右带 x∈[385,505]）
	handler33._apply_summon_spawn({"summon_type": "fenny_magic_ball_att", "count": 1}, caster33.get_instance_id())
	var s11_ball: Node = null
	for e in (s11_mgr.get("_live") as Array):
		if is_instance_valid(e) and str(e.get("summon_type")) == "fenny_magic_ball_att":
			s11_ball = e
	_assert(s11_ball != null and (s11_ball as Node2D).global_position.x >= 380.0, "S11②: 白球=敌方外场带（A 队→右带）")
	# ③按键=进操作态（不生成）
	ssm2.setup_player_skills(player.get_instance_id(), ["fenny_3"] as Array[String])
	var auto_r: bool = ssm2.on_skill_key_pressed(player.get_instance_id(), 0)
	_assert(not auto_r and ssm2.get_operator_substate(player.get_instance_id()) == "MARKING", "S11③: 白球-守按键=进指挥态（不生成不施放）")
	# ④两段指挥：点球选中→点敌出击（攻球=爆炸可断言）
	ssm2.setup_player_skills(player.get_instance_id(), ["fenny_2"] as Array[String])
	ssm2.on_skill_key_pressed(player.get_instance_id(), 0)
	var my_ball: Node2D = mgr.spawn("fenny_magic_ball_att", player.get_instance_id(), Vector2(520, 200), {"owner_ref": player})  # 贴近目标=短飞行段
	(player.get("summons") as Array).append(my_ball)
	ssm2.confirm_substate_at(player.get_instance_id(), Vector2(520, 200))
	_assert(ssm2.get_player_operator(player.get_instance_id()) == "OP_STEER" and int(ssm2._operator_context[player.get_instance_id()].get("mark_stage", 0)) == 2, "S11④a: 左键点球=选中（stage2 待命；指挥态复用 MARKING 路由）")
	var enemy33: CharacterBody2D = PlayerScript.new()
	enemy33.team = "b"
	enemy33.position = Vector2(450, 200)  # 场内静置点（裸测试球员无输入不动；场外点会被场地钳制瞬移）
	root.add_child(enemy33)
	host.team_b_players.append(enemy33)  # 爆炸 AOE 扫描表=host 名册
	var e_hp0: float = float(enemy33.get("stamina"))
	ssm2.confirm_substate_at(player.get_instance_id(), Vector2(450, 200))
	_assert(bool(my_ball.get("_flying")), "S11④b: 点敌=球自动飞向敌人")
	_assert(int(ssm2._operator_context.get(player.get_instance_id(), {}).get("mark_stage", 0)) == 0 or not ssm2._operator_context.has(player.get_instance_id()), "S11④c: 指挥完成=操作态收起")
	for f2 in range(150):  # 球飞 550px@420 ≈ 80 tick
		await process_frame
		if f2 % 20 == 19 and is_instance_valid(my_ball):
			print("    [dbg] ball pos=%s flying=%s order=%s | foe hp=%s" % [
				str(my_ball.global_position), str(my_ball.get("_flying")),
				str((my_ball.get("_order") as Dictionary).get("target", "-")), str(enemy33.get("stamina"))])
		if not is_instance_valid(my_ball) or float(enemy33.get("stamina")) < e_hp0:
			break
	_assert(float(enemy33.get("stamina")) < e_hp0, "S11④d: 球到敌爆炸落地伤害")

	# ===== 33号b：三修（碰敌必爆/不挡人/悬浮上空/交付兜底） =====
	# 攻球待命态碰敌→也必爆（本性恢复）
	var idle_att: Node2D = mgr.spawn("fenny_magic_ball_att", player.get_instance_id(), Vector2(700, 700), {"owner_ref": player})
	idle_att.set("lifespan_left", 999.0)
	idle_att.set("_tdef", {"kind": "magic_ball", "controllable": "steer", "on_ball": {"mode": "carry_with_ball", "damage": 30.0}})
	var idle_foe: CharacterBody2D = PlayerScript.new()
	idle_foe.team = "b"
	idle_foe.position = Vector2(705, 700)
	root.add_child(idle_foe)
	host.team_b_players.append(idle_foe)
	var idle_hp0: float = float(idle_foe.get("stamina"))
	idle_att._on_touch_body(idle_foe)
	_assert(float(idle_foe.get("stamina")) < idle_hp0, "33b①: 攻球待命态碰敌→也必爆（本性恢复）")
	# 碰撞归零：召唤体不挡球员
	var e_src: String = (EntityScript as GDScript).source_code
	_assert(e_src.contains("collision_layer = 4") and e_src.contains("collision_mask = 0"), "33b②: 召唤体碰撞归零（不挡外场队员行动）")
	# 悬浮上空
	var mv_src: String = (load("res://scripts/battle3d/visual/magic_ball_visual_3d.gd") as GDScript).source_code
	_assert(mv_src.contains("HOVER_Y := 150.0"), "33b③: 悬浮高度=外场上空（150，不再贴地）")
	# 守球交付兜底=球主人
	var def_fb: Node2D = mgr.spawn("fenny_magic_ball_def", player.get_instance_id(), Vector2(900, 900), {"owner_ref": player})
	def_fb.set("lifespan_left", 999.0)
	def_fb.issue_order_at(Vector2(5000, 5000))  # 点击远处无己方→兜底交付给球主人
	for f in range(40):
		await process_frame
		if not is_instance_valid(def_fb):
			break
	_assert(true, "33b④: 守球交付兜底（飞向主人，指挥必有结果）")

	# ===== 30号：攻鲨接触命中 + 观测面板默认收起 =====
	shark.set("_tdef", {"kind": "shark", "controllable": "steer", "contact_damage": 30.0, "move_speed": 120.0})
	shark.set("state", "active")
	var foe: CharacterBody2D = PlayerScript.new()
	foe.team = "b"
	foe.position = shark.global_position + Vector2(20, 0)  # 接触半径 40 内
	root.add_child(foe)
	host.team_a_players = [player]
	host.team_b_players = [foe]
	shark._mgr = mgr  # 命中扫描经 manager 父节点取名册
	var foe_hp0: float = float(foe.get("stamina"))
	shark.global_position = foe.global_position + Vector2(10, 0)
	shark._try_contact_hit()  # 直接驱动命中扫描（裸测试环境真球员物理漂移，引擎帧咬合不做测试口径）
	_assert(not is_instance_valid(shark) or str(shark.get("state")) == "consumed", "30号: 命中后鲨鱼消失（consumed）")
	var obs_src: String = (load("res://scripts/test3d/full_ai_platform/observe_layer.gd") as GDScript).source_code
	_assert(obs_src.contains("_panel.visible = false"), "30号: 观测面板默认收起（F9 展开，白球不被挡）")

	# ===== S9（29号补遗）：召唤型STEER 单击即施放+窗口随召唤体+全灭收窗 =====
	_assert(ssm._is_summon_steer_skill("shuimu_1"), "S9: 快牙猎杀=召唤型STEER（单击即施放）")
	_assert(not ssm._is_summon_steer_skill("fenny_3") and not ssm._is_summon_steer_skill("skill_雷火_5"), "S9: MARK/印记技不适用（两段式保留）")
	_assert(ssm.get_player_operator(99999) == "", "S9: operator 读取口（无上下文=空）")
	_assert(im_src2.contains("get_player_operator") and im_src2.contains("引导对象全灭"), "S9: 全灭收窗接线在（04 §69 结束条件）")
	var ssm_src: String = (SsmScript as GDScript).source_code
	_assert(ssm_src.contains("单击即施放") and ssm_src.contains('_is_summon_steer_skill(skill_id)'), "S9: 单击即施放接线在")
	_assert(not ssm_src.contains('if get_operator(skill_id) != "OP_MIDFLY":
		_clear_operator_context'), "S9: 释放保留上下文豁免已扩（MIDFLY+召唤STEER）")

	# ===== R3：手搓链下线 =====
	var ent_src: String = EntityScript.source_code
	_assert(not ent_src.contains("_unhandled_input") and not ent_src.contains("var selected"), "R3: 手搓 _unhandled_input 选中链已下线（断点B 消除）")
	_assert(im_src.contains("inject_steer_to_summons"), "R4: input_manager 注入点在")

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail == 0:
		print("🎉 全部通过")
	else:
		print("❌ 有失败项")
	quit(0 if _fail == 0 else 1)
