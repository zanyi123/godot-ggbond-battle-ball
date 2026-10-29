## U0-1 · UI 色板单例套件（美术UI线乙线窗口 · 2026-10-27）
## 运行：bash ./run_suite_guarded.sh res://scripts/test3d/regression/test_ui_palette.gd
## 覆盖：C1 文件与结构 / C2 六元素结构与v5显示名映射 / C3 各组完备性 /
##       C4 col/get_value 回退不炸 / C5 reload 幂等 / C6 旧值迁移逐位一致（非元素组）
## 纪律：元素色断言只验结构与映射（1027-2 定版后六色会变）；非元素组断言锁定迁移值防手滑
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


## 十六进制色与旧浮点色逐通道比对：hex 是 8 位量化，允许 ≤1/255 步进误差
func _assert_col(a: Color, b: Color, n: String) -> void:
	var tol: float = 1.0 / 255.0
	_assert(absf(a.r - b.r) <= tol and absf(a.g - b.g) <= tol and absf(a.b - b.b) <= tol, n)


func _run() -> void:
	print("\n========== U0-1 · UI 色板单例套件（UiPalette） ==========\n")

	# C1 文件与结构
	_assert(FileAccess.file_exists("res://data/ui/ui_palette.json"), "C1a: 色板文件存在 data/ui/ui_palette.json")
	_assert(UiPalette.get_value("meta.status") == "locked" and UiPalette.get_value("meta.locked_by") != null, "C1b: meta.status 锁版标记+批复来源在位")
	_assert(UiPalette.get_value("meta.rule") is String and str(UiPalette.get_value("meta.rule")).contains("唯一来源"), "C1c: meta.rule 唯一来源纪律在位")

	# C2 六元素（key=数据层旧词；display=v5 §7.4 定稿新词）
	var element_keys: Array = ["金刚", "梦幻", "草木", "大地", "冰雪", "雷火"]
	var all_element := true
	for ek in element_keys:
		if UiPalette.get_value("element.%s.display" % ek) == null or UiPalette.get_value("element.%s.color" % ek) == null:
			all_element = false
	_assert(all_element, "C2a: 六元素 key 全有 display+color")
	_assert(UiPalette.element_display("金刚") == "神力" and UiPalette.element_display("梦幻") == "泯灭", "C2b: 旧词→新词映射（金刚→神力/梦幻→泯灭，v5 §7.4）")
	_assert(UiPalette.element_display("草木") == "巨木" and UiPalette.element_display("大地") == "艮土" and UiPalette.element_display("冰雪") == "玄冰" and UiPalette.element_display("雷火") == "雷火", "C2c: 旧词→新词映射（草木→巨木/大地→艮土/冰雪→玄冰/雷火不变）")
	var ec: Color = UiPalette.element_color("金刚")
	_assert(ec.r > 0.5 and ec.g > 0.5 and ec.b < 0.6, "C2d: element_color 返回可解析 Color（暗金系）")

	# C3 各组完备性
	var rarity_ok := true
	for rk in ["common", "good", "rare", "epic", "legendary"]:
		var c: Color = UiPalette.rarity_color(rk)
		if c == Color.WHITE:
			rarity_ok = false
	_assert(rarity_ok, "C3a: 稀有度五色齐全且可解析（白绿蓝紫金）")
	var semantic_keys: Array = ["primary", "primary_hi", "on_primary", "bg_base", "bg_panel", "bg_panel_hi", "line", "line_hi", "text", "text_dim", "success", "warn", "danger", "disabled"]
	var semantic_ok := true
	for sk in semantic_keys:
		if UiPalette.get_value("semantic.%s" % sk) == null:
			semantic_ok = false
	_assert(semantic_ok, "C3b: 语义色十四键齐全")
	var status_keys: Array = ["heal_block", "energy_block", "reflect", "element_immune", "element_weak", "energy_share", "charge_stock", "stealthed", "invincible", "stunned", "rooted", "silenced", "disarmed", "mark", "shield", "toggle", "heal"]
	var status_ok := true
	for stk in status_keys:
		var e: Dictionary = UiPalette.status_entry(stk)
		if e.is_empty() or str(e.get("char", "")) == "" or e.get("color", Color.WHITE) == Color.WHITE:
			status_ok = false
	_assert(status_ok and status_keys.size() == 17, "C3c: 状态图标 17 键全有 char+color（旧表全量迁移）")
	var stat_ok := true
	for stk2 in ["stamina", "defense", "speed", "attack", "resilience", "defense_factor", "ball_speed"]:
		if UiPalette.get_value("stat.%s" % stk2) == null:
			stat_ok = false
	_assert(stat_ok, "C3d: 属性条七色齐全")
	_assert(UiPalette.get_value("durability.low") != null and UiPalette.get_value("durability.mid") != null and UiPalette.get_value("durability.ok") != null, "C3e: 耐久三档齐全")

	# C4 回退不炸（UI 零判定红线：缺键绝不 crash）
	_assert(UiPalette.col("element.不存在.color", Color.MAGENTA) == Color.MAGENTA, "C4a: col 缺键回退 fallback")
	_assert(UiPalette.col("semantic.primary") == Color.html("#e8b54a"), "C4b: col 正常取色逐位一致")
	_assert(UiPalette.get_value("a.b.c.d", "哨兵") == "哨兵", "C4c: get_value 深路径缺键回退哨兵")

	# C5 reload 幂等
	UiPalette.reload()
	_assert(UiPalette.col("semantic.primary") == Color.html("#e8b54a"), "C5: reload 后取值仍一致（幂等）")

	# C6 迁移一致（8 位量化容差 ≤1/255）+ 元素定版锁色（1027-2 候选A，hex 对 hex 精确锁）
	_assert_col(UiPalette.status_entry("heal_block")["color"], Color(0.65, 0.3, 0.85), "C6a: 状态色迁移 heal_block #a64dd9≈旧(0.65,0.3,0.85)")
	_assert_col(UiPalette.status_entry("shield")["color"], Color(1.0, 0.84, 0.0), "C6b: 状态色迁移 shield #ffd600≈旧(1.0,0.84,0.0)")
	_assert_col(UiPalette.status_entry("mark")["color"], Color(0.3, 0.85, 0.4), "C6c: 状态色迁移 mark #4dd966≈旧(0.3,0.85,0.4)")
	_assert_col(UiPalette.col("stat.stamina"), Color(0.9, 0.2, 0.2), "C6d: 属性色迁移 stamina #e63333≈旧(0.9,0.2,0.2)")
	_assert_col(UiPalette.col("stat.ball_speed"), Color(0.6, 0.4, 0.2), "C6e: 属性色迁移 ball_speed #996633≈旧(0.6,0.4,0.2)")
	_assert(UiPalette.get_value("meta.status") == "locked", "C6f0: 色板已锁版（1027-2 候选A）")
	_assert(UiPalette.element_color("金刚") == Color.html("#d9a441"), "C6f1: 定版锁色 神力 #d9a441")
	_assert(UiPalette.element_color("梦幻") == Color.html("#8a6fc8"), "C6f2: 定版锁色 泯灭 #8a6fc8")
	_assert(UiPalette.element_color("草木") == Color.html("#4caf6d"), "C6f3: 定版锁色 巨木 #4caf6d")
	_assert(UiPalette.element_color("大地") == Color.html("#a07b52"), "C6f4: 定版锁色 艮土 #a07b52")
	_assert(UiPalette.element_color("冰雪") == Color.html("#6ec6ff"), "C6f5: 定版锁色 玄冰 #6ec6ff")
	_assert(UiPalette.element_color("雷火") == Color.html("#ff7a3d"), "C6f6: 定版锁色 雷火 #ff7a3d")
	_assert(UiPalette.col("element.雷火.deep") == Color.html("#a64f28") and UiPalette.col("element.雷火.soft") == Color.html("#ff7a3d33"), "C6f7: 元素三态 deep/soft 在位")

	# C7 耐久色阶边界
	_assert(UiPalette.durability_color(0.9) == UiPalette.durability_color(0.6) and UiPalette.durability_color(0.6) == UiPalette.col("durability.ok"), "C7a: 耐久>=0.5 走 ok 档")
	_assert(UiPalette.durability_color(0.3) == UiPalette.col("durability.mid") and UiPalette.durability_color(0.15) == UiPalette.col("durability.low"), "C7b: 耐久 0.2~0.5 走 mid / <0.2 走 low（濒损规则）")
