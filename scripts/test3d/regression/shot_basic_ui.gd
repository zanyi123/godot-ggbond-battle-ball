## 19 工单截图补档：非 headless 渲染状态图标条/盾弧面 → docs/img/（有窗口环境补档，06/19 工单要求）
extends SceneTree

func _initialize() -> void:
	_run()

func _run() -> void:
	var bar_script: GDScript = load("res://scripts/battle/status_icon_bar.gd")
	var bar: Control = bar_script.new()
	bar.position = Vector2(60, 60)
	bar.scale = Vector2(3, 3)   # 放大便于目验
	root.add_child(bar)
	# 填典型条目：禁疗/禁能/反伤/免疫/分摊/印记2层/充能3/6/盾2次/开关
	bar.set_entry("heal_block", "疗", Color(0.65, 0.3, 0.85), 4)
	bar.set_entry("energy_block", "能", Color(0.45, 0.55, 0.65), 7)
	bar.set_entry("reflect", "反", Color(1.0, 0.45, 0.2), 2)
	bar.set_entry("element_immune", "免", Color(0.95, 0.95, 0.95), 5)
	bar.set_entry("energy_share", "摊", Color(0.2, 0.8, 0.8), 9)
	bar.set_entry("mark_frost", "印", Color(0.3, 0.85, 0.4), 0, 2)
	bar.set_entry("charge_stock", "储", Color(0.3, 0.7, 0.9), 8, 0, 3, 6)
	bar.set_entry("shield", "盾", Color(1.0, 0.84, 0.0), 0, 0, 2, 3)
	bar.set_entry("toggle_t1", "T", Color(0.9, 0.75, 0.25), 0)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.12, 0.18)
	bg.size = Vector2(640, 200)
	root.add_child(bg)
	root.move_child(bg, 0)
	for i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png("res://docs/img/ui_status_bar_shot.png")
	print("[Shot] 已存 docs/img/ui_status_bar_shot.png size=", img.get_size())
	quit(0)
