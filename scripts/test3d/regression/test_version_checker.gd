## 工单03 下一批 · 版本检查器套件（纯逻辑零网络）
## 运行：bash ./run_suite_guarded.sh res://scripts/test3d/regression/test_version_checker.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0

func _initialize() -> void:
	_run()
	print("\n========== 结果：%d/%d PASS ==========" % [_pass, _pass + _fail])
	quit(0 if _fail == 0 else 1)

func _assert(cond: bool, n: String) -> void:
	if cond:
		_pass += 1
		print("  ✅ PASS: " + n)
	else:
		_fail += 1
		print("  ❌ FAIL: " + n)

func _run() -> void:
	print("\n========== 版本检查器套件 ==========\n")
	# V1 语义比较三态
	_assert(VersionChecker.compare_versions("1.2.0", "1.2.0") == 0, "V1a: 相等版本=0")
	_assert(VersionChecker.compare_versions("1.2.0", "1.3.0") == -1, "V1b: 旧<新=-1")
	_assert(VersionChecker.compare_versions("2.0.0", "1.9.9") == 1, "V1c: 主版本跨代=1")
	# V2 边界：段数不齐/非数字
	_assert(VersionChecker.compare_versions("1.2", "1.2.0") == 0, "V2a: 段数不齐按 0 补齐（1.2==1.2.0）")
	_assert(VersionChecker.compare_versions("1.2.1", "1.2.0.5") == 1, "V2b: 多段数字逐位比")
	# V3 决策矩阵
	var d := VersionChecker.decide({"version": "1.0.0"}, {"version": "1.1.0", "url": "https://x", "notes": "修复"})
	_assert(bool(d.get("update_needed")) and str(d.get("to")) == "1.1.0" and str(d.get("url")) == "https://x", "V3a: 远端更新→需要更新+载荷齐")
	var d2 := VersionChecker.decide({"version": "1.1.0"}, {"version": "1.1.0"})
	_assert(not bool(d2.get("update_needed")), "V3b: 同版本→静默")
	var d3 := VersionChecker.decide({"version": "2.0.0"}, {"version": "1.0.0"})
	_assert(not bool(d3.get("update_needed")), "V3c: 本地更新→静默（防回滚误报）")
	# V4 本地版本真相读取
	var lv := VersionChecker.load_local_version()
	_assert(str(lv.get("version")) == "0.1.0", "V4: 本地 version.json 读取（0.1.0）")
