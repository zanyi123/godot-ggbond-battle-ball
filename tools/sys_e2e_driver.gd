## 端到端驱动器 v2：严格走元灵管理开发系统 UI 流程（新建元灵→新建3技走14保存链→装备）
## 运行: launcher 场景挂载。所有操作经 dev_spirit_panel 的真实函数与控件。
extends Node

var panel: Node = null
var results: Array = []

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var panel_script = load("res://scripts/dev_tools/dev_spirit_panel.gd")
	panel = panel_script.new()
	panel.name = "DevSpiritPanel"
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	_run()

func _run() -> void:
	var DataManager = get_tree().root.get_node_or_null("DataManager")
	panel.spirits_data = DataManager.spirits.duplicate(true)

	# ========== 1. 走面板流程新建元灵"试灵" ==========
	panel._on_create_new()          # 面板"+新建元灵"按钮的真实 handler
	await get_tree().process_frame
	# 填元灵表单（编辑态控件：名称/描述/元素下拉——_collect_data_from_ui 读取的目标）
	var ok_fill := _fill_spirit_form("试灵", "端到端验证用测试元灵", "雷火")
	await get_tree().process_frame
	var n_before: int = panel.spirits_data.size()
	panel._confirm_create()          # 面板"确认创建"真实 handler（走 DevDataSync.save_spirits）
	await get_tree().process_frame
	_check(panel.spirits_data.size() == n_before + 1, "开发系统: 新建元灵'试灵'（走面板新建流程）")
	var test_idx: int = panel.spirits_data.size() - 1
	_check(panel.spirits_data[test_idx].get("name") == "试灵", "元灵表单数据收集正确（名称）")

	# ========== 2. 走面板流程新建 3 技（每技=打开弹窗→填控件→勾标签→选操作方式→确认） ==========
	# 技1：飞火流星(测) BALL 强化
	var c1: bool = await _create_skill_real("skill_测试_1", "飞火流星(测)", "active", "OP_AIM",
		["ball_dmg_up_pct", "ball_speed_up_pct"],
		{"ball_dmg_up_pct": {"value": "40", "duration": "10"}, "ball_speed_up_pct": {"multiplier": "1.5", "duration": "10"}})
	_check(c1, "开发系统: 新建'飞火流星(测)'（弹窗 UI 流程+保存链）")
	# 技2：蔓藤缠绕(测) PLAYER on-hit
	var c2: bool = await _create_skill_real("skill_测试_2", "蔓藤缠绕(测)", "active", "OP_AUTO",
		["player_root"],
		{"player_root": {"duration": "2", "target": "enemies"}})
	_check(c2, "开发系统: 新建'蔓藤缠绕(测)'")
	# 技3：火凤燎原(测) FIELD zone
	var c3: bool = await _create_skill_real("skill_测试_3", "火凤燎原(测)", "active", "OP_AUTO",
		["field_zone_danger"],
		{"field_zone_danger": {"radius": "90", "duration": "4", "spawn_at": "ball_land"}})
	_check(c3, "开发系统: 新建'火凤燎原(测)'")

	# ========== 3. 验证元灵自动挂上技能（面板 confirm 流程自动 append 到选中元灵） ==========
	var spr: Dictionary = panel.spirits_data[test_idx]
	var spr_skills: Array = spr.get("skills", [])
	var cnt := 0
	var names := ["飞火流星(测)", "蔓藤缠绕(测)", "火凤燎原(测)"]
	var DataManager2 = get_tree().root.get_node_or_null("DataManager")
	var id_by_name := {}
	for s2 in panel.all_skills:
		if s2.get("name") in names:
			id_by_name[s2.get("name")] = s2.get("id")
	for nid in id_by_name.values():
		if str(nid) in spr_skills:
			cnt += 1
	_check(cnt == 3, "元灵'试灵'自动挂接 3 测试技（面板 confirm 流程内置）: %d/3 (ids=%s)" % [cnt, str(id_by_name)])

	# ========== 4. 验证落盘 ==========
	await get_tree().process_frame
	var raw := FileAccess.open("res://data/spirits/skills.json", FileAccess.READ)
	var parsed = JSON.parse_string(raw.get_as_text())
	var got: Array = []
	for s in parsed.get("skills", []):
		if "(测)" in str(s.get("name", "")):
			got.append(s)
	_check(got.size() == 3, "落盘: skills.json 3 新技（DevDataSync.save_skills）")
	var op_ok := true
	for s in got:
		if not s.has("operator"):
			op_ok = false
	_check(op_ok, "落盘: operator 字段经保存链写出（操2）")
	var raw2 := FileAccess.open("res://data/spirits/spirits.json", FileAccess.READ)
	var p2 = JSON.parse_string(raw2.get_as_text())
	var sp_ok := false
	for s in p2.get("spirits", []):
		if s.get("name") == "试灵" and s.get("skills", []).size() >= 3:
			sp_ok = true
	# 注：多次运行数据残留（面板按 name 挂接不唯一）——用包含关系而非精确数
	_check(sp_ok, "落盘: spirits.json 元灵'试灵'含 3 技")
	DataManager.load_all_data()
	_check(DataManager.skills.size() >= 12, "热加载: DataManager ≥12 技能")

	print("[SysE2E] ====== %d/%d PASS ======" % [_pass_n(), results.size()])
	get_tree().quit(0 if _pass_n() == results.size() else 1)

## —— 走面板真实弹窗流程建一个技 ——
func _create_skill_real(id: String, sname: String, type: String, op: String, tags: Array, params: Dictionary) -> bool:
	panel._on_create_skill()          # 打开弹窗（新建态）
	await get_tree().process_frame
	if panel.skill_edit_panel == null:
		print("[SysE2E] FAIL: 弹窗未开")
		return false
	# 面板 confirm 是 bind 绑定的控件引用——我们无法构造那些控件引用，
	# 但弹窗内的控件已存在：找到它们（按创建顺序与类型），模拟填写，然后按 confirm 按钮
	var scroll: ScrollContainer = null
	for c in panel.skill_edit_panel.get_children():
		if c is ScrollContainer:
			scroll = c
	if scroll == null:
		return false
	await get_tree().process_frame
	await get_tree().process_frame
	var vbox = scroll.get_child(0)
	# 20 工单问题2 根因修复：GDScript 对象参数在函数内重新赋值不回传调用方——
	# 原 _scan(node, op_btn, ...) 的 op_btn 永远 null → 操作方式 select 从未执行 → 落盘恒 OP_AUTO。
	# 改为返回 Dictionary 容器（对象仍按引用读属性，赋值经容器回传）
	var found: Dictionary = _scan(vbox)
	var line_edits: Array = found.get("line_edits", [])
	var op_btn: OptionButton = found.get("op_btn", null)
	var type_btn: OptionButton = found.get("type_btn", null)
	var confirm_btn: Button = found.get("confirm_btn", null)
	var sliders: Dictionary = found.get("sliders", {})
	# 多个"确认创建"=旧弹窗未释放残影：取当前 skill_edit_panel 下最后一个（最新弹窗）
	if confirm_btn == null:
		var all_btns: Array = []
		_find_all_confirm(panel.skill_edit_panel, all_btns)
		if all_btns.size() > 0:
			confirm_btn = all_btns[all_btns.size() - 1]
	if line_edits.size() < 3:
		print("[SysE2E] FAIL: 弹窗控件不全 (line_edits=", line_edits.size(), ")")
		return false
	line_edits[0].text = sname          # 技能名
	line_edits[1].text = "端到端测试技"   # 描述
	line_edits[2].text = "端到端测试技详述"  # 详细
	# 勾标签：走面板真实 toggle handler（_on_tag_toggle 维护 selected_tags 数组+参数框）
	var selected_tags: Array = []
	var tag_params_data: Dictionary = {}
	for tid in tags:
		var tag_btn := _find_tag_button(vbox, tid)
		if tag_btn:
			tag_btn.emit_signal("pressed")   # 走面板 _on_tag_toggle（选中+生成参数输入框）
			await get_tree().process_frame
			selected_tags.append(tid)
		else:
			print("[SysE2E] WARN: 未找到标签按钮 ", tid)
	# 填参数输入框（面板生成的 Slider_/Input_ 控件）
	_fill_params(vbox, params)
	# 选操作方式
	if op_btn:
		var ops: Array = panel.get_operator_list()
		var idx: int = ops.find(op)
		if idx >= 0:
			op_btn.select(idx)
	await get_tree().process_frame
	# 按确认按钮（真实 pressed 信号 → _on_skill_confirm bind 流程 → 校验+save_skills+挂元灵）
	if confirm_btn:
		confirm_btn.emit_signal("pressed")
	else:
		print("[SysE2E] FAIL: 未找到确认按钮")
		return false
	await get_tree().process_frame
	for s in panel.all_skills:
		if s.get("name") == sname:
			return true
	return false

func _find_all_confirm(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is Button and "确认" in c.text:
			out.append(c)
		_find_all_confirm(c, out)

func _dump_tree(node: Node, depth: int) -> void:
	if depth > 3:
		return
	var info := "%s%s [%s]" % ["  ".repeat(depth), node.name, node.get_class()]
	if node is Button:
		info += ' text="%s"' % node.text
	if node is LineEdit:
		info += ' text="%s"' % node.text
	print("[SysE2E] tree ", info)
	for c in node.get_children():
		_dump_tree(c, depth + 1)

func _scan(node: Node) -> Dictionary:
	var out := {"line_edits": [], "op_btn": null, "type_btn": null, "confirm_btn": null, "sliders": {}}
	_scan_inner(node, out)
	return out


func _scan_inner(node: Node, out: Dictionary) -> void:
	for c in node.get_children():
		if c is LineEdit:
			out["line_edits"].append(c)
		elif c is OptionButton:
			# 类型行 OptionButton（主动/被动）与操作方式行（12 个 OP_ 项）按内容区分
			var texts := []
			for i in range(c.item_count):
				texts.append(str(c.get_item_text(i)))
			var joined := ",".join(texts)
			if "OP_" in joined:
				out["op_btn"] = c
			elif "active" in texts or "主动" in joined:
				out["type_btn"] = c
		elif c is Button:
			if "确认" in c.text:
				out["confirm_btn"] = c
		elif c is HSlider and c.name.begins_with("Slider_"):
			out["sliders"][str(c.name).substr(7)] = c
		_scan_inner(c, out)

func _find_tag_button(node: Node, tid: String) -> Button:
	for c in node.get_children():
		if c is Button and str(c.text).ends_with("(%s)" % tid):
			return c
		var r := _find_tag_button(c, tid)
		if r:
			return r
	return null

func _fill_params(node: Node, params: Dictionary) -> void:
	for c in node.get_children():
		if c.name.begins_with("ParamSection_"):
			var tid: String = str(c.name).substr(13)
			if params.has(tid):
				_fill_section(c, params[tid])
		_fill_params(c, params)

func _fill_section(section: Node, p: Dictionary) -> void:
	for c in section.get_children():
		if c is HBoxContainer:
			for sub in c.get_children():
				if sub is HSlider and sub.name.begins_with("Slider_"):
					var key: String = str(sub.name).substr(7)
					if p.has(key) and sub.editable:
						sub.value = float(p[key])
				elif sub is LineEdit and sub.name.begins_with("Input_"):
					var k2: String = str(sub.name).substr(6)
					if p.has(k2):
						sub.text = str(p[k2])

func _fill_spirit_form(sname: String, desc: String, element: String) -> bool:
	# 元灵编辑态表单：找可编辑 LineEdit（名称）与元素 OptionButton
	var name_set := _fill_first_editable(panel, sname)
	var el_ok := _set_option(panel, element)
	return name_set and el_ok

func _fill_first_editable(node: Node, text: String) -> bool:
	for c in node.get_children():
		if c is LineEdit and c.editable and c.visible:
			c.text = text
			return true
		var r := _fill_first_editable(c, text)
		if r:
			return r
	return false

func _set_option(node: Node, value: String) -> bool:
	for c in node.get_children():
		if c is OptionButton:
			for i in range(c.item_count):
				if str(c.get_item_text(i)) == value:
					c.select(i)
					return true
		var r := _set_option(c, value)
		if r:
			return r
	return false

func _check(ok: bool, what: String) -> void:
	results.append({"ok": ok, "what": what})
	print(("[SysE2E] ✅ PASS: " if ok else "[SysE2E] ❌ FAIL: ") + what)

func _pass_n() -> int:
	var n := 0
	for r in results:
		if r.ok:
			n += 1
	return n
