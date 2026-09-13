## 模型身份对比探针：并排加载 p2/p3/p4/p5 的 idle FBX+各自 PBR 贴图，截图对比外观
extends Node3D

const CFG = preload("res://scripts/battle3d/battle3d_const.gd")

func _ready() -> void:
	var bg := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.15, 0.15, 0.18)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 1.0
	bg.environment = env
	add_child(bg)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	add_child(sun)
	var sentry := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 30
	sph.height = 60
	sentry.mesh = sph
	sentry.position = Vector3(0, 30, 200)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(1, 0, 0)
	smat.emission_enabled = true
	smat.emission = Color(1, 0, 0)
	smat.emission_energy_multiplier = 2.0
	sentry.material_override = smat
	add_child(sentry)

	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.position = Vector3(0, 260, 780)
	cam.look_at(Vector3(0, 70, 0), Vector3.UP)

	# 四个建模编号并排：p2(菲菲) p3(小呆呆?) p4(波比?) p5(超人强?)
	var cases := [
		{"n": 1, "label": "player1(Idle)"},
		{"n": 2, "label": "player2(StandingIdle)"},
		{"n": 3, "label": "player3(Block)"},
		{"n": 4, "label": "player4(Block)"},
		{"n": 5, "label": "player5(Block)"},
	]
	var x := -360.0
	for c in cases:
		var fbx := "res://建模素材库/3D模型素材/player%d动作/Standing Block Idle.fbx" % c["n"]
		if c["n"] == 1:
			fbx = "res://建模素材库/3D模型素材/player1动作/Idle.fbx"
		if c["n"] == 2:
			fbx = "res://建模素材库/3D模型素材/player2动作/Standing Idle.fbx"
		var sc: PackedScene = load(fbx)
		if sc == null:
			print("[Ident][FAIL] 无法加载 ", fbx)
			x += 240.0
			continue
		var inst := sc.instantiate()
		var holder := Node3D.new()
		holder.position = Vector3(x, 0, 0)
		holder.add_child(inst)
		# 贴 PBR（同 PlayerProxy3D 逻辑）
		var tex: Texture2D = load("res://建模素材库/3D模型素材/player%d_base_texture_pbr_20250901.png" % c["n"])
		var nrm: Texture2D = load("res://建模素材库/3D模型素材/player%d_base_texture_pbr_20250901_normal.png" % c["n"])
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var m3 := mi as MeshInstance3D
			if m3.mesh == null:
				continue
			for s in range(m3.mesh.get_surface_count()):
				var mat := StandardMaterial3D.new()
				if tex:
					mat.albedo_texture = tex
				if nrm:
					mat.normal_enabled = true
					mat.normal_map = nrm
				mat.metallic = 0.0
				mat.roughness = 0.6
				m3.set_surface_override_material(s, mat)
		# 名字标签
		for mi2 in inst.find_children("*", "MeshInstance3D", true, false):
			var m2 := mi2 as MeshInstance3D
			if m2.mesh != null:
				var ab2: AABB = m2.mesh.get_aabb()
				print("[Ident] player%d 原始AABB高=%.6f" % [c["n"], ab2.size.y])
		var lb := Label3D.new()
		lb.text = c["label"]
		lb.position = Vector3(0, 140, 0)
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.modulate = Color(1, 0.9, 0.3)
		lb.font_size = 60
		holder.add_child(lb)
		add_child(holder)
		print("[Ident] player%d 已摆放" % c["n"])
		x += 240.0

	await get_tree().create_timer(1.0).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	# 诊断
	var holders := []
	for c in get_children():
		if c is Node3D and c.name.begins_with("Snapshot") == false and c != cam:
			for cc in c.get_children():
				pass
	var meshes := find_children("*", "MeshInstance3D", true, false)
	print("[Ident] 场景 MeshInstance 总数=", meshes.size(), " 相机=", cam.position, " 朝向目标=(0,70,0)")
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh != null:
			var ab: AABB = mi.global_transform * mi.mesh.get_aabb()
			print("[Ident] AABB 世界=", str(ab), " size=", str(ab.size))
	var img := get_viewport().get_texture().get_image()
	if img:
		DirAccess.open("res://docs").make_dir_recursive("img/3d_p2")
		img.save_png("res://docs/img/3d_p2/model_identity.png")
		print("[Ident] 📷 model_identity.png 已存（p2/p3/p4/p5 并排，看金发菲菲有几个）")
	get_tree().quit()
