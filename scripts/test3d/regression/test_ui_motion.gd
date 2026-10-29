## U0-5 · UI 动效小库套件（美术UI线乙线窗口 · 2026-10-28）
## 运行：bash ./run_suite_guarded.sh res://scripts/test3d/regression/test_ui_motion.gd
## 覆盖：C1 参数源 / C2 shader 资源 / C3 hover_pop / C4 slide_in / C5 breathe / C6 edge_sweep /
##       C7 空参安全 / C8 cfg_reload 幂等
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
	print("\n========== U0-5 · UI 动效小库套件（UiMotion） ==========\n")

	# C1 参数源（json 唯一来源）
	_assert(UiMotion.num("tween.slide_in.dur", -1.0) == 0.32, "C1a: slide_in 时长==0.32（json）")
	_assert(UiMotion.num("tween.hover_pop.scale", -1.0) == 1.04, "C1b: 悬停幅度==1.04（json）")
	_assert(UiMotion.num("shader.breathe_period", -1.0) == 4.0, "C1c: 呼吸周期==4.0（json）")
	_assert(UiMotion.num("不存在的键", 7.0) == 7.0, "C1d: 缺键回退不炸")

	# C2 shader 资源可加载
	var sh_b: Shader = load("res://scripts/ui/shaders/ui_breathe.gdshader")
	var sh_s: Shader = load("res://scripts/ui/shaders/ui_edge_sweep.gdshader")
	_assert(sh_b != null and sh_s != null, "C2: 呼吸/流光两支 shader 加载成功")

	# C3 hover_pop（真 Tween 在真实节点上）
	var c := Control.new()
	root.add_child(c)
	c.size = Vector2(400, 60)
	var tw: Tween = UiMotion.hover_pop(c)
	_assert(tw != null and tw.is_running(), "C3a: hover_pop 生成运行中的 Tween")
	_assert(c.pivot_offset == c.size * 0.5, "C3b: 缩放轴取中心")
	tw.kill()

	# C4 slide_in（起始偏移+淡入起点）
	var d := Control.new()
	root.add_child(d)
	d.position = Vector2(100, 100)
	var tw2: Tween = UiMotion.slide_in(d, Vector2(0, 24))
	_assert(tw2 != null and d.position.y > 100.0, "C4a: slide_in 起始位置带偏移")
	_assert(d.modulate.a == 0.0, "C4b: 淡入起点 alpha==0")
	tw2.kill()

	# C5 breathe
	var e := ColorRect.new()
	root.add_child(e)
	var mat: ShaderMaterial = UiMotion.breathe(e)
	_assert(mat != null and e.material == mat and mat.shader != null, "C5a: breathe 材质挂接")
	_assert(absf(mat.get_shader_parameter("breathe_period") - 4.0) < 0.001, "C5b: 呼吸周期参数注入==4.0")

	# C6 edge_sweep（挂主按钮）
	var btn := Button.new()
	root.add_child(btn)
	var mat2: ShaderMaterial = UiMotion.edge_sweep(btn, UiPalette.col("semantic.primary_hi"))
	_assert(mat2 != null and btn.material == mat2, "C6a: edge_sweep 材质挂接")
	_assert(absf(mat2.get_shader_parameter("sweep_period") - 3.2) < 0.001, "C6b: 扫描周期注入==3.2")
	var sc: Color = mat2.get_shader_parameter("sweep_color")
	_assert(sc.r == UiPalette.col("semantic.primary_hi").r and absf(sc.a - 0.5) < 0.001, "C6c: 扫描色=传入色板色+json alpha 0.5")

	# C7 空参安全（UI 零判定红线：绝不让面板炸）
	_assert(UiMotion.hover_pop(null) == null, "C7a: hover_pop(null) 安全返回")
	_assert(UiMotion.slide_in(null, Vector2.ZERO) == null, "C7b: slide_in(null) 安全返回")
	_assert(UiMotion.breathe(null) == null, "C7c: breathe(null) 安全返回")
	_assert(UiMotion.edge_sweep(null, Color.WHITE) == null, "C7d: edge_sweep(null) 安全返回")

	# C8 cfg_reload 幂等
	UiMotion.cfg_reload()
	_assert(UiMotion.num("tween.fade_in.dur", -1.0) == 0.25, "C8: reload 后取值一致（幂等）")

	# 清理
	for n in [c, d, e, btn]:
		root.remove_child(n)
		n.free()
