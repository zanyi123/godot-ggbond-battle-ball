## GUI 截图自检脚本
## 运行 player_3d_test.tscn，等待几秒后截图保存
extends Node

const TEST_SCENE: String = "res://scenes/test/player_3d_test.tscn"
const SCREENSHOT_PATH: String = "E:/项目储存/决竞球battle-ball/sim_results/test_screenshot.png"  # 绝对路径

var _test_root: Node = null
var _frame_count: int = 0
var _screenshot_taken: bool = false


func _ready() -> void:
	print("[ScreenshotTest] === 开始 GUI 截图测试 ===")
	# 加载测试场景
	var scene: PackedScene = load(TEST_SCENE)
	if scene == null:
		print("[ScreenshotTest] ❌ 无法加载测试场景: %s" % TEST_SCENE)
		get_tree().quit(1)
		return
	_test_root = scene.instantiate()
	get_tree().root.add_child(_test_root)
	print("[ScreenshotTest] ✅ 测试场景加载完成")
	# 等待渲染稳定
	await get_tree().create_timer(2.0).timeout
	# 模拟 F1 投球
	print("[ScreenshotTest] === 模拟 F1 throw ===")
	if _test_root.has_method("_hk_throw"):
		_test_root._hk_throw()
	# 再等待 1 秒让球飞
	await get_tree().create_timer(1.0).timeout
	# 截图
	_take_screenshot()
	# 等待 0.5 秒确保截图完成
	await get_tree().create_timer(0.5).timeout
	print("[ScreenshotTest] === 测试完成，退出 ===")
	get_tree().quit(0)


func _take_screenshot() -> void:
	# 等待渲染完成
	await get_tree().process_frame
	await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		print("[ScreenshotTest] ❌ 截图失败: img == null")
		return
	var abs_path: String = SCREENSHOT_PATH
	var err: int = img.save_png(abs_path)
	if err == OK:
		print("[ScreenshotTest] 📷 截图保存成功: %s" % abs_path)
		print("[ScreenshotTest] 图片尺寸: %dx%d" % [img.get_width(), img.get_height()])
		# 分析截图内容
		_analyze_image(img)
	else:
		print("[ScreenshotTest] ❌ 截图保存失败 err=%d" % err)


func _analyze_image(img: Image) -> void:
	"""分析截图内容，检测模型是否正确显示"""
	var width: int = img.get_width()
	var height: int = img.get_height()
	print("[ScreenshotTest] === 截图分析 ===")
	print("[ScreenshotTest] 尺寸: %dx%d" % [width, height])

	# 检测蓝色区域（球员A的颜色）
	var blue_pixels: int = 0
	# 检测红色区域（球员B的颜色）
	var red_pixels: int = 0
	# 检测绿色区域（场地）
	var green_pixels: int = 0
	# 检测皮肤色区域（模型）
	var skin_pixels: int = 0

	# 采样区域（中心 400x400）
	var sample_left: int = max(0, width / 2 - 200)
	var sample_right: int = min(width, width / 2 + 200)
	var sample_top: int = max(0, height / 2 - 200)
	var sample_bottom: int = min(height, height / 2 + 200)

	for y in range(sample_top, sample_bottom):
		for x in range(sample_left, sample_right):
			var c: Color = img.get_pixel(x, y)
			# 蓝色检测
			if c.b > 0.6 and c.r < 0.4 and c.g < 0.5:
				blue_pixels += 1
			# 红色检测
			if c.r > 0.6 and c.b < 0.4 and c.g < 0.5:
				red_pixels += 1
			# 绿色检测（场地）
			if c.g > 0.25 and c.g < 0.35 and c.r > 0.1 and c.r < 0.2 and c.b > 0.1 and c.b < 0.2:
				green_pixels += 1
			# 皮肤色检测（模型）
			if c.r > 0.6 and c.g > 0.4 and c.g < 0.7 and c.b > 0.2 and c.b < 0.5:
				skin_pixels += 1

	print("[ScreenshotTest] 采样区域 (%d,%d)-(%d,%d):" % [sample_left, sample_top, sample_right, sample_bottom])
	print("[ScreenshotTest]   蓝色像素: %d" % blue_pixels)
	print("[ScreenshotTest]   红色像素: %d" % red_pixels)
	print("[ScreenshotTest]   绿色像素(场地): %d" % green_pixels)
	print("[ScreenshotTest]   皮肤色像素(模型): %d" % skin_pixels)

	# 判断模型是否显示
	if skin_pixels > 500:
		print("[ScreenshotTest] ✅ 检测到模型皮肤区域")
	elif skin_pixels > 100:
		print("[ScreenshotTest] ⚠️ 检测到少量皮肤区域，模型可能太小")
	else:
		print("[ScreenshotTest] ❌ 未检测到模型皮肤区域，模型可能未显示")

	# 判断场地
	if green_pixels > 1000:
		print("[ScreenshotTest] ✅ 检测到场地")
	else:
		print("[ScreenshotTest] ⚠️ 场地像素较少")