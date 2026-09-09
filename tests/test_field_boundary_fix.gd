extends Node3D

var passed: int = 0
var failed: int = 0
var failures: Array[String] = []
var _field_zone: Node3D


func _ready() -> void:
	print("=== Field Boundary Fix Test Suite ===")
	_ensure_init()
	test_inner_normal()
	test_outer_main()
	test_outer_arms()
	test_penalized()
	test_team_b()
	test_transfer_destination()
	test_midline_violation()
	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	if failed > 0:
		print("FAILURES:")
		for f in failures:
			print("  - %s" % f)
	get_tree().quit()


func _ensure_init() -> void:
	_field_zone = Node3D.new()
	_field_zone.set_script(load("res://scripts/test/field_zone_3d.gd"))


func _make_player():
	var p = CharacterBody3D.new()
	add_child(p)
	return p


func _check(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		passed += 1
		print("  [PASS] %s" % name)
	else:
		failed += 1
		failures.append(name)
		print("  [FAIL] %s  %s" % [name, detail])


func test_inner_normal() -> void:
	print("\n--- group1: inner field normal ---")
	var p = _make_player()
	_field_zone.register_player(p, "a")
	p.global_position = Vector3(-200, 0, 0)
	_check("1a: team A inner(-200,0) no violation", _field_zone.check_field_boundary_violation(p) == _field_zone.ViolationType.NONE)
	p.global_position = Vector3(-380, 0, 0)
	_check("1b: team A inner left boundary(-380,0)", _field_zone.check_field_boundary_violation(p) == _field_zone.ViolationType.NONE)
	p.global_position = Vector3(380, 0, 0)
	_check("1c: team A inner right boundary(380,0)", _field_zone.check_field_boundary_violation(p) == _field_zone.ViolationType.NONE)
	p.global_position = Vector3(-200, 0, 250)
	_check("1d: team A inner top(-200,250)", _field_zone.check_field_boundary_violation(p) == _field_zone.ViolationType.NONE)
	p.queue_free()


func test_outer_main() -> void:
	print("\n--- group2: outer main area ---")
	var p = _make_player()
	_field_zone.register_player(p, "a")
	p.global_position = Vector3(-400, 0, 0)
	_check("2a: team A own left outer(-400,0) VIOLATION", _field_zone.check_field_boundary_violation(p) == _field_zone.ViolationType.CROSS_FIELD_BOUNDARY)
	p.global_position = Vector3(400, 0, 0)
	_check("2b: team A opponent right outer(400,0) NO violation", _field_zone.check_field_boundary_violation(p) == _field_zone.ViolationType.NONE)
	p.global_position = Vector3(-500, 0, -300)
	_check("2c: team A own left outer deep(-500,-300) VIOLATION", _field_zone.check_field_boundary_violation(p) == _field_zone.ViolationType.CROSS_FIELD_BOUNDARY)
	p.global_position = Vector3(500, 0, 300)
	_check("2d: team A opponent right outer deep(500,300) NO violation", _field_zone.check_field_boundary_violation(p) == _field_zone.ViolationType.NONE)
	p.queue_free()


func test_outer_arms() -> void:
	print("\n--- group3: outer arms (team-specific) ---")
	var p = _make_player()
	_field_zone.register_player(p, "a")
	p.global_position = Vector3(-300, 0, 300)
	_check("3a: team A own bottom-left arm(-300,300) VIOLATION", _field_zone.check_field_boundary_violation(p) == _field_zone.ViolationType.CROSS_FIELD_BOUNDARY)
	p.global_position = Vector3(300, 0, 300)
	_check("3b: team A opponent bottom-right arm(300,300) NO violation", _field_zone.check_field_boundary_violation(p) == _field_zone.ViolationType.NONE)
	p.global_position = Vector3(-300, 0, -300)
	_check("3c: team A own top-left arm(-300,-300) VIOLATION", _field_zone.check_field_boundary_violation(p) == _field_zone.ViolationType.CROSS_FIELD_BOUNDARY)
	p.global_position = Vector3(300, 0, -300)
	_check("3d: team A opponent top-right arm(300,-300) NO violation", _field_zone.check_field_boundary_violation(p) == _field_zone.ViolationType.NONE)
	p.queue_free()


func test_penalized() -> void:
	print("\n--- group4: penalized exemption ---")
	var p = _make_player()
	_field_zone.register_player(p, "a")
	_field_zone.set_player_penalized(p, true)
	p.global_position = Vector3(400, 0, 0)
	_check("4a: penalized A in opponent outer no violation", _field_zone.check_field_boundary_violation(p) == _field_zone.ViolationType.NONE)
	p.global_position = Vector3(-400, 0, 0)
	_check("4b: penalized A in own outer no violation", _field_zone.check_field_boundary_violation(p) == _field_zone.ViolationType.NONE)
	p.global_position = Vector3(300, 0, 300)
	_check("4c: penalized A in opponent arm no violation", _field_zone.check_field_boundary_violation(p) == _field_zone.ViolationType.NONE)
	p.queue_free()


func test_team_b() -> void:
	print("\n--- group5: team B symmetric ---")
	var p = _make_player()
	_field_zone.register_player(p, "b")
	p.global_position = Vector3(200, 0, 0)
	_check("5a: team B inner(200,0) no violation", _field_zone.check_field_boundary_violation(p) == _field_zone.ViolationType.NONE)
	p.global_position = Vector3(-400, 0, 0)
	_check("5b: team B opponent left outer(-400,0) NO violation", _field_zone.check_field_boundary_violation(p) == _field_zone.ViolationType.NONE)
	p.global_position = Vector3(400, 0, 0)
	_check("5c: team B own right outer(400,0) VIOLATION", _field_zone.check_field_boundary_violation(p) == _field_zone.ViolationType.CROSS_FIELD_BOUNDARY)
	p.global_position = Vector3(-300, 0, 300)
	_check("5d: team B opponent bottom-left arm(-300,300) NO violation", _field_zone.check_field_boundary_violation(p) == _field_zone.ViolationType.NONE)
	p.global_position = Vector3(300, 0, -300)
	_check("5e: team B own top-right arm(300,-300) VIOLATION", _field_zone.check_field_boundary_violation(p) == _field_zone.ViolationType.CROSS_FIELD_BOUNDARY)
	p.queue_free()


func test_transfer_destination() -> void:
	print("\n--- group6: transfer destination (opponent outer) ---")
	var p = _make_player()
	_field_zone.register_player(p, "a")
	var right_center = _field_zone.get_right_outer_center()
	print("  right outer center: %s" % right_center)
	_check("team A transfers to opponent right outer (x>0)", right_center.x > 0)
	_check("right center x~445", abs(right_center.x - 445.0) < 1.0)
	_check("right center z~0", abs(right_center.z) < 1.0)
	var p2 = _make_player()
	_field_zone.register_player(p2, "b")
	var left_center = _field_zone.get_left_outer_center()
	_check("team B transfers to opponent left outer (x<0)", left_center.x < 0)
	_check("left center x~-445", abs(left_center.x - (-445.0)) < 1.0)
	p.queue_free()
	p2.queue_free()


func test_midline_violation() -> void:
	print("\n--- group7: midline violation ---")
	var p = _make_player()
	_field_zone.register_player(p, "a")
	p.global_position = Vector3(100, 0, 0)
	var result_a = _field_zone.check_midline_violation(p)
	_check("team A cross midline(x=100) VIOLATION", result_a == _field_zone.ViolationType.CROSS_MIDLINE)
	p.global_position = Vector3(-100, 0, 0)
	var result_a2 = _field_zone.check_midline_violation(p)
	_check("team A own side(x=-100) no violation", result_a2 == _field_zone.ViolationType.NONE)
	var p2 = _make_player()
	_field_zone.register_player(p2, "b")
	p2.global_position = Vector3(-100, 0, 0)
	var result_b = _field_zone.check_midline_violation(p2)
	_check("team B cross midline(x=-100) VIOLATION", result_b == _field_zone.ViolationType.CROSS_MIDLINE)
	p2.global_position = Vector3(100, 0, 0)
	var result_b2 = _field_zone.check_midline_violation(p2)
	_check("team B own side(x=100) no violation", result_b2 == _field_zone.ViolationType.NONE)
	p.queue_free()
	p2.queue_free()
