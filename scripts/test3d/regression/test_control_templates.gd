## 工单38 S1~S3 验收套件：操控出口模板系统（schema/校验器/模板库/工作台消费通路）
## 覆盖（38号§G1 最低集）：①schema 校验四查 ②三级回落 ③M1 兜底 ④引用扫描 ⑤版本迁移 ⑥黄金模板
##   +演示场消费通路（工作台改值即时生效）+黑名单动态生成+破坏演练等效（读取口失效→回落不崩）。
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_control_templates.gd
extends SceneTree

const Validator := preload("res://scripts/systems/control_templates/schema_validator.gd")
const PLATFORM_SCENE := "res://scenes/test3d/skill_control_demo_platform.tscn"

var _pass: int = 0
var _fail: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== 工单38：操控出口模板系统验收 ==========\n")
	for i in range(3):
		await process_frame

	# ===== A schema 校验四查 =====
	var ok_tpl: Dictionary = Validator.validate({"ctl_input_operator": "OP_SELECT", "ctl_input_hover_snap": 120.0})
	_assert("A1: 合法模板过校验", ok_tpl.ok and ok_tpl.resolved.get("ctl_input_operator") == "OP_SELECT")
	_assert("A2: 缺键补默认（18 键全集+M1 标记）", ok_tpl.resolved.size() >= Validator.SCHEMAS.size())
	var bl_tpl: Dictionary = Validator.validate({"duration": 5.0, "radius": 100.0})
	_assert("A3: 效果轴键（黑名单）出现=报错", not bl_tpl.ok and bl_tpl.errors.size() >= 2)
	var unk: Dictionary = Validator.validate({"ctl_foo_bar": 1})
	_assert("A4: 未知 ctl_ 键=报错（白名单制）", not unk.ok)
	var bad_type: Dictionary = Validator.validate({"ctl_visual_alpha": "abc"})
	_assert("A5: 类型错=报错", not bad_type.ok)
	var bad_enum: Dictionary = Validator.validate({"ctl_input_operator": "OP_NOPE"})
	_assert("A6: 非法枚举值=报错", not bad_enum.ok)

	# ===== B 黑名单动态生成（A6：registry 增参自动跟随） =====
	var bl: Dictionary = Validator.blacklist()
	_assert("B1: 黑名单动态生成（93 键级）", bl.size() >= 90)
	_assert("B2: 黑名单含抽样品（duration/radius/multiplier/hp）", bl.has("duration") and bl.has("radius") and bl.has("multiplier") and bl.has("hp"))

	# ===== C 三级回落（A9/D2：模板→gold→内置默认，不崩） =====
	var r3: Dictionary = Validator.resolve_params({"ctl_input_operator": "OP_SELECT", "duration": 1.0}, "OP_SELECT")
	_assert("C1: 坏模板回落 gold/默认（不崩+出全键集）", r3.size() >= Validator.SCHEMAS.size() and r3.get("ctl_input_operator") == "OP_SELECT")
	var missing: Dictionary = Validator.read_template_file("res://data/control_templates/no_such.json")
	var r3b: Dictionary = Validator.resolve_params(missing.get("params", {}), "OP_SELECT")
	_assert("C2: 模板文件缺失→gold_op_select 兜底", r3b.get("ctl_input_hover_snap") == 120.0)

	# ===== D M1 兜底（25号闸门） =====
	var m1: Dictionary = Validator.validate({"ctl_visual_model_path": "res://assets/no_such_model.glb"})
	_assert("D1: 假路径=校验报错+model_ok=false（procedural 兜底可测）", not m1.ok and not m1.model_ok)
	var m2: Dictionary = Validator.validate({})
	_assert("D2: 空路径=M1 兜底标记（默认占位）", not m2.model_ok)

	# ===== E 引用扫描（F1/F4） =====
	var refs: Array = Validator.referenced_templates()
	_assert("E1: 现库引用扫描（F2 后：fenny_2/3 挂 gold_op_select=引用×2）", refs.count("gold_op_select") == 2 and refs.size() == 2)
	var refs2: Array = Validator.referenced_templates({"skills": [{"id": "a", "control_template": "ctl_x"}, {"id": "b"}, {"id": "c", "control_template": "ctl_x"}]})
	_assert("E2: 注入引用解析（引用集去重计数）", refs2.size() == 2 and refs2.has("ctl_x"))

	# ===== F 版本迁移（A10） =====
	var old_tpl: Dictionary = Validator.read_template_file("res://data/control_templates/gold_op_select.json")
	_assert("F1: 黄金模板读入+version 存在", old_tpl.get("version", 0) >= 1 and old_tpl.get("operator") == "OP_SELECT")
	var migrated: Dictionary = Validator._migrate({"params": {}})
	_assert("F2: 无 version 旧模板迁移补 version（不崩）", int(migrated.get("version", 0)) >= 1)

	# ===== G0 批2 五模板（ORIENT/TRAIL/GUIDE/TRANSFORM/HOLD——§I 反向抽取） =====
	var five_ok := true
	var five_seen := {}
	for op in ["OP_ORIENT", "OP_TRAIL", "OP_GUIDE", "OP_TRANSFORM", "OP_HOLD"]:
		var gt: Dictionary = Validator.read_template_file("res://data/control_templates/gold_%s.json" % op.to_lower())
		if gt.is_empty() or str(gt.get("operator")) != op:
			five_ok = false
			continue
		var vr: Dictionary = Validator.validate(gt.get("params", {}))
		if not vr.ok:
			five_ok = false
		five_seen[op] = true
	_assert("G7: 批2 五黄金模板加载+校验全过（operator 逐一对账）", five_ok and five_seen.size() == 5)
	var hold_tpl: Dictionary = Validator.read_template_file("res://data/control_templates/gold_op_hold.json")
	_assert("G8: OP_HOLD 模板承载 hold_key/timer（扩展口①参数）", str(hold_tpl.get("params", {}).get("ctl_input_hold_key", "")) == "H" and float(hold_tpl.get("params", {}).get("ctl_time_hold_timer", 0.0)) == 5.0)

	# ===== G 演示场消费通路（工作台改值→演示场即时生效） =====
	var packed: PackedScene = load(PLATFORM_SCENE)
	var platform: Node3D = packed.instantiate()
	root.add_child(platform)
	_assert("G1: 平台工作台模板装载（gold_op_select resolved）", platform.workbench_template.get("ctl_input_operator") == "OP_SELECT")
	_assert("G2: runner env.template=同一副本引用（即时生效通路）", platform.runner.env.get("template") == platform.workbench_template)
	platform.workbench_template["ctl_input_hover_snap"] = 60.0
	_assert("G3: 工作台改值→剧本 tpl() 立即可读", float(platform.runner.tpl("ctl_input_hover_snap", 0.0)) == 60.0)
	var draft_ok: bool = Validator.save_draft("op_select_draft_test", {"version": 1, "source": "workbench", "operator": "OP_SELECT", "params": platform.workbench_template})
	var back: Dictionary = Validator.read_template_file(Validator.DRAFT_DIR + "op_select_draft_test.json")
	_assert("G4: 草稿保存/加载往返（user://）", draft_ok and int(back.get("version", 0)) == 1 and back.get("params", {}).has("ctl_input_hover_snap"))
	var pub_probe: Dictionary = Validator.validate(platform.workbench_template)
	print("[DBG-G5] ok=%s errors=%s" % [str(pub_probe.ok), str(pub_probe.errors)])
	var pub_ok: bool = Validator.save_published("ctl_publish_test", {"version": 1, "source": "workbench", "operator": "OP_SELECT", "params": platform.workbench_template})
	_assert("G5: 发布实战库往返（校验过才写 data/）", pub_ok and Validator.read_template_file(Validator.GOLD_DIR + "ctl_publish_test.json").has("params"))
	var pub_bad: bool = Validator.save_published("ctl_publish_bad", {"version": 1, "params": {"duration": 1.0}})
	_assert("G6: 黑名单参数发布=拒绝（fail-closed）", not pub_bad)

	# ===== G10 批4 开发系统对接（ssm 读取口源码指纹+面板只读行+版本报告） =====
	var ssm_src := _read_file("res://scripts/systems/spirit_system/skill_state_manager.gd")
	_assert("G10a: ssm 模板读取口已挂（_template_val 单一出口+消费点×2+缓存键含 skill_id）", ssm_src.count("_template_val(") >= 3 and ssm_src.contains('tid + ":" + skill_id') and ssm_src.contains("ControlTemplateValidator"))
	var panel_src := _read_file("res://scripts/dev_tools/dev_spirit_panel.gd")
	_assert("G10b: 元灵面板只读行（E3：操控模板展示）", panel_src.contains("操控模板："))
	_assert("G10e: 技能弹窗操控模板下拉（快速套用写 control_template）", panel_src.contains("ControlTemplateOption") and panel_src.contains("skill_data[\"control_template\"] = ctl_option.get_item_text"))
	# G10c 复核修复行为断言（10-23）：两技能共模板缓存隔离+lock_snap 可读
	var ssm = load("res://scripts/systems/spirit_system/skill_state_manager.gd").new()
	ssm._operator_context = {999: {"skill_id": "fenny_2"}, 998: {"skill_id": "fenny_3"}}
	var v1: float = ssm._template_val(999, "ctl_input_hover_snap", 120.0)
	var v2v: float = ssm._template_val(998, "ctl_input_hover_snap", 120.0)
	var ck_keys: Array = []
	for ck in ssm._tpl_cache:
		ck_keys.append(ck)
	var iso_ok: bool = ck_keys.size() == 2
	for ck in ck_keys:
		if not str(ck).contains(":"):
			iso_ok = false
	_assert("G10c: 两技能共模板缓存隔离（tid:skill_id 各自条目+值相等）", iso_ok and v1 == 120.0 and v2v == 120.0)
	_assert("G10d: lock_snap 经单一出口可读（实战挂点 v2 接入）", float(ssm._template_val(999, "ctl_input_lock_snap", 150.0)) == 150.0)
	var rep: Dictionary = Validator.template_version_report()
	_assert("G9: 版本报告（sim 规矩③④：total>=18+F2 引用分级正确）", int(rep.get("total", 0)) >= 18 and (rep.get("referenced") as Array).has("gold_op_select") and not ((rep.get("demo") as Array).has("gold_op_select")))
	_assert("G9b: F2 引用生效（fenny_2/3 挂模板→实战模板分级）", Validator.referenced_templates().count("gold_op_select") == 2)

	# ===== I 缺口修复验证（13.2 sim 规矩①+13.3 消费点闭环） =====
	var sm_src := _read_file("res://scripts/systems/summon/summon_manager.gd")
	_assert("I1: 缺口一：summon_manager 无裸 randf_range（指纹）", not sm_src.contains("randf_range") and sm_src.contains("_spawn_roll"))
	var dyn := GDScript.new()
	dyn.source_code = "extends Node\nvar team := \"a\"\n"
	dyn.reload()
	var mock: Node = dyn.new()
	var sm = load("res://scripts/systems/summon/summon_manager.gd").new()
	sm._types["fenny_ball_test"] = {"spawn_hint": "enemy_outer_random"}   # 白名单测试条目：走外场散布分支
	var p1: Vector2 = sm.resolve_spawn_position("fenny_ball_test", mock)
	var p2v: Vector2 = sm.resolve_spawn_position("fenny_ball_test", mock)
	_assert("I2: 缺口一：同场次连续两颗=确定性散布（带界内且不全等）", p1.x >= 385.0 and p1.x <= 505.0 and p1.y >= -320.0 and p1.y <= 320.0 and not (p1 == p2v or (absf(p1.x - p2v.x) < 0.01 and absf(p1.y - p2v.y) < 0.01)) or p1.distance_to(p2v) > 1.0)
	var sm2 = load("res://scripts/systems/summon/summon_manager.gd").new()
	sm2._types["fenny_ball_test"] = {"spawn_hint": "enemy_outer_random"}
	var p3: Vector2 = sm2.resolve_spawn_position("fenny_ball_test", mock)
	_assert("I3: 缺口一：同输入恒同输出（fresh 实例逐位一致）", p1 == p3)
	# 13.3-4 闭环机检：工单附录对照表 18 键逐键标注
	var order_doc := _read_file("res://操控与基础Ui规划/38_操控出口工单.md")
	var keys_ok := true
	for key in Validator.SCHEMAS:
		if not order_doc.contains("| " + key + " |"):
			keys_ok = false
	_assert("I4: 13.3 闭环：工单附录对照表 18 键逐键标注（消费/挂账）", keys_ok)
	# 13.3-3 新消费端行为抽测（fp_cross 转发/enter_fx fade/model apply）
	var platform2: Node3D = load(PLATFORM_SCENE).instantiate()
	root.add_child(platform2)
	var r2 = platform2.runner
	r2.env["template"]["ctl_input_view_mode"] = "fp_cross"
	r2.switch_to("whiteball_select")
	r2.advance("activate")
	_assert("I5: view_mode=fp_cross→OP_SELECT 自动走 FP 准星变体", r2.phase == "fp_scan" and platform2.fp_active)
	platform2.enter_fp(false)
	r2.clear_script()
	r2.env["template"]["ctl_time_enter_fx"] = "fade"
	r2.switch_to("auto")
	r2.advance("activate")
	var auto_ph = r2.ph
	var faded: bool = auto_ph != null and auto_ph.mat != null and auto_ph.mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and auto_ph.mat.albedo_color.a < 0.1
	_assert("I6: enter_fx=fade→占位淡入起步（透明起步）", faded)
	r2.env["template"]["ctl_visual_model_path"] = "res://assets/game_models/battleball.glb"
	r2.env["template"]["_model_ok"] = true
	r2.clear_script()
	r2.switch_to("whiteball_select")
	r2.advance("activate")
	var ball_node = (r2.flags.get("balls", [{}])[0].get("node"))
	var has_model := false
	if ball_node != null:
		for c in ball_node.get_children():
			if c is Node3D and not (c is MeshInstance3D):
				has_model = true
	_assert("I7: model_path 有效→对象占位自动替换真模型（25号闸门正走向）", has_model)
	platform2.queue_free()

	# ===== H 破坏演练等效（G2：读取口失效→回落不崩） =====
	var broken: Dictionary = Validator.resolve_params({"ctl_input_operator": "OP_SELECT", "ctl_input_hover_snap": "bad_type"}, "OP_SELECT")
	_assert("H1: 校验口失效（类型坏）→回落不崩+全键集", broken.size() >= Validator.SCHEMAS.size())
	_assert("H2: 黄金模板仍在回归位（改模板系统必跑）", FileAccess.file_exists(ProjectSettings.globalize_path("res://data/control_templates/gold_op_select.json")))

	platform.queue_free()
	print("\n---------- 结果：%d 过 / %d 败 ----------" % [_pass, _fail])
	print("========== 工单38 模板系统验收结束 ==========\n")
	quit(1 if _fail > 0 else 0)


func _read_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


func _assert(name: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("  ✅ " + name)
	else:
		_fail += 1
		print("  ❌ " + name)
