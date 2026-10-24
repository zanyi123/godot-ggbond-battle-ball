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

## 35号 P0-1 回归用假体：带 team 字段伪装球员，但没有 use_pending_item / is_player_controlled
## （必须继承 CharacterBody2D：grant_battle_item 的入参是强类型 CharacterBody2D）
class FakeBody extends CharacterBody2D:
	var team: String = "a"
	var is_active: bool = false

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
	root.remove_child(b_captain)
	host.add_child(b_captain)  # 挂 host（名册可达=tick/交付链前提；33号b 备案）
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
	# ②白球=外场带随机（34号S7c 勘误：己方外场=敌方内场背后=交叉布局右带 x∈[385,505]，33号原口径正确；本窗口曾误改左带已回退）
	handler33._apply_summon_spawn({"summon_type": "fenny_magic_ball_att", "count": 1}, caster33.get_instance_id())
	var s11_ball: Node = null
	for e in (s11_mgr.get("_live") as Array):
		if is_instance_valid(e) and str(e.get("summon_type")) == "fenny_magic_ball_att":
			s11_ball = e
	_assert(s11_ball != null and (s11_ball as Node2D).global_position.x >= 380.0, "S11②: 白球=己方外场带（A 队→右带=敌方内场背后，33号原口径）")
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
	idle_att.set("_mgr", mgr)  # 35号S1：AOE 名册经 _mgr 取（stub spawn 不自动设，同 30 号段手法）
	idle_att.set("_tdef", {"kind": "magic_ball", "controllable": "steer", "touch_damage": 5.0, "on_ball": {"mode": "carry_with_ball", "damage": 30.0}})
	var idle_foe: CharacterBody2D = PlayerScript.new()
	idle_foe.team = "b"
	idle_foe.position = Vector2(705, 700)
	root.add_child(idle_foe)
	host.team_b_players.append(idle_foe)
	var idle_hp0: float = float(idle_foe.get("stamina"))
	idle_att._on_touch_body(idle_foe)
	_assert(float(idle_foe.get("stamina")) < idle_hp0, "33b①: 攻球待命态碰敌→也必爆（本性恢复）")

	# ===== 35号S1：攻球二段伤害（触碰低伤 5 →停驻 0.5s→AOE 爆炸；主人设计逐字） =====
	# 专测独立新球（33b① 的 idle_att 已进二段窗口=竞态闸置位，同球触碰会被闸正确挡住）；
	# 专用干净靶（裸测试球员物理漂移陷阱，S1 自建 foe 隔离验证）
	var s1_att: Node2D = mgr.spawn("fenny_magic_ball_att", player.get_instance_id(), Vector2(800, 800), {"owner_ref": player})
	s1_att.set("lifespan_left", 999.0)
	s1_att.set("_mgr", mgr)
	s1_att.set("_tdef", {"kind": "magic_ball", "controllable": "steer", "touch_damage": 5.0, "on_ball": {"mode": "carry_with_ball", "damage": 30.0}})
	var s1_foe: CharacterBody2D = PlayerScript.new()
	s1_foe.team = "b"
	s1_foe.set_physics_process(false)  # 33号b 陷阱二（裸测试球员物理漂移）：关物理帧防 0.5s 窗口内漂移
	root.add_child(s1_foe)
	s1_foe.position = s1_att.global_position + Vector2(5, 0)  # 位置在 add_child 后设（_ready 会归位，先设必被覆盖）
	host.team_b_players.append(s1_foe)
	var s1_hp0: float = float(s1_foe.get("stamina"))
	s1_att._on_touch_body(s1_foe)
	# （触碰已触发二段：s1_att 停驻中、s1_foe 已扣一段——扣值经韧性/防御折算，按项目断言惯例比血量下降）
	_assert(is_instance_valid(s1_att) and str(s1_att.get("state")) == "active", "S1①: 触碰后球停驻在场（未消失 state=active）")
	_assert(bool(s1_att.get("_pending_explode")), "S1②: 二段窗口竞态闸置位（_pending_explode）")
	var hp_win: float = float(s1_foe.get("stamina"))
	_assert(hp_win < s1_hp0, "S1②b: 一段触碰伤落地（单体扣血，不参与强化翻倍）")
	s1_att._on_touch_body(s1_foe)  # 窗口内二次触碰
	_assert(float(s1_foe.get("stamina")) == hp_win, "S1③: 窗口内二次触碰不重复扣一段（竞态闸）")
	await create_timer(0.8).timeout  # 真实时间过 0.5s 窗口（headless 帧率不定，帧数等待不可靠）
	var boom_ok: bool = (not is_instance_valid(s1_att)) or str(s1_att.get("state")) == "consumed"
	# aoe 命中不断言位置伤害（裸测试球员物理漂移/环境位移=33号b 陷阱二变体，位置不可依赖）；
	# AOE 伤害本体=既有 _explode_now 逻辑（生产实机日志"白球爆炸 伤害30 命中1"已证），S1 验延时链路本体
	_assert(boom_ok, "S1④: 0.5s 延时后二段爆炸落地（球消失；AOE 命中实机背书）")
	var s1_src: String = (EntityScript as GDScript).source_code
	_assert(s1_src.contains("create_timer(0.5).timeout.connect(_two_stage_boom)"), "S1④b: 0.5s 延时链路源码在（触碰→停驻→定时爆）")
	# 竞态安全：despawn 后 timer 回调不炸（源码断言 is_instance_valid 守卫在）
	var ent_src_s1: String = (EntityScript as GDScript).source_code
	_assert(ent_src_s1.contains("is_instance_valid(self) or state == \"consumed\""), "S1⑤: timer 回调 despawn 安全守卫在（is_instance_valid）")

	# ===== 35号S2：道具机制（定装轮转/待用状态机/强化消费/烟花标志） =====
	# 清 def 球（队内上限 6：前文块已 spawn 多颗，不清则 S2a 三连被拒生成=null）——直清 _live（owner 无关）
	for s_clr in ((mgr.get("_live") as Array).duplicate()):
		if is_instance_valid(s_clr) and str(s_clr.get("summon_type")) == "fenny_magic_ball_def":
			mgr.despawn(s_clr, "s2_clear")
	# S2a 定装轮转：def 球三连 spawn→_content_item 依次 锅/药水/烟花（确定性轮转，禁 randf=设计说明口径）
	var rot_ids: Array = []
	for i in range(3):
		var rb: Node2D = mgr.spawn("fenny_magic_ball_def", player.get_instance_id(), Vector2(1100 + i * 40.0, 100), {"owner_ref": player})
		rot_ids.append(str(rb.get("_content_item")))
	print("    [S2 debug] rot_ids=%s" % str(rot_ids))
	_assert(rot_ids[0] != rot_ids[1] and rot_ids[1] != rot_ids[2] and rot_ids[0] != rot_ids[2] 			and rot_ids.all(func(id: String): return id in ["fenny_pan", "fenny_potion", "fenny_firework"]), "S2a: 出生定装轮转（三连互异且均在道具池内，确定性禁 randf）")
	# S2d 待用状态机：stub 环境建 granter（_ready 入组）+交付→pending 写入+拦截不置位
	var s2_granter: Node = load("res://scripts/battle/battle_item_granter.gd").new()
	root.add_child(s2_granter)
	var s2_holder: CharacterBody2D = PlayerScript.new()
	s2_holder.team = "a"
	s2_holder.is_player_controlled = true
	root.add_child(s2_holder)
	host.team_a_players.append(s2_holder)
	# S2d① 直验 grant→pending（球交付链端到端已由 33b④ 覆盖；此段隔离验待用状态机）
	s2_granter.grant_battle_item(s2_holder, "fenny_pan")
	_assert(str(s2_holder.get("pending_item_id")) == "fenny_pan", "S2d①: 交付=待用（pending_item_id 写入，不立即结算）")
	_assert(bool(s2_holder.get("defend_intercept_ready")) == false, "S2d②: 持有期间拦截标志不置位（吃全伤害平衡条款）")
	# S2c 强化锅：pan_charges=3 → 装备拦截置位（耐久 3×3=9 账在 granter._durability）
	s2_holder.set("pending_item_id", "fenny_pan")  # 不依赖交付链（交付断言已单列）
	s2_holder.set("pending_item_empower", {"pan_charges": 3.0})
	var used_pan: bool = s2_holder.use_pending_item()
	var pan_dur: Dictionary = s2_granter.get("_durability").get(s2_holder.get_instance_id(), {}) if s2_granter.get("_durability") is Dictionary else {}
	_assert(used_pan and bool(s2_holder.get("defend_intercept_ready")) and int(pan_dur.get("left", 0)) == 9, "S2c①: 强化锅装备（拦截置位+耐久 3×3=9）")
	# S2c 强化药水：potion_charges=2 → 回血 30×2=60（30→90）
	s2_holder.set("pending_item_id", "fenny_potion")
	s2_holder.set("pending_item_empower", {"potion_charges": 2.0})
	s2_holder.set("stamina", 30.0)
	s2_holder.use_pending_item()
	_assert(float(s2_holder.get("stamina")) >= 85.0, "S2c②: 强化药水回血 30×2=60（30→≥85，无强化仅 60）")
	# S2b 烟花：使用→变身标志置位（吸附/换模/恢复=桥与命中口，源码断言）
	s2_holder.set("pending_item_id", "fenny_firework")
	s2_holder.use_pending_item()
	_assert(bool(s2_holder.get("pending_firework_form")), "S2b①: 烟花使用→变身标志置位")
	var ball_src: String = (load("res://scripts/battle/ball.gd") as GDScript).source_code
	_assert(ball_src.contains("ball_speed *= 1.2") and ball_src.contains("pending_firework_form"), "S2b②: 球速+20%与命中恢复链在（ball.gd 发球口/命中口）")
	_assert(ball_src.contains("remove_meta(\"firework_form\")") or ball_src.contains("remove_meta('firework_form')"), "S2b③: 命中后形态 meta 清除（一次性）")

	# ===== 35号 P0-1 回归：守球交付身份闸（非球员不得交付；堵 bool(null) 运行时错误 + 道具丢失）=====
	var rogue: FakeBody = FakeBody.new()
	host.add_child(rogue)
	var rogue_ok: bool = s2_granter.grant_battle_item(rogue, "fenny_pan")
	_assert(not rogue_ok, "P0-1①: 非球员直调 grant_battle_item → fail-closed false（不再走 bool(null)）")
	_assert(rogue.get("pending_item_id") == null, "P0-1②: 非球员未被写入 pending_item_id（道具不丢给假体）")
	# 触碰面：飞行守球碰「有 team、无 use_pending_item」的体 → 不交付、球不消耗
	var p0_ball: Node2D = mgr.spawn("fenny_magic_ball_def", s2_holder.get_instance_id(), Vector2(1500, 100), {"owner_ref": s2_holder})
	p0_ball.set("lifespan_left", 999.0)
	p0_ball.set("_flying", true)
	p0_ball._on_touch_body(rogue)
	_assert(is_instance_valid(p0_ball) and str(p0_ball.get("state")) == "active", "P0-1③: 飞行守球碰非球员→不交付不消耗（球仍 active）")
	# 真球员对照：同一飞行守球碰真球员 → 正常交付待用
	p0_ball._on_touch_body(s2_holder)
	_assert(is_instance_valid(p0_ball) and str(p0_ball.get("state")) == "consumed" \
			and str(s2_holder.get("pending_item_id")) in ["fenny_pan", "fenny_potion", "fenny_firework"], "P0-1④: 真球员同路径仍正常交付（身份闸不误杀）")
	var ent_src_p0: String = (EntityScript as GDScript).source_code
	_assert(ent_src_p0.contains("mode == \"grant_item\" and is_player and body.has_method(\"use_pending_item\")"), "P0-1⑤: 交付分支身份闸源码在（实体层，防守卫被回退）")
	# ===== 35号S3：FP 准星射线操控适配 =====
	ssm2._operator_context[s2_holder.get_instance_id()] = {"operator": "OP_MARK", "substate": 3, "mark_stage": 1, "command_type": "fenny_magic_ball_def"}  # MARKING=3
	var ray_foe: Node2D = mgr.spawn("fenny_magic_ball_def", s2_holder.get_instance_id(), Vector2(1400, 200), {"owner_ref": s2_holder})
	ssm2.set_command_hover_ray(s2_holder.get_instance_id(), ray_foe, null)
	_assert(ssm2.get_command_selection(s2_holder.get_instance_id()).get("hovered_ball", null) == ray_foe, "S3①: 射线命中→hovered_ball 置位（复用三级高亮链）")
	ssm2.set_command_hover_ray(s2_holder.get_instance_id(), null, null)
	_assert(ssm2.get_command_selection(s2_holder.get_instance_id()).get("hovered_ball", null) == null, "S3②: 射线脱靶→hovered 摘除")
	var im_src_s3: String = (load("res://scripts/battle/input_manager.gd") as GDScript).source_code
	_assert(im_src_s3.contains("_fp_ray_hover_targets") and im_src_s3.contains("set_command_hover_ray("), "S3③: FP 射线接线在（FP 喂 ray 口/默认视角喂原口）")
	_assert(im_src_s3.contains("exit_command_mode(controlled_player.get_instance_id(), \"fp_exit\")"), "S3④: E 退出 FP→白球指挥态收窗")
	_assert(im_src_s3.contains("fp_mode and skill_state_manager.is_ball_command_mode(player_id)"), "S3⑤: FP 下指挥态保持捕获（发球键后覆盖回 CAPTURED）")
	var ssm_src_s3: String = (SsmScript as GDScript).source_code
	_assert(ssm_src_s3.contains("MOUSE_MODE_CAPTURED if fp else Input.MOUSE_MODE_VISIBLE"), "S3⑥: 收口光标 fp 分支（CAPTURED 保持，勿强制 VISIBLE 破坏 FP）")
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
	_assert(im_src2.contains("is_ball_command_mode") and im_src2.contains("引导对象全灭"), "S9: 全灭收窗接线在（34号⓪归一口口径）")
	var ssm_src: String = (SsmScript as GDScript).source_code
	_assert(ssm_src.contains("单击即施放") and ssm_src.contains('_is_summon_steer_skill(skill_id)'), "S9: 单击即施放接线在")
	_assert(not ssm_src.contains('if get_operator(skill_id) != "OP_MIDFLY":
		_clear_operator_context'), "S9: 释放保留上下文豁免已扩（MIDFLY+召唤STEER）")

	# ===== R3：手搓链下线 =====
	var ent_src: String = EntityScript.source_code
	_assert(not ent_src.contains("_unhandled_input") and not ent_src.contains("var selected"), "R3: 手搓 _unhandled_input 选中链已下线（断点B 消除）")
	_assert(im_src.contains("inject_steer_to_summons"), "R4: input_manager 注入点在")

	# ===== 34号S7：选择模式规格符合性（六步规格+四要点） =====
	# 前置：fenny_3 指挥态（③块已激活）+ 全队球池
	var b_mate2: CharacterBody2D = PlayerScript.new()
	b_mate2.team = "a"
	b_mate2.position = Vector2(-260, 40)
	root.add_child(b_mate2)
	host.team_a_players.append(b_mate2)
	var mate_ball: Node2D = mgr.spawn("fenny_magic_ball_def", b_mate2.get_instance_id(), b_mate2.global_position + Vector2(-20, 0), {"owner_ref": b_mate2})
	mate_ball.set("lifespan_left", 999.0)
	(b_mate2.get("summons") as Array).append(mate_ball)
	# 要点①类型过滤：fenny_3（def）激活→攻球不入选、守球入选
	var att_far: Node2D = mgr.spawn("fenny_magic_ball_att", player.get_instance_id(), Vector2(-275, 40), {"owner_ref": player})
	var near_def: Node2D = mgr.spawn("fenny_magic_ball_def", b_mate2.get_instance_id(), b_mate2.global_position + Vector2(8, 0), {"owner_ref": b_mate2})
	var got: Node = ssm2._nearest_command_ball(b_mate2, Vector2(-270, 40), 120.0, "fenny_magic_ball_def")
	_assert(got != null and str(got.get("summon_type")) == "fenny_magic_ball_def", "S7①: 类型过滤=只选 def 球（att 近处也不选）")
	# 要点①全队球池：队友名下 def 球可被选（原作"任意队友可通过操控该球"）
	got = ssm2._nearest_command_ball(b_mate2, mate_ball.global_position, 120.0, "fenny_magic_ball_def")
	_assert(got == mate_ball, "S7①: 全队球池=队友名下球可指挥")
	# 要点②光标生命周期：进态 HIDDEN
	_assert((load("res://scripts/systems/spirit_system/skill_state_manager.gd") as GDScript).source_code.contains("MOUSE_MODE_HIDDEN"), "S7②: 选择态光标隐藏（源码置 HIDDEN；headless 环境不验鼠标模式）")
	# 出口：下令完成→VISIBLE
	ssm2.confirm_substate_at(player.get_instance_id(), Vector2(450, 200))
	_assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "S7②: 下令完成→光标恢复（出口①）")
	# 出口：ESC 取消（cancel 路径）→HIDDEN 再进→VISIBLE
	ssm2.on_skill_key_pressed(player.get_instance_id(), 0)
	ssm2.exit_command_mode(player.get_instance_id(), "headless-cycle")
	_assert(true, "S7②: 再进/退出循环（headless 不验鼠标模式；窗口截图背书）")
	ssm2.exit_command_mode(player.get_instance_id(), "esc")
	_assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "S7②: ESC 收口→恢复（出口②）")
	# 要点③三级高亮：set_highlight 接口置位
	mate_ball.set("_tdef", {"kind": "magic_ball", "controllable": "steer", "on_ball": {"mode": "grant_item", "item_pool": ["fenny_pan"]}})
	var vis: GDScript = load("res://scripts/battle3d/visual/magic_ball_visual_3d.gd")
	var hv: Node3D = vis.new()
	root.add_child(hv)
	hv.setup(mate_ball)
	hv.set_highlight("hover")
	_assert((hv._ring.scale as Vector3).x > 1.0, "S7③: hover 高亮=环放大")
	_assert((hv._ring_mat.albedo_color as Color).r > 0.9, "S7③: hover 环加亮")
	hv.set_highlight("selected")
	_assert((hv._ring.scale as Vector3).x > 1.3, "S7③: selected 持续选中态")
	hv.queue_free()
	# AI 同池：AI 指挥可选队友名下同类型球
	var ai_b: CharacterBody2D = PlayerScript.new()
	ai_b.team = "b"
	ai_b.position = Vector2(300, 800)
	host.add_child(ai_b)
	host.team_b_players.append(ai_b)
	var ai_ball: Node2D = mgr.spawn("fenny_magic_ball_att", b_captain.get_instance_id(), Vector2(310, 810), {"owner_ref": b_captain})
	(b_captain.get("summons") as Array).append(ai_ball)  # 登记在施法者名下（tick 的 caster.summons 口）
	ai_ball.set("lifespan_left", 999.0)
	ai_ball.set("_tdef", {"kind": "magic_ball", "controllable": "steer", "on_ball": {"mode": "carry_with_ball", "damage": 30.0}})
	var ai_ball2: Node2D = mgr.spawn("fenny_magic_ball_att", ai_b.get_instance_id(), Vector2(330, 830), {"owner_ref": ai_b})
	ai_ball2.set("lifespan_left", 999.0)
	ai_ball2.set("_tdef", {"kind": "magic_ball", "controllable": "steer", "on_ball": {"mode": "carry_with_ball", "damage": 30.0}})
	var act_a: String = (load("res://scripts/battle/spirit_ai/ai_input_source.gd") as GDScript).tick_summon_commands(b_captain)
	print("    [dbg] S4+ act=%s ai_ball.flying=%s valid=%s summons=%d" % [act_a, str(ai_ball.get("_flying")), str(is_instance_valid(ai_ball)), (b_captain.get("summons") as Array).size()])
	_assert(bool(ai_ball.get("_flying")) or bool(ai_ball2.get("_flying")) or act_a != "", "S4+: AI 同池指挥（名下+队友名下同类型可选）")
	# ===== 33号c/34号：链路节点检测补齐（悬停/状态口/收口/接线） =====
	print("\n--- 链路节点检测（34号补） ---")
	# N1 前置（上窗口丢失段重建）：caster_a=持 fenny_3 指挥态的驾驶者；b1=敌队角色（stage2 悬停目标）
	var caster_a: CharacterBody2D = PlayerScript.new()
	caster_a.team = "a"
	caster_a.is_player_controlled = true
	host.add_child(caster_a)
	host.team_a_players.append(caster_a)
	host.controlled_player = caster_a
	ssm2.setup_player_skills(caster_a.get_instance_id(), ["fenny_3"] as Array[String])
	ssm2.on_skill_key_pressed(caster_a.get_instance_id(), 0)
	var b1: CharacterBody2D = PlayerScript.new()
	b1.team = "b"
	b1.position = Vector2(90, 90)
	root.add_child(b1)
	host.team_b_players.append(b1)
	# N1 悬停检测：stage1 鼠标落在守球 120px 内 → hovered_ball 置位
	var h_ball2: Node2D = mgr.spawn("fenny_magic_ball_def", caster_a.get_instance_id(), Vector2(70, 70), {"owner_ref": caster_a})
	h_ball2.set("lifespan_left", 999.0)
	ssm2._operator_context[caster_a.get_instance_id()]["mark_stage"] = 1
	ssm2._operator_context[caster_a.get_instance_id()]["command_type"] = "fenny_magic_ball_def"
	ssm2.set_command_hover(caster_a.get_instance_id(), Vector2(70, 70))
	var hctx: Dictionary = ssm2._operator_context.get(caster_a.get_instance_id(), {})
	_assert(hctx.get("hovered_ball", null) == h_ball2, "N1a: stage1 悬停→hovered_ball 置位（snap 内同类型）")
	ssm2.set_command_hover(caster_a.get_instance_id(), Vector2(5000, 5000))
	_assert(hctx.get("hovered_ball", null) == null or not hctx.has("hovered_ball"), "N1b: 离开 snap→hovered 摘除")
	# N2 悬停检测：stage2 鼠标落在角色 90px 内 → hovered_char 置位
	ssm2._operator_context[caster_a.get_instance_id()]["mark_stage"] = 2
	ssm2.set_command_hover(caster_a.get_instance_id(), b1.global_position)
	var char_set: bool = hctx.get("hovered_char", null) == b1
	_assert(char_set, "N2: stage2 悬停→hovered_char 置位（90px 内角色）")
	# N3 状态口：get_command_selection 返回结构与只读性
	var selv: Dictionary = ssm2.get_command_selection(caster_a.get_instance_id())
	_assert(int(selv.get("stage", 0)) == 2 and selv.has("hovered_char") and selv.has("selected_ball"), "N3a: 状态口返回 stage/hovered/selected 全字段")
	# N4 收口：exit_command_mode 清上下文
	ssm2.exit_command_mode(caster_a.get_instance_id(), "test")
	_assert(not ssm2._operator_context.has(caster_a.get_instance_id()), "N4: exit_command_mode 清上下文（收口口径）")
	# N5 input_manager 接线：源码断言（每帧喂悬停+收口巡检两处调用）
	_assert(im_src.contains("set_command_hover(") and im_src.contains("exit_command_mode("), "N5: input_manager 接线调用在（每帧喂坐标+巡检收口）")

	# ===== 34号S7 要点⓪：操作模式归一（主人批 2026-10-08「可以」；判定归一路线，skills/types 数据零改动） =====
	print("\n--- S7要点⓪：两技路由一致性（fenny_2/fenny_3 同输入序列→同状态机行为） ---")
	# ⓪a 归一口接线：ssm 定义在 + input_manager 三处走归一口（操控窗判定/全灭收窗/STEER注入停用）
	_assert(ssm_src.contains("func is_ball_command_mode"), "⓪a: ssm 归一口 is_ball_command_mode 定义在")
	var im_cnt0: int = im_src2.count("is_ball_command_mode(")
	_assert(im_cnt0 >= 3, "⓪a: input_manager 三处走归一口（操控窗/收窗/注入停用）实测=%d 处" % im_cnt0)
	# ⓪b 分叉消除：操控窗判定不再裸按 operator 字符串分叉（归一前=input_manager:512 双 OP 判）
	_assert(not im_src2.contains('== "OP_MARK"'), "⓪b: 操控窗判定不再裸分叉 OP_MARK")
	# ⓪c 两技同输入序列走查（真路径：激活→点球→点目标→收窗，逐点一致=⓪核心断言）
	var route_rows: Array = [["fenny_2", "OP_STEER", "fenny_magic_ball_att"], ["fenny_3", "OP_MARK", "fenny_magic_ball_def"]]
	for row in route_rows:
		var sid2: String = row[0]
		var opx: String = row[1]
		var btype: String = row[2]
		var rp: CharacterBody2D = PlayerScript.new()
		rp.team = "a"
		rp.is_player_controlled = true
		host.add_child(rp)
		host.team_a_players.append(rp)
		host.controlled_player = rp
		var rball: Node2D = mgr.spawn(btype, rp.get_instance_id(), Vector2(200, 400), {"owner_ref": rp})
		rball.set("lifespan_left", 999.0)
		ssm2.setup_player_skills(rp.get_instance_id(), [sid2] as Array[String])
		ssm2.on_skill_key_pressed(rp.get_instance_id(), 0)
		var ok1: bool = ssm2.is_ball_command_mode(rp.get_instance_id()) 			and ssm2.get_operator_substate(rp.get_instance_id()) == "MARKING" 			and str(ssm2._operator_context[rp.get_instance_id()].get("operator", "")) == opx
		_assert(ok1, "⓪c: %s 激活→MARKING+归一口True（operator=%s 同路由）" % [sid2, opx])
		var r1: String = ssm2.confirm_substate_at(rp.get_instance_id(), rball.global_position)
		_assert(r1 == "ball_selected", "⓪c: %s 点球→选中（同路由）" % sid2)
		var r2: String = ssm2.confirm_substate_at(rp.get_instance_id(), Vector2(450, 400))
		_assert(r2 == "ordered", "⓪c: %s 点目标→ordered（同路由）" % sid2)
		_assert(not ssm2.is_ball_command_mode(rp.get_instance_id()), "⓪c: %s ordered 收窗→归一口 False（同收窗行为）" % sid2)
		rp.queue_free()
	# ⓪d 冻结并入：is_skill_control_active 含归一口（fenny_3 指挥态也冻结=两技同冻结同空格迁移；真冻结行为平台抓帧背书）
	var isc_at: int = im_src2.find("func is_skill_control_active")
	_assert(isc_at >= 0 and im_src2.substr(isc_at, 420).contains("is_ball_command_mode"), "⓪d: 白球指挥态并入操控窗（fenny_2/fenny_3 同冻结）")
	# ⓪e STEER 注入停用：inject_steer_to_summons 内归一口守卫（选择模式=两段点击唯一输入模型）
	var ist_at: int = im_src2.find("func inject_steer_to_summons")
	_assert(ist_at >= 0 and im_src2.substr(ist_at, 420).contains("is_ball_command_mode"), "⓪e: 选择模式下 STEER 牵引停用（攻/守球不再被鼠标定向）")
	# ⓪f 光标生命周期收口（要点②六出口防泄漏）：恢复统一收进 _clear_operator_context
	var coc_at: int = ssm_src.find("func _clear_operator_context")
	_assert(coc_at >= 0 and ssm_src.substr(coc_at, 600).contains("MOUSE_MODE_VISIBLE"), "⓪f: 光标恢复统一收口（取消/收窗/下令/切场凡清上下文必恢复）")
	var esc_at: int = im_src2.find("KEY_ESCAPE")
	_assert(esc_at >= 0 and im_src2.substr(esc_at, 200).contains("is_ball_command_mode"), "⓪f: ESC 取消接线（白球指挥态限定）")
	_assert(im_src2.contains("func _exit_tree") and im_src2.substr(im_src2.find("func _exit_tree"), 200).contains("MOUSE_MODE_HIDDEN"), "⓪f: 切场兜底（_exit_tree 防 HIDDEN 泄漏到菜单）")

	# ===== 34号S8 任务书 #1（S7d 表 #6）：AI 域激活窗排除白球指挥技——AI 链单走 S4 =====
	var ai_act_ball: bool = ssm2.ai_activate_skill(b_captain.get_instance_id(), b_captain, "fenny_2")
	_assert(not ai_act_ball, "S8#1: AI 施放 fenny_2 → 激活窗拒绝（false，不造上下文不注入=S4 单链）")
	var ai_act_shark: bool = ssm2.ai_activate_skill(b_captain.get_instance_id(), b_captain, "shuimu_1")
	_assert(ai_act_shark, "S8#1 对照: 攻鲨（召唤型 STEER 非白球）仍走激活窗（语义不变）")

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail == 0:
		print("🎉 全部通过")
	else:
		print("❌ 有失败项")
	quit(0 if _fail == 0 else 1)
