## 23号工单验收套件：敌方作用对象头顶状态标记（headless 可跑）
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_enemy_status_marker.gd
## 覆盖工单 §四 断言 1~8（减速/属性削弱类走 buff 无信号=本批边界备案，以 energy_block 代验减益键）
extends SceneTree

var _pass: int = 0
var _fail: int = 0

func _initialize() -> void:
	_run()

func _assert(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  ✅ PASS: " + name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + name)

func _run() -> void:
	print("\n========== 23号：敌方作用对象头顶标记验收 ==========\n")
	for i in range(3):
		await process_frame  # 等 autoload 就位
	var PlayerScript: GDScript = load("res://scripts/battle/player.gd")
	var MarkerScript: GDScript = load("res://scripts/battle/enemy_status_marker.gd")
	var Marker3DScript: GDScript = load("res://scripts/battle3d/visual/enemy_marker_3d.gd")
	_assert(MarkerScript != null, "EnemyStatusMarker 组件可加载（含语法/继承编译）")
	_assert(Marker3DScript != null, "EnemyMarker3D 组件可加载")
	_assert(MarkerScript.ENEMY_KEYS.size() == 8, "白名单 8 键（控制4+减益4）")
	_assert(str(MarkerScript.show_mode) == "all", "默认 show_mode=all（正式版+测试平台全员显示）")

	# --- 断言1：印记两次→层数2 ---
	var enemy: CharacterBody2D = PlayerScript.new()
	enemy.team = "b"
	root.add_child(enemy)
	await process_frame
	var marker: Control = MarkerScript.new()
	enemy.add_child(marker)
	marker.bind_enemy(enemy)
	await process_frame
	enemy.apply_mark("test_mark", 3, 10.0)
	enemy.apply_mark("test_mark", 3, 10.0)
	await process_frame
	var mark_key: String = "mark_test_mark"
	_assert(marker._entries.has(mark_key) and int(marker._entries[mark_key]["stacks"]) == 2, "断言1: 印记两命中→层数=2")

	# --- 断言2/6：眩晕灯 on→「晕」出现；off→消失 ---
	enemy.turn_on_light("stunned", 2.0)
	await process_frame
	_assert(marker._entries.has("stunned") and str(marker._entries["stunned"]["char"]) == "晕", "断言2: 眩晕→「晕」红标出现")
	enemy.turn_off_light("stunned")
	await process_frame
	_assert(not marker._entries.has("stunned"), "断言6: 灯灭→标记消失")

	# --- 断言3：禁疗/禁能/易伤字符 ---
	enemy.turn_on_light("heal_block", 5.0)
	enemy.turn_on_light("energy_block", 5.0)
	enemy.turn_on_light("vulnerable", 5.0)
	await process_frame
	_assert(str(marker._entries.get("heal_block", {}).get("char", "")) == "疗", "断言3a: 禁疗→「疗」紫标")
	_assert(str(marker._entries.get("energy_block", {}).get("char", "")) == "能", "断言3b: 禁能→「能」标")
	_assert(str(marker._entries.get("vulnerable", {}).get("char", "")) == "易", "断言3c: 易伤→补映射「易」（父类表外键）")

	# --- 断言4：敌我分流（白名单外键不显示） ---
	enemy.turn_on_light("energy_share", 5.0)  # 己方支援键
	enemy.turn_on_light("reflect", 5.0)       # 增益键
	enemy.turn_on_light("invincible", 5.0)
	await process_frame
	_assert(not marker._entries.has("energy_share") and not marker._entries.has("reflect") and not marker._entries.has("invincible"), "断言4: 己方支援/增益键被白名单滤除（敌方标记只显示减益/控制）")

	# --- 断言5：跟随=挂宿主子节点+头顶偏移（position 由接入层设置，此处同接入层行为） ---
	marker.position = MarkerScript.HEAD_OFFSET
	await process_frame
	_assert(marker.get_parent() == enemy and marker.position == MarkerScript.HEAD_OFFSET, "断言5: 挂宿主头顶（子节点随动，偏移不被布局篡改）")

	# --- 断言7：空态自动隐藏 ---
	var m2: Control = MarkerScript.new()
	root.add_child(m2)
	await process_frame
	_assert(not m2.visible, "断言7a: 无状态→空条不显示（visible=false）")
	_assert(m2.get_visible_count() == 0, "断言7b: 空条可见图标数=0")

	# --- 断言8：UI 零判定 grep（组件源码无写操作模式） ---
	var src2d: String = MarkerScript.source_code
	var src3d: String = Marker3DScript.source_code
	var bad_patterns: Array[String] = ["turn_on_light(", "turn_off_light(", "apply_mark(", "add_buff(", ".stamina", ".energy +=", ".hp ="]
	var clean := true
	for pat in bad_patterns:
		if src2d.contains(pat) or src3d.contains(pat):
			clean = false
			print("    命中写操作模式: " + pat)
	_assert(clean, "断言8: 敌标记组件源码零判定写操作（grep 核验）")

	# --- 断言9：3D 聚合文本 ---
	var marker3d: Node3D = Marker3DScript.new()
	enemy.add_child(marker3d)
	marker3d.setup(enemy)
	await process_frame
	var label: Label3D = marker3d.get_node_or_null("EnemyMarkerLabel")
	_assert(label != null, "3D: Label3D 在位")
	# 印记（挂载后命中→信号驱动快照；生产时序=开赛挂载早于任何印记）
	enemy.apply_mark("late_mark", 3, 10.0)
	enemy.apply_mark("late_mark", 3, 10.0)
	await process_frame
	var txt: String = label.text if label != null else ""
	_assert(txt.contains("疗") and txt.contains("能") and txt.contains("易"), "3D: 灯类聚合「疗 能 易」")
	_assert(txt.contains("印2"), "3D: 印记聚合「印2」")
	_assert(not txt.contains("摊") and not txt.contains("反"), "3D: 白名单外键不入聚合文本")
	# 分流开关三态
	MarkerScript.show_mode = "off"
	_assert(not MarkerScript.should_mark(enemy, null), "分流: off=全不挂")
	MarkerScript.show_mode = "own_side"
	_assert(MarkerScript.should_mark(enemy, null), "分流: own_side 无人类→降级全员（AI观测）")
	var mate: CharacterBody2D = PlayerScript.new()
	mate.team = "b"
	var foe: CharacterBody2D = PlayerScript.new()
	foe.team = "a"
	root.add_child(mate)
	root.add_child(foe)
	_assert(MarkerScript.should_mark(mate, enemy) and not MarkerScript.should_mark(foe, enemy), "分流: own_side 有人类→仅玩家方（同队挂/敌队不挂）")
	MarkerScript.show_mode = "all"
	_assert(MarkerScript.should_mark(foe, enemy), "分流: all=全员（正式版+测试平台默认）")

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail == 0:
		print("🎉 全部通过")
	else:
		print("❌ 有失败项")
	quit(0 if _fail == 0 else 1)
