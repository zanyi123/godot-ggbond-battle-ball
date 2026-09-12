## 元素克制编辑器（dev_tools · 事件-响应·元素克制可视化）
## 功能：
##   · 六元素环形排布，克制关系箭头可视化（攻击方→被克方）
##   · 点击两个元素切换克制关系（A→B 增/删，直接改 counters 数组）
##   · 克制倍率编辑（counter_multiplier）
##   · 保存写回 elements.json（重启对局后 DataManager 重新加载生效）
## 数据：data/spirits/elements.json
extends Control

signal closed

const PATH := "res://data/spirits/elements.json"
const CENTER := Vector2(430, 460)
const RADIUS := 240.0

var data: Dictionary = {}
var elements: Array = []           # 六元素名
var counters: Array = []           # [{attacker, defender}]
var multiplier: float = 1.3
var pick_first: String = ""        # 连线模式：第一个选中元素
var _dirty: bool = false

var canvas: Control
var hud: Label
var mult_spin: SpinBox
var list_label: Label

## 元素主题色（与六元灵气质对应）
const ELEM_COLOR := {
	"金刚": Color(0.85, 0.75, 0.3),
	"大地": Color(0.7, 0.55, 0.35),
	"雷火": Color(1.0, 0.4, 0.2),
	"冰雪": Color(0.4, 0.8, 1.0),
	"草木": Color(0.3, 0.8, 0.3),
	"梦幻": Color(0.7, 0.5, 0.9),
}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = get_viewport().get_visible_rect().size
	_load_data()
	_build_ui()
	print("[元素编辑器] 已打开：%d 元素 / %d 条克制 / 倍率 %.2f（点击元素A再点元素B=切换A克B）" % [
		elements.size(), counters.size(), multiplier])

func _load_data() -> void:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f:
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			data = parsed
	elements = data.get("elements", [])
	counters = data.get("counters", [])
	multiplier = float(data.get("counter_multiplier", 1.3))

func _save_data() -> void:
	data["counters"] = counters
	data["counter_multiplier"] = multiplier
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_error("[元素编辑器] 无法写入 elements.json")
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	_dirty = false
	print("[元素编辑器] 💾 已保存（重启对局后 DataManager 重新加载生效）")

## ==================== UI ====================

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.position = Vector2.ZERO
	bg.size = get_viewport().get_visible_rect().size
	bg.color = Color(0.07, 0.08, 0.1)
	add_child(bg)

	canvas = Control.new()
	canvas.position = Vector2.ZERO
	canvas.size = Vector2(880, bg.size.y)
	canvas.draw.connect(_on_draw)
	add_child(canvas)

	var title := Label.new()
	title.text = "⚡ 元素克制编辑器（开发者）——  点元素A再点元素B = 切换「A克B」关系"
	title.position = Vector2(12, 8)
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color(1.0, 0.75, 0.4))
	add_child(title)

	# 右侧操作面板
	var px := 910.0
	var lb := Label.new()
	lb.text = "—— 克制倍率 ——"
	lb.position = Vector2(px, 50)
	lb.add_theme_font_size_override("font_size", 15)
	add_child(lb)

	mult_spin = SpinBox.new()
	mult_spin.position = Vector2(px, 78)
	mult_spin.size = Vector2(140, 30)
	mult_spin.min_value = 1.0
	mult_spin.max_value = 3.0
	mult_spin.step = 0.05
	mult_spin.value = multiplier
	add_child(mult_spin)

	var btn_apply_mult := Button.new()
	btn_apply_mult.text = "应用倍率"
	btn_apply_mult.position = Vector2(px + 150, 78)
	btn_apply_mult.size = Vector2(110, 30)
	btn_apply_mult.pressed.connect(func():
		multiplier = float(mult_spin.value)
		_dirty = true
		canvas.queue_redraw())
	add_child(btn_apply_mult)

	list_label = Label.new()
	list_label.position = Vector2(px, 130)
	list_label.add_theme_font_size_override("font_size", 14)
	list_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	add_child(list_label)

	var btn_save := Button.new()
	btn_save.text = "💾 保存到 elements.json"
	btn_save.position = Vector2(px, bg.size.y - 110)
	btn_save.size = Vector2(260, 36)
	btn_save.pressed.connect(_save_data)
	add_child(btn_save)

	var btn_close := Button.new()
	btn_close.text = "← 返回（Esc）"
	btn_close.position = Vector2(px, bg.size.y - 62)
	btn_close.size = Vector2(260, 36)
	btn_close.pressed.connect(_close)
	add_child(btn_close)

	var hint := Label.new()
	hint.text = "克制=伤害×%.2f；连线颜色=攻击方元素色\n环形排列顺序=数据文件顺序" % multiplier
	hint.position = Vector2(px, 350)
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	add_child(hint)

	# 元素节点按钮（环形）
	for i in range(elements.size()):
		var ename := str(elements[i])
		var node := Button.new()
		node.name = "Elem_" + ename
		node.text = ename
		var pos := CENTER + Vector2(cos(TAU * i / elements.size() - PI / 2), sin(TAU * i / elements.size() - PI / 2)) * RADIUS
		node.position = pos - Vector2(52, 30)
		node.size = Vector2(104, 60)
		node.add_theme_font_size_override("font_size", 20)
		var col: Color = ELEM_COLOR.get(ename, Color.WHITE)
		node.add_theme_color_override("font_color", col)
		node.add_theme_color_override("font_hover_color", col.lightened(0.4))
		node.pressed.connect(_on_element_pressed.bind(ename))
		canvas.add_child(node)
	_refresh_list()

func _elem_pos(ename: String) -> Vector2:
	var i := elements.find(ename)
	if i < 0:
		return CENTER
	return CENTER + Vector2(cos(TAU * i / elements.size() - PI / 2), sin(TAU * i / elements.size() - PI / 2)) * RADIUS

func _on_draw() -> void:
	# 克制箭头（攻击方 → 被克方），颜色=攻击方元素色
	for c in counters:
		var a := str(c.get("attacker", ""))
		var d := str(c.get("defender", ""))
		if not elements.has(a) or not elements.has(d):
			continue
		var pa := _elem_pos(a)
		var pd := _elem_pos(d)
		var dir := (pd - pa).normalized()
		var start := pa + dir * 62.0
		var end := pd - dir * 66.0
		var col: Color = ELEM_COLOR.get(a, Color.WHITE)
		col.a = 0.75
		canvas.draw_line(start, end, col, 2.5)
		# 箭头头部
		var head_a := end - dir.rotated(deg_to_rad(25)) * 14.0
		var head_b := end - dir.rotated(deg_to_rad(-25)) * 14.0
		canvas.draw_colored_polygon(PackedVector2Array([end, head_a, head_b]), col)
		# 中点倍率标注
		var mid := (start + end) / 2.0
		canvas.draw_string(ThemeDB.fallback_font, mid + Vector2(-16, -6), "×%.1f" % multiplier, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.5))
	# 连线模式高亮
	if pick_first != "":
		var pf := _elem_pos(pick_first)
		canvas.draw_arc(pf, 44.0, 0, TAU, 40, Color(1, 0.9, 0.4), 3.0)
		canvas.draw_line(get_global_mouse_position(), pf, Color(1, 0.9, 0.4, 0.4), 1.5)

func _on_element_pressed(ename: String) -> void:
	if pick_first == "":
		pick_first = ename
		print("[元素编辑器] 已选 %s——再点一个元素切换「%s 克 它」" % [ename, ename])
	elif pick_first == ename:
		pick_first = ""
	else:
		_toggle_counter(pick_first, ename)
		pick_first = ""
	canvas.queue_redraw()
	_refresh_list()

## 切换 A 克 B：存在则删除，不存在则添加
func _toggle_counter(attacker: String, defender: String) -> void:
	for c in counters:
		if str(c.get("attacker")) == attacker and str(c.get("defender")) == defender:
			counters.erase(c)
			_dirty = true
			print("[元素编辑器] ✂ 移除克制：%s → %s" % [attacker, defender])
			return
	counters.append({"attacker": attacker, "defender": defender})
	_dirty = true
	print("[元素编辑器] ⚔ 新增克制：%s → %s（伤害×%.2f）" % [attacker, defender, multiplier])

func _refresh_list() -> void:
	if list_label == null:
		return
	var lines := ["—— 当前克制关系（%d 条）——" % counters.size()]
	for c in counters:
		var a := str(c.get("attacker", ""))
		var d := str(c.get("defender", ""))
		lines.append("%s 克 %s" % [a, d])
	list_label.text = "\n".join(lines)

func _close() -> void:
	if _dirty:
		print("[元素编辑器] ⚠ 有未保存修改（点保存才会写入 elements.json）")
	closed.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_close()
		elif event.keycode == KEY_S and event.ctrl_pressed:
			_save_data()
