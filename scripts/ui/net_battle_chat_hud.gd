## 工单01 S13.2/D23 · 对局聊天 HUD 最小版（联机模式挂 battle；主人在用窗口期仅落码未测）
## Enter 唤起半透明输入条（再 Enter 发送/Esc 关闭）；最近 4 条小字（系统播报与玩家消息同区）。
## 已知限制（如实）：输入条打开期间 host 本地键位屏蔽清单（回签三）未接——guest 侧已由
## battle_manager._net_guest_forward_input 在聊天打开时暂停上行；host 侧防误触待操控域键位批。
class_name NetBattleChatHud
extends Control

var _box: VBoxContainer
var _edit: LineEdit
var _open := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_box = VBoxContainer.new()
	_box.position = Vector2(20, 620)
	_box.size = Vector2(420, 200)
	add_child(_box)
	_edit = LineEdit.new()
	_edit.placeholder_text = "回车发送（对局=仅同队；Esc 关闭）"
	_edit.position = Vector2(20, 826)
	_edit.size = Vector2(420, 32)
	_edit.text_submitted.connect(_on_send)
	add_child(_edit)
	_edit.visible = false
	var s := NetManager.session
	if s != null:
		s.chat_display.connect(_on_chat)

func _input(event: InputEvent) -> void:
	if not NetManager.active or NetManager.session == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER:
			if not _open:
				_open = true
				visible = true
				_edit.visible = true
				_edit.grab_focus()
				get_viewport().set_input_as_handled()
			# 打开态的 Enter 由 LineEdit text_submitted 处理
		elif event.keycode == KEY_ESCAPE and _open:
			_close()

func _on_send(text: String) -> void:
	if NetManager.session != null:
		NetManager.session.send_chat(text)
	_close()

func _close() -> void:
	_open = false
	_edit.visible = false
	_edit.release_focus()
	visible = false

func _on_chat(chat: Dictionary, mine: bool) -> void:
	var tag := "【队】" if str(chat.get("channel")) == NetSchema.CHAT_CHANNEL_TEAM else ""
	var l := Label.new()
	l.text = "%s%s: %s" % [tag, str(chat.get("from_name")), str(chat.get("text"))]
	l.add_theme_font_size_override("font_size", 14)
	l.modulate = Color(1, 1, 1, 0.85)
	_box.add_child(l)
	while _box.get_child_count() > 4:
		_box.get_child(0).queue_free()
