## 操控出口验收 · 数据层门禁（DSH验收操控出口工作规范 §四 G3 / D1~D8）
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_data_gate.gd
## 只读：不改数据；D8 用前后原文比对证明测试过程零污染。
extends SceneTree

const SKILLS_PATH := "res://data/spirits/skills.json"
const SPIRITS_PATH := "res://data/spirits/spirits.json"
const LOADOUT_PATH := "res://data/systems/spirit_ai/test_loadouts.json"
const TARGET_SKILL := "skill_冰雪_2"
const TARGET_SPIRIT := "spirit_1"

var _pass: int = 0
var _fail: int = 0
var _raw: Dictionary = {}

func _initialize() -> void:
	_run()

func _assert(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  ✅ PASS: " + name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + name)

func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s

func _parse(path: String) -> Dictionary:
	var s := _read(path)
	if s.is_empty():
		return {}
	var v: Variant = JSON.parse_string(s)
	return v if v is Dictionary else {}

func _run() -> void:
	print("\n========== 操控出口 · 数据层门禁 D1~D8 ==========\n")
	for p in [SKILLS_PATH, SPIRITS_PATH, LOADOUT_PATH]:
		_raw[p] = _read(p)
	var skills_d := _parse(SKILLS_PATH)
	var spirits_d := _parse(SPIRITS_PATH)
	var loadout_d := _parse(LOADOUT_PATH)
	var skills: Array = skills_d.get("skills", [])
	var spirits: Array = spirits_d.get("spirits", [])
	var test_spirits: Array = loadout_d.get("test_spirits", [])

	# D1 可解析 + id 唯一
	_assert(not skills.is_empty(), "D1a: skills.json 可解析（%d 条）" % skills.size())
	var ids := {}
	var dup := []
	for s in skills:
		var sid := str(s.get("id", ""))
		if ids.has(sid):
			dup.append(sid)
		ids[sid] = true
	_assert(dup.is_empty(), "D1b: 技能 id 唯一（重复=%s）" % str(dup))

	# D2 新技能必须被某个元灵持有
	var holders: Array = []
	for sp in spirits:
		if TARGET_SKILL in (sp.get("skills", []) as Array):
			holders.append(str(sp.get("id", "")))
	_assert(not holders.is_empty(), "D2: %s 被元灵持有（holders=%s）" % [TARGET_SKILL, str(holders)])

	# D2b 目标技能操控轴完整（本轮验收对象=fenny_2；新建克隆会触发 38 套件硬编码引用×2，
	# 按规范「不许改断言压红」改用既有技能走元灵持有链，克隆路径作为问题上报）
	var target := {}
	for s in skills:
		if str(s.get("id", "")) == TARGET_SKILL:
			target = s
	var tps: Dictionary = target.get("tag_params", {}).get("summon_spawn", {}) if target.get("tag_params", {}).get("summon_spawn", {}) is Dictionary else {}
	var axis_ok: bool = not target.is_empty() \
			and str(target.get("operator", "")) == "OP_STEER" \
			and (target.get("tags", []) as Array).has("summon_spawn") \
			and str(tps.get("summon_type", "")) == "shuimu_shark_att"
	_assert(axis_ok, "D2b: 目标技能操控轴完整（OP_STEER + summon_spawn→shuimu_shark_att）")

	# D3 元灵持有闭包：元灵引用的每个 skill id 都存在于 skills.json
	var missing: Array = []
	for sp in spirits:
		for sid in (sp.get("skills", []) as Array):
			if not ids.has(str(sid)):
				missing.append("%s→%s" % [str(sp.get("id", "")), str(sid)])
	_assert(missing.is_empty(), "D3: 元灵持有闭包（缺失=%s）" % str(missing))

	# D4 带 control_template 的技能：模板文件存在 + schema 校验通过
	var SV = load("res://scripts/systems/control_templates/schema_validator.gd")
	var tpl_bad: Array = []
	for s in skills:
		var tid := str(s.get("control_template", ""))
		if tid.is_empty():
			continue
		var tpl: Dictionary = SV.read_template_file(SV.GOLD_DIR + tid + ".json")
		if tpl.is_empty():
			tpl_bad.append("%s:模板缺失(%s)" % [str(s.get("id", "")), tid])
			continue
		var vr: Dictionary = SV.validate(tpl.get("params", {}) as Dictionary)
		if not bool(vr.get("ok", false)):
			tpl_bad.append("%s:%s" % [str(s.get("id", "")), str(vr.get("errors", []))])
	_assert(tpl_bad.is_empty(), "D4: 模板存在且过 schema（坏项=%s）" % str(tpl_bad))

	# D5 operator ∈ 18；tags 不得混入 ctl_ 键
	var op_bad: Array = []
	var tag_bad: Array = []
	for s in skills:
		var op := str(s.get("operator", ""))
		# 存量技能可缺 operator（ssm normalize_operator 归一到 OP_AUTO）；显式写了就必须在 18 内
		if op != "" and not op in SV.OPERATORS_18:
			op_bad.append("%s=%s" % [str(s.get("id", "")), op])
		for t in (s.get("tags", []) as Array):
			if str(t).begins_with("ctl_"):
				tag_bad.append("%s→%s" % [str(s.get("id", "")), str(t)])
	_assert(op_bad.is_empty(), "D5a: operator ∈ 18 枚举（越界=%s）" % str(op_bad))
	_assert(tag_bad.is_empty(), "D5b: tags 无 ctl_ 键（混入=%s，DR2）" % str(tag_bad))

	# D6 装载入口能解析到目标元灵与技能
	var lo_hit := {}
	for sp in test_spirits:
		if str(sp.get("id", "")) == TARGET_SPIRIT:
			lo_hit = sp
	var lo_ok: bool = not lo_hit.is_empty() and TARGET_SKILL in (lo_hit.get("skills", []) as Array)
	_assert(lo_ok, "D6: test_loadouts 可解析目标元灵与技能")

	# D7 DataManager 能查回该元灵（模拟备战界面取数）
	var dm = load("res://scripts/core/data_manager.gd").new()
	dm.spirits = dm._load_spirits_array()
	var sp7: Dictionary = dm.get_spirit_by_id(TARGET_SPIRIT)
	_assert(not sp7.is_empty() and TARGET_SKILL in (sp7.get("skills", []) as Array), "D7: DataManager.spirits 可查回目标元灵（%d 元灵）" % dm.spirits.size())
	dm.free()

	# D8 测试前后原文逐字一致（只读证明）
	var changed: Array = []
	for p in [SKILLS_PATH, SPIRITS_PATH, LOADOUT_PATH]:
		if _read(p) != str(_raw[p]):
			changed.append(p)
	_assert(changed.is_empty(), "D8: 测试后数据原文一致（污染=%s）" % str(changed))

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	quit(0 if _fail == 0 else 1)
