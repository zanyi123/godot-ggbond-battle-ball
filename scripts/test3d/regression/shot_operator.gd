## 06 工单截图补档：非 headless 跑操作注入+操作中截图（AIM/POINT/TOGGLE 态）
## 沿用 e2e 的 stub 注入模式；每技在“操作中”状态截 1 张 → docs/img/
extends SceneTree

var _raw_backup: String = ""


func _initialize() -> void:
	_run()

func _run() -> void:
	for i in range(5):
		await process_frame
	var im_script: GDScript = load("res://scripts/battle/input_manager.gd")
	# 数据（备份在先）
	_raw_backup = FileAccess.get_file_as_string("res://data/spirits/skills.json")
	var skills: Array = DevDataSync.load_skills()
	var temp := {
		"shot_aim": {"tags": ["ball_carry_push"], "tag_params": {"ball_carry_push": {"pull_speed": 200.0, "max_duration": 3.0}}, "operator": "OP_AIM"},
		"shot_point": {"tags": ["field_zone_boost"], "tag_params": {"field_zone_boost": {"position": "0,0", "size": "180,180", "boost_multiplier": 1.4, "duration": 10.0}}, "operator": "OP_POINT"},
		"shot_steer": {"tags": ["ball_manual_steering"], "tag_params": {"ball_manual_steering": {"energy_per_sec": 4.0, "max_duration": 8.0}}, "operator": "OP_STEER"},
		"shot_toggle": {"tags": ["player_shield_obstacle"], "tag_params": {"player_shield_obstacle": {"shape": "circle", "radius": 35.0, "hp": 2.0, "uses": 2, "durability_mode": "uses", "follow_mode": "follow", "duration": 10.0}}, "operator": "OP_TOGGLE", "mode": "toggle"},
		"shot_midfly": {"tags": ["ball_recall"], "tag_params": {"ball_recall": {"max_times": 2}}, "operator": "OP_MIDFLY"},
	}
	var have := {"shot_aim": false, "shot_point": false, "shot_steer": false, "shot_toggle": false, "shot_midfly": false}
	for sid in have:
		for s in skills:
			if str(s.get("id", "")) == sid:
				have[sid] = true
	for sid in temp:
		if not have[sid]:
			var cfg: Dictionary = temp[sid]
			var entry := {"id": sid, "name": "t", "type": "active", "element": "雷火", "tags": cfg["tags"], "tag_params": cfg["tag_params"], "operator": cfg["operator"], "description": "t"}
			if cfg.has("mode"):
				entry["mode"] = cfg["mode"]
			skills.append(entry)
	DevDataSync.save_skills(skills)
	await process_frame

	# 装配（同 e2e stub）
	var im: Node = im_script.new()
	root.add_child(im)
	var caster: CharacterBody2D = load("res://scripts/battle/player.gd").new()
	caster.team = "a"
	caster.position = Vector2(0, 0)
	root.add_child(caster)
	im.set_controlled_player(caster)
	im.match_started = true
	var issm: Node = im.skill_state_manager
	var cpid: int = caster.get_instance_id()
	var ofb: Node3D = Node3D.new()
	ofb.set_script(load("res://scripts/battle3d/visual/operator_feedback_3d.gd"))
	ofb.name = "OperatorFeedback3D"
	root.add_child(ofb)
	await process_frame

	# 3D 背景垫（观感参考：地面网格+球位标记，简约）
	var bg3d := Node3D.new()
	root.add_child(bg3d)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1040, 680)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.16, 0.3, 0.2)
	ground.material_override = gm
	bg3d.add_child(ground)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 900, 420)
	cam.rotation_degrees = Vector3(-65, 0, 0)
	bg3d.add_child(cam)
	cam.current = true

	# ① AIM：激活→AIMING+预览→鼠移右侧→截图
	issm.setup_player_skills(cpid, ["shot_aim"] as Array[String])
	im._handle_skill_key_press(0)
	await process_frame
	im.update_aim_from_mouse(Vector2(260, -80))
	await process_frame
	await _shot("op_aim_aiming")

	# ② POINT：SELECTING+目标圈
	issm.setup_player_skills(cpid, ["shot_point"] as Array[String])
	im._handle_skill_key_press(0)
	await process_frame
	ofb.show_target_ring(Vector2(180, 60))
	await _shot("op_point_selecting")

	# ③ STEER：球手动态+方向注入
	issm.setup_player_skills(cpid, ["shot_steer"] as Array[String])
	im._handle_skill_key_press(0)
	await process_frame
	im._release_active_skill(cpid)
	await process_frame
	im.update_aim_from_mouse(Vector2(300, -120))
	await _shot("op_steer_active")

	# ④ TOGGLE：盾开(form1)
	issm.setup_player_skills(cpid, ["shot_toggle"] as Array[String])
	var trig: Node = load("res://scripts/systems/spirit_system/spirit_skill_trigger.gd").new()
	root.add_child(trig)
	var roster: Array[Node] = [caster]
	trig.players = roster
	var om: Node = load("res://scripts/battle/obstacle_manager.gd").new()
	root.add_child(om)
	caster.spirit_energy = 100.0
	await process_frame
	var jd: Dictionary = {}
	for s2 in DevDataSync.load_skills():
		if str(s2.get("id", "")) == "shot_toggle":
			jd = s2
	trig._toggle_skill(jd, cpid, "shot_toggle")
	await process_frame
	await _shot("op_toggle_shield_on")

	# ⑤ MIDFLY：飞行干预态（球在飞标志）
	issm.setup_player_skills(cpid, ["shot_midfly"] as Array[String])
	im._handle_skill_key_press(0)
	await process_frame
	await _shot("op_midfly_armed")

	# 还原
	var wf := FileAccess.open("res://data/spirits/skills.json", FileAccess.WRITE)
	wf.store_string(_raw_backup)
	wf.close()
	print("[Shot] 5 技截图完成，数据已还原")
	quit(0)


func _shot(name: String) -> void:
	for i in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png("res://docs/img/%s.png" % name)
	print("[Shot] docs/img/%s.png" % name)
