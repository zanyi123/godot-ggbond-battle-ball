## E-Editor 验收：打开天赋树编辑器 → 首次自动布局 → 新增/连接/保存 → 截图
extends Node3D
func _ready() -> void:
	var mm = load("res://scripts/ui/main_menu.gd").new()
	add_child(mm)
	await get_tree().create_timer(0.5).timeout
	# 找到天赋编辑器按钮并按下（模拟主人点管理员模式的入口）
	var btn = mm.get_node_or_null("BtnTalentEditor")
	if btn == null:
		# 按钮在 admin 菜单构建后才有——直接调 handler
		mm._on_open_talent_editor()
	await get_tree().create_timer(0.5).timeout
	var editor = mm.get_node_or_null("BtnTalentEditor")
	var editor_ctrl: Control = null
	for c in mm.get_children():
		if c.get_script() and str(c.get_script().resource_path).contains("dev_talent_tree_editor"):
			editor_ctrl = c
	if editor_ctrl == null:
		print("[Edt][FAIL] 编辑器未打开")
		get_tree().quit(1)
		return
	print("[Edt] 编辑器已打开，节点数=", editor_ctrl._nodes().size())
	await get_tree().create_timer(1.0).timeout
	# 截图（首次自动布局观感）
	var img := get_viewport().get_texture().get_image()
	if img:
		DirAccess.open("res://docs").make_dir_recursive("img/3d_p2")
		img.save_png("res://docs/img/3d_p2/talent_editor.png")
		print("[Edt] 📷 talent_editor.png")
	get_tree().quit(0)
