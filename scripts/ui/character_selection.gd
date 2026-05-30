extends Control
## 角色选择界面 - 用于替补球员时选择角色

signal character_selected(char_id: String)

var character_grid: GridContainer
var available_characters: Array[Dictionary] = []
var selected_char_id: String = ""


func _ready() -> void:
	_setup_ui()


func _setup_ui() -> void:
	size = Vector2(600, 400)
	position = Vector2(300, 200)
	
	var bg := ColorRect.new()
	bg.size = size
	bg.color = Color(0.2, 0.2, 0.3, 0.98)
	bg.z_index = -1
	add_child(bg)
	
	var title := Label.new()
	title.text = "选择角色"
	title.position = Vector2(250, 20)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color.WHITE)
	add_child(title)
	
	character_grid = GridContainer.new()
	character_grid.position = Vector2(50, 70)
	character_grid.size = Vector2(500, 280)
	character_grid.columns = 3
	add_child(character_grid)
	
	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.position = Vector2(250, 360)
	close_btn.size = Vector2(100, 30)
	close_btn.pressed.connect(_on_close)
	add_child(close_btn)


func load_characters(characters: Array[Dictionary]) -> void:
	"""加载可用角色"""
	available_characters = characters
	
	for child in character_grid.get_children():
		child.queue_free()
	
	for char_data in available_characters:
		var card := _create_character_card(char_data)
		character_grid.add_child(card)


func _create_character_card(char_data: Dictionary) -> Panel:
	"""创建角色卡片"""
	var card := Panel.new()
	card.size = Vector2(150, 120)
	
	var container := VBoxContainer.new()
	container.position = Vector2(10, 10)
	container.size = Vector2(130, 100)
	
	var name_label := Label.new()
	name_label.text = char_data.get("name", "未知")
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	container.add_child(name_label)
	
	var attr_text: String = "速度: %.1f\\n攻击: %.1f" % [char_data.get("speed", 100.0), char_data.get("attack", 100.0)]
	var attr_label := Label.new()
	attr_label.text = attr_text
	attr_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	container.add_child(attr_label)
	
	var select_btn := Button.new()
	select_btn.text = "选择"
	select_btn.size = Vector2(60, 25)
	select_btn.pressed.connect(_on_character_selected.bind(char_data.get("id", "")))
	container.add_child(select_btn)
	
	card.add_child(container)
	return card


func _on_character_selected(char_id: String) -> void:
	"""角色选择"""
	selected_char_id = char_id
	character_selected.emit(char_id)
	visible = false


func _on_close() -> void:
	"""关闭"""
	visible = false


func get_selected_character() -> String:
	"""获取选中的角色ID"""
	return selected_char_id
