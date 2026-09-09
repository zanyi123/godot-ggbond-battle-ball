extends Node

func _ready() -> void:
	print("Starting test...")
	var script = load("res://scripts/test/player_3d_test.gd")
	if script == null:
		print("SCRIPT FAILED TO LOAD")
	else:
		print("SCRIPT LOADED OK")
		print("Has PLAYER1_BODY_PATH: ", script.PLAYER1_BODY_PATH)
	get_tree().quit(0)
