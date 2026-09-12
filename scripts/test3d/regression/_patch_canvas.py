# -*- coding: utf-8 -*-
# 大画布+平移缩放补丁（原子应用，全部锚点验证）
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

# 1) 常量块（CENTER/STEP 可能带注释行，用宽松锚：替换 const 两行）
rep("const CENTER := Vector2(520, 440)",
    "## 世界坐标（天赋点坐标空间，可远超屏幕）；view_pos=视口左上角在世界坐标中的位置\n"
    "const WORLD_CENTER := Vector2(1400, 1000)\n"
    "const ZOOM_MIN := 0.4\n"
    "const ZOOM_MAX := 1.6\n"
    "var view_pos := Vector2(450, 330)\n"
    "var zoom := 1.0\n"
    "var _panning := false\n"
    "var _pan_start := Vector2.ZERO\n"
    "var _view_start := Vector2.ZERO\n"
    "const CENTER := Vector2(520, 440)  # 兼容旧引用（将由 WORLD_CENTER 取代）", "constants")

# 2) 相机换算函数（挂在 _pos_to_vec 前）
rep("## JSON pos → Vector2（统一入口）",
    "## 世界 → 屏幕（画布内）\n"
    "func world_to_screen(wp: Vector2) -> Vector2:\n"
    "\treturn (wp - view_pos) * zoom\n\n"
    "## 屏幕（画布内）→ 世界\n"
    "func screen_to_world(sp: Vector2) -> Vector2:\n"
    "\treturn sp / zoom + view_pos\n\n"
    "## JSON pos → Vector2（统一入口）", "camera fns")

# 3) 全部 CENTER 数据引用 → WORLD_CENTER（保留 compat 常量行本身）
src = src.replace('n.get("pos", CENTER)', 'n.get("pos", WORLD_CENTER)')
src = src.replace('parent.get("pos", CENTER)', 'parent.get("pos", WORLD_CENTER)')
src = src.replace('.get("pos", CENTER))', '.get("pos", WORLD_CENTER))')
src = src.replace('parent_pos = CENTER\n', 'parent_pos = WORLD_CENTER\n')
src = src.replace('node["pos"] = CENTER + dirv * STEP', 'node["pos"] = WORLD_CENTER + dirv * STEP')
src = src.replace('\treturn CENTER', '\treturn WORLD_CENTER')

# 4) canvas 全屏 + 输入接线
rep("""	canvas = Control.new()
	canvas.name = "Canvas"
	canvas.position = Vector2.ZERO
	canvas.size = Vector2(bg.size.x - 330, bg.size.y)
	canvas.draw.connect(_on_canvas_draw)
	add_child(canvas)""",
    """	canvas = Control.new()
	canvas.name = "Canvas"
	canvas.position = Vector2.ZERO
	canvas.size = bg.size  # 全屏画布（右侧面板浮层）
	canvas.draw.connect(_on_canvas_draw)
	canvas.gui_input.connect(_on_canvas_gui_input)
	add_child(canvas)""", "canvas full")

rep('_add_top_btn("💾 保存树", Vector2(canvas.size.x - 300, 6), _on_save)\n\t_add_top_btn("🔗 连接模式", Vector2(canvas.size.x - 180, 6), _on_toggle_link)',
    '_add_top_btn("💾 保存树", Vector2(bg.size.x - 300, 6), _on_save)\n\t_add_top_btn("🔗 连接模式", Vector2(bg.size.x - 180, 6), _on_toggle_link)', "topbtns")

rep('prop_scroll.position = Vector2(canvas.size.x + 4, 40)', 'prop_scroll.position = Vector2(bg.size.x - 326, 40)', "panel pos")

# 5) 卡片：世界→屏幕 + 缩放
rep("""	card.position = _pos_to_vec(n.get("pos", WORLD_CENTER))
	card.size = CARD_SIZE""",
    """	card.position = world_to_screen(_pos_to_vec(n.get("pos", WORLD_CENTER)))
	card.size = CARD_SIZE
	card.scale = Vector2(zoom, zoom)
	card.pivot_offset = CARD_SIZE / 2.0""", "card transform")

# 6) 拖拽保存世界坐标
rep("""	if not n.is_empty():
		n["pos"] = card.position
		_dirty = true""",
    """	if not n.is_empty():
		n["pos"] = screen_to_world(card.position)
		_dirty = true""", "drag save")

# 7) 画布平移/缩放输入（挂在 _on_card_input 前）
rep("func _on_card_input(event: InputEvent, card: Button) -> void:",
    """## 画布：中键/右键拖动平移，滚轮缩放（以鼠标为中心）
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
		canvas.queue_redraw()

func _apply_zoom(at_screen: Vector2, factor: float) -> void:
	var world_at := screen_to_world(at_screen)
	zoom = clampf(zoom * factor, ZOOM_MIN, ZOOM_MAX)
	view_pos = world_at - at_screen / zoom
	_refresh_card_positions()
	canvas.queue_redraw()

## 视口变化后重排卡片（世界→屏幕）
func _refresh_card_positions() -> void:
	for n in _nodes():
		var card := canvas.get_node_or_null(NodePath("Card_" + str(n.get("id"))))
		if card != null:
			card.position = world_to_screen(_pos_to_vec(n.get("pos", WORLD_CENTER)))
			card.scale = Vector2(zoom, zoom)

func _on_card_input(event: InputEvent, card: Button) -> void:""", "canvas input")

# 8) draw 里方向大字/圆心用屏幕坐标换算（画布 draw 以屏幕为系：把引导线端点换算）
rep("""	# 中心核心
	canvas.draw_circle(CENTER, 12.0, Color(1, 0.95, 0.6))
	canvas.draw_string(ThemeDB.fallback_font, CENTER + Vector2(-14, 28), "核心", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.95, 0.6))
	# 四方向引导线
	for d in DIR_VEC:
		canvas.draw_line(CENTER, CENTER + DIR_VEC[d] * STEP * 1.2, Color(1, 1, 1, 0.12), 2.0)""",
    """	# 中心核心（世界→屏幕）
	var core_s := world_to_screen(WORLD_CENTER)
	canvas.draw_circle(core_s, 12.0 * zoom, Color(1, 0.95, 0.6))
	canvas.draw_string(ThemeDB.fallback_font, core_s + Vector2(-14, 28), "核心", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.95, 0.6))
	# 四方向引导线
	for d in DIR_VEC:
		canvas.draw_line(core_s, core_s + DIR_VEC[d] * STEP * 1.2 * zoom, Color(1, 1, 1, 0.12), 2.0)""", "draw core")

# 连线端点换算
rep("""			var a: Vector2 = _card_center(parent_card)
			var b: Vector2 = _card_center(child_card)""",
    """			var a: Vector2 = _card_center(parent_card)
			var b: Vector2 = _card_center(child_card)""", "lines keep")

# 选中高亮框不变（卡片已是屏幕坐标）
# 9) 连线/高亮用卡片中心（已是屏幕系）——无需改
# 10) 方向水印大字保持屏幕固定（不随世界移动，装饰性）——保持

io.open(p, 'w', encoding='utf-8', newline='\n').write(src)
if fails:
    print("FAIL:", fails)
    sys.exit(1)
print("全部锚点应用成功")
