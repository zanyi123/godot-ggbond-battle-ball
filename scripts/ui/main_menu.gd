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

	# 背景
	var bg := ColorRect.new()
	bg.name = "BG"
	bg.size = Vector2(1440, 900)
	bg.color = Color(0.1, 0.1, 0.2)
	add_child(bg)

	# 标题
	var title := Label.new()
	title.name = "Title"
	title.text = "猪猪侠之决竞球"
	title.position = Vector2(470, 120)
	title.size = Vector2(500, 70)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color.YELLOW)
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
func _show_mode_selection() -> void:
	_clear_mode_selection()

	var subtitle := Label.new()
	subtitle.text = "请选择模式"
	subtitle.position = Vector2(470, 200)
	subtitle.size = Vector2(500, 40)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 22)
	subtitle.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	add_child(subtitle)
	_mode_selection_nodes.append(subtitle)

	# 玩家模式按钮
	var btn_player := Button.new()
	btn_player.text = "玩家模式"
	btn_player.position = Vector2(545, 320)
	btn_player.size = Vector2(350, 65)
	btn_player.add_theme_font_size_override("font_size", 22)
	btn_player.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	btn_player.pressed.connect(_on_enter_player_mode)
	add_child(btn_player)
	_mode_selection_nodes.append(btn_player)

	var player_desc := Label.new()
	player_desc.text = "正常游戏体验，不含开发者工具"
	player_desc.position = Vector2(545, 395)
	player_desc.size = Vector2(350, 25)
	player_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_desc.add_theme_font_size_override("font_size", 13)
	player_desc.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	add_child(player_desc)
	_mode_selection_nodes.append(player_desc)

	# 管理员模式按钮
	var btn_admin := Button.new()
	btn_admin.text = "管理员模式"
	btn_admin.position = Vector2(545, 460)
	btn_admin.size = Vector2(350, 65)
	btn_admin.add_theme_font_size_override("font_size", 22)
	btn_admin.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
	btn_admin.pressed.connect(_on_enter_admin_mode)
	add_child(btn_admin)
	_mode_selection_nodes.append(btn_admin)

	var admin_desc := Label.new()
	admin_desc.text = "开发者工具 + 数据管理 + 物资发放（测试用）"
	admin_desc.position = Vector2(545, 535)
	admin_desc.size = Vector2(350, 25)
	admin_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	admin_desc.add_theme_font_size_override("font_size", 13)
	admin_desc.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	add_child(admin_desc)
	_mode_selection_nodes.append(admin_desc)


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
	var btn_start := Button.new()
	btn_start.name = "BtnStart"
	btn_start.text = "开始比赛"
	btn_start.position = Vector2(545, 260)
	btn_start.size = Vector2(350, 55)
	btn_start.pressed.connect(_on_start_match)
	add_child(btn_start)
	_menu_interactive_nodes.append(btn_start)

	# 角色系统按钮
	var btn_chars := Button.new()
	btn_chars.name = "BtnCharacters"
	btn_chars.text = "角色系统"
	btn_chars.position = Vector2(545, 335)
	btn_chars.size = Vector2(350, 55)
	btn_chars.pressed.connect(_on_open_characters)
	add_child(btn_chars)
	_menu_interactive_nodes.append(btn_chars)

	# 元灵系统按钮
	var btn_spirits := Button.new()
	btn_spirits.name = "BtnSpirits"
	btn_spirits.text = "元灵系统"
	btn_spirits.position = Vector2(545, 410)
	btn_spirits.size = Vector2(350, 55)
	btn_spirits.pressed.connect(_on_open_spirits)
	add_child(btn_spirits)
	_menu_interactive_nodes.append(btn_spirits)

	# 基地按钮
	var btn_base := Button.new()
	btn_base.name = "BtnBase"
	btn_base.text = "基地"
	btn_base.position = Vector2(545, 485)
	btn_base.size = Vector2(350, 55)
	btn_base.pressed.connect(_on_open_base)
	add_child(btn_base)
	_menu_interactive_nodes.append(btn_base)

	# 交易按钮
	var btn_trade := Button.new()
	btn_trade.name = "BtnTrade"
	btn_trade.text = "交易"
	btn_trade.position = Vector2(545, 560)
	btn_trade.size = Vector2(350, 55)
	btn_trade.pressed.connect(_on_open_trade)
	add_child(btn_trade)
	_menu_interactive_nodes.append(btn_trade)

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
		btn_dev.position = Vector2(545, 700)
		btn_dev.size = Vector2(350, 55)
		btn_dev.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
		btn_dev.pressed.connect(_on_open_dev_settings)
		add_child(btn_dev)
		_menu_interactive_nodes.append(btn_dev)

		# 管理员模式下返回按钮再往下挪一点
		var btn_back_mode := Button.new()
		btn_back_mode.name = "BtnBackMode"
		btn_back_mode.text = "← 返回模式选择"
		btn_back_mode.position = Vector2(545, 775)
		btn_back_mode.size = Vector2(350, 45)
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
