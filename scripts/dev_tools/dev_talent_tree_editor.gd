## 开发者天赋树编辑器（dev_tools · 2026-09-11）
## 功能：四方向十字布局（进攻→右 / 生存→上 / 防御→左 / 增益→下）
##   · 节点卡片直接拖拽摆位（pos 存入 tree.json）
##   · 新增天赋点（名称/描述/cost/类型/事件/标签参数）
##   · 连接模式：点父节点 → 点子节点 → 建立线性前置链（requires）
##   · 属性编辑：选中节点改名称/描述/cost；删除节点
##   · 保存：写回 tree.json（含 pos 布局，玩家侧读取兼容）
## 入口：主菜单 管理员模式 → 天赋树编辑器（开发者）
extends Control

signal closed

const TREE_PATH := "res://data/systems/talent_tree/tree.json"
## 世界坐标（天赋点坐标空间，可远超屏幕）；view_pos=视口左上角在世界坐标中的位置
const WORLD_CENTER := Vector2(1400, 1000)
const ZOOM_MIN := 0.4
const ZOOM_MAX := 1.6
var view_pos := Vector2(845, 550)  ## 默认对准世界核心（打开即见四方向主干）
var zoom := 1.0
var _panning := false
var _pan_start := Vector2.ZERO
var _view_start := Vector2.ZERO
const CENTER := Vector2(520, 440)  # 兼容旧引用（将由 WORLD_CENTER 取代）
const STEP := 175.0
const CARD_SIZE := Vector2(132, 56)
const DIR_VEC := {
	"进攻": Vector2(1, 0),
	"防御": Vector2(-1, 0),
	"生存": Vector2(0, -1),
	"增益": Vector2(0, 1),
}
const DIR_COLOR := {
	"进攻": Color(0.95, 0.45, 0.35),
	"防御": Color(0.45, 0.65, 0.95),
	"生存": Color(0.4, 0.85, 0.5),
	"增益": Color(0.85, 0.6, 0.95),
}

var tree_data: Dictionary = {}
var selected_id: String = ""
var link_mode: bool = false
var link_parent: String = ""
var _drag_card: Button = null
var _drag_offset: Vector2 = Vector2.ZERO
var _dirty: bool = false

var canvas: Control
var prop_scroll: ScrollContainer
var prop_box: VBoxContainer
var hud_label: Label

## 属性面板输入控件（中文快速上手版）
var inp_name: LineEdit
var inp_desc: TextEdit
var inp_cost: SpinBox
var inp_dir: OptionButton
var inp_type: OptionButton
var inp_event: OptionButton          ## 触发事件（中文分组下拉）
var inp_cooldown: SpinBox
var inp_energy: SpinBox
var inp_skill: OptionButton          ## 解锁技能（中文名下拉）
var _effect_rows: VBoxContainer      ## 效果标签动态行容器
var _effect_inputs: Array = []       ## [{opt, val, dur}]
var _tag_catalog: Array = []         ## [{id, name}] 来自 tags_registry
var _audit_status: Dictionary = {}   ## {tag_id: {name, verdict}} E6 审计结果
var _skill_catalog: Array = []       ## [{id, name}] 来自 skills.json
var _node_id_label: Label

## 事件下拉选项（大类·中文 → 枚举名）
const EVENT_OPTIONS := [
	{"label": "── 受击类 ──", "name": ""},
	{"label": "球命中受击", "name": "Hit.HIT_TAKEN"},
	{"label": "克制命中（联动元素克制）", "name": "Hit.HIT_COUNTER"},
	{"label": "韧性判定完成", "name": "Hit.HIT_RESILIENCE_ROLLED"},
	{"label": "球员被击倒", "name": "Hit.HIT_DEFEATED"},
	{"label": "── 攻击类 ──", "name": ""},
	{"label": "发球出手", "name": "Attack.LAUNCHED"},
	{"label": "── 接球防御类 ──", "name": ""},
	{"label": "进入待接球", "name": "Defend.CATCH_STANCE"},
	{"label": "接住来球（夺球权）", "name": "Defend.CAUGHT"},
	{"label": "韧性弹飞来球", "name": "Defend.BOUNCED"},
	{"label": "── 资源类 ──", "name": ""},
	{"label": "技能冷却结束", "name": "Resource.COOLDOWN_READY"},
	{"label": "体力跨过阈值", "name": "Resource.STAMINA_THRESHOLD"},
	{"label": "能量跨过阈值", "name": "Resource.ENERGY_THRESHOLD"},
]

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = get_viewport().get_visible_rect().size
	_load_tree()
	_load_catalogs()
	_build_ui()
	_auto_layout_missing()
	_rebuild_canvas()
	_on_fit_view()
	print("[天赋树编辑器] 已打开，节点 %d 个（拖拽摆位 / 新增 / 连接模式 / 保存）" % _nodes().size())

## ==================== 数据 ====================

## 加载标签/技能中文名目录（下拉快速选择，免手打英文 id）
## 加载 tag 审计状态（E6 报告产物，下拉标注 ✅/⚠/❌ 防静默无效）
func _load_audit_status() -> void:
	_audit_status.clear()
	var f := FileAccess.open("res://docs/tag_audit_status.json", FileAccess.READ)
	if f:
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			_audit_status = parsed

func _load_catalogs() -> void:
	_load_audit_status()
	_tag_catalog.clear()
	var f := FileAccess.open("res://data/spirits/tags_registry.json", FileAccess.READ)
	if f:
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary and parsed.has("tags"):
			for t in parsed["tags"]:
				_tag_catalog.append({"id": str(t.get("id", "")), "name": str(t.get("name", ""))})
	_skill_catalog.clear()
	var f2 := FileAccess.open("res://data/spirits/skills.json", FileAccess.READ)
	if f2:
		var parsed2 = JSON.parse_string(f2.get_as_text())
		f2.close()
		if parsed2 is Dictionary and parsed2.has("skills"):
			for s in parsed2["skills"]:
				_skill_catalog.append({"id": str(s.get("id", "")), "name": str(s.get("name", ""))})

func _load_tree() -> void:
	if FileAccess.file_exists(TREE_PATH):
		var f := FileAccess.open(TREE_PATH, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text()) if f else null
		if f:
			f.close()
		if parsed is Dictionary:
			tree_data = parsed
	if tree_data.is_empty():
		tree_data = {"points_total": 6, "directions": DIR_VEC.keys(), "nodes": []}

func _nodes() -> Array:
	return tree_data.get("nodes", [])

func _node_by_id(id: String) -> Dictionary:
	for n in _nodes():
		if str(n.get("id")) == id:
			return n
	return {}

func save_tree() -> void:
	var f := FileAccess.open(TREE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[天赋树编辑器] 无法写入 tree.json")
		return
	f.store_string(JSON.stringify(tree_data, "\t"))
	f.close()
	_dirty = false
	print("[天赋树编辑器] 💾 已保存 tree.json（%d 节点）" % _nodes().size())

## 世界 → 屏幕（画布内）
func world_to_screen(wp: Vector2) -> Vector2:
	return (wp - view_pos) * zoom

## 屏幕（画布内）→ 世界
func screen_to_world(sp: Vector2) -> Vector2:
	return sp / zoom + view_pos

## JSON pos → Vector2（统一入口）
## 三种形态：Vector2（本会话内存）/ Array [x,y] / String "(x, y)"（JSON.stringify 序列化 Vector2 的产物）
func _pos_to_vec(v) -> Vector2:
	if v is Vector2:
		return v
	if v is Array and v.size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	if v is String:
		var s: String = (v as String).trim_prefix("(").trim_suffix(")")
		var parts: PackedStringArray = s.split(",")
		if parts.size() >= 2:
			return Vector2(float(parts[0]), float(parts[1]))
	return WORLD_CENTER

## 首次无 pos 的节点自动布局：沿方向向量链式延伸
func _auto_layout_missing() -> void:
	var placed := {}
	for n in _nodes():
		if n.get("pos") != null:
			placed[str(n.get("id"))] = true
	# 父优先迭代放置
	var rounds := 0
	while rounds < 8:
		rounds += 1
		var progressed := false
		for n in _nodes():
			var id := str(n.get("id"))
			if placed.has(id):
				continue
			var reqs: Array = n.get("requires", [])
			var parent_pos: Variant = null
			if reqs.is_empty():
				parent_pos = WORLD_CENTER
			elif placed.has(str(reqs[0])):
				parent_pos = _pos_to_vec(_node_by_id(str(reqs[0])).get("pos", WORLD_CENTER))
			if parent_pos == null:
				continue  # 父还没放，下一轮
			var dir: Vector2 = DIR_VEC.get(str(n.get("direction", "进攻")), Vector2(1, 0))
			n["pos"] = parent_pos + dir * STEP
			placed[id] = true
			progressed = true
		if progressed == false:
			break

## ==================== UI 构建 ====================

func _build_ui() -> void:
	# 背景
	var bg := ColorRect.new()
	bg.position = Vector2.ZERO
	bg.size = get_viewport().get_visible_rect().size
	bg.color = Color(0.07, 0.08, 0.1)
	add_child(bg)

	# 画布（连线绘制 + 节点卡片容器）
	canvas = Control.new()
	canvas.name = "Canvas"
	canvas.position = Vector2.ZERO
	canvas.size = bg.size  # 全屏画布（右侧面板浮层）
	canvas.draw.connect(_on_canvas_draw)
	add_child(canvas)

	# 顶栏
	var title := Label.new()
	title.text = "🌿 天赋树编辑器（开发者）——  拖拽摆位 | 连接模式建前置链 | 右侧编辑属性"
	title.position = Vector2(12, 8)
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color(0.7, 0.9, 0.6))
	add_child(title)

	_add_top_btn("💾 保存树", Vector2(bg.size.x - 820, 6), _on_save)
	_add_top_btn("🔗 连接模式", Vector2(bg.size.x - 700, 6), _on_toggle_link)
	_add_top_btn("🔁 重排布局", Vector2(bg.size.x - 580, 6), _on_relayout)
	_add_top_btn("⛶ 适应视图", Vector2(bg.size.x - 460, 6), _on_fit_view)

	# 右侧属性面板
	prop_scroll = ScrollContainer.new()
	prop_scroll.position = Vector2(bg.size.x - 326, 40)
	prop_scroll.size = Vector2(322, bg.size.y - 50)
	add_child(prop_scroll)
	prop_box = VBoxContainer.new()
	prop_box.custom_minimum_size = Vector2(300, 0)
	prop_scroll.add_child(prop_box)
	_build_prop_panel()

	hud_label = Label.new()
	hud_label.position = Vector2(12, 36)
	hud_label.add_theme_font_size_override("font_size", 14)
	hud_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.7))
	add_child(hud_label)

func _add_top_btn(text: String, pos: Vector2, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = Vector2(112, 30)
	b.pressed.connect(fn)
	add_child(b)
	return b

func _mk_field(parent: Control, label: String, y: float, wide: float = 260.0) -> LineEdit:
	var lb := Label.new()
	lb.text = label
	lb.position = Vector2(8, y)
	lb.add_theme_font_size_override("font_size", 13)
	parent.add_child(lb)
	var le := LineEdit.new()
	le.position = Vector2(8, y + 20)
	le.size = Vector2(wide, 26)
	parent.add_child(le)
	return le

func _mk_spin(parent: Control, label: String, y: float, mn: float, mx: float, val: float) -> SpinBox:
	var lb := Label.new()
	lb.text = label
	lb.position = Vector2(8, y)
	lb.add_theme_font_size_override("font_size", 13)
	parent.add_child(lb)
	var sb := SpinBox.new()
	sb.position = Vector2(8, y + 20)
	sb.size = Vector2(120, 26)
	sb.min_value = mn
	sb.max_value = mx
	sb.step = 0.5
	sb.value = val
	parent.add_child(sb)
	return sb

func _build_prop_panel() -> void:
	var y := 0.0
	var lb := Label.new()
	lb.text = "—— 节点属性 ——"
	lb.position = Vector2(8, y)
	lb.add_theme_font_size_override("font_size", 15)
	prop_box.add_child(lb)
	y += 28

	_node_id_label = Label.new()
	_node_id_label.text = "（未选中节点）"
	_node_id_label.position = Vector2(8, y)
	_node_id_label.add_theme_font_size_override("font_size", 12)
	_node_id_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	prop_box.add_child(_node_id_label)
	y += 24

	inp_name = _mk_field(prop_box, "名称", y); y += 52

	var lb_desc := Label.new()
	lb_desc.text = "描述（玩家可见的说明文字）"
	lb_desc.position = Vector2(8, y)
	lb_desc.add_theme_font_size_override("font_size", 13)
	prop_box.add_child(lb_desc)
	inp_desc = TextEdit.new()
	inp_desc.position = Vector2(8, y + 20)
	inp_desc.size = Vector2(285, 66)
	inp_desc.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	prop_box.add_child(inp_desc)
	y += 92

	var lb_dir := Label.new()
	lb_dir.text = "方向（决定自动布局朝向）"
	lb_dir.position = Vector2(8, y)
	lb_dir.add_theme_font_size_override("font_size", 13)
	prop_box.add_child(lb_dir)
	inp_dir = OptionButton.new()
	inp_dir.position = Vector2(8, y + 20)
	inp_dir.size = Vector2(140, 26)
	for d in DIR_VEC.keys():
		inp_dir.add_item(str(d))
	prop_box.add_child(inp_dir)
	y += 56

	inp_cost = _mk_spin(prop_box, "点数消耗", y, 0, 6, 1); y += 52

	var lb_type := Label.new()
	lb_type.text = "类型"
	lb_type.position = Vector2(8, y)
	lb_type.add_theme_font_size_override("font_size", 13)
	prop_box.add_child(lb_type)
	inp_type = OptionButton.new()
	inp_type.position = Vector2(8, y + 20)
	inp_type.size = Vector2(140, 26)
	inp_type.item_selected.connect(func(_i): _refresh_type_visibility())
	for t in [["stat", "数值型（常驻加成）"], ["event", "事件触发型"], ["manual", "手动技能型"]]:
		inp_type.add_item(t[1])
		inp_type.set_item_metadata(inp_type.item_count - 1, t[0])
	prop_box.add_child(inp_type)
	y += 56

	var lb_ev := Label.new()
	lb_ev.text = "── 事件触发 ──"
	lb_ev.position = Vector2(8, y)
	lb_ev.add_theme_font_size_override("font_size", 13)
	lb_ev.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	prop_box.add_child(lb_ev)
	y += 24

	var lb_evd := Label.new()
	lb_evd.text = "触发事件"
	lb_evd.position = Vector2(8, y)
	lb_evd.add_theme_font_size_override("font_size", 13)
	prop_box.add_child(lb_evd)
	inp_event = OptionButton.new()
	inp_event.position = Vector2(8, y + 18)
	inp_event.size = Vector2(280, 28)
	for opt in EVENT_OPTIONS:
		if opt["name"] == "":
			inp_event.add_separator()
		else:
			inp_event.add_item(opt["label"])
			inp_event.set_item_metadata(inp_event.item_count - 1, opt["name"])
	prop_box.add_child(inp_event)
	y += 54

	inp_cooldown = _mk_spin(prop_box, "内冷却（秒）", y, 0, 120, 10); y += 52
	inp_energy = _mk_spin(prop_box, "耗能", y, 0, 100, 0); y += 52

	var lb_tag := Label.new()
	lb_tag.text = "── 效果标签（可多条）──"
	lb_tag.position = Vector2(8, y)
	lb_tag.add_theme_font_size_override("font_size", 13)
	lb_tag.add_theme_color_override("font_color", Color(0.9, 0.75, 0.4))
	prop_box.add_child(lb_tag)
	y += 24

	_effect_rows = VBoxContainer.new()
	prop_box.add_child(_effect_rows)
	y += 8

	var btn_add_tag := Button.new()
	btn_add_tag.text = "＋ 添加效果标签"
	btn_add_tag.position = Vector2(8, y)
	btn_add_tag.size = Vector2(200, 28)
	btn_add_tag.pressed.connect(func(): _add_effect_row("player_atk_up_flat", 10.0, 5.0))
	prop_box.add_child(btn_add_tag)
	y += 40

	var lb_sk := Label.new()
	lb_sk.text = "── 手动技能型 ──"
	lb_sk.position = Vector2(8, y)
	lb_sk.add_theme_font_size_override("font_size", 13)
	lb_sk.add_theme_color_override("font_color", Color(0.9, 0.75, 0.4))
	prop_box.add_child(lb_sk)
	y += 24

	var lb_skl := Label.new()
	lb_skl.text = "解锁技能"
	lb_skl.position = Vector2(8, y)
	lb_skl.add_theme_font_size_override("font_size", 13)
	prop_box.add_child(lb_skl)
	inp_skill = OptionButton.new()
	inp_skill.position = Vector2(8, y + 18)
	inp_skill.size = Vector2(280, 28)
	for s in _skill_catalog:
		inp_skill.add_item("%s（%s）" % [s["name"], s["id"]])
		inp_skill.set_item_metadata(inp_skill.item_count - 1, s["id"])
	prop_box.add_child(inp_skill)
	y += 54

	var btn_apply := Button.new()
	btn_apply.text = "✔ 应用修改到选中节点"
	btn_apply.position = Vector2(8, y)
	btn_apply.size = Vector2(280, 36)
	btn_apply.pressed.connect(_on_apply_edit)
	prop_box.add_child(btn_apply)
	y += 44

	var btn_del := Button.new()
	btn_del.text = "🗑 删除选中节点"
	btn_del.position = Vector2(8, y)
	btn_del.size = Vector2(280, 30)
	btn_del.pressed.connect(_on_delete_selected)
	prop_box.add_child(btn_del)
	y += 40

	var lb_new := Label.new()
	lb_new.text = "—— 新增天赋点 ——"
	lb_new.position = Vector2(8, y)
	lb_new.add_theme_font_size_override("font_size", 15)
	prop_box.add_child(lb_new)
	y += 30

	var btn_new := Button.new()
	btn_new.text = "➕ 在选中节点后方新增（线性延伸）"
	btn_new.position = Vector2(8, y)
	btn_new.size = Vector2(290, 34)
	btn_new.pressed.connect(_on_new_after_selected)
	prop_box.add_child(btn_new)
	y += 42
	var btn_new_root := Button.new()
	btn_new_root.text = "➕ 在四方向根部新增"
	btn_new_root.position = Vector2(8, y)
	btn_new_root.size = Vector2(290, 30)
	btn_new_root.pressed.connect(_on_new_root)
	prop_box.add_child(btn_new_root)
	y += 40

	var hint := Label.new()
	hint.text = "提示：新增读取上方全部字段；线性延伸\n=新节点以选中节点为前置，继承方向"
	hint.position = Vector2(8, y)
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	prop_box.add_child(hint)

	_refresh_type_visibility()

## 类型切换显隐提示（首期：事件触发型/手动型字段并列展示）
func _refresh_type_visibility() -> void:
	pass

## 添加一条效果标签行（中文标签下拉 + 数值 + 时长 + 删除）
func _add_effect_row(tag_id: String, val: float, dur: float) -> void:
	var row := HBoxContainer.new()
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.custom_minimum_size = Vector2(150, 26)
	var mark := ""
	for t in _tag_catalog:
		var st := str(_audit_status.get(t["id"], {}).get("verdict", ""))
		match st:
			"OK": mark = "✅ "
			"WARN": mark = "⚠ "
			"FAIL": mark = "❌ "
			_: mark = ""
		opt.add_item(mark + t["name"])
		opt.set_item_metadata(opt.item_count - 1, t["id"])
	for i in range(opt.item_count):
		if str(opt.get_item_metadata(i)) == tag_id:
			opt.select(i)
			break
	row.add_child(opt)
	var val_sb := SpinBox.new()
	val_sb.min_value = -200
	val_sb.max_value = 200
	val_sb.step = 1.0
	val_sb.value = val
	val_sb.custom_minimum_size = Vector2(64, 26)
	val_sb.tooltip_text = "数值"
	row.add_child(val_sb)
	var dur_sb := SpinBox.new()
	dur_sb.min_value = 0
	dur_sb.max_value = 60
	dur_sb.step = 0.5
	dur_sb.value = dur
	dur_sb.custom_minimum_size = Vector2(60, 26)
	dur_sb.tooltip_text = "时长(秒)"
	row.add_child(dur_sb)
	var del := Button.new()
	del.text = "×"
	del.custom_minimum_size = Vector2(26, 26)
	del.pressed.connect(func():
		_effect_inputs.erase({"opt": opt, "val": val_sb, "dur": dur_sb})
		row.queue_free())
	row.add_child(del)
	_effect_rows.add_child(row)
	_effect_inputs.append({"opt": opt, "val": val_sb, "dur": dur_sb})

## 收集效果标签行 → node 字段
func _collect_effect_rows(n: Dictionary) -> void:
	var ids: Array = []
	var tp: Dictionary = {}
	for row in _effect_inputs:
		var tid := str(row["opt"].get_selected_metadata())
		if tid == "":
			continue
		ids.append(tid)
		tp[tid] = {"duration": float(row["dur"].value), "value": float(row["val"].value)}
	if ids.size() > 0:
		n["tags"] = ids
		n["tag_params"] = tp

## 回填效果标签行
func _fill_effect_rows(n: Dictionary) -> void:
	for c in _effect_rows.get_children():
		c.queue_free()
	_effect_inputs.clear()
	var ids: Array = n.get("tags", [])
	var tp: Dictionary = n.get("tag_params", {})
	for tid in ids:
		var tid_s := str(tid)
		var d: Dictionary = tp.get(tid_s, {}) if tp.has(tid_s) else {}
		_add_effect_row(tid_s, float(d.get("value", 10.0)), float(d.get("duration", 5.0)))

## 事件枚举名 → 下拉索引
func _event_enum_to_index(enum_name: String) -> int:
	for i in range(inp_event.item_count):
		if str(inp_event.get_item_metadata(i)) == enum_name:
			return i
	return -1

## 技能 id → 下拉索引
func _skill_id_to_index(skill_id: String) -> int:
	for i in range(inp_skill.item_count):
		if str(inp_skill.get_item_metadata(i)) == skill_id:
			return i
	return -1

## ==================== 画布与节点卡片 ====================

func _rebuild_canvas() -> void:
	for c in canvas.get_children():
		c.queue_free()
	canvas.queue_redraw()
	for n in _nodes():
		_make_card(n)
	_update_hud()

func _make_card(n: Dictionary) -> void:
	var id := str(n.get("id"))
	var dir := str(n.get("direction", "进攻"))
	var card := Button.new()
	card.name = "Card_" + id
	card.text = "%s\n%s (cost %d)" % [str(n.get("name", id)), id, int(n.get("cost", 1))]
	card.position = world_to_screen(_pos_to_vec(n.get("pos", WORLD_CENTER)))
	card.size = CARD_SIZE
	card.scale = Vector2(zoom, zoom)
	card.pivot_offset = CARD_SIZE / 2.0
	card.add_theme_font_size_override("font_size", 12)
	var col: Color = DIR_COLOR.get(dir, Color.WHITE)
	card.add_theme_color_override("font_color", col)
	card.add_theme_color_override("font_hover_color", col.lightened(0.3))
	card.tooltip_text = "%s\n%s\ntype=%s" % [str(n.get("name", "")), str(n.get("desc", "")), str(n.get("type", ""))]
	card.pressed.connect(_on_card_pressed.bind(n, card))
	canvas.add_child(card)
	# 方向色条（顶部小色块）
	var strip := ColorRect.new()
	strip.position = Vector2(0, 0)
	strip.size = Vector2(CARD_SIZE.x, 4)
	strip.color = col
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(strip)

func _card_center(card: Button) -> Vector2:
	return card.position + CARD_SIZE / 2.0

func _on_canvas_draw() -> void:
	# 中心核心（世界→屏幕）
	var core_s := world_to_screen(WORLD_CENTER)
	canvas.draw_circle(core_s, 12.0 * zoom, Color(1, 0.95, 0.6))
	canvas.draw_string(ThemeDB.fallback_font, core_s + Vector2(-14, 28), "核心", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.95, 0.6))
	# 四方向引导线
	for d in DIR_VEC:
		canvas.draw_line(core_s, core_s + DIR_VEC[d] * STEP * 1.2 * zoom, Color(1, 1, 1, 0.12), 2.0)
	# 四方向大号淡显字（世界层：随平移/缩放整体移动；锚点=该方向根部外侧）
	var anchors := {
		"生存": WORLD_CENTER + Vector2(0, -STEP * 2.6),
		"增益": WORLD_CENTER + Vector2(0, STEP * 3.4),
		"防御": WORLD_CENTER + Vector2(-STEP * 2.9, 0),
		"进攻": WORLD_CENTER + Vector2(STEP * 2.9, 0),
	}
	for d in anchors:
		var sp := world_to_screen(anchors[d])
		var fs := int(64 * zoom)
		if fs < 8:
			continue
		var col: Color = DIR_COLOR.get(d, Color.WHITE)
		col.a = 0.16
		canvas.draw_string(ThemeDB.fallback_font, sp - Vector2(fs, -fs * 0.8), d, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	# 前置连线（线性延伸）
	for n in _nodes():
		var child_id := str(n.get("id"))
		var child_card := canvas.get_node_or_null(NodePath("Card_" + child_id))
		if child_card == null:
			continue
		for req in n.get("requires", []):
			var parent_card := canvas.get_node_or_null(NodePath("Card_" + str(req)))
			if parent_card == null:
				continue
			var a: Vector2 = _card_center(parent_card)
			var b: Vector2 = _card_center(child_card)
			var is_link_src: bool = link_mode and link_parent == str(req) and selected_id == child_id
			var col := Color(0.35, 0.9, 0.5, 0.9) if is_link_src else Color(0.6, 0.8, 1.0, 0.5)
			canvas.draw_line(a, b, col, 3.0 if is_link_src else 1.6)
			# 箭头（子端小圆点）
			canvas.draw_circle(b, 3.5, col)
	# 选中高亮框
	if selected_id != "":
		var sc := canvas.get_node_or_null(NodePath("Card_" + selected_id))
		if sc != null:
			canvas.draw_rect(Rect2(sc.position - Vector2(4, 4), sc.size + Vector2(8, 8)), Color(1, 0.9, 0.4), false, 2.0)

func _update_hud() -> void:
	if hud_label == null:
		return
	if link_mode:
		hud_label.text = "🔗 连接模式：已选父节点 [%s] —— 点击子节点建立前置链（Esc 取消）" % link_parent
	else:
		var n := _node_by_id(selected_id)
		hud_label.text = "选中: %s（%s）" % [selected_id, str(n.get("name", ""))] if selected_id != "" else "未选中节点"

## ==================== 交互 ====================

## 屏幕点 → 最上层命中卡片
func _hit_test_card(screen_pos: Vector2) -> Button:
	var found: Button = null
	for c in canvas.get_children():
		if c is Button and c.visible:
			var b := c as Button
			if screen_pos >= b.position and screen_pos <= b.position + b.size * zoom:
				found = b  # 取最后=最上层
	return found

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

func _save_card_pos(card: Button) -> void:
	var id := card.name.trim_prefix("Card_")
	var n := _node_by_id(id)
	if not n.is_empty():
		n["pos"] = screen_to_world(card.position)
		_dirty = true

func _on_card_pressed(n: Dictionary, card: Button) -> void:
	if link_mode:
		# 连接模式：当前选中节点为父，点中的为子 → requires 建立
		if selected_id != "" and selected_id != str(n.get("id")):
			var parent_id := selected_id
			var reqs: Array = n.get("requires", [])
			if not parent_id in reqs:
				reqs.append(parent_id)
				n["requires"] = reqs
				_dirty = true
				print("[天赋树编辑器] 前置链: %s → %s" % [parent_id, str(n.get("id"))])
		link_mode = false
		link_parent = ""
		_rebuild_canvas()
		return
	selected_id = str(n.get("id"))
	_fill_prop_panel(n)
	canvas.queue_redraw()
	_update_hud()

func _fill_prop_panel(n: Dictionary) -> void:
	inp_name.text = str(n.get("name", ""))
	inp_desc.text = str(n.get("desc", ""))
	inp_cost.value = float(n.get("cost", 1))
	var dir := str(n.get("direction", "进攻"))
	for i in range(inp_dir.item_count):
		if inp_dir.get_item_text(i) == dir:
			inp_dir.select(i)
	var t := str(n.get("type", "stat"))
	for i in range(inp_type.item_count):
		if str(inp_type.get_item_metadata(i)) == t:
			inp_type.select(i)
	var ei := _event_enum_to_index(str(n.get("event", "")))
	if ei >= 0:
		inp_event.select(ei)
	else:
		inp_event.select(1)  # 默认第一项非分隔
	inp_cooldown.value = float(n.get("cooldown", 0))
	inp_energy.value = float(n.get("energy_cost", 0))
	var sk := str(n.get("skill_id", ""))
	var si := _skill_id_to_index(sk)
	if si >= 0:
		inp_skill.select(si)
	_fill_effect_rows(n)


## ==================== 按钮 handlers ====================

func _on_apply_edit() -> void:
	var n := _node_by_id(selected_id)
	if n.is_empty():
		print("[天赋树编辑器] 未选中节点")
		return
	n["name"] = inp_name.text
	n["desc"] = inp_desc.text
	n["cost"] = int(inp_cost.value)
	n["direction"] = inp_dir.get_item_text(inp_dir.selected)
	var t := str(inp_type.get_item_metadata(inp_type.selected))
	n["type"] = t
	_collect_effect_rows(n)
	if t == "event":
		var ei := inp_event.selected
		if ei >= 0:
			n["event"] = str(inp_event.get_item_metadata(ei))
		n["cooldown"] = float(inp_cooldown.value)
		n["energy_cost"] = int(inp_energy.value)
	if t == "manual":
		var si := inp_skill.selected
		if si >= 0:
			n["skill_id"] = str(inp_skill.get_item_metadata(si))
	_dirty = true
	save_tree()
	_rebuild_canvas()
	print("[天赋树编辑器] 已应用修改: %s" % selected_id)


func _on_delete_selected() -> void:
	if selected_id == "":
		return
	var nodes: Array = _nodes()
	for i in range(nodes.size()):
		if str(nodes[i].get("id")) == selected_id:
			nodes.remove_at(i)
			break
	# 清理其他节点对它的 requires 引用
	for n in nodes:
		var reqs: Array = n.get("requires", [])
		if reqs.has(selected_id):
			reqs.erase(selected_id)
			n["requires"] = reqs
	selected_id = ""
	_dirty = true
	_rebuild_canvas()

## 在选中节点后方新增（线性延伸）：方向继承选中节点，类型/名称读右面板
func _on_new_after_selected() -> void:
	if selected_id == "":
		print("[天赋树编辑器] 请先点选一个父节点")
		return
	_new_node(selected_id)

## 四方向根部新增（requires 为空，位置=核心旁）
func _on_new_root() -> void:
	_new_node("")

func _new_node(parent_id: String) -> void:
	var nodes: Array = _nodes()
	var dir := inp_dir.get_item_text(inp_dir.selected)
	var seq := nodes.size() + 1
	var id := "%s_%d" % [dir.left(1), seq]
	while _node_by_id(id) != {}:
		seq += 1
		id = "%s_%d" % [dir.left(1), seq]
	var node := {
		"id": id,
		"direction": dir,
		"name": inp_name.text if inp_name.text != "" else "新天赋" + str(seq),
		"desc": inp_desc.text,
		"cost": int(inp_cost.value),
		"type": str(inp_type.get_item_metadata(inp_type.selected)),
	}
	var parent := _node_by_id(parent_id) if parent_id != "" else {}
	if parent_id != "" and not parent.is_empty():
		node["requires"] = [parent_id]
		node["direction"] = parent.get("direction", dir)  # 线性延伸继承父方向
	_collect_effect_rows(node)
	if str(node["type"]) == "event":
		var ei := inp_event.selected
		if ei >= 0:
			node["event"] = str(inp_event.get_item_metadata(ei))
		node["cooldown"] = float(inp_cooldown.value)
		node["energy_cost"] = int(inp_energy.value)
	if str(node["type"]) == "manual":
		var si := inp_skill.selected
		if si >= 0:
			node["skill_id"] = str(inp_skill.get_item_metadata(si))
	# 位置
	if parent_id != "" and not parent.is_empty():
		var ppos: Vector2 = _pos_to_vec(parent.get("pos", WORLD_CENTER))
		node["pos"] = ppos + DIR_VEC.get(str(node["direction"]), Vector2(1, 0)) * STEP
	else:
		var dirv: Vector2 = DIR_VEC.get(dir, Vector2(1, 0))
		node["pos"] = WORLD_CENTER + dirv * STEP
	nodes.append(node)
	selected_id = id
	save_tree()
	_rebuild_canvas()
	print("[天赋树编辑器] ➕ 新增 %s（%s / %s）已保存" % [id, str(node["name"]), str(node["direction"])])


## 一键重排：按方向链式重算所有节点位置（丢弃旧拖拽位置，结构=requires 树）
func _on_relayout() -> void:
	for n in _nodes():
		n.erase("pos")
	_auto_layout_missing()
	_dirty = true
	save_tree()
	_on_fit_view()
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
	save_tree()

func _on_toggle_link() -> void:
	link_mode = not link_mode
	if link_mode:
		if selected_id == "":
			print("[天赋树编辑器] 先点选父节点再开连接模式")
			link_mode = false
		else:
			link_parent = selected_id
			print("[天赋树编辑器] 连接模式：父=[%s]，点击子节点建立前置链" % link_parent)
	_update_hud()
	canvas.queue_redraw()

## 编辑器级统一输入（先于 GUI 分发）：节点拖拽/平移/缩放都在这里命中
func _input(event: InputEvent) -> void:
	# ---- 鼠标 ----
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var pos := mb.position
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var hit := _hit_test_card(pos)
				if hit != null:
					# 命中节点 → 拖节点
					_drag_card = hit
					_drag_offset = hit.position - pos
					var id := hit.name.trim_prefix("Card_")
					selected_id = id
					_fill_prop_panel(_node_by_id(id))
					get_viewport().set_input_as_handled()
					canvas.queue_redraw()
					_update_hud()
				else:
					# 空白 → 左键平移画布（业内常规：空白拖动=移动视图）
					_panning = true
					_pan_start = pos
					_view_start = view_pos
			else:
				if _drag_card != null:
					_save_card_pos(_drag_card)
					_drag_card = null
					get_viewport().set_input_as_handled()
				elif _panning and selected_id != "":
					# 空白拖动结束 → 取消选中（点空白=取消选择），面板同步清空
					selected_id = ""
					inp_name.text = ""
					inp_desc.text = ""
					_node_id_label.text = "（未选中节点）"
					_update_hud()
					canvas.queue_redraw()
				_panning = false
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_apply_zoom(pos, 1.1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_apply_zoom(pos, 1.0 / 1.1)
		elif mb.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_panning = mb.pressed
			_pan_start = mb.position
			_view_start = view_pos
			if mb.pressed:
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag_card != null:
			_drag_card.position = mm.position - _drag_offset
			_save_card_pos(_drag_card)
			canvas.queue_redraw()
		elif _panning:
			view_pos = _view_start - (mm.position - _pan_start) / zoom
			_refresh_card_positions()
			canvas.queue_redraw()
	# ---- 键盘 ----
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and link_mode:
			link_mode = false
			_update_hud()
			canvas.queue_redraw()
		elif event.keycode == KEY_S and event.ctrl_pressed:
			save_tree()
		elif event.keycode == KEY_ESCAPE:
			closed.emit()
			queue_free()
