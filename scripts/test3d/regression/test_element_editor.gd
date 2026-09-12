## 元素克制编辑器验收：打开→切克制关系→倍率→保存→截图
extends Node3D
func _ready() -> void:
	var mm = load("res://scripts/ui/main_menu.gd").new()
	add_child(mm)
	await get_tree().create_timer(0.5).timeout
	mm._on_open_element_editor()
	await get_tree().create_timer(0.5).timeout
	var editor: Control = null
	for c in mm.get_children():
		if c.get_script() and str(c.get_script().resource_path).contains("dev_element_counter_editor"):
			editor = c
	if editor == null:
		print("[ElemEdt][FAIL] 编辑器未打开")
		get_tree().quit(1)
		return
	var before: int = editor.counters.size()
	# 切一对克制（金刚→冰雪，原数据里不存在）
	editor._on_element_pressed("金刚")
	editor._on_element_pressed("冰雪")
	var after: int = editor.counters.size()
	print("[ElemEdt][%s] 切换克制 金刚→冰雪 (%d→%d 条)" % ["PASS" if after == before + 1 else "FAIL", before, after])
	# 再切一次应移除
	editor._on_element_pressed("金刚")
	editor._on_element_pressed("冰雪")
	print("[ElemEdt][%s] 再切移除 (%d 条)" % ["PASS" if editor.counters.size() == before else "FAIL", editor.counters.size()])
	# 保存+截图
	editor._save_data()
	await get_tree().create_timer(0.5).timeout
	var img := get_viewport().get_texture().get_image()
	if img:
		DirAccess.open("res://docs").make_dir_recursive("img/3d_p2")
		img.save_png("res://docs/img/3d_p2/element_editor.png")
		print("[ElemEdt] 📷 element_editor.png")
	var ok: bool = editor.counters.size() == before
	print("[ElemEdt] RESULT: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
