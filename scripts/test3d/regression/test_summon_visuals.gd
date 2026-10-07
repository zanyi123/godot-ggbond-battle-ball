## 24号工单 A1/A2 验收套件：水鲨鱼+魔术白球 3D 简易模型（随行测试平台美术资源首批件，headless 可跑）
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_summon_visuals.gd
## 覆盖：模型可加载/鲨鱼三态显示（游走·遁地·融合）/白球攻红守蓝环+悬浮旋转/均匀撒点确定性/UI 零判定
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

func _run() -> void:
	print("\n========== 24号 A1/A2：水鲨鱼+魔术白球模型验收 ==========\n")
	for i in range(3):
		await process_frame  # 等 autoload 就位
	var SummonScript: GDScript = load("res://scripts/systems/summon/summon_entity.gd")
	var SharkScript: GDScript = load("res://scripts/battle3d/visual/shark_visual_3d.gd")
	var BallScript: GDScript = load("res://scripts/battle3d/visual/magic_ball_visual_3d.gd")
	var BridgeScript: GDScript = load("res://scripts/battle3d/battle_arena_3d_bridge.gd")
	_assert(SummonScript != null, "召唤实体基类可加载")
	_assert(SharkScript != null, "SharkVisual3D 可加载（含语法/继承编译）")
	_assert(BallScript != null, "MagicBallVisual3D 可加载（含语法/继承编译）")
	_assert(BridgeScript != null, "桥接层可加载（含 _sync_summons 增量编译）")
	_assert(str(BridgeScript.source_code).contains("_sync_summons()"), "桥接层已挂 _sync_summons 每帧同步")
	_assert(str(BridgeScript.source_code).contains("SUMMON_SPAWNED"), "桥接层已订阅 SUMMON_SPAWNED 事件")

	# ===== A1 水鲨鱼：常态（游走）=====
	var shark_tdef := {"kind": "shark", "hitbox": "circle:22", "lifespan": 15.0,
		"burrow": {"burrow_energy_cost_per_s": 2.0, "jump_key": true},
		"on_ball": {"mode": "merge_with_ball"}}
	var shark = SummonScript.new()
	shark.summon_type = "shuimu_shark_att"
	root.add_child(shark)
	shark.setup(shark_tdef, 0, {})
	await process_frame
	var shark_vis: Node3D = SharkScript.new()
	root.add_child(shark_vis)
	shark_vis.setup(shark)
	await process_frame
	var body: Node3D = shark_vis.get_node_or_null("SharkBody")
	_assert(body != null, "A1: 鱼形体容器在位")
	_assert(body.get_child_count() >= 5, "A1: 盒体拼形≥5件（躯干/头/尾/背鳍/尾鳍）")
	var body_mat: StandardMaterial3D = shark_vis._body_mat
	_assert(body_mat != null and body_mat.albedo_color == SharkScript.BODY_COLOR, "A1: 常态紫色鱼身")
	_assert(body_mat.albedo_color.a == 1.0, "A1: 常态不透明")
	_assert(is_equal_approx(body.scale.x, 1.0), "A1: 常态 scale=1.0")
	shark_vis.sync_from_2d(Vector2(100, 200), 0.0)
	_assert(shark_vis.global_position == Vector3(100, 0, 200), "A1: sync_from_2d 单位制 (x,0,y) 1:1")

	# ===== A1 水鲨鱼：遁地（alpha 半透明+贴地下沉 50%）=====
	shark.enter_burrow()
	await process_frame
	_assert(str(shark.state) == "burrowed", "A1: enter_burrow→状态机 burrowed（判定层既有语义）")
	_assert(body_mat.albedo_color.a == SharkScript.BURROW_ALPHA, "A1: 遁地 alpha=0.5 半透明")
	_assert(is_equal_approx(body.position.y, -SharkScript.BURROW_SINK), "A1: 遁地下沉 50%（-12，体高24）")
	shark.exit_burrow()
	await process_frame
	_assert(body_mat.albedo_color.a == 1.0, "A1: 浮出恢复不透明")

	# ===== A1 水鲨鱼：融合态（shuimu_shark_bomb=scale×1.6+金红变色）=====
	var bomb = SummonScript.new()
	bomb.summon_type = "shuimu_shark_bomb"
	root.add_child(bomb)
	bomb.setup({"kind": "shark", "hitbox": "circle:26", "lifespan": 12.0, "burrow": null,
		"on_ball": {"mode": "merge_with_ball", "damage_mult": 2.0}}, 0, {})
	var bomb_vis: Node3D = SharkScript.new()
	root.add_child(bomb_vis)
	bomb_vis.setup(bomb)
	await process_frame
	_assert(bomb_vis._is_fusion, "A1: bomb 型识别为融合态")
	_assert(bomb_vis._body_mat.albedo_color == SharkScript.FUSION_BODY_COLOR, "A1: 融合态金红变色")
	_assert(is_equal_approx(bomb_vis._body.scale.x, 1.6), "A1: 融合态 scale=×1.6")

	# ===== A2 魔术白球：攻红环/守蓝环+悬浮旋转 =====
	var ball_att = SummonScript.new()
	ball_att.summon_type = "fenny_magic_ball_att"
	root.add_child(ball_att)
	ball_att.setup({"kind": "magic_ball", "hitbox": "circle:18", "lifespan": 20.0,
		"on_ball": {"mode": "carry_with_ball", "explode_on_enemy": true, "damage": 30.0}}, 0, {})
	var ball_att_vis: Node3D = BallScript.new()
	root.add_child(ball_att_vis)
	ball_att_vis.setup(ball_att)
	await process_frame
	var sphere: MeshInstance3D = ball_att_vis.get_node_or_null("BallBody")
	var ring: MeshInstance3D = ball_att_vis.get_node_or_null("OutlineRing")
	_assert(sphere != null and ring != null, "A2: 白球体+轮廓环在位")
	var sphere_mat: StandardMaterial3D = sphere.material_override
	_assert(sphere_mat.albedo_color == BallScript.BALL_COLOR, "A2: 球体白色")
	_assert(ball_att_vis._ring_mat.albedo_color == BallScript.ATTACK_RING_COLOR, "A2: 攻球红环（_att）")
	ball_att_vis.sync_from_2d(Vector2(-300, 100), 0.0)
	_assert(ball_att_vis.global_position == Vector3(-300, 0, 100), "A2: sync_from_2d 单位制 (x,0,y) 1:1")
	var y0: float = sphere.position.y
	var rot0: float = ring.rotation.y
	for i in range(4):
		await process_frame
	_assert(absf(sphere.position.y - y0) > 0.1, "A2: 悬浮浮动（y 随时间变化）")
	_assert(ring.rotation.y > rot0, "A2: 轮廓环旋转")

	var ball_def = SummonScript.new()
	ball_def.summon_type = "fenny_magic_ball_def"
	root.add_child(ball_def)
	ball_def.setup({"kind": "magic_ball", "hitbox": "circle:18", "lifespan": 25.0,
		"on_ball": {"mode": "grant_item", "item_pool": ["fenny_pan"]}}, 0, {})
	var ball_def_vis: Node3D = BallScript.new()
	root.add_child(ball_def_vis)
	ball_def_vis.setup(ball_def)
	await process_frame
	_assert(ball_def_vis._ring_mat.albedo_color == BallScript.DEFEND_RING_COLOR, "A2: 守球蓝环（_def）")
	# 环色回退：类型名无 _att/_def 后缀时按 on_ball 模式判
	var ball_fallback = SummonScript.new()
	ball_fallback.summon_type = "magic_ball_x"
	root.add_child(ball_fallback)
	ball_fallback.setup({"kind": "magic_ball", "hitbox": "circle:18", "lifespan": 20.0,
		"on_ball": {"mode": "carry_with_ball"}}, 0, {})
	var ball_fb_vis: Node3D = BallScript.new()
	root.add_child(ball_fb_vis)
	ball_fb_vis.setup(ball_fallback)
	await process_frame
	_assert(ball_fb_vis._ring_mat.albedo_color == BallScript.ATTACK_RING_COLOR, "A2: 环色回退（无后缀→on_ball 模式=攻红）")

	# ===== 均匀撒点（主人令：白球随机生成均匀分布在要求场地上；确定性种子）=====
	var pts: Array = BallScript.scatter_positions(64)
	_assert(pts.size() == 64, "撒点: 数量=64")
	var in_bounds := true
	for p in pts:
		if absf(p.x) > 510.0 or absf(p.y) > 325.0:
			in_bounds = false
	_assert(in_bounds, "撒点: 全部落在外场边界内（±510/±325）")
	var pts2: Array = BallScript.scatter_positions(64)
	_assert(pts == pts2, "撒点: 同种子逐点一致（确定性可复现）")
	var pts3: Array = BallScript.scatter_positions(64, 7)
	_assert(pts != pts3, "撒点: 异种子分布不同")
	var min_x := 1e9
	var max_x := -1e9
	var min_y := 1e9
	var max_y := -1e9
	for p in pts:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	_assert((max_x - min_x) >= 1020.0 * 0.85, "撒点: 横向铺展≥85%场宽（均匀覆盖）")
	_assert((max_y - min_y) >= 650.0 * 0.85, "撒点: 纵向铺展≥85%场深（均匀覆盖）")

	# ===== UI 零判定红线 grep（两模型源码无写操作/判定接入模式）=====
	var src_shark: String = SharkScript.source_code
	var src_ball: String = BallScript.source_code
	var bad_patterns: Array[String] = [".state =", "enter_burrow(", "consume(", "spirit_energy",
		"emit_event(", "despawn(", "summon_manager", "subscribe("]
	var clean := true
	for pat in bad_patterns:
		if src_shark.contains(pat) or src_ball.contains(pat):
			clean = false
			print("    命中写操作模式: " + pat)
	_assert(clean, "零判定: 两模型源码无写操作/判定接入（grep 核验；接线仅桥接层只读消费）")

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail == 0:
		print("🎉 全部通过")
	else:
		print("❌ 有失败项")
	quit(0 if _fail == 0 else 1)
