extends Node2D
## 工单36 技能测试专用平台（1v1 技能场，与 full-ai 平台同级）——操控与UI窗口
## 用法：Godot 编辑器打开 res://scenes/test3d/skill_test_platform.tscn → F7 入口（或本场景 F6 直开）
## 设计：复用 battle_arena + dev_prep 数据驱动路径（1v1=char_id 空跳过，零改 3v3 默认行为）；
##   靶子三开关（AI 总/移动/发球，ai_manager gate 热切）；测试前面板（双槽技能全池勾选）；
##   五件：L 技能轮换 / Y CD重置能量满 / P 时间三态 / F8 一键重置 / 靶子受击统计。
## 红线：召唤/事件/道具系统零改动（只做调用方）；不改 3v3 默认行为；ai_manager 只加 gate 不动评分。

const ARENA_SCENE := "res://scenes/battle/battle_arena.tscn"

var battle_manager: Node2D = null
var panel_layer: CanvasLayer = null      # 测试前面板（开赛前）
var ctrl_layer: CanvasLayer = null       # 运行时控制条（开赛后）
var stat_layer: CanvasLayer = null       # 靶子受击统计（件⑤）
var stat_label: Label = null
var speed_label: Label = null            # 件③ 速度角标
var panel_box: VBoxContainer = null      # 面板技能勾选容器（测试者）
var panel_box_t: VBoxContainer = null    # 面板技能勾选容器（靶子）
var tester_checks: Dictionary = {}       # skill_id -> CheckBox（测试者）
var target_checks: Dictionary = {}       # skill_id -> CheckBox（靶子）
var tester_spirit: String = "test_spirit_bei_ai"
var target_spirit: String = ""
var tester_card: Dictionary = {}         # 卡片控件引用（char_opt/char_ids/spirit_opt/spirit_pick/sk_box）
var target_card: Dictionary = {}
var match_live: bool = false
var speed_states: Array[float] = [1.0, 0.2, 0.0]
var speed_idx: int = 0
var hit_count: int = 0
var hit_total: float = 0.0
var hit_log: Array = []                  # 最近 5 笔 {dmg, src}
var target_last_stamina: float = -1.0
var target_spawn: Vector2 = Vector2(260, -130)
var tester_spawn: Vector2 = Vector2(-260, -130)
var spirit_pool: Array = []              # 36号补：元灵池实体清单（测试元灵优先+正式兜底，id 去重）
var spirit_ids: Array = []               # 元灵 id 清单（面板下拉用）

func _ready() -> void:
	seed(41)
	var arena: PackedScene = load(ARENA_SCENE)
	if arena == null:
		push_error("[SkillTest] battle_arena 加载失败")
		get_tree().quit(1)
		return
	battle_manager = arena.instantiate()
	# 36号S1：dev_prep 数据驱动路径——跳过默认 3v3 建人，1v1 由本平台组装
	battle_manager.dev_prep_mode = true
	add_child(battle_manager)
	_build_spirit_pool()
	# headless 冒烟：不建面板直开（面板 UI 在 headless 下构建中断；默认装载 fenny_2 攻球 vs 素靶）
	if DisplayServer.get_name() == "headless":
		_start_1v1.call_deferred(["fenny_2"] as Array[String], [] as Array[String])
		return
	_show_panel()

var _prep_hidden := false

func _process(_delta: float) -> void:
	# 36号：dev_prep 备战界面延迟创建——轮询到即隐藏（装载由本平台面板负责）
	if _prep_hidden or battle_manager == null:
		return
	var pu = battle_manager.get("preparation_ui")
	if pu != null and is_instance_valid(pu):
		(pu as Control).visible = false
		_prep_hidden = true


## 36号补（主人报"面板选不到 full-ai 测试技能"）：元灵池=测试元灵优先+正式元灵兜底——
## full-ai 测试技能（fenny_/shuimu_ 等）走 LoadoutLoader 内存注册（不进 DataManager 主数据），
## 只读 DataManager 会漏整个测试池；复用 LoadoutLoader.load_config+register_test_spirits（零重复造）
func _build_spirit_pool() -> void:
	spirit_pool.clear()
	var loader := load("res://scripts/test3d/full_ai_platform/loadout_loader.gd")
	if loader != null and loader.has_method("load_config"):
		var config: Dictionary = loader.load_config()
		var test_spirits: Array = loader.register_test_spirits(config) if loader.has_method("register_test_spirits") else []
		for sd in test_spirits:
			if sd is Dictionary and str(sd.get("id", "")) != "":
				spirit_pool.append(sd)
	for sd in DataManager.spirits:
		if not (sd is Dictionary) or str(sd.get("id", "")) == "":
			continue
		var dup := false
		for already in spirit_pool:
			if str(already.get("id", "")) == str(sd.get("id", "")):
				dup = true
				break
		if not dup:
			spirit_pool.append(sd)
	spirit_ids.clear()
	for sd in spirit_pool:
		spirit_ids.append(str(sd.get("id")))
	if spirit_ids.is_empty():
		spirit_ids = ["test_spirit_bei_ai"]

## ===== S2 测试前面板（球员+元灵为主的双选择卡，仿 roster_panel 卡片结构） =====
var tester_char := "char_001"
var target_char := "char_004"

func _show_panel() -> void:
	panel_layer = CanvasLayer.new()
	panel_layer.name = "SkillRosterPanel"
	panel_layer.layer = 70
	add_child(panel_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	panel_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_layer.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.custom_minimum_size = Vector2(640, 0)
	margin.add_child(vb)
	var title := Label.new()
	title.text = "36 技能测试场 · 1v1 选择卡（球员+元灵为主）"
	title.add_theme_font_size_override("font_size", 18)
	vb.add_child(title)
	var sub := Label.new()
	sub.text = "选球员+元灵即自动带入其技能（可去勾微调，≤3 进技能栏）；靶子元灵选（无）=素靶。"
	sub.add_theme_font_size_override("font_size", 12)
	sub.modulate = Color(1, 1, 1, 0.7)
	vb.add_child(sub)
	vb.add_child(HSeparator.new())
	# 双卡
	vb.add_child(_make_card(true))
	vb.add_child(_make_card(false))
	vb.add_child(HSeparator.new())
	var btn := Button.new()
	btn.text = "✅ 确认开赛（1v1）"
	btn.add_theme_font_size_override("font_size", 16)
	btn.pressed.connect(_on_panel_confirm)
	vb.add_child(btn)

func _make_card(is_tester: bool) -> PanelContainer:
	var card := PanelContainer.new()
	var mv := MarginContainer.new()
	mv.add_theme_constant_override("margin_left", 10)
	mv.add_theme_constant_override("margin_right", 10)
	mv.add_theme_constant_override("margin_top", 8)
	mv.add_theme_constant_override("margin_bottom", 8)
	card.add_child(mv)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	mv.add_child(vb)
	# 卡头
	var head := Label.new()
	head.text = "【测试者】（您操控）" if is_tester else "【靶子】（被打/被测对象）"
	head.add_theme_font_size_override("font_size", 15)
	vb.add_child(head)
	# 球员选择（角色为主选）
	var row_c := HBoxContainer.new()
	row_c.add_theme_constant_override("separation", 10)
	vb.add_child(row_c)
	var lc := Label.new()
	lc.text = "球员:"
	row_c.add_child(lc)
	var char_opt := OptionButton.new()
	var char_ids: Array = []
	for cd in DataManager.characters:
		if cd is Dictionary:
			char_opt.add_item("%s（%s）" % [str(cd.get("name", "?")), str(cd.get("id", ""))])
			char_ids.append(str(cd.get("id", "")))
	char_opt.select(0 if is_tester else 3 if char_ids.size() > 3 else 0)
	if is_tester:
		tester_char = char_ids[char_opt.selected]
	else:
		target_char = char_ids[char_opt.selected]
	char_opt.item_selected.connect(func(idx: int):
		if is_tester:
			tester_char = char_ids[idx]
		else:
			target_char = char_ids[idx]
		_refresh_card_skills(is_tester))
	row_c.add_child(char_opt)
	# 元灵选择（为主）
	var row_s := HBoxContainer.new()
	row_s.add_theme_constant_override("separation", 10)
	vb.add_child(row_s)
	var ls := Label.new()
	ls.text = "元灵:"
	row_s.add_child(ls)
	var spirit_opt := OptionButton.new()
	spirit_opt.add_item("（无——素靶）")
	var spirit_pick: Array = [""]
	for sd in spirit_pool:  # 36号补：池=测试元灵（fenny_/shuimu_ 等）+正式元灵并集
		if sd is Dictionary and str(sd.get("id", "")) != "":
			spirit_opt.add_item("%s（%s）" % [str(sd.get("name", "?")), str(sd.get("element", ""))])
			spirit_pick.append(str(sd.get("id")))
	if is_tester:
		spirit_opt.select(1)
		tester_spirit = spirit_pick[1]
	spirit_opt.item_selected.connect(func(idx: int):
		var sid: String = spirit_pick[idx]
		if is_tester:
			tester_spirit = sid
		else:
			target_spirit = sid
		_refresh_card_skills(is_tester))
	row_s.add_child(spirit_opt)
	# 技能勾选区（随元灵联动；默认全勾，≤3）
	var sk_box := VBoxContainer.new()
	sk_box.name = "SkillBox"
	vb.add_child(sk_box)
	if is_tester:
		tester_card = {"char_opt": char_opt, "char_ids": char_ids, "spirit_opt": spirit_opt, "spirit_pick": spirit_pick, "sk_box": sk_box, "is_tester": true}
		_refresh_card_skills(true)
	else:
		target_card = {"char_opt": char_opt, "char_ids": char_ids, "spirit_opt": spirit_opt, "spirit_pick": spirit_pick, "sk_box": sk_box, "is_tester": false}
	return card

## 元灵联动：选元灵→自动带入其技能（默认全勾，超 3 提示截断）；无元灵=清空
func _refresh_card_skills(is_tester: bool) -> void:
	var card: Dictionary = tester_card if is_tester else target_card
	var sid: String = str(tester_spirit if is_tester else target_spirit)
	var box: VBoxContainer = card.get("sk_box")
	for c in box.get_children():
		c.queue_free()
	var checks: Dictionary = tester_checks if is_tester else target_checks
	checks.clear()
	if sid.is_empty():
		var none := Label.new()
		none.text = "（素靶：无元灵无技能）"
		none.modulate = Color(1, 1, 1, 0.6)
		box.add_child(none)
		return
	for sd in spirit_pool:  # 36号补：测试元灵优先并池（面板选得到 fenny_/shuimu_ 等）
		if not (sd is Dictionary) or str(sd.get("id", "")) != sid:
			continue
		var spname: String = str(sd.get("name", "?"))
		for sk in (sd.get("skills", []) as Array):
			var kid := str(sk)
			var cb := CheckBox.new()
			cb.button_pressed = true  # 元灵带入默认全勾
			var sname := kid
			for skd in DataManager.skills:
				if skd is Dictionary and str(skd.get("id", "")) == kid:
					sname = str(skd.get("name", kid))
					break
			cb.text = "%s（%s）" % [sname, kid]
			checks[kid] = cb
			box.add_child(cb)
		var cap := Label.new()
		var total := (sd.get("skills", []) as Array).size()
		cap.text = "元灵 %s 自带 %d 技%s" % [spname, total, "（超 3 自动取前 3，勾选微调）" if total > 3 else ""]
		cap.add_theme_font_size_override("font_size", 11)
		cap.modulate = Color(1, 1, 1, 0.6)
		box.add_child(cap)
		break

## ===== S1 1v1 接入 + 开赛 =====
## 件① L 轮换面板用：全技能池勾选（不限元灵，任意技进栏——轮换语义）
func _fill_skill_checks(box: VBoxContainer, checks: Dictionary) -> void:
	for skd in DataManager.skills:
		if not (skd is Dictionary):
			continue
		var kid := str(skd.get("id", ""))
		if kid.is_empty() or checks.has(kid):
			continue
		var cb := CheckBox.new()
		cb.text = "%s（%s）" % [str(skd.get("name", kid)), kid]
		checks[kid] = cb
		box.add_child(cb)


## 收集卡片勾选技能（≤3 进技能栏，顺序按勾选框创建序）
func _checked_skills(checks: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for kid in checks:
		if (checks[kid] as CheckBox).button_pressed:
			out.append(str(kid))
			if out.size() >= 3:
				break
	return out


func _on_panel_confirm() -> void:
	var tester_skills := _checked_skills(tester_checks)
	var target_skills := _checked_skills(target_checks)
	panel_layer.queue_free()
	panel_layer = null
	_start_1v1(tester_skills, target_skills)

func _start_1v1(tester_skills: Array[String], target_skills: Array[String]) -> void:
	var bm := battle_manager
	var a_data: Array[Dictionary] = [
		{"char_id": tester_char, "spirit_id": tester_spirit, "equipment": {"glove": "", "jersey": "", "shoes": ""}, "food": ""},
		{"char_id": "", "spirit_id": "", "equipment": {"glove": "", "jersey": "", "shoes": ""}, "food": ""},
		{"char_id": "", "spirit_id": "", "equipment": {"glove": "", "jersey": "", "shoes": ""}, "food": ""},
	]
	var b_data: Array[Dictionary] = [
		{"char_id": target_char, "spirit_id": target_spirit, "equipment": {"glove": "", "jersey": "", "shoes": ""}, "food": ""},
		{"char_id": "", "spirit_id": "", "equipment": {"glove": "", "jersey": "", "shoes": ""}, "food": ""},
		{"char_id": "", "spirit_id": "", "equipment": {"glove": "", "jersey": "", "shoes": ""}, "food": ""},
	]
	bm._on_dev_prep_match_started(a_data, b_data, 0, "a")
	# 36号S1：技能装载（LoadoutLoader 既有链——equipped→ssm→HUD）
	var tester: CharacterBody2D = bm.team_a_players[0] if bm.team_a_players.size() > 0 else null
	var target: CharacterBody2D = bm.team_b_players[0] if bm.team_b_players.size() > 0 else null
	# 36号补（主人报"面板选不到测试技能"）：元灵真装备——dev_prep 的 _apply_player_data 查
	# DataManager 会漏测试元灵（LoadoutLoader 内存注册不进主数据）——此处用并池 resolve 补装备
	var loader := load("res://scripts/test3d/full_ai_platform/loadout_loader.gd")
	if tester != null:
		if loader != null and loader.has_method("resolve_spirit_from") and not tester_spirit.is_empty():
			var sd_t: Dictionary = loader.resolve_spirit_from(spirit_pool, tester_spirit)
			if not sd_t.is_empty() and tester.has_method("equip_spirit"):
				tester.equip_spirit(sd_t)  # 元灵真上身（SpiritAI/触发链注册）
		tester.equipped_skills = tester_skills
		if bm.spirit_system and bm.spirit_system.has_method("set_player_skills"):
			bm.spirit_system.set_player_skills(tester.get_instance_id(), tester.get_equipped_skills())
	if target != null:
		if loader != null and loader.has_method("resolve_spirit_from") and not target_spirit.is_empty():
			var sd_t2: Dictionary = loader.resolve_spirit_from(spirit_pool, target_spirit)
			if not sd_t2.is_empty() and target.has_method("equip_spirit"):
				target.equip_spirit(sd_t2)
		target.equipped_skills = target_skills
		if bm.spirit_system and bm.spirit_system.has_method("set_player_skills"):
			bm.spirit_system.set_player_skills(target.get_instance_id(), target.get_equipped_skills())
	# 36号补（主人实测"白球自动生成器在该平台没作用"）：白球体系初始化——
	# full-ai 的注册在 LoadoutLoader.apply_loadouts（本平台绕行 dev_prep 不经过）——
	# 照同款逻辑补：持 fenny_2/3 的球员注册自动生成器+开局首生成（原作=开局1+5s/个，不依赖魔术无上限）
	var smgr36: Node = get_tree().get_first_node_in_group("summon_managers") if get_tree() else null
	if smgr36 != null and smgr36.has_method("register_auto_spawner"):
		for team36 in range(2):
			var team_players36: Array = bm.team_a_players if team36 == 0 else bm.team_b_players
			for pl36 in team_players36:
				if pl36 == null or not is_instance_valid(pl36):
					continue
				var ball_type36 := ""
				for sid36 in pl36.get_equipped_skills():
					if str(sid36) == "fenny_2":
						ball_type36 = "fenny_magic_ball_att"
					elif str(sid36) == "fenny_3":
						ball_type36 = "fenny_magic_ball_def"
				if ball_type36.is_empty():
					continue
				var pid36: int = pl36.get_instance_id()
				smgr36.register_auto_spawner(pid36, ball_type36, 5.0, {"owner_ref": pl36, "summon_type": ball_type36, "count": 1})
				smgr36.spawn(ball_type36, pid36, smgr36.resolve_spawn_position(ball_type36, pl36), {"owner_ref": pl36, "summon_type": ball_type36})
				print("[SkillTest] 白球体系初始化: %s → %s（开局1+5s/个）" % [str(pl36.char_data.get("name", "?")) if pl36.get("char_data") != null else "?", ball_type36])
	# 36号S6 系统性排查（对照 full-ai 副作用清单）：dev_prep 建人路径漏挂 spirit_trigger/ball_ref
	# （_deferred_init_spirit_system 的挂接遍历发生在 _ready——彼时 dev_prep 球员未建=零挂接
	#   →触发权威表/CD 判定/球技能光环通知全断）——照 _deferred_init_spirit_system 同款补挂
	for player36: CharacterBody2D in bm.team_a_players + bm.team_b_players:
		if player36 and is_instance_valid(player36):
			player36.spirit_trigger = bm.spirit_system.skill_trigger
			player36.ball_ref = bm.ball_node
	# 36号修（主人实测"技能栏没加载出来"）：36 平台建人时 set_controlled_player 早于装载
	# （此时 equipped 为空→ssm 槽空），装载后必须走既有刷新口重读——
	# full-ai 平台装载在前故无此问题，36 平台绕行 dev_prep 时序不同
	if bm.input_mgr != null and bm.input_mgr.has_method("refresh_controlled_skills"):
		bm.input_mgr.refresh_controlled_skills()
		print("[SkillTest] 驾驶位技能槽已刷新（装载后重读 equipped_skills）")
	# 36号补：HUD 图标条刷新（refresh 只刷 ssm，图标条灰格=独立缺口）——测试者 A0/靶子 B0
	var hud = bm.ui_layer.get_node_or_null("HUD") if bm.get("ui_layer") != null else null
	if hud != null and hud.has_method("_update_player_skill_icons"):
		hud._update_player_skill_icons(0)
		hud._update_player_skill_icons(3)
		print("[SkillTest] HUD 图标条已刷新（A0/B0）")
	# 靶子出生位标准 1v1 摆位（dev_prep B0=对侧 (260,-130)——platform target_spawn 同值）
	if target != null:
		target.global_position = target_spawn
	if tester != null:
		tester.global_position = tester_spawn
	# 36号：球默认给测试者（技能测试需持球态；_assign_initial_ball 是随机分两队——
	# 一半概率球在靶子手上=主人实测"球不在测试操控的球员上"）
	if tester != null and bm.get("ball_node") != null and is_instance_valid(bm.get("ball_node")):
		# 清全员持球标志（_assign_initial_ball 可能已给靶子——残留=双持球脏状态）
		for p_clr in (bm.team_a_players + bm.team_b_players):
			if p_clr != null and is_instance_valid(p_clr) and p_clr.has_method("set_carrying_ball"):
				p_clr.set_carrying_ball(false)
		bm.ball_node.return_to_player(tester)
	# 三开关初始态：AI 总关（靶子纯站桩）
	ai_mgr_gate_apply()
	_build_ctrl_bar()  # 含控制条+速度角标+受击统计面板（件③⑤）
	match_live = true
	target_last_stamina = float(target.get("stamina")) if target != null else -1.0
	print("[SkillTest] ✅ 1v1 就绪：测试者技能=%s 靶子技能=%s（AI 总开关=关，靶子站桩）" % [
		str(tester_skills), str(target_skills)])

## ===== S3 靶子三开关（ai_manager gate 热切） =====
var gate_ai := false       # AI 总开关（默认关=站桩）
var gate_move := false     # 移动开关（AI 总开时有效）
var gate_shoot := false    # 发球开关（AI 总开时有效）

func ai_mgr_gate_apply() -> void:
	var am: Node = battle_manager.get("ai_mgr") if battle_manager != null else null
	var target: CharacterBody2D = bm_target()
	if am == null or target == null:
		return
	var pid: int = target.get_instance_id()
	if am.has_method("set_target_gates"):
		am.set_target_gates(pid, {"ai": gate_ai, "move": gate_move, "shoot": gate_shoot})

func bm_target() -> CharacterBody2D:
	return battle_manager.team_b_players[0] if battle_manager != null and battle_manager.team_b_players.size() > 0 else null

func _build_ctrl_bar() -> void:
	ctrl_layer = CanvasLayer.new()
	ctrl_layer.name = "TestCtrlBar"
	ctrl_layer.layer = 100  # 36号：battle ui_layer=10 会压住默认 layer=1→鼠标点不到开关（主人实测）
	add_child(ctrl_layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(10, 40)
	ctrl_layer.add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	var title := Label.new()
	title.text = "靶子控制（AI 总开→子开关生效）"
	vb.add_child(title)
	var cb_ai := CheckBox.new()
	cb_ai.text = "AI 总开关"
	cb_ai.button_pressed = gate_ai
	cb_ai.toggled.connect(func(on: bool):
		gate_ai = on
		ai_mgr_gate_apply())
	vb.add_child(cb_ai)
	var cb_move := CheckBox.new()
	cb_move.text = "  移动开关"
	cb_move.button_pressed = gate_move
	cb_move.toggled.connect(func(on: bool):
		gate_move = on
		ai_mgr_gate_apply())
	vb.add_child(cb_move)
	var cb_shoot := CheckBox.new()
	cb_shoot.text = "  发球开关"
	cb_shoot.button_pressed = gate_shoot
	cb_shoot.toggled.connect(func(on: bool):
		gate_shoot = on
		ai_mgr_gate_apply())
	vb.add_child(cb_shoot)
	var tip2 := Label.new()
	tip2.text = "F1~F3=指挥靶子放技能栏 1~3\nL 轮换装载 / Y CD能量 / P 时间三态 / F8 一键重置"
	vb.add_child(tip2)
	# 件③ 速度角标
	speed_label = Label.new()
	speed_label.text = "速度 x1.0"
	speed_label.position = Vector2(700, 34)
	ctrl_layer.add_child(speed_label)
	# 件⑤ 受击统计
	stat_layer = CanvasLayer.new()
	stat_layer.name = "TargetStats"
	stat_layer.layer = 100  # 同上置顶
	add_child(stat_layer)
	var sp := PanelContainer.new()
	sp.position = Vector2(1150, 40)
	stat_layer.add_child(sp)
	var sv := VBoxContainer.new()
	sp.add_child(sv)
	stat_label = Label.new()
	stat_label.text = "靶子受击: 0 次 / 0 伤\n（最近5笔空）"
	sv.add_child(stat_label)

## ===== 件② Y：CD 重置+能量满 =====
func _reset_cd_energy() -> void:
	var cp: CharacterBody2D = bm_controlled()
	if cp == null:
		return
	var ssm: Node = battle_manager.get("spirit_system").get("skill_trigger") if battle_manager.get("spirit_system") != null else null
	var ssm2: Node = battle_manager.input_mgr.get("skill_state_manager") if battle_manager.input_mgr != null else null
	if ssm2 != null:
		var skills: Dictionary = ssm2.get("_player_skills").get(cp.get_instance_id(), {})
		for slot in skills:
			skills[slot]["state"] = 0  # SkillState.IDLE
		var lcd: Dictionary = ssm2.get("_last_press_times")
		if lcd is Dictionary:
			lcd.erase(cp.get_instance_id())
	cp.set("spirit_energy", cp.get("max_spirit_energy"))
	print("[SkillTest] Y：CD 清零+能量回满")

func bm_controlled() -> CharacterBody2D:
	return battle_manager.input_mgr.controlled_player if battle_manager != null and battle_manager.input_mgr != null else null

## ===== 件③ P：时间三态 =====
func _cycle_time() -> void:
	speed_idx = (speed_idx + 1) % speed_states.size()
	Engine.time_scale = speed_states[speed_idx]
	if speed_label != null:
		speed_label.text = "速度 x%.1f" % speed_states[speed_idx]
	print("[SkillTest] P：time_scale=%.2f" % Engine.time_scale)

## ===== 件① L：技能轮换装载（打开面板暂停，确认重挂恢复） =====
func _open_swap_panel() -> void:
	var prev_scale := Engine.time_scale
	Engine.time_scale = 0.0  # 件③联动：装载期间暂停
	var layer := CanvasLayer.new()
	layer.name = "SwapPanel"
	add_child(layer)
	var root := PanelContainer.new()
	root.set_anchors_preset(Control.PRESET_CENTER)
	layer.add_child(root)
	var vb := VBoxContainer.new()
	root.add_child(vb)
	vb.add_child(Label.new())
	vb.add_child(Label.new())
	var swap_box := VBoxContainer.new()
	vb.add_child(swap_box)
	var swap_checks: Dictionary = {}
	_fill_skill_checks(swap_box, swap_checks)
	var btn := Button.new()
	btn.text = "确认替换技能栏"
	btn.pressed.connect(func():
		var picked := _checked_skills(swap_checks)
		var cp := bm_controlled()
		if cp != null:
			cp.equipped_skills = picked
			var ss: Node = battle_manager.get("spirit_system")
			if ss != null and ss.has_method("set_player_skills"):
				ss.set_player_skills(cp.get_instance_id(), cp.get_equipped_skills())
			var ssm: Node = battle_manager.input_mgr.get("skill_state_manager") if battle_manager.input_mgr != null else null
			if ssm != null and ssm.has_method("setup_player_skills"):
				ssm.setup_player_skills(cp.get_instance_id(), cp.get_equipped_skills())
			print("[SkillTest] L：技能栏替换 → %s" % str(picked))
		Engine.time_scale = prev_scale
		layer.queue_free())
	vb.add_child(btn)
	Engine.time_scale = 0.0

## ===== 件④ F8：一键重置（不重载场景=新开赛等价） =====
func _reset_match() -> void:
	var bm := battle_manager
	# 召唤物全清
	var smgr: Node = get_tree().get_first_node_in_group("summon_managers")
	if smgr != null and smgr.has_method("clear_all"):
		smgr.clear_all()
	# 球回中圈
	var ball: Node2D = bm.get("ball_node")
	if ball != null and is_instance_valid(ball):
		ball.global_position = Vector2.ZERO
		ball.set("ball_speed", 0.0)
		ball.set("is_active", true)
		ball.set("is_ready_to_catch", false)
	# 球员回出生点+满状态+待用/形态清
	for p in (bm.team_a_players + bm.team_b_players):
		if p == null or not is_instance_valid(p):
			continue
		p.global_position = tester_spawn if str(p.get("team")) == "a" else target_spawn
		p.set("stamina", p.get("max_stamina"))
		p.set("spirit_energy", p.get("max_spirit_energy"))
		p.set("pending_item_id", "")
		p.set("pending_firework_form", false)
		p.set("defend_intercept_ready", false)
		p.set("is_defeated", false)
	# 道具/统计清
	var g: Node = get_tree().get_first_node_in_group("battle_item_granters")
	if g != null and g.has_method("clear_all"):
		g.clear_all()
	hit_count = 0
	hit_total = 0.0
	hit_log.clear()
	_update_stat_label()
	# 相位重置（PRE 待开）
	GameManager.score_team_a = 0
	GameManager.score_team_b = 0
	GameManager.start_match()
	ai_mgr_gate_apply()
	print("[SkillTest] F8：一键重置完成（新一局待开状态）")

## ===== 件⑤ 靶子受击统计（轮询 stamina delta 记账） =====
func _update_stat_label() -> void:
	if stat_label != null:
		var recent := ""
		for h in hit_log:
			recent += "%s\n" % str(h)
		stat_label.text = "靶子受击: %d 次 / %.0f 伤\n最近5笔:\n%s" % [hit_count, hit_total, recent if recent != "" else "（空）"]

func _physics_process(_delta: float) -> void:
	if not match_live:
		return
	var t := bm_target()
	if t == null or not is_instance_valid(t):
		return
	var now: float = float(t.get("stamina"))
	if target_last_stamina >= 0.0 and now < target_last_stamina:
		var dmg: float = target_last_stamina - now
		hit_count += 1
		hit_total += dmg
		hit_log.push_front({"dmg": dmg, "src": "recent"})
		if hit_log.size() > 5:
			hit_log.pop_back()
		_update_stat_label()
	target_last_stamina = now

## ===== 键位（L/Y/P/F8/F1-F3） =====
func _unhandled_key_input(event: InputEvent) -> void:
	if not match_live or not (event is InputEventKey) or not event.pressed:
		return
	match event.keycode:
		KEY_L:
			_open_swap_panel()
		KEY_Y:
			_reset_cd_energy()
		KEY_P:
			_cycle_time()
		KEY_F8:
			_reset_match()
		KEY_F1:
			_order_target_cast(0)
		KEY_F2:
			_order_target_cast(1)
		KEY_F3:
			_order_target_cast(2)

## 36号S3 靶子技能释放指挥：F1~F3=靶子技能栏对应技立即施放（主人触发不走 AI 时机）
func _order_target_cast(slot: int) -> void:
	var t := bm_target()
	if t == null or not is_instance_valid(t):
		return
	var skills: Array = t.get("equipped_skills") if t.get("equipped_skills") != null else []
	if slot >= skills.size():
		print("[SkillTest] F%d：靶子技能栏无此槽（装载 %s）" % [slot + 1, str(skills)])
		return
	var sid := str(skills[slot])
	if t.has_method("use_skill_by_id"):
		t.use_skill_by_id(sid)
		print("[SkillTest] F%d：指挥靶子施放 %s" % [slot + 1, sid])
