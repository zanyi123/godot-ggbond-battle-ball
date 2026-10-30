extends Control
## 主菜单 - 游戏入口
## 支持两种模式：玩家模式（普通用户）/ 管理员模式（开发者工具）

# 主菜单交互节点列表（打开子界面时隐藏，关闭时恢复）
var _menu_interactive_nodes: Array[Node] = []
# 当前模式："player" / "admin"
var _current_mode: String = ""
# 模式选择界面节点
var _mode_selection_nodes: Array[Node] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# ★ 2026-10-30 U0-6 排版规范落地：根节点统一挂 Theme，所有子控件继承字号/色值/框件。
	#   U0-6 §七 验收：面板脚本内不应再有 add_theme_font_size_override / 散落 Color(。
	theme = UiTheme.shared()

	# 36号：F7 入口=技能测试专用平台（键位表已登记；主菜单按下即切场景）
	# 36号：F7 用 _input 截获（见 _input 实现）
	set_process_input(true)

	# 背景（2026-10-30 挂载：蓝白星动态背景 → 协会大厅）
	# 原为 ColorRect(0.1,0.1,0.2) 纯色占位；现替换为 scenes/ui/bg_lobby_planet.tscn
	# （四层实时 GPU 动效，14 秒无缝循环；资源见美术规划/08 档 §十五）
	var bg_scene_path := "res://scenes/ui/bg_lobby_planet.tscn"
	if ResourceLoader.exists(bg_scene_path):
		var bg_dyn: Control = (load(bg_scene_path) as PackedScene).instantiate()
		bg_dyn.name = "BG"
		add_child(bg_dyn)
		# 不在任何交互路径上挡鼠标（背景只做视觉）
		bg_dyn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 左侧压暗带：菜单区文字保持 Theme 原色也清晰（U0-6 §六 对比度）
		if bg_dyn.has_method("add_left_scrim"):
			bg_dyn.add_left_scrim(0.40, 0.58)
	else:
		# 资源缺失回退原占位色块（保持旧行为，不崩）
		var bg := ColorRect.new()
		bg.name = "BG"
		bg.size = Vector2(1440, 900)
		bg.color = Color(0.1, 0.1, 0.2)
		add_child(bg)

	# 标题（2026-10-30 走 Theme：LblDisplay 40 档 + 色板文字色，去硬编码）
	# 注：标题文案按 v5 §7.8 应改「寻源竞球者」——属主题改名，**主人令暂缓**，此处保持原文案
	var title := Label.new()
	title.name = "Title"
	title.text = "决竞球"
	title.theme_type_variation = "LblDisplay"
	title.position = Vector2(120, 78)
	title.size = Vector2(700, 70)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(title)

	# 如果有上次记录的模式，直接进入；否则显示模式选择
	if GameManager and GameManager.last_menu_mode == "player":
		if PlayerSaveManager and PlayerSaveManager.current_slot != GameManager.MODE_SLOT_PLAYER:
			PlayerSaveManager.load_slot(GameManager.MODE_SLOT_PLAYER)
		_build_main_menu(false)
	elif GameManager and GameManager.last_menu_mode == "admin":
		if PlayerSaveManager and PlayerSaveManager.current_slot != GameManager.MODE_SLOT_ADMIN:
			PlayerSaveManager.load_slot(GameManager.MODE_SLOT_ADMIN)
		_build_main_menu(true)
	else:
		_show_mode_selection()


## 显示模式选择界面
## ★ 2026-10-30 按 U0-6 排版规范重做（原为硬编码坐标+写死色值，零 Theme）
##   §三 字号档：页题用 LblTitle / 节题 LblSection / 辅助 LblCaption
##   §四 固定操作区：按钮高 ≥44px，快捷键提示行常驻底栏
##   经验库 10-27「去卡片化」：大号裸文字 + 序号 + 斜切高亮，禁圆角卡片感
##   §七 验收：本函数内**无 Color( / add_theme_color_override / add_theme_font_size_override**
func _show_mode_selection() -> void:
	_clear_mode_selection()

	# 主菜单根节点挂 Theme（一处生效，子控件全继承）
	theme = UiTheme.shared()

	var vs: Vector2 = get_viewport_rect().size

	# ── 页题区（左对齐，让出右侧主视觉；N1 规格「左1/3 留白」）
	var title_lb := UiLayout.make_page_title("选 择 模 式")
	title_lb.position = Vector2(UiLayout.PAD_PANEL * 3, 178)
	title_lb.size = Vector2(560, 48)
	add_child(title_lb)
	_mode_selection_nodes.append(title_lb)

	var sub_lb := UiLayout.make_section_label("SELECT MODE")
	sub_lb.position = Vector2(UiLayout.PAD_PANEL * 3, 234)
	sub_lb.size = Vector2(560, 24)
	add_child(sub_lb)
	_mode_selection_nodes.append(sub_lb)

	# ── 菜单项（去卡片化：大号裸文字 + 序号）
	var stack := UiLayout.make_vstack(UiLayout.GAP_M)
	stack.position = Vector2(UiLayout.PAD_PANEL * 3, 300)
	stack.custom_minimum_size = Vector2(380, 0)
	add_child(stack)
	_mode_selection_nodes.append(stack)

	var e_player := UiLayout.make_menu_entry(1, "玩 家 模 式", _on_enter_player_mode)
	stack.add_child(e_player)
	_mode_selection_nodes.append(e_player)

	var d_player := UiLayout.make_caption("正常游戏体验，不含开发者工具")
	d_player.custom_minimum_size = Vector2(380, 0)
	stack.add_child(d_player)
	_mode_selection_nodes.append(d_player)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, UiLayout.GAP_L - UiLayout.GAP_XS)
	stack.add_child(spacer)
	_mode_selection_nodes.append(spacer)

	var e_admin := UiLayout.make_menu_entry(2, "管 理 员 模 式", _on_enter_admin_mode)
	stack.add_child(e_admin)
	_mode_selection_nodes.append(e_admin)

	var d_admin := UiLayout.make_caption("开发者工具 · 数据管理 · 物资发放（测试用）")
	d_admin.custom_minimum_size = Vector2(380, 0)
	stack.add_child(d_admin)
	_mode_selection_nodes.append(d_admin)

	# ── 快捷键提示行（U0-6 §四 第4条：常驻底栏）
	var hint := UiLayout.make_key_hint_bar("Enter 确认 · Esc 返回 · F7 技能测试平台")
	add_child(hint)
	_mode_selection_nodes.append(hint)


func _clear_mode_selection() -> void:
	for node in _mode_selection_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_mode_selection_nodes.clear()


## 进入玩家模式
func _on_enter_player_mode() -> void:
	_current_mode = "player"
	if GameManager:
		GameManager.last_menu_mode = "player"
		# 切换到玩家存档（数据隔离）
		if PlayerSaveManager and PlayerSaveManager.current_slot != GameManager.MODE_SLOT_PLAYER:
			PlayerSaveManager.load_slot(GameManager.MODE_SLOT_PLAYER)
	_clear_mode_selection()
	_build_main_menu(false)


## 36号：F7=技能测试专用平台入口（键位表登记；用 _input 截获防 UI 消费——
## _unhandled_input 会被全屏 Control 的键盘焦点吃掉）
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F7:
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file("res://scenes/test3d/skill_test_platform.tscn")


## 进入管理员模式
func _on_enter_admin_mode() -> void:
	_current_mode = "admin"
	if GameManager:
		GameManager.last_menu_mode = "admin"
		# 切换到管理员存档（数据隔离）
		if PlayerSaveManager and PlayerSaveManager.current_slot != GameManager.MODE_SLOT_ADMIN:
			PlayerSaveManager.load_slot(GameManager.MODE_SLOT_ADMIN)
	_clear_mode_selection()
	_build_main_menu(true)


## 返回模式选择界面
func _on_back_to_mode_selection() -> void:
	_current_mode = ""
	if GameManager:
		GameManager.last_menu_mode = ""
	# 清空主菜单按钮
	for node in _menu_interactive_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_menu_interactive_nodes.clear()
	_show_mode_selection()


## 构建主菜单按钮
## is_admin: 是否显示管理员专属按钮
func _build_main_menu(is_admin: bool) -> void:
	# 模式标识
	if is_admin:
		var mode_tag := Label.new()
		mode_tag.text = "【管理员模式】"
		mode_tag.position = Vector2(1150, 15)
		mode_tag.size = Vector2(260, 30)
		mode_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		mode_tag.add_theme_font_size_override("font_size", 16)
		mode_tag.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
		add_child(mode_tag)
		_menu_interactive_nodes.append(mode_tag)

	# 开始比赛按钮
	var btn_start := UiLayout.make_primary_button("开始比赛", 350)
	btn_start.name = "BtnStart"
	btn_start.text = "开始比赛"
	btn_start.position = Vector2(545, 260)
	btn_start.pressed.connect(_on_start_match)
	add_child(btn_start)
	_menu_interactive_nodes.append(btn_start)

	# 角色系统按钮
	var btn_chars := UiLayout.make_ghost_button("角色系统", 350)
	btn_chars.name = "BtnCharacters"
	btn_chars.text = "角色系统"
	btn_chars.position = Vector2(545, 335)
	btn_chars.pressed.connect(_on_open_characters)
	add_child(btn_chars)
	_menu_interactive_nodes.append(btn_chars)

	# 元灵系统按钮
	var btn_spirits := UiLayout.make_ghost_button("元灵系统", 350)
	btn_spirits.name = "BtnSpirits"
	btn_spirits.text = "元灵系统"
	btn_spirits.position = Vector2(545, 410)
	btn_spirits.pressed.connect(_on_open_spirits)
	add_child(btn_spirits)
	_menu_interactive_nodes.append(btn_spirits)

	# 基地按钮
	var btn_base := UiLayout.make_ghost_button("基地", 350)
	btn_base.name = "BtnBase"
	btn_base.text = "基地"
	btn_base.position = Vector2(545, 485)
	btn_base.pressed.connect(_on_open_base)
	add_child(btn_base)
	_menu_interactive_nodes.append(btn_base)

	# 交易按钮
	var btn_trade := UiLayout.make_ghost_button("交易", 350)
	btn_trade.name = "BtnTrade"
	btn_trade.text = "交易"
	btn_trade.position = Vector2(545, 560)
	btn_trade.pressed.connect(_on_open_trade)
	add_child(btn_trade)
	_menu_interactive_nodes.append(btn_trade)

	# 联机对战按钮（工单01 S2：左列独立位，不动现有按钮布局）
	var btn_net := UiLayout.make_ghost_button("联机对战", 220)
	btn_net.name = "BtnNetLobby"
	btn_net.text = "联机对战"
	btn_net.position = Vector2(150, 260)
	btn_net.pressed.connect(_on_open_net_lobby)
	add_child(btn_net)
	_menu_interactive_nodes.append(btn_net)

	# ── 设置 / 教学（2026-10-30 第3批：U1 面板进主流程）
	# 之前 settings_panel / tutorial_overlay 只被测试套件引用，玩家无入口。
	var btn_settings := UiLayout.make_ghost_button("设 置", 220)
	btn_settings.name = "BtnSettings"
	btn_settings.position = Vector2(150, 320)
	btn_settings.pressed.connect(_on_open_settings)
	add_child(btn_settings)
	_menu_interactive_nodes.append(btn_settings)

	var btn_tutorial := UiLayout.make_ghost_button("溯源第一课", 220)
	btn_tutorial.name = "BtnTutorial"
	btn_tutorial.position = Vector2(150, 380)
	btn_tutorial.pressed.connect(_on_open_tutorial)
	add_child(btn_tutorial)
	_menu_interactive_nodes.append(btn_tutorial)

	# 奖励开关按钮（所有玩家可用）
	var btn_reward := Button.new()
	btn_reward.name = "BtnReward"
	var reward_on: bool = RewardSystem.reward_config.get("reward_enabled", false)
	btn_reward.text = "比赛奖励: %s" % ("已开启" if reward_on else "已关闭")
	btn_reward.position = Vector2(545, 635)
	btn_reward.size = Vector2(350, 45)
	btn_reward.add_theme_font_size_override("font_size", 16)
	btn_reward.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3) if reward_on else Color(0.6, 0.6, 0.6))
	btn_reward.pressed.connect(_on_toggle_reward)
	add_child(btn_reward)
	_menu_interactive_nodes.append(btn_reward)

	# 管理员专属：开发者工具按钮
	if is_admin:
		var btn_dev := Button.new()
		btn_dev.name = "BtnDev"
		btn_dev.text = "快捷设置（开发者）"
		btn_dev.position = Vector2(545, 695)
		btn_dev.size = Vector2(350, 40)
		btn_dev.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
		btn_dev.pressed.connect(_on_open_dev_settings)
		add_child(btn_dev)
		_menu_interactive_nodes.append(btn_dev)

		# 管理员专属：天赋树编辑器（E5 天赋树可视化配置）
		var btn_talent := Button.new()
		btn_talent.name = "BtnTalentEditor"
		btn_talent.text = "天赋树编辑器（开发者）"
		btn_talent.position = Vector2(545, 743)
		btn_talent.size = Vector2(350, 40)
		btn_talent.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
		btn_talent.pressed.connect(_on_open_talent_editor)
		add_child(btn_talent)
		_menu_interactive_nodes.append(btn_talent)

		# 管理员专属：元素克制编辑器（事件-响应·元素克制可视化）
		var btn_element := Button.new()
		btn_element.name = "BtnElementEditor"
		btn_element.text = "元素克制编辑器（开发者）"
		btn_element.position = Vector2(545, 791)
		btn_element.size = Vector2(350, 40)
		btn_element.add_theme_color_override("font_color", Color(1.0, 0.75, 0.4))
		btn_element.pressed.connect(_on_open_element_editor)
		add_child(btn_element)
		_menu_interactive_nodes.append(btn_element)

		# 管理员模式下返回按钮再往下挪一点
		var btn_back_mode := Button.new()
		btn_back_mode.name = "BtnBackMode"
		btn_back_mode.text = "← 返回模式选择"
		btn_back_mode.position = Vector2(545, 845)
		btn_back_mode.size = Vector2(350, 40)
		btn_back_mode.add_theme_font_size_override("font_size", 16)
		btn_back_mode.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
		btn_back_mode.pressed.connect(_on_back_to_mode_selection)
		add_child(btn_back_mode)
		_menu_interactive_nodes.append(btn_back_mode)
	else:
		# 玩家模式返回按钮
		var btn_back_mode := Button.new()
		btn_back_mode.name = "BtnBackMode"
		btn_back_mode.text = "← 返回模式选择"
		btn_back_mode.position = Vector2(545, 700)
		btn_back_mode.size = Vector2(350, 45)
		btn_back_mode.add_theme_font_size_override("font_size", 16)
		btn_back_mode.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
		btn_back_mode.pressed.connect(_on_back_to_mode_selection)
		add_child(btn_back_mode)
		_menu_interactive_nodes.append(btn_back_mode)


# 隐藏主菜单交互节点（打开子界面时调用）
func _hide_menu_interactive_nodes() -> void:
	for node in _menu_interactive_nodes:
		if is_instance_valid(node):
			node.visible = false


# 恢复主菜单交互节点（关闭子界面时调用）
func _show_menu_interactive_nodes() -> void:
	for node in _menu_interactive_nodes:
		if is_instance_valid(node):
			node.visible = true


func _on_start_match() -> void:
	# 切换到备战场景（目前直接进入比赛）
	get_tree().change_scene_to_file("res://scenes/battle/battle_arena.tscn")


var char_ui: Control = null
# 联机大厅（工单01 S2；照 char_ui 先例实例化叠加，关闭时由大厅回调恢复按钮）
var _net_lobby: Control = null
# 2026-10-30 第3批：U1 面板实例（设置/教学）
var _settings_panel: Control = null
var _tutorial_overlay: Control = null


func _on_open_net_lobby() -> void:
	# 已打开且可见 → 不做任何事
	if _net_lobby and is_instance_valid(_net_lobby) and _net_lobby.visible:
		return

	# 已打开但失效 → 清理后重建
	if _net_lobby and is_instance_valid(_net_lobby):
		_net_lobby.queue_free()
		_net_lobby = null

	var NetLobbyClass = load("res://scripts/ui/net_lobby_ui.gd")
	_net_lobby = NetLobbyClass.new()
	add_child(_net_lobby)
	_hide_menu_interactive_nodes()


## 设置面板入口（2026-10-30 第3批：U1 面板进主流程）
## settings_panel.gd 已实现：三音量滑杆 + 画质/窗口下拉 + 键位占位行
##   signal setting_changed(key, value) / close_requested
##   持久化归实现窗口；本处只负责"开/关"与恢复菜单按钮
func _on_open_settings() -> void:
	if _settings_panel and is_instance_valid(_settings_panel) and _settings_panel.visible:
		return
	if _settings_panel and is_instance_valid(_settings_panel):
		_settings_panel.queue_free()
		_settings_panel = null
	var SettingsClass = load("res://scripts/ui/settings_panel.gd")
	if SettingsClass == null:
		push_warning("[MainMenu] settings_panel.gd 加载失败，跳过")
		return
	_settings_panel = SettingsClass.new()
	add_child(_settings_panel)
	_hide_menu_interactive_nodes()
	# 关闭信号 → 恢复菜单
	if _settings_panel.has_signal("close_requested"):
		_settings_panel.close_requested.connect(func() -> void:
			if _settings_panel and is_instance_valid(_settings_panel):
				_settings_panel.queue_free()
				_settings_panel = null
			_show_menu_interactive_nodes())
	# 打开动画（U0-6 转场 ≤300ms）
	if _settings_panel.has_method("open"):
		_settings_panel.open()


## 教学入口（溯源第一课）
## tutorial_overlay.gd 已实现：5 步数据驱动（data/ui/tutorial_steps.json）
##   signal tutorial_finished / start()
func _on_open_tutorial() -> void:
	if _tutorial_overlay and is_instance_valid(_tutorial_overlay) and _tutorial_overlay.visible:
		return
	if _tutorial_overlay and is_instance_valid(_tutorial_overlay):
		_tutorial_overlay.queue_free()
		_tutorial_overlay = null
	var TutClass = load("res://scripts/ui/tutorial_overlay.gd")
	if TutClass == null:
		push_warning("[MainMenu] tutorial_overlay.gd 加载失败，跳过")
		return
	_tutorial_overlay = TutClass.new()
	add_child(_tutorial_overlay)
	_hide_menu_interactive_nodes()
	if _tutorial_overlay.has_signal("tutorial_finished"):
		_tutorial_overlay.tutorial_finished.connect(func() -> void:
			if _tutorial_overlay and is_instance_valid(_tutorial_overlay):
				_tutorial_overlay.queue_free()
				_tutorial_overlay = null
			_show_menu_interactive_nodes())
	if _tutorial_overlay.has_method("start"):
		_tutorial_overlay.start()


func _on_open_characters() -> void:
	# 已打开且可见 → 不做任何事（角色系统有关闭按钮）
	if char_ui and is_instance_valid(char_ui) and char_ui.visible:
		return

	# 已打开但隐藏（不应发生，角色系统关闭时会 queue_free）→ 清理后重建
	if char_ui and is_instance_valid(char_ui):
		char_ui.queue_free()
		char_ui = null

	# 创建新的角色系统界面
	var CharacterSystemClass = load("res://scripts/ui/character_system.gd")
	char_ui = CharacterSystemClass.new()
	add_child(char_ui)

	# 隐藏主菜单按钮，避免鼠标穿透
	_hide_menu_interactive_nodes()

	# 关闭时恢复按钮并清理引用
	if char_ui.has_signal("closed"):
		char_ui.closed.connect(func() -> void:
			_show_menu_interactive_nodes()
			char_ui = null
		)


var spirit_ui: Control = null


func _on_open_spirits() -> void:
	# 已打开且可见 → 隐藏
	if spirit_ui and is_instance_valid(spirit_ui) and spirit_ui.visible:
		spirit_ui.visible = false
		return

	# 已打开但隐藏 → 显示并刷新数据
	if spirit_ui and is_instance_valid(spirit_ui):
		if spirit_ui.has_method("refresh_data"):
			spirit_ui.refresh_data()
		spirit_ui.visible = true
		return

	# 首次打开
	var script := load("res://scripts/systems/spirit_system/spirit_ui.gd")
	spirit_ui = Control.new()
	spirit_ui.name = "SpiritUI"
	spirit_ui.set_script(script)
	spirit_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(spirit_ui)

	# 关闭信号：隐藏面板
	if spirit_ui.has_signal("close_requested"):
		spirit_ui.close_requested.connect(func(): spirit_ui.visible = false)

	print("[Main] 元灵系统已打开")


var base_ui: Control = null


func _on_open_base() -> void:
	if base_ui and is_instance_valid(base_ui) and base_ui.visible:
		return
	
	if base_ui and is_instance_valid(base_ui):
		base_ui.queue_free()
		base_ui = null
	
	var BaseSystemClass = load("res://scripts/ui/base_system.gd")
	base_ui = BaseSystemClass.new()
	base_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(base_ui)
	
	_hide_menu_interactive_nodes()
	
	if base_ui.has_signal("closed"):
		base_ui.closed.connect(func() -> void:
			_show_menu_interactive_nodes()
			base_ui = null
		)


func _on_open_element_editor() -> void:
	var EditorClass = load("res://scripts/dev_tools/dev_element_counter_editor.gd")
	var editor: Control = EditorClass.new()
	editor.set_anchors_preset(Control.PRESET_FULL_RECT)
	editor.closed.connect(editor.queue_free)
	add_child(editor)
	print("[Main] 元素克制编辑器已打开")


func _on_open_talent_editor() -> void:
	var EditorClass = load("res://scripts/dev_tools/dev_talent_tree_editor.gd")
	var editor: Control = EditorClass.new()
	editor.set_anchors_preset(Control.PRESET_FULL_RECT)
	editor.closed.connect(editor.queue_free)
	add_child(editor)
	print("[Main] 天赋树编辑器已打开")


func _on_open_dev_settings() -> void:
	var DevSettingsClass = load("res://scripts/dev_tools/dev_settings_main.gd")
	var dev_panel: Control = DevSettingsClass.new()
	dev_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	dev_panel.closed.connect(dev_panel.queue_free)
	add_child(dev_panel)
	print("[Main] 快捷设置系统已打开")


func _on_toggle_reward() -> void:
	var current: bool = RewardSystem.reward_config.get("reward_enabled", false)
	RewardSystem.set_reward_enabled(not current)
	# 刷新菜单按钮显示
	_rebuild_reward_button()


func _rebuild_reward_button() -> void:
	var btn = get_node_or_null("BtnReward")
	if btn and is_instance_valid(btn):
		var reward_on: bool = RewardSystem.reward_config.get("reward_enabled", false)
		btn.text = "比赛奖励: %s" % ("已开启" if reward_on else "已关闭")
		btn.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3) if reward_on else Color(0.6, 0.6, 0.6))


func _on_open_trade() -> void:
	print("[Main] 交易 - 待实现")
