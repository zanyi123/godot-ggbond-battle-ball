# -*- coding: utf-8 -*-
# 面板重构脚本：_build_prop_panel 整段替换为中文动态版
import io

p = 'scripts/dev_tools/dev_talent_tree_editor.gd'
src = io.open(p, encoding='utf-8').read()

start = src.index("func _build_prop_panel() -> void:")
end = src.index("## ==================== 画布与节点卡片")

new_panel = u'''func _build_prop_panel() -> void:
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
	hint.text = "提示：新增读取上方全部字段；线性延伸\\n=新节点以选中节点为前置，继承方向"
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
	for t in _tag_catalog:
		opt.add_item(t["name"])
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

'''

src = src[:start] + new_panel + src[end:]
io.open(p, 'w', encoding='utf-8', newline='\n').write(src)
print("面板重构完成")
