## 操2 验收：元灵管理"操作方式"选择器（操控规划/03 操2 / 04 三·大点1~3；headless 可跑）
## 覆盖：枚举源一致 / 选择→保存→重载回显 / passive+非AUTO 拦截 / MIDFLY·TOGGLE params 校验 /
##       徽标映射覆盖 / 落盘清洁（备份→临时数据→还原一致，R1：不碰真实技能条目）
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_operator_selector.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0
var _raw_backup: String = ""


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== 操2 操作方式选择器测试 ==========\n")
	for i in range(3):
		await process_frame

	var panel_script: GDScript = load("res://scripts/dev_tools/dev_spirit_panel.gd")
	var sm_script: GDScript = load("res://scripts/systems/spirit_system/skill_state_manager.gd")

	# ===== ① 枚举源一致：面板读 skill_state_manager.OPERATORS，共 12 项 =====
	var ops: Array = panel_script.get_operator_list()
	_assert("枚举: 面板 get_operator_list 读取 12 项", ops.size() == 12)
	_assert("枚举: 与 skill_state_manager.OPERATORS 同源", str(ops) == str(sm_script.OPERATORS))
	var expect_ops := ["OP_AUTO", "OP_AIM", "OP_POINT", "OP_MARK", "OP_STEER", "OP_MIDFLY",
		"OP_TOGGLE", "OP_KEY_JUMP", "OP_PLACE", "OP_SUMMON", "OP_FP", "OP_COMBO"]
	_assert("枚举: 12 类名逐一匹配工单定义", str(ops) == str(expect_ops))

	# ===== ② 徽标映射：OPERATOR_LABELS 覆盖 12 枚举，非 AUTO 简称非空 =====
	var labels: Dictionary = panel_script.OPERATOR_LABELS
	var labels_ok := true
	for op in ops:
		if not labels.has(str(op)):
			labels_ok = false
		elif str(op) != "OP_AUTO" and str(labels[op]).strip_edges() == "":
			labels_ok = false
	_assert("徽标: OPERATOR_LABELS 覆盖 12 枚举且非AUTO简称非空", labels_ok)

	# ===== ③ 选择→保存→重载回显（走 14 保存链路；R1 备份在先）=====
	_raw_backup = FileAccess.get_file_as_string("res://data/spirits/skills.json")
	_assert("前置: skills.json 原文可读且非空", _raw_backup.length() > 100)
	var base_count: int = DevDataSync.load_skills().size()

	var skills: Array = DevDataSync.load_skills()
	var temp_skill := {"id": "test_op_sel_1", "name": "临时操作方式测试技", "type": "active",
		"element": "雷火", "energy_cost": 10.0, "cooldown": 5.0,
		"tags": ["ball_dmg_up_pct"], "tag_params": {"ball_dmg_up_pct": {"value": 20.0}},
		"operator": "OP_AIM", "description": "t", "icon_color": "#FFFFFF", "icon_path": ""}
	skills.append(temp_skill)
	_assert("保存: save_skills 返回 true", DevDataSync.save_skills(skills) == true)
	var reloaded: Array = DevDataSync.load_skills()
	var echo := ""
	for s in reloaded:
		if str(s.get("id", "")) == "test_op_sel_1":
			echo = str(s.get("operator", ""))
	_assert("回显: OP_AIM 选择→保存→重载一致", echo == "OP_AIM")

	# 编辑改 TOGGLE 档 → 重载回显
	for s in reloaded:
		if str(s.get("id", "")) == "test_op_sel_1":
			s["operator"] = "OP_TOGGLE"
	DevDataSync.save_skills(reloaded)
	var echo2 := ""
	for s in DevDataSync.load_skills():
		if str(s.get("id", "")) == "test_op_sel_1":
			echo2 = str(s.get("operator", ""))
	_assert("回显: 编辑改 OP_TOGGLE→重载一致", echo2 == "OP_TOGGLE")

	# 缺省路径：无 operator 字段的存量条目回落 AUTO（向后兼容）
	var no_op_ok := true
	for s in DevDataSync.load_skills():
		if str(s.get("id", "")) == "test_op_sel_1":
			continue
		if s.has("operator"):
			no_op_ok = false
	_assert("兼容: 存量条目无 operator 字段（缺省 AUTO 语义）", no_op_ok)

	# ===== ④ 组合校验（04 大点2，validate_skill_data 拦截）=====
	var existing: Array = DevDataSync.load_skills()
	# ④a passive + 非 AUTO 拦截
	var bad_passive := {"id": "x_op1", "name": "t", "type": "passive", "tags": [], "tag_params": {},
		"trigger": {"event": "Hit.TAKEN"}, "operator": "OP_STEER"}
	var e1: Array[String] = DevDataSync.validate_skill_data(bad_passive, existing, "")
	_assert("校验: passive+OP_STEER 被拦截", e1.any(func(e): return e.contains("被动")))
	# ④b MIDFLY 缺 params 拦截
	var bad_midfly := {"id": "x_op2", "name": "t", "type": "active", "tags": [], "tag_params": {},
		"operator": "OP_MIDFLY"}
	var e2: Array[String] = DevDataSync.validate_skill_data(bad_midfly, existing, "")
	_assert("校验: OP_MIDFLY 缺 params 被拦截", e2.any(func(e): return e.contains("MIDFLY")))
	# ④c MIDFLY 带 ball_recall(max_times) 通过
	var good_midfly := {"id": "x_op3", "name": "t", "type": "active",
		"tags": ["ball_recall"], "tag_params": {"ball_recall": {"max_times": 2}},
		"operator": "OP_MIDFLY"}
	var e3: Array[String] = DevDataSync.validate_skill_data(good_midfly, existing, "")
	_assert("校验: OP_MIDFLY 带 ball_recall 通过", e3.is_empty())
	# ④d TOGGLE 缺 mode 拦截 / 带 mode 通过
	var bad_toggle := {"id": "x_op4", "name": "t", "type": "active", "tags": [], "tag_params": {},
		"operator": "OP_TOGGLE"}
	var e4: Array[String] = DevDataSync.validate_skill_data(bad_toggle, existing, "")
	_assert("校验: OP_TOGGLE 缺 mode=toggle 被拦截", e4.any(func(e): return e.contains("TOGGLE")))
	var good_toggle := {"id": "x_op5", "name": "t", "type": "active", "tags": [], "tag_params": {},
		"operator": "OP_TOGGLE", "mode": "toggle"}
	var e5: Array[String] = DevDataSync.validate_skill_data(good_toggle, existing, "")
	_assert("校验: OP_TOGGLE 带 mode=toggle 通过", e5.is_empty())
	# ④e 非法枚举拦截
	var bad_enum := {"id": "x_op6", "name": "t", "type": "active", "tags": [], "tag_params": {},
		"operator": "OP_NOPE"}
	var e6: Array[String] = DevDataSync.validate_skill_data(bad_enum, existing, "")
	_assert("校验: 非法枚举 OP_NOPE 被拦截", e6.any(func(e): return e.contains("枚举")))
	# ④f 12 枚举逐个合法（active 基础条目，除 TOGGLE 补 mode/MIDFLY 补 params 外无 operator 报错）
	var all_enum_ok := true
	for op in ops:
		var probe := {"id": "x_probe", "name": "t", "type": "active", "tags": [], "tag_params": {},
			"operator": str(op)}
		if str(op) == "OP_TOGGLE":
			probe["mode"] = "toggle"
		if str(op) == "OP_MIDFLY":
			probe["tags"] = ["ball_recall"]
			probe["tag_params"] = {"ball_recall": {"max_times": 1}}
		var es: Array[String] = DevDataSync.validate_skill_data(probe, existing, "")
		if es.any(func(e): return e.contains("operator") or e.contains("操作方式")):
			all_enum_ok = false
	_assert("校验: 12 枚举合法值全部不报 operator 错", all_enum_ok)

	# ===== ⑤ 落盘清洁：删除临时技+还原原文 =====
	var wf := FileAccess.open("res://data/spirits/skills.json", FileAccess.WRITE)
	wf.store_string(_raw_backup)
	wf.close()
	var clean: bool = FileAccess.get_file_as_string("res://data/spirits/skills.json") == _raw_backup
	_assert("落盘清洁: 测试后 skills.json 与原文一致 (git diff 空)", clean and DevDataSync.load_skills().size() == base_count)

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 全部通过！（skills.json 已还原）")
	quit(1 if _fail > 0 else 0)


func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)
