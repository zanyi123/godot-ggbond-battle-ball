## 13号消费②走位消费——诊断取证套件（只读诊断，零热文件改动）
## 工单：13_场地认知共享层 §三消费②（主人令"优化笨笨走向"）；流程=诊断先行
## 三现象取证：外场绕远/卡滞（第二真相漂移实锤）+ 卡线残余 + 贴边抖动
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_walk_consumption_diagnosis.gd
extends SceneTree

# 运行时 load（foundation 同款）：-s 模式下 preload 热文件撞 autoload 编译期解析坑
var RealAim: GDScript = null
var RealProfile: GDScript = null
var FieldZone: GDScript = null

var _pass: int = 0
var _fail: int = 0


class StubPlayer extends CharacterBody2D:
	var character_id: String = ""
	var team: String = "a"
	var is_defeated: bool = false
	var is_penalized: bool = false
	var is_carrying_ball: bool = false
	var facing_direction: Vector2 = Vector2.RIGHT
	var stamina: float = 100.0
	var max_stamina: float = 100.0
	var spirit_energy: float = 100.0
	var max_spirit_energy: float = 100.0
	var attack_power: float = 10.0
	var defense: float = 10.0
	var speed: float = 10.0
	var resilience: float = 10.0


class StubObstacleManager extends Node:
	var obstacles: Array = []


class StubBall extends Area2D:
	var is_active: bool = false
	var owner_player: CharacterBody2D = null
	var ball_direction: Vector2 = Vector2.RIGHT
	var ball_speed: float = 400.0
	var global_target: Vector2 = Vector2.ZERO


func _initialize() -> void:
	_run()


func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  ✓ " + name)
	else:
		_fail += 1
		print("  ✗ " + name)


func _make_player(id: String, team: String, pos: Vector2, penalized: bool = false) -> StubPlayer:
	var p: StubPlayer = StubPlayer.new()
	p.character_id = id
	p.team = team
	p.position = pos
	p.is_penalized = penalized
	root.add_child(p)
	return p


func _run() -> void:
	print("\n========== 13号消费②诊断：走位三现象取证 ==========\n")
	for i in range(3):
		await process_frame
	# 看门狗
	RealAim = load("res://scripts/battle/ai_manager.gd")
	RealProfile = load("res://scripts/battle/ai_profile.gd")
	FieldZone = load("res://scripts/battle/field_zone.gd")
	create_timer(60.0).timeout.connect(func() -> void:
		print("❌ WATCHDOG 诊断超时")
		quit(3))

	var aim: Node = RealAim.new()
	var ball: StubBall = StubBall.new()
	root.add_child(ball)

	# ===== D1/D2：第二真相漂移取证（凹口带内外场判定分歧）=====
	print("[D1/D2] 外场判定分歧（ai_manager 私有盒 vs 知识库凹字形）")
	var d1_am: bool = aim._is_pos_in_outer(Vector2(300, 0), "a")
	var d1_kz: String = FieldZone.knowledge_zone_of(Vector2(300, 0), "a")
	print("  凹口点(300,0)：ai_manager 外场=%s | knowledge=%s" % [str(d1_am), d1_kz])
	_check(not d1_am and d1_kz.begins_with("inner"), "D1(修复后) 凹口点判定合一：ai_manager=知识库=内场%s" % d1_kz)
	# 分歧带面积量化：x∈[250,380], y∈[-255,255] 网格
	var diverge: int = 0
	var sampled: int = 0
	var x := 255.0
	while x <= 375.0:
		var y := -255.0
		while y <= 255.0:
			sampled += 1
			if aim._is_pos_in_outer(Vector2(x, y), "a") and str(FieldZone.knowledge_zone_of(Vector2(x, y), "a")).begins_with("inner"):
				diverge += 1
			y += 25.0
		x += 25.0
	print("  凹口带网格分歧点：%d/%d" % [diverge, sampled])
	_check(diverge == 0, "D2(修复后) 凹口带分歧=0（第二真相合一回归仪）")
	# 一致性对照组：真外场点两套判定一致
	_check(aim._is_pos_in_outer(Vector2(420, 0), "a") and str(FieldZone.knowledge_zone_of(Vector2(420, 0), "a")) == "outer_own", "D2b 真外场点(420,0)两套判定一致（分歧仅凹口带）")

	# ===== D6：第二真相漂移守卫（私有常量 vs 知识库权威值）=====
	print("[D6] 常量漂移守卫")
	var am_inner_x_min: float = aim.FIELD_X_MIN
	var kz_inner: Dictionary = FieldZone.INNER
	_check(is_equal_approx(am_inner_x_min, float(kz_inner["x"])) , "D6a FIELD_X_MIN==knowledge INNER.x")
	var kz_r: Dictionary = FieldZone.RIGHT_OUTER
	var am_r_xmin: float = aim.RIGHT_OUTER_X_MIN
	var kz_r_xmin: float = minf(float(kz_r["main"]["x"]), float(kz_r["top_arm"]["x"]))
	_check(is_equal_approx(am_r_xmin, kz_r_xmin), "D6b RIGHT_OUTER_X_MIN==知识库凹字形包围(min)")
	var kz_l: Dictionary = FieldZone.LEFT_OUTER
	var am_l_xmax: float = aim.LEFT_OUTER_X_MAX
	var kz_l_xmax: float = maxf(float(kz_l["main"]["x"]) + float(kz_l["main"]["width"]), float(kz_l["top_arm"]["x"]) + float(kz_l["top_arm"]["width"]))
	_check(is_equal_approx(am_l_xmax, kz_l_xmax), "D6c LEFT_OUTER_X_MAX==知识库凹字形包围(max)")
	var gap_am_ok: bool = is_equal_approx(aim.GAP_Y_MIN, -float(kz_inner["height"]) / 2.0) and is_equal_approx(aim.GAP_Y_MAX, float(kz_inner["height"]) / 2.0)
	_check(gap_am_ok, "D6d GAP_Y==内场y半高（凹口口径一致）")

	# ===== D3：行为取证——流放球员对凹口球的误就位 =====
	print("[D3] 行为取证：流放球员 × 凹口球（内场点被当外场球追）")
	var exile: StubPlayer = _make_player("t_exile", "a", Vector2(420, 0), true)
	var mate: StubPlayer = _make_player("t_mate", "a", Vector2(-100, 0))
	var foe: StubPlayer = _make_player("t_foe", "b", Vector2(-200, 0))
	var aim2: Node = RealAim.new()
	var profile: AIProfile = RealProfile.new()
	var aps: Array[Dictionary] = [
		{"player": exile, "team": "a", "profile": profile},
		{"player": mate, "team": "a", "profile": profile},
		{"player": foe, "team": "b", "profile": profile},
	]
	aim2.ai_players = aps
	aim2.ball_node = ball
	ball.is_active = false
	ball.owner_player = null
	ball.position = Vector2(300, 0)   # 凹口带球（知识库=内场）
	var sad := {"player": exile, "team": "a", "profile": profile, "skill_decide_count": 0}
	var target_history: Array = []
	for i in range(12):
		aim2._decide_penalty_move(sad)
		target_history.append(Vector2(sad.get("target_pos", Vector2.ZERO)))
	var last_target: Vector2 = target_history.back()
	var am_outer: bool = aim2._is_pos_in_outer(Vector2(300, 0), "a")
	var ball_in_outer: bool = aim2._is_pos_in_outer(ball.position, "a")
	var threat: float = aim2._eval_ball_threat(sad)
	var catch_util: float = aim2._utility_catch(sad, aim2._evaluate_situation(sad), threat, ball.position)
	var in_gap_chase: bool = last_target.x < 380.0   # 目标被引向凹口/内场侧
	print("  ball_in_outer判定=%s（知识库=%s）| threat=%.2f catch_util=%.2f | 目标末值=%s（凹口追逐=%s）" % [str(ball_in_outer), str(FieldZone.knowledge_zone_of(ball.position, "a")), threat, catch_util, str(last_target), str(in_gap_chase)])
	_check(not ball_in_outer and not in_gap_chase, "D3(修复后) 凹口球不再误判：流放球员留守外场，不被内场球诱离")

	# ===== D4：卡线残余取证（追球 clamp 的目标翻面计数）=====
	print("[D4] 卡线残余：a 队进攻者 × 球在敌半场（中线 clamp 场景）")
	var atk: StubPlayer = _make_player("t_atk", "a", Vector2(-20, 0))
	var sad2 := {"player": atk, "team": "a", "profile": profile, "skill_decide_count": 0}
	ball.position = Vector2(200, 0)   # 球在敌半场
	ball.owner_player = null
	ball.is_active = false
	var flip: int = 0
	var prev_x: float = 0.0
	var clamp_diffs: Array = []
	for i in range(20):
		var t: Vector2 = aim._clamp_to_half_field(Vector2(200, 0), "a")
		clamp_diffs.append(t.x)
		if i > 0 and signf(t.x) != signf(prev_x) and absf(t.x - prev_x) > 1.0:
			flip += 1
		prev_x = t.x
	var stable: bool = true
	for v in clamp_diffs:
		if not is_equal_approx(v, clamp_diffs[0]):
			stable = false
	print("  clamp 目标 20 周期稳定=%s（值=%s）" % [str(stable), str(clamp_diffs[0])])
	_check(stable, "D4 纯函数稳定：clamp 本身无翻面（卡线残余若有，源头在决策分支非 clamp）")

	# ===== D5：贴边抖动取证（hold 目标贴边 + 分离力推挤的目标振荡）=====
	print("[D5] 贴边抖动：hold 目标 y 越界时的 clamp 行为")
	var t_out: Vector2 = aim._clamp_to_field(Vector2(-100, 320))
	var t_in: Vector2 = aim._clamp_to_field(Vector2(-100, 100))
	_check(absf(t_out.y) <= 260.0 and is_equal_approx(t_in.y, 100.0), "D5 clamp_to_field 边界回收正常（贴边抖动若有，源头在 steering/分离力非 clamp）")

	print("\n========== 诊断结论：%d 通过 / %d 失败 ==========" % [_pass, _fail])
	print("""
【走位消费诊断结论】
  根因（外场绕远/卡驻类）=第二真相漂移：ai_manager._is_pos_in_outer 用简化包围盒
  （右外场 x∈[250,510] 全高），与知识库凹字形（main x≥380+上下臂带）在凹口带
  x∈[250,380],|y|<260 系统性分歧——流放球员对凹口带球触发外场追球/驻留（D1~D3）。
  卡线/贴边两类 clamp 纯函数本身稳定（D4/D5），如有残余源头在决策分支，暂无证据。
  修复已实施（2026-09-28）：_is_pos_in_outer 权威单源（knowledge_zone_of 凹字形），
  D1~D3 翻转为修复后语义=回归仪；外场游走 randf_range 残留另案（确定性纪律）；
  卡线/贴边 clamp 纯函数稳定（D4/D5），如见残余源头在决策分支另诊。
""")
	# ===== W：墙体滑行绕行（0928-11 选A：教AI绕墙+发球寻新路径）=====
	print("[W] 墙体滑行绕行")
	var no_mgr_aim: Node = RealAim.new()
	var pre_runner: StubPlayer = _make_player("t_pre", "a", Vector2(0, 0))
	var sad_w0 := {"player": pre_runner, "team": "a", "profile": profile, "skill_decide_count": 0}
	var vel_nomgr: Vector2 = no_mgr_aim._calc_wall_slide(sad_w0, Vector2(200, 0))
	_check(vel_nomgr == Vector2(200, 0), "W3 无墙管理器 fail-open=原速度")
	var wall_mgr := StubObstacleManager.new()
	wall_mgr.add_to_group("obstacle_managers")
	root.add_child(wall_mgr)
	var wall := StaticBody2D.new()   # 几何体即可（_calc_wall_slide 只读位置/尺寸；不挂 obstacle.gd 避免其 _process 依赖真实世界）
	wall.position = Vector2(100, 0)
	var wall_cs := CollisionShape2D.new()
	var wshape := RectangleShape2D.new()
	wshape.size = Vector2(28, 140)   # 纵墙（短轴=x → 绕行朝墙端 x 方向）
	wall_cs.shape = wshape
	wall.add_child(wall_cs)
	wall.set("_cached_width", 28.0)
	wall.set("_cached_height", 140.0)
	wall_mgr.obstacles = [wall]
	var runner: StubPlayer = _make_player("t_runner", "a", Vector2(0, 0))
	var sad_w := {"player": runner, "team": "a", "profile": profile, "skill_decide_count": 0}
	var vel_out: Vector2 = aim._calc_wall_slide(sad_w, Vector2(200, 0))
	print("  直行(200,0) × 纵墙(28×140@100,0) → 滑行输出=%s" % [str(vel_out)])
	_check(absf(vel_out.x) > 1.0 and signf(vel_out.x) == 1.0 and absf(vel_out.y) > 1.0, "W1 滑行=保留推进+朝墙端侧偏（x正+侧向分量）")
	var vel_far: Vector2 = aim._calc_wall_slide(sad_w, Vector2(0, 200))
	_check(is_equal_approx(vel_far.y, 200.0) and vel_far.x == 0.0, "W2 不朝墙方向 fail-open=原速度")
	quit(1 if _fail > 0 else 0)
