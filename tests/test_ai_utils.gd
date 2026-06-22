extends SceneTree
## ============================================================================
## 决竞球 AI 工具函数单元测试（vibecoding 方案B）
## ----------------------------------------------------------------------------
## 目的：抓"改 A 坏 B"的低级逻辑回归。直接测真实的 ai_manager 方法，
##       不做 GDScript→Python 移植（避免漂移，符合"单一事实源"原则）。
## 用法：./run_tests.sh  或  godot --headless -s res://tests/test_ai_utils.gd
## 覆盖：_curve / _utility_carrying / _utility_catch / _ball_in_reachable_half
## ============================================================================

const AIManager = preload("res://scripts/battle/ai_manager.gd")
const AIProfile = preload("res://scripts/battle/ai_profile.gd")

var passed: int = 0
var failed: int = 0
var failures: Array[String] = []


func _init() -> void:
	print("=".repeat(60))
	print("决竞球 AI 工具函数单元测试")
	print("=".repeat(60))

	# 裸实例化 ai_manager（不进场景树，不触发 _ready 依赖）
	var mgr: Node = AIManager.new()

	test_curve(mgr)
	test_utility_carrying(mgr)
	test_utility_catch(mgr)
	test_ball_in_reachable_half(mgr)

	mgr.queue_free()
	print_summary()
	quit(1 if failed > 0 else 0)


# ---------- 断言工具 ----------
func approx(a: float, b: float, eps: float = 0.01) -> bool:
	return abs(a - b) < eps


func check(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		passed += 1
		print("  ✓ %s" % name)
	else:
		failed += 1
		failures.append(name)
		print("  ✗ %s   %s" % [name, detail])


# ---------- [1] _curve ----------
func test_curve(mgr: Node) -> void:
	print("\n[1] _curve Response Curve（4 种曲线 + 设计契约）")

	# 边界值
	check("linear(0)=0", approx(mgr._curve(0.0, "linear"), 0.0))
	check("linear(0.5)=0.5", approx(mgr._curve(0.5, "linear"), 0.5))
	check("linear(1)=1", approx(mgr._curve(1.0, "linear"), 1.0))

	# 设计契约：logistic/exp/inv_log 在中点 0.5 不改变默认平衡
	# （见 ai_profile 注释：curve_k 默认 1.0，拐点 0.5，中点行为与原线性一致）
	var l_half: float = mgr._curve(0.5, "logistic")
	check("logistic(0.5)≈0.5（中点契约）", approx(l_half, 0.5), "got %f" % l_half)
	check("exp(0.5)=0.25（凸曲线中点）", approx(mgr._curve(0.5, "exp"), 0.25))
	var il_half: float = mgr._curve(0.5, "inv_log")
	check("inv_log(0.5)≈0.5（中点契约）", approx(il_half, 0.5), "got %f" % il_half)

	# 值域 [0,1]
	check("logistic 值域上界≤1", mgr._curve(0.99, "logistic") <= 1.0)
	check("logistic 值域下界≥0", mgr._curve(0.01, "logistic") >= 0.0)

	# exp 单调递增（越高越极端）
	check("exp 单调递增", mgr._curve(0.8, "exp") > mgr._curve(0.2, "exp"))

	# clamp 越界输入
	check("clamp 负值=0", approx(mgr._curve(-0.5, "linear"), 0.0))
	check("clamp >1=1", approx(mgr._curve(1.5, "linear"), 1.0))

	# 未知类型兜底为 linear
	check("未知类型=linear", approx(mgr._curve(0.3, "foobar"), 0.3))

	# k 越大 logistic 越陡（x=0.7 偏离 0.5 的幅度更大）
	var diff_small: float = abs(mgr._curve(0.7, "logistic", 0.5) - 0.5)
	var diff_large: float = abs(mgr._curve(0.7, "logistic", 2.0) - 0.5)
	check("k 越大 logistic 越陡", diff_large > diff_small,
		"k=2 diff=%f vs k=0.5 diff=%f" % [diff_large, diff_small])


# ---------- [2] _utility_carrying ----------
func test_utility_carrying(mgr: Node) -> void:
	print("\n[2] _utility_carrying 持球效用（pass vs shoot 倾向）")

	var attacker: AIProfile = AIProfile.get_role_preset("attacker")
	attacker.player_strategy_name = "breakthrough"  # 主攻手配突破（真实场景）
	var supporter: AIProfile = AIProfile.get_role_preset("supporter")
	var ap_a: Dictionary = {"profile": attacker}
	var ap_s: Dictionary = {"profile": supporter}

	var neutral: Dictionary = {"team_state": 0.5, "enemy_state": 0.5, "active_skill_ready": 0.5}
	var r_a: Dictionary = mgr._utility_carrying(ap_a, neutral)
	var r_s: Dictionary = mgr._utility_carrying(ap_s, neutral)

	# 设计契约：主攻手偏投球，辅助手偏传球
	check("主攻手(breakthrough)偏投球", r_a["shoot_score"] > r_a["pass_score"],
		"shoot=%f pass=%f" % [r_a["shoot_score"], r_a["pass_score"]])
	check("辅助手偏传球", r_s["pass_score"] > r_s["shoot_score"],
		"pass=%f shoot=%f" % [r_s["pass_score"], r_s["shoot_score"]])

	# 对手残血（enemy_state 高，过 logistic 曲线放大）→ 投球加分（猛打）
	var enemy_weak: Dictionary = {"team_state": 0.5, "enemy_state": 0.9, "active_skill_ready": 0.5}
	var enemy_strong: Dictionary = {"team_state": 0.5, "enemy_state": 0.1, "active_skill_ready": 0.5}
	var r_weak: Dictionary = mgr._utility_carrying(ap_a, enemy_weak)
	var r_strong: Dictionary = mgr._utility_carrying(ap_a, enemy_strong)
	check("对手残血→投球加分", r_weak["shoot_score"] > r_strong["shoot_score"],
		"weak=%f strong=%f" % [r_weak["shoot_score"], r_strong["shoot_score"]])


# ---------- [3] _utility_catch ----------
func test_utility_catch(mgr: Node) -> void:
	print("\n[3] _utility_catch 接球效用（接球 vs 拒接）")

	var attacker: AIProfile = AIProfile.get_role_preset("attacker")  # 默认 passing
	var defender: AIProfile = AIProfile.get_role_preset("defender")
	var ap_a: Dictionary = {"profile": attacker, "team": "a", "player": null}
	var ap_d: Dictionary = {"profile": defender, "team": "a", "player": null}

	var safe_sit: Dictionary = {"possession_value": 0.8, "my_stamina_health": 0.9}

	# 安全球（低威胁高体力）→ 正分（应该接）
	var util_safe: float = mgr._utility_catch(ap_a, safe_sit, 0.1, Vector2.ZERO)
	check("安全球→正分（接球）", util_safe > 0.0, "got %f" % util_safe)

	# 高威胁球 → 分数更低（应该拒接）
	var util_threat: float = mgr._utility_catch(ap_a, safe_sit, 0.9, Vector2.ZERO)
	check("高威胁球→分数更低（拒接）", util_threat < util_safe,
		"threat=%f safe=%f" % [util_threat, util_safe])

	# 体力差（过 exp 曲线压低）→ 接球意愿低
	var tired_sit: Dictionary = {"possession_value": 0.8, "my_stamina_health": 0.2}
	var util_tired: float = mgr._utility_catch(ap_a, tired_sit, 0.1, Vector2.ZERO)
	check("体力差→接球意愿低", util_tired < util_safe,
		"tired=%f safe=%f" % [util_tired, util_safe])

	# 角色加分：防御者主动接（+30），主攻手（passing）无加分
	var util_d: float = mgr._utility_catch(ap_d, safe_sit, 0.1, Vector2.ZERO)
	check("防御者比主攻手更爱接球", util_d > util_safe,
		"defender=%f attacker=%f" % [util_d, util_safe])


# ---------- [4] _ball_in_reachable_half ----------
func test_ball_in_reachable_half(mgr: Node) -> void:
	print("\n[4] _ball_in_reachable_half 球在己方可达半场")

	# 队A：可达 x≤0（己方左半场 + 中线）
	check("队A 己方半场", mgr._ball_in_reachable_half(Vector2(-100, 0), "a") == true)
	check("队A 中线可达", mgr._ball_in_reachable_half(Vector2(0, 0), "a") == true)
	check("队A 对方半场不可达", mgr._ball_in_reachable_half(Vector2(100, 0), "a") == false)

	# 队B 镜像：可达 x≥0
	check("队B 己方半场", mgr._ball_in_reachable_half(Vector2(100, 0), "b") == true)
	check("队B 中线可达", mgr._ball_in_reachable_half(Vector2(0, 0), "b") == true)
	check("队B 对方半场不可达", mgr._ball_in_reachable_half(Vector2(-100, 0), "b") == false)

	# y 坐标不影响判定（只看 x）
	check("y 不影响判定（队A）", mgr._ball_in_reachable_half(Vector2(-50, 999), "a") == true)
	check("y 不影响判定（队B）", mgr._ball_in_reachable_half(Vector2(50, -999), "b") == true)


# ---------- 汇总 ----------
func print_summary() -> void:
	print("\n" + "=".repeat(60))
	print("通过: %d  /  失败: %d  /  总计: %d" % [passed, failed, passed + failed])
	if failed > 0:
		print("失败项:")
		for f in failures:
			print("  - %s" % f)
		print("=".repeat(60))
		print("✗ 有失败项，请检查 ai_manager 对应函数")
	else:
		print("=".repeat(60))
		print("✓ 全部通过")
