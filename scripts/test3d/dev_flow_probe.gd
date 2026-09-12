## dev 模式流程探针：随机两队 → 开赛 → HUD/球员/3D代理 三方对照
extends Node3D

func _ready() -> void:
	var arena_scene: PackedScene = load("res://scenes/battle/battle_arena.tscn")
	var arena = arena_scene.instantiate()
	add_child(arena)
	await get_tree().create_timer(1.5).timeout
	var mgr = arena
	if not mgr.dev_prep_mode:
		print("[DevProbe][FAIL] dev_prep_mode 未开启（需 --dev-prep 命令行）")
		get_tree().quit(1)
		return
	# 构造随机两队（固定可辨组合：A=002/004/007，B=001/005/006）
	var a_ids := ["char_002", "char_004", "char_007"]
	var b_ids := ["char_001", "char_005", "char_006"]
	var a_data: Array[Dictionary] = []
	var b_data: Array[Dictionary] = []
	for cid in a_ids:
		a_data.append({"char_id": cid, "spirit_id": "", "equipment": {"glove": "", "jersey": "", "shoes": ""}, "food": ""})
	for cid in b_ids:
		b_data.append({"char_id": cid, "spirit_id": "", "equipment": {"glove": "", "jersey": "", "shoes": ""}, "food": ""})
	mgr._on_dev_prep_match_started(a_data, b_data, 0, "a")
	await get_tree().create_timer(1.0).timeout  # 等 bridge 补建 + HUD 绑定
	# 三方对照
	var bridge = mgr.get_node_or_null("BattleArena3DBridge")
	var hud = mgr.ui_layer.get_node_or_null("HUD") if mgr.ui_layer else null
	var pass_count := 0
	var fail_count := 0
	for i in range(3):
		var p = mgr.team_a_players[i]
		var pid := str(p.character_id)
		# HUD 球员栏名字
		var hud_name := ""
		if hud != null and i < hud.player_name_labels.size():
			hud_name = str(hud.player_name_labels[i].text)
		var expect_name := str(p.char_data.get("name", "?"))
		var ok_hud: bool = hud_name == expect_name
		# 3D 代理
		var proxy_cid := "无"
		if bridge != null and bridge._player_proxies.has(p):
			proxy_cid = str(bridge._player_proxies[p].char_id)
		var ok_proxy: bool = proxy_cid == pid
		if ok_hud and ok_proxy: pass_count += 1
		else: fail_count += 1
		print("[DevProbe][%s] A%d 实际=%s(%s) HUD栏=%s(%s) 代理=%s" % [
			"PASS" if ok_hud and ok_proxy else "FAIL", i + 1, pid, expect_name, hud_name, "对" if ok_hud else "错", proxy_cid])
	for i in range(3):
		var p = mgr.team_b_players[i]
		var proxy_cid := "无"
		if bridge != null and bridge._player_proxies.has(p):
			proxy_cid = str(bridge._player_proxies[p].char_id)
		var ok_proxy: bool = proxy_cid == str(p.character_id)
		if ok_proxy: pass_count += 1
		else: fail_count += 1
		print("[DevProbe][%s] B%d 实际=%s 代理=%s" % ["PASS" if ok_proxy else "FAIL", i + 1, str(p.character_id), proxy_cid])
	# 带窗口：3D+HUD 同框截图（对照模型与信息栏）
	var img := get_viewport().get_texture().get_image()
	if img != null:
		DirAccess.open("res://docs").make_dir_recursive("img/3d_p2")
		img.save_png("res://docs/img/3d_p2/dev_flow.png")
		print("[DevProbe] 📷 dev_flow.png 已存（3D+HUD 同框对照）")
	print("[DevProbe] RESULT: %s (%d/%d)" % ["PASS" if fail_count == 0 else "FAIL", pass_count, pass_count + fail_count])
	get_tree().quit(0 if fail_count == 0 else 1)
