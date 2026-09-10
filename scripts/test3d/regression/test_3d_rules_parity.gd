## Phase 3 类二验证：白线规则双轨比对（battle3d/test3d · headless 可跑）
## 用例矩阵 × 双轨：真 field_zone.check_zone_violation(真 player 实例)
##              vs  FieldRules3D.check_violation(team, pos, is_penalized)
## 运行：Godot --headless 加载本场景自动跑完退出（PASS=exit 0）
extends Node3D

const CASES: Array[Dictionary] = [
	# {team, pos, penalized, expect_desc}
	{"team": "a", "pos": Vector2(-190, 0), "penalized": false, "desc": "A内场中心"},
	{"team": "a", "pos": Vector2(-370, -250), "penalized": false, "desc": "A内场左上角(界内)"},
	{"team": "a", "pos": Vector2(1, 0), "penalized": false, "desc": "A内场越中线x=+1"},
	{"team": "a", "pos": Vector2(0, 0), "penalized": false, "desc": "A内场中线x=0(不违规)"},
	{"team": "a", "pos": Vector2(-381, 0), "penalized": false, "desc": "A越边界x=-381(进左外场)"},
	{"team": "a", "pos": Vector2(-380, 0), "penalized": false, "desc": "A边界x=-380(不违规)"},
	{"team": "a", "pos": Vector2(-450, -300), "penalized": false, "desc": "A在右外场主体(合法)"},
	{"team": "a", "pos": Vector2(-300, -300), "penalized": false, "desc": "A蓝色禁区(内场上方)"},
	{"team": "a", "pos": Vector2(0, -300), "penalized": false, "desc": "A蓝色禁区(中线上方)"},
	{"team": "a", "pos": Vector2(-450, 0), "penalized": true, "desc": "A被惩罚在左外场(不违规)"},
	{"team": "a", "pos": Vector2(320, 0), "penalized": true, "desc": "A被惩罚在内场右侧(只查蓝区)"},
	{"team": "b", "pos": Vector2(190, 0), "penalized": false, "desc": "B内场中心"},
	{"team": "b", "pos": Vector2(-1, 0), "penalized": false, "desc": "B内场越中线x=-1"},
	{"team": "b", "pos": Vector2(381, 0), "penalized": false, "desc": "B越边界x=+381(进右外场)"},
	{"team": "b", "pos": Vector2(380, 0), "penalized": false, "desc": "B边界x=+380(不违规)"},
	{"team": "b", "pos": Vector2(450, 280), "penalized": false, "desc": "B在右外场臂部(合法)"},
	{"team": "b", "pos": Vector2(450, -280), "penalized": false, "desc": "B蓝色禁区(右外场主体与臂之间的缺口)"},
	{"team": "b", "pos": Vector2(-450, 0), "penalized": false, "desc": "B在左外场主体(合法)"},
	{"team": "b", "pos": Vector2(-300, -300), "penalized": false, "desc": "B蓝色禁区(左上)"},
	{"team": "b", "pos": Vector2(511, 0), "penalized": false, "desc": "B外场外x=511(蓝色禁区)"},
	{"team": "b", "pos": Vector2(510, 0), "penalized": false, "desc": "B外场边缘x=510(合法)"},
	{"team": "a", "pos": Vector2(-450, 280), "penalized": false, "desc": "A在左外场臂部(蓝区,臂属队B)"},
]

func _ready() -> void:
	print("[P3] === 白线规则双轨验证开始 (%d 用例) ===" % CASES.size())
	# 让 field_zone 场景节点就绪（本场景根下动态建一个）
	var fz := Node2D.new()
	fz.set_script(load("res://scripts/battle/field_zone.gd"))
	add_child(fz)

	var player_script := load("res://scripts/battle/player.gd")
	var pass_count := 0
	var fail_count := 0
	for i in range(CASES.size()):
		var c: Dictionary = CASES[i]
		# 轨道1：真 field_zone + 真 player 实例
		var player := CharacterBody2D.new()
		player.set_script(player_script)
		add_child(player)
		player.global_position = c["pos"]
		player.team = c["team"]
		player.set("is_penalized", c["penalized"])
		var gd_result: int = int(fz.check_zone_violation(player))
		player.queue_free()
		# 轨道2：FieldRules3D 纯函数
		var r3d_result: int = FieldRules3D.check_violation(c["team"], c["pos"], c["penalized"])
		var ok := gd_result == r3d_result
		if ok:
			pass_count += 1
		else:
			fail_count += 1
		print("[P3][%s] #%02d %s → field_zone=%d rules_3d=%d" % [
			"PASS" if ok else "FAIL", i + 1, c["desc"], gd_result, r3d_result])
	print("[P3] === 结果: %d/%d 通过 ===" % [pass_count, CASES.size()])
	print("[P3] RESULT: %s" % ("PASS" if fail_count == 0 else "FAIL"))
	get_tree().quit(0 if fail_count == 0 else 1)
