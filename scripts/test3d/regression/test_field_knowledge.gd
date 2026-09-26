## 13号工单验收：场地认知共享层知识库API套件（布场窗口交付）
## 断言组：Z-区域语义 / L-白线几何 / G-通道口 / Q-规则问答
## 纯静态查询层（field_zone.gd 追加段），零游戏行为改动。
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_field_knowledge.gd
extends SceneTree

const Knowledge: GDScript = preload("res://scripts/battle/field_zone.gd")

var _pass: int = 0
var _fail: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== 13工单：场地知识库API套件 ==========\n")
	for i in range(3):
		await process_frame
	# 看门狗：运行时错误会跳过 _finish 的 quit()，90s 强制退出防挂死
	create_timer(90.0).timeout.connect(func() -> void:
		print("❌ WATCHDOG：套件超时强退（存在未捕获脚本错误，见上方 ERROR）")
		quit(3))

	# ===== Z-区域语义归属 =====
	_assert("Z1: 场心=中圈发球区", Knowledge.knowledge_zone_of(Vector2(0, 0)) == "center_circle")
	_assert("Z2: 队a半场语义（a半场=x≤0左，x>0为敌半场）", Knowledge.knowledge_zone_of(Vector2(-100, 100), "a") == "inner_own" and Knowledge.knowledge_zone_of(Vector2(100, 100), "a") == "inner_enemy")
	_assert("Z3: 队b半场语义（镜像）", Knowledge.knowledge_zone_of(Vector2(-100, 0), "b") == "inner_enemy" and Knowledge.knowledge_zone_of(Vector2(100, 0), "b") == "inner_own")
	_assert("Z4: 左右外场方位语义", Knowledge.knowledge_zone_of(Vector2(-450, 0)) == "outer_left" and Knowledge.knowledge_zone_of(Vector2(450, 0)) == "outer_right")
	_assert("Z5: 流放区归属（左=队b自家/队a敌方）", Knowledge.knowledge_zone_of(Vector2(-450, 0), "b") == "outer_own" and Knowledge.knowledge_zone_of(Vector2(-450, 0), "a") == "outer_enemy")
	_assert("Z6: 流放区归属（右=队a自家/队b敌方）", Knowledge.knowledge_zone_of(Vector2(450, 0), "a") == "outer_own" and Knowledge.knowledge_zone_of(Vector2(450, 0), "b") == "outer_enemy")
	_assert("Z7: 蓝色禁区（界外与内场延长带）", Knowledge.knowledge_zone_of(Vector2(600, 0)) == "out_of_bounds" and Knowledge.knowledge_zone_of(Vector2(0, -290)) == "out_of_bounds")
	_assert("Z8: 外场上下臂归属（凹字形）", Knowledge.knowledge_zone_of(Vector2(300, -290)) == "outer_right" and Knowledge.knowledge_zone_of(Vector2(-300, 290)) == "outer_left")
	_assert("Z9: 通行规则语义表6区齐全", Knowledge.KNOWLEDGE_ZONE_RULES.size() == 6 and Knowledge.KNOWLEDGE_ZONE_RULES.has("inner_own") and Knowledge.KNOWLEDGE_ZONE_RULES.has("out_of_bounds"))

	# ===== L-白线几何查询 =====
	_assert("L1: 到中线距离（(100,0)→100）", absf(Knowledge.knowledge_dist_to_line(Vector2(100, 0), "midline") - 100.0) < 0.001)
	_assert("L2: 到内场顶线距离（(0,-270)→10）", absf(Knowledge.knowledge_dist_to_line(Vector2(0, -270), "inner_top") - 10.0) < 0.001)
	_assert("L3: 到内场左线距离（(200,0)→580）", absf(Knowledge.knowledge_dist_to_line(Vector2(200, 0), "inner_left") - 580.0) < 0.001)
	_assert("L4: 未知line_id返回-1（fail-closed）", Knowledge.knowledge_dist_to_line(Vector2.ZERO, "no_such_line") == -1.0)
	_assert("L5: 越中线走位判定（a向右穿=交叉）", Knowledge.knowledge_would_cross_line(Vector2(-100, 0), Vector2(100, 0), "midline"))
	_assert("L6: 半场内走位不交叉", not Knowledge.knowledge_would_cross_line(Vector2(-100, 0), Vector2(-200, 0), "midline"))
	_assert("L7: 出内场纵深走位交叉顶线", Knowledge.knowledge_would_cross_line(Vector2(0, -100), Vector2(0, -290), "inner_top"))
	_assert("L8: 平行走线不判交", not Knowledge.knowledge_would_cross_line(Vector2(-100, -270), Vector2(100, -270), "inner_top"))

	# ===== G-外场通道口 =====
	var gate_left: Dictionary = Knowledge.knowledge_outer_gate_segment("left")
	_assert("G1: 左口线段=两臂之间开口 x=-250 y∈[-260,260]", (gate_left["a"] as Vector2).distance_to(Vector2(-250, -260)) < 0.001 and (gate_left["b"] as Vector2).distance_to(Vector2(-250, 260)) < 0.001)
	_assert("G2: 右口中心=(250,0)", Knowledge.knowledge_outer_gate_point("right").distance_to(Vector2(250, 0)) < 0.001)
	_assert("G3: 己方流放区入口（a=右口/b=左口，start_field_transition口径）", Knowledge.knowledge_own_gate_point("a").distance_to(Vector2(250, 0)) < 0.001 and Knowledge.knowledge_own_gate_point("b").distance_to(Vector2(-250, 0)) < 0.001)
	_assert("G4: 敌方流放区入口（a→左口/b→右口）", Knowledge.knowledge_enemy_gate_point("a").distance_to(Vector2(-250, 0)) < 0.001 and Knowledge.knowledge_enemy_gate_point("b").distance_to(Vector2(250, 0)) < 0.001)
	var near1: Dictionary = Knowledge.knowledge_nearest_gate(Vector2(-300, 0))
	_assert("G5: 最近口（(-300,0)→左口50px）", str(near1.get("side")) == "left" and absf(float(near1.get("dist"))) - 50.0 < 0.001 and (near1["pos"] as Vector2).distance_to(Vector2(-250, 0)) < 0.001)
	var near2: Dictionary = Knowledge.knowledge_nearest_gate(Vector2(400, 100))
	_assert("G6: 最近口（(400,100)→右口√(150²+100²)≈180.3px）", str(near2.get("side")) == "right" and absf(float(near2.get("dist")) - 180.2776) < 0.01)

	# ===== Q-关键位置与规则问答 =====
	_assert("Q1: 球门区纵深点（a→(-320,0)/b→(320,0)）", Knowledge.knowledge_goal_area_point("a").distance_to(Vector2(-320, 0)) < 0.001 and Knowledge.knowledge_goal_area_point("b").distance_to(Vector2(320, 0)) < 0.001)
	_assert("Q2: 球门区纵深点自定义深度（b,100→(280,0)）", Knowledge.knowledge_goal_area_point("b", 100.0).distance_to(Vector2(280, 0)) < 0.001)
	_assert("Q3: 贴己方白线内侧（y跟随并夹回纵深带 a,y300→(-368,220)/b,y-300→(368,-220)）", Knowledge.knowledge_own_line_inner_point("a", 300.0).distance_to(Vector2(-368, 220)) < 0.001 and Knowledge.knowledge_own_line_inner_point("b", -300.0).distance_to(Vector2(368, -220)) < 0.001)
	_assert("Q4: 走位违规=越中线（a穿右）", Knowledge.knowledge_would_violate("a", Vector2(-100, 0), Vector2(100, 0)) == "cross_midline")
	_assert("Q5: 走位违规=越中线（b穿左）", Knowledge.knowledge_would_violate("b", Vector2(100, 0), Vector2(-100, 0)) == "cross_midline")
	_assert("Q6: 走位违规=越界进敌方流放区（a→左外场）", Knowledge.knowledge_would_violate("a", Vector2(0, 0), Vector2(-450, 0)) == "cross_field_boundary")
	_assert("Q7: 走位违规=越界进敌方流放区（b→右外场）", Knowledge.knowledge_would_violate("b", Vector2(0, 0), Vector2(450, 0)) == "cross_field_boundary")
	_assert("Q8: 走位违规=蓝色禁区优先", Knowledge.knowledge_would_violate("a", Vector2(0, 0), Vector2(600, 0)) == "out_of_bounds")
	_assert("Q9: 合规走位零违规", Knowledge.knowledge_would_violate("a", Vector2(0, 0), Vector2(-100, 0)) == "")
	_assert("Q10: 救援回流规则当前未实装（false=预留接入点）", Knowledge.knowledge_rescue_rule_active() == false)
	_assert("Q11: 实例侧旧判定零改动（get_zone_at 仍为枚举口径）", Knowledge.new().get_zone_at(Vector2(0, 0)) == Knowledge.ZoneType.INNER_FIELD)

	_finish()


func _finish() -> void:
	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 全部通过！（纯增量静态层，零旧行为改动）")
	quit(1 if _fail > 0 else 0)


func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)
