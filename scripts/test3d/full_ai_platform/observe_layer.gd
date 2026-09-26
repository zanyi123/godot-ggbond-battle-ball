extends CanvasLayer
## 工单10 P3 观测层 —— 平台窗口
## 决策/通讯/开关可视化：全部只读既有口（spirit_ai_data / message_sent 信号 / registry.is_wave_enabled）。
## 开关热切：写 switches.json + registry.reload_switches()（08 已授权平台窗口热改）；
##   提供"恢复进入时状态"按钮与"全关(交付态)"按钮，防污染主游戏。
## F9 收起/展开。headless 下平台不会创建本层。

const SpiritAIPrimitiveRegistry := preload("res://scripts/battle/spirit_ai/primitive_registry.gd")
const SWITCHES_PATH := "res://data/systems/spirit_ai/switches.json"
const MSG_TEXT := {
	0: "防守!", 1: "传我!", 2: "别传!", 3: "技能就绪!", 4: "加油!", 5: "需要支援!",
}

var bm: Node2D = null
var _panel: PanelContainer = null
var _player_rows: Array[Label] = []
var _wave_boxes: Dictionary = {}       # "master"/"A".."E" -> CheckBox
var _state_line: Label = null
var _decision_label: Label = null
var _comm_log: RichTextLabel = null
var _switches_snapshot: String = ""    # 进入时 switches.json 原文（供恢复）
var _refresh_accum: float = 0.0


func setup(battle_manager: Node2D) -> void:
	bm = battle_manager
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_switches_snapshot = _read_switches_text()
	_build_ui()
	# 开关状态以文件实态为准（含 registry 未加载过的情形）
	SpiritAIPrimitiveRegistry.reload_switches()
	_sync_boxes_from_file()
	_refresh_state_line()
	if bm.comm_system and bm.comm_system.has_signal("message_sent"):
		bm.comm_system.message_sent.connect(_on_comm_message)
		_append_comm("[观测] 通讯日志已挂接（message_sent）")
	else:
		_append_comm("[观测] ⚠ comm_system 不可用")


func _input(event: InputEvent) -> void:
	if _panel == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F9:
			_panel.visible = not _panel.visible


func _process(delta: float) -> void:
	_refresh_accum += delta
	if _refresh_accum < 0.5:
		return
	_refresh_accum = 0.0
	_refresh_player_rows()
	_refresh_decision()


# ==================== UI 构建 ====================

func _build_ui() -> void:
	var root := Control.new()
	root.name = "ObserveRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.name = "ObservePanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 10)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.custom_minimum_size = Vector2(350, 0)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "完全体AI 观测层（F9 收起）"
	title.add_theme_font_size_override("font_size", 15)
	vbox.add_child(title)

	# --- 球员行（A0-A2 / B0-B2）---
	var all_players: Array = []
	if bm:
		all_players = bm.team_a_players + bm.team_b_players
	for i in range(all_players.size()):
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 12)
		vbox.add_child(row)
		_player_rows.append(row)

	# --- 波次开关热切 ---
	vbox.add_child(HSeparator.new())
	var sw_title := Label.new()
	sw_title.text = "波次开关（热切：写 switches.json + registry.reload）"
	sw_title.add_theme_font_size_override("font_size", 13)
	vbox.add_child(sw_title)

	var master_row := HBoxContainer.new()
	vbox.add_child(master_row)
	_wave_boxes["master"] = _make_switch(master_row, "总开关 master")
	for wave in ["A", "B", "C", "D"]:
		_wave_boxes[wave] = _make_switch(master_row, "波%s" % wave)
	var wave_e := _make_switch(master_row, "波E")
	wave_e.disabled = true
	wave_e.tooltip_text = "波E 长尾未排期"
	_wave_boxes["E"] = wave_e

	var btn_row := HBoxContainer.new()
	vbox.add_child(btn_row)
	btn_row.add_child(_make_button("一键全开", _on_all_on))
	btn_row.add_child(_make_button("全关(交付态)", _on_all_off))
	btn_row.add_child(_make_button("恢复进入时状态", _on_restore_snapshot))

	_state_line = Label.new()
	_state_line.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_state_line)
	_refresh_state_line()

	# --- 决策 dump 口 ---
	vbox.add_child(HSeparator.new())
	_decision_label = Label.new()
	_decision_label.add_theme_font_size_override("font_size", 12)
	_decision_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_decision_label)

	# --- 队内通讯日志 ---
	vbox.add_child(HSeparator.new())
	var comm_title := Label.new()
	comm_title.text = "队内通讯（message_sent）"
	comm_title.add_theme_font_size_override("font_size", 13)
	vbox.add_child(comm_title)
	_comm_log = RichTextLabel.new()
	_comm_log.bbcode_enabled = false
	_comm_log.scroll_following = true
	_comm_log.custom_minimum_size = Vector2(0, 110)
	_comm_log.add_theme_font_size_override("normal_font_size", 12)
	vbox.add_child(_comm_log)


func _make_switch(parent: Control, text: String) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.add_theme_font_size_override("font_size", 12)
	box.pressed.connect(_on_switch_clicked)
	parent.add_child(box)
	return box


func _make_button(text: String, handler: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 12)
	btn.pressed.connect(handler)
	return btn


# ==================== 刷新 ====================

func _refresh_player_rows() -> void:
	if bm == null or not is_instance_valid(bm):
		return
	var sam = bm.ai_mgr.spirit_ai_mgr if bm.ai_mgr else null
	var all_players: Array = bm.team_a_players + bm.team_b_players
	for i in range(mini(all_players.size(), _player_rows.size())):
		var player = all_players[i]
		if player == null or not is_instance_valid(player):
			continue
		var slot := "A%d" % i if i < 3 else "B%d" % (i - 3)
		var spirit_name := str(player.spirit_id)
		for spirit_data in DataManager.spirits:
			if str(spirit_data.get("id", "")) == spirit_name:
				spirit_name = str(spirit_data.get("name", spirit_name))
				break
		var cd_active := 0
		for sid in player.skill_cooldowns:
			if float(player.skill_cooldowns[sid]) > 0.0:
				cd_active += 1
		var decide_count := 0
		if sam:
			for sad in sam.spirit_ai_data:
				if sad.get("player") == player:
					decide_count = int(sad.get("skill_decide_count", 0))
					break
		_player_rows[i].text = "%s %s[%s] 能量%d/%d 冷却%d 技%d 决策%d" % [
			slot, str(player.char_data.get("name", "?")), spirit_name,
			int(player.spirit_energy), int(player.max_spirit_energy),
			cd_active, player.get_equipped_skills().size(), decide_count]


func _refresh_decision() -> void:
	if _decision_label == null or bm == null:
		return
	var sam = bm.ai_mgr.spirit_ai_mgr if bm.ai_mgr else null
	if sam and sam.has_method("get_decision_dump"):
		# 集成窗口 dump 口（10工单 P3 配套，~15行只读口）落地后自动点亮
		_decision_label.text = str(sam.get_decision_dump())
	else:
		_decision_label.text = "决策评分明细：待集成窗口 dump 口（10工单P3残留，接口探活中）"


func _refresh_state_line() -> void:
	if _state_line == null:
		return
	var parts: Array[String] = []
	parts.append("master=%s" % ("开" if SpiritAIPrimitiveRegistry._switches.get("master_enabled", false) else "关"))
	for wave in ["A", "B", "C", "D", "E"]:
		parts.append("%s=%s" % [wave, "开" if SpiritAIPrimitiveRegistry.is_wave_enabled(wave) else "关"])
	_state_line.text = " ".join(parts)


# ==================== 开关热切 ====================

func _on_switch_clicked() -> void:
	_write_switches()


func _on_all_on() -> void:
	for key in _wave_boxes:
		var box: CheckBox = _wave_boxes[key]
		if key != "E":
			box.set_pressed_no_signal(true)
	_write_switches()


func _on_all_off() -> void:
	for key in _wave_boxes:
		var box: CheckBox = _wave_boxes[key]
		box.set_pressed_no_signal(false)
	_write_switches()


func _on_restore_snapshot() -> void:
	if _switches_snapshot.is_empty():
		return
	var f := FileAccess.open(SWITCHES_PATH, FileAccess.WRITE)
	if f:
		f.store_string(_switches_snapshot)
		f.close()
	SpiritAIPrimitiveRegistry.reload_switches()
	_sync_boxes_from_file()
	_refresh_state_line()
	_append_comm("[观测] switches.json 已恢复进入时状态")


func _write_switches() -> void:
	var current := _read_switches_json()
	if current.is_empty():
		_append_comm("[观测] ⚠ switches.json 读取失败，热切中止")
		return
	current["master_enabled"] = _wave_boxes["master"].button_pressed
	var waves: Dictionary = current.get("waves", {})
	for wave in ["A", "B", "C", "D", "E"]:
		if _wave_boxes.has(wave) and waves.has(wave):
			waves[wave] = _wave_boxes[wave].button_pressed
	current["waves"] = waves
	var f := FileAccess.open(SWITCHES_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(current, "	"))
		f.close()
	SpiritAIPrimitiveRegistry.reload_switches()
	_refresh_state_line()
	_append_comm("[观测] 开关已热切 → %s" % _state_line.text)


func _sync_boxes_from_file() -> void:
	var data := _read_switches_json()
	if data.is_empty():
		return
	_wave_boxes["master"].set_pressed_no_signal(bool(data.get("master_enabled", false)))
	var waves: Dictionary = data.get("waves", {})
	for wave in ["A", "B", "C", "D", "E"]:
		if _wave_boxes.has(wave) and waves.has(wave):
			_wave_boxes[wave].set_pressed_no_signal(bool(waves[wave]))


func _read_switches_text() -> String:
	if not FileAccess.file_exists(SWITCHES_PATH):
		return ""
	var f := FileAccess.open(SWITCHES_PATH, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _read_switches_json() -> Dictionary:
	var text := _read_switches_text()
	if text.is_empty():
		return {}
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


# ==================== 通讯日志 ====================

func _on_comm_message(sender: CharacterBody2D, msg_type: int, team: String) -> void:
	var text := str(MSG_TEXT.get(msg_type, "消息#%d" % msg_type))
	var who := "?"
	if sender and is_instance_valid(sender):
		who = str(sender.char_data.get("name", sender.name))
	_append_comm("[%s] %s: %s" % [team.to_upper(), who, text])


func _append_comm(line: String) -> void:
	if _comm_log == null:
		return
	_comm_log.append_text(line + "\n")
	var lines := _comm_log.get_line_count()
	if lines > 60:
		_comm_log.clear()
		_append_comm("[观测] （日志过长已清屏）")
		_comm_log.append_text(line + "\n")
