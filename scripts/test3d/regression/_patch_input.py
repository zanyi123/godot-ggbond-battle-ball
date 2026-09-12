# -*- coding: utf-8 -*-
# 编辑器交互重构：画布级拖拽（命中测试）+ 自动适配视图 + 重排/适应按钮
import io, sys

p = 'scripts/dev_tools/dev_talent_tree_editor.gd'
src = io.open(p, encoding='utf-8').read()
fails = []

def rep(old, new, tag):
    global src
    if old not in src:
        fails.append(tag)
        return
    src = src.replace(old, new, 1)

# 1) 打开时自动适配视图（看到全部节点）
rep("""	canvas.draw.connect(_on_canvas_draw)
	canvas.gui_input.connect(_on_canvas_gui_input)
	add_child(canvas)""",
    """	canvas.draw.connect(_on_canvas_draw)
	canvas.gui_input.connect(_on_canvas_gui_input)
	add_child(canvas)""", "noop-canvas")

# 2) _rebuild_canvas 末尾自动适配 + 新按钮（改 _build_ui 顶栏）
rep('''	_add_top_btn("💾 保存树", Vector2(bg.size.x - 300, 6), _on_save)
	_add_top_btn("🔗 连接模式", Vector2(bg.size.x - 180, 6), _on_toggle_link)''',
    '''	_add_top_btn("💾 保存树", Vector2(bg.size.x - 820, 6), _on_save)
	_add_top_btn("🔗 连接模式", Vector2(bg.size.x - 700, 6), _on_toggle_link)
	_add_top_btn("🔁 重排布局", Vector2(bg.size.x - 580, 6), _on_relayout)
	_add_top_btn("⛶ 适应视图", Vector2(bg.size.x - 460, 6), _on_fit_view)''', "topbtns")

# 3) _ready：_auto_layout_missing 后 + _rebuild_canvas 后 fit
rep("""	_load_tree()
	_load_catalogs()
	_build_ui()
	_auto_layout_missing()
	_rebuild_canvas()""",
    """	_load_tree()
	_load_catalogs()
	_build_ui()
	_auto_layout_missing()
	_rebuild_canvas()
	_fit_view()""", "ready fit")

# 4) 重排布局：按方向链式重算所有 pos（丢弃旧拖拽位置）
rep("""func _on_save() -> void:
	save_tree()""",
    """## 一键重排：按方向链式重算所有节点位置（丢弃旧拖拽位置，结构=requires 树）
func _on_relayout() -> void:
	for n in _nodes():
		n.erase("pos")
	_auto_layout_missing()
	_dirty = true
	save_tree()
	_fit_view()
	_rebuild_canvas()
	print("[天赋树编辑器] 🔁 已按结构重排布局")

## 一键适应视图：包围盒全部节点+核心
func _on_fit_view() -> void:
	var min_p := WORLD_CENTER
	var max_p := WORLD_CENTER
	for n in _nodes():
		var wp := _pos_to_vec(n.get("pos", WORLD_CENTER))
		min_p = min_p.min(wp)
		max_p = max_p.max(wp)
	var center := (min_p + max_p) / 2.0
	var span := (max_p - min_p).length() + 400.0
	# 视口约 1110x900（画布区），取适配缩放
	var vs := get_viewport().get_visible_rect().size - Vector2(340, 60)
	zoom = clampf(min(vs.x, vs.y) / max(span, 300.0), ZOOM_MIN, ZOOM_MAX)
	view_pos = center - Vector2(vs.x, vs.y) / 2.0 / zoom + Vector2(0, 0)
	# 居中修正：视口中心对准包围盒中心
	view_pos = center - (Vector2(min(vs.x, 1110.0), min(vs.y, 900.0)) / 2.0) / zoom
	_refresh_card_positions()
	canvas.queue_redraw()
	print("[天赋树编辑器] ⛶ 适应视图 zoom=%.2f center=%s" % [zoom, str(center)])


func _on_save() -> void:
	save_tree()""", "relayout+fit")

# 5) 交互重构：_on_canvas_gui_input 统一处理左键节点拖拽（命中测试）+ 平移
rep("""## 画布：中键/右键拖动平移，滚轮缩放（以鼠标为中心）
func _on_canvas_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_apply_zoom(mb.position, 1.1)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_apply_zoom(mb.position, 1.0 / 1.1)
		elif mb.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_panning = mb.pressed
			_pan_start = mb.get_global_position()
			_view_start = view_pos
	elif event is InputEventMouseMotion and _panning:
		var mm := event as InputEventMouseMotion
		view_pos = _view_start - (mm.get_global_position() - _pan_start) / zoom
		_refresh_card_positions()
		canvas.queue_redraw()""",
    """## 画布统一输入：左键=命中测试拖节点；中/右键=平移；滚轮=缩放
func _on_canvas_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var hit := _hit_test_card(mb.position)
				if hit != null:
					_drag_card = hit
					_drag_offset = hit.position - mb.position  # 屏幕系 offset
					# 选中
					var id := hit.name.trim_prefix("Card_")
					selected_id = id
					_fill_prop_panel(_node_by_id(id))
					canvas.queue_redraw()
			else:
				if _drag_card != null:
					_save_card_pos(_drag_card)
				_drag_card = null
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_apply_zoom(mb.position, 1.1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_apply_zoom(mb.position, 1.0 / 1.1)
		elif mb.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_panning = mb.pressed
			_pan_start = mb.get_global_position()
			_view_start = view_pos
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag_card != null:
			_drag_card.position = mm.get_global_position() - _drag_offset
			_save_card_pos(_drag_card)
			canvas.queue_redraw()
		elif _panning:
			view_pos = _view_start - (mm.get_global_position() - _pan_start) / zoom
			_refresh_card_positions()
			canvas.queue_redraw()

## 屏幕点 → 最上层命中卡片
func _hit_test_card(screen_pos: Vector2) -> Button:
	var found: Button = null
	for c in canvas.get_children():
		if c is Button and c.visible:
			var b := c as Button
			if screen_pos >= b.position and screen_pos <= b.position + b.size * zoom:
				found = b  # 不 break：取最后（最上层）
	return found""", "unified input")

# 6) 删卡片级拖拽处理（保留 pressed 选择）；card gui_input 不再需要
rep("""	card.gui_input.connect(_on_card_input.bind(card))
	card.pressed.connect(_on_card_pressed.bind(n, card))""",
    """	card.pressed.connect(_on_card_pressed.bind(n, card))""", "no card input")

# 删 _on_card_input 整函数
start = src.index("func _on_card_input(event: InputEvent, card: Button) -> void:")
end = src.index("func _save_card_pos(card: Button) -> void:")
src = src[:start] + src[end:]

io.open(p, 'w', encoding='utf-8', newline='\n').write(src)
if fails:
    print("FAIL:", fails)
    sys.exit(1)
print("交互重构成功")
