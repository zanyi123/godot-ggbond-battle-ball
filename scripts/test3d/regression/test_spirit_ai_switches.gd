## 08集成基建工单 §五 测试矩阵：S1-默认 / S2-总开关 / S3-分波 / S4-fail-closed / S5-聚合 / R-纪律
## 三文件白名单（switches.json / primitive_registry.gd / 本文件）由窗口在 commit 前以
## git status 外部核对恰为白名单。测试注入一律写 user:// 临时文件（不污染仓库）。
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_spirit_ai_switches.gd
extends SceneTree

const Registry = preload("res://scripts/battle/spirit_ai/primitive_registry.gd")

var _pass: int = 0
var _fail: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== 08集成基建：原语开关矩阵 ==========\n")
	for i in range(3):
		await process_frame

	# ===== S1-默认：无 switches.json / 全关 → 任意 tag 返回 {} =====
	Registry.reload_switches("user://__no_switches_file__.json")
	_assert("S1a: switches.json 不存在 → 波A标签返回 {}", Registry.get_descriptor("ball_dmg_up_pct").is_empty())
	_assert("S1b: 不存在 → is_wave_enabled(A)=false", not Registry.is_wave_enabled("A"))
	Registry.reload_switches()  # 仓库内真实 switches.json（默认全关）
	_assert("S1c: 全关（默认）→ 波A描述符存在但返回 {}", Registry.get_descriptor("ball_dmg_up_pct").is_empty())
	_assert("S1d: 全关 → 任意未知 tag 同样返回 {}", Registry.get_descriptor("__no_such_tag__").is_empty())
	var real_raw = JSON.parse_string(FileAccess.get_file_as_string(Registry.SWITCHES_PATH))
	_assert("S1e: 仓库默认文件 master_enabled=false（主游戏稳定默认）",
			real_raw is Dictionary and real_raw.get("master_enabled") == false)

	# ===== S2-总开关：master=true + waveA=true 可查得；master=false 同 tag 返回 {} =====
	var sw_on: String = _write_temp("t_sw_on.json",
			{"schema_version": 1, "master_enabled": true, "waves": {"A": true, "B": false, "C": false, "D": false, "E": false}})
	Registry.reload_switches(sw_on)
	var d: Dictionary = Registry.get_descriptor("ball_dmg_up_pct")
	_assert("S2a: 总开关+波A开 → 描述符可查得", not d.is_empty() and str(d.get("family", "")) == "ball_stat")
	var sw_off: String = _write_temp("t_sw_off.json",
			{"schema_version": 1, "master_enabled": false, "waves": {"A": true}})
	Registry.reload_switches(sw_off)
	_assert("S2b: master=false → 同一 tag 返回 {}（整体旁路）", Registry.get_descriptor("ball_dmg_up_pct").is_empty())

	# ===== S3-分波：仅A开 → A 可查；B 描述符存在但返回 {}；未知波次字母视同关 =====
	var fake_b: String = _write_temp("t_fake_wave_b.json", {
		"schema_version": 1, "wave": "B",
		"descriptors": {"fake_b_tag": {"family": "player_attr", "direction": "self", "timing_gate": "always",
			"value_param": "value", "value_unit": 1.0, "value_min": 15.0, "value_cap": 50.0,
			"intent": "defense", "intent_strength": 0.5, "target_mode": "self", "notes": "S3注入"}},
	})
	var fake_z: String = _write_temp("t_fake_wave_z.json", {
		"schema_version": 1, "wave": "Z",
		"descriptors": {"fake_z_tag": {"family": "ball_stat", "direction": "self", "timing_gate": "always",
			"value_param": "value", "value_unit": 1.0, "value_min": 15.0, "value_cap": 50.0,
			"intent": "attack", "intent_strength": 0.5, "target_mode": "ball", "notes": "S3注入"}},
	})
	var paths: Array = [Registry.WAVE_TABLES[0], fake_b, fake_z]
	Registry._agg = Registry._aggregate(paths)
	Registry._agg_loaded = true
	Registry.reload_switches(sw_on)  # master=true, 仅A开
	_assert("S3a: 仅A开 → 波A tag 可查", not Registry.get_descriptor("ball_dmg_up_pct").is_empty())
	_assert("S3b: B 描述符已聚合但波未开 → 返回 {}", Registry.get_descriptor("fake_b_tag").is_empty())
	_assert("S3c: 未知波次字母 Z 视同关 → 返回 {}", Registry.get_descriptor("fake_z_tag").is_empty())
	Registry.reload_switches(_write_temp("t_sw_ab.json",
			{"schema_version": 1, "master_enabled": true, "waves": {"A": true, "B": true}}))
	_assert("S3d: 开B后 → B 描述符可查得（分波独立控制）",
			not Registry.get_descriptor("fake_b_tag").is_empty())

	# ===== S4-fail-closed：坏 JSON / 缺 waves / 非法值 → 视同全关，不崩溃 =====
	var bad: String = _write_temp("t_sw_bad.json", {})
	var f: FileAccess = FileAccess.open(bad, FileAccess.WRITE)
	f.store_string("{ master_enabled : not json !!!")
	f.close()
	Registry.reload_switches(bad)
	_assert("S4a: 坏 JSON → 视同全关不崩溃", not Registry.is_wave_enabled("A"))
	Registry.reload_switches(_write_temp("t_sw_nowaves.json", {"schema_version": 1, "master_enabled": true}))
	_assert("S4b: 缺 waves 字段 → 视同全关", not Registry.is_wave_enabled("A"))
	Registry.reload_switches(_write_temp("t_sw_illmaster.json",
			{"schema_version": 1, "master_enabled": "yes", "waves": {"A": true}}))
	_assert("S4c: master 非布尔 → 视同全关", not Registry.is_wave_enabled("A"))
	Registry.reload_switches(_write_temp("t_sw_illwave.json",
			{"schema_version": 1, "master_enabled": true, "waves": {"A": "on"}}))
	_assert("S4d: 波值非布尔 → 视同关", not Registry.is_wave_enabled("A"))

	# ===== S5-聚合：wave 字段打标；同 tag_id 冲突后加载者覆盖并告警 =====
	var fake_x: String = _write_temp("t_dup_x.json", {
		"schema_version": 1, "wave": "X",
		"descriptors": {"dup_tag": {"family": "ball_stat", "direction": "self", "timing_gate": "always",
			"value_param": "value", "value_unit": 1.0, "value_min": 15.0, "value_cap": 50.0,
			"intent": "attack", "intent_strength": 0.5, "target_mode": "ball", "notes": "先加载"}},
	})
	var fake_y: String = _write_temp("t_dup_y.json", {
		"schema_version": 1, "wave": "Y",
		"descriptors": {"dup_tag": {"family": "player_attr", "direction": "self", "timing_gate": "always",
			"value_param": "value", "value_unit": 1.0, "value_min": 15.0, "value_cap": 50.0,
			"intent": "defense", "intent_strength": 0.5, "target_mode": "self", "notes": "后加载覆盖"}},
	})
	var agg: Dictionary = Registry._aggregate([fake_x, fake_y])
	var dup: Dictionary = agg.get("dup_tag", {})
	_assert("S5a: 同 tag 冲突 → 后加载者覆盖", str(dup.get("wave", "")) == "Y"
			and str(dup.get("descriptor", {}).get("family", "")) == "player_attr")
	var agg_a: Dictionary = Registry._aggregate([Registry.WAVE_TABLES[0]])
	_assert("S5b: 顶层 wave 字段正确打标（波A全部标 A）", _all_wave_a(agg_a))
	print("  ℹ S5 告警核对人肉项：上方 stderr 应含『tag_id 跨波冲突』push_warning 一条")

	# ===== R-纪律：registry 源码无随机函数调用 =====
	var src: String = FileAccess.get_file_as_string("res://scripts/battle/spirit_ai/primitive_registry.gd")
	_assert("R1: primitive_registry.gd 无 randf/randf_range 调用",
			src.find("randf(") == -1 and src.find("randf_range") == -1)
	_assert("R2: primitive_registry.gd 无 randi 调用", src.find("randi(") == -1)

	# ===== 清理：恢复真实开关与真实聚合（不留测试态）=====
	Registry.reload_switches()
	Registry._agg = Registry._aggregate(Registry.WAVE_TABLES)
	Registry._agg_loaded = true
	for p in [sw_on, sw_off, fake_b, fake_z, bad]:
		DirAccess.remove_absolute(p)

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 08开关矩阵全部通过！")
	quit(1 if _fail > 0 else 0)


func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)


func _write_temp(name: String, data: Dictionary) -> String:
	var path: String = "user://" + name
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return path


func _all_wave_a(agg: Dictionary) -> bool:
	if agg.size() != 39:
		return false
	for tag_id in agg.keys():
		if str(agg[tag_id].get("wave", "")) != "A":
			return false
	return true
