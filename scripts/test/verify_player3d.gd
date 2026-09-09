extends Node

func _ready() -> void:
	print("=== Syntax check for player_3d_test.gd ===")
	
	var script := load("res://scripts/test/player_3d_test.gd")
	if script == null:
		print("FAIL: Cannot load script")
		return
	print("OK: Script loaded successfully")
	
	# Check key constants
	var p: String = script.PLAYER1_BODY_PATH
	print("PLAYER1_BODY_PATH = ", p)
	
	# Check if FBX exists
	var fb_exists = ResourceLoader.exists(p)
	print("Body resource exists: ", fb_exists)
	
	# Check textures
	var body_dir: String = p.get_base_dir()
	var dir_scan := DirAccess.open(body_dir)
	var png_count := 0
	var jpg_count := 0
	if dir_scan != null:
		dir_scan.list_dir_begin()
		var fn: String = dir_scan.get_next()
		while fn != "":
			if not dir_scan.current_is_dir():
				var lower_fn: String = fn.to_lower()
				if lower_fn.ends_with(".png"):
					png_count += 1
					print("  PNG: ", fn)
				elif lower_fn.ends_with(".jpg") or lower_fn.ends_with(".jpeg"):
					jpg_count += 1
					print("  JPG: ", fn)
			fn = dir_scan.get_next()
		dir_scan.list_dir_end()
	print("Total PNG: ", png_count)
	print("Total JPG: ", jpg_count)
	
	print("=== All checks done ===")
	get_tree().quit(0)
