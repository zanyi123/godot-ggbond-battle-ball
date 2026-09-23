## 工单14 验收：元灵管理保存链路 + F5 合法性校验（headless 可跑）
## 落盘测试走真实 save_skills/load_skills 路径；开始备份原文、结束还原（R1 落盘清洁）
## 运行：Godot_console.exe --headless --script res://scripts/test3d/regression/test_dev_skill_save.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0
var _raw_backup: String = ""


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== 元灵管理保存链路测试 ==========\n")
	for i in range(3):
		await process_frame

	# 备份 skills.json 原文（R1 落盘清洁）
	_raw_backup = FileAccess.get_file_as_string("res://data/spirits/skills.json")
	_assert("前置: skills.json 原文可读且非空", _raw_backup.length() > 100)

	var base_count: int = DevDataSync.load_skills().size()

	# ===== ① 新建→保存→load→数据在且字段完整 =====
	var new_skill := {"id": "test_save_1", "name": "临时测试技", "type": "active",
		"element": "雷火", "energy_cost": 15.0, "cooldown": 5.0,
		"tags": ["ball_dmg_up_pct"], "tag_params": {"ball_dmg_up_pct": {"value": 20.0}},
		"description": "t", "icon_color": "#FFFFFF", "icon_path": ""}
	var skills: Array = DevDataSync.load_skills()
	skills.append(new_skill)
	_assert("新建: save_skills 返回 true", DevDataSync.save_skills(skills) == true)
	var reloaded: Array = DevDataSync.load_skills()
	var found: Dictionary = {}
	for s in reloaded:
		if str(s.get("id", "")) == "test_save_1":
			found = s
	_assert("新建: 重载后数据在", not found.is_empty())
	_assert("新建: 字段完整 (tags/tag_params/energy_cost)", \
		found.get("tags", []).size() == 1 and float(found.get("energy_cost", 0)) == 15.0 \
		and not found.get("tag_params", {}).is_empty())

	# ===== ② 编辑→保存→重载→修改生效 =====
	found["energy_cost"] = 33.0
	_assert("编辑: save_skills 返回 true", DevDataSync.save_skills(reloaded) == true)
	var reloaded2: Array = DevDataSync.load_skills()
	var got33 := false
	for s in reloaded2:
		if str(s.get("id", "")) == "test_save_1":
			got33 = absf(float(s.get("energy_cost", 0)) - 33.0) < 0.01
	_assert("编辑: 修改生效 (33)", got33)

	# ===== ③ 删除→保存→重载→消失 =====
	var without: Array = []
	for s in reloaded2:
		if str(s.get("id", "")) != "test_save_1":
			without.append(s)
	_assert("删除: save_skills 返回 true", DevDataSync.save_skills(without) == true)
	var gone := true
	for s in DevDataSync.load_skills():
		if str(s.get("id", "")) == "test_save_1":
			gone = false
	_assert("删除: 重载后消失", gone)

	# ===== ④⑤⑥ F5 校验（纯逻辑：注入面板成员）=====
	var existing: Array = [{"id": "exist_1", "name": "已有"}]
	var bad_tag := {"id": "x1", "name": "t", "type": "active", "tags": ["不存在的标签"], "tag_params": {}}
	var e1: Array[String] = DevDataSync.validate_skill_data(bad_tag, existing, "")
	_assert("校验: 非法标签 id 被阻断", e1.any(func(e): return e.contains("标签不存在")))
	var dup := {"id": "exist_1", "name": "t", "type": "active", "tags": [], "tag_params": {}}
	var e2: Array[String] = DevDataSync.validate_skill_data(dup, existing, "")
	_assert("校验: 重复 id 被阻断", e2.any(func(e): return e.contains("重复")))
	var bad_passive := {"id": "x2", "name": "t", "type": "passive", "tags": [], "tag_params": {}, "trigger": {}}
	var e3: Array[String] = DevDataSync.validate_skill_data(bad_passive, existing, "")
	_assert("校验: passive 缺 trigger 被阻断", e3.any(func(e): return e.contains("trigger.event")))
	var good_passive := {"id": "x3", "name": "t", "type": "passive", "tags": [], "tag_params": {},
		"trigger": {"event": "Hit.TAKEN"}}
	var e4: Array[String] = DevDataSync.validate_skill_data(good_passive, existing, "")
	_assert("校验: 合法 passive 通过", e4.is_empty())

	# ===== ⑦ 保存后文件人类可读 JSON =====
	var raw: String = FileAccess.get_file_as_string("res://data/spirits/skills.json")
	var parsed: Variant = JSON.parse_string(raw)
	_assert("格式: 保存后为可解析 JSON 且带缩进(tab)", parsed is Dictionary and raw.contains("\n\t"))

	# ===== ⑧ 落盘清洁：还原原文 =====
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
