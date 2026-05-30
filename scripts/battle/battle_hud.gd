extends Control
## 比赛HUD - 显示在最下方的球员栏和比赛信息

# HUD布局（从下到上）
# [球员栏1] [球员栏2] [球员栏3]    [计时器] [比分]
# 每个球员栏：技能图标x3 | 体力条 | 元灵能量条 | 头像

var player_panels: Array[Control] = []
var timer_label: Label
var score_label: Label


func _ready() -> void:
	# 设置HUD占满屏幕
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = Vector2(1440, 810)
	
	_create_score_panel()
	_create_player_panels()


func _create_score_panel() -> void:
	"""顶部计分板和计时器"""
	# 背景条
	var top_bar := ColorRect.new()
	top_bar.size = Vector2(1440, 45)
	top_bar.color = Color(0, 0, 0, 0.7)
	add_child(top_bar)
	
	# 比分
	score_label = Label.new()
	score_label.text = "队A 0 : 0 队B"
	score_label.position = Vector2(620, 7)
	score_label.size = Vector2(200, 32)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.add_theme_color_override("font_color", Color.WHITE)
	add_child(score_label)
	
	# 计时器
	timer_label = Label.new()
	timer_label.text = "05:00"
	timer_label.position = Vector2(50, 7)
	timer_label.size = Vector2(120, 32)
	timer_label.add_theme_color_override("font_color", Color.YELLOW)
	add_child(timer_label)
	
	# 连接信号
	if GameManager:
		GameManager.match_time_updated.connect(_on_time_updated)
		GameManager.score_updated.connect(_on_score_updated)


func _create_player_panels() -> void:
	"""底部三个球员面板"""
	var panel_width: float = 380.0
	var panel_height: float = 90.0
	var start_x: float = (1440.0 - panel_width * 3 - 20) / 2.0
	var start_y: float = 810.0 - panel_height - 12.0
	
	for i in range(3):
		var panel := _create_single_panel(i, Vector2(start_x + i * (panel_width + 10), start_y), panel_width, panel_height)
		player_panels.append(panel)
		add_child(panel)


func _create_single_panel(index: int, pos: Vector2, width: float, height: float) -> Panel:
	"""创建单个球员面板"""
	var panel := Panel.new()
	panel.position = pos
	panel.size = Vector2(width, height)
	
	# 背景
	var bg := ColorRect.new()
	bg.size = Vector2(width, height)
	bg.color = Color(0.1, 0.1, 0.3, 0.8)
	panel.add_child(bg)
	
	# 球员头像区域（左侧）
	var avatar_box := ColorRect.new()
	avatar_box.size = Vector2(50, 50)
	avatar_box.position = Vector2(10, 15)
	avatar_box.color = Color.BLUE
	panel.add_child(avatar_box)
	
	# 编号
	var num_label := Label.new()
	num_label.text = str(index + 1)
	num_label.position = Vector2(25, 25)
	num_label.add_theme_color_override("font_color", Color.WHITE)
	panel.add_child(num_label)
	
	# 体力条
	var stamina := ProgressBar.new()
	stamina.position = Vector2(70, 15)
	stamina.size = Vector2(150, 12)
	stamina.max_value = 100
	stamina.value = 100
	stamina.show_percentage = false
	panel.add_child(stamina)
	
	# 元灵能量条
	var energy := ProgressBar.new()
	energy.position = Vector2(70, 32)
	energy.size = Vector2(150, 8)
	energy.max_value = 100
	energy.value = 0
	energy.show_percentage = false
	panel.add_child(energy)
	
	# 技能图标占位 x3
	for s in range(3):
		var skill_box := ColorRect.new()
		skill_box.size = Vector2(30, 30)
		skill_box.position = Vector2(70 + s * 35, 45)
		skill_box.color = Color(0.3, 0.3, 0.3)
		panel.add_child(skill_box)
		
		var skill_num := Label.new()
		skill_num.text = str(s + 4)  # 快捷键 4,5,6
		skill_num.position = Vector2(80 + s * 35, 50)
		skill_num.add_theme_color_override("font_color", Color.WHITE)
		panel.add_child(skill_num)
	
	# 快捷键提示
	var key_label := Label.new()
	key_label.text = "[%d]" % (index + 1)
	key_label.position = Vector2(10, height - 20)
	key_label.add_theme_font_size_override("font_size", 12)
	key_label.add_theme_color_override("font_color", Color.YELLOW)
	panel.add_child(key_label)
	
	return panel


func _on_time_updated(time: float) -> void:
	var total_seconds: int = int(time)
	var minutes: int = total_seconds / 60
	var seconds: int = total_seconds % 60
	timer_label.text = "%02d:%02d" % [minutes, seconds]


func _on_score_updated(team: String, new_score: int) -> void:
	score_label.text = "队A %d : %d 队B" % [GameManager.score_team_a, GameManager.score_team_b]
