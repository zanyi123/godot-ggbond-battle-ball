extends Control
class_name DevGrowthPanel
## 成长曲线规划面板 - 开发者工具
## 新建球员时配置：每一级场地对应一个属性上限数据点
## 球员基础属性固定，训练往上加，但不超过当前场地等级的上限

signal closed()

const TRAIN_STATS_INFO := {
	"stamina": {"name": "体力", "color": Color.GREEN, "max": 300, "step": 1},
	"defense": {"name": "防御", "color": Color(0.4, 0.7, 1.0), "max": 200, "step": 1},
	"speed": {"name": "速度", "color": Color(1.0, 0.8, 0.3), "max": 200, "step": 1},
	"attack": {"name": "攻击", "color": Color(1.0, 0.4, 0.4), "max": 150, "step": 1},
	"resilience": {"name": "韧性", "color": Color(0.8, 0.5, 1.0), "max": 200, "step": 1},
	"ball_speed": {"name": "球速", "color": Color(0.5, 1.0, 0.6), "max": 1000, "step": 5},
}
const TRAIN_STATS_ORDER := ["stamina", "defense", "speed", "attack", "resilience", "ball_speed"]
const MAX_FIELD_LEVEL := 10

## 默认每级固定增量（非百分比）
const DEFAULT_INCREMENT := {
	"stamina": 10,
	"defense": 8,
	"speed": 8,
	"attack": 5,
	"resilience": 6,
	"ball_speed": 30,
}

var _curves: Dictionary = {}
var _selected_char_id: String = ""
var _selected_level: int = 1
var _stat_sliders: Dictionary = {}
var _stat_labels: Dictionary = {}
var _level_buttons: Array = []
var _char_buttons: Dictionary = {}
var _base_info_label: Label = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_curves = DevDataSync.load_growth_curves()
	_build_ui()
	if _initial_char_id != "":
		_on_char_selected(_initial_char_id)


var _initial_char_id: String = ""


func set_initial_character(char_id: String) -> void:
	_initial_char_id = char_id


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.06, 0.10, 0.97)
	add_child(bg)

	# 标题栏
	var title_bar := HBoxContainer.new()
	title_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_bar.offset_top = 15
	title_bar.offset_bottom = 60
	add_child(title_bar)

	var title := Label.new()
	title.text = "成长曲线规划"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.8, 0.6, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(title)

	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.custom_minimum_size = Vector2(80, 40)
	save_btn.add_theme_font_size_override("font_size", 14)
	save_btn.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	save_btn.pressed.connect(_on_save)
	title_bar.add_child(save_btn)

	var back_btn := Button.new()
	back_btn.text = "← 返回"
	back_btn.custom_minimum_size = Vector2(80, 40)
	back_btn.add_theme_font_size_override("font_size", 14)
	back_btn.pressed.connect(_on_back)
	title_bar.add_child(back_btn)

	# 左侧：球员列表
	var player_list := ScrollContainer.new()
	player_list.offset_left = 20
	player_list.offset_top = 70
	player_list.offset_right = 220
	player_list.offset_bottom = 780
	player_list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(player_list)

	var player_vbox := VBoxContainer.new()
	player_vbox.custom_minimum_size = Vector2(190, 0)
	player_vbox.add_theme_constant_override("separation", 5)
	player_list.add_child(player_vbox)

	var chars: Array = DataManager.characters
	for char in chars:
		var cid: String = char.get("id", "")
		var cname: String = char.get("name", "")
		if cid == "":
			continue
		var btn := Button.new()
		btn.text = cname
		btn.custom_minimum_size = Vector2(180, 35)
		btn.add_theme_font_size_override("font_size", 14)
		btn.toggle_mode = true
		btn.pressed.connect(_on_char_selected.bind(cid))
		player_vbox.add_child(btn)
		_char_buttons[cid] = btn

	# 上方：场地等级选择
	var level_select := HBoxContainer.new()
	level_select.offset_left = 240
	level_select.offset_top = 70
	level_select.offset_right = 1420
	level_select.offset_bottom = 110
	level_select.add_theme_constant_override("separation", 4)
	add_child(level_select)

	var level_label := Label.new()
	level_label.text = "场地等级: "
	level_label.add_theme_font_size_override("font_size", 15)
	level_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	level_select.add_child(level_label)

	for level in range(1, MAX_FIELD_LEVEL + 1):
		var btn := Button.new()
		btn.text = "Lv.%d" % level
		btn.custom_minimum_size = Vector2(58, 30)
		btn.add_theme_font_size_override("font_size", 13)
		btn.toggle_mode = true
		btn.pressed.connect(_on_level_selected.bind(level))
		level_select.add_child(btn)
		_level_buttons.append(btn)

	# 中间：属性滑块区
	var content := ScrollContainer.new()
	content.offset_left = 240
	content.offset_top = 120
	content.offset_right = 1420
	content.offset_bottom = 780
	content.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(content)

	var content_vbox := VBoxContainer.new()
	content_vbox.custom_minimum_size = Vector2(1170, 0)
	content_vbox.add_theme_constant_override("separation", 8)
	content.add_child(content_vbox)

	# 基础属性参考
	_base_info_label = Label.new()
	_base_info_label.text = "请先选择球员"
	_base_info_label.add_theme_font_size_override("font_size", 13)
	_base_info_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.8))
	content_vbox.add_child(_base_info_label)

	# 说明
	var desc_label := Label.new()
	desc_label.text = "拖动滑块设置当前场地等级下各项属性的最大上限值（训练不能超过此值）"
	desc_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	desc_label.add_theme_font_size_override("font_size", 12)
	content_vbox.add_child(desc_label)

	# 6个属性滑块
	for stat_key in TRAIN_STATS_ORDER:
		var info: Dictionary = TRAIN_STATS_INFO.get(stat_key, {})
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 40)

		var name_lbl := Label.new()
		name_lbl.text = info.name
		name_lbl.add_theme_font_size_override("font_size", 15)
		name_lbl.add_theme_color_override("font_color", info.color)
		name_lbl.custom_minimum_size = Vector2(60, 35)
		row.add_child(name_lbl)

		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = info.max
		slider.step = info.step
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(_on_slider_changed.bind(stat_key))
		row.add_child(slider)
		_stat_sliders[stat_key] = slider

		var val_lbl := Label.new()
		val_lbl.custom_minimum_size = Vector2(60, 35)
		val_lbl.add_theme_font_size_override("font_size", 14)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val_lbl)
		_stat_labels[stat_key] = val_lbl

		content_vbox.add_child(row)

	# 底部按钮
	var gen_btn := Button.new()
	gen_btn.text = "生成当前球员默认曲线（基于基础属性，每级固定数值递增）"
	gen_btn.custom_minimum_size = Vector2(0, 38)
	gen_btn.add_theme_font_size_override("font_size", 13)
	gen_btn.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	gen_btn.pressed.connect(_on_generate_default)
	content_vbox.add_child(gen_btn)

	var gen_all_btn := Button.new()
	gen_all_btn.text = "生成所有球员默认曲线"
	gen_all_btn.custom_minimum_size = Vector2(0, 38)
	gen_all_btn.add_theme_font_size_override("font_size", 13)
	gen_all_btn.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
	gen_all_btn.pressed.connect(_on_generate_all_default)
	content_vbox.add_child(gen_all_btn)


func _on_char_selected(char_id: String) -> void:
	_selected_char_id = char_id
	_update_base_info()
	_update_sliders()


func _on_level_selected(level: int) -> void:
	_selected_level = level
	_update_sliders()


func _update_base_info() -> void:
	if _selected_char_id == "":
		_base_info_label.text = "请先选择球员"
		return
	var char_data: Dictionary = DataManager.get_character_by_id(_selected_char_id)
	var cname: String = char_data.get("name", "")
	var info_text := "%s 基础属性: " % cname
	for i in range(TRAIN_STATS_ORDER.size()):
		var sk: String = TRAIN_STATS_ORDER[i]
		var base_val: float = float(char_data.get(sk, 0))
		var display_name: String = TRAIN_STATS_INFO[sk].name
		if i > 0:
			info_text += " | "
		info_text += "%s %.0f" % [display_name, base_val]
	_base_info_label.text = info_text


func _update_sliders() -> void:
	if _selected_char_id == "":
		return

	var char_curve: Dictionary = _curves.get(_selected_char_id, {})
	var level_key: String = "field_level_%d" % _selected_level
	var level_data: Dictionary = char_curve.get(level_key, {})

	for stat_key in TRAIN_STATS_ORDER:
		var slider: HSlider = _stat_sliders.get(stat_key, null)
		var val_lbl: Label = _stat_labels.get(stat_key, null)
		if slider and val_lbl:
			var val: float = float(level_data.get(stat_key + "_max", 0))
			# 避免触发 value_changed 信号
			slider.set_block_signals(true)
			slider.value = val
			slider.set_block_signals(false)
			val_lbl.text = str(int(val))

	_refresh_button_states()


func _refresh_button_states() -> void:
	for cid in _char_buttons:
		var btn: Button = _char_buttons[cid]
		btn.button_pressed = (cid == _selected_char_id)

	for i in range(_level_buttons.size()):
		var btn: Button = _level_buttons[i]
		btn.button_pressed = ((i + 1) == _selected_level)


func _on_slider_changed(stat_key: String, value: float) -> void:
	if _selected_char_id == "":
		return

	if not _curves.has(_selected_char_id):
		var char_data: Dictionary = DataManager.get_character_by_id(_selected_char_id)
		_curves[_selected_char_id] = {"name": char_data.get("name", "")}

	var level_key: String = "field_level_%d" % _selected_level
	if not _curves[_selected_char_id].has(level_key):
		_curves[_selected_char_id][level_key] = {}

	var new_val: int = int(value)

	# 限制1：不能小于前一级（Lv.N >= Lv.N-1）
	if _selected_level > 1:
		var prev_key: String = "field_level_%d" % (_selected_level - 1)
		var prev_data: Dictionary = _curves[_selected_char_id].get(prev_key, {})
		var prev_val: int = int(prev_data.get(stat_key + "_max", 0))
		if new_val < prev_val:
			new_val = prev_val
			var slider: HSlider = _stat_sliders.get(stat_key, null)
			if slider:
				slider.set_block_signals(true)
				slider.value = new_val
				slider.set_block_signals(false)

	_curves[_selected_char_id][level_key][stat_key + "_max"] = new_val

	# 更新数值显示
	var val_lbl: Label = _stat_labels.get(stat_key, null)
	if val_lbl:
		val_lbl.text = str(new_val)

	# 限制2：向后级联，后续等级如果小于当前值则提升（保持单调递增）
	var cascade_val: int = new_val
	var check_level: int = _selected_level + 1
	while check_level <= MAX_FIELD_LEVEL:
		var next_key: String = "field_level_%d" % check_level
		if not _curves[_selected_char_id].has(next_key):
			_curves[_selected_char_id][next_key] = {}
		var next_data: Dictionary = _curves[_selected_char_id][next_key]
		var next_val: int = int(next_data.get(stat_key + "_max", 0))
		if next_val < cascade_val:
			_curves[_selected_char_id][next_key][stat_key + "_max"] = cascade_val
		else:
			break
		check_level += 1


func _generate_default_curve(char_data: Dictionary) -> Dictionary:
	var base_stats := {
		"stamina": float(char_data.get("stamina", 80)),
		"defense": float(char_data.get("defense", 60)),
		"speed": float(char_data.get("speed", 70)),
		"attack": float(char_data.get("attack", 40)),
		"resilience": float(char_data.get("resilience", 50)),
		"ball_speed": float(char_data.get("ball_speed", 400))
	}

	var char_curve: Dictionary = {"name": char_data.get("name", "")}
	for level in range(1, MAX_FIELD_LEVEL + 1):
		# Lv.N 上限 = 基础值 + N * 每级增量
		char_curve["field_level_%d" % level] = {
			"stamina_max": int(round(base_stats["stamina"] + level * DEFAULT_INCREMENT["stamina"])),
			"defense_max": int(round(base_stats["defense"] + level * DEFAULT_INCREMENT["defense"])),
			"speed_max": int(round(base_stats["speed"] + level * DEFAULT_INCREMENT["speed"])),
			"attack_max": int(round(base_stats["attack"] + level * DEFAULT_INCREMENT["attack"])),
			"resilience_max": int(round(base_stats["resilience"] + level * DEFAULT_INCREMENT["resilience"])),
			"ball_speed_max": int(round(base_stats["ball_speed"] + level * DEFAULT_INCREMENT["ball_speed"]))
		}
	return char_curve


func _on_generate_default() -> void:
	if _selected_char_id == "":
		return
	var char_data: Dictionary = DataManager.get_character_by_id(_selected_char_id)
	if char_data.is_empty():
		return
	_curves[_selected_char_id] = _generate_default_curve(char_data)
	_update_sliders()
	print("[成长曲线] 已生成 %s 的默认曲线（固定数值递增）" % char_data.get("name", ""))


func _on_generate_all_default() -> void:
	var chars: Array = DataManager.characters
	for char in chars:
		var cid: String = char.get("id", "")
		if cid == "":
			continue
		_curves[cid] = _generate_default_curve(char)
	_update_sliders()
	print("[成长曲线] 已生成所有球员默认曲线")


func _on_save() -> void:
	var ok: bool = DevDataSync.save_growth_curves(_curves)
	if ok:
		TrainingManager.set_growth_curves(_curves)
		print("[成长曲线] 保存成功")
	else:
		print("[成长曲线] 保存失败")


func _on_back() -> void:
	closed.emit()
