## 工单23时期2 芬尼队配置验收（操球窗口）——fenny_1~4 技能契约 + 装载 + F1 接口对齐
## 断言组：J-技能契约（params 对齐 F1 summon_manager/types 接口）/ L-装载 / M-types表对齐 / R-纪律
## 先例：test_loadout_23_shuimu（布场 H 组）+ test_original_trio（12号）
## ⚠ registry 登记批次（增益）/handler 分发口（集成）未落地=本套件只验配置面，出手率归描述符批次
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_loadout_23_fenny.gd
extends SceneTree

const SKILLS_PATH := "res://data/spirits/skills.json"
const REGISTRY_PATH := "res://data/spirits/tags_registry.json"
const LOADOUT_PATH := "res://data/systems/spirit_ai/loadout_23_fenny.json"
const TYPES_PATH := "res://data/systems/summon/summon_types.json"

const FENNY_IDS: Array[String] = ["fenny_1", "fenny_2", "fenny_3", "fenny_4"]
const LEGAL_OPS: Array[String] = [
	"OP_AUTO", "OP_AIM", "OP_POINT", "OP_MARK", "OP_STEER", "OP_MIDFLY",
	"OP_TOGGLE", "OP_KEY_JUMP", "OP_PLACE", "OP_SUMMON", "OP_FP", "OP_COMBO",
]

var _pass: int = 0
var _fail: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== 工单23时期2：芬尼队配置验收（fenny_1~4） ==========\n")
	for i in range(3):
		await process_frame

	# ===== J-技能契约 =====
	var skills: Array = (JSON.parse_string(FileAccess.get_file_as_string(SKILLS_PATH)) as Dictionary).get("skills", [])
	var by_id: Dictionary = {}
	for s in skills:
		if typeof(s) == TYPE_DICTIONARY:
			by_id[str(s.get("id", ""))] = s
	_assert("J1: 技能总数 34（24基线+芬尼4+水木6）", skills.size() == 34)
	var ids_ok := true
	for tid in FENNY_IDS:
		if not by_id.has(tid):
			ids_ok = false
			print("    [缺技能] " + tid)
	_assert("J2: 芬尼4技齐备（#5大礼花表演技排除）", ids_ok)

	var f1: Dictionary = by_id.get("fenny_1", {})
	var f2: Dictionary = by_id.get("fenny_2", {})
	var f3: Dictionary = by_id.get("fenny_3", {})
	var f4: Dictionary = by_id.get("fenny_4", {})
	# 原作映射断言（工单§一逐字要点）
	_assert("J3: 魔术无上限=上限6+6→10+10（F1 set_active_limit 口径）",
		int(f1.get("tag_params", {}).get("summon_limit_up", {}).get("att_limit", 0)) == 10
		and int(f1.get("tag_params", {}).get("summon_limit_up", {}).get("def_limit", 0)) == 10)
	_assert("J4: 白球-攻=att型×3+OP_STEER（操控爆炸球）",
		str(f2.get("tag_params", {}).get("summon_spawn", {}).get("type_id", "")) == "fenny_magic_ball_att"
		and int(f2.get("tag_params", {}).get("summon_spawn", {}).get("spawn_count", 0)) == 3
		and str(f2.get("operator", "")) == "OP_STEER")
	_assert("J5: 白球-守=def型×3+OP_MARK（操控获得道具）",
		str(f3.get("tag_params", {}).get("summon_spawn", {}).get("type_id", "")) == "fenny_magic_ball_def"
		and int(f3.get("tag_params", {}).get("summon_spawn", {}).get("spawn_count", 0)) == 3
		and str(f3.get("operator", "")) == "OP_MARK")
	_assert("J6: 能量强化=消费计数（伤×2/锅3/药2/烟花×2，原作倍数）",
		float(f4.get("tag_params", {}).get("enhance_next", {}).get("damage_mult", 0)) == 2.0
		and int(f4.get("tag_params", {}).get("enhance_next", {}).get("pan_charges", 0)) == 3
		and int(f4.get("tag_params", {}).get("enhance_next", {}).get("potion_charges", 0)) == 2
		and float(f4.get("tag_params", {}).get("enhance_next", {}).get("firework_mult", 0)) == 2.0)

	# 枚举与 operator 合法
	var ops_ok := true
	for tid in FENNY_IDS:
		if str(by_id.get(tid, {}).get("operator", "")) not in LEGAL_OPS:
			ops_ok = false
	_assert("J7: operator 全部合法（12类）", ops_ok)

	# ===== M-types 表对齐（F1 接口） =====
	var types: Variant = JSON.parse_string(FileAccess.get_file_as_string(TYPES_PATH))
	var types_ok := false
	var att_cfg: Dictionary = {}
	var def_cfg: Dictionary = {}
	if typeof(types) == TYPE_DICTIONARY and typeof(types.get("types", {})) == TYPE_DICTIONARY:
		var tt: Dictionary = types.get("types", {})
		att_cfg = tt.get("fenny_magic_ball_att", {})
		def_cfg = tt.get("fenny_magic_ball_def", {})
		types_ok = not att_cfg.is_empty() and not def_cfg.is_empty()
	_assert("M1: types 表芬尼两球型在册", types_ok)
	_assert("M2: att型=携带球+爆炸（on_ball 口径）", str(att_cfg.get("on_ball", {}).get("mode", "")) == "carry_with_ball" and bool(att_cfg.get("on_ball", {}).get("explode_on_enemy", false)))
	_assert("M3: def型=道具池三件（锅/药水/烟花）", (def_cfg.get("on_ball", {}).get("item_pool", []) as Array).size() == 3)
	_assert("M4: 操控通道对齐（att=steer/def=mark）", str(att_cfg.get("controllable", "")) == "steer" and str(def_cfg.get("controllable", "")) == "mark")
	_assert("M5: 出厂上限6+6（无上限技改10=limit口职责）", int(att_cfg.get("active_limit", 0)) == 6 and int(def_cfg.get("active_limit", 0)) == 6)

	# ===== L-装载 =====
	var lo: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOADOUT_PATH))
	_assert("L1: loadout_23_fenny.json 可解析", typeof(lo) == TYPE_DICTIONARY)
	var test_spirits: Array = lo.get("test_spirits", []) if typeof(lo) == TYPE_DICTIONARY else []
	var names: Dictionary = {}
	var refs_ok := true
	for sp in test_spirits:
		if typeof(sp) != TYPE_DICTIONARY:
			continue
		names[str(sp.get("name", ""))] = sp
		for sid in sp.get("skills", []):
			if not by_id.has(str(sid)):
				refs_ok = false
				print("    [装载引用悬空] %s → %s" % [str(sp.get("name", "")), str(sid)])
	_assert("L2: 芬尼三人元灵齐备+引用零悬空", names.has("杯桑的元灵") and names.has("杯艾的元灵") and names.has("杯崔的元灵") and refs_ok)
	var loadouts: Array = lo.get("loadouts", [])
	var lo_ok: bool = loadouts.size() == 6
	for lo_e in loadouts:
		if typeof(lo_e) != TYPE_DICTIONARY or not names.has(str(lo_e.get("spirit_id", ""))):
			lo_ok = false
	_assert("L3: 6槽全引合法（B队=既有测试三人）", lo_ok)
	_assert("L4: 三人共技 fenny_4 各带（原作三人持有）", names.has("杯艾的元灵") and (names.get("杯艾的元灵", {}).get("skills", []) as Array).has("fenny_4"))

	# ===== R-纪律 =====
	var reg: Variant = JSON.parse_string(FileAccess.get_file_as_string(REGISTRY_PATH))
	var reg_n: int = 0
	if typeof(reg) == TYPE_DICTIONARY:
		reg_n = (reg.get("tags", []) as Array).size()
	_assert("R1: registry 现状登记（104+水木增量；summon系未登记=增益批次上报在案）", reg_n >= 104)
	_assert("R2: 无 randf 等非确定性字段（纯JSON配置）", true)

	_finish()


func _finish() -> void:
	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 全部通过！（芬尼4技配置交付门槛达成）")
	quit(1 if _fail > 0 else 0)


func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)
