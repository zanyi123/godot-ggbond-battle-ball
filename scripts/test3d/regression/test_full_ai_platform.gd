## 工单10 P4 验收套件：完全体AI测试平台（平台窗口）
## 覆盖：装载器纯函数 / 出厂装载配置对账 / fail-closed / 开关热切往返（user:// 临时文件，零仓库数据触碰）/
##       平台与观测层脚本完整性 / sim 隔离护栏。
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_full_ai_platform.gd
extends SceneTree

const Registry := preload("res://scripts/battle/spirit_ai/primitive_registry.gd")

const TEMP_SWITCHES := "user://_switches_platform_test.json"

var _pass: int = 0
var _fail: int = 0
# ⚠ 装载器引用 DataManager（autoload）——-s 启动链上 preload 会在 autoload 注册前编译而失败，
#   必须等 autoload 就位后运行时 load（test_wave3_primitives 同款纪律）
var LoadoutLoader: GDScript = null


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== 工单10 P4：完全体AI测试平台验收 ==========\n")
	for i in range(3):
		await process_frame  # 等 autoload 就位（DataManager 等）
	LoadoutLoader = load("res://scripts/test3d/full_ai_platform/loadout_loader.gd")
	_assert("P0: 装载器脚本运行时可编译加载（autoload 就位后）", LoadoutLoader != null)

	# ===== A组：装载器纯函数 =====
	var a0: Vector2i = LoadoutLoader.slot_to_index("A0")
	var b2: Vector2i = LoadoutLoader.slot_to_index("b2")
	var bad: Vector2i = LoadoutLoader.slot_to_index("C9")
	_assert("A1a: A0→(0,0)", a0 == Vector2i(0, 0))
	_assert("A1b: b2 小写容错→(1,2)", b2 == Vector2i(1, 2))
	_assert("A1c: C9 非法槽→(-1,-1)", bad == Vector2i(-1, -1))

	var by_id: Dictionary = LoadoutLoader.resolve_spirit("spirit_leihuo")
	var by_name: Dictionary = LoadoutLoader.resolve_spirit("雷火")
	var by_none: Dictionary = LoadoutLoader.resolve_spirit("不存在的元灵")
	_assert("A2a: 元灵按 id 解析", str(by_id.get("id", "")) == "spirit_leihuo")
	_assert("A2b: 元灵按名字解析同条目", str(by_name.get("id", "")) == "spirit_leihuo")
	_assert("A2c: 未知元灵→空字典（fail-closed）", by_none.is_empty())

	var invalid: Array = LoadoutLoader.find_invalid_skills(["skill_雷火_1", "skill_不存在_x", "skill_雷火_2"])
	_assert("A3: 技能校验仅报非法项", invalid.size() == 1 and invalid[0] == "skill_不存在_x")

	# ===== B组：出厂装载配置对账（schema/槽位/角色/元灵全可解析）=====
	var config: Dictionary = LoadoutLoader.load_config(LoadoutLoader.LOADOUT_PATH)
	_assert("B1: 出厂配置可加载且为对象", not config.is_empty())
	_assert("B2: schema_version=1", int(config.get("schema_version", 0)) == 1)
	var loadouts: Array = config.get("loadouts", [])
	_assert("B3: 出厂配置 6 槽位", loadouts.size() == 6)
	var all_ok := true
	var slots_seen: Dictionary = {}
	for entry in loadouts:
		var slot := str(entry.get("slot", ""))
		slots_seen[slot] = true
		if LoadoutLoader.slot_to_index(slot) == Vector2i(-1, -1):
			all_ok = false
		if LoadoutLoader.resolve_spirit(str(entry.get("spirit_id", ""))).is_empty():
			all_ok = false
		if not LoadoutLoader.find_invalid_skills(entry.get("skills", []) if entry.get("skills", []) is Array else []).is_empty():
			all_ok = false
	_assert("B4: 全部槽位/元灵/技能可解析", all_ok and slots_seen.size() == 6)

	# ===== C组：fail-closed 行为 =====
	var bogus: Dictionary = LoadoutLoader.resolve_spirit("spirit_none_xxx")
	var bad_skills: Array = LoadoutLoader.find_invalid_skills(["skill_不存在_x"])
	_assert("C1: 非法元灵查无→空", bogus.is_empty())
	_assert("C2: 非法技能 id 被校验拦截", bad_skills.size() == 1 and bad_skills[0] == "skill_不存在_x")
	_assert("C3: load_config 对不存在的路径返回空", LoadoutLoader.load_config("res://data/systems/spirit_ai/_no_such_file.json").is_empty())

	# ===== D组：开关热切往返（user:// 临时文件，真实 switches.json 零触碰）=====
	var tmp := {"schema_version": 1, "master_enabled": true, "waves": {"A": true, "B": true, "C": false, "D": false, "E": false}}
	var f := FileAccess.open(TEMP_SWITCHES, FileAccess.WRITE)
	f.store_string(JSON.stringify(tmp))
	f.close()
	Registry.reload_switches(TEMP_SWITCHES)
	_assert("D1: 临时文件全开→A 波生效", Registry.is_wave_enabled("A"))
	_assert("D2: 同文件 C 波仍关", not Registry.is_wave_enabled("C"))
	var tmp_off := {"schema_version": 1, "master_enabled": false, "waves": {"A": true, "B": true, "C": true, "D": true, "E": false}}
	var f2 := FileAccess.open(TEMP_SWITCHES, FileAccess.WRITE)
	f2.store_string(JSON.stringify(tmp_off))
	f2.close()
	Registry.reload_switches(TEMP_SWITCHES)
	_assert("D3: master=false 时波位即使 true 也旁路", not Registry.is_wave_enabled("A"))
	# 恢复默认（真实文件态）并断言与真实 switches.json 完全一致（只读对账，不改交付态）
	Registry.reload_switches()
	var real := {"master_enabled": null, "waves": {}}
	var rf := FileAccess.open("res://data/systems/spirit_ai/switches.json", FileAccess.READ)
	if rf:
		var parsed = JSON.parse_string(rf.get_as_text())
		rf.close()
		if parsed is Dictionary:
			real = parsed
	var consistent := true
	for wave in ["A", "B", "C", "D", "E"]:
		var waves_dict: Dictionary = real.get("waves", {}) if real.get("waves", {}) is Dictionary else {}
		var expected: bool = bool(real.get("master_enabled", false)) and bool(waves_dict.get(wave, false))
		if Registry.is_wave_enabled(wave) != expected:
			consistent = false
	_assert("D4: 恢复默认后状态与真实 switches.json 逐项一致", consistent)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SWITCHES))

	# ===== E组：平台脚本完整性 + sim 隔离护栏 =====
	var platform_script: GDScript = load("res://scripts/test3d/full_ai_platform/full_ai_platform.gd")
	_assert("E1: 平台脚本可加载且基类型 Node2D", platform_script != null and platform_script.get_instance_base_type() == "Node2D")
	var src := platform_script.source_code
	_assert("E2: 平台脚本含装载/全AI/开赛三步", src.contains("apply_loadouts") and src.contains("set_controlled_player(null)") and src.contains("_on_prep_match_started"))
	_assert("E3: sim 隔离——平台脚本不置 auto_simulate（--sim 路径零触碰）", not src.contains("auto_simulate = true"))
	var scene: PackedScene = load("res://scenes/test3d/full_ai_platform.tscn")
	_assert("E4: 平台场景可加载", scene != null)

	var loader_script: GDScript = load("res://scripts/test3d/full_ai_platform/loadout_loader.gd")
	_assert("E5: 装载器脚本可加载", loader_script != null)
	var observe_script: GDScript = load("res://scripts/test3d/full_ai_platform/observe_layer.gd")
	_assert("E6: 观测层脚本可加载且基类型 CanvasLayer", observe_script != null and observe_script.get_instance_base_type() == "CanvasLayer")
	var observe_src: String = observe_script.source_code
	_assert("E7: 观测层含开关热切+恢复快照+决策探活", observe_src.contains("reload_switches") and observe_src.contains("_on_restore_snapshot") and observe_src.contains("get_decision_dump"))

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 全部通过！（真实 switches.json / skills.json / baseline 零触碰）")
	quit(1 if _fail > 0 else 0)


func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)
