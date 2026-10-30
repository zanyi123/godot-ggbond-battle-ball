## 工单01 S11 · e2e 3v3 AI（COOP）：三进程真跑（host+2 guest=3 人 vs 3 AI）——纯断言
## 编排：scripts/test3d/regression/e2e_run_3v3.sh；读三 worker json。
extends SceneTree

const HOST_OUT := "sim_results/net_e2e_3v3_host.json"
const G1_OUT := "sim_results/net_e2e_3v3_guest1.json"
const G2_OUT := "sim_results/net_e2e_3v3_guest2.json"

var _pass: int = 0
var _fail: int = 0

func _initialize() -> void:
	await _run()
	print("
========== 结果：%d/%d PASS ==========" % [_pass, _pass + _fail])
	quit(0 if _fail == 0 else 1)

func _assert(cond: bool, n: String) -> void:
	if cond:
		_pass += 1
		print("  ✅ PASS: " + n)
	else:
		_fail += 1
		print("  ❌ FAIL: " + n)

func _read(p: String) -> Dictionary:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var v: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return v if v is Dictionary else {}

func _run() -> void:
	print("
========== e2e 3v3 AI（COOP 三进程） ==========")
	var h := _read(HOST_OUT)
	var g1 := _read(G1_OUT)
	var g2 := _read(G2_OUT)
	_assert(not h.is_empty() and not g1.is_empty() and not g2.is_empty(), "T0: 三 worker 产物落盘")
	if h.is_empty() or g1.is_empty() or g2.is_empty():
		return
	_assert(bool(h.get("ok")) and bool(g1.get("ok")) and bool(g2.get("ok")), "T1: 三端全链完成")
	var hs: Dictionary = h.get("score", {})
	_assert(not hs.is_empty() and hs == g1.get("score", {}) and hs == g2.get("score", {}), "T2: 三端比分一致（%s）" % str(hs))
	_assert(int(h.get("replica_players")) == 6 and int(g1.get("replica_players")) == 6 and int(g2.get("replica_players")) == 6, "T3: 三端副本 6 球员（3 人 + 3 AI）")
	_assert(str(h.get("final_phase")) == NetSchema.PHASE_RESULTS and str(g1.get("final_phase")) == NetSchema.PHASE_RESULTS and str(g2.get("final_phase")) == NetSchema.PHASE_RESULTS, "T4: 三端终态一致=RESULTS")
