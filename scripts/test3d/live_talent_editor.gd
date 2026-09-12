## 真实鼠标测试用：打开天赋编辑器并保持运行（不自动退出）
extends Node3D
func _ready() -> void:
	var mm = load("res://scripts/ui/main_menu.gd").new()
	add_child(mm)
	await get_tree().create_timer(1.0).timeout
	mm._on_open_talent_editor()
	# 置顶：防多窗口焦点争夺干扰真实鼠标测试
	get_window().always_on_top = true
	print("[Live] 编辑器已打开（置顶），等待真实鼠标操作")
