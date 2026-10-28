## 30-S9 托管档验收套件（工单30，headless）
## 覆盖：参数集存在+区间 / apply 覆写终值 / 热调 set/get / 单机零引用（构造性隔离）
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_hosted_profile.gd
## 注：进度走文件痕迹（sim_results/_s9_trace.log），绕开 -s stdout 缓冲
extends SceneTree

const AIProfileScript = preload("res://scripts/battle/ai_profile.gd")
const TRACE := "res://sim_results/_s9_trace.log"

var _pass: int = 0
var _fail: int = 0


func _cp(msg: String) -> void:
	var f := FileAccess.open(TRACE, FileAccess.READ_WRITE if FileAccess.file_exists(TRACE) else FileAccess.WRITE)
	f.seek_end()
	f.store_line(msg)
	f.flush()


func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		_cp("  ✓ " + name)
	else:
		_fail += 1
		_cp("  ✗ " + name)


func _run() -> void:
	_cp("S9 start")
	print("\n========== 30-S9 托管档验收 ==========\n")
	var AIProfileClass = load("res://scripts/battle/ai_profile.gd")

	# ===== H1：参数集存在+区间（不超标准档强度，R8）=====
	_cp("H1")
	var view: Dictionary = AIProfileClass.HOSTED_PROFILE
	_check(view.has("skill_think_interval") and view.has("skill_use_threshold") and view.has("skill_mistake_chance"), "H1a 参数集键齐全")
	_check(float(view["skill_think_interval"]) == 0.4 and float(view["skill_use_threshold"]) == 8.0, "H1b 托管档基值（思考0.4/门槛8）")
	_check(float(view["skill_mistake_chance"]) == 0.18, "H1c 失误率微升 0.18")

	# ===== H2：apply 覆写终值 =====
	_cp("H2")
	var hosted = AIProfileClass.new()
	var profile = AIProfileClass.new()
	profile.skill_use_threshold = 100.0
	profile.skill_think_interval = 9.0
	hosted.apply_hosted_profile(profile)
	_check(is_equal_approx(float(profile.skill_use_threshold), 8.0) and is_equal_approx(float(profile.skill_think_interval), 0.4), "H2 apply 覆写终值（干扰值被覆盖）")
	_check(float(profile.skill_mistake_chance) == 0.18, "H2b 失误率随档")

	# ===== H3：热调 set/get/clear =====
	_cp("H3")
	hosted.set_hosted_override("skill_use_threshold", 12.0)
	var merged: Dictionary = hosted.get_hosted_profile_view()
	_check(float(merged["skill_use_threshold"]) == 12.0, "H3a set_hosted_override 生效")
	var profile2 = AIProfileClass.new()
	profile2.skill_use_threshold = 100.0
	hosted.apply_hosted_profile(profile2)
	_check(is_equal_approx(float(profile2.skill_use_threshold), 12.0), "H3b 覆写含热调覆盖（12.0）")
	hosted.clear_hosted_overrides()
	var merged2: Dictionary = hosted.get_hosted_profile_view()
	_check(float(merged2["skill_use_threshold"]) == 8.0, "H3c clear 后回落基档")

	# ===== H4：单机零引用（构造性隔离的静态面）=====
	_cp("H4")
	var src := FileAccess.get_file_as_string("res://scripts/battle/battle_manager.gd")
	var src_ai := FileAccess.get_file_as_string("res://scripts/battle/ai_manager.gd")
	_check(not src.contains("apply_hosted_profile") and not src_ai.contains("apply_hosted_profile"), "H4 单机主链零引用（托管档仅联机分支装载，构造性隔离）")
	var sim_src := FileAccess.get_file_as_string("res://run_sim.sh")
	_check(not sim_src.contains("hosted"), "H4b run_sim 不触托管档")

	# ===== H5：R8 红线面 =====
	_cp("H5")
	_check(float(AIProfileClass.HOSTED_PROFILE["skill_mistake_chance"]) <= 0.2, "H5a 失误率≤0.2（不超 easy 档 0.3，公平线）")
	_check(float(AIProfileClass.HOSTED_PROFILE["skill_use_threshold"]) >= 5.0, "H5b 门槛≥标准档 5（托管不比标准更凶）")

	_cp("S9 done: %d/%d" % [_pass, _pass + _fail])
	print("\n========== 结果：%d 通过 / %d 失败 ==========" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _initialize() -> void:
	_run()
