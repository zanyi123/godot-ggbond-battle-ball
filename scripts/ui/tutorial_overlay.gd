extends Control

## U1 · 溯源第一课教学蒙层（美术UI线乙线窗口 · 2026-10-28）
## 文案数据源：res://data/ui/tutorial_steps.json（改文案只改 json）
## 职责：只出蒙层+步骤卡与翻页；触发时机/高亮区域=实现窗口（v2 再做区域高亮与箭头）
## API：start() 开课 / next() 下一步；信号：tutorial_finished

signal tutorial_finished

const STEPS_PATH := "res://data/ui/tutorial_steps.json"

var _steps: Array = []
var _idx: int = -1
var _dim: ColorRect
var _card: PanelContainer
var _title: Label
var _body: Label
var _next_btn: Button


func _ready() -> void:
	theme = UiTheme.shared()
	visible = false
	_build()
	_load_steps()


func _load_steps() -> void:
	_steps = []
	if FileAccess.file_exists(STEPS_PATH):
		var f := FileAccess.open(STEPS_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary and parsed.get("steps") is Array:
				_steps = parsed["steps"]


func _build() -> void:
	var c: Color = UiPalette.col("semantic.bg_base")
	_dim = ColorRect.new()
	_dim.color = Color(c.r, c.g, c.b, 0.7)
	_dim.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_dim)

	_card = PanelContainer.new()
	_card.theme_type_variation = "PanelHighlighted"
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.anchor_top = 0.5
	_card.anchor_bottom = 0.5
	_card.offset_left = -300
	_card.offset_right = 300
	_card.offset_top = -150
	_card.offset_bottom = 150
	add_child(_card)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_card.add_child(v)

	_title = Label.new()
	_title.theme_type_variation = "LblTitle"
	v.add_child(_title)

	_body = Label.new()
	_body.theme_type_variation = "LblCaption"
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(540, 0)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_body)

	_next_btn = Button.new()
	_next_btn.text = "下一步"
	_next_btn.theme_type_variation = "BtnPrimary"
	_next_btn.pressed.connect(next)
	v.add_child(_next_btn)


## 开课（实现窗口在合适时机调用；无步骤数据时直接发完成信号防卡流程）
func start() -> void:
	if _steps.is_empty():
		tutorial_finished.emit()
		return
	_idx = 0
	visible = true
	_show_step()


func next() -> void:
	if _idx < 0 or _steps.is_empty():
		return
	_idx += 1
	if _idx >= _steps.size():
		_idx = -1
		visible = false
		tutorial_finished.emit()
		return
	_show_step()


func _show_step() -> void:
	var step: Dictionary = _steps[_idx]
	_title.text = str(step.get("title", ""))
	_body.text = str(step.get("text", ""))
	_next_btn.text = "下一步" if _idx < _steps.size() - 1 else "开 始 选 拔"
	UiMotion.slide_in(_card, Vector2(0, 24))


func step_index() -> int:
	return _idx


func step_count() -> int:
	return _steps.size()
