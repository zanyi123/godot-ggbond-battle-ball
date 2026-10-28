## 工单30 S3 验收：联机 AI 自动选角策略（纯函数）
## 断言组：J-接口契约 / D-确定性 / E-边界 / S-策略语义 / R-纪律
## 依据：元灵技能AI规划/30_联机01对接方案_S3选角策略_S9托管档.md §一 + 联机01移交单
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_pick_strategy.gd
extends SceneTree

const STRATEGY_PATH := "res://scripts/battle/spirit_ai/pick_strategy.gd"

var _pass: int = 0
var _fail: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== 工单30 S3：AI 自动选角策略（纯函数） ==========\n")
	for i in range(3):
		await process_frame

	var strat: GDScript = load(STRATEGY_PATH)

	# 全池（7球员/6元灵，与 DataManager 一致的 id 清单——只读不注数据）
	var all_chars: Array = ["char_001", "char_002", "char_003", "char_004", "char_005", "char_006", "char_007"]
	var all_spirits: Array = ["spirit_jingang", "spirit_dadi", "spirit_leihuo", "spirit_bingxue", "spirit_caomu", "spirit_menghuan"]

	# ===== J-接口契约 =====
	var r1: String = strat.pick_character(all_chars, [])
	_assert("J1: pick_character 全池返回合法 id", all_chars.has(r1))
	var r2: String = strat.pick_spirit(all_spirits, [])
	_assert("J2: pick_spirit 全池返回合法 id", all_spirits.has(r2))

	# ===== E-边界 =====
	_assert("E1: 空池→空串（联机侧兜底随机契约）", strat.pick_character([], []) == "" and strat.pick_spirit([], []) == "")
	var last_c := ["char_005"]
	_assert("E2: 池余1→返回唯一（不炸）", strat.pick_character(last_c, ["char_001"]) == "char_005")
	var last_s := ["spirit_bingxue"]
	_assert("E3: 池余1 spirit→返回唯一", strat.pick_spirit(last_s, ["spirit_jingang"]) == "spirit_bingxue")
	_assert("E4: 队友 id 无效（DataManager 查不到）→fail-closed 不炸", strat.pick_character(["char_003"], ["char_nope"]) != "")
	_assert("E5: 重复队友条目→不炸", strat.pick_spirit(all_spirits, ["char_001", "char_001"]) != "")

	# ===== S-策略语义 =====
	# S1：职位画像补缺——已选防御画像双星（超人强 def80/ res70+小呆呆 def65）→应补非防御画像（猪猪侠 spd75 atk38=攻/辅画像）
	var picks_def := ["char_002", "char_004"]
	var pool := ["char_005", "char_003", "char_001"]  # 波比(atk43攻)/菲菲(spd85攻)/猪猪侠
	var pick_c: String = strat.pick_character(pool, picks_def)
	_assert("S1: 防御画像已足→补攻/辅画像（不选防御波比）", pick_c != "char_005")
	# S2：弱点互补 spirit——队=菲菲+波比（攻高防低 def 全队最低）→防御向元灵（大山 大地_2=def_up 技）优先
	var pool_s := ["spirit_dadi", "spirit_leihuo"]
	var picks_off := ["char_003", "char_005"]
	var pick_s: String = strat.pick_spirit(pool_s, picks_off)
	_assert("S2: 队内防弱→补防御向元灵（大山 大地_2 def_up 技亲和）", pick_s == "spirit_dadi")
	# S3：元素均衡——队已带金刚元灵→再选时避金刚重复元素（选非金刚）
	var pool_s2 := ["spirit_jingang", "spirit_bingxue"]
	var pick_s2: String = strat.pick_spirit(pool_s2, ["char_001"])
	_assert("S3: 元素分布均衡（队已有金刚→不选金刚元灵）", pick_s2 == "spirit_bingxue")

	# ===== D-确定性：固定输入双跑逐位（三连选全序列） =====
	var fixed_pool := ["char_003", "char_001", "char_005", "char_002"]
	var run1: Array = []
	var p1: Array = []
	for cid in fixed_pool:
		var g: String = strat.pick_character(fixed_pool, p1)
		run1.append(g)
		p1.append(g)
	var run1b: Array = []
	var p1b: Array = []
	for cid in fixed_pool:
		var g3: String = strat.pick_character(fixed_pool, p1b)
		run1b.append(g3)
		p1b.append(g3)
	var run2: Array = []
	var p2a: Array = []
	for sid in ["spirit_leihuo", "spirit_dadi", "spirit_bingxue", "spirit_jingang"]:
		var g2: String = strat.pick_spirit(["spirit_leihuo", "spirit_dadi", "spirit_bingxue", "spirit_jingang"], p2a)
		run2.append(g2)
		p2a.append(g2)
	_assert("D1: 同输入两次 character 三连选逐位一致", str(run1) == str(run1b))
	_assert("D2: 确定性输出非空全合法", not run1.has("") and not run2.has(""))

	# ===== R-纪律 =====
	var src: String = FileAccess.get_file_as_string(STRATEGY_PATH)
	_assert("R1: 源码无 randf(/randi(/shuffle（禁随机铁律）", src.find("randf(") == -1 and src.find("randi(") == -1 and src.find("shuffle(") == -1)
	_assert("R2: 源码无写盘（FileAccess.WRITE/SampleDevice）", src.find("FileAccess.WRITE") == -1 and src.find("SampleDevice") == -1)

	_finish()


func _finish() -> void:
	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 全部通过！（工单30 S3 交付门槛达成）")
	quit(1 if _fail > 0 else 0)


func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)
